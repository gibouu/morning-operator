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
        case .emptyText: String(localized: "There is no text to read.", bundle: .module)
        case .audioUnavailable(let reason): String(localized: "Audio output is unavailable: \(reason)", bundle: .module)
        }
    }
}

/// Local system text-to-speech. The system/user chooses the output route.
@MainActor
@Observable
public final class SpeechCoordinator: NSObject {
    public private(set) var state: SpeechPlaybackState = .idle
    public private(set) var lastError: String?
    /// Identifies the current utterance so a preview cannot stop later routine speech.
    public private(set) var playbackID: UUID?
    /// A persisted choice may become unavailable after a system voice is removed.
    /// Nil, unknown, and unavailable choices use an available voice matching the system language.
    public var voiceIdentifier: String?
    public var isSpeaking: Bool { state == .speaking }
    public var preferredLanguage: String { AVSpeechSynthesisVoice.currentLanguageCode() }

    public var statusText: String {
        if let lastError { return lastError }
        switch state {
        case .idle: return String(localized: "Ready to speak", bundle: .module)
        case .preparing: return String(localized: "Preparing audio…", bundle: .module)
        case .speaking: return String(localized: "Speaking…", bundle: .module)
        case .paused: return String(localized: "Paused", bundle: .module)
        }
    }

    public var recommendedVoice: SpeechVoiceDescriptor? {
        SpeechVoicePolicy.recommended(from: availableVoices, language: preferredLanguage,
            systemVoiceID: AVSpeechSynthesisVoice(language: preferredLanguage)?.identifier)
    }

    public var selectedVoice: SpeechVoiceDescriptor? {
        let voices = availableVoices
        if let voiceIdentifier, let selected = voices.first(where: { $0.id == voiceIdentifier }) { return selected }
        return SpeechVoicePolicy.recommended(from: voices, language: preferredLanguage,
            systemVoiceID: AVSpeechSynthesisVoice(language: preferredLanguage)?.identifier)
    }

    public var selectedVoiceSummary: String {
        guard let voice = selectedVoice else { return String(localized: "Device language", bundle: .module) }
        return "\(voice.name) · \(voice.quality.displayName)"
    }

    public var previewText: String {
        SpeechVoicePolicy.previewText(language: selectedVoice?.language ?? preferredLanguage)
    }

    public func matchesPreferredLanguage(_ language: String) -> Bool {
        SpeechVoicePolicy.languageMatch(language, preferredLanguage) > 0
    }

    public var availableVoices: [SpeechVoiceDescriptor] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { Self.isBuiltInVoice($0) }
            .map { SpeechVoiceDescriptor(id: $0.identifier, name: $0.name, language: $0.language,
                quality: SpeechVoiceQuality(rawValue: $0.quality.rawValue) ?? .standard) }
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

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: ObjectIdentifier?
    @ObservationIgnored private var speechRequestID: UUID?
    @ObservationIgnored private var completion: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var activationTask: Task<Void, Never>?
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { try await Self.activateAudioSession() },
        deactivate: { try await Self.deactivateAudioSession() }
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

    deinit {
        routeTask?.cancel()
        interruptionTask?.cancel()
        activationTask?.cancel()
    }

    public func speak(_ text: String) {
        stop()
        beginSpeech(text, requestID: UUID())
    }

    /// Returns only when AVSpeechSynthesizer reports didFinish for this exact utterance.
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
        lastError = nil
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            failBeforeSpeaking(SpeechPlaybackError.emptyText)
            return
        }
        playbackID = requestID
        speechRequestID = requestID
        state = .preparing
        activationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, speechRequestID == requestID else { return }
            do {
                let prepared = try await audioSession.prepare(for: requestID).value
                guard prepared, !Task.isCancelled, speechRequestID == requestID else { return }
                enqueueSpeech(text)
            } catch {
                guard speechRequestID == requestID else { return }
                failBeforeSpeaking(SpeechPlaybackError.audioUnavailable(error.localizedDescription))
            }
        }
    }

    private func enqueueSpeech(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if let selected = selectedVoice, let voice = AVSpeechSynthesisVoice(identifier: selected.id), Self.isBuiltInVoice(voice) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: preferredLanguage), Self.isBuiltInVoice(voice) {
            // No foreign-language or novelty fallback is chosen by our ranking policy.
            utterance.voice = voice
        } else {
            failBeforeSpeaking(.audioUnavailable(String(localized: "No supported system voice is available for this language. Choose an installed voice in Settings.", bundle: .module)))
            return
        }
        currentUtterance = ObjectIdentifier(utterance)
        synthesizer.speak(utterance)
    }

    public func pause() {
        guard currentUtterance != nil else { return }
        if synthesizer.isPaused || synthesizer.pauseSpeaking(at: .immediate) { state = .paused }
    }

    public func resume() {
        guard state == .paused, currentUtterance != nil, let requestID = speechRequestID else { return }
        activationTask?.cancel()
        let activationID = UUID()
        lastError = nil
        state = .preparing
        activationTask = Task { [weak self] in
            guard let self, !Task.isCancelled, speechRequestID == requestID else { return }
            do {
                let prepared = try await audioSession.prepare(for: activationID).value
                guard prepared, !Task.isCancelled, speechRequestID == requestID else { return }
                if synthesizer.continueSpeaking() { state = .speaking }
                else { failBeforeSpeaking(.audioUnavailable(String(localized: "This speech could not resume. Play it again when ready.", bundle: .module))) }
            } catch {
                guard speechRequestID == requestID else { return }
                failBeforeSpeaking(.audioUnavailable(error.localizedDescription))
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
        playbackID = nil
        speechRequestID = nil
        activationTask?.cancel()
        activationTask = nil
        let pending = completion
        completion = nil
        synthesizer.stopSpeaking(at: .immediate)
        state = .idle
        lastError = nil
        let release = audioSession.cancel()
        pending?.resume(throwing: CancellationError())
        return release
    }

    /// Notification handlers must not invent a resumable session after playback has ended.
    func handleAudioInterruption(outputChanged: Bool) {
        guard playbackID != nil else { return }
        // A pending initial activation or resume must not finish and start audio after
        // an interruption. It cannot be represented as a safely resumable utterance yet.
        if state == .preparing { stop() }
        else { pause() }
        if state == .paused {
            lastError = outputChanged ? String(localized: "Audio output changed. Resume when you are ready to listen.", bundle: .module)
                : String(localized: "Speech was interrupted. Resume when you are ready.", bundle: .module)
        } else {
            stop()
            lastError = outputChanged ? String(localized: "Audio output changed. Play the voice again when ready.", bundle: .module)
                : String(localized: "Speech stopped during an interruption. Play it again when ready.", bundle: .module)
        }
    }

    private func failBeforeSpeaking(_ error: SpeechPlaybackError) {
        lastError = error.localizedDescription
        currentUtterance = nil
        playbackID = nil
        speechRequestID = nil
        activationTask?.cancel()
        activationTask = nil
        let pending = completion
        completion = nil
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

    private static func activateAudioSession() async throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        if #available(iOS 27.0, *) {
            // Xcode 27 AVAudioSession.h makes this public on iOS 27, not just watchOS.
            let activated = try await session.activate(options: [])
            guard activated else { throw SpeechPlaybackError.audioUnavailable(String(localized: "The audio session did not activate.", bundle: .module)) }
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
                throw SpeechPlaybackError.audioUnavailable(String(localized: "The audio session could not be released. Try again before listening.", bundle: .module))
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
