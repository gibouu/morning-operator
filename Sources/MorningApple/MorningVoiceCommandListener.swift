import Foundation
import MorningCore
import Observation
#if os(iOS)
import AVFAudio
import Speech
import UIKit
#endif

public enum MorningVoiceListeningState: String, Sendable {
    case idle, requestingPermission, preparing, listening, finishing, unavailable, failed
}

public enum MorningVoiceListeningError: LocalizedError, Sendable, Equatable {
    case alreadyListening, microphoneDenied, speechDenied, onDeviceUnavailable, unavailable
    case unrecognized, timedOut, audio(String)
    case captureMicrophoneDenied, captureSpeechDenied, captureOnDeviceUnavailable, captureUnavailable, captureTimedOut

    public var errorDescription: String? {
        switch self {
        case .alreadyListening: String(localized: "Finish or cancel the current listening turn first.", bundle: .module)
        case .microphoneDenied: String(localized: "Microphone access is off. Use the routine buttons, or enable access in Settings.", bundle: .module)
        case .speechDenied: String(localized: "Speech recognition is unavailable or not allowed. You can still use the routine buttons.", bundle: .module)
        case .onDeviceUnavailable: String(localized: "On-device recognition is not available for this language. Use the routine buttons; audio will not be sent to a server.", bundle: .module)
        case .unavailable: String(localized: "Voice commands are not available here right now. Use the routine buttons.", bundle: .module)
        case .unrecognized: String(localized: "That was not one clear command. Try next, pause, resume, skip, repeat or stop.", bundle: .module)
        case .timedOut: String(localized: "No final command was received. Nothing was changed. Try again or use the routine buttons.", bundle: .module)
        case .audio(let reason): String(localized: "Listening could not finish safely: \(reason)", bundle: .module)
        case .captureMicrophoneDenied: String(localized: "Microphone access is off. Type your thought, or enable access in Settings.", bundle: .module)
        case .captureSpeechDenied: String(localized: "Speech recognition is unavailable or not allowed. You can still type your thought.", bundle: .module)
        case .captureOnDeviceUnavailable: String(localized: "On-device dictation is not available for this language. Type your thought; audio will not be sent to a server.", bundle: .module)
        case .captureUnavailable: String(localized: "Spoken capture is not available here right now. You can still type your thought.", bundle: .module)
        case .captureTimedOut: String(localized: "No final capture was received. Nothing was saved. Try again or type your thought.", bundle: .module)
        }
    }
}

/// One user-initiated, on-device microphone turn. The caller first pauses its routine,
/// cancels automation and awaits SpeechCoordinator.stopAndRelease(). Returned commands
/// have no effect until the caller verifies their pinned context and dispatches them.
/// Dictation returns plain text for review through a separate, pinned mode; a captured
/// word such as "stop" is never routed through the routine-command parser.
@MainActor
@Observable
public final class MorningVoiceCommandListener {
    private enum TurnPurpose: Sendable {
        case command(MorningVoiceCommandContext), capture
        var isCapture: Bool { if case .capture = self { true } else { false } }
    }

    private enum TurnResult: Sendable {
        case command(MorningVoiceCommandEnvelope), capture(String)
    }

    public private(set) var state: MorningVoiceListeningState = .idle
    public private(set) var transcript = ""
    public private(set) var message = String(localized: "Tap to say one command.", bundle: .module)
    public private(set) var inputRouteName: String?
    /// Playback must remain blocked until microphone ownership has been released.
    public private(set) var needsAudioRelease = false
    public var isBusy: Bool {
        switch state {
        case .requestingPermission, .preparing, .listening, .finishing: true
        default: false
        }
    }

    #if os(iOS)
    @ObservationIgnored private var activeTurnID: UUID?
    @ObservationIgnored private var finishingTurnID: UUID?
    @ObservationIgnored private var cancelledTurnID: UUID?
    @ObservationIgnored private var awaitingResultTurnID: UUID?
    @ObservationIgnored private var turn: MorningVoiceCommandTurn?
    @ObservationIgnored private var captureTurn: MorningCaptureTurn?
    @ObservationIgnored private var purpose: TurnPurpose?
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var sink: CommandAudioBufferSink?
    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private var hasTap = false
    @ObservationIgnored private var inputRouteIDs: [String] = []
    @ObservationIgnored private var pending: CheckedContinuation<TurnResult, any Error>?
    @ObservationIgnored private var captureDeadline: Task<Void, Never>?
    @ObservationIgnored private var finalDeadline: Task<Void, Never>?
    @ObservationIgnored private var shutdownTask: Task<Void, any Error>?
    @ObservationIgnored private var shutdownTaskID: UUID?
    @ObservationIgnored private var routeTask: Task<Void, Never>?
    @ObservationIgnored private var interruptionTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: Task<Void, Never>?
    @ObservationIgnored private lazy var audioSession = SpeechAudioSessionGate(
        activate: { try await Self.activateMicrophone() },
        deactivate: { try await Self.releaseMicrophone() }
    )
    #endif

    public init() {
        #if os(iOS)
        routeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
                guard !Task.isCancelled else { return }
                guard let self, self.state == .listening,
                      self.inputRouteIDs != AVAudioSession.sharedInstance().currentRoute.inputs.map(\.uid) else { continue }
                try? await self.cancel()
            }
        }
        interruptionTask = Task { [weak self] in
            let types = NotificationCenter.default.notifications(named: AVAudioSession.interruptionNotification)
                .compactMap { $0.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt }
            for await type in types {
                guard !Task.isCancelled else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue { try? await self?.cancel() }
            }
        }
        backgroundTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UIApplication.didEnterBackgroundNotification) {
                guard !Task.isCancelled else { return }
                try? await self?.cancel()
            }
        }
        #endif
    }

    deinit {
        #if os(iOS)
        captureDeadline?.cancel(); finalDeadline?.cancel()
        routeTask?.cancel(); interruptionTask?.cancel(); backgroundTask?.cancel()
        #endif
    }

    /// Requests permissions only in response to this call. Captures for at most eight
    /// seconds, then allows three seconds for the recognizer's final whole-turn result.
    /// Never persists audio or a transcript and never falls back to server recognition.
    public func listen(context: MorningVoiceCommandContext,
                       language: MorningVoiceCommandLanguage = .english) async throws -> MorningVoiceCommandEnvelope {
        let result = try await performTurn(purpose: .command(context), language: language)
        guard case .command(let command) = result else { throw MorningVoiceListeningError.unrecognized }
        return command
    }

    /// One explicit on-device dictation turn: up to thirty seconds of input and three
    /// seconds for a final result. Returns at most 4,000 Characters for caller-owned review;
    /// it never executes a command, persists a transcript or starts a new listening turn.
    public func dictate(language: MorningVoiceCommandLanguage = .english) async throws -> String {
        let result = try await performTurn(purpose: .capture, language: language)
        try Task.checkCancellation()
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
        #endif
        guard case .capture(let text) = result else { throw MorningVoiceListeningError.captureUnavailable }
        return text
    }

    private func performTurn(purpose: TurnPurpose, language: MorningVoiceCommandLanguage) async throws -> TurnResult {
        guard !isBusy else { throw MorningVoiceListeningError.alreadyListening }
        guard !needsAudioRelease else {
            throw MorningVoiceListeningError.audio(String(localized: "Microphone release is still unconfirmed. Retry stopping listening before starting another turn.", bundle: .module))
        }
        #if os(iOS)
        guard awaitingResultTurnID == nil else { throw MorningVoiceListeningError.alreadyListening }
        try Task.checkCancellation()
        guard UIApplication.shared.applicationState == .active else { throw CancellationError() }
        let id = UUID()
        switch purpose {
        case .command(let context):
            turn = MorningVoiceCommandTurn(id: id, context: context); captureTurn = nil
        case .capture:
            turn = nil; captureTurn = MorningCaptureTurn(id: id)
        }
        self.purpose = purpose
        activeTurnID = id; awaitingResultTurnID = id
        defer {
            if awaitingResultTurnID == id { awaitingResultTurnID = nil }
        }
        cancelledTurnID = nil
        transcript = ""; inputRouteName = nil
        state = .requestingPermission; message = String(localized: "Checking microphone and speech access…", bundle: .module)
        return try await withTaskCancellationHandler {
            do {
                try await requestPermissionsAndRecognizer(language: language, id: id)
                try checkCurrent(id)
                state = .preparing; message = String(localized: "Preparing the microphone…", bundle: .module)
                needsAudioRelease = true
                let prepared = try await audioSession.prepare(for: id).value
                try checkCurrent(id)
                guard prepared else { throw CancellationError() }
                let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TurnResult, any Error>) in
                    pending = continuation
                    do { try beginCapture(id: id, language: language) }
                    catch { _ = completeTurn(id: id, result: .failure(error)) }
                }
                try Task.checkCancellation()
                guard cancelledTurnID != id, UIApplication.shared.applicationState == .active else {
                    if purpose.isCapture { transcript = "" }
                    throw CancellationError()
                }
                // The returned value now belongs to caller-owned review. Keep no
                // second copy on this shared listener after the capture handoff.
                if purpose.isCapture { transcript = "" }
                return result
            } catch {
                if purpose.isCapture, awaitingResultTurnID == id { transcript = "" }
                let failure = listeningError(error, purpose: purpose)
                // Also handles permission/setup failures before a continuation exists.
                if let cleanup = completeTurn(id: id, result: .failure(failure)) {
                    try await cleanup.value
                }
                throw failure
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.awaitingResultTurnID == id else { return }
                try? await self.cancel()
            }
        }
        #else
        let error: MorningVoiceListeningError = purpose.isCapture ? .captureUnavailable : .unavailable
        state = .unavailable; message = error.localizedDescription
        throw error
        #endif
    }

    /// End input but allow its final recognition result. Cancel is a separate operation.
    public func finishListening() {
        #if os(iOS)
        guard state == .listening, let id = activeTurnID else { return }
        captureDeadline?.cancel(); captureDeadline = nil
        stopAudioInput()
        let isCapture = purpose?.isCapture == true
        state = .finishing; message = isCapture ? String(localized: "Finishing your capture…", bundle: .module) : String(localized: "Understanding your command…", bundle: .module)
        recognitionTask?.finish()
        finalDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard let self, self.activeTurnID == id else { return }
            let error: MorningVoiceListeningError = isCapture ? .captureTimedOut : .timedOut
            _ = self.completeTurn(id: id, result: .failure(error))
        }
        #endif
    }

    /// Invalidates late callbacks before releasing the microphone. Repeated cancellation
    /// awaits the same cleanup; a release failure is surfaced rather than claiming success.
    public func cancel() async throws {
        #if os(iOS)
        // A final result can be waiting for its caller while microphone release is
        // finishing. Cancellation still invalidates that result before delivery.
        if let awaitingResultTurnID { cancelledTurnID = awaitingResultTurnID }
        transcript = ""
        if let id = activeTurnID {
            cancelledTurnID = id
            if let cleanup = completeTurn(id: id, result: .failure(CancellationError())) { try await cleanup.value }
        } else if needsAudioRelease, state != .finishing {
            // A previous release failure remains a real ownership problem. Retrying
            // cleanup never activates the microphone or starts a recognition turn.
            state = .finishing; message = String(localized: "Releasing the microphone…", bundle: .module)
            let retryID = UUID()
            shutdownTaskID = retryID
            let retry = Task { @MainActor [self] in
                defer { clearFinishedShutdown(id: retryID) }
                do {
                    try await audioSession.cancelAndWait()
                    needsAudioRelease = false
                    state = .idle; message = String(localized: "Microphone released.", bundle: .module)
                } catch {
                    state = .failed
                    message = MorningVoiceListeningError.audio(error.localizedDescription).localizedDescription
                    throw error
                }
            }
            shutdownTask = retry
            try await retry.value
        } else if let shutdownTask {
            if let finishingTurnID { cancelledTurnID = finishingTurnID }
            try await shutdownTask.value
        }
        #endif
    }

    #if os(iOS)
    private func requestPermissionsAndRecognizer(language: MorningVoiceCommandLanguage, id: UUID) async throws {
        try checkCurrent(id)
        var authorization = SFSpeechRecognizer.authorizationStatus()
        if authorization == .notDetermined {
            let raw = await withCheckedContinuation { continuation in
                let completion: @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void = { status in
                    continuation.resume(returning: status.rawValue)
                }
                SFSpeechRecognizer.requestAuthorization(completion)
            }
            authorization = SFSpeechRecognizerAuthorizationStatus(rawValue: raw) ?? .denied
        }
        try checkCurrent(id)
        guard authorization == .authorized else { throw MorningVoiceListeningError.speechDenied }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable else { throw MorningVoiceListeningError.unavailable }
        let actualLanguage = recognizer.locale.identifier.replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-").first
        let expectedLanguage = language.localeIdentifier.components(separatedBy: "-").first
        guard actualLanguage == expectedLanguage, recognizer.supportsOnDeviceRecognition else {
            throw MorningVoiceListeningError.onDeviceUnavailable
        }
        var granted = AVAudioApplication.shared.recordPermission == .granted
        if AVAudioApplication.shared.recordPermission == .undetermined {
            granted = await withCheckedContinuation { continuation in
                let completion: @Sendable (Bool) -> Void = { value in continuation.resume(returning: value) }
                AVAudioApplication.requestRecordPermission(completionHandler: completion)
            }
        }
        try checkCurrent(id)
        guard granted else { throw MorningVoiceListeningError.microphoneDenied }
        self.recognizer = recognizer
    }

    private func checkCurrent(_ id: UUID) throws {
        try Task.checkCancellation()
        // Native permission sheets can briefly make the app inactive. Backgrounding
        // invalidates setup; final delivery separately requires the active foreground.
        guard activeTurnID == id, UIApplication.shared.applicationState != .background else { throw CancellationError() }
    }

    private func beginCapture(id: UUID, language: MorningVoiceCommandLanguage) throws {
        try checkCurrent(id)
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            throw MorningVoiceListeningError.onDeviceUnavailable
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let isCapture = purpose?.isCapture == true
        request.addsPunctuation = isCapture
        request.taskHint = isCapture ? .dictation : .confirmation
        if !isCapture {
            request.contextualStrings = language.exampleCommands + language.exampleCommands.map { "MORE \($0)" }
        }
        let sink = CommandAudioBufferSink(request: request)
        self.sink = sink
        let receiveResult: @Sendable (SFSpeechRecognitionResult?, (any Error)?) -> Void = { [weak self] result, error in
            // Only send value types across the framework callback's executor boundary.
            let hypothesis = result.map { CommandHypothesis(text: $0.bestTranscription.formattedString,
                isFinal: $0.isFinal, alternatives: $0.transcriptions.map(\.formattedString)) }
            let failure = error?.localizedDescription
            Task { @MainActor [weak self] in self?.receive(hypothesis, error: failure, id: id) }
        }
        recognitionTask = recognizer.recognitionTask(with: request, resultHandler: receiveResult)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            throw MorningVoiceListeningError.audio(String(localized: "No microphone input is available.", bundle: .module))
        }
        let audioTap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { [sink] buffer, _ in sink.append(buffer) }
        input.installTap(onBus: 0, bufferSize: 1_024, format: format, block: audioTap)
        hasTap = true
        engine.prepare()
        try engine.start()
        let route = AVAudioSession.sharedInstance().currentRoute
        inputRouteIDs = route.inputs.map(\.uid)
        inputRouteName = route.inputs.map(\.portName).joined(separator: ", ")
        state = .listening
        message = isCapture ? String(localized: "Listening to your thought… Tap Done when you finish.", bundle: .module) : String(localized: "Listening for one command…", bundle: .module)
        captureDeadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(isCapture ? 30 : 8)) } catch { return }
            guard let self, self.activeTurnID == id else { return }
            self.finishListening()
        }
    }

    private func receive(_ hypothesis: CommandHypothesis?, error: String?, id: UUID) {
        guard activeTurnID == id else { return }
        guard UIApplication.shared.applicationState == .active else {
            cancelledTurnID = id
            _ = completeTurn(id: id, result: .failure(CancellationError()))
            return
        }
        if let error {
            _ = completeTurn(id: id, result: .failure(MorningVoiceListeningError.audio(error)))
            return
        }
        guard let hypothesis else { return }
        let isCapture = purpose?.isCapture == true
        transcript = isCapture ? String(hypothesis.text.prefix(MorningCaptureTurn.maximumCharacters)) : hypothesis.text
        guard hypothesis.isFinal else { return }
        if isCapture {
            do {
                guard let text = try captureTurn?.accept(transcript: hypothesis.text, isFinal: true) else {
                    throw CancellationError()
                }
                transcript = text
                _ = completeTurn(id: id, result: .success(.capture(text)))
            } catch { _ = completeTurn(id: id, result: .failure(error)) }
        } else if let envelope = turn?.accept(transcript: hypothesis.text, isFinal: true, alternatives: hypothesis.alternatives) {
            _ = completeTurn(id: id, result: .success(.command(envelope)))
        } else {
            _ = completeTurn(id: id, result: .failure(MorningVoiceListeningError.unrecognized))
        }
    }

    private func stopAudioInput() {
        engine.stop()
        if hasTap { engine.inputNode.removeTap(onBus: 0); hasTap = false }
        sink?.endAudio()
    }

    @discardableResult
    private func completeTurn(id: UUID, result: Result<TurnResult, any Error>) -> Task<Void, any Error>? {
        guard activeTurnID == id else { return nil }
        let completedPurpose = purpose
        activeTurnID = nil; turn?.cancel(); captureTurn?.cancel()
        turn = nil; captureTurn = nil; purpose = nil
        finishingTurnID = id
        state = .finishing
        captureDeadline?.cancel(); captureDeadline = nil
        finalDeadline?.cancel(); finalDeadline = nil
        stopAudioInput()
        recognitionTask?.cancel(); recognitionTask = nil
        sink = nil; recognizer = nil
        let continuation = pending; pending = nil
        shutdownTaskID = id
        let cleanup = Task { @MainActor [self] in
            defer { clearFinishedShutdown(id: id) }
            var outcome = result.mapError { listeningError($0, purpose: completedPurpose) }
            var releaseFailure: (any Error)?
            do {
                try await audioSession.cancelAndWait()
                needsAudioRelease = false
            }
            catch {
                releaseFailure = error
                outcome = .failure(MorningVoiceListeningError.audio(error.localizedDescription))
            }
            if releaseFailure == nil,
               cancelledTurnID == id || UIApplication.shared.applicationState != .active {
                outcome = .failure(CancellationError())
            }
            finishingTurnID = nil
            switch outcome {
            case .success(.command(let command)):
                state = .idle; message = String(localized: "Heard: \(command.transcript)", bundle: .module)
            case .success(.capture):
                state = .idle; message = String(localized: "Your words are ready to review. Nothing has been saved.", bundle: .module)
            case .failure(let error):
                if completedPurpose?.isCapture == true || error is CancellationError { transcript = "" }
                if error is CancellationError { state = .idle; message = String(localized: "Listening stopped.", bundle: .module) }
                else {
                    switch error as? MorningVoiceListeningError {
                    case .microphoneDenied, .speechDenied, .onDeviceUnavailable, .unavailable,
                         .captureMicrophoneDenied, .captureSpeechDenied, .captureOnDeviceUnavailable, .captureUnavailable:
                        state = .unavailable
                    default: state = .failed
                    }
                    message = error.localizedDescription
                }
            }
            continuation?.resume(with: outcome)
            if let releaseFailure { throw releaseFailure }
        }
        shutdownTask = cleanup
        return cleanup
    }

    /// Drop the completed closure (which captured its recognition result) without
    /// touching a replacement cleanup. Existing waiters keep their own task handle.
    private func clearFinishedShutdown(id: UUID) {
        guard shutdownTaskID == id else { return }
        shutdownTask = nil
        shutdownTaskID = nil
    }

    private func listeningError(_ error: any Error, purpose: TurnPurpose?) -> any Error {
        guard purpose?.isCapture == true, let error = error as? MorningVoiceListeningError else { return error }
        switch error {
        case .microphoneDenied: return MorningVoiceListeningError.captureMicrophoneDenied
        case .speechDenied: return MorningVoiceListeningError.captureSpeechDenied
        case .onDeviceUnavailable: return MorningVoiceListeningError.captureOnDeviceUnavailable
        case .unavailable: return MorningVoiceListeningError.captureUnavailable
        case .timedOut: return MorningVoiceListeningError.captureTimedOut
        default: return error
        }
    }

    private static func activateMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [])
        if #available(iOS 27.0, *) {
            guard try await session.activate(options: []) else { throw MorningVoiceListeningError.audio(String(localized: "The microphone session did not activate.", bundle: .module)) }
        } else { try session.setActive(true) }
    }

    private static func releaseMicrophone() async throws {
        let session = AVAudioSession.sharedInstance()
        if #available(iOS 27.0, *) {
            guard try await session.deactivate(options: .notifyOthersOnDeactivation) else {
                throw MorningVoiceListeningError.audio(String(localized: "Microphone audio release was not confirmed.", bundle: .module))
            }
        } else { try session.setActive(false, options: .notifyOthersOnDeactivation) }
    }
    #endif
}

#if os(iOS)
private struct CommandHypothesis: Sendable {
    let text: String
    let isFinal: Bool
    let alternatives: [String]
}

/// AVAudioEngine invokes its tap outside the main actor. This small locked sink is the
/// only cross-executor owner of the request's append/endAudio boundary; no audio is saved.
private final class CommandAudioBufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private let request: SFSpeechAudioBufferRecognitionRequest
    private var ended = false
    init(request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        request.append(buffer)
    }
    func endAudio() {
        lock.lock(); defer { lock.unlock() }
        guard !ended else { return }
        ended = true
        request.endAudio()
    }
}
#endif
