import Foundation
import MorningCore
import Observation
#if os(iOS)
import AVFAudio
import Speech
import UIKit
#endif

public enum MorningHandsFreeVoiceState: String, Sendable {
    case idle, preparing, listening, understanding, unavailable, failed
}

/// One foreground session owns a duplex microphone, with short recognition turns
/// renewed automatically. Audio buffers and utterances are never written to disk.
@MainActor
@Observable
public final class MorningHandsFreeVoiceCoordinator {
    public private(set) var state: MorningHandsFreeVoiceState = .idle
    public private(set) var message = AppLanguage.localized("Voice is off.", bundle: .module)
    public private(set) var needsAudioRelease = false
    public var isActive: Bool { state == .preparing || state == .listening || state == .understanding }
    /// Latest hypothesis, kept only until replacement/stop so final words remain readable.
    public private(set) var transcript = ""
    public private(set) var transcriptRevision: UInt = 0
    public let conversation = MorningVoiceConversation()
    public var interruptedRunningSession = false
    public var momentContext = ""
    public var continuation = MorningVoiceContinuationPolicy()

    #if os(iOS)
    @ObservationIgnored private var language: MorningVoiceCommandLanguage = .current
    @ObservationIgnored private var languageGeneration = UUID()
    @ObservationIgnored private var runID: UUID?
    @ObservationIgnored private var recognitionID: UUID?
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var cleanup: Task<Void, any Error>?
    @ObservationIgnored private var processing: Task<Void, Never>?
    @ObservationIgnored private var silenceDeadline: Task<Void, Never>?
    @ObservationIgnored private var turnDeadline: Task<Void, Never>?
    @ObservationIgnored private var finalDeadline: Task<Void, Never>?
    @ObservationIgnored private var notificationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private weak var speech: SpeechCoordinator?
    @ObservationIgnored private var context: (@MainActor () -> MorningVoiceCommandContext?)?
    @ObservationIgnored private var onSpeech: (@MainActor () -> Void)?
    @ObservationIgnored private var onUtterance: (@MainActor (MorningHandsFreeUtterance) async -> Void)?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let sink = HandsFreeAudioSink()
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var turn = MorningHandsFreeVoiceTurn()
    @ObservationIgnored private var isFinishing = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var echoOutput: String?
    @ObservationIgnored private var echoOutputAt = Date.distantPast
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { try await Self.activateMicrophone() },
        deactivate: { try await Self.releaseMicrophone() }
    )
    #endif

    public init() {}

    deinit {
        #if os(iOS)
        startup?.cancel(); processing?.cancel()
        silenceDeadline?.cancel(); turnDeadline?.cancel(); finalDeadline?.cancel()
        for task in notificationTasks { task.cancel() }
        #endif
    }

    /// Starting a morning is the explicit session-level request for listening.
    /// Unavailable local recognition never falls back to a remote recognizer.
    public func start(language: MorningVoiceCommandLanguage, speech: SpeechCoordinator,
                      languageGeneration: UUID = UUID(),
                      context: @escaping @MainActor () -> MorningVoiceCommandContext?,
                      onSpeech: @escaping @MainActor () -> Void,
                      onUtterance: @escaping @MainActor (MorningHandsFreeUtterance) async -> Void) {
        #if os(iOS)
        guard !isActive, !needsAudioRelease, UIApplication.shared.applicationState == .active,
              context() != nil else { return }
        let id = UUID()
        runID = id
        self.language = language
        self.languageGeneration = languageGeneration
        self.speech = speech; self.context = context; self.onSpeech = onSpeech; self.onUtterance = onUtterance
        state = .preparing; transcript = ""
        consecutiveFailures = 0
        message = AppLanguage.localized("Preparing hands-free voice…", bundle: .module)
        let precedingCleanup = cleanup
        startup = Task { [weak self] in
            guard let self else { return }
            do {
                try await precedingCleanup?.value
                try checkCurrent(id)
                try requirePreparedPermissions(language: language)
                // The microphone owner holds one shared duplex session while TTS
                // starts, pauses and finishes; TTS must not deactivate it mid-turn.
                speech.handsFreeAudioSessionIsOwned = true
                needsAudioRelease = true
                guard try await audioSession.prepare(for: id).value else { throw CancellationError() }
                try checkCurrent(id)
                try startInput()
                observeInterruptions(id: id)
                beginRecognition(id: id)
            } catch {
                guard runID == id else { return }
                let reason = (error as? MorningVoiceListeningError)?.moreDescription
                    ?? AppLanguage.localized("Hands-free voice is unavailable. Your morning controls remain available.", bundle: .module)
                stop(finalState: .unavailable, finalMessage: reason)
            }
        }
        #else
        state = .unavailable
        message = AppLanguage.localized("Hands-free microphone input requires an iPhone.", bundle: .module)
        #endif
    }

    /// Invalidation is synchronous: a late result cannot survive stop/background.
    public func stop() { stop(finalState: .idle, finalMessage: AppLanguage.localized("Voice is off.", bundle: .module)) }

    public func stopAndRelease() async throws {
        stop()
        #if os(iOS)
        try await cleanup?.value
        #endif
    }

    private func stop(finalState: MorningHandsFreeVoiceState, finalMessage: String) {
        transcript = ""; interruptedRunningSession = false; momentContext = ""; continuation.invalidate()
        transcriptRevision &+= 1
        #if os(iOS)
        runID = nil; recognitionID = nil; turn.cancel()
        startup?.cancel(); processing?.cancel(); processing = nil
        silenceDeadline?.cancel(); turnDeadline?.cancel(); finalDeadline?.cancel()
        silenceDeadline = nil; turnDeadline = nil; finalDeadline = nil
        for task in notificationTasks { task.cancel() }
        notificationTasks.removeAll()
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        sink.endAudio(); recognitionTask?.cancel(); recognitionTask = nil; recognizer = nil
        echoOutput = nil; context = nil; onSpeech = nil; onUtterance = nil
        let pendingStartup = startup; startup = nil
        let previousCleanup = cleanup
        let output = speech
        let release = audioSession.cancel()
        state = finalState; message = finalMessage
        cleanup = Task { [weak self] in
            guard let self else { return }
            _ = try? await previousCleanup?.value
            await pendingStartup?.value
            do {
                if output?.handsFreeAudioSessionIsOwned == true { try await output?.stopAndRelease() }
                try await release.task.value
                guard runID == nil else { return }
                output?.setHandsFreeOutput(nil)
                output?.handsFreeAudioSessionIsOwned = false
                needsAudioRelease = false
            } catch {
                needsAudioRelease = true; state = .failed
                message = AppLanguage.localized("The microphone could not be released. Stop voice again before continuing.", bundle: .module)
                throw error
            }
        }
        #else
        state = finalState; message = finalMessage
        #endif
    }

    #if os(iOS)
    private func checkCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        guard runID == id, UIApplication.shared.applicationState != .background else { throw CancellationError() }
    }

    private func requirePreparedPermissions(language: MorningVoiceCommandLanguage) throws {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else { throw MorningVoiceListeningError.speechDenied }
        guard AVAudioApplication.shared.recordPermission == .granted else { throw MorningVoiceListeningError.microphoneDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)), recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else { throw MorningVoiceListeningError.onDeviceUnavailable }
        self.recognizer = recognizer
    }

    private func startInput() throws {
        let input = engine.inputNode
        // Without voice processing, synthesized output could be recognized as the
        // user's own authorization. Fail closed if duplex echo cancellation fails.
        try input.setVoiceProcessingEnabled(true)
        guard input.isVoiceProcessingEnabled, !input.isVoiceProcessingBypassed else {
            throw MorningVoiceListeningError.unavailable
        }
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw MorningVoiceListeningError.unavailable }
        let sink = sink
        // The framework invokes this on its audio thread. An untyped closure
        // here inherits MainActor and traps before its body under Swift 6.
        let audioTap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [sink] buffer, _ in sink.append(buffer) }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: audioTap)
        hasTap = true
        speech?.setHandsFreeOutput(try MorningDuplexSpeechOutput(engine: engine))
        engine.prepare()
        try engine.start()
    }

    private func beginRecognition(id: UUID) {
        guard runID == id, let recognizer, recognizer.isAvailable else {
            if runID == id { stop(finalState: .unavailable, finalMessage: MorningVoiceListeningError.unavailable.moreDescription) }
            return
        }
        recognitionTask?.cancel()
        turn = MorningHandsFreeVoiceTurn(languageGeneration: languageGeneration); isFinishing = false
        let recognitionID = UUID()
        self.recognitionID = recognitionID
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = true
        request.addsPunctuation = true; request.taskHint = .dictation
        request.contextualStrings = language.exampleCommands + language.exampleCommands.map { "MORE \($0)" }
        sink.replace(with: request)
        state = .listening
        message = AppLanguage.localized("Listening · You can interrupt MORE.", bundle: .module)
        let receiveResult: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal == true
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.receive(text: text, isFinal: isFinal, failed: failed, runID: id, recognitionID: recognitionID)
            }
        }
        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: receiveResult)
        turnDeadline?.cancel()
        turnDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(45)) } catch { return }
            guard let self, self.runID == id, self.recognitionID == recognitionID else { return }
            finishInput(runID: id, recognitionID: recognitionID)
        }
    }

    private func receive(text: String?, isFinal: Bool, failed: Bool, runID id: UUID, recognitionID: UUID) {
        guard runID == id, self.recognitionID == recognitionID else { return }
        guard UIApplication.shared.applicationState == .active else { stop(); return }
        if failed {
            // Silence at the bounded recognition-window end is expected; a failure
            // during actual speech must not dispatch its partial transcription.
            if !isFinishing {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    stop(finalState: .unavailable, finalMessage: MorningVoiceListeningError.unavailable.moreDescription)
                    return
                }
            }
            finishTurn(nil, id: id, recognitionID: recognitionID)
            return
        }
        guard let text, !text.isEmpty else { return }
        if let output = speech?.currentText { echoOutput = output; echoOutputAt = Date() }
        let echo = Date().timeIntervalSince(echoOutputAt) < 1.5 ? echoOutput : nil
        let acousticDuplex = engine.isRunning && engine.inputNode.isVoiceProcessingEnabled &&
            !engine.inputNode.isVoiceProcessingBypassed && speech?.usesDuplexPlayback == true
        if turn.context == nil, MorningHandsFreeVoicePolicy.isOutputEcho(text, output: echo,
            acousticDuplexIsActive: acousticDuplex) {
            if isFinal { finishTurn(nil, id: id, recognitionID: recognitionID) }
            return
        }
        if turn.context == nil {
            guard let current = context?() else { stop(); return }
            processing?.cancel(); processing = nil
            consecutiveFailures = 0
            turn.begin(in: current)
            onSpeech?()
        }
        transcript = String(text.prefix(4_000))
        transcriptRevision &+= 1
        if isFinal {
            finishTurn(turn.accept(text, isFinal: true), id: id, recognitionID: recognitionID)
        } else if !isFinishing {
            silenceDeadline?.cancel()
            silenceDeadline = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(1.1)) } catch { return }
                guard let self, self.runID == id, self.recognitionID == recognitionID else { return }
                finishInput(runID: id, recognitionID: recognitionID)
            }
        }
    }

    private func finishInput(runID id: UUID, recognitionID: UUID) {
        guard !isFinishing else { return }
        isFinishing = true; sink.endAudio(); recognitionTask?.finish()
        finalDeadline?.cancel()
        finalDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.runID == id, self.recognitionID == recognitionID else { return }
            finishTurn(nil, id: id, recognitionID: recognitionID)
        }
    }

    private func finishTurn(_ utterance: MorningHandsFreeUtterance?, id: UUID, recognitionID: UUID) {
        guard runID == id, self.recognitionID == recognitionID else { return }
        let missedSpeech = utterance == nil && turn.context != nil
        self.recognitionID = nil; turn.cancel()
        sink.endAudio(); recognitionTask?.cancel(); recognitionTask = nil
        silenceDeadline?.cancel(); turnDeadline?.cancel(); finalDeadline?.cancel()
        // Start listening again before interpretation/speech, so the next utterance
        // can interrupt an answer without tapping or opening a sheet.
        beginRecognition(id: id)
        if missedSpeech {
            speech?.speak(AppLanguage.localized("I couldn't hear that clearly. Please say it again.", bundle: .module))
        }
        guard let utterance, let onUtterance else { return }
        processing?.cancel()
        processing = Task { [weak self] in
            guard let self, runID == id else { return }
            await onUtterance(utterance)
        }
    }

    private func observeInterruptions(id: UUID) {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
                     UIApplication.didEnterBackgroundNotification] {
            notificationTasks.append(Task { [weak self] in
                let reasons = NotificationCenter.default.notifications(named: name)
                    .map { $0.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt ?? 0 }
                for await reason in reasons {
                    guard !Task.isCancelled, let self, runID == id else { return }
                    if name == AVAudioSession.routeChangeNotification,
                       reason == AVAudioSession.RouteChangeReason.categoryChange.rawValue { continue }
                    stop(finalState: .idle, finalMessage: AppLanguage.localized("Voice paused after an interruption. Resume your morning to listen again.", bundle: .module))
                    return
                }
            })
        }
    }

    private static func activateMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw MorningVoiceListeningError.unavailable }
        } else { try session.setActive(true) }
    }

    private static func releaseMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            guard try await session.deactivate(options: .notifyOthersOnDeactivation) else { throw MorningVoiceListeningError.unavailable }
        } else { try session.setActive(false, options: .notifyOthersOnDeactivation) }
    }
    #endif
}

#if os(iOS)
private final class HandsFreeAudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    func replace(with request: SFSpeechAudioBufferRecognitionRequest) {
        lock.lock(); defer { lock.unlock() }
        self.request?.endAudio(); self.request = request
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        request?.append(buffer)
    }
    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        request?.endAudio(); request = nil
    }
}
#endif
