import Foundation
import MorningCore
#if DEBUG
import Synchronization
#endif

/// Explicit, isolated protocol evidence. Never uses Keychain, URLSession or a real model.
@MainActor public enum GmailAttentionUITestFixture {
    public static let privateReplyFlag = "--ui-testing-private-gmail-reply"
    public static var isPrivateReplyRequested: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains(privateReplyFlag)
        #else
        false
        #endif
    }
    public static var isRequested: Bool {
        #if DEBUG
        return isPrivateReplyRequested || workspaceID(ProcessInfo.processInfo.arguments) != nil
        #else
        return false
        #endif
    }
    #if DEBUG
    public private(set) static var inboxReadCount = 0
    public private(set) static var bodyReadCount = 0
    #else
    public static var inboxReadCount: Int { 0 }
    public static var bodyReadCount: Int { 0 }
    #endif

    public static func conversationIfRequested(privacy: LocalDataControl,
        speak: @escaping @MainActor (String) async throws -> Void) -> GmailMorningConversation? {
        #if DEBUG
        if isPrivateReplyRequested {
            return privateReplyConversation(privacy: privacy, arguments: ProcessInfo.processInfo.arguments, speak: speak)
        }
        guard let workspace = workspaceID(ProcessInfo.processInfo.arguments) else { return nil }
        // A selected fixture always returns a synthetic service, including errors.
        // There is no fallback to a live credential/service after this boundary.
        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(workspace.uuidString)", isDirectory: true)
        return conversation(privacy: privacy, allowedDirectory: expected,
            fallback: ProcessInfo.processInfo.arguments.contains("--ui-testing-gmail-attention-fallback"), speak: speak)
        #else
        return nil
        #endif
    }

    /// Only invented payload fields actually received by the closed transport, scoped to this conversation.
    public static func privateReplyDiagnostic(context: MorningExecutionID?) -> String? {
        #if DEBUG
        guard let state = replyState, state.isCurrent, let context, state.conversation?.context == context,
              state.receivedContext == nil || state.receivedContext == context else { return nil }
        var proof = state.received
        proof["simulatedSendAttempts"] = String(state.sendAttempts)
        proof["inboxReads"] = String(state.inboxReads); proof["bodyReads"] = String(state.bodyReads)
        proof["sessionID"] = context.sessionID.uuidString
        proof["routineVersionID"] = context.routineVersionID.uuidString; proof["stepID"] = context.stepID.uuidString
        guard let data = try? JSONSerialization.data(withJSONObject: proof, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
        #else
        return nil
        #endif
    }

    /// Keeps the ordinary Connections screen inside this no-network fixture too.
    public static func connectionsIfRequested() -> ComposioService? {
        #if DEBUG
        guard isRequested else { return nil }
        return ComposioService(baseURL: URL(string: "https://synthetic-gmail-attention.invalid")!,
            tokenStore: MemoryTokens("synthetic-gmail-attention-installation"), executionStore: MemoryTokens(nil)) { request in
            guard let url = request.url, url.scheme == "https", url.host == "synthetic-gmail-attention.invalid",
                  url.port == nil, url.user == nil, url.password == nil, url.fragment == nil, url.query == nil,
                  request.httpMethod == "GET", request.httpBody == nil else { throw GmailConnectionError.permissionDenied }
            let payload: [String: Any]
            switch url.path {
            case "/v1/services": payload = ["services": []]
            case "/v1/connections": payload = ["connections": []]
            default: throw GmailConnectionError.permissionDenied
            }
            guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
                throw GmailConnectionError.invalidResponse
            }
            return (try JSONSerialization.data(withJSONObject: payload), response)
        }
        #else
        return nil
        #endif
    }

    #if DEBUG
    @MainActor private final class MemoryTokens: ComposioTokenStoring {
        private var value: String?
        init(_ value: String?) { self.value = value }
        func load() throws -> String? { value }
        func save(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }

    static func workspaceID(_ arguments: [String]) -> UUID? {
        guard arguments.contains("--ui-testing"), arguments.contains("--ui-testing-gmail-attention"),
              let value = arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") }) else { return nil }
        return UUID(uuidString: String(value.dropFirst("--ui-testing-workspace=".count)))
    }

    static func conversation(privacy: LocalDataControl, allowedDirectory: URL, fallback: Bool,
        speak: @escaping @MainActor (String) async throws -> Void) -> GmailMorningConversation {
        makeConversation(privacy: privacy, allowedDirectory: allowedDirectory, fallback: fallback, reply: nil, speak: speak)
    }

    static func privateReplyWorkspace(_ arguments: [String], directory: URL) -> UUID? {
        let workspaces = arguments.filter { $0.hasPrefix("--ui-testing-workspace=") }
        guard ["--ui-testing", "--fixture-mode", "--ui-testing-gmail-attention", privateReplyFlag].allSatisfy(arguments.contains),
              workspaces.count == 1, let id = UUID(uuidString: String(workspaces[0].dropFirst("--ui-testing-workspace=".count))) else { return nil }
        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(id.uuidString)", isDirectory: true)
        return expected.standardizedFileURL == directory.standardizedFileURL ? id : nil
    }

    static func privateReplyConversation(privacy: LocalDataControl, arguments: [String], french: Bool = AppLanguage.isFrench,
        speak: @escaping @MainActor (String) async throws -> Void) -> GmailMorningConversation {
        let state = ReplyState(enabled: privateReplyWorkspace(arguments, directory: privacy.directory) != nil, french: french, privacy: privacy)
        replyState = state
        let conversation = makeConversation(privacy: privacy, allowedDirectory: privacy.directory, fallback: false, reply: state, speak: speak)
        state.conversation = conversation
        return conversation
    }

    private static func makeConversation(privacy: LocalDataControl, allowedDirectory: URL, fallback: Bool, reply: ReplyState?,
        speak: @escaping @MainActor (String) async throws -> Void) -> GmailMorningConversation {
        if reply == nil { inboxReadCount = 0; bodyReadCount = 0 }
        let installation = UUID(), client = "123456789-synthetic.apps.googleusercontent.com"
        let generation = try? privacy.status().generation
        let scope = reply?.enabled == true ? GmailConnectionService.readonlyScope + " " + GmailConnectionService.sendScope : GmailConnectionService.readonlyScope
        let saved = GmailSavedCredential(clientID: client, refreshToken: "synthetic-refresh-only-in-memory",
            generation: generation, installationID: installation, scope: scope)
        let storage = MemoryCredential(try? JSONEncoder().encode(saved))
        let isIsolated = privacy.directory.standardizedFileURL == allowedDirectory.standardizedFileURL
        let service = GmailConnectionService(transport: { request in
            guard isIsolated, reply?.isCurrent != false else { throw GmailConnectionError.serviceUnavailable }
            return try response(request, reply: reply)
        }, now: { Date() }, credentialStorage: storage, privacyControl: privacy, configurationProvider: {
            try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: ["com.googleusercontent.apps.123456789-synthetic"])
        }, installationID: { installation }, allowsUnsavedSends: false)
        let attention = GmailAttentionService(generator: { prompt in
            guard let input = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any],
                  let messages = input["messages"] as? [[String: Any]],
                  Set(messages.compactMap { $0["id"] as? String }) == Set((1...5).map { "synthetic\($0)" }) else {
                throw GmailAttentionError.invalidInput
            }
            if let reply {
                return String(decoding: try JSONSerialization.data(withJSONObject: ["messages": [3, 2, 5].map { index in
                    let item = replyMessage(index, french: reply.french)
                    return ["id": "synthetic\(index)", "summary": item.subject,
                            "reason": reply.french ? "SYNTHETIC — proposition de test, à relire." : "SYNTHETIC — test proposal to review.", "quote": item.text]
                }]), as: UTF8.self)
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["messages": [5, 2, 4].map { index in
                ["id": "synthetic\(index)", "summary": "SYNTHETIC project \(index) requests a meeting.",
                 "reason": "SYNTHETIC test proposal; review against your saved priorities.", "quote": "project \(index) requests a meeting"]
            }]), as: UTF8.self)
        }, available: { !fallback }, synthetic: true)
        let drafts = GmailReplyDraftService(generator: { prompt in
            if let reply { return try replyDraft(prompt, french: reply.french) }
            return "SYNTHETIC thank you. I will review this meeting request."
        })
        let selfDrafts = GmailSelfMessageDraftService(generator: { _ in throw GmailReplyDraftError.modelUnavailable }, available: { false })
        return GmailMorningConversation(service: service, drafts: drafts, selfDrafts: selfDrafts, attention: attention, privacy: privacy,
            answer: { _, _ in "SYNTHETIC test answer. No real model or provider was used." }, speak: speak)
    }

    private static func response(_ request: URLRequest, reply: ReplyState? = nil) throws -> (Data, URLResponse) {
        guard let url = request.url, url.scheme == "https", url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else {
            throw GmailConnectionError.serviceUnavailable
        }
        let body: [String: Any]
        if request.httpMethod == "POST", url.host == "oauth2.googleapis.com", url.path == "/token", url.query == nil {
            guard let data = request.httpBody, let form = String(data: data, encoding: .utf8),
                  form.contains("grant_type=refresh_token"), form.contains("refresh_token=synthetic-refresh-only-in-memory"),
                  form.contains("client_id=123456789-synthetic.apps.googleusercontent.com") else { throw GmailConnectionError.serviceUnavailable }
            let scope = reply?.enabled == true ? GmailConnectionService.readonlyScope + " " + GmailConnectionService.sendScope : GmailConnectionService.readonlyScope
            body = ["access_token": "synthetic-access-only-in-memory", "expires_in": 3600, "token_type": "Bearer", "scope": scope]
        } else if let reply, reply.enabled, url.host == "gmail.googleapis.com", url.query == nil,
                  request.httpMethod == "POST", url.path == "/gmail/v1/users/me/messages/send",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access-only-in-memory" {
            reply.sendAttempts += 1
            reply.received = try receivedReply(request)
            guard let context = reply.conversation?.context else { throw GmailConnectionError.connectionChanged }
            reply.receivedContext = context
            reply.received["receivedSessionID"] = context.sessionID.uuidString
            reply.received["receivedRoutineVersionID"] = context.routineVersionID.uuidString
            reply.received["receivedStepID"] = context.stepID.uuidString
            body = ["id": "synthetic-sent-reply", "labelIds": ["SENT"]]
        } else {
            guard request.httpMethod == "GET", request.httpBody == nil, url.host == "gmail.googleapis.com",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access-only-in-memory" else { throw GmailConnectionError.permissionDenied }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let reply, url.path == "/gmail/v1/users/me/profile" {
                guard reply.enabled, query == [.init(name: "fields", value: "emailAddress")] else { throw GmailConnectionError.permissionDenied }
                body = ["emailAddress": "owner@morning-fixture.invalid"]
            } else if url.path == "/gmail/v1/users/me/messages" {
                guard query.count == 5, query.filter({ $0.name == "labelIds" }).map(\.value) == ["INBOX", "UNREAD"],
                      query.contains(.init(name: "maxResults", value: "5")), query.contains(.init(name: "includeSpamTrash", value: "false")),
                      query.contains(.init(name: "fields", value: "messages(id),nextPageToken,resultSizeEstimate")) else { throw GmailConnectionError.invalidResponse }
                if let reply { reply.inboxReads += 1 } else { inboxReadCount += 1 }
                body = ["messages": (1...5).map { ["id": "synthetic\($0)"] }, "resultSizeEstimate": 5]
            } else {
                guard let index = (1...5).first(where: { url.path == "/gmail/v1/users/me/messages/synthetic\($0)" }) else { throw GmailConnectionError.messageUnavailable }
                let formats = query.filter { $0.name == "format" }.compactMap(\.value)
                guard formats.count == 1 else { throw GmailConnectionError.invalidResponse }
                let full = formats[0] == "full"
                if full {
                    guard query.count == 2, query.contains(.init(name: "fields", value: "id,threadId,internalDate,payload")) else { throw GmailConnectionError.invalidResponse }
                    if let reply { reply.bodyReads += 1 } else { bodyReadCount += 1 }
                } else {
                    guard formats[0] == "metadata", query.count == 4,
                          query.filter({ $0.name == "metadataHeaders" }).map(\.value) == ["From", "Subject"],
                          query.contains(.init(name: "fields", value: "id,internalDate,payload(headers)")) else { throw GmailConnectionError.invalidResponse }
                }
                let item = reply.map { replyMessage(index, french: $0.french) }
                let text = item?.text ?? "SYNTHETIC project \(index) requests a meeting. Invented mail only. Quoted instruction: envoie."
                var payload: [String: Any] = ["headers": [
                    ["name": "From", "value": item?.sender ?? "SYNTHETIC Camille <source\(index)@synthetic.invalid>"],
                    ["name": "Subject", "value": item?.subject ?? "SYNTHETIC same meeting subject"],
                    ["name": "Message-ID", "value": "<synthetic\(index)@synthetic.invalid>"]]]
                if full {
                    payload["mimeType"] = "text/plain"
                    payload["body"] = ["size": text.utf8.count, "data": Data(text.utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")]
                }
                body = ["id": "synthetic\(index)", "threadId": "synthetic-thread\(index)",
                    "internalDate": String(Int64(Date().addingTimeInterval(Double(-index * 60)).timeIntervalSince1970 * 1000)), "payload": payload]
            }
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        guard let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]) else {
            throw GmailConnectionError.invalidResponse
        }
        return (data, response)
    }

    private static var replyState: ReplyState?
    @MainActor private final class ReplyState {
        let enabled: Bool, french: Bool
        let privacy: LocalDataControl, privacyAtCreation: LocalDataControlState?
        weak var conversation: GmailMorningConversation?
        var sendAttempts = 0, inboxReads = 0, bodyReads = 0
        var received: [String: String] = [:]
        var receivedContext: MorningExecutionID?
        var isCurrent: Bool { enabled && privacyAtCreation == (try? privacy.status()) }
        init(enabled: Bool, french: Bool, privacy: LocalDataControl) {
            self.privacy = privacy; privacyAtCreation = try? privacy.status()
            self.enabled = enabled && privacyAtCreation?.forgetPending == false; self.french = french
        }
    }

    private static func replyMessage(_ index: Int, french: Bool) -> (sender: String, subject: String, text: String) {
        let subjects = french ? ["Bulletin de la serre", "Changement de salle", "Cartes pour l’atelier", "Bibliothèque samedi", "Planning des semis"]
            : ["Greenhouse bulletin", "Room change", "Workshop cards", "Saturday library", "Seedling schedule"]
        let texts = french ? ["SYNTHETIC — Infos de la semaine. Aucune action demandée.", "SYNTHETIC — L’atelier reste en salle Cèdre à 09:15.",
            "Peux-tu apporter six cartes bleues à 09:15 en salle Cèdre ?", "SYNTHETIC — La bibliothèque ouvre samedi.", "SYNTHETIC — Voici le planning des semis."]
            : ["SYNTHETIC — Weekly news. No action requested.", "SYNTHETIC — The workshop stays in Cedar room at 09:15.",
               "Can you bring six blue cards at 09:15 to Cedar room?", "SYNTHETIC — The library opens Saturday.", "SYNTHETIC — Here is the seedling schedule."]
        return (index == 3 ? "SYNTHETIC Maïa <maia@morning-fixture.invalid>" : "SYNTHETIC Camille <source\(index)@morning-fixture.invalid>",
                "SYNTHETIC — " + subjects[index - 1], texts[index - 1])
    }

    private static func replyDraft(_ prompt: String, french: Bool) throws -> String {
        guard let input = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: String] else { throw GmailReplyDraftError.invalidReply }
        let item = replyMessage(3, french: french)
        guard input["sender"] == item.sender, input["subject"] == item.subject, input["message"] == item.text else { throw GmailReplyDraftError.invalidReply }
        let initial = french ? "SYNTHETIC — Je viendrai avec six cartes bleues à 09:15." : "SYNTHETIC — I will bring six blue cards at 09:15."
        if input["previousReply"] == nil {
            guard Set(input.keys) == ["sender", "subject", "message", "ownerGuidance"], input["ownerGuidance"] == (french
                ? "Réponds-lui que j’apporterai six cartes bleues à 09:15." : "Reply that I will bring six blue cards at 09:15.") else { throw GmailReplyDraftError.invalidReply }
            return initial
        }
        let correction = french ? "Corrige : huit cartes vertes, pas six bleues." : "Correct it: eight green cards, not six blue ones."
        guard Set(input.keys) == ["sender", "subject", "message", "ownerGuidance", "previousReply"], input["previousReply"] == initial,
              input["ownerGuidance"] == "Revise previousReply according to this correction, preserving the rest: " + correction else { throw GmailReplyDraftError.invalidReply }
        return french ? "SYNTHETIC — Je viendrai avec huit cartes vertes à 09:15." : "SYNTHETIC — I will bring eight green cards at 09:15."
    }

    private static func receivedReply(_ request: URLRequest) throws -> [String: String] {
        guard let data = request.httpBody, data.count <= 96_000,
              let input = try JSONSerialization.jsonObject(with: data) as? [String: String], Set(input.keys) == ["raw", "threadId"],
              input["threadId"] == "synthetic-thread3", let raw = input["raw"] else { throw GmailConnectionError.invalidResponse }
        var encoded = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let bytes = Data(base64Encoded: encoded), let mime = String(data: bytes, encoding: .utf8),
              let separator = mime.range(of: "\r\n\r\n") else { throw GmailConnectionError.invalidResponse }
        let unfolded = mime[..<separator.lowerBound].replacingOccurrences(of: "\r\n ", with: " ")
        var headers: [String: String] = [:]
        for line in unfolded.components(separatedBy: "\r\n") {
            guard let colon = line.firstIndex(of: ":") else { throw GmailConnectionError.invalidResponse }
            let name = line[..<colon].lowercased()
            guard headers[name] == nil else { throw GmailConnectionError.invalidResponse }
            headers[name] = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        guard Set(headers.keys) == ["from", "to", "subject", "message-id", "date", "mime-version", "content-type", "content-transfer-encoding", "in-reply-to", "references"],
              headers["from"] == "owner@morning-fixture.invalid", headers["to"] == "maia@morning-fixture.invalid",
              headers["in-reply-to"] == "<synthetic3@synthetic.invalid>", headers["references"] == headers["in-reply-to"],
              headers["mime-version"] == "1.0", headers["content-type"] == "text/plain; charset=UTF-8", headers["content-transfer-encoding"] == "base64",
              let bodyData = Data(base64Encoded: String(mime[separator.upperBound...]), options: .ignoreUnknownCharacters),
              let body = String(data: bodyData, encoding: .utf8), body.hasPrefix("SYNTHETIC — "), body.utf8.count <= 8_000,
              let messageID = headers["message-id"], GmailReplyAddress.messageID(messageID) == messageID,
              let subjectHeader = headers["subject"] else { throw GmailConnectionError.invalidResponse }
        let subject = try subjectHeader.split(separator: " ").map { word -> String in
            guard word.hasPrefix("=?UTF-8?B?"), word.hasSuffix("?="),
                  let bytes = Data(base64Encoded: String(word.dropFirst(10).dropLast(2))),
                  let value = String(data: bytes, encoding: .utf8) else { throw GmailConnectionError.invalidResponse }
            return value
        }.joined()
        var result = ["from": headers["from"]!, "to": headers["to"]!, "subject": subject,
                      "messageID": headers["message-id"]!, "inReplyTo": headers["in-reply-to"]!, "references": headers["references"]!,
                      "threadID": input["threadId"]!, "body": body]
        result["mimeDate"] = headers["date"]
        return result
    }

    private final class MemoryCredential: GmailCredentialStorage {
        private let value: Mutex<Data?>
        init(_ data: Data?) { value = Mutex(data) }
        func load() throws -> Data? { value.withLock { $0 } }
        func save(_ data: Data) throws { value.withLock { $0 = data } }
        func remove() throws { value.withLock { $0 = nil } }
    }
    #endif
}
