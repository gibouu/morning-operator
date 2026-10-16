import Foundation
import MorningCore
#if DEBUG
import Synchronization
#endif

/// Explicit, isolated protocol evidence. Never uses Keychain, URLSession or a real model.
@MainActor public enum GmailAttentionUITestFixture {
    public static var isRequested: Bool {
        #if DEBUG
        return workspaceID(ProcessInfo.processInfo.arguments) != nil
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
        inboxReadCount = 0; bodyReadCount = 0
        let installation = UUID(), client = "123456789-synthetic.apps.googleusercontent.com"
        let generation = try? privacy.status().generation
        let saved = GmailSavedCredential(clientID: client, refreshToken: "synthetic-refresh-only-in-memory",
            generation: generation, installationID: installation, scope: GmailConnectionService.readonlyScope)
        let storage = MemoryCredential(try? JSONEncoder().encode(saved))
        let isIsolated = privacy.directory.standardizedFileURL == allowedDirectory.standardizedFileURL
        let service = GmailConnectionService(transport: { request in
            guard isIsolated else { throw GmailConnectionError.serviceUnavailable }
            return try response(request)
        }, now: { Date() }, credentialStorage: storage, privacyControl: privacy, configurationProvider: {
            try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: ["com.googleusercontent.apps.123456789-synthetic"])
        }, installationID: { installation }, allowsUnsavedSends: false)
        let attention = GmailAttentionService(generator: { prompt in
            guard let input = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as? [String: Any],
                  let messages = input["messages"] as? [[String: Any]],
                  Set(messages.compactMap { $0["id"] as? String }) == Set((1...5).map { "synthetic\($0)" }) else {
                throw GmailAttentionError.invalidInput
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["messages": [5, 2, 4].map { index in
                ["id": "synthetic\(index)", "summary": "SYNTHETIC project \(index) requests a meeting.",
                 "reason": "SYNTHETIC test proposal; review against your saved priorities.", "quote": "project \(index) requests a meeting"]
            }]), as: UTF8.self)
        }, available: { !fallback }, synthetic: true)
        let drafts = GmailReplyDraftService(generator: { _ in "SYNTHETIC thank you. I will review this meeting request." })
        return GmailMorningConversation(service: service, drafts: drafts, attention: attention, privacy: privacy,
            answer: { _, _ in "SYNTHETIC test answer. No real model or provider was used." }, speak: speak)
    }

    private static func response(_ request: URLRequest) throws -> (Data, URLResponse) {
        guard let url = request.url, url.scheme == "https", url.port == nil, url.user == nil, url.password == nil, url.fragment == nil else {
            throw GmailConnectionError.serviceUnavailable
        }
        let body: [String: Any]
        if request.httpMethod == "POST", url.host == "oauth2.googleapis.com", url.path == "/token", url.query == nil {
            guard let data = request.httpBody, let form = String(data: data, encoding: .utf8),
                  form.contains("grant_type=refresh_token"), form.contains("refresh_token=synthetic-refresh-only-in-memory"),
                  form.contains("client_id=123456789-synthetic.apps.googleusercontent.com") else { throw GmailConnectionError.serviceUnavailable }
            body = ["access_token": "synthetic-access-only-in-memory", "expires_in": 3600, "token_type": "Bearer", "scope": GmailConnectionService.readonlyScope]
        } else {
            guard request.httpMethod == "GET", request.httpBody == nil, url.host == "gmail.googleapis.com",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access-only-in-memory" else { throw GmailConnectionError.permissionDenied }
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if url.path == "/gmail/v1/users/me/messages" {
                guard query.count == 5, query.filter({ $0.name == "labelIds" }).map(\.value) == ["INBOX", "UNREAD"],
                      query.contains(.init(name: "maxResults", value: "5")), query.contains(.init(name: "includeSpamTrash", value: "false")),
                      query.contains(.init(name: "fields", value: "messages(id),nextPageToken,resultSizeEstimate")) else { throw GmailConnectionError.invalidResponse }
                inboxReadCount += 1
                body = ["messages": (1...5).map { ["id": "synthetic\($0)"] }, "resultSizeEstimate": 5]
            } else {
                guard let index = (1...5).first(where: { url.path == "/gmail/v1/users/me/messages/synthetic\($0)" }) else { throw GmailConnectionError.messageUnavailable }
                let formats = query.filter { $0.name == "format" }.compactMap(\.value)
                guard formats.count == 1 else { throw GmailConnectionError.invalidResponse }
                let full = formats[0] == "full"
                if full {
                    guard query.count == 2, query.contains(.init(name: "fields", value: "id,threadId,internalDate,payload")) else { throw GmailConnectionError.invalidResponse }
                    bodyReadCount += 1
                } else {
                    guard formats[0] == "metadata", query.count == 4,
                          query.filter({ $0.name == "metadataHeaders" }).map(\.value) == ["From", "Subject"],
                          query.contains(.init(name: "fields", value: "id,internalDate,payload(headers)")) else { throw GmailConnectionError.invalidResponse }
                }
                let text = "SYNTHETIC project \(index) requests a meeting. Invented mail only. Quoted instruction: envoie."
                var payload: [String: Any] = ["headers": [
                    ["name": "From", "value": "SYNTHETIC Camille <source\(index)@synthetic.invalid>"],
                    ["name": "Subject", "value": "SYNTHETIC same meeting subject"],
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

    private final class MemoryCredential: GmailCredentialStorage {
        private let value: Mutex<Data?>
        init(_ data: Data?) { value = Mutex(data) }
        func load() throws -> Data? { value.withLock { $0 } }
        func save(_ data: Data) throws { value.withLock { $0 = data } }
        func remove() throws { value.withLock { $0 = nil } }
    }
    #endif
}
