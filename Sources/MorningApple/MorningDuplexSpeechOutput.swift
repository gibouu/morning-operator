import AVFAudio
import Foundation

/// Synthesis completion is not playback completion. A canceled/replaced chunk can
/// never complete a newer narration through a late player or synthesis callback.
struct DuplexSpeechPlaybackLedger {
    private(set) var id: UUID?
    private(set) var pending = Set<Int>()
    private(set) var hasAudio = false
    private var synthesisEnded = false
    private var scheduled = Set<Int>()

    mutating func begin(_ id: UUID) {
        self.id = id; pending.removeAll(); scheduled.removeAll(); hasAudio = false; synthesisEnded = false
    }
    mutating func scheduled(_ sequence: Int, id: UUID) -> Bool {
        guard self.id == id, !synthesisEnded, scheduled.insert(sequence).inserted else { return false }
        pending.insert(sequence)
        hasAudio = true
        return true
    }
    mutating func synthesized(id: UUID) -> Bool {
        guard self.id == id else { return false }
        synthesisEnded = true
        return claimCompletion()
    }
    mutating func played(_ sequence: Int, id: UUID) -> Bool {
        guard self.id == id, pending.remove(sequence) != nil else { return false }
        return claimCompletion()
    }
    mutating func cancel() { id = nil; pending.removeAll(); scheduled.removeAll(); synthesisEnded = false; hasAudio = false }
    private mutating func claimCompletion() -> Bool {
        guard hasAudio, synthesisEnded, pending.isEmpty, id != nil else { return false }
        id = nil
        return true
    }
}

/// PCM output enters the very engine that supplies voice-processed microphone
/// input, giving the voice-processing I/O its far-end signal for echo cancellation.
@MainActor
final class MorningDuplexSpeechOutput {
    private let engine: AVAudioEngine
    private let player = AVAudioPlayerNode()
    private let synthesizer = AVSpeechSynthesizer()
    private var format: AVAudioFormat?
    private var programID: UUID?
    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var ledger = DuplexSpeechPlaybackLedger()
    private var nextSequence = 0
    private var packets: [Int: DuplexSpeechPacket] = [:]
    private var scheduledBytes: [Int: Int] = [:]
    private var isPaused = false
    private var onStarted: (@MainActor () -> Void)?
    private static let maximumQueuedBytes = 16 * 1_024 * 1_024

    init(engine: AVAudioEngine) {
        self.engine = engine
        engine.attach(player)
    }

    func play(_ text: String, voice: AVSpeechSynthesisVoice,
              onStarted: @escaping @MainActor () -> Void,
              completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        cancel()
        let id = UUID()
        programID = id; self.onStarted = onStarted
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Exact chunks are synthesized sequentially and drained before the
                // next one, so a long private reading cannot queue unbounded PCM.
                let chunks = try LearningTextChunker.split(text, maximumCharacters: 200, maximumUTF8Bytes: 800)
                for chunk in chunks where !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try Task.checkCancellation()
                    guard programID == id else { throw CancellationError() }
                    try await playChunk(chunk, voice: voice)
                }
                guard programID == id else { return }
                programID = nil; task = nil; self.onStarted = nil
                completion(.success(()))
            } catch {
                guard programID == id else { return }
                cancel()
                completion(.failure(error))
            }
        }
    }

    func pause() -> Bool {
        guard programID != nil else { return false }
        isPaused = true; player.pause()
        return true
    }

    func resume() -> Bool {
        guard programID != nil, engine.isRunning else { return false }
        isPaused = false
        if !scheduledBytes.isEmpty { player.play() }
        return true
    }

    func cancel() {
        programID = nil; task?.cancel(); task = nil; ledger.cancel()
        packets.removeAll(); scheduledBytes.removeAll(); onStarted = nil
        let waiting = continuation; continuation = nil
        player.stop(); synthesizer.stopSpeaking(at: .immediate)
        isPaused = false
        waiting?.resume(throwing: CancellationError())
    }

    func detach() {
        cancel()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
    }

    private func playChunk(_ text: String, voice: AVSpeechSynthesisVoice) async throws {
        let id = UUID()
        ledger.begin(id); nextSequence = 0; packets.removeAll(); scheduledBytes.removeAll()
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice; utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            let ingress = DuplexSpeechIngress()
            let receiveBuffer: @Sendable (AVAudioBuffer) -> Void = { [weak self] buffer in
                let packet = ingress.copy(buffer)
                Task { @MainActor [weak self] in self?.receive(packet, id: id) }
            }
            synthesizer.write(utterance, toBufferCallback: receiveBuffer)
        }
    }

    private func receive(_ packet: DuplexSpeechPacket, id: UUID) {
        guard ledger.id == id, programID != nil else { return }
        guard packet.isValid, packets[packet.sequence] == nil, packet.sequence >= nextSequence else {
            failChunk(); return
        }
        packets[packet.sequence] = packet
        while let packet = packets.removeValue(forKey: nextSequence) {
            nextSequence += 1
            guard let buffer = packet.buffer else {
                if ledger.synthesized(id: id) { finishChunk() }
                else if !ledger.hasAudio { failChunk() }
                return
            }
            guard engine.isRunning,
                  scheduledBytes.values.reduce(0, +) + packet.byteCount <= Self.maximumQueuedBytes else {
                failChunk(); return
            }
            if format?.isEqual(buffer.format) != true {
                guard scheduledBytes.isEmpty else { failChunk(); return }
                engine.disconnectNodeOutput(player)
                engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
                format = buffer.format
            }
            guard ledger.scheduled(packet.sequence, id: id) else { failChunk(); return }
            scheduledBytes[packet.sequence] = packet.byteCount
            let sequence = packet.sequence
            let playedBuffer: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
                Task { @MainActor [weak self] in self?.played(sequence, id: id) }
            }
            player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: playedBuffer)
            if !isPaused { player.play() }
            let started = onStarted; onStarted = nil; started?()
        }
    }

    private func played(_ sequence: Int, id: UUID) {
        guard ledger.id == id else { return }
        scheduledBytes.removeValue(forKey: sequence)
        if ledger.played(sequence, id: id) { finishChunk() }
    }

    private func finishChunk() {
        let waiting = continuation; continuation = nil
        player.stop(); packets.removeAll(); scheduledBytes.removeAll()
        waiting?.resume()
    }

    private func failChunk() {
        ledger.cancel(); packets.removeAll(); scheduledBytes.removeAll()
        let waiting = continuation; continuation = nil
        player.stop(); synthesizer.stopSpeaking(at: .immediate)
        waiting?.resume(throwing: SpeechPlaybackError.audioUnavailable("Duplex speech output could not finish safely."))
    }
}

private struct DuplexSpeechPacket: @unchecked Sendable {
    let sequence: Int
    let buffer: AVAudioPCMBuffer?
    let byteCount: Int
    let isValid: Bool
}

/// Owns copied buffers across the synthesis callback boundary; never retains a
/// framework-owned mutable buffer or writes speech/microphone audio to a file.
private final class DuplexSpeechIngress: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence = 0
    func copy(_ audio: AVAudioBuffer) -> DuplexSpeechPacket {
        lock.lock(); defer { lock.unlock() }
        let index = sequence; sequence += 1
        guard let source = audio as? AVAudioPCMBuffer else {
            return .init(sequence: index, buffer: nil, byteCount: 0, isValid: false)
        }
        guard source.frameLength > 0 else {
            return .init(sequence: index, buffer: nil, byteCount: 0, isValid: true)
        }
        let inputs = UnsafeMutableAudioBufferListPointer(source.mutableAudioBufferList)
        let bytes = inputs.reduce(0) { $0 + Int($1.mDataByteSize) }
        guard bytes <= 2 * 1_024 * 1_024,
              let owned = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength) else {
            return .init(sequence: index, buffer: nil, byteCount: 0, isValid: false)
        }
        owned.frameLength = source.frameLength
        let outputs = UnsafeMutableAudioBufferListPointer(owned.mutableAudioBufferList)
        guard inputs.count == outputs.count else {
            return .init(sequence: index, buffer: nil, byteCount: 0, isValid: false)
        }
        for bufferIndex in inputs.indices {
            guard let input = inputs[bufferIndex].mData, let output = outputs[bufferIndex].mData,
                  outputs[bufferIndex].mDataByteSize >= inputs[bufferIndex].mDataByteSize else {
                return .init(sequence: index, buffer: nil, byteCount: 0, isValid: false)
            }
            memcpy(output, input, Int(inputs[bufferIndex].mDataByteSize))
        }
        return .init(sequence: index, buffer: owned, byteCount: bytes, isValid: true)
    }
}
