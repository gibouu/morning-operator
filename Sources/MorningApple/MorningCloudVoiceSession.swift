import Foundation
import Observation
import MorningCore

public enum MorningCloudVoiceState: String, Sendable { case off, connecting, listening, speaking, failed }
public enum MorningCloudVoiceControl: String, Sendable, CaseIterable {
    case pause, resume, next, skip, stop, extendTwoMinutes = "extend_two_minutes"
}

/// Routine metadata only. Health, inbox contents and recordings are never included here.
public struct MorningCloudVoiceContext: Sendable, Equatable, Encodable {
    public let sessionID: UUID?
    public let routineVersionID: UUID?
    public let stepID: UUID?
    public let stepTitle: String
    public let sessionState: String
    private enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", routineVersionID = "routine_version_id", stepID = "step_id"
        case stepTitle = "step_title", sessionState = "session_state"
    }

    public init(binding: MorningVoiceCommandContext?, stepTitle: String = "", sessionState: String = "") {
        sessionID = binding?.sessionID; routineVersionID = binding?.routineVersionID; stepID = binding?.stepID
        self.stepTitle = String(stepTitle.prefix(200)); self.sessionState = String(sessionState.prefix(40))
    }
    public var binding: MorningVoiceCommandContext? {
        guard let sessionID, let routineVersionID, let stepID else { return nil }
        return .init(sessionID: sessionID, routineVersionID: routineVersionID, stepID: stepID)
    }
    public var encoded: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data("{}".utf8), as: UTF8.self)
    }
}

public struct MorningCloudVoiceToolCall: Sendable, Equatable {
    public let id: String
    public let name: String
    public let parametersJSON: String
    public let eventID: Int
    public init(id: String, name: String, parametersJSON: String, eventID: Int = 0) {
        self.id = id; self.name = name; self.parametersJSON = parametersJSON; self.eventID = eventID
    }
}

public enum MorningCloudVoiceEvent: Sendable {
    case listening, speaking, agentText(String), userText(String, eventID: Int = 0), interruption
    /// Display-only local recognition; never authorizes tools or personal-memory writes.
    case userTranscriptPreview(String)
    case tool(MorningCloudVoiceToolCall)
    case ended, failed
}

/// The SDK stays in the app target; tests inject a transport that never opens a microphone.
@MainActor public protocol MorningCloudVoiceTransport: AnyObject {
    var onEvent: (@MainActor (MorningCloudVoiceEvent) -> Void)? { get set }
    func connect(token: String, language: String, voiceGender: MorningVoiceGender) async throws
    func updateContext(_ context: String) async throws
    func sendUserMessage(_ text: String) async throws
    func reply(to callID: String, result: String, isError: Bool) async throws
    func suspendReply()
    func cancelPlayback()
    func stop() async
}

public enum MorningCloudVoiceError: Error, Sendable { case consentRequired, invalidToken, unavailable }

/// One explicitly chosen cloud conversation owns audio until stop/background/Forget.
@MainActor @Observable
public final class MorningCloudVoiceSession {
    public private(set) var state: MorningCloudVoiceState = .off
    public private(set) var caption: String?
    /// Temporary display text. Only `transcript` contains the provider's final turn.
    public private(set) var userCaption: String?
    public private(set) var transcript: String?
    public private(set) var userTurnID: UUID?
    public private(set) var errorMessage: String?
    public var isActive: Bool { state == .connecting || state == .listening || state == .speaking }
    @ObservationIgnored public var onInterruption: (@MainActor () -> Void)?
    /// Only microphone transcripts enter here. Nil invalidates an oversized/empty
    /// turn without retaining its text; agent responses and app narrations never enter.
    @ObservationIgnored public var onUserText: (@MainActor (String?, UUID) -> Void)?

    public typealias TokenProvider = @MainActor () async throws -> String
    public typealias ControlHandler = @MainActor (MorningCloudVoiceControl, MorningVoiceCommandContext) async throws -> String
    public typealias RequestHandler = @MainActor (String, MorningVoiceCommandContext) -> Bool
    @ObservationIgnored private let tokenProvider: TokenProvider
    @ObservationIgnored private let makeTransport: @MainActor () -> any MorningCloudVoiceTransport
    @ObservationIgnored private let control: ControlHandler
    @ObservationIgnored private let request: RequestHandler?
    @ObservationIgnored private var transport: (any MorningCloudVoiceTransport)?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?
    @ObservationIgnored private var cleanupTask: Task<Void, Never>?
    @ObservationIgnored private var toolTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var replies: [String: (String, Bool)] = [:]
    @ObservationIgnored private var context = MorningCloudVoiceContext(binding: nil)
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var french = false
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let narrationTimeout: Duration
    @ObservationIgnored private var narrationID: UUID?
    @ObservationIgnored private var narration: CheckedContinuation<Void, any Error>?
    @ObservationIgnored private var narrationSendTask: Task<Void, Never>?
    @ObservationIgnored private var narrationTimer: Task<Void, Never>?
    @ObservationIgnored private var narrationMarker: MorningCloudVoiceToolCall?
    @ObservationIgnored private var narrationSpoke = false
    @ObservationIgnored private var narrationStopped = false
    @ObservationIgnored private var narrationFinishing = false
    @ObservationIgnored private var lastUserEventID: Int?
    @ObservationIgnored private var userEventReceipts: [Int: (String, Bool)] = [:]
    @ObservationIgnored private var awaitingAppResponse = false

    public init(tokenProvider: @escaping TokenProvider,
                makeTransport: @escaping @MainActor () -> any MorningCloudVoiceTransport,
                control: @escaping ControlHandler,
                request: RequestHandler? = nil,
                clock: any Clock<Duration> = ContinuousClock(), narrationTimeout: Duration = .seconds(120)) {
        self.tokenProvider = tokenProvider; self.makeTransport = makeTransport; self.control = control
        self.request = request
        self.clock = clock; self.narrationTimeout = narrationTimeout
    }

    /// Only call after the cloud audio purpose and selected context have been explained.
    public func start(context: MorningCloudVoiceContext, language: String, consented: Bool,
                      voiceGender: MorningVoiceGender = .female) async {
        stop()
        french = language.hasPrefix("fr")
        guard consented else { fail(.consentRequired); return }
        self.context = context
        let id = UUID(); attempt = id; state = .connecting; errorMessage = nil
        let priorCleanup = cleanupTask
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                await priorCleanup?.value
                try check(id)
                let token = try await tokenProvider()
                try check(id)
                guard (16...16_384).contains(token.utf8.count), !token.contains(where: \.isWhitespace) else {
                    throw MorningCloudVoiceError.invalidToken
                }
                let client = makeTransport()
                transport = client
                client.onEvent = { [weak self] event in self?.receive(event, attempt: id) }
                try await client.connect(token: token, language: language, voiceGender: voiceGender)
                try check(id)
                try await client.updateContext(self.context.encoded)
                try check(id)
                if state == .connecting { state = .listening }
            } catch {
                guard attempt == id else { return }
                if error is CancellationError { stop() }
                else { fail(.unavailable) }
            }
        }
        connectionTask = task
        await task.value
    }

    public func updateContext(_ next: MorningCloudVoiceContext) async {
        context = next
        guard let transport, state == .listening || state == .speaking else { return }
        let id = attempt
        do { try await transport.updateContext(next.encoded); try check(id) }
        catch { if attempt == id { fail(.unavailable) } }
    }

    /// The caller has separately consented to sending this approved spoken source text.
    /// A tool marker after speech AND the SDK's playback transition must agree before success.
    public func narrate(_ text: String, forUserTurn expectedTurn: UUID? = nil) async throws {
        try Task.checkCancellation()
        if let expectedTurn, !isCurrentUserTurn(expectedTurn) { throw CancellationError() }
        guard isActive, state != .connecting, let transport, !text.isEmpty,
              text.utf8.count <= 32_768 else { throw MorningCloudVoiceError.unavailable }
        userCaption = nil
        awaitingAppResponse = false
        cancelNarration()
        let id = UUID(), session = attempt
        narrationID = id; narrationSpoke = false; narrationStopped = false; narrationFinishing = false
        struct Payload: Encodable { let type = "more_approved_narration"; let narration_id: UUID; let source_text: String }
        let message = String(decoding: try JSONEncoder().encode(Payload(narration_id: id, source_text: text)), as: UTF8.self)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                narration = continuation
                narrationTimer = Task { @MainActor [weak self, clock, narrationTimeout] in
                    do { try await clock.sleep(for: narrationTimeout) } catch { return }
                    guard self?.narrationID == id else { return }
                    self?.cancelNarration(error: MorningCloudVoiceError.unavailable)
                }
                narrationSendTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        try check(session)
                        guard narrationID == id,
                              expectedTurn.map({ isCurrentUserTurn($0) }) ?? true else { throw CancellationError() }
                        try await transport.sendUserMessage(message)
                        if attempt == session, narrationID == id { narrationSendTask = nil }
                    }
                    catch {
                        guard attempt == session, narrationID == id else { return }
                        cancelNarration(error: error is CancellationError ? CancellationError() : MorningCloudVoiceError.unavailable)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.narrationID == id else { return }
                self?.cancelNarration()
            }
        }
    }

    public func cancelNarration() { cancelNarration(error: CancellationError()) }

    private func cancelNarration(error: any Error) {
        narrationSendTask?.cancel(); narrationSendTask = nil
        narrationID = nil; narrationTimer?.cancel(); narrationTimer = nil; narrationMarker = nil; narrationFinishing = false
        let waiting = narration; narration = nil
        transport?.cancelPlayback()
        waiting?.resume(throwing: error)
    }

    /// Invalidate synchronously; late tokens, speech or tool replies cannot revive this session.
    public func stop() {
        cancelNarration()
        attempt = UUID()
        let connecting = connectionTask; connectionTask = nil; connecting?.cancel()
        for task in toolTasks.values { task.cancel() }
        toolTasks = [:]; replies = [:]
        let client = transport; transport = nil; client?.onEvent = nil
        let previous = cleanupTask
        cleanupTask = Task { await previous?.value; await client?.stop(); await connecting?.value }
        caption = nil; userCaption = nil; transcript = nil; errorMessage = nil; state = .off
        lastUserEventID = nil
        userTurnID = nil
        userEventReceipts = [:]
        awaitingAppResponse = false
        context = .init(binding: nil)
    }

    /// Await before handing the microphone back to Apple's local listener.
    public func stopAndRelease() async { stop(); await cleanupTask?.value }

    public func isCurrentUserTurn(_ id: UUID) -> Bool { isActive && userTurnID == id }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard attempt == id else { throw CancellationError() }
    }

    private func receive(_ event: MorningCloudVoiceEvent, attempt id: UUID) {
        guard attempt == id else { return }
        switch event {
        case .listening:
            state = .listening
            if narrationSpoke { narrationStopped = true; finishNarrationIfReady() }
        case .speaking:
            state = .speaking
            userCaption = nil
            if narrationID != nil { narrationSpoke = true; narrationStopped = false }
        case .agentText(let text):
            if !awaitingAppResponse {
                userCaption = nil
                caption = Self.captionText(String(text.prefix(2_000)))
            }
        case .userTranscriptPreview(let text):
            userCaption = Self.boundedUserText(text)
        case .userText(let text, let eventID):
            let bounded = Self.boundedUserText(text)
            guard lastUserEventID != eventID || transcript != bounded else { return }
            if narrationID != nil { cancelNarration() }
            awaitingAppResponse = false
            transcript = bounded
            userCaption = bounded
            lastUserEventID = eventID
            let turn = UUID(); userTurnID = turn
            onUserText?(bounded, turn)
        case .interruption: caption = nil; userCaption = nil; cancelNarration(); onInterruption?()
        case .tool(let call): handle(call, attempt: id)
        case .ended: fail(.unavailable)
        case .failed: fail(.unavailable)
        }
    }

    private static func boundedUserText(_ text: String) -> String? {
        text.count <= 4_000 && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : nil
    }

    private func handle(_ call: MorningCloudVoiceToolCall, attempt id: UUID) {
        guard !call.id.isEmpty, call.id.utf8.count <= 200, toolTasks[call.id] == nil,
              let transport else { return }
        if let cached = replies[call.id] {
            Task { [weak self] in
                guard self?.attempt == id else { return }
                try? await transport.reply(to: call.id, result: cached.0, isError: cached.1)
            }
            return
        }
        guard replies.count + toolTasks.count < 256 else { fail(.unavailable); return }
        if call.name == "more_narration_complete" {
            if let values = try? JSONDecoder().decode([String: String].self, from: Data(call.parametersJSON.utf8)),
               Set(values.keys) == ["narration_id"],
               let current = narrationID, values["narration_id"].flatMap(UUID.init(uuidString:)) == current {
                narrationMarker = call; finishNarrationIfReady()
            } else {
                Task { try? await transport.reply(to: call.id, result: "This narration is no longer current.", isError: true) }
            }
            return
        }
        let binding = context.binding
        toolTasks[call.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if attempt == id { toolTasks[call.id] = nil } }
            var result = "This control is unavailable for the current morning."
            var isError = true
            if let binding, call.eventID == lastUserEventID {
                do {
                    try check(id)
                    guard context.binding == binding else { throw CancellationError() }
                    if let previous = userEventReceipts[call.eventID] {
                        (result, isError) = previous
                    } else {
                        let action = Self.control(from: call, binding: binding)
                        let requestText = transcript.flatMap { Self.request(from: call, binding: binding, transcript: $0) }
                        if action != nil || requestText != nil {
                            // Reserve before an async handler: one spoken turn cannot cause two effects.
                            userEventReceipts[call.eventID] = ("This spoken request is already pending. No additional action was applied.", false)
                            if let requestText {
                                // Close both surfaces before the app handler can start its own async work.
                                awaitingAppResponse = true; caption = nil
                                transport.suspendReply()
                                if let request, request(requestText, binding) {
                                    result = "Request accepted and pending. Wait silently for the app's next narration; no external success is confirmed."
                                    isError = false
                                }
                            } else if let action {
                                result = String(try await control(action, binding).prefix(1_000))
                                try check(id)
                                isError = false
                            }
                            userEventReceipts[call.eventID] = (result, isError)
                        }
                    }
                } catch {
                    if error is CancellationError { return }
                    result = "The control could not be completed. No success is confirmed."
                }
            }
            guard attempt == id, !Task.isCancelled else { return }
            if userEventReceipts[call.eventID] != nil { userEventReceipts[call.eventID] = (result, isError) }
            replies[call.id] = (result, isError)
            do { try await transport.reply(to: call.id, result: result, isError: isError) }
            catch { if attempt == id { fail(.unavailable) } }
        }
    }

    private func finishNarrationIfReady() {
        guard let id = narrationID, narrationSpoke, narrationStopped, !narrationFinishing,
              let marker = narrationMarker, let waiting = narration, let transport else { return }
        narrationFinishing = true
        let session = attempt
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await transport.reply(to: marker.id, result: "Playback completed. Wait silently for the next user or app request.", isError: false)
                guard attempt == session, narrationID == id else { return }
                narrationID = nil; narrationMarker = nil; narration = nil; narrationFinishing = false
                narrationTimer?.cancel(); narrationTimer = nil
                replies[marker.id] = ("Playback completed. Wait silently for the next user or app request.", false)
                waiting.resume()
            } catch {
                if attempt == session, narrationID == id { cancelNarration(error: MorningCloudVoiceError.unavailable) }
            }
        }
    }

    /// A model call proposes one bounded routine control; it cannot send mail or request source data.
    public static func control(from call: MorningCloudVoiceToolCall,
                               binding: MorningVoiceCommandContext) -> MorningCloudVoiceControl? {
        guard call.name == "more_control", call.parametersJSON.utf8.count <= 2_048,
              let values = try? JSONDecoder().decode([String: String].self, from: Data(call.parametersJSON.utf8)),
              Set(values.keys) == ["action", "session_id", "step_id"],
              values["session_id"].flatMap(UUID.init(uuidString:)) == binding.sessionID,
              values["step_id"].flatMap(UUID.init(uuidString:)) == binding.stepID,
              let name = values["action"] else { return nil }
        return MorningCloudVoiceControl(rawValue: name)
    }

    public static func request(from call: MorningCloudVoiceToolCall, binding: MorningVoiceCommandContext,
                               transcript: String) -> String? {
        guard call.name == "more_request", call.parametersJSON.utf8.count <= 20_000,
              let values = try? JSONDecoder().decode([String: String].self, from: Data(call.parametersJSON.utf8)),
              Set(values.keys) == ["request", "session_id", "step_id"],
              values["session_id"].flatMap(UUID.init(uuidString:)) == binding.sessionID,
              values["step_id"].flatMap(UUID.init(uuidString:)) == binding.stepID,
              let text = values["request"], !text.isEmpty, text.count <= 4_000, text == transcript else { return nil }
        return text
    }

    /// These two voice direction tags were returned by the configured TTS model.
    /// Other brackets remain source text, including titles and quoted data.
    public static func captionText(_ text: String) -> String {
        ["[happy]", "[slow]"].reduce(text) {
            $0.replacingOccurrences(of: $1, with: "", options: .caseInsensitive)
        }.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fail(_ error: MorningCloudVoiceError) {
        // Preserve a provider failure for the narration's recovery policy.
        // Deliberate stop, interruption and replacement remain cancellation.
        cancelNarration(error: error)
        stop(); state = .failed
        errorMessage = error == .consentRequired
            ? (french ? "Choisissez explicitement la conversation en ligne avant de démarrer." : "Choose cloud conversation explicitly before starting.")
            : (french ? "La conversation en ligne est indisponible. Réessayez ; les commandes tactiles restent disponibles." : "Cloud conversation is unavailable. Try again; touch controls remain available.")
    }
}
