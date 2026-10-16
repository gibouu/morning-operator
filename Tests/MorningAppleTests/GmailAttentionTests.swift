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
