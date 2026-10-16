import AVFAudio
import Foundation
import MorningCore

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
    private let format: AVAudioFormat
    private var programID: UUID?
    private var task: Task<Void, Never>?
    private var continuation: CheckedContinuation<Void, any Error>?
    private var ledger = DuplexSpeechPlaybackLedger()
    private var nextSequence = 0
    private var packets: [Int: DuplexSpeechPacket] = [:]
    private var scheduledBytes: [Int: Int] = [:]
    private var isPaused = false
    private var onChunkStarted: (@MainActor (String) -> Void)?
    private var pendingCaption: String?
    private var dataCompletion: (@MainActor (Result<Void, any Error>) -> Void)?
    private var dataStarted: (@MainActor () -> Void)?
    private static let maximumQueuedBytes = 16 * 1_024 * 1_024

    init(engine: AVAudioEngine) throws {
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw SpeechAudioPCM.unavailable() }
        self.engine = engine
        self.format = format
        engine.attach(player)
        #if compiler(>=6.4)
        if #available(iOS 27.0, macOS 27.0, *) {
            try engine.connectNode(player, to: engine.outputNode, format: format)
        } else { engine.connect(player, to: engine.outputNode, format: format) }
        #else
        engine.connect(player, to: engine.outputNode, format: format)
        #endif
    }

    func play(data: Data, startPaused: Bool = false,
              onStarted: @escaping @MainActor (TimeInterval) -> Void,
              completion: @escaping @MainActor (Result<Void, any Error>) -> Void) throws {
        cancel()
        let buffer = try SpeechAudioPCM.convert(SpeechAudioPCM.decode(data), to: format)
        let bytes = SpeechAudioPCM.byteCount(buffer)
        guard engine.isRunning, bytes <= Self.maximumQueuedBytes else { throw SpeechAudioPCM.unavailable() }
        let id = UUID(), duration = Double(buffer.frameLength) / format.sampleRate
        programID = id; ledger.begin(id)
        guard ledger.scheduled(0, id: id) else { throw SpeechAudioPCM.unavailable() }
        _ = ledger.synthesized(id: id)
        scheduledBytes[0] = bytes; dataCompletion = completion
        dataStarted = { onStarted(duration) }; isPaused = startPaused
        let playedBuffer: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
            Task { @MainActor [weak self] in self?.played(0, id: id) }
        }
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack, completionHandler: playedBuffer)
        startPlayback()
    }

    func play(_ text: String, voice: AVSpeechSynthesisVoice,
              onChunkStarted: @escaping @MainActor (String) -> Void,
              completion: @escaping @MainActor (Result<Void, any Error>) -> Void) {
        cancel()
        let id = UUID()
        programID = id; self.onChunkStarted = onChunkStarted
        task = Task { [weak self] in
            guard let self else { return }
            do {
                // Exact chunks are synthesized sequentially and drained before the
                // next one, so a long private reading cannot queue unbounded PCM.
                let chunks = try SpeechCaptionProgress.chunks(text)
                for chunk in chunks where !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try Task.checkCancellation()
                    guard programID == id else { throw CancellationError() }
                    try await playChunk(chunk, voice: voice)
                }
                guard programID == id else { return }
                programID = nil; task = nil; self.onChunkStarted = nil
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
        startPlayback()
        return true
    }

    func cancel() {
        programID = nil; task?.cancel(); task = nil; ledger.cancel()
        packets.removeAll(); scheduledBytes.removeAll(); onChunkStarted = nil; pendingCaption = nil
        let waiting = continuation; continuation = nil
        let dataWaiting = dataCompletion; dataCompletion = nil; dataStarted = nil
        player.stop(); synthesizer.stopSpeaking(at: .immediate)
        isPaused = false
        waiting?.resume(throwing: CancellationError())
        dataWaiting?(.failure(CancellationError()))
    }

    func detach() {
        cancel()
        engine.disconnectNodeOutput(player)
        engine.detach(player)
    }

    private func playChunk(_ text: String, voice: AVSpeechSynthesisVoice) async throws {
        let id = UUID()
        ledger.begin(id); nextSequence = 0; packets.removeAll(); scheduledBytes.removeAll()
        pendingCaption = text
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
            let playback: AVAudioPCMBuffer
            do { playback = try SpeechAudioPCM.convert(buffer, to: format) }
            catch { failChunk(); return }
            let bytes = SpeechAudioPCM.byteCount(playback)
            guard scheduledBytes.values.reduce(0, +) + bytes <= Self.maximumQueuedBytes else { failChunk(); return }
            guard ledger.scheduled(packet.sequence, id: id) else { failChunk(); return }
            scheduledBytes[packet.sequence] = bytes
            let sequence = packet.sequence
            let playedBuffer: @Sendable (AVAudioPlayerNodeCompletionCallbackType) -> Void = { [weak self] _ in
                Task { @MainActor [weak self] in self?.played(sequence, id: id) }
            }
            player.scheduleBuffer(playback, completionCallbackType: .dataPlayedBack, completionHandler: playedBuffer)
            startPlayback()
        }
    }

    private func startPlayback() {
        guard !isPaused, !scheduledBytes.isEmpty else { return }
        player.play()
        let started = dataStarted; dataStarted = nil; started?()
        if let pendingCaption {
            self.pendingCaption = nil
            onChunkStarted?(pendingCaption)
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
        if let completed = dataCompletion {
            dataCompletion = nil; dataStarted = nil; programID = nil
            completed(.success(()))
        }
        waiting?.resume()
    }

    private func failChunk() {
        ledger.cancel(); packets.removeAll(); scheduledBytes.removeAll()
        let waiting = continuation; continuation = nil
        player.stop(); synthesizer.stopSpeaking(at: .immediate)
        if let completed = dataCompletion {
            dataCompletion = nil; dataStarted = nil; programID = nil
            completed(.failure(SpeechAudioPCM.unavailable()))
        }
        waiting?.resume(throwing: SpeechPlaybackError.audioUnavailable(AppLanguage.localized("Audio output could not finish safely.", bundle: .module)))
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

/// Bounded decoding of synthesized output only. Microphone buffers never enter this path.
@MainActor
enum SpeechAudioPCM {
    static func unavailable() -> SpeechPlaybackError {
        .audioUnavailable(AppLanguage.localized("Audio output could not be prepared.", bundle: .module))
    }

    static func decode(_ data: Data) throws -> AVAudioPCMBuffer {
        guard !data.isEmpty, data.count <= 16 * 1_024 * 1_024 else { throw unavailable() }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("more-speech-\(UUID().uuidString).audio")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        #if os(iOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        let file = try AVAudioFile(forReading: fileURL)
        let format = file.processingFormat
        let bytesPerFrame = Double(format.streamDescription.pointee.mBytesPerFrame) * Double(format.isInterleaved ? 1 : format.channelCount)
        guard file.length > 0, file.length <= 12_000_000,
              bytesPerFrame > 0, file.processingFormat.channelCount <= 2,
              Double(file.length) * bytesPerFrame <= 64 * 1_024 * 1_024,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw unavailable()
        }
        try file.read(into: buffer)
        guard buffer.frameLength > 0 else { throw unavailable() }
        return buffer
    }

    static func byteCount(_ buffer: AVAudioPCMBuffer) -> Int {
        UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList).reduce(0) { $0 + Int($1.mDataByteSize) }
    }

    static func convert(_ input: AVAudioPCMBuffer, to format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard input.frameLength > 0, input.frameLength <= 12_000_000,
              input.format.sampleRate > 0, format.sampleRate > 0, format.channelCount > 0 else { throw unavailable() }
        if input.format.isEqual(format) { return input }
        guard let converter = AVAudioConverter(from: input.format, to: format) else { throw unavailable() }
        let ratio = format.sampleRate / input.format.sampleRate
        let prime = Double(converter.primeInfo.leadingFrames) + Double(converter.primeInfo.trailingFrames)
        let capacity = ceil((Double(input.frameLength) + prime) * ratio) + 32
        let bytesPerFrame = Double(format.streamDescription.pointee.mBytesPerFrame) * Double(format.isInterleaved ? 1 : format.channelCount)
        guard capacity.isFinite, capacity > 0, capacity <= 12_000_000,
              bytesPerFrame > 0, capacity * bytesPerFrame <= 64 * 1_024 * 1_024,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw unavailable()
        }
        var supplied = false
        var failure: NSError?
        let status = converter.convert(to: output, error: &failure) { _, status in
            guard !supplied else { status.pointee = .endOfStream; return nil }
            supplied = true; status.pointee = .haveData
            return input
        }
        if let failure { throw failure }
        guard status != .error, output.frameLength > 0 else { throw unavailable() }
        return output
    }
}
