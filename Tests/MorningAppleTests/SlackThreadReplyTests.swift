import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Invented Slack messages and injected providers only. No account, token or external post.
@Suite("Slack source-bound thread reply — synthetic contracts") @MainActor
struct SlackThreadReplyTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let channel = "C12345678", author = "U33333333", parent = "1800000000.000001"

    #if DEBUG
    @Test("The deterministic mixed-journey draft requires its private flags and isolated workspace")
    func integratedDraftCannotEnterAnOrdinaryLaunch() async throws {
        let flags = ["--ui-testing", "--ui-testing-integrated-three-moments", "--ui-testing-slack-setup",
                     "--ui-testing-gmail-attention", "--ui-testing-workspace=\(UUID().uuidString)"]
        for missing in flags.indices {
            #expect(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(
                arguments: flags.enumerated().filter { $0.offset != missing }.map(\.element)) == nil)
        }
        #expect(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(arguments: []) == nil)
        #expect(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(arguments: flags + [flags.last!]) == nil)
        #expect(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(arguments:
            Array(flags.dropLast()) + ["--ui-testing-workspace=invalid"]) == nil)
        #expect(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(arguments: flags + ["--ui-testing-slack-reply"]) == nil)
        let drafts = try #require(SlackReplyDraftService.syntheticIntegratedJourneyIfRequested(arguments: flags))
        let body = try await drafts.draft(source: source(), intention: "Review these invented notes")
        #expect(body == "SYNTHETIC I will review the invented meeting notes.")
    }
    #endif

    @Test func languagePresentationPreservesDraftAndSourceWithoutPosting() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination()), source = try source()
        let exact = "Café e\u{301} stays exact."
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in exact }), directory: setup.directory,
            now: { instant }, speak: { _ in })
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        #expect(conversation.canConfirm)
        conversation.appLanguageDidChange()
        #expect(!conversation.canConfirm && provider.sends == 0)
        #expect(conversation.source == source && Data(conversation.body.utf8) == Data(exact.utf8))
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 0)
    }

    @Test func provenanceIsRequiredAndProviderIDsNeverComeFromProse() throws {
        let context = context()
        let result = readResult()
        let unknown = try ConnectedMomentDocument(executionID: context, service: "slack", result: result, receivedAt: instant)
        #expect(throws: SlackReplyError.unsupportedSource) { try SlackReplySource.sources(in: unknown, at: instant) }
        for tool in ["SLACK_SEND_MESSAGE", "SLACK_SEARCH_MESSAGES", "invented tool"] {
            let doc = try document(context: context, tool: tool)
            #expect(throws: SlackReplyError.unsupportedSource) { try SlackReplySource.sources(in: doc, at: instant) }
        }
        let doc = try document(context: context)
        let source = try #require(SlackReplySource.sources(in: doc, at: instant).first)
        #expect(source.channelID == channel && source.messageTS == parent && source.threadTS == parent && source.authorID == author)
        #expect(source.origin == doc.origin)
        #expect(throws: SlackReplyError.unsupportedSource) { try SlackReplySource.sources(in: doc, at: instant.addingTimeInterval(300)) }
        let wrongThread = try document(context: context, tool: "SLACK_FETCH_MESSAGE_THREAD_FROM_A_CONVERSATION", thread: "1800000000.999999")
        #expect(throws: SlackReplyError.unsupportedSource) { try SlackReplySource.sources(in: wrongThread, at: instant) }
    }

    @Test func channelChoicesAreBoundedNamedMembersAndPaginationIsHonest() throws {
        let value = wrapped(["channels": .array([
            .object(["id": .string(channel), "name": .string("morning"), "is_member": .bool(true), "is_archived": .bool(false)]),
            .object(["id": .string("C99999999"), "name": .string("not-joined"), "is_member": .bool(false), "is_archived": .bool(false)])
        ]), "response_metadata": .object(["next_cursor": .string("opaque-not-a-destination")])])
        let page = try SlackChannelPage(result: value)
        #expect(page.channels.count == 1 && page.channels.first?.id == channel && page.channels.first?.name == "morning")
        #expect(page.nextCursor == "opaque-not-a-destination")
        #expect(throws: SlackReplyError.unsupportedSource) { try SlackChannelPage(result: .object(["ok": .bool(false), "channels": .array([])])) }
        #expect(throws: SlackReplyError.destinationUnavailable) { try SlackChannelPage(result: wrapped(["channels": .array([]), "response_metadata": .object(["next_cursor": .number(3)])])) }
    }

    @Test func exactSeparateSendFollowsActualReviewAndDuplicateSendCannotPostAgain() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        var prompts: [String] = [], spoken: [String] = []
        let provider = Provider(destination: try destination())
        let conversation = SlackThreadReplyConversation(provider: provider, drafts: SlackReplyDraftService(generator: {
            prompts.append($0); return "I can review this tomorrow."
        }), directory: setup.directory, now: { instant }, speak: { spoken.append($0) })
        let source = try source()
        await conversation.prepare(intention: "Say I can review tomorrow, then send it", source: source, context: source.executionID)
        #expect(provider.sends == 0 && conversation.canConfirm)
        #expect(spoken.last?.contains("Actual workspace") == true && spoken.last?.contains("actual-owner") == true && spoken.last?.contains("morning") == true)
        #expect(prompts.count == 1 && !prompts[0].contains(channel) && !prompts[0].contains(author) && !prompts[0].contains(parent))
        #expect(try JSONSerialization.jsonObject(with: Data(prompts[0].utf8)) is [String: Any])
        _ = await conversation.respond("yes", context: source.executionID)
        #expect(provider.sends == 0)
        _ = await conversation.respond("send it", context: source.executionID)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 1 && conversation.phase == .completed)
        let saved = try String(contentsOf: setup.directory.appendingPathComponent("slack-reply-journal.json"), encoding: .utf8)
        #expect(!saved.contains(channel) && !saved.contains(author) && !saved.contains("tomorrow") && !saved.contains("Original private message"))
    }

    @Test func correctionAndInterruptedReviewRevokeSendUntilSeparateCompleteReview() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        var interrupt = true
        let provider = Provider(destination: try destination())
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in "First draft" }), directory: setup.directory, now: { instant },
            speak: { _ in if interrupt { throw CancellationError() } })
        let source = try source()
        await conversation.prepare(intention: "Reply with first draft", source: source, context: source.executionID)
        #expect(!conversation.canConfirm && conversation.body == "First draft")
        _ = await conversation.respond("envoie", context: source.executionID)
        #expect(provider.sends == 0)
        conversation.acknowledgeScreenReview()
        #expect(conversation.canConfirm)
        conversation.edit(body: "")
        #expect(conversation.body.isEmpty && !conversation.canConfirm)
        await conversation.review()
        _ = await conversation.respond("envoie", context: source.executionID)
        #expect(provider.sends == 0)
        conversation.edit(body: "Corrected draft")
        #expect(!conversation.canConfirm)
        _ = await conversation.respond("envoie", context: source.executionID)
        #expect(provider.sends == 0)
        interrupt = false; await conversation.review()
        _ = await conversation.respond("envoie", context: source.executionID)
        #expect(provider.sends == 1 && provider.sentBody == "Corrected draft")
    }

    @Test func unavailableLocalModelStillAllowsEditedAndSeparatelyReviewedReply() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination())
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in throw SlackReplyError.unavailable }), directory: setup.directory,
            now: { instant }, speak: { _ in })
        let source = try source()
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        #expect(conversation.destination != nil && conversation.phase == .unavailable && !conversation.canConfirm)
        conversation.edit(body: "Exact screen-written response")
        #expect(conversation.phase == .reviewing && !conversation.canConfirm)
        await conversation.review()
        #expect(conversation.canConfirm && provider.sends == 0)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 1 && provider.sentBody == "Exact screen-written response")
    }

    @Test func screenReviewSurvivesTheStoppedOlderNarrationCallback() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination())
        var release: CheckedContinuation<Void, any Error>?, holdReview = true
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in "Exact reply" }), directory: setup.directory, now: { instant },
            speak: { _ in if holdReview { try await withCheckedThrowingContinuation { release = $0 } } })
        let source = try source()
        let preparing = Task { await conversation.prepare(intention: "Reply", source: source, context: source.executionID) }
        for _ in 0..<200 where release == nil { await Task.yield() }
        let continuation = try #require(release)
        #expect(conversation.phase == .reviewing && !conversation.canConfirm)
        holdReview = false
        conversation.acknowledgeScreenReview()
        continuation.resume(throwing: CancellationError())
        await preparing.value
        #expect(conversation.canConfirm && provider.sends == 0)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(conversation.phase == .completed && provider.sends == 1)
    }

    @Test func sourceExpiryAndAccountChangeBeforeWriteCannotDispatch() async throws {
        for expire in [false, true] {
            let setup = try setup(); defer { setup.cleanup() }
            var time = instant
            let provider = Provider(destination: try destination())
            let conversation = SlackThreadReplyConversation(provider: provider,
                drafts: SlackReplyDraftService(generator: { _ in "Draft" }), directory: setup.directory, now: { time }, speak: { _ in })
            let source = try source()
            await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
            if expire { time = instant.addingTimeInterval(300) } else { provider.validationError = .accountChanged }
            _ = await conversation.respond("send it", context: source.executionID)
            #expect(provider.sends == 0 && conversation.phase != .completed && !conversation.canConfirm)
        }
    }

    @Test func unknownSurvivesRestoreAndBlocksChangedBodyNewOperationOnSameThread() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination()); provider.sendError = URLError(.timedOut)
        let source = try source()
        let conversation = makeConversation(provider, directory: setup.directory)
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 1 && conversation.phase == .uncertain)
        conversation.clear()
        let restored = makeConversation(provider, directory: setup.directory, draft: "Changed body")
        await restored.prepare(intention: "Reply differently", source: source, context: source.executionID)
        _ = await restored.respond("send it", context: source.executionID)
        #expect(restored.phase == .uncertain && provider.sends == 1)
    }

    @Test func verifiedNoEffectReleasesClaimButRequiresFreshReview() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination()); provider.sendError = SlackReplyDispatchError.notDispatched(.accountChanged)
        let conversation = makeConversation(provider, directory: setup.directory), source = try source()
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(conversation.phase == .reviewing && !conversation.canConfirm && provider.sends == 1)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 1)
        provider.sendError = nil
        await conversation.review()
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 2 && conversation.phase == .completed)
    }

    @Test func receiptMustEchoExactMarkerAuthorChannelThreadAndBody() throws {
        let reply = try SlackPreparedReply(source: source(), destination: destination(), body: "Exact draft")
        let id = UUID()
        #expect(try SlackReplyReceipt.verified(result: receipt(reply, id: id), reply: reply, operationID: id).channelID == channel)
        for change in ["marker", "author", "channel", "thread", "body", "ts", "inner-error", "no-source", "request"] {
            #expect(throws: (any Error).self) { try SlackReplyReceipt.verified(result: receipt(reply, id: id, change: change), reply: reply, operationID: id) }
        }
        let args = reply.arguments(operationID: id)
        #expect(args["markdown_text"] == nil && args["metadata"] == nil && args["client_msg_id"] == nil)
        #expect(args["reply_broadcast"] == .bool(false) && args["unfurl_links"] == .bool(false) && args["unfurl_media"] == .bool(false))
        for body in ["", "<@U99999999> ping", "<!channel> ping", "<#C99999999>", String(repeating: "😀", count: 1_501)] {
            #expect(throws: SlackReplyError.invalidReply) { try SlackPreparedReply(source: source(), destination: destination(), body: body) }
        }
    }

    @Test func lateModelCallbackCannotRestoreOldContextOrPrivacyEpoch() async throws {
        for forget in [false, true] {
            let setup = try setup(); defer { setup.cleanup() }
            var release: CheckedContinuation<String, Never>?
            let provider = Provider(destination: try destination())
            let conversation = SlackThreadReplyConversation(provider: provider,
                drafts: SlackReplyDraftService(generator: { _ in await withCheckedContinuation { release = $0 } }),
                directory: setup.directory, now: { instant }, speak: { _ in })
            let source = try source()
            let task = Task { await conversation.prepare(intention: "Reply", source: source, context: source.executionID) }
            for _ in 0..<200 where release == nil { await Task.yield() }
            let continuation = try #require(release)
            if forget { _ = try LocalDataControl(directory: setup.directory).beginForget() }
            conversation.clear()
            continuation.resume(returning: "Late private draft"); await task.value
            #expect(conversation.phase == .idle && conversation.context == nil && conversation.body.isEmpty && provider.sends == 0)
        }
    }

    @Test func confirmedReceiptSurvivesNarrationFailureAndLateSendDoesNotSpeakIntoReplacement() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination())
        var spoken: [String] = [], failSpeech = false
        let source = try source()
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in "Exact draft" }), directory: setup.directory, now: { instant },
            speak: { spoken.append($0); if failSpeech { throw CancellationError() } })
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        failSpeech = true
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(conversation.phase == .completed && provider.sends == 1)
        let entries = try AtomicJSONFile<[SlackReplyJournal.Entry]>(url: setup.directory.appendingPathComponent("slack-reply-journal.json"), maximumBytes: 262_144).load()
        #expect(entries.count == 1 && entries[0].receipt != nil)
        _ = await conversation.respond("send it", context: source.executionID)
        #expect(provider.sends == 1)
    }

    @Test func lateKnownReceiptIsDurableWithoutRestoringClearedPrivatePanel() async throws {
        let setup = try setup(); defer { setup.cleanup() }
        let provider = Provider(destination: try destination())
        var release: CheckedContinuation<Void, Never>?, spoken: [String] = []
        provider.beforeReceipt = { await withCheckedContinuation { release = $0 } }
        let conversation = SlackThreadReplyConversation(provider: provider,
            drafts: SlackReplyDraftService(generator: { _ in "Exact draft" }), directory: setup.directory, now: { instant }, speak: { spoken.append($0) })
        let source = try source()
        await conversation.prepare(intention: "Reply", source: source, context: source.executionID)
        let task = Task { await conversation.respond("send it", context: source.executionID) }
        for _ in 0..<200 where release == nil { await Task.yield() }
        let continuation = try #require(release)
        conversation.clear(); let before = spoken.count
        continuation.resume(); _ = await task.value
        #expect(conversation.context == nil && conversation.body.isEmpty && conversation.phase == .idle && spoken.count == before)
        let entries = try AtomicJSONFile<[SlackReplyJournal.Entry]>(url: setup.directory.appendingPathComponent("slack-reply-journal.json"), maximumBytes: 262_144).load()
        #expect(entries.count == 1 && entries[0].receipt != nil && provider.sends == 1)
        let journal = SlackReplyJournal(control: .init(directory: setup.directory))
        let counts = try journal.actionCounts(contexts: [source.executionID], generation: nil)
        #expect(counts.confirmed == 1 && counts.unconfirmed == 0)
        let other = try journal.actionCounts(contexts: [context()], generation: nil)
        #expect(other.confirmed == 0 && other.unconfirmed == 0)
    }

    private func makeConversation(_ provider: Provider, directory: URL, draft: String = "Exact draft") -> SlackThreadReplyConversation {
        SlackThreadReplyConversation(provider: provider, drafts: SlackReplyDraftService(generator: { _ in draft }), directory: directory, now: { instant }, speak: { _ in })
    }

    @Test func recapAttributesDurableRepliesToExactPinnedStepAfterRelaunch() throws {
        let setup = try setup(); defer { setup.cleanup() }
        let steps = [RoutineStep(title: "Same Slack title"), RoutineStep(title: "Same Slack title")]
        let session = RoutineSession(routine: .init(sourceLabel: "SYNTHETIC", steps: steps, isApproved: true))
        let contexts = steps.map { MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: $0.id) }
        let journal = SlackReplyJournal(control: .init(directory: setup.directory))
        let firstSource = try #require(SlackReplySource.sources(in: document(context: contexts[0]), at: instant).first)
        let reply = try SlackPreparedReply(source: firstSource, destination: destination(), body: "Exact reply")
        let firstID = UUID(), firstFingerprint = String(repeating: "a", count: 64)
        #expect(try journal.claim(id: firstID, context: contexts[0], target: String(repeating: "b", count: 64), fingerprint: firstFingerprint, generation: nil))
        let verified = try SlackReplyReceipt.verified(result: receipt(reply, id: firstID), reply: reply, operationID: firstID)
        try journal.confirm(id: firstID, fingerprint: firstFingerprint, receipt: verified, generation: nil)
        #expect(try journal.claim(id: UUID(), context: contexts[1], target: String(repeating: "c", count: 64), fingerprint: String(repeating: "d", count: 64), generation: nil))
        let restored = makeConversation(Provider(destination: try destination()), directory: setup.directory)
        let confirmed = try restored.actionCounts(for: session, stepID: steps[0].id)
        let unconfirmed = try restored.actionCounts(for: session, stepID: steps[1].id)
        #expect(confirmed.confirmed == 1 && confirmed.unconfirmed == 0)
        #expect(unconfirmed.confirmed == 0 && unconfirmed.unconfirmed == 1)
        let differentSession = RoutineSession(routine: session.routine)
        #expect(try restored.actionCounts(for: differentSession, stepID: steps[0].id).confirmed == 0)
        let differentVersion = RoutineSession(id: session.id, routine: .init(sourceLabel: "SYNTHETIC other version", steps: steps, isApproved: true))
        #expect(try restored.actionCounts(for: differentVersion, stepID: steps[1].id).unconfirmed == 0)
        #expect(try restored.actionCounts(for: session, stepID: UUID()).unconfirmed == 0)
        let total = try restored.actionCounts(for: session)
        #expect(total.confirmed == 1 && total.unconfirmed == 1)
    }
    private func setup() throws -> Workspace { Workspace() }
    private struct Workspace {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SlackReply-SYNTHETIC-\(UUID())")
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
    private func context() -> MorningExecutionID { .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()) }
    private func document(context: MorningExecutionID, tool: String = "SLACK_FETCH_CONVERSATION_HISTORY", thread: String? = nil) throws -> ConnectedMomentDocument {
        var args: [String: ComposioJSONValue] = ["channel": .string(channel), "limit": .number(3)]
        if let thread { args["ts"] = .string(thread) }
        return try ConnectedMomentDocument(executionID: context, service: "slack", result: readResult(), receivedAt: instant,
            origin: .init(tool: tool, connectionID: "ca_synthetic", arguments: args))
    }
    private func source() throws -> SlackReplySource { try #require(SlackReplySource.sources(in: document(context: context()), at: instant).first) }
    private func destination() throws -> SlackReplyDestination {
        try .init(identity: .init(connectionID: "ca_synthetic", revision: String(repeating: "a", count: 64), teamID: "T12345678", userID: "U12345678", teamName: "Actual workspace", userName: "actual-owner"), channelID: channel, channelName: "morning")
    }
    private func wrapped(_ fields: [String: ComposioJSONValue]) -> ComposioJSONValue {
        .object(["successful": .bool(true), "data": .object(fields.merging(["ok": .bool(true)]) { _, new in new })])
    }
    private func readResult() -> ComposioJSONValue { wrapped(["messages": .array([.object(["type": .string("message"), "ts": .string(parent), "user": .string(author), "text": .string("Original private message")])])]) }
    private func receipt(_ reply: SlackPreparedReply, id: UUID, change: String = "") -> ComposioExecutionResult {
        Self.receipt(reply, id: id, change: change)
    }
    private static func receipt(_ reply: SlackPreparedReply, id: UUID, change: String = "") -> ComposioExecutionResult {
        let ts = "1800000001.000002"
        var message: [String: ComposioJSONValue] = ["ts": .string(change == "ts" ? "1800000009.000001" : ts),
            "user": .string(change == "author" ? "U99999999" : reply.destination.userID),
            "thread_ts": .string(change == "thread" ? "1800000099.000001" : reply.source.threadTS),
            "blocks": .array([.object(["type": .string("section"), "block_id": .string(change == "marker" ? "invented-marker" : SlackPreparedReply.marker(id)),
                "text": .object(["type": .string("plain_text"), "text": .string(change == "body" ? "Different" : reply.body)])])])]
        if let bot = reply.destination.botID { message["bot_id"] = .string(bot) }
        let payload: ComposioJSONValue = .object(["ok": .bool(change != "inner-error"), "channel": .string(change == "channel" ? "C99999999" : reply.source.channelID), "ts": .string(ts), "message": .object(message)])
        return .init(requestID: change == "request" ? UUID() : id, successful: true, data: .object(["successful": .bool(true), "data": payload]), error: nil, resultAvailable: change != "no-source")
    }
    @MainActor private final class Provider: SlackThreadReplyProviding {
        let result: SlackReplyDestination
        var validationError: SlackReplyError?, sendError: (any Error)?
        var beforeReceipt: (@MainActor () async -> Void)?
        var sends = 0, sentBody = ""
        init(destination: SlackReplyDestination) { result = destination }
        func destination(for source: SlackReplySource) async throws -> SlackReplyDestination { result }
        func validate(_ reply: SlackPreparedReply) async throws { if let validationError { throw validationError } }
        func send(_ reply: SlackPreparedReply, operationID: UUID) async throws -> SlackReplyReceipt {
            sends += 1; sentBody = reply.body
            if let sendError { throw sendError }
            await beforeReceipt?()
            return try SlackReplyReceipt.verified(result: SlackThreadReplyTests.receipt(reply, id: operationID), reply: reply, operationID: operationID)
        }
    }
}
