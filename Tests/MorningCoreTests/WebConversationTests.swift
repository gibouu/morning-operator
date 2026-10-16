import Foundation
import Testing
@testable import MorningCore

@Suite("Browser conversation reply contract")
struct WebConversationTests {
    static func source(_ site: WebMorningSite = .linkedin, text: String = "Are you available tomorrow?") -> WebConversationSnapshot {
        WebConversationSnapshot(site: site, conversationID: site == .linkedin ? "thread-1" : "T1/C1", recipient: "Alex", accountID: "me",
            messageID: "incoming-1", messageText: text, editorID: site == .linkedin ? "linkedin-message-editor" : "slack-message-editor", outgoingMessageIDs: ["previous-1"])
    }

    @Test("Reply guidance never becomes an instruction to send", arguments: ["réponds-lui oui et envoie", "reply yes and send it"])
    func compoundSendIsDraftOnly(text: String) {
        #expect(WebConversationIntent.parse(text) != .send)
    }

    @Test("French and English commands retain conversational context")
    func bilingualIntents() {
        #expect(WebConversationIntent.parse("Réponds-lui") == .reply(""))
        #expect(WebConversationIntent.parse("réponds lui") == .reply(""))
        #expect(WebConversationIntent.parse("Réponds lui que je suis disponible") == .reply("que je suis disponible"))
        #expect(WebConversationIntent.parse("reply I am available") == .reply("I am available"))
        #expect(WebConversationIntent.parse("oui") == .accept)
        #expect(WebConversationIntent.parse("yes") == .accept)
        #expect(WebConversationIntent.parse("non") == .decline)
        #expect(WebConversationIntent.parse("no") == .decline)
        #expect(WebConversationIntent.parse("envoie !") == .send)
        #expect(WebConversationIntent.parse("send it") == .send)
        #expect(WebConversationIntent.parse("change the last sentence") == .revise("change the last sentence"))
        #expect(WebConversationIntent.parse("lis cette conversation") == .read)
        #expect(WebConversationIntent.parse("read this conversation") == .read)
    }

    @Test("Review binds exactly to the selected source and draft")
    func reviewGate() {
        var draft = WebConversationDraft()
        let now = Date(timeIntervalSince1970: 1_000)
        #expect(Bool(draft.begin(Self.source())))
        #expect(Bool(draft.edit("Yes, tomorrow.")))
        #expect(Bool(!draft.claimSend(current: Self.source(), at: now)))
        #expect(Bool(draft.reviewed(at: now)))
        #expect(Bool(!draft.claimSend(current: Self.source(text: "Changed message"), at: now)))
        #expect(Bool(draft.edit("Tomorrow at noon.")))
        #expect(Bool(!draft.claimSend(current: Self.source(), at: now)))
        #expect(Bool(draft.reviewed(at: now)))
        #expect(Bool(!draft.claimSend(current: Self.source(), at: now.addingTimeInterval(300))))
        #expect(Bool(draft.claimSend(current: Self.source(), at: now.addingTimeInterval(1))))
        draft.finish(verified: false)
        #expect(draft.phase == .uncertain)
        #expect(Bool(!draft.begin(Self.source())))
        #expect(Bool(!draft.edit("Retry")))
        draft.cancel()
        #expect(draft.phase == .uncertain)
    }

    @Test("Interrupted sends stay uncertain")
    func cancellation() {
        var draft = WebConversationDraft()
        #expect(Bool(draft.begin(Self.source())))
        #expect(Bool(draft.edit("Yes"))); #expect(Bool(draft.reviewed())); #expect(Bool(draft.claimSend(current: Self.source())))
        draft.cancel()
        #expect(draft.phase == .uncertain)
        draft.finish(verified: true)
        #expect(draft.phase == .uncertain)
    }

    @Test("Invalid edits revoke a previous review", arguments: ["", " \n ", String(repeating: "a", count: 4_001)])
    func invalidEditRevokesReview(text: String) {
        var draft = WebConversationDraft()
        #expect(Bool(draft.begin(Self.source()))); #expect(Bool(draft.edit("Old reviewed reply"))); #expect(Bool(draft.reviewed()))
        #expect(Bool(!draft.edit(text)))
        #expect(draft.phase == .reviewing)
        #expect(Bool(!draft.reviewed()))
        #expect(Bool(!draft.claimSend(current: Self.source())))
        #expect(draft.body != "Old reviewed reply")
    }

    @Test("Malformed observations cannot authorize a send")
    func resultValidation() throws {
        #expect(WebConversationScriptResult.parse("{\"status\":\"ready\"}") == nil)
        #expect(WebConversationScriptResult.parse("{\"status\":\"verified\"}") == nil)
        #expect(WebConversationScriptResult.parse("{\"status\":\"signin\"}")?.status == .signin)
        let invalid = WebConversationSnapshot(site: .news, conversationID: "thread", recipient: "Alex", accountID: "me", messageID: "1", messageText: "Hello", editorID: "editor", outgoingMessageIDs: [])
        #expect(!invalid.isValid)
        #expect(!WebConversationDraft.validBody(" \n "))
        #expect(!WebConversationDraft.validBody("hello\u{0000}"))
    }

    @Test("Durable attempts contain no source text and prohibit ambiguous retries")
    func durableJournal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = WebConversationJournal(directory: directory), first = UUID(), session = UUID(), step = UUID()
        #expect(try journal.reserve(id: first, sessionID: session, stepID: step, snapshot: Self.source(), body: "Private reply"))
        let reopened = WebConversationJournal(directory: directory)
        #expect(try reopened.hasPending())
        #expect(try reopened.pendingID(for: Self.source()) == first)
        #expect(try reopened.pendingID(for: Self.source(.slack)) == nil)
        #expect(try !reopened.reserve(id: UUID(), sessionID: session, stepID: step, snapshot: Self.source(), body: "Private reply"))
        let saved = try String(contentsOf: directory.appendingPathComponent("browser-reply-journal.json"), encoding: .utf8)
        for text in ["Private reply", "Alex", "Are you available", "thread-1", "incoming-1", "linkedin"] { #expect(!saved.contains(text)) }
        try reopened.confirm(id: first, receiptID: "remote-message-2")
        #expect(try !reopened.hasPending())
        #expect(try !reopened.reserve(id: first, sessionID: session, stepID: step, snapshot: Self.source(), body: "Same operation"))
        let second = UUID()
        #expect(try reopened.reserve(id: second, sessionID: session, stepID: step, snapshot: Self.source(), body: "New reply"))
        try reopened.reconcile(id: second, sent: false)
        #expect(try !reopened.hasPending())
    }
}
