import MorningCore
import AVFAudio
import Foundation
import Observation

public enum SpeechPlaybackState: String, Sendable, Equatable {
    case idle, preparing, speaking, paused
}

public enum SpeechPlaybackError: LocalizedError, Sendable, Equatable {
    case emptyText
    case audioUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyText: AppLanguage.localized("There is no text to read.", bundle: .module)
        case .audioUnavailable(let reason): AppLanguage.localized("Audio output is unavailable: \(reason)", bundle: .module)
        }
    }
}

/// UTF-16 ranges match AVSpeechSynthesizer's callbacks, including emoji and accents.
struct SpeechCaptionProgress {
    private(set) var currentCaption: String?
    private(set) var revision: UInt = 0
    private var requestID: UUID?
    private var originalText = ""
    private var passages: [(range: NSRange, text: String)] = []
    private var currentPassage: Int?
    private var currentCaptionRange: NSRange?
    private var nextDuplexPassage = 0

    static func chunks(_ text: String) throws -> [String] {
        try LearningTextChunker.split(text, maximumCharacters: 110, maximumUTF8Bytes: 800)
    }

    mutating func begin(_ text: String, requestID: UUID) {
        reset()
        self.requestID = requestID
        originalText = text
        let chunks = (try? Self.chunks(text)) ?? []
        var offset = 0
        passages = chunks.map { chunk in
            let range = NSRange(location: offset, length: chunk.utf16.count)
            offset += range.length
            return (range, chunk)
        }
    }

    mutating func advance(to range: NSRange, requestID: UUID) {
        guard self.requestID == requestID, range.location != NSNotFound, range.location >= 0,
              range.length > 0, let last = passages.last,
              range.location < NSMaxRange(last.range),
              range.length <= NSMaxRange(last.range) - range.location,
              let index = passages.firstIndex(where: { NSLocationInRange(range.location, $0.range) }),
              currentPassage.map({ index > $0 }) ?? true else { return }
        currentPassage = index
        let text = passages[index].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentCaptionRange = passages[index].range
        show(text)
    }

    mutating func showChunk(_ text: String, requestID: UUID) {
        guard self.requestID == requestID else { return }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        // Duplex synthesizes these exact chunks in order, skipping whitespace.
        // A mismatched callback cannot supply a guessed position in private text.
        while nextDuplexPassage < passages.count,
              passages[nextDuplexPassage].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nextDuplexPassage += 1
        }
        if nextDuplexPassage < passages.count,
           passages[nextDuplexPassage].text.utf8.elementsEqual(text.utf8) {
            currentCaptionRange = passages[nextDuplexPassage].range
            nextDuplexPassage += 1
        } else {
            currentCaptionRange = nil
            nextDuplexPassage = passages.count
        }
        show(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes only an exact initial prefix, using the spoken passage's source
    /// range even when that prefix crosses several chunks. Audio stays intact.
    func caption(omittingInitialPrefix prefix: String) -> String? {
        guard let currentCaption else { return nil }
        guard !prefix.isEmpty, originalText.utf8.starts(with: prefix.utf8) else { return currentCaption }
        guard let currentCaptionRange else { return nil }
        let start = max(currentCaptionRange.location, prefix.utf16.count)
        let end = NSMaxRange(currentCaptionRange)
        guard start < end,
              let range = Range(NSRange(location: start, length: end - start), in: originalText) else { return nil }
        let text = originalText[range].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    mutating func reset() {
        requestID = nil; originalText = ""; passages.removeAll(); currentPassage = nil
        currentCaptionRange = nil; nextDuplexPassage = 0
        if currentCaption != nil { currentCaption = nil; revision &+= 1 }
    }

    private mutating func show(_ text: String) {
        guard !text.isEmpty else { return }
        currentCaption = text
        revision &+= 1
    }
}

/// Local system text-to-speech. The system/user chooses the output route.
@MainActor
@Observable
public final class SpeechCoordinator: NSObject {
    /// Keep the newest recognized words in Home's single short passage.
    public static func inputCaption(_ transcript: String) -> String {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 110 else { return text }
        let tail = text.suffix(110)
        let start = tail.firstIndex(where: \.isWhitespace).map { tail.index(after: $0) } ?? tail.startIndex
        return "…" + tail[start...]
    }

    public private(set) var state: SpeechPlaybackState = .idle
    public private(set) var lastError: String?
    /// Identifies the current utterance so a preview cannot stop later routine speech.
    public private(set) var playbackID: UUID?
    /// Session-only duplex ownership. The listener releases the shared session
    /// after playback has stopped; ordinary speech keeps its existing ownership.
    public var handsFreeAudioSessionIsOwned = false
    /// Installed only after explicit cloud narration consent.
    @ObservationIgnored public var externalSpeech: (@MainActor (String) async throws -> Void)?
    @ObservationIgnored public var cancelExternalSpeech: (@MainActor () -> Void)?
    /// An explicit cloud-to-Apple recovery policy. It must release the cloud audio
    /// owner and reject stale consent/context before returning. Cancellation never invokes it.
    @ObservationIgnored public var externalSpeechFallback: (@MainActor () async throws -> Void)?
    /// Text-only synthesis, installed by the app after its sharing disclosure.
    /// The duplex SDK route above takes priority while explicitly connected.
    @ObservationIgnored public var cloudSpeech: (@MainActor (String, MorningVoiceGender) async throws -> Data)?
    /// The workspace persists this preference; the coordinator holds no durable consent.
    public var voiceGender: MorningVoiceGender = .female {
        didSet {
            if oldValue != voiceGender { chosenVoiceIdentifier = nil; stop() }
        }
    }
    public private(set) var currentText: String?
    /// Only the passage currently being spoken; never persisted as a transcript.
    public var currentCaption: String? { captionProgress.currentCaption }
    public var captionRevision: UInt { captionProgress.revision }
    /// Display-only projection of the current spoken range; never changes TTS.
    public func caption(omittingInitialPrefix prefix: String) -> String? {
        captionProgress.caption(omittingInitialPrefix: prefix)
    }
    public var usesDuplexPlayback: Bool { duplexOutput != nil }
    /// Only an installed voice in the app's language can become a persisted choice.
    /// This also repairs a saved English voice when the app is opened in French.
    public var voiceIdentifier: String? {
        get { chosenVoiceIdentifier }
        set {
            chosenVoiceIdentifier = SpeechVoicePolicy.validatedIdentifier(newValue,
                from: availableVoices, language: preferredLanguage)
        }
    }
    private var chosenVoiceIdentifier: String?
    public var isSpeaking: Bool { state == .speaking }
    public var preferredLanguage: String { AppLanguage.localeIdentifier }

    public func repairVoiceSelection() {
        voiceIdentifier = chosenVoiceIdentifier
    }

    public var statusText: String {
        if let lastError { return lastError }
        switch state {
        case .idle: return AppLanguage.localized("Ready to speak", bundle: .module)
        case .preparing: return AppLanguage.localized("Preparing audio…", bundle: .module)
        case .speaking: return AppLanguage.localized("Speaking…", bundle: .module)
        case .paused: return AppLanguage.localized("Paused", bundle: .module)
        }
    }

    public var recommendedVoice: SpeechVoiceDescriptor? {
        SpeechVoicePolicy.recommended(from: availableVoices, language: preferredLanguage,
            gender: voiceGender,
            systemVoiceID: AVSpeechSynthesisVoice(language: preferredLanguage)?.identifier)
    }

    public var selectedVoice: SpeechVoiceDescriptor? {
        let voices = availableVoices
        return SpeechVoicePolicy.recommended(from: voices, language: preferredLanguage,
            gender: voiceGender,
            systemVoiceID: voiceIdentifier ?? AVSpeechSynthesisVoice(language: preferredLanguage)?.identifier)
    }

    public var selectedVoiceSummary: String {
        AppLanguage.localized(voiceGender == .male ? "Male" : "Female", bundle: .module)
    }

    public var previewText: String {
        SpeechVoicePolicy.previewText(language: selectedVoice?.language ?? preferredLanguage)
    }

    public func matchesPreferredLanguage(_ language: String) -> Bool {
        SpeechVoicePolicy.languageMatch(language, preferredLanguage) > 0
    }

    public var availableVoices: [SpeechVoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { Self.isBuiltInVoice($0) && matchesPreferredLanguage($0.language) }
            .map { SpeechVoiceDescriptor(id: $0.identifier, name: $0.name, language: $0.language,
                quality: SpeechVoiceQuality(rawValue: $0.quality.rawValue) ?? .standard,
                gender: $0.gender == .male ? .male : $0.gender == .female ? .female : nil) }
            .sorted {
                let leftMatch = SpeechVoicePolicy.languageMatch($0.language, preferredLanguage)
                let rightMatch = SpeechVoicePolicy.languageMatch($1.language, preferredLanguage)
                if leftMatch != rightMatch { return leftMatch > rightMatch }
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                let nameOrder = $0.name.localizedStandardCompare($1.name)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                if $0.language != $1.language { return $0.language < $1.language }
                return $0.id < $1.id
            }
    }

    private var captionProgress = SpeechCaptionProgress()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var duplexOutput: MorningDuplexSpeechOutput?
    @ObservationIgnored private let audioDataOutput = SpeechAudioDataOutput()
    @ObservationIgnored private var currentAudioData: Data?
    @ObservationIgnored private var outputRevision = UUID()
    @ObservationIgnored private var audioCaptionTask: Task<Void, Never>?
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private var speechRequestID: UUID?
    @ObservationIgnored private var completion: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    /// Injected by shared tests to observe completion without opening an audio device.
    @ObservationIgnored private var localSpeechOutput: (@MainActor (String, SpeechVoiceDescriptor?) async throws -> Void)?
    @ObservationIgnored private var audioDataPlayback: (@MainActor (Data) async throws -> Void)?
    @ObservationIgnored private var externalSpeechLocale: @MainActor () -> Locale = { AppLanguage.locale }
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { [weak self] in
            try await Self.activateAudioSession(handsFree: self?.handsFreeAudioSessionIsOwned == true)
        },
        deactivate: { [weak self] in
            guard self?.handsFreeAudioSessionIsOwned != true else { return }
            try await Self.deactivateAudioSession()
        }
    )

    public override init() {
        super.init()
        synthesizer.delegate = self
        #if os(iOS)
        routeTask = Task { [weak self] in
            let reasons = NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification)
                .compactMap { $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt }
            for await rawReason in reasons {
                guard !Task.isCancelled else { return }
                let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason)
                if reason == .oldDeviceUnavailable {
                    self?.handleAudioInterruption(outputChanged: true)
                }
            }
        }
        interruptionTask = Task { [weak self] in
            let types = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
                .compactMap { $0.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt }
            for await rawType in types {
                guard !Task.isCancelled else { return }
                let type = AVAudioSession.InterruptionType(rawValue: rawType)
                if type == .began {
                    self?.handleAudioInterruption(outputChanged: false)
                }
            }
        }
        #endif
    }

    convenience init(localSpeechOutput: @escaping @MainActor (String, SpeechVoiceDescriptor?) async throws -> Void,
                     audioDataPlayback: (@MainActor (Data) async throws -> Void)? = nil) {
        self.init()
        self.localSpeechOutput = localSpeechOutput
        self.audioDataPlayback = audioDataPlayback
    }

    convenience init(externalSpeechLocale: @escaping @MainActor () -> Locale) {
        self.init()
        self.externalSpeechLocale = externalSpeechLocale
    }

    deinit {
        routeTask?.cancel()
        interruptionTask?.cancel()
        activationTask?.cancel()
        audioCaptionTask?.cancel()
    }

    public func speak(_ text: String) {
        stop()
        beginSpeech(text, requestID: UUID())
    }

    /// Returns after this exact utterance finishes, including actual player drain
    /// when hands-free speech uses the shared voice-processing engine.
    /// Stop, replacement, cancellation or didCancel throws; pause alone keeps waiting.
    /// Completion proves synthesis finished, not that a listener heard the selected output.
    public func speakAndWait(_ text: String) async throws {
        try Task.checkCancellation()
        let requestID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                stop()
                speechRequestID = requestID
                completion = continuation
                beginSpeech(text, requestID: requestID)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                // A delayed cancellation must not stop a newer request.
                guard self?.speechRequestID == requestID else { return }
                self?.stop()
            }
        }
    }

    private func beginSpeech(_ text: String, requestID: UUID) {
        repairVoiceSelection()
        lastError = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            failBeforeSpeaking(SpeechPlaybackError.emptyText)
            return
        }
        playbackID = requestID
        currentText = text
        speechRequestID = requestID
        captionProgress.begin(text, requestID: requestID)
        state = .preparing
        let route = UUID(); outputRevision = route
        if let externalSpeech {
            activationTask = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled, speechRequestID == requestID else { return }
                state = .speaking
                captionProgress.showChunk(text, requestID: requestID)
                do {
                    try await externalSpeech(text)
                    try Task.checkCancellation()
                    finishExternalSpeech(requestID: requestID, result: .success(()))
                } catch {
                    await recoverAppleSpeech(error, text: text, requestID: requestID, requiresRelease: true)
                }
            }
            return
        }
        activationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, speechRequestID == requestID else { return }
            do {
                if let cloudSpeech {
                    do {
                        let data = try await cloudSpeech(text, voiceGender)
                        try Task.checkCancellation()
                        guard speechRequestID == requestID, outputRevision == route else { return }
                        try await prepareAudioData(data, text: text, requestID: requestID)
                        guard outputRevision == route else { return }
                        finishExternalSpeech(requestID: requestID, result: .success(()))
                        return
                    } catch {
                        guard outputRevision == route else { return }
                        await recoverAppleSpeech(error, text: text, requestID: requestID, requiresRelease: false)
                        return
                    }
                }
                try await prepareLocalSpeech(text, requestID: requestID)
            } catch {
                guard speechRequestID == requestID else { return }
                failBeforeSpeaking(SpeechPlaybackError.audioUnavailable(error.moreDescription))
            }
        }
    }

    private func recoverAppleSpeech(_ error: any Error, text: String, requestID: UUID, requiresRelease: Bool) async {
        guard speechRequestID == requestID else { return }
        guard !(error is CancellationError), !Task.isCancelled, state != .paused,
              !requiresRelease || externalSpeechFallback != nil else {
            finishExternalSpeech(requestID: requestID, result: .failure(error))
            return
        }
        audioDataOutput.stop(); duplexOutput?.cancel(); currentAudioData = nil
        audioCaptionTask?.cancel(); audioCaptionTask = nil
        state = .preparing
        captionProgress.begin(text, requestID: requestID)
        do {
            if let externalSpeechFallback { try await externalSpeechFallback() }
            try Task.checkCancellation()
            guard speechRequestID == requestID else { return }
            try await prepareLocalSpeech(text, requestID: requestID)
        } catch { finishExternalSpeech(requestID: requestID, result: .failure(error)) }
    }

    private func prepareAudioData(_ data: Data, text: String, requestID: UUID, startPaused: Bool = false) async throws {
        let prepared = try await audioSession.prepare(for: requestID).value
        try Task.checkCancellation()
        guard prepared, speechRequestID == requestID else { throw CancellationError() }
        currentAudioData = data
        if let audioDataPlayback {
            state = .speaking
            if let first = try SpeechCaptionProgress.chunks(text).first { captionProgress.showChunk(first, requestID: requestID) }
            try await audioDataPlayback(data)
            try Task.checkCancellation()
            return
        }
        try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<Void, any Error>) in
            do {
                let completed: @MainActor (Result<Void, any Error>) -> Void = { waiting.resume(with: $0) }
                if let duplexOutput {
                    try duplexOutput.play(data: data, startPaused: startPaused, onStarted: { [weak self] duration in
                        self?.beginAudioCaptions(text, duration: duration, requestID: requestID)
                    }, completion: completed)
                } else {
                    let duration = try audioDataOutput.play(data, completion: completed)
                    beginAudioCaptions(text, duration: duration, requestID: requestID)
                }
            } catch { waiting.resume(throwing: error) }
        }
    }

    private func beginAudioCaptions(_ text: String, duration: TimeInterval, requestID: UUID) {
        guard speechRequestID == requestID else { return }
        state = .speaking
        let chunks = (try? SpeechCaptionProgress.chunks(text)) ?? []
        guard let first = chunks.first else { return }
        captionProgress.showChunk(first, requestID: requestID)
        audioCaptionTask?.cancel()
        let revision = outputRevision
        // Approximate passage timing only. The audio player's drain decides completion.
        audioCaptionTask = Task { [weak self] in
            let total = Double(max(1, chunks.reduce(0) { $0 + $1.count }))
            var elapsed: TimeInterval = 0, last = Date.timeIntervalSinceReferenceDate, index = 0
            var next = duration * Double(first.count) / total
            while index + 1 < chunks.count {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                guard let self, speechRequestID == requestID, outputRevision == revision else { return }
                let now = Date.timeIntervalSinceReferenceDate
                if state == .speaking { elapsed += max(0, now - last) }
                last = now
                if elapsed >= next {
                    index += 1
                    captionProgress.showChunk(chunks[index], requestID: requestID)
                    next += duration * Double(chunks[index].count) / total
                }
            }
        }
    }

    private func prepareLocalSpeech(_ text: String, requestID: UUID) async throws {
        let prepared = try await audioSession.prepare(for: requestID).value
        try Task.checkCancellation()
        guard prepared, speechRequestID == requestID else { throw CancellationError() }
        if let localSpeechOutput {
            state = .speaking
            captionProgress.showChunk(text, requestID: requestID)
            try await localSpeechOutput(text, selectedVoice)
            try Task.checkCancellation()
            finishExternalSpeech(requestID: requestID, result: .success(()))
        } else { enqueueSpeech(text) }
    }

    private func enqueueSpeech(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let selected = selectedVoice, let voice = AVSpeechSynthesisVoice(identifier: selected.id), Self.isBuiltInVoice(voice) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: preferredLanguage), Self.isBuiltInVoice(voice), matchesPreferredLanguage(voice.language) {
            // No foreign-language or novelty fallback is chosen by our ranking policy.
            utterance.voice = voice
        } else {
            failBeforeSpeaking(.audioUnavailable(AppLanguage.localized("No voice is available for this language on this device.", bundle: .module)))
            return
        }
        if let duplexOutput, let requestID = speechRequestID, let voice = utterance.voice {
            currentUtterance = nil
            duplexOutput.play(text, voice: voice, onChunkStarted: { [weak self] chunk in
                guard let self, speechRequestID == requestID else { return }
                captionProgress.showChunk(chunk, requestID: requestID)
                if state != .paused { state = .speaking }
            }, completion: { [weak self] result in
                guard let self, speechRequestID == requestID else { return }
                switch result {
                case .success:
                    currentText = nil; playbackID = nil; speechRequestID = nil; state = .idle; lastError = nil
                    captionProgress.reset()
                    let pending = completion; completion = nil
                    audioSession.cancel(); pending?.resume()
                case .failure(let error):
                    failBeforeSpeaking(.audioUnavailable(error is CancellationError ? AppLanguage.localized("Speech stopped.", bundle: .module) : AppLanguage.localized("Duplex speech output could not finish safely.", bundle: .module)))
                }
            })
        } else {
            currentUtterance = ObjectIdentifier(utterance)
            synthesizer.speak(utterance)
        }
    }

    /// Attaches only inside the foreground session's microphone owner. Existing
    /// ordinary speech is restarted through the shared output without completing
    /// its caller early; teardown happens after stopAndRelease has drained owners.
    func setHandsFreeOutput(_ output: MorningDuplexSpeechOutput?) {
        guard duplexOutput !== output else { return }
        let data = audioDataOutput.hasPlayback ? currentAudioData : nil
        let transferring = duplexOutput == nil && output != nil && (currentUtterance != nil || data != nil)
        let wasPaused = state == .paused
        if transferring {
            outputRevision = UUID()
            currentUtterance = nil; synthesizer.stopSpeaking(at: .immediate)
            audioDataOutput.stop()
        }
        duplexOutput?.detach(); duplexOutput = output
        if transferring, let text = currentText {
            if let data, let requestID = speechRequestID {
                let revision = outputRevision
                activationTask = Task { [weak self] in
                    guard let self, speechRequestID == requestID, outputRevision == revision else { return }
                    do {
                        try await prepareAudioData(data, text: text, requestID: requestID, startPaused: wasPaused)
                        guard outputRevision == revision else { return }
                        finishExternalSpeech(requestID: requestID, result: .success(()))
                    } catch {
                        guard outputRevision == revision else { return }
                        await recoverAppleSpeech(error, text: text, requestID: requestID, requiresRelease: false)
                    }
                }
            } else {
                enqueueSpeech(text)
                if wasPaused { _ = output?.pause() }
            }
        }
    }

    public func pause() {
        // Cloud streaming cannot be resumed from an exact audio position.
        if externalSpeech != nil { stop(); return }
        if let duplexOutput {
            if duplexOutput.pause() { state = .paused }
            return
        }
        if audioDataOutput.pause() { state = .paused; return }
        guard currentUtterance != nil else { return }
        if synthesizer.isPaused || synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
    }

    public func resume() {
        guard state == .paused, currentUtterance != nil || duplexOutput != nil || audioDataOutput.hasPlayback,
              let requestID = speechRequestID else { return }
        if currentAudioData == nil { activationTask?.cancel() }
        let activationID = UUID()
        lastError = nil
        state = .preparing
        activationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, speechRequestID == requestID else { return }
            do {
                let prepared = try await audioSession.prepare(for: activationID).value
                guard prepared, !Task.isCancelled, speechRequestID == requestID else { return }
                if let duplexOutput {
                    if duplexOutput.resume() { state = .speaking }
                    else { failBeforeSpeaking(.audioUnavailable(AppLanguage.localized("Duplex speech could not resume.", bundle: .module))) }
                } else if audioDataOutput.hasPlayback {
                    if audioDataOutput.resume() { state = .speaking }
                    else { failBeforeSpeaking(.audioUnavailable(AppLanguage.localized("Audio playback could not resume.", bundle: .module))) }
                } else if synthesizer.continueSpeaking() { state = .speaking }
                else { failBeforeSpeaking(.audioUnavailable(AppLanguage.localized("This speech could not resume. Play it again when ready.", bundle: .module))) }
            } catch {
                guard speechRequestID == requestID else { return }
                failBeforeSpeaking(.audioUnavailable(error.moreDescription))
            }
        }
    }

    public func stop() {
        stopPlayback()
    }

    /// Stops synthesis and waits until its pending activation and audio release finish.
    /// A microphone owner must await this before activating its own session, and must
    /// still validate its own listening request after the await. Cancellation or newer
    /// speech supersedes the handoff; release errors are surfaced rather than ignored.
    public func stopAndRelease() async throws {
        let preparing = activationTask
        let release = stopPlayback()
        await preparing?.value
        try await release.task.value
        try Task.checkCancellation()
        guard speechRequestID == nil, audioSession.isCurrent(release) else { throw CancellationError() }
    }

    @discardableResult
    private func stopPlayback() -> SpeechAudioSessionGate.Release {
        // Invalidate first, so a late callback from the previous utterance cannot stop a new one.
        currentUtterance = nil
        currentText = nil
        currentAudioData = nil
        outputRevision = UUID()
        audioCaptionTask?.cancel(); audioCaptionTask = nil
        captionProgress.reset()
        playbackID = nil
        speechRequestID = nil
        activationTask?.cancel()
        activationTask = nil
        cancelExternalSpeech?()
        let pending = completion
        completion = nil
        duplexOutput?.cancel()
        audioDataOutput.stop()
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        lastError = nil
        let release = audioSession.cancel()
        pending?.resume(throwing: CancellationError())
        return release
    }

    private func finishExternalSpeech(requestID: UUID, result: Result<Void, any Error>) {
        guard speechRequestID == requestID else { return }
        currentText = nil; captionProgress.reset(); playbackID = nil; speechRequestID = nil
        currentAudioData = nil
        audioCaptionTask?.cancel(); audioCaptionTask = nil
        activationTask = nil; state = .idle
        audioSession.cancel()
        let pending = completion; completion = nil
        switch result {
        case .success: lastError = nil; pending?.resume()
        case .failure(let error):
            lastError = error is CancellationError ? nil : AppLanguage.localized("Cloud speech could not finish. Try again or continue with the controls.", bundle: .module, locale: externalSpeechLocale())
            pending?.resume(throwing: error is CancellationError ? CancellationError() : SpeechPlaybackError.audioUnavailable(lastError!))
        }
    }

    /// Notification handlers must not invent a resumable session after playback has ended.
    func handleAudioInterruption(outputChanged: Bool) {
        guard playbackID != nil else { return }
        // A pending initial activation or resume must not finish and start audio after
        // an interruption. It cannot be represented as a safely resumable utterance yet.
        if state == .preparing { stop() }
        else { pause() }
        if state == .paused {
            lastError = outputChanged ? AppLanguage.localized("Audio output changed. Resume when you are ready to listen.", bundle: .module)
                : AppLanguage.localized("Speech was interrupted. Resume when you are ready.", bundle: .module)
        } else {
            stop()
            lastError = outputChanged ? AppLanguage.localized("Audio output changed. Play the voice again when ready.", bundle: .module)
                : AppLanguage.localized("Speech stopped during an interruption. Play it again when ready.", bundle: .module)
        }
    }

    private func failBeforeSpeaking(_ error: SpeechPlaybackError) {
        lastError = error.moreDescription
        currentText = nil
        currentAudioData = nil
        audioCaptionTask?.cancel(); audioCaptionTask = nil
        captionProgress.reset()
        currentUtterance = nil
        playbackID = nil
        speechRequestID = nil
        activationTask?.cancel()
        activationTask = nil
        let pending = completion
        completion = nil
        duplexOutput?.cancel()
        audioDataOutput.stop()
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        audioSession.cancel()
        pending?.resume(throwing: error)
    }

    private func receive(_ state: SpeechPlaybackState, utteranceID: ObjectIdentifier,
                         finished: Bool = false, cancelled: Bool = false) {
        guard currentUtterance == utteranceID else { return }
        self.state = state
        if finished {
            currentText = nil
            captionProgress.reset()
            currentUtterance = nil
            playbackID = nil
            speechRequestID = nil
            lastError = nil
            let pending = completion
            completion = nil
            audioSession.cancel()
            if cancelled { pending?.resume(throwing: CancellationError()) }
            else { pending?.resume() }
        }
    }

    private func receiveCaption(_ range: NSRange, utteranceID: ObjectIdentifier) {
        guard currentUtterance == utteranceID, state != .paused, let requestID = speechRequestID else { return }
        captionProgress.advance(to: range, requestID: requestID)
    }

    private static func activateAudioSession(handsFree: Bool) async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if handsFree {
            try session.setCategory(.playAndRecord, mode: .voiceChat,
                options: [.defaultToSpeaker, .allowBluetoothHFP])
        } else {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        if #available(iOS 27.0, *) {
            // Xcode 27 AVAudioSession.h makes this public on iOS 27, not just watchOS.
            let activated = try await session.activate(options: [])
            guard activated else { throw SpeechPlaybackError.audioUnavailable(AppLanguage.localized("The audio session did not activate.", bundle: .module)) }
        } else {
            try session.setActive(true)
        }
        #endif
    }

    private static func deactivateAudioSession() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            let deactivated = try await session.deactivate(options: .notifyOthersOnDeactivation)
            guard deactivated else {
                throw SpeechPlaybackError.audioUnavailable(AppLanguage.localized("The audio session could not be released. Try again before listening.", bundle: .module))
            }
        } else {
            try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        #endif
    }

    private static func isBuiltInVoice(_ voice: AVSpeechSynthesisVoice) -> Bool {
        // speechVoices() also includes third-party providers. Apple exposes no provider
        // ownership property, so use a conservative namespace filter for this chooser.
        // Personal Voice stays excluded even if another app flow previously authorized it.
        voice.identifier.hasPrefix("com.apple.")
            && !voice.voiceTraits.contains(.isPersonalVoice)
            && !voice.voiceTraits.contains(.isNoveltyVoice)
    }
}

extension SpeechCoordinator: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                             willSpeakRangeOfSpeechString characterRange: NSRange,
                                             utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receiveCaption(characterRange, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.speaking, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.paused, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.speaking, utteranceID: id) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.idle, utteranceID: id, finished: true) }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.receive(.idle, utteranceID: id, finished: true, cancelled: true) }
    }
}

/// Standalone synthesized output. Explicit cancellation resolves its waiter and
/// late callbacks cannot finish a replacement player. No microphone is opened.
@MainActor
private final class SpeechAudioDataOutput: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var completion: (@MainActor (Result<Void, any Error>) -> Void)?
    var hasPlayback: Bool { player != nil }

    func play(_ data: Data, completion: @escaping @MainActor (Result<Void, any Error>) -> Void) throws -> TimeInterval {
        stop()
        guard !data.isEmpty, data.count <= 16 * 1_024 * 1_024 else { throw SpeechAudioPCM.unavailable() }
        let player = try AVAudioPlayer(data: data)
        guard player.duration.isFinite, player.duration > 0, player.duration <= 600,
              player.prepareToPlay() else { throw SpeechAudioPCM.unavailable() }
        self.player = player; self.completion = completion; player.delegate = self
        guard player.play() else {
            self.player = nil; self.completion = nil; player.delegate = nil
            throw SpeechAudioPCM.unavailable()
        }
        return player.duration
    }

    func pause() -> Bool {
        guard let player else { return false }
        player.pause(); return true
    }
    func resume() -> Bool { player?.play() == true }
    func stop() {
        let old = player; player = nil; old?.delegate = nil; old?.stop()
        let waiting = completion; completion = nil
        waiting?(.failure(CancellationError()))
    }
    private func finish(_ id: ObjectIdentifier, success: Bool) {
        guard let player, ObjectIdentifier(player) == id else { return }
        self.player = nil; player.delegate = nil
        let waiting = completion; completion = nil
        waiting?(success ? .success(()) : .failure(SpeechAudioPCM.unavailable()))
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finish(id, success: flag) }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor [weak self] in self?.finish(id, success: false) }
    }
}
