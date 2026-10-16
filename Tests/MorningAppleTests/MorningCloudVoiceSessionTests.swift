import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Cloud voice lifecycle — fixture transport, no microphone or provider", .timeLimit(.minutes(1)))
@MainActor
struct MorningCloudVoiceSessionTests {
    private let binding = MorningVoiceCommandContext(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())

    @Test(arguments: MorningVoiceGender.allCases)
    func chosenGenderReachesTheTransport(voiceGender: MorningVoiceGender) async {
        let transport = CloudVoiceFixture(), session = makeSession(transport)
        await session.start(context: .init(binding: nil), language: "fr", consented: true, voiceGender: voiceGender)
        #expect(transport.voiceGender == voiceGender)
        await session.stopAndRelease()
    }

    @Test(arguments: [false, true])
    func unexpectedEndAndFailurePreserveProviderFailureForNarration(unexpectedEnd: Bool) async {
        let transport = CloudVoiceFixture(), session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let reading = Task { try await session.narrate("SYNTHETIC_APPROVED_READING") }
        await transport.waitForMessages()
        transport.emit(unexpectedEnd ? .ended : .failed)
        do {
            try await reading.value
            Issue.record("Provider failure must not complete narration.")
        } catch let error as MorningCloudVoiceError { #expect(error == .unavailable) }
        catch { Issue.record("Provider failure must remain distinguishable from deliberate cancellation.") }
        #expect(session.state == .failed)
        await session.stopAndRelease()
    }

    @Test func noCloudConnectionWithoutExplicitConsent() async {
        let transport = CloudVoiceFixture()
        var tokens = 0
        let session = MorningCloudVoiceSession(tokenProvider: { tokens += 1; return "SYNTHETIC_TOKEN_123456" },
            makeTransport: { transport }, control: { _, _ in "SYNTHETIC_RECEIPT" })
        #expect(session.state == .off && !session.isActive)
        await session.start(context: .init(binding: binding), language: "fr", consented: false)
        #expect(tokens == 0 && transport.connections == 0)
        #expect(session.state == .failed && session.errorMessage != nil)
        await session.stopAndRelease()
    }

    @Test func onePersistentConversationCarriesOnlyRoutineMetadataAndTemporaryCaptions() async throws {
        let transport = CloudVoiceFixture()
        let session = makeSession(transport)
        let context = MorningCloudVoiceContext(binding: binding, stepTitle: "SYNTHETIC_MOMENT", sessionState: "paused")
        await session.start(context: context, language: "fr", consented: true)
        #expect(session.state == .listening && transport.connections == 1)
        let metadata = try #require(transport.contexts.first)
        let keys = try JSONDecoder().decode([String: String].self, from: Data(metadata.utf8))
        #expect(Set(keys.keys) == ["session_id", "routine_version_id", "step_id", "step_title", "session_state"])
        transport.emit(.agentText("SYNTHETIC_ANSWER")); transport.emit(.userText("SYNTHETIC_QUESTION"))
        transport.emit(.speaking)
        #expect(session.caption == "SYNTHETIC_ANSWER" && session.transcript == "SYNTHETIC_QUESTION")
        #expect(session.state == .speaking)
        transport.emit(.interruption)
        #expect(session.caption == nil)
        await session.updateContext(.init(binding: binding, stepTitle: "SYNTHETIC_UPDATED_MOMENT", sessionState: "running"))
        #expect(transport.connections == 1 && transport.contexts.count == 2)
        await session.stopAndRelease()
        #expect(session.state == .off && session.caption == nil && session.transcript == nil)
        #expect(transport.stops == 1)
        transport.emit(.agentText("LATE_SYNTHETIC_RESPONSE"))
        #expect(session.caption == nil)
    }

    @Test func stoppedTokenRequestCannotConnectLater() async {
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate()
        let session = MorningCloudVoiceSession(tokenProvider: { await gate.value(); return "SYNTHETIC_TOKEN_123456" },
            makeTransport: { transport }, control: { _, _ in "SYNTHETIC_RECEIPT" })
        let starting = Task { await session.start(context: .init(binding: binding), language: "en", consented: true) }
        await gate.waitUntilCalled()
        session.stop()
        gate.release()
        await starting.value
        await session.stopAndRelease()
        #expect(session.state == .off && transport.connections == 0)
    }

    @Test func livePreviewNeverBecomesAFinalTurnOrAuthorizesATool() async throws {
        let transport = CloudVoiceFixture()
        var ownerTexts: [String?] = [], effects = 0
        let session = makeSession(transport, control: { _, _ in effects += 1; return "SYNTHETIC_RECEIPT" })
        session.onUserText = { text, _ in ownerTexts.append(text) }
        await session.start(context: .init(binding: binding), language: "fr", consented: true)
        for text in ["Je", "Je vais", "Je vais à pied", "Je vais à vélo"] {
            transport.emit(.userTranscriptPreview(text))
            #expect(session.userCaption == text)
            #expect(session.transcript == nil && session.userTurnID == nil && ownerTexts.isEmpty)
        }
        transport.emit(.tool(call("next")))
        await transport.waitForReplies(1)
        #expect(effects == 0 && transport.replies[0].2)
        transport.emit(.userText("Je vais à vélo.", eventID: 12))
        #expect(session.userCaption == "Je vais à vélo." && session.transcript == "Je vais à vélo.")
        #expect(ownerTexts == ["Je vais à vélo."])
        transport.emit(.userTranscriptPreview("Une autre"))
        #expect(session.transcript == "Je vais à vélo." && ownerTexts.count == 1)
        transport.emit(.agentText("SYNTHETIC_ANSWER"))
        #expect(session.userCaption == nil && session.transcript == "Je vais à vélo.")
        await session.stopAndRelease()
    }

    @Test func previewIsBoundedAndClearedByPlaybackInterruptionAndStop() async {
        let transport = CloudVoiceFixture(), session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        transport.emit(.userTranscriptPreview("SYNTHETIC_WORDS"))
        transport.emit(.userTranscriptPreview(String(repeating: "x", count: 4_001)))
        #expect(session.userCaption == nil)
        transport.emit(.userTranscriptPreview(" \n "))
        #expect(session.userCaption == nil)
        for boundary in [MorningCloudVoiceEvent.speaking, .interruption] {
            transport.emit(.userTranscriptPreview("SYNTHETIC_WORDS"))
            transport.emit(boundary)
            #expect(session.userCaption == nil)
        }
        transport.emit(.userTranscriptPreview("SYNTHETIC_LAST_WORDS"))
        let late = transport.onEvent
        await session.stopAndRelease()
        late?(.userTranscriptPreview("SYNTHETIC_LATE_WORDS"))
        #expect(session.userCaption == nil && session.transcript == nil)
    }

    @Test func conversationWithoutAMorningConnectsButCannotApplyTools() async throws {
        let transport = CloudVoiceFixture()
        var effects = 0
        let session = MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport },
            control: { _, _ in effects += 1; return "UNEXPECTED_CONTROL" },
            request: { _, _ in effects += 1; return true })
        await session.start(context: .init(binding: nil), language: "en", consented: true)
        #expect(session.state == .listening && transport.connections == 1)
        let control = call("next")
        transport.emit(.userText("SYNTHETIC_NEXT", eventID: 9))
        transport.emit(.tool(.init(id: "SYNTHETIC_NO_MORNING_CONTROL", name: control.name,
                                  parametersJSON: control.parametersJSON, eventID: 9)))
        await transport.waitForReplies(1)
        let parameters = String(decoding: try JSONEncoder().encode([
            "request": "SYNTHETIC_REQUEST", "session_id": binding.sessionID.uuidString, "step_id": binding.stepID.uuidString]), as: UTF8.self)
        transport.emit(.userText("SYNTHETIC_REQUEST", eventID: 10))
        transport.emit(.tool(.init(id: "SYNTHETIC_NO_MORNING_REQUEST", name: "more_request",
                                  parametersJSON: parameters, eventID: 10)))
        await transport.waitForReplies(2)
        #expect(effects == 0 && transport.replies.count == 2)
        #expect(transport.replies.allSatisfy { $0.2 })
        await session.stopAndRelease()
    }

    @Test func tokenOrProviderErrorsNeverExposePrivateErrorText() async {
        struct SyntheticPrivateError: Error, CustomStringConvertible { var description: String { "SYNTHETIC_PRIVATE_SECRET" } }
        for invalidToken in [true, false] {
            let transport = CloudVoiceFixture()
            let session = MorningCloudVoiceSession(tokenProvider: {
                if invalidToken { return "bad token" }
                throw SyntheticPrivateError()
            }, makeTransport: { transport }, control: { _, _ in "SYNTHETIC_RECEIPT" })
            await session.start(context: .init(binding: binding), language: "en", consented: true)
            #expect(session.state == .failed && transport.connections == 0)
            #expect(session.errorMessage?.contains("SYNTHETIC_PRIVATE_SECRET") == false)
            await session.stopAndRelease()
        }
    }

    @Test func ownerCallbacksExcludeAgentNarrationDuplicatesAndStoppedConnections() async throws {
        let transport = CloudVoiceFixture(), session = makeSession(transport)
        var ownerTexts: [String?] = [], turns: [UUID] = []
        session.onUserText = { text, turn in ownerTexts.append(text); turns.append(turn) }
        await session.start(context: .init(binding: nil), language: "fr", consented: true)
        transport.emit(.agentText("je prends les transports"))
        let reading = Task { try await session.narrate("je prends les transports") }
        await transport.waitForMessages()
        #expect(ownerTexts.isEmpty)
        session.cancelNarration()
        await #expect(throws: CancellationError.self) { try await reading.value }
        transport.emit(.userText("je prends les transports", eventID: 31))
        let first = try #require(turns.first)
        transport.emit(.userText("je prends les transports", eventID: 31))
        #expect(ownerTexts == ["je prends les transports"] && session.isCurrentUserTurn(first))
        transport.emit(.userText(String(repeating: "x", count: 4_001), eventID: 32))
        #expect(ownerTexts.count == 2 && ownerTexts[1] == nil)
        #expect(!session.isCurrentUserTurn(first) && session.transcript == nil)
        let late = transport.onEvent
        await session.stopAndRelease()
        late?(.userText("je préfère le vélo", eventID: 33))
        #expect(ownerTexts.count == 2 && session.userTurnID == nil)
    }

    @Test func aCloudOwnerStatementAndItsDelegatedAnswerExtractMemoryOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CloudOwnerMemory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var extractions = 0
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in
            extractions += 1
            return #"{"facts":[{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#
        })
        let conversation = MorningVoiceConversation(generator: { prompt in
            #expect(prompt.contains("publicTransport"))
            return "SYNTHETIC_ANSWER"
        }, memory: memory)
        let transport = CloudVoiceFixture()
        var learning: Task<Void, Never>?, answer: Task<String, any Error>?
        let session = MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport },
            control: { _, _ in "SYNTHETIC_RECEIPT" }, request: { text, _ in
                let memoryBarrier = learning
                answer = Task {
                    await memoryBarrier?.value
                    return try await conversation.answer(text, context: "SYNTHETIC_WEATHER", learnFromOwner: false)
                }
                return true
            })
        session.onUserText = { text, _ in
            guard let text else { return }
            learning = Task { await memory.remember(fromOwnerUtterance: text) }
        }
        await session.start(context: .init(binding: binding), language: "fr", consented: true)
        let text = "je prends les transports"
        transport.emit(.userText(text, eventID: 34))
        let parameters = String(decoding: try JSONEncoder().encode([
            "request": text, "session_id": binding.sessionID.uuidString, "step_id": binding.stepID.uuidString]), as: UTF8.self)
        transport.emit(.tool(.init(id: "SYNTHETIC_MEMORY_REQUEST", name: "more_request", parametersJSON: parameters, eventID: 34)))
        await transport.waitForReplies(1)
        let response = try #require(answer)
        #expect(try await response.value == "SYNTHETIC_ANSWER")
        #expect(extractions == 1 && memory.facts.first?.value == "publicTransport")
        #expect(transport.contexts.allSatisfy { !$0.contains("publicTransport") })
        await session.stopAndRelease()
    }

    @Test func aDelayedAnswerCannotNarrateAfterANewMicrophoneTurn() async throws {
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate(), session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        transport.emit(.userText("SYNTHETIC_FIRST_QUESTION", eventID: 35))
        let firstTurn = try #require(session.userTurnID)
        let conversation = MorningVoiceConversation(generator: { _ in await gate.value(); return "SYNTHETIC_OLD_ANSWER" })
        let response = Task {
            let text = try await conversation.answer("SYNTHETIC_FIRST_QUESTION", context: "SYNTHETIC_CONTEXT", learnFromOwner: false)
            try await session.narrate(text, forUserTurn: firstTurn)
        }
        await gate.waitUntilCalled()
        transport.emit(.userText("SYNTHETIC_NEW_QUESTION", eventID: 36))
        gate.release()
        await #expect(throws: CancellationError.self) { try await response.value }
        #expect(transport.messages.isEmpty && !session.isCurrentUserTurn(firstTurn))
        await session.stopAndRelease()
    }

    @Test(arguments: [false, true]) func delayedMemoryCannotPersistAfterItsTurnOrConnectionEnds(stopped: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("StaleCloudMemory-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate(), session = makeSession(transport)
        let memory = MorePersonalMemory(directory: directory, extractor: { _ in
            await gate.value()
            return #"{"facts":[{"key":"usualTransport","value":"publicTransport","evidence":"je prends les transports"}]}"#
        })
        await session.start(context: .init(binding: nil), language: "fr", consented: true)
        transport.emit(.userText("je prends les transports", eventID: 37))
        let turn = try #require(session.userTurnID)
        let learning = Task {
            await memory.remember(fromOwnerUtterance: "je prends les transports", whileCurrent: {
                session.isCurrentUserTurn(turn)
            })
        }
        await gate.waitUntilCalled()
        if stopped { await session.stopAndRelease() }
        else { transport.emit(.userText("SYNTHETIC_NEW_TURN", eventID: 38)) }
        gate.release()
        await learning.value
        #expect(memory.facts.isEmpty && memory.promptContext == "{}")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("personal-memory.json").path))
        await session.stopAndRelease()
    }

    @Test func modelToolsCannotReadHealthSendMailOrTargetAnotherStep() throws {
        let valid = call("next")
        #expect(MorningCloudVoiceSession.control(from: valid, binding: binding) == .next)
        for action in ["send_email", "read_health", "delete_data", "extend_500_minutes"] {
            #expect(MorningCloudVoiceSession.control(from: call(action), binding: binding) == nil)
        }
        #expect(MorningCloudVoiceSession.control(from: .init(id: "SYNTHETIC_CALL", name: "send_email", parametersJSON: valid.parametersJSON), binding: binding) == nil)
        #expect(MorningCloudVoiceSession.control(from: call("next", step: UUID()), binding: binding) == nil)
        let extra = String(valid.parametersJSON.dropLast()) + ",\"health_data\":\"SYNTHETIC_DATA\"}"
        #expect(MorningCloudVoiceSession.control(from: .init(id: "SYNTHETIC_CALL", name: "more_control", parametersJSON: extra), binding: binding) == nil)
    }

    @Test func duplicateToolDeliveryDoesNotApplyTheControlTwice() async {
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate()
        var controls = 0
        let session = makeSession(transport) { _, _ in controls += 1; await gate.value(); return "SYNTHETIC_PAUSED_RECEIPT" }
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let tool = call("pause")
        transport.emit(.userText("SYNTHETIC_PAUSE"))
        transport.emit(.tool(tool)); transport.emit(.tool(tool))
        await gate.waitUntilCalled()
        transport.emit(.tool(.init(id: "SYNTHETIC_SECOND_CALL", name: tool.name, parametersJSON: tool.parametersJSON)))
        await transport.waitForReplies(1)
        gate.release()
        await transport.waitForReplies(2)
        transport.emit(.tool(tool))
        await transport.waitForReplies(3)
        #expect(controls == 1 && transport.replies.count == 3)
        #expect(transport.replies.allSatisfy { !$0.2 })
        #expect(transport.replies.filter { $0.1 == "SYNTHETIC_PAUSED_RECEIPT" }.count == 2)
        await session.stopAndRelease()
    }

    @Test func serviceRequestsRequireTheExactCurrentSpokenTranscriptAndApplyOncePerUtterance() async throws {
        let transport = CloudVoiceFixture()
        var accepted = 0
        let session = MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport },
            control: { _, _ in Issue.record("A service request must not become a routine control."); return "UNEXPECTED" },
            request: { _, current in #expect(current == binding); accepted += 1; return true })
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let parameters = String(decoding: try JSONEncoder().encode([
            "request": "SYNTHETIC_SERVICE_REQUEST", "session_id": binding.sessionID.uuidString, "step_id": binding.stepID.uuidString]), as: UTF8.self)
        transport.emit(.userText("SYNTHETIC_DIFFERENT_WORDS", eventID: 4))
        transport.emit(.tool(.init(id: "SYNTHETIC_MISMATCH", name: "more_request", parametersJSON: parameters, eventID: 4)))
        await transport.waitForReplies(1)
        #expect(accepted == 0 && transport.replies[0].2)
        transport.emit(.userText("SYNTHETIC_SERVICE_REQUEST", eventID: 5))
        for id in ["SYNTHETIC_REQUEST_1", "SYNTHETIC_REQUEST_2"] {
            transport.emit(.tool(.init(id: id, name: "more_request", parametersJSON: parameters, eventID: 5)))
        }
        await transport.waitForReplies(3)
        #expect(accepted == 1)
        #expect(transport.replies[1...].allSatisfy { !$0.2 && $0.1.contains("pending") })
        await session.stopAndRelease()
    }

    @Test func stoppedToolCannotPublishALateReceipt() async {
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate()
        let session = makeSession(transport) { _, _ in await gate.value(); return "LATE_SYNTHETIC_RECEIPT" }
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        transport.emit(.userText("SYNTHETIC_PAUSE"))
        transport.emit(.tool(call("pause")))
        await gate.waitUntilCalled()
        session.stop(); gate.release()
        await session.stopAndRelease()
        for _ in 0..<10 { await Task.yield() }
        #expect(transport.replies.isEmpty && session.state == .off)
    }

    @Test(arguments: [false, true]) func pendingRequestClosesAudioAndCaptionsBeforeTheHandlerUntilANewTurn(appNarration: Bool) async throws {
        let transport = CloudVoiceFixture()
        let session = MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport },
            control: { _, _ in "SYNTHETIC_RECEIPT" }, request: { _, _ in
                #expect(transport.replySuppressions == 1, "The output gate must close before app work starts.")
                return true
            })
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let parameters = String(decoding: try JSONEncoder().encode([
            "request": "SYNTHETIC_REQUEST", "session_id": binding.sessionID.uuidString, "step_id": binding.stepID.uuidString]), as: UTF8.self)
        transport.emit(.agentText("SYNTHETIC_PREVIOUS_CAPTION"))
        transport.emit(.userText("SYNTHETIC_REQUEST", eventID: 7))
        transport.emit(.tool(.init(id: "SYNTHETIC_PENDING", name: "more_request", parametersJSON: parameters, eventID: 7)))
        await transport.waitForReplies(1)
        transport.emit(.agentText("SYNTHETIC_UNCONFIRMED_SUCCESS"))
        #expect(session.caption == nil && transport.replySuppressions == 1)
        if appNarration {
            let reading = Task { try await session.narrate("SYNTHETIC_APP_RESULT") }
            await transport.waitForMessages()
            transport.emit(.agentText("SYNTHETIC_APP_FACTS"))
            #expect(session.caption == "SYNTHETIC_APP_FACTS")
            session.cancelNarration()
            await #expect(throws: CancellationError.self) { try await reading.value }
        } else {
            transport.emit(.userText("SYNTHETIC_NEW_QUESTION", eventID: 8))
            transport.emit(.agentText("SYNTHETIC_NEW_REPLY"))
            #expect(session.caption == "SYNTHETIC_NEW_REPLY")
        }
        await session.stopAndRelease()
    }

    @Test func captionsRemoveOnlyTheObservedVoiceTagsAndPreserveOtherBrackets() {
        #expect(MorningCloudVoiceSession.captionText("[happy] Hello [Project Blue].") == "Hello [Project Blue].")
        #expect(MorningCloudVoiceSession.captionText("[SLOW] Bring [one, two] pencils.") == "Bring [one, two] pencils.")
        #expect(MorningCloudVoiceSession.captionText("[Quoted source] Keep this.") == "[Quoted source] Keep this.")
    }

    @Test func narrationRequiresBothBoundCompletionMarkerAndPlaybackEnd() async throws {
        let transport = CloudVoiceFixture()
        let session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        var completed = false
        let reading = Task { try await session.narrate("SYNTHETIC_APPROVED_FACT"); completed = true }
        await transport.waitForMessages()
        let message = try JSONDecoder().decode([String: String].self, from: Data(transport.messages[0].utf8))
        #expect(message["type"] == "more_approved_narration" && message["source_text"] == "SYNTHETIC_APPROVED_FACT")
        let id = try #require(message["narration_id"])
        transport.emit(.speaking)
        transport.emit(.tool(.init(id: "SYNTHETIC_COMPLETE", name: "more_narration_complete", parametersJSON: "{\"narration_id\":\"\(id)\"}")))
        await Task.yield()
        #expect(!completed && transport.replies.isEmpty, "Generation completion alone must not advance the routine.")
        transport.emit(.listening)
        try await reading.value
        #expect(completed && transport.replies.count == 1)
        await session.stopAndRelease()
    }

    @Test func interruptedNarrationThrowsAndCannotCompleteFromALateMarker() async throws {
        let transport = CloudVoiceFixture()
        let session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let reading = Task { try await session.narrate("SYNTHETIC_INTERRUPTED_FACT") }
        await transport.waitForMessages()
        transport.emit(.speaking); transport.emit(.interruption); transport.emit(.listening)
        await #expect(throws: CancellationError.self) { try await reading.value }
        #expect(session.isActive, "An interruption preserves the conversation while rejecting narration completion.")
        await session.stopAndRelease()
    }

    @Test func stoppedNarrationCancelsAnEnqueuedSourceSend() async {
        let transport = CloudVoiceFixture(), gate = CloudVoiceGate()
        transport.sendGate = gate
        let session = makeSession(transport)
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let reading = Task { try await session.narrate("SYNTHETIC_CANCELLED_BEFORE_SEND") }
        await gate.waitUntilCalled()
        session.stop(); gate.release()
        await #expect(throws: CancellationError.self) { try await reading.value }
        await session.stopAndRelease()
        for _ in 0..<10 { await Task.yield() }
        #expect(transport.messages.isEmpty && session.state == .off)
    }

    @Test func narrationWithoutConfirmedEndTimesOutWithoutSuccess() async {
        let transport = CloudVoiceFixture(), clock = ManualTestClock()
        let session = MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport },
            control: { _, _ in "SYNTHETIC_RECEIPT" }, clock: clock, narrationTimeout: .seconds(5))
        await session.start(context: .init(binding: binding), language: "en", consented: true)
        let reading = Task { try await session.narrate("SYNTHETIC_FACT_WITHOUT_END_MARKER") }
        await transport.waitForMessages(); await clock.waitForSleepers()
        clock.advance(by: .seconds(5))
        await #expect(throws: MorningCloudVoiceError.self) { try await reading.value }
        #expect(transport.replies.isEmpty)
        await session.stopAndRelease()
    }

    private func makeSession(_ transport: CloudVoiceFixture,
                             control: @escaping MorningCloudVoiceSession.ControlHandler = { _, _ in "SYNTHETIC_RECEIPT" }) -> MorningCloudVoiceSession {
        MorningCloudVoiceSession(tokenProvider: { "SYNTHETIC_TOKEN_123456" }, makeTransport: { transport }, control: control)
    }
    private func call(_ action: String, step: UUID? = nil) -> MorningCloudVoiceToolCall {
        let values = ["action": action, "session_id": binding.sessionID.uuidString, "step_id": (step ?? binding.stepID).uuidString]
        return .init(id: "SYNTHETIC_CALL", name: "more_control", parametersJSON: String(decoding: try! JSONEncoder().encode(values), as: UTF8.self))
    }
}

@MainActor
private final class CloudVoiceFixture: MorningCloudVoiceTransport {
    var onEvent: (@MainActor (MorningCloudVoiceEvent) -> Void)?
    var sendGate: CloudVoiceGate?
    private(set) var connections = 0
    private(set) var voiceGender: MorningVoiceGender?
    private(set) var stops = 0
    private(set) var contexts: [String] = []
    private(set) var replies: [(String, String, Bool)] = []
    private(set) var messages: [String] = []
    private(set) var replySuppressions = 0
    private var replyWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var messageWaiters: [CheckedContinuation<Void, Never>] = []
    func connect(token: String, language: String, voiceGender: MorningVoiceGender) async throws {
        connections += 1; self.voiceGender = voiceGender
    }
    func updateContext(_ context: String) async throws { contexts.append(context) }
    func sendUserMessage(_ text: String) async throws {
        if let sendGate { await sendGate.value() }
        try Task.checkCancellation()
        messages.append(text)
        let current = messageWaiters; messageWaiters = []
        for waiter in current { waiter.resume() }
    }
    func cancelPlayback() { }
    func suspendReply() { replySuppressions += 1 }
    func reply(to callID: String, result: String, isError: Bool) async throws {
        replies.append((callID, result, isError))
        let ready = replyWaiters.filter { $0.0 <= replies.count }
        replyWaiters.removeAll { $0.0 <= replies.count }
        for (_, waiter) in ready { waiter.resume() }
    }
    func stop() async { stops += 1 }
    func emit(_ event: MorningCloudVoiceEvent) { onEvent?(event) }
    func waitForReplies(_ count: Int) async {
        guard replies.count < count else { return }
        await withCheckedContinuation { replyWaiters.append((count, $0)) }
    }
    func waitForMessages() async {
        guard messages.isEmpty else { return }
        await withCheckedContinuation { messageWaiters.append($0) }
    }
}

@MainActor
private final class CloudVoiceGate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func value() async {
        await withCheckedContinuation { continuation in
            waiting = continuation
            let current = observers; observers = []
            for observer in current { observer.resume() }
        }
    }
    func waitUntilCalled() async {
        guard waiting == nil else { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func release() { let current = waiting; waiting = nil; current?.resume() }
}
