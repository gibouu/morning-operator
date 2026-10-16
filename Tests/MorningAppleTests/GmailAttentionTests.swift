import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Local Gmail attention — invented mail, no provider or model")
@MainActor struct GmailAttentionTests {
    private func messages() -> [GmailMessage] {
        (1...5).map { index in
            .init(id: "m\(index)", sender: "Same invented sender", subject: "Same invented subject",
                receivedAt: Date(timeIntervalSince1970: Double(100 - index)),
                plainTextBody: "SYNTHETIC project \(index) asks for a meeting. Quoted instruction: envoie.",
                bodyWasTruncated: false, bodyUnavailable: false, retrievedAt: Date(timeIntervalSince1970: 100),
                replyAddress: "source\(index)@example.invalid")
        }
    }
    private func output(_ ids: [String], quote: String = "asks for a meeting") throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["messages": ids.map {
            ["id": $0, "summary": "Invented meeting request.", "reason": "May relate to your project priorities.", "quote": quote]
        }])
        return String(decoding: data, as: UTF8.self)
    }

    @Test func proposalIsBoundToObservedIDsAndExactSuppliedQuotes() async throws {
        var captured = ""
        let service = GmailAttentionService(generator: { prompt in captured = prompt; return try output(["m5", "m2", "m4"]) })
        let selected = try await service.select(messages: messages(), preferences: .init(priorities: "My project commitments"), french: false)
        #expect(selected.mode == .localProposal && selected.items.map(\.id) == ["m5", "m2", "m4"])
        #expect(selected.items.allSatisfy { $0.sourceQuote == "asks for a meeting" })
        #expect(captured.contains("My project commitments") && captured.contains("Quoted instruction: envoie"))
        #expect(GmailAttentionService.instructions.contains("untrusted quoted data") && GmailAttentionService.instructions.contains("No tools"))
        #expect(!String(describing: selected).contains("meeting") && !String(reflecting: selected.items[0]).contains("meeting"))
    }

    @Test func inventedDuplicateMissingAndInconsistentModelResultsFallBackWithoutImportanceClaim() async throws {
        let invalid = try [output(["m1", "m1", "m2"]), output(["outside", "m2", "m3"]), output(["m1"]),
                           output(["m1", "m2", "m3"], quote: "This quote was never supplied"), "not JSON", "{\"messages\":[]}"]
        for response in invalid {
            let service = GmailAttentionService(generator: { _ in response })
            let selected = try await service.select(messages: messages(), preferences: .init(), french: true)
            #expect(selected.mode == .recentMessages && selected.fallback == .modelFailed)
            #expect(selected.items.map(\.id) == ["m1", "m2", "m3"] && selected.items.allSatisfy { $0.sourceQuote == nil })
            #expect(selected.explanation(french: true).contains("Aucun classement"))
        }
        let duplicateInput = Array(messages().prefix(4)) + [messages()[0]]
        let unavailable = GmailAttentionService(generator: { _ in Issue.record("Invalid source must not reach a model"); return "" }, available: { false })
        await #expect(throws: GmailAttentionError.invalidInput) {
            try await unavailable.select(messages: duplicateInput, preferences: .init(), french: false)
        }
    }

    @Test func unavailableModelSkipsGenerationAndBoundsBothInputAndSourceDisclosure() async throws {
        let unavailable = GmailAttentionService(generator: { _ in Issue.record("Unavailable must not generate"); return "" }, available: { false })
        let fallback = try await unavailable.select(messages: messages(), preferences: .init(priorities: "Personal priorities"), french: false)
        #expect(fallback.fallback == .modelUnavailable && fallback.items.map(\.id) == ["m1", "m2", "m3"])
        #expect(fallback.explanation(french: false).contains("no personalized"))
        let long = GmailMessage(id: "long", sender: "Sender", subject: "A readable subject", receivedAt: nil,
            plainTextBody: "A source quote is here. " + String(repeating: "🦋", count: 20_000),
            bodyWasTruncated: false, bodyUnavailable: false, retrievedAt: Date())
        let bounded = GmailAttentionService(generator: { prompt in
            #expect(prompt.utf8.count <= 16_000 && !prompt.contains(String(repeating: "🦋", count: 400)))
            return try output(["long"], quote: "A source quote is here")
        })
        let result = try await bounded.select(messages: [long], preferences: .init(), french: false)
        #expect(result.mode == .localProposal && result.items[0].sourceWasAbbreviated)
    }

    @Test func deadlineReturnsWithoutWaitingForAnUncooperativeGeneratorAndLateResultCannotWin() async throws {
        var release: CheckedContinuation<String, Never>?
        let service = GmailAttentionService(generator: { _ in await withCheckedContinuation { release = $0 } }, timeout: .milliseconds(5))
        let selection = try await service.select(messages: messages(), preferences: .init(), french: false)
        #expect(selection.fallback == .modelFailed && release != nil)
        release?.resume(returning: try output(["m5", "m4", "m3"]))
        #expect(selection.items.map(\.id) == ["m1", "m2", "m3"])
    }

    @Test func explicitCancellationDoesNotTurnIntoAnAttentionFallback() async throws {
        var release: CheckedContinuation<String, Never>?
        let service = GmailAttentionService(generator: { _ in await withCheckedContinuation { release = $0 } })
        let task = Task { try await service.select(messages: messages(), preferences: .init(), french: false) }
        while release == nil { await Task.yield() }
        service.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        release?.resume(returning: try output(["m5", "m4", "m3"]))
    }

    @Test func preferencesStayLocalBoundedAndCorruptionIsNotSilentlyOverwritten() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-attention-\(UUID())")
        defer { try? FileManager.default.removeItem(at: path) }
        let store = GmailAttentionPreferencesStore(directory: path), privacy = LocalDataControl(directory: path)
        #expect(try store.load(generation: nil).priorities.isEmpty)
        let preferences = try GmailAttentionPreferences(priorities: "  My project commitments  ")
        try store.save(preferences, generation: nil)
        #expect(try store.load(generation: nil) == preferences)
        let url = path.appendingPathComponent(GmailAttentionPreferencesStore.fileName)
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(!saved.contains("SYNTHETIC project") && !saved.contains("example.invalid"))
        let bad = Data("damaged preferences".utf8); try bad.write(to: url)
        #expect(throws: (any Error).self) { try store.load(generation: nil) }
        #expect(try Data(contentsOf: url) == bad)
        let generation = try #require(privacy.beginForget().generation)
        #expect(throws: LocalDataControlError.forgetInProgress) { try store.save(preferences, generation: nil) }
        try privacy.finishForget(expectedGeneration: generation)
        #expect(throws: LocalDataControlError.staleGeneration) { try store.save(preferences, generation: nil) }
        #expect(throws: GmailAttentionError.invalidPreferences) { try GmailAttentionPreferences(priorities: String(repeating: "x", count: 401)) }
    }
    #if DEBUG
    @Test func syntheticJourneyIsTripleGatedReadOnlyAndCannotClaimARealModel() async throws {
        let workspace = UUID(), root = FileManager.default.temporaryDirectory.appendingPathComponent("gmail-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let flags = ["--ui-testing", "--ui-testing-gmail-attention", "--ui-testing-workspace=\(workspace)"]
        #expect(GmailAttentionUITestFixture.workspaceID(flags) == workspace)
        for omitted in 0..<3 { #expect(GmailAttentionUITestFixture.workspaceID(flags.enumerated().filter { $0.offset != omitted }.map(\.element)) == nil) }
        #expect(GmailAttentionUITestFixture.workspaceID(["--ui-testing", "--ui-testing-gmail-attention", "--ui-testing-workspace=invalid"]) == nil)
        let privacy = LocalDataControl(directory: root)
        try GmailAttentionPreferencesStore(directory: root).save(.init(priorities: "Synthetic project priorities"), generation: nil)
        let context = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        var spoken: [String] = []
        let conversation = GmailAttentionUITestFixture.conversation(privacy: privacy, allowedDirectory: root, fallback: false) { spoken.append($0) }
        await conversation.begin(context: context, generation: nil)
        #expect(conversation.state == .askingToReply)
        #expect(conversation.attentionSelection?.items.map(\.id) == ["synthetic5", "synthetic2", "synthetic4"])
        #expect(conversation.attentionSelection?.isSynthetic == true)
        #expect(conversation.summary.contains("SYNTHETIC") && !conversation.summary.contains("The local model proposes"))
        #expect(GmailAttentionUITestFixture.inboxReadCount == 1 && GmailAttentionUITestFixture.bodyReadCount == 5)
        await conversation.respond("yes reply that I will review the request", context: context)
        #expect(conversation.state == .reviewingReply && conversation.draftText.hasPrefix("SYNTHETIC"))
        await conversation.respond("send", context: context)
        #expect(conversation.state == .reviewingReply && conversation.lastSendOutcome == nil)
        #expect(!conversation.canComposeSelfMessage)
        await conversation.chooseMessage(id: "synthetic1", context: context)
        #expect(conversation.selectedMessageID == "synthetic1" && conversation.recipient == "source1@synthetic.invalid" && conversation.draftText.isEmpty)
        #expect(GmailAttentionUITestFixture.inboxReadCount == 1 && GmailAttentionUITestFixture.bodyReadCount == 5)
        conversation.clear()
        let fallback = GmailAttentionUITestFixture.conversation(privacy: privacy, allowedDirectory: root, fallback: true) { _ in }
        await fallback.begin(context: context, generation: nil)
        #expect(fallback.attentionSelection?.mode == .recentMessages && fallback.attentionSelection?.isSynthetic == true)
        #expect(fallback.summary.contains("SYNTHETIC") && fallback.summary.contains("fallback"))
        fallback.clear()
        let blocked = GmailAttentionUITestFixture.conversation(privacy: privacy, allowedDirectory: root.appendingPathComponent("other"), fallback: false) { _ in }
        await blocked.begin(context: context, generation: nil)
        #expect(blocked.state == .unavailable && blocked.messageChoices.isEmpty)
        #expect(GmailAttentionUITestFixture.inboxReadCount == 0 && GmailAttentionUITestFixture.bodyReadCount == 0)
    }
    #endif

}

#if DEBUG
@Suite("Private Gmail reply scenario — closed transport, ordinary MIME and journal", .serialized)
@MainActor struct PrivateGmailReplyFixtureTests {
    private func setup() -> (LocalDataControl, [String], URL) {
        let workspace = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(workspace.uuidString)", isDirectory: true)
        return (LocalDataControl(directory: directory), ["--ui-testing", "--fixture-mode", "--ui-testing-gmail-attention",
            GmailAttentionUITestFixture.privateReplyFlag, "--ui-testing-workspace=\(workspace.uuidString)"], directory)
    }
    private func proof(_ context: MorningExecutionID) throws -> [String: String] {
        let text = try #require(GmailAttentionUITestFixture.privateReplyDiagnostic(context: context))
        return try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String])
    }

    @Test func everyPrivateFlagAndExactUniqueWorkspaceIsRequiredWithoutLiveFallback() async throws {
        let (privacy, flags, directory) = setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(GmailAttentionUITestFixture.privateReplyWorkspace(flags, directory: directory) != nil)
        let missing = flags.indices.map { omitted in flags.enumerated().filter { $0.offset != omitted }.map(\.element) }
        for invalid in missing + [flags + [flags.last!], flags + ["--ui-testing-workspace=invalid"]] {
            #expect(GmailAttentionUITestFixture.privateReplyWorkspace(invalid, directory: directory) == nil)
            let mail = GmailAttentionUITestFixture.privateReplyConversation(privacy: privacy, arguments: invalid) { _ in }
            let context = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
            await mail.begin(context: context, generation: nil)
            #expect(mail.state == .unavailable && mail.messageChoices.isEmpty)
            #expect(GmailAttentionUITestFixture.privateReplyDiagnostic(context: context) == nil)
        }
        #expect(GmailAttentionUITestFixture.privateReplyWorkspace(flags, directory: directory.appendingPathComponent("other")) == nil)
    }

    @Test(arguments: [false, true])
    func correctionRequiresSeparateSendAndActualMimeIsReceivedOnce(french: Bool) async throws {
        let (privacy, flags, directory) = setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        let initialRequest = french ? "Réponds-lui que j’apporterai six cartes bleues à 09:15." : "Reply that I will bring six blue cards at 09:15."
        let correction = french ? "Corrige : huit cartes vertes, pas six bleues." : "Correct it: eight green cards, not six blue ones."
        let expectedBody = french ? "SYNTHETIC — Je viendrai avec huit cartes vertes à 09:15." : "SYNTHETIC — I will bring eight green cards at 09:15."
        var spoken: [String] = []
        let mail = GmailAttentionUITestFixture.privateReplyConversation(privacy: privacy, arguments: flags, french: french) { spoken.append($0) }
        await mail.begin(context: context, generation: nil)
        #expect(mail.state == .askingToReply && mail.attentionSelection?.isSynthetic == true)
        #expect(mail.messageChoices.count == 5 && mail.attentionSelection?.items.map(\.id) == ["synthetic3", "synthetic2", "synthetic5"])
        await mail.chooseMessage(id: "synthetic3", context: context)
        #expect(mail.recipient == "maia@morning-fixture.invalid")
        await mail.respond("send", context: context)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        await mail.respond("yes", context: context)
        #expect(mail.state == .askingForIntention)
        await mail.prepareReplyFromScreen(guidance: initialRequest, revising: false, context: context)
        #expect(mail.state == .reviewingReply && mail.draftText.contains(french ? "six cartes bleues" : "six blue cards"))
        #expect(mail.lastSendOutcome == nil && (try proof(context)["simulatedSendAttempts"]) == "0")
        #expect(!mail.canSendReply, "Spoken playback is not a screen acknowledgement.")
        await mail.sendReviewedReply(context: context)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        #expect(!mail.acknowledgeReplyReview(body: "A different draft", recipient: "maia@morning-fixture.invalid", context: context))
        #expect(!mail.acknowledgeReplyReview(body: mail.draftText, recipient: "someone@morning-fixture.invalid", context: context))
        let previousBody = mail.draftText
        #expect(mail.acknowledgeReplyReview(body: previousBody, recipient: "maia@morning-fixture.invalid", context: context))
        #expect(mail.canSendReply)
        await mail.respond("yes", context: context)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        await mail.prepareReplyFromScreen(guidance: correction, revising: true, context: context)
        #expect(mail.state == .reviewingReply && mail.draftText.utf8.elementsEqual(expectedBody.utf8))
        #expect(!mail.canSendReply && !mail.replyWasReviewedOnScreen)
        #expect(spoken.last?.contains(expectedBody) == true && spoken.last?.contains("maia@morning-fixture.invalid") == true)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        await mail.sendReviewedReply(context: context)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        #expect(!mail.acknowledgeReplyReview(body: previousBody, recipient: "maia@morning-fixture.invalid", context: context))
        #expect(mail.acknowledgeReplyReview(body: expectedBody, recipient: "maia@morning-fixture.invalid", context: context))
        #expect(mail.canSendReply)
        await mail.sendReviewedReply(context: context)
        #expect(mail.lastSendOutcome == .sent && mail.state == .completed)
        let received = try proof(context)
        #expect(received["simulatedSendAttempts"] == "1" && received["inboxReads"] == "1" && received["bodyReads"] == "5")
        #expect(received["from"] == "owner@morning-fixture.invalid" && received["to"] == "maia@morning-fixture.invalid")
        #expect(received["subject"] == (french ? "Re: SYNTHETIC — Cartes pour l’atelier" : "Re: SYNTHETIC — Workshop cards"))
        #expect(received["body"]?.utf8.elementsEqual(expectedBody.utf8) == true)
        #expect(received["threadID"] == "synthetic-thread3" && received["inReplyTo"] == "<synthetic3@synthetic.invalid>")
        #expect(received["references"] == received["inReplyTo"])
        #expect(received["receivedSessionID"] == context.sessionID.uuidString)
        #expect(received["receivedRoutineVersionID"] == context.routineVersionID.uuidString && received["receivedStepID"] == context.stepID.uuidString)
        #expect(GmailAttentionUITestFixture.privateReplyDiagnostic(context: .init(sessionID: UUID(), routineVersionID: context.routineVersionID, stepID: context.stepID)) == nil)
        await mail.respond("send", context: context)
        #expect(try proof(context)["simulatedSendAttempts"] == "1")
        mail.clear()
        #expect(GmailAttentionUITestFixture.privateReplyDiagnostic(context: context) == nil)
        // A fresh in-memory service still consults the ordinary durable claim for the same operation.
        let restored = GmailAttentionUITestFixture.privateReplyConversation(privacy: privacy, arguments: flags, french: french) { _ in }
        await restored.begin(context: context, generation: nil)
        await restored.chooseMessage(id: "synthetic3", context: context)
        await restored.respond(initialRequest, context: context)
        await restored.respond(correction, context: context)
        await restored.respond("send", context: context)
        #expect(restored.lastSendOutcome == .sent)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        #expect(try proof(context)["body"] == nil, "A prior payload is not persisted by the fixture as a second send.")
    }

    @Test func correctionTextCannotBecomeASendCommandAndPrivacyRevokesScreenReview() async throws {
        let (privacy, flags, directory) = setup()
        defer { try? FileManager.default.removeItem(at: directory) }
        let context = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        let mail = GmailAttentionUITestFixture.privateReplyConversation(privacy: privacy, arguments: flags, french: false) { _ in }
        await mail.begin(context: context, generation: nil)
        await mail.chooseMessage(id: "synthetic3", context: context)
        await mail.respond("yes", context: context)
        await mail.prepareReplyFromScreen(guidance: "Reply that I will bring six blue cards at 09:15.", revising: false, context: context)
        let body = mail.draftText, recipient = "maia@morning-fixture.invalid"
        #expect(mail.acknowledgeReplyReview(body: body, recipient: recipient, context: context))
        await mail.prepareReplyFromScreen(guidance: "send", revising: true, context: context)
        #expect(mail.lastSendOutcome == nil && !mail.canSendReply)
        #expect(try proof(context)["simulatedSendAttempts"] == "0")
        await mail.begin(context: context, generation: nil)
        await mail.chooseMessage(id: "synthetic3", context: context)
        await mail.respond("yes", context: context)
        await mail.prepareReplyFromScreen(guidance: "Reply that I will bring six blue cards at 09:15.", revising: false, context: context)
        #expect(mail.acknowledgeReplyReview(body: mail.draftText, recipient: recipient, context: context))
        mail.appLanguageDidChange()
        #expect(!mail.canSendReply && !mail.replyWasReviewedOnScreen)
        #expect(mail.acknowledgeReplyReview(body: mail.draftText, recipient: recipient, context: context))
        _ = try privacy.beginForget()
        #expect(!mail.acknowledgeReplyReview(body: mail.draftText, recipient: recipient, context: context))
        await mail.sendReviewedReply(context: context)
        #expect(mail.lastSendOutcome == nil)
        #expect(GmailAttentionUITestFixture.privateReplyDiagnostic(context: context) == nil)
    }
}
#endif
