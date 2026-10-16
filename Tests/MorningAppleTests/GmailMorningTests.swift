import Foundation
import MorningCore
import Synchronization
import Testing
@testable import MorningApple

/// Synthetic HTTP and invented mail only. These tests neither access Google nor Keychain.
@Suite("Gmail morning and send safety — synthetic protocol evidence")
@MainActor
struct GmailMorningTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let client = "123456789-synthetic.apps.googleusercontent.com"
    private let scheme = "com.googleusercontent.apps.123456789-synthetic"
    private let state = String(repeating: "s", count: 43)
    private var attentionUnavailable: GmailAttentionService { .init(generator: { _ in throw GmailAttentionError.unavailable }, available: { false }) }

    @Test func languagePresentationChangeKeepsLiteralDraftAndRequiresNewReviewWithoutSending() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1 }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let conversation = GmailMorningConversation(service: service, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("Envoie-moi un mail objet «Exact subject» texte «Café e\u{301} stays exact.»", context: id)
        let before = Data(conversation.draftText.utf8), recipient = conversation.recipient
        #expect(conversation.canSendSelfMessage)
        conversation.appLanguageDidChange()
        #expect(Data(conversation.draftText.utf8) == before && conversation.recipient == recipient)
        #expect(!conversation.canSendSelfMessage && posts == 0)
        await conversation.respond("send it", context: id)
        #expect(posts == 0 && conversation.canSendSelfMessage)
    }

    @Test func newSelfMessageUsesNativeProfileExactMIMEAndOneDurableClaim() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts: [URLRequest] = []
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            posts.append(request); return response(request, ["id": "sent123", "labelIds": ["SENT"]])
        }
        let session = try await access(service)
        let body = "Exact synthetic test.\nCafé e\u{301}.  "
        let draft = try await service.prepareSelfMessage(subject: "Test MORE", body: body, session: session, generation: nil)
        #expect(draft.recipient == "owner@example.invalid" && draft.body.utf8.elementsEqual(body.utf8))
        #expect(try await service.sendSelfMessage(draft, operationID: "self-one", session: session, generation: nil) == .sent)
        #expect(try await service.sendSelfMessage(draft, operationID: "self-one", session: session, generation: nil) == .sent)
        #expect(posts.count == 1)
        let request = try #require(posts.first)
        let requestBody = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        #expect(payload["threadId"] == nil)
        let mime = try decodeRaw(#require(payload["raw"]))
        #expect(mime.contains("From: owner@example.invalid\r\nTo: owner@example.invalid\r\n"))
        #expect(!mime.contains("In-Reply-To:") && !mime.contains("References:") && !mime.contains("Re:"))
        #expect(mime.contains("Subject: =?UTF-8?B?" + Data("Test MORE".utf8).base64EncodedString()))
        let encoded = try #require(mime.components(separatedBy: "\r\n\r\n").last)
        let decoded = try #require(Data(base64Encoded: encoded, options: .ignoreUnknownCharacters))
        #expect(decoded == Data(body.utf8))
        let changed = try await service.prepareSelfMessage(subject: "Test MORE", body: "Different text", session: session, generation: nil)
        #expect(try await service.sendSelfMessage(changed, operationID: "self-one", session: session, generation: nil) == .draftMismatch)
        #expect(posts.count == 1)
        let journal = try String(contentsOf: context.directory.appendingPathComponent("gmail-send-journal.json"), encoding: .utf8)
        #expect(!journal.contains("owner@example") && !journal.contains("Test MORE") && !journal.contains("Exact synthetic"))
    }

    @Test func selfMessageProfileFailureOrAccountReplacementCannotSend() async throws {
        let context = Context(); defer { context.cleanup() }
        var address = "owner@example.invalid", posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.httpMethod == "POST" { posts += 1 }
            return response(request, ["emailAddress": address])
        }
        let session = try await access(service)
        let draft = try await service.prepareSelfMessage(subject: "A", body: "B", session: session, generation: nil)
        address = "other@example.invalid"
        await #expect(throws: GmailConnectionError.connectionChanged) {
            try await service.sendSelfMessage(draft, operationID: "wrong-account", session: session, generation: nil)
        }
        address = ""
        await #expect(throws: GmailConnectionError.invalidResponse) {
            try await service.prepareSelfMessage(subject: "A", body: "B", session: session, generation: nil)
        }
        #expect(posts == 0)
        let readOnly = try await access(service, .readMessages)
        await #expect(throws: GmailConnectionError.sendAccessRequired) {
            try await service.prepareSelfMessage(subject: "A", body: "B", session: readOnly, generation: nil)
        }
    }

    @Test func selfMessageTimeoutAndCancellationOnlyReconcileStableMessageID() async throws {
        for cancel in [false, true] {
            let context = Context(); defer { context.cleanup() }
            var posts = 0, sentID = ""
            let route: GmailConnectionService.Transport = { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
                if request.httpMethod == "POST" {
                    posts += 1
                    let requestBody = try #require(request.httpBody)
        let payload = try #require(JSONSerialization.jsonObject(with: requestBody) as? [String: String])
                    let mime = try decodeRaw(#require(payload["raw"]))
                    sentID = try #require(mime.components(separatedBy: "\r\n").first { $0.hasPrefix("Message-ID: ") }).replacingOccurrences(of: "Message-ID: ", with: "")
                    if cancel { throw CancellationError() }
                    throw URLError(.timedOut)
                }
                if request.url?.path.hasSuffix("/messages") == true {
                    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems
                    #expect(query?.first { $0.name == "q" }?.value == "in:sent rfc822msgid:" + sentID.dropFirst().dropLast())
                    return response(request, ["resultSizeEstimate": 0])
                }
                return response(request, [:])
            }
            let service = makeService(context, route), session = try await access(service)
            let draft = try await service.prepareSelfMessage(subject: "Test MORE", body: "Exact body", session: session, generation: nil)
            if cancel {
                await #expect(throws: CancellationError.self) {
                    try await service.sendSelfMessage(draft, operationID: "ambiguous-self", session: session, generation: nil)
                }
            } else {
                #expect(try await service.sendSelfMessage(draft, operationID: "ambiguous-self", session: session, generation: nil) == .uncertain)
            }
            #expect(try await makeService(context, route).sendSelfMessage(draft, operationID: "ambiguous-self", session: session, generation: nil) == .uncertain)
            #expect(posts == 1)
        }
    }

    @Test func emptyInboxOffersOrdinarySelfNoteAndLiteralDraftRequiresSeparateReviewedSend() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let conversation = GmailMorningConversation(service: service,
            selfDrafts: GmailSelfMessageDraftService(generator: { _ in Issue.record("Literal text must avoid model"); return "{}" }, available: { false }),
            attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        #expect(conversation.state == .choosingMailAction && conversation.canComposeSelfMessage)
        await conversation.respond("Envoie-moi un mail objet «Test MORE» texte «Exact body.»", context: id)
        #expect(conversation.isComposingSelfMessage && conversation.canSendSelfMessage)
        #expect(conversation.selfMessageSubject == "Test MORE" && conversation.draftText == "Exact body.")
        #expect(posts == 0)
        await conversation.respond("oui", context: id)
        #expect(posts == 0)
        conversation.editSelfMessage(subject: "Test MORE", body: "Edited body.", context: id)
        #expect(!conversation.canSendSelfMessage)
        await conversation.respond("envoie", context: id)
        #expect(posts == 0)
        await conversation.reviewSelfMessage(subject: "Test MORE", body: "Edited body.", context: id)
        await conversation.respond("envoie", context: id)
        await conversation.respond("envoie", context: id)
        #expect(posts == 1 && conversation.isCompleted && conversation.lastSendOutcome == .sent)
    }

    @Test func selfMessageRequiresSavedGrantAndRejectsAReplacedGrant() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = GmailConnectionService(transport: { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.httpMethod == "POST" { posts += 1 }
            return response(request, ["emailAddress": "owner@example.invalid"])
        }, now: { instant }, credentialStorage: context.storage, privacyControl: context.privacy,
            configurationProvider: { try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [scheme]) },
            installationID: { context.installation }, allowsUnsavedSends: false)
        let unsaved = try await access(service)
        await #expect(throws: GmailConnectionError.connectionChanged) {
            try await service.prepareSelfMessage(subject: "A", body: "B", session: unsaved, generation: nil)
        }
        try service.saveConnection(session: unsaved, generation: nil)
        let saved = try #require(try await service.restoreConnection(generation: nil))
        let draft = try await service.prepareSelfMessage(subject: "A", body: "B", session: saved, generation: nil)
        try service.saveConnection(session: await access(service), generation: nil)
        await #expect(throws: GmailConnectionError.connectionChanged) {
            try await service.sendSelfMessage(draft, operationID: "replaced", session: saved, generation: nil)
        }
        #expect(posts == 0)
    }

    @Test func aLateSelfProfileCannotRestoreClearedContextAndFailedRevisionCannotSendOldDraft() async throws {
        let context = Context(); defer { context.cleanup() }
        var release: CheckedContinuation<Void, Never>?, delays = true, posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true {
                if delays { await withCheckedContinuation { release = $0 } }
                return response(request, ["emailAddress": "owner@example.invalid"])
            }
            if request.httpMethod == "POST" { posts += 1 }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let conversation = GmailMorningConversation(service: service,
            selfDrafts: GmailSelfMessageDraftService(generator: { _ in "{}" }, available: { false }),
            attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        let pending = Task { await conversation.beginSelfMessage(intention: "objet «Test MORE» texte «Exact body»", context: id) }
        while release == nil { await Task.yield() }
        conversation.clear(); release?.resume(); await pending.value
        #expect(conversation.context == nil && conversation.recipient == nil && conversation.draftText.isEmpty)
        delays = false
        await conversation.begin(context: id, generation: nil)
        await conversation.beginSelfMessage(intention: "objet «Test MORE» texte «Exact body»", context: id)
        #expect(conversation.canSendSelfMessage)
        await conversation.respond("Change la dernière phrase", context: id)
        #expect(conversation.state == .reviewingSelfMessage && !conversation.canSendSelfMessage)
        await conversation.respond("envoie", context: id)
        #expect(posts == 0)
    }

    @Test func sendingRequiresExplicitScopeAndReadGrantCannotEscalate() async throws {
        let context = Context(); defer { context.cleanup() }
        var mailRequests = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            mailRequests += 1; return response(request, [:])
        }
        let request = try attempt(.readAndSend)
        let query = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(query.first(where: { $0.name == "scope" })?.value == GmailConnectionService.readonlyScope + " " + GmailConnectionService.sendScope)
        #expect(query.first(where: { $0.name == "prompt" })?.value == "consent")
        let readonly = try await access(service, .readMessages)
        #expect(readonly.canReadMessages && !readonly.canSendMessages)
        await #expect(throws: GmailConnectionError.sendAccessRequired) {
            try await service.sendReply(to: mail(), body: "Invented reply", operationID: "synthetic-operation", session: readonly, generation: nil)
        }
        #expect(mailRequests == 0)
        let writable = try await access(service)
        #expect(writable.canSendMessages)
        try service.saveConnection(session: writable, generation: nil)
        let restored = try #require(try await service.restoreConnection(generation: nil))
        #expect(restored.canSendMessages && restored.canReadMessages)
    }

    @Test func mimeBindsRecipientAndThreadAndNeverCopiesBodyIntoHeaders() async throws {
        let context = Context(); defer { context.cleanup() }
        var post: URLRequest?
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            post = request
            return response(request, ["id": "sent123", "labelIds": ["SENT"]])
        }
        let session = try await access(service)
        let source = mail(subject: "Invented café\r\nBcc: intruder@example.invalid")
        let result = try await service.sendReply(to: source, body: "Invented text\nBcc: inert body text", operationID: "one", session: session, generation: nil)
        #expect(result == .sent)
        let request = try #require(post)
        #expect(request.httpMethod == "POST" && request.url?.path.hasSuffix("/messages/send") == true)
        let requestBody = try #require(request.httpBody)
        let payload = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: String])
        #expect(payload["threadId"] == "thread1")
        let mime = try decodeRaw(#require(payload["raw"]))
        #expect(mime.contains("From: owner@example.invalid\r\nTo: sender@example.invalid\r\n"))
        #expect(mime.contains("In-Reply-To: <source@example.invalid>\r\nReferences: <source@example.invalid>"))
        #expect(!mime.contains("\r\nBcc:"))
        #expect(mime.contains("Message-ID: <more.") && mime.contains("@morning.local>"))
        let journal = try String(contentsOf: context.directory.appendingPathComponent("gmail-send-journal.json"), encoding: .utf8)
        #expect(!journal.contains("sender@example") && !journal.contains("owner@example") && !journal.contains("Invented"))
        #expect(!journal.contains("SYNTHETIC"))
    }

    @Test func ambiguousSendSurvivesRestartAndOnlyReconcilesNeverRetransmits() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        var messageID = ""
        var found = false
        let route: GmailConnectionService.Transport = { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" {
                posts += 1
                let requestBody = try #require(request.httpBody)
        let payload = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: String])
                let mime = try decodeRaw(#require(payload["raw"]))
                messageID = try #require(mime.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("Message-ID:") }))
                    .replacingOccurrences(of: "Message-ID: ", with: "")
                throw URLError(.timedOut)
            }
            if request.url?.path.hasSuffix("/messages") == true {
                let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
                #expect(query.first(where: { $0.name == "q" })?.value == "in:sent rfc822msgid:" + messageID.dropFirst().dropLast())
                return response(request, found ? ["messages": [["id": "sent123"]]] : ["resultSizeEstimate": 0])
            }
            return response(request, ["id": "sent123", "labelIds": ["SENT"], "payload": ["headers": [["name": "Message-ID", "value": messageID]]]])
        }
        let first = makeService(context, route)
        let session = try await access(first)
        #expect(try await first.sendReply(to: mail(), body: "Invented", operationID: "uncertain", session: session, generation: nil) == .uncertain)
        let restarted = makeService(context, route)
        #expect(try await restarted.sendReply(to: mail(), body: "Invented", operationID: "uncertain", session: session, generation: nil) == .uncertain)
        #expect(posts == 1)
        found = true
        #expect(try await restarted.sendReply(to: mail(), body: "Invented", operationID: "uncertain", session: session, generation: nil) == .sent)
        #expect(try await makeService(context, route).sendReply(to: mail(), body: "Invented", operationID: "uncertain", session: session, generation: nil) == .sent)
        #expect(posts == 1)
    }

    @Test func unsafeRecipientAndForgetCannotStartSend() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.httpMethod == "POST" { posts += 1 }
            return response(request, ["emailAddress": "owner@example.invalid"])
        }
        let session = try await access(service)
        for address in ["sender@example.invalid\r\nBcc: other@example.invalid", "one@example.invalid,two@example.invalid", "missing"] {
            await #expect(throws: GmailConnectionError.invalidRecipient) {
                try await service.sendReply(to: mail(address: address), body: "Invented", operationID: "unsafe", session: session, generation: nil)
            }
        }
        _ = try context.privacy.beginForget()
        await #expect(throws: GmailConnectionError.sendJournalUnavailable) {
            try await service.sendReply(to: mail(), body: "Invented", operationID: "forget", session: session, generation: nil)
        }
        #expect(posts == 0)
    }

    @Test func headerDecoderKeepsReplyToSeparateFromModelAndRejectsAmbiguity() throws {
        var payload = object("a1", subject: "Invented", body: "Invented message")
        var part = try #require(payload["payload"] as? [String: Any])
        var headers = try #require(part["headers"] as? [[String: String]])
        headers.append(["name": "Reply-To", "value": "Invented Reply <reply@example.invalid>"])
        part["headers"] = headers; payload["payload"] = part
        let decoded = try GmailMessageDecoder.message(from: JSONSerialization.data(withJSONObject: payload), expectedID: "a1", retrievedAt: instant)
        #expect(decoded.replyAddress == "reply@example.invalid")
        #expect(decoded.internetMessageID == "<source@example.invalid>" && decoded.threadID == "thread1")
        #expect(GmailReplyAddress.parse("One <one@example.invalid>, Two <two@example.invalid>") == nil)
        #expect(GmailReplyAddress.parse("One <one@example.invalid> trailing") == nil)
        #expect(GmailReplyAddress.parse("One <one@example.invalid>\r\nBcc: hidden@example.invalid") == nil)
    }

    @Test func contextualConversationRequiresSendWordAndKeepsDraftForRevision() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"], ["id": "b2"]]]) }
            let id = request.url?.lastPathComponent ?? "a1"
            return response(request, object(id, subject: id == "b2" ? "Urgent invented deadline" : "Invented hello", body: "Invented request for a meeting."))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        var prompts: [String] = []
        let drafts = GmailReplyDraftService(generator: { prompt in
            prompts.append(prompt)
            return prompts.count == 1 ? "Invented draft reply." : "Invented revised reply."
        })
        var spoken: [String] = []
        let conversation = GmailMorningConversation(service: service, drafts: drafts, attention: attentionUnavailable, privacy: context.privacy, speak: { spoken.append($0) })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        #expect(conversation.state == .askingToReply && conversation.recipient == "sender@example.invalid")
        #expect(conversation.summary.range(of: "Invented hello")!.lowerBound < conversation.summary.range(of: "Urgent invented deadline")!.lowerBound)
        await conversation.respond("oui", context: id)
        #expect(conversation.state == .askingForIntention)
        await conversation.respond("Dis que je suis disponible demain", context: id)
        #expect(conversation.state == .reviewingReply && posts == 0)
        await conversation.respond("oui", context: id)
        #expect(posts == 0 && conversation.state == .reviewingReply)
        await conversation.respond("change la dernière phrase", context: id)
        #expect(prompts.count == 2 && prompts[1].contains("previousReply") && prompts[1].contains("Invented draft reply."))
        await conversation.respond("n’envoie pas", context: id)
        #expect(posts == 0)
        await conversation.respond("envoyer", context: id)
        #expect(posts == 1 && conversation.isCompleted)
        #expect(conversation.lastSendOutcome == .sent && spoken.last == conversation.message)
        #expect(spoken.last?.contains("sender@example.invalid") == true)
        await conversation.respond("envoyer", context: id)
        #expect(posts == 1)
        conversation.clear()
        #expect(conversation.draftText.isEmpty && conversation.recipient == nil && conversation.summary.isEmpty)
    }

    @Test func unavailableLocalModelStillAllowsVoiceDecline() async throws {
        let context = Context(); defer { context.cleanup() }
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
            return response(request, object("a1", subject: "Invented", body: "Invented message"))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let drafts = GmailReplyDraftService(generator: { _ in "Never generated" }, availability: { "Synthetic unavailable" })
        let conversation = GmailMorningConversation(service: service, drafts: drafts, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("oui", context: id)
        await conversation.respond("Invented intention", context: id)
        #expect(conversation.isAwaitingResponse && conversation.state == .askingForIntention)
        await conversation.respond("non", context: id)
        #expect(conversation.isCompleted)
    }

    @Test func removedReplacedOrForgottenSavedGrantCannotReadOrSendWithItsOldToken() async throws {
        for change in ["disconnect", "replace", "forget"] {
            let context = Context(); defer { context.cleanup() }
            var gmailRequests = 0
            let service = makeService(context) { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                gmailRequests += 1
                return response(request, [:])
            }
            try service.saveConnection(session: await access(service), generation: nil)
            let oldSession = try #require(try await service.restoreConnection(generation: nil))
            switch change {
            case "disconnect": try service.disconnect()
            case "replace": try service.saveConnection(session: await access(service), generation: nil)
            default:
                let forget = try context.privacy.beginForget()
                try context.privacy.finishForget(expectedGeneration: #require(forget.generation))
            }
            await #expect(throws: GmailConnectionError.connectionChanged) { try await service.inboxUnreadCount(session: oldSession) }
            await #expect(throws: GmailConnectionError.connectionChanged) { try await service.unreadInboxMessages(session: oldSession) }
            await #expect(throws: GmailConnectionError.connectionChanged) { try await service.message(id: "a1", session: oldSession) }
            await #expect(throws: GmailConnectionError.connectionChanged) {
                try await service.sendReply(to: mail(), body: "Invented reply", operationID: "old-grant", session: oldSession, generation: nil)
            }
            #expect(gmailRequests == 0)
        }
    }

    @Test func disconnectDuringProfileReadPreventsTheSendPost() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true {
                try context.storage.remove()
                return response(request, ["emailAddress": "owner@example.invalid"])
            }
            posts += 1
            return response(request, ["id": "sent123"])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let saved = try #require(try await service.restoreConnection(generation: nil))
        await #expect(throws: GmailConnectionError.connectionChanged) {
            try await service.sendReply(to: mail(), body: "Invented reply", operationID: "changed-during-profile", session: saved, generation: nil)
        }
        #expect(posts == 0)
        #expect(!FileManager.default.fileExists(atPath: context.directory.appendingPathComponent("gmail-send-journal.json").path))
    }

    @Test func productionSendPolicyRejectsAnUnsavedAuthorizationAttempt() async throws {
        let context = Context(); defer { context.cleanup() }
        var gmailRequests = 0
        let service = GmailConnectionService(transport: { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            gmailRequests += 1
            return response(request, [:])
        }, now: { instant }, credentialStorage: context.storage, privacyControl: context.privacy,
            configurationProvider: { try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [scheme]) },
            installationID: { context.installation }, allowsUnsavedSends: false)
        let unsaved = try await access(service)
        await #expect(throws: GmailConnectionError.connectionChanged) {
            try await service.sendReply(to: mail(), body: "Invented reply", operationID: "unsaved", session: unsaved, generation: nil)
        }
        #expect(gmailRequests == 0)
    }

    @Test func previousReceiptCannotCertifyADifferentRecipientThreadOrBody() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            posts += 1
            return response(request, ["id": "sent123"])
        }
        let saved = try await access(service)
        #expect(try await service.sendReply(to: mail(), body: "Invented original", operationID: "one-reply", session: saved, generation: nil) == .sent)
        #expect(try await service.sendReply(to: mail(), body: "Invented correction", operationID: "one-reply", session: saved, generation: nil) == .draftMismatch)
        #expect(try await service.sendReply(to: mail(address: "other@example.invalid"), body: "Invented original", operationID: "one-reply", session: saved, generation: nil) == .draftMismatch)
        let anotherThread = GmailMessage(id: "a1", sender: "Invented Sender", subject: "Invented subject", receivedAt: instant,
            plainTextBody: "Invented mail", bodyWasTruncated: false, bodyUnavailable: false, retrievedAt: instant,
            replyAddress: "sender@example.invalid", internetMessageID: "<other@example.invalid>", threadID: "thread2")
        #expect(try await service.sendReply(to: anotherThread, body: "Invented original", operationID: "one-reply", session: saved, generation: nil) == .draftMismatch)
        #expect(try await service.sendReply(to: mail(), body: "Invented original", operationID: "one-reply", session: saved, generation: nil) == .sent)
        #expect(posts == 1)
        let journal = try String(contentsOf: context.directory.appendingPathComponent("gmail-send-journal.json"), encoding: .utf8)
        #expect(!journal.contains("Invented") && !journal.contains("sender@example") && !journal.contains("owner@example"))
    }

    @Test func conversationInvalidatesPrivateDraftAfterDisconnectAndDoesNotCertifyRecoveryMismatch() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0, draftsPrepared = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
            return response(request, object("a1", subject: "Invented", body: "Invented message"))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let drafts = GmailReplyDraftService(generator: { _ in draftsPrepared += 1; return "Invented draft \(draftsPrepared)." })
        let conversation = GmailMorningConversation(service: service, drafts: drafts, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("oui", context: id)
        await conversation.respond("Invented intention", context: id)
        try service.disconnect()
        await conversation.respond("envoyer", context: id)
        #expect(posts == 0 && conversation.state == .unavailable)
        #expect(conversation.draftText.isEmpty && conversation.summary.isEmpty && conversation.recipient == nil)
        await conversation.respond("non", context: id)
        #expect(conversation.completedExecutionOutcome == .unavailable)

        try service.saveConnection(session: await access(service), generation: nil)
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("oui", context: id)
        await conversation.respond("Invented intention", context: id)
        await conversation.respond("envoyer", context: id)
        #expect(posts == 1 && conversation.completedExecutionOutcome == .completed)
        conversation.clear() // Background or restart lost the in-memory dialogue before advancement.
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("oui", context: id)
        await conversation.respond("Invented different intention", context: id)
        await conversation.respond("envoyer", context: id)
        #expect(posts == 1 && conversation.lastSendOutcome == .draftMismatch && conversation.state == .uncertain)
        #expect(!conversation.message.contains("confirme l’envoi"))
        await conversation.respond("non", context: id)
        #expect(conversation.completedExecutionOutcome == .uncertain)
    }

    @Test func decliningFailedReadStaysUnavailableAndAnObservedEmptyInboxOffersSelfNoteOrContinue() async throws {
        for failReading in [true, false] {
            let context = Context(); defer { context.cleanup() }
            let service = makeService(context) { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                if failReading { throw URLError(.notConnectedToInternet) }
                return response(request, ["resultSizeEstimate": 0])
            }
            try service.saveConnection(session: await access(service), generation: nil)
            let conversation = GmailMorningConversation(service: service, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
            let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
            await conversation.begin(context: id, generation: nil)
            if failReading {
                #expect(conversation.state == .unavailable && conversation.readOutcome == .unavailable)
                await conversation.respond("non", context: id)
                #expect(conversation.isCompleted && conversation.completedExecutionOutcome == .unavailable)
            } else {
                #expect(conversation.state == .choosingMailAction && conversation.readOutcome == .read)
                await conversation.respond("continuer", context: id)
                #expect(conversation.readOutcome == .read && conversation.completedExecutionOutcome == .completed)
            }
        }
    }

    @Test func interruptedProviderSendAndConfirmedReceiptSurviveNarrationCancellation() async throws {
        for receiptConfirmed in [false, true] {
            let context = Context(); defer { context.cleanup() }
            var release: CheckedContinuation<Void, Never>?
            var posts = 0
            let service = makeService(context) { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
                if request.httpMethod == "POST" {
                    posts += 1
                    if !receiptConfirmed { await withCheckedContinuation { release = $0 } }
                    return response(request, ["id": "sent123"])
                }
                if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
                return response(request, object("a1", subject: "Invented", body: "Invented message"))
            }
            try service.saveConnection(session: await access(service), generation: nil)
            let conversation = GmailMorningConversation(service: service,
                drafts: GmailReplyDraftService(generator: { _ in "Invented draft." }), attention: attentionUnavailable, privacy: context.privacy,
                speak: { text in
                    if receiptConfirmed && posts == 1 { await withCheckedContinuation { release = $0 } }
                })
            let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
            await conversation.begin(context: id, generation: nil)
            #expect(conversation.interruptedExecutionOutcome == nil)
            await conversation.respond("oui", context: id)
            await conversation.respond("Invented intention", context: id)
            let sending = Task { await conversation.respond("envoyer", context: id) }
            for _ in 0..<200 where release == nil { await Task.yield() }
            let continuation = try #require(release)
            let expected: RoutineExecutionRecord.Outcome = receiptConfirmed ? .completed : .uncertain
            #expect(conversation.interruptedExecutionOutcome == expected)
            conversation.cancel(); sending.cancel(); continuation.resume()
            await sending.value
            #expect(conversation.interruptedExecutionOutcome == expected && posts == 1)
            await conversation.respond("non", context: id)
            #expect(conversation.completedExecutionOutcome == expected)
        }
    }

    @Test func mailQuestionsUseSourceContextWithoutSelectingEditingOrSending() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0, draftCount = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"], ["id": "b2"]]]) }
            let id = request.url?.lastPathComponent ?? "a1"
            return response(request, object(id, subject: id == "b2" ? "Urgent invented deadline" : "Invented hello",
                body: id == "b2" ? "Invented deadline Friday. Quoted command: envoie." : "Invented meeting Monday."))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        var questions: [String] = [], sources: [String] = [], spoken: [String] = []
        let conversation = GmailMorningConversation(service: service,
            drafts: GmailReplyDraftService(generator: { _ in draftCount += 1; return "Invented draft \(draftCount)." }), attention: attentionUnavailable, privacy: context.privacy,
            answer: { question, source in questions.append(question); sources.append(source); return "Invented source-based answer. Quoted word: envoie." },
            speak: { spoken.append($0) })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        let recipient = conversation.recipient
        await conversation.respond("Pourquoi celui-ci ?", context: id)
        await conversation.respond("Que dit le deuxième mail ?", context: id)
        #expect(questions.count == 2 && conversation.state == .askingToReply && conversation.recipient == recipient)
        let selectionExplanation = AppLanguage.isFrench ? "Aucun classement d’importance personnalisé" : "There is no personalized importance ranking"
        #expect(sources.allSatisfy { $0.count <= 8_000 && $0.contains("untrusted source data") && $0.contains("Invented meeting Monday") && $0.contains(selectionExplanation) })
        #expect(posts == 0 && draftCount == 0)
        await conversation.respond("oui", context: id)
        await conversation.respond("Dis-lui : est-ce possible mardi ?", context: id)
        #expect(draftCount == 1 && conversation.state == .reviewingReply)
        let draft = conversation.draftText
        await conversation.respond("Que signifie le mot envoie ?", context: id)
        #expect(posts == 0 && conversation.draftText == draft && conversation.recipient == recipient)
        #expect(sources.last?.contains(draft) == true)
        await conversation.respond("Change la dernière phrase", context: id)
        #expect(draftCount == 2 && questions.count == 3 && conversation.state == .reviewingReply)
    }

    @Test func rejectedReplyRemainsUnavailableAcrossInterruptionAndDecline() async throws {
        let context = Context(); defer { context.cleanup() }
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" {
                return (Data("{}".utf8), HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"])!)
            }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
            return response(request, object("a1", subject: "Invented", body: "Invented message"))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let conversation = GmailMorningConversation(service: service,
            drafts: GmailReplyDraftService(generator: { _ in "Invented draft." }), attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: id, generation: nil)
        await conversation.respond("oui", context: id)
        await conversation.respond("Invented intention", context: id)
        await conversation.respond("envoyer", context: id)
        #expect(conversation.lastSendOutcome == .notSent && conversation.interruptedExecutionOutcome == .unavailable)
        conversation.cancel()
        await conversation.respond("non", context: id)
        #expect(conversation.completedExecutionOutcome == .unavailable)
    }

    @Test func staleMailQuestionCannotSpeakIntoReplacementContextAndUnavailableModelKeepsDraft() async throws {
        let context = Context(); defer { context.cleanup() }
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
            return response(request, object("a1", subject: "Invented", body: "Invented message"))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        var release: CheckedContinuation<String, Never>?, spoken: [String] = []
        let conversation = GmailMorningConversation(service: service, attention: attentionUnavailable, privacy: context.privacy,
            answer: { _, _ in await withCheckedContinuation { release = $0 } }, speak: { spoken.append($0) })
        let old = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: old, generation: nil)
        let question = Task { await conversation.respond("Pourquoi celui-ci ?", context: old) }
        for _ in 0..<200 where release == nil { await Task.yield() }
        let continuation = try #require(release)
        let replacement = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await conversation.begin(context: replacement, generation: nil)
        continuation.resume(returning: "Stale private answer.")
        await question.value
        #expect(!spoken.contains("Stale private answer.") && conversation.context == replacement && conversation.state == .askingToReply)

        let unavailable = GmailMorningConversation(service: service,
            drafts: GmailReplyDraftService(generator: { _ in "Invented draft." }), attention: attentionUnavailable, privacy: context.privacy,
            answer: { _, _ in throw MorningVoiceConversationError.unavailable }, speak: { spoken.append($0) })
        await unavailable.begin(context: replacement, generation: nil)
        await unavailable.respond("oui", context: replacement)
        await unavailable.respond("Invented intention", context: replacement)
        let draft = unavailable.draftText
        await unavailable.respond("Pourquoi cette phrase ?", context: replacement)
        #expect(unavailable.state == .reviewingReply && unavailable.draftText == draft)
        let availabilityExplanation = AppLanguage.isFrench ? "La conversation locale n’est pas disponible" : "Local conversation is unavailable"
        #expect(unavailable.message.contains(availabilityExplanation) && unavailable.lastSendOutcome == nil)
    }

    @Test func nativeDialogueTerminalCannotSendTheOlderMailWithoutFreshSeparateReview() async throws {
        for selfMessage in [false, true] {
            let context = Context(); defer { context.cleanup() }
            var posts = 0, spoken: [String] = []
            let service = makeService(context) { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
                if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
                if request.url?.path.hasSuffix("/messages") == true {
                    return response(request, selfMessage ? ["resultSizeEstimate": 0] : ["messages": [["id": "a1"]]])
                }
                return response(request, object("a1", subject: "Invented", body: "Invented request"))
            }
            try service.saveConnection(session: await access(service), generation: nil)
            let mail = GmailMorningConversation(service: service,
                drafts: GmailReplyDraftService(generator: { _ in "Exact older reply." }), attention: attentionUnavailable, privacy: context.privacy,
                speak: { spoken.append($0) })
            let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
            await mail.begin(context: id, generation: nil)
            if selfMessage { await mail.beginSelfMessage(intention: "objet «Test MORE» texte «Exact older note.»", context: id) }
            else { await mail.respond("oui", context: id); await mail.respond("Invented intention", context: id) }
            let oldDraft = mail.draftText, oldRecipient = mail.recipient
            let native = NativeMomentConversation(provider: MailHandoffNativeProvider(), directory: context.directory, speak: { _ in })
            // Same focus handoff as the ordinary Store native entry points.
            mail.revokeReviewPreservingDraft(context: id)
            _ = await native.respond("Reminder: water plants no date", context: id)
            _ = await native.respond("add it", context: id)
            #expect(native.phase == .completed)
            #expect(mail.draftText == oldDraft && mail.recipient == oldRecipient && !mail.canSendSelfMessage)
            await mail.respond("envoie", context: id)
            #expect(posts == 0 && spoken.last?.contains(oldDraft) == true)
            #expect(mail.draftText == oldDraft && mail.recipient == oldRecipient)
            await mail.respond("envoie", context: id)
            await mail.respond("envoie", context: id)
            #expect(posts == 1 && mail.lastSendOutcome == .sent)
        }
    }

    @Test func interruptedHandoffReviewKeepsTouchAndVoiceSendRevokedUntilACompleteReview() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0, interruptReview = false
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let mail = GmailMorningConversation(service: service, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in
            if interruptReview { throw CancellationError() }
        })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await mail.begin(context: id, generation: nil)
        await mail.beginSelfMessage(intention: "objet «Test MORE» texte «Exact body»", context: id)
        mail.revokeReviewPreservingDraft(context: .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()))
        #expect(mail.canSendSelfMessage)
        mail.revokeReviewPreservingDraft(context: id)
        #expect(!mail.canSendSelfMessage)
        interruptReview = true
        await mail.respond("envoie", context: id)
        await mail.respond("envoie", context: id)
        #expect(!mail.canSendSelfMessage && posts == 0)
        interruptReview = false
        await mail.reviewSelfMessage(subject: mail.selfMessageSubject, body: mail.draftText, context: id)
        #expect(mail.canSendSelfMessage && posts == 0)
        await mail.respond("envoie", context: id)
        mail.revokeReviewPreservingDraft(context: id)
        #expect(posts == 1 && mail.lastSendOutcome == .sent && mail.isCompleted)
    }

    @Test func handoffDoesNotResetAnUncertainSendOrItsDurableClaim() async throws {
        let context = Context(); defer { context.cleanup() }
        var posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; throw URLError(.timedOut) }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let mail = GmailMorningConversation(service: service, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await mail.begin(context: id, generation: nil)
        await mail.beginSelfMessage(intention: "objet «Test MORE» texte «Exact body»", context: id)
        await mail.respond("envoie", context: id)
        #expect(mail.state == .uncertain && mail.lastSendOutcome == .uncertain && posts == 1)
        mail.revokeReviewPreservingDraft(context: id)
        await mail.respond("envoie", context: id)
        #expect(mail.state == .uncertain && mail.lastSendOutcome == .uncertain && posts == 1)
    }

    @Test func expiredBudgetKeepsReviewedDraftAndExtensionNeverRefetchesOrSends() async throws {
        let context = Context(); defer { context.cleanup() }
        var inboxFetches = 0, posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            if request.url?.path.hasSuffix("/messages") == true {
                inboxFetches += 1; return response(request, ["messages": [["id": "a1"]]])
            }
            return response(request, object("a1", subject: "Invented", body: "Invented request"))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let mail = GmailMorningConversation(service: service,
            drafts: GmailReplyDraftService(generator: { _ in "Exact retained draft." }), attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await mail.begin(context: id, generation: nil)
        await mail.respond("oui", context: id)
        await mail.respond("Invented intention", context: id)
        let draft = mail.draftText, recipient = mail.recipient, summary = mail.summary
        #expect(mail.hasUnfinishedIntention && mail.state == .reviewingReply)
        #expect(GmailMomentBudgetPolicy.decision(state: mail.state, readOutcome: mail.readOutcome,
            hasUnfinishedIntention: mail.hasUnfinishedIntention, hasUncertainRecord: false,
            workInFlight: false) == .pauseKeepingDialogue)
        var timer = StepTimer(sessionID: id.sessionID, stepID: id.stepID, minutes: 1, at: instant)
        timer.markOpened(at: instant)
        let end = instant.addingTimeInterval(60)
        let claimed = timer.claimAlert(at: end)
        #expect(claimed)
        timer.pause(at: end)
        // The same pause boundary used by the Store does not clear the mail dialogue.
        mail.cancel()
        try StepTimerFile.save(timer, directory: context.directory)
        let extended = try #require(StepTimerFile.update(sessionID: id.sessionID, stepID: id.stepID,
            directory: context.directory, { $0.extend(expectedEnd: end, at: end.addingTimeInterval(600)) }))
        var resumed = extended.0
        resumed.resume(at: end.addingTimeInterval(600))
        try StepTimerFile.save(resumed, directory: context.directory)
        #expect(resumed.remaining(at: end.addingTimeInterval(600)) == 120)
        #expect(mail.context == id && mail.draftText == draft && mail.recipient == recipient && mail.summary == summary)
        #expect(mail.state == .reviewingReply && inboxFetches == 1 && posts == 0)
        await mail.respond("envoie", context: id)
        #expect(posts == 1 && inboxFetches == 1 && mail.lastSendOutcome == .sent)
    }

    @Test func unavailableRereadCannotResolveTheEarlierUncertainEffectAtDeadline() async throws {
        let context = Context(); defer { context.cleanup() }
        var readFails = false, posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/profile") == true { return response(request, ["emailAddress": "owner@example.invalid"]) }
            if request.httpMethod == "POST" { posts += 1; throw URLError(.timedOut) }
            if readFails { throw URLError(.notConnectedToInternet) }
            return response(request, ["resultSizeEstimate": 0])
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let mail = GmailMorningConversation(service: service, attention: attentionUnavailable, privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await mail.begin(context: id, generation: nil)
        await mail.beginSelfMessage(intention: "objet «Test MORE» texte «Exact body»", context: id)
        await mail.respond("envoie", context: id)
        let persistedOutcome = try #require(mail.interruptedExecutionOutcome)
        #expect(persistedOutcome == .uncertain && posts == 1)
        readFails = true
        // Restoring source text is a new read, never evidence about the older POST.
        await mail.begin(context: id, generation: nil)
        #expect(mail.state == .unavailable && mail.lastSendOutcome == nil)
        #expect(GmailMomentBudgetPolicy.decision(state: mail.state, readOutcome: mail.readOutcome,
            hasUnfinishedIntention: mail.hasUnfinishedIntention, hasUncertainRecord: persistedOutcome == .uncertain,
            workInFlight: false) == .pauseKeepingDialogue)
        mail.cancel()
        #expect(posts == 1)
    }

    @MainActor private final class MailHandoffNativeProvider: NativeMomentProviding {
        func destination(for kind: CaptureDestination) throws -> NativeMomentDestination {
            .init(id: "synthetic-list", sourceID: "synthetic-account", title: "Synthetic list", sourceTitle: "Synthetic account", kind: kind)
        }
        func validateDestination(_ destination: NativeMomentDestination) throws {}
        func upcomingReminders() async throws -> [ReminderSummary] { [] }
        func perform(_ action: NativeMomentAction) throws -> String { "synthetic-native-receipt" }
    }

    @Test func semanticSelectionKeepsObservedIdentityAndOwnerCanChooseAnotherReadMailWithoutFetchingOrSending() async throws {
        let context = Context(); defer { context.cleanup() }
        var reads = 0, posts = 0
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.httpMethod == "POST" { posts += 1; return response(request, ["id": "sent123"]) }
            reads += 1
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": (1...5).map { ["id": "m\($0)"] }]) }
            let id = request.url!.lastPathComponent
            var result = object(id, subject: "Same invented subject", body: "Invented readable source for \(id).")
            var payload = result["payload"] as! [String: Any]
            payload["headers"] = [["name": "From", "value": "Same invented name <\(id)@example.invalid>"],
                                  ["name": "Subject", "value": "Same invented subject"],
                                  ["name": "Message-ID", "value": "<\(id)@example.invalid>"]]
            result["payload"] = payload
            return response(request, result)
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let attention = GmailAttentionService(generator: { _ in
            let rows = ["m5", "m2", "m4"].map { ["id": $0, "summary": "Invented source summary.", "reason": "A tentative project request.", "quote": "Invented readable source"] }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["messages": rows]), as: UTF8.self)
        })
        let mail = GmailMorningConversation(service: service, drafts: .init(generator: { _ in "Invented draft." }), attention: attention,
            privacy: context.privacy, speak: { _ in })
        let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
        await mail.begin(context: id, generation: nil)
        #expect(mail.attentionSelection?.mode == .localProposal && mail.messageChoices.map(\.id) == ["m5", "m2", "m4", "m1", "m3"])
        #expect(mail.recipient == "m5@example.invalid")
        await mail.respond("oui", context: id); await mail.respond("Invented intention", context: id)
        #expect(mail.state == .reviewingReply && !mail.draftText.isEmpty)
        let readCount = reads
        await mail.chooseMessage(id: "not-observed", context: id)
        #expect(mail.recipient == "m5@example.invalid" && !mail.draftText.isEmpty)
        await mail.chooseMessage(id: "m3", context: id)
        #expect(mail.selectedMessageID == "m3" && mail.recipient == "m3@example.invalid" && mail.draftText.isEmpty)
        #expect(reads == readCount && posts == 0 && mail.state == .askingToReply)
        await mail.respond("envoie", context: id)
        #expect(posts == 0 && mail.state == .askingToReply)
        mail.clear()
        #expect(mail.messageChoices.isEmpty && mail.attentionSelection == nil)
    }

    @Test func lateAttentionAfterPauseClearForgetOrDisconnectCannotPublishOldMail() async throws {
        for interruption in ["pause", "clear", "forget", "disconnect"] {
            let context = Context(); defer { context.cleanup() }
            let service = makeService(context) { request in
                if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
                if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
                return response(request, object("a1", subject: "Invented subject", body: "Invented readable source."))
            }
            try service.saveConnection(session: await access(service), generation: nil)
            var release: CheckedContinuation<String, Never>?
            let attention = GmailAttentionService(generator: { _ in await withCheckedContinuation { release = $0 } })
            let mail = GmailMorningConversation(service: service, attention: attention, privacy: context.privacy, speak: { _ in })
            let id = MorningExecutionID(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID())
            let beginning = Task { await mail.begin(context: id, generation: nil) }
            while release == nil { await Task.yield() }
            if interruption == "pause" { mail.cancel() }
            else if interruption == "clear" { mail.clear() }
            else if interruption == "forget" { _ = try context.privacy.beginForget(); mail.clear() }
            else { try service.disconnect() }
            release?.resume(returning: "{\"messages\":[{\"id\":\"a1\",\"summary\":\"Old summary\",\"reason\":\"Old reason\",\"quote\":\"Invented readable source\"}]}")
            await beginning.value
            #expect(mail.attentionSelection == nil && mail.messageChoices.isEmpty && mail.summary.isEmpty && mail.recipient == nil)
        }
    }

    @Test func unreadableAttentionPreferencesKeepTheirBytesAndUseAnHonestFallback() async throws {
        let context = Context(); defer { context.cleanup() }
        let service = makeService(context) { request in
            if request.url?.host == "oauth2.googleapis.com" { return response(request, token()) }
            if request.url?.path.hasSuffix("/messages") == true { return response(request, ["messages": [["id": "a1"]]]) }
            return response(request, object("a1", subject: "Invented subject", body: "Invented readable source."))
        }
        try service.saveConnection(session: await access(service), generation: nil)
        let url = context.directory.appendingPathComponent(GmailAttentionPreferencesStore.fileName)
        let bytes = Data("damaged preferences".utf8); try bytes.write(to: url)
        let attention = GmailAttentionService(generator: { _ in Issue.record("Unreadable owner preferences must not be replaced or passed as empty"); return "{}" })
        let mail = GmailMorningConversation(service: service, attention: attention, privacy: context.privacy, speak: { _ in })
        await mail.begin(context: .init(sessionID: UUID(), routineVersionID: UUID(), stepID: UUID()), generation: nil)
        #expect(mail.attentionSelection?.fallback == .preferencesUnavailable && mail.state == .askingToReply)
        #expect(try Data(contentsOf: url) == bytes)
    }

    private func makeService(_ context: Context, _ transport: @escaping GmailConnectionService.Transport) -> GmailConnectionService {
        GmailConnectionService(transport: transport, now: { instant }, credentialStorage: context.storage,
            privacyControl: context.privacy, configurationProvider: {
                try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [scheme])
            }, installationID: { context.installation })
    }
    private func attempt(_ access: GmailAuthorizationAccess) throws -> GmailAuthorizationRequest {
        try GmailAuthorizationRequest(configuration: GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [scheme]),
            verifier: String(repeating: "v", count: 43), state: state, access: access)
    }
    private func access(_ service: GmailConnectionService, _ access: GmailAuthorizationAccess = .readAndSend) async throws -> GmailAccessSession {
        try await service.completeAuthorization(attempt(access), callbackURL: URL(string: "\(scheme):/oauth2redirect?state=\(state)&code=SYNTHETIC_CODE")!)
    }
    private func token() -> [String: Any] {
        ["access_token": "SYNTHETIC_ACCESS", "refresh_token": "SYNTHETIC_REFRESH", "token_type": "Bearer", "expires_in": 3600,
         "scope": GmailConnectionService.readonlyScope + " " + GmailConnectionService.sendScope]
    }
    private func response(_ request: URLRequest, _ object: [String: Any]) -> (Data, URLResponse) {
        (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!)
    }
    private func mail(subject: String = "Invented subject", address: String = "sender@example.invalid") -> GmailMessage {
        GmailMessage(id: "a1", sender: "Invented Sender <sender@example.invalid>", subject: subject, receivedAt: instant,
            plainTextBody: "Invented mail", bodyWasTruncated: false, bodyUnavailable: false, retrievedAt: instant,
            replyAddress: address, internetMessageID: "<source@example.invalid>", threadID: "thread1")
    }
    private func object(_ id: String, subject: String, body: String) -> [String: Any] {
        ["id": id, "threadId": "thread1", "internalDate": "1800000000000", "payload": ["mimeType": "text/plain",
            "headers": [["name": "From", "value": "Invented Sender <sender@example.invalid>"], ["name": "Subject", "value": subject],
                        ["name": "Message-ID", "value": "<source@example.invalid>"]],
            "body": ["size": body.utf8.count, "data": Data(body.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")]]]
    }
    private func decodeRaw(_ value: String) throws -> String {
        var encoded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        let data = try #require(Data(base64Encoded: encoded))
        return try #require(String(data: data, encoding: .utf8))
    }

    private final class Storage: GmailCredentialStorage, Sendable {
        let data = Mutex<Data?>(nil)
        func load() throws -> Data? { data.withLock { $0 } }
        func save(_ value: Data) throws { data.withLock { $0 = value } }
        func remove() throws { data.withLock { $0 = nil } }
    }
    private struct Context {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MORE-Gmail-Synthetic-\(UUID().uuidString)")
        let storage = Storage()
        let installation = UUID()
        var privacy: LocalDataControl { LocalDataControl(directory: directory) }
        func cleanup() { try? FileManager.default.removeItem(at: directory) }
    }
}
