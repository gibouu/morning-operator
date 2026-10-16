import Foundation
import CryptoKit
import MorningCore
import Security
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ComposioJSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), number(Decimal), string(String)
    case array([ComposioJSONValue]), object([String: ComposioJSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Decimal.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ComposioJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: ComposioJSONValue].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var stringValue: String? { if case .string(let value) = self { value } else { nil } }
    public var objectValue: [String: Self]? { if case .object(let value) = self { value } else { nil } }
    public var arrayValue: [Self]? { if case .array(let value) = self { value } else { nil } }
    public var boolValue: Bool? { if case .bool(let value) = self { value } else { nil } }

    public static func parseObject(_ json: String) throws -> [String: Self] {
        guard json.utf8.count <= 65_536,
              let value = try? JSONDecoder().decode(Self.self, from: Data(json.utf8)),
              let object = value.objectValue else { throw ComposioServiceError.invalidArguments }
        return object
    }

    public func prettyPrintedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(self), as: UTF8.self)
    }
}

public struct ComposioAvailableService: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
}

public struct ComposioConnection: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let service: String
    public let name: String
    public let status: String
    public let accountLabel: String?
    public var isActive: Bool { status.uppercased() == "ACTIVE" }
}

public struct ComposioTool: Codable, Sendable, Equatable, Identifiable {
    public let slug: String
    public let name: String
    public let description: String
    public let inputSchema: ComposioJSONValue
    public var id: String { slug }
}

public struct ComposioAuthorization: Codable, Sendable, Equatable {
    public let id: String?
    public let authorizationURL: URL
}

public struct ComposioFailure: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
}

public struct ComposioExecutionResult: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let successful: Bool
    public let data: ComposioJSONValue?
    public let error: ComposioFailure?
    public let resultAvailable: Bool?
}

public enum ComposioServiceError: LocalizedError, Sendable, Equatable {
    case notConfigured, insecureURL, credentialsUnavailable, notAuthorized, invalidArguments, invalidResponse
    case requestFailed(Int), backend(ComposioFailure), executionUncertain(UUID)

    public var errorDescription: String? {
        let french = AppLanguage.isFrench
        switch self {
        case .notConfigured: return french ? "Les connexions en ligne ne sont pas encore disponibles dans cette version." : "Online connections are not available in this build yet."
        case .insecureURL: return french ? "Le service de connexion doit utiliser une adresse HTTPS sécurisée." : "The connection service must use a secure HTTPS address."
        case .credentialsUnavailable: return french ? "L’autorisation sécurisée est inaccessible. Déverrouillez l’appareil puis réessayez." : "The secure connection token could not be accessed. Unlock your device and try again."
        case .notAuthorized: return french ? "Cette installation n’est plus autorisée par le service de connexion." : "This installation is no longer authorized by the connection service."
        case .invalidArguments: return french ? "Vérifiez les champs de l’action. Les paramètres doivent former un objet JSON de moins de 64 Ko." : "Review the action fields. Parameters must form a JSON object within 64 KB."
        case .invalidResponse: return french ? "Le service de connexion a renvoyé une réponse illisible." : "The connection service returned an unreadable response."
        case .requestFailed(let status): return french ? "Le service de connexion n’a pas pu terminer cette demande (\(status))." : "The connection service could not complete this request (\(status))."
        case .backend(let failure): return String(failure.message.prefix(500))
        case .executionUncertain(let requestID): return french ? "Le résultat de l’action est inconnu. Vérifiez le compte connecté avant de recommencer. Demande : \(requestID.uuidString)." : "The action's outcome is unknown. Check the connected account before doing it again. Request: \(requestID.uuidString)."
        }
    }
}

@MainActor
public protocol ComposioTokenStoring {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// Stores only this installation's bearer token, never the provider or Composio API key.
@MainActor
public final class ComposioKeychainTokenStore: ComposioTokenStoring {
    private let account: String
    public init(account: String) { self.account = account }
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.morningoperator.online-installation",
         kSecAttrAccount as String: account]
    }
    public func load() throws -> String? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data,
              let token = String(data: data, encoding: .utf8), !token.isEmpty else {
            throw ComposioServiceError.credentialsUnavailable
        }
        return token
    }
    public func save(_ token: String) throws {
        let values = [kSecValueData as String: Data(token.utf8)]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(values) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw ComposioServiceError.credentialsUnavailable
            }
        } else if status != errSecSuccess { throw ComposioServiceError.credentialsUnavailable }
    }
    public func clear() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw ComposioServiceError.credentialsUnavailable
        }
    }
}

private final class ComposioNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Explicit HTTP operations only. Constructing the service never contacts a server.
@MainActor
public final class ComposioService {
    public typealias Transport = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    public let baseURL: URL?
    public var isConfigured: Bool { baseURL != nil }
    private let tokenStore: any ComposioTokenStoring
    private let executionStore: any ComposioTokenStoring
    private let transport: Transport
    private var generation = UUID()
    private var pending: [UUID: Task<(Data, HTTPURLResponse), any Error>] = [:]
    private var installation: Task<String, any Error>?

    public static var configuredBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "MorningAPIBaseURL") as? String,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }
    public static var callbackScheme: String {
        let configured = Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String
        return configured == "moreqa" ? "moreqa" : "more"
    }

    public init(baseURL: URL? = ComposioService.configuredBaseURL,
                tokenStore: (any ComposioTokenStoring)? = nil,
                executionStore: (any ComposioTokenStoring)? = nil, transport: Transport? = nil) {
        self.baseURL = baseURL
        let scope = (Bundle.main.bundleIdentifier ?? "MorningOperator") + "|" + LocalDataControl.defaultDirectory.standardizedFileURL.path
        self.tokenStore = tokenStore ?? ComposioKeychainTokenStore(account: scope + "|" + (baseURL?.absoluteString ?? "unconfigured"))
        self.executionStore = executionStore ?? ComposioKeychainTokenStore(account: scope + "|" + (baseURL?.absoluteString ?? "unconfigured") + "|pending-executions")
        if let transport { self.transport = transport }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            let session = URLSession(configuration: configuration, delegate: ComposioNoRedirectDelegate(), delegateQueue: nil)
            self.transport = { request in
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else { throw ComposioServiceError.invalidResponse }
                return (data, response)
            }
        }
    }

    public func services() async throws -> [ComposioAvailableService] {
        let response: Services = try await request("GET", path: "services")
        return response.services
    }
    public func connections() async throws -> [ComposioConnection] {
        let response: Connections = try await request("GET", path: "connections")
        return response.connections
    }
    public func startConnection(service: String, callbackURL: URL) async throws -> ComposioAuthorization {
        guard Self.validIdentifier(service), callbackURL.scheme == Self.callbackScheme, callbackURL.host == "composio",
              callbackURL.path == "/callback", callbackURL.query == nil, callbackURL.fragment == nil else {
            throw ComposioServiceError.invalidArguments
        }
        let response: ComposioAuthorization = try await request("POST", path: "connections", body: .object([
            "service": .string(service), "callbackURL": .string(callbackURL.absoluteString)]))
        try Self.validateURL(response.authorizationURL)
        return response
    }
    public func disconnect(connectionID: String) async throws {
        guard Self.validIdentifier(connectionID) else { throw ComposioServiceError.invalidArguments }
        _ = try await send("DELETE", path: "connections/" + connectionID)
    }
    public func completeConnection(sessionURI: String) async throws {
        guard !sessionURI.isEmpty, sessionURI.utf8.count <= 4096 else {
            throw ComposioServiceError.invalidArguments
        }
        _ = try await send("POST", path: "connections/complete", body: .object(["sessionURI": .string(sessionURI)]))
    }
    public func tools(service: String) async throws -> [ComposioTool] {
        guard Self.validIdentifier(service) else { throw ComposioServiceError.invalidArguments }
        let response: Tools = try await request("GET", path: "tools", query: [URLQueryItem(name: "service", value: service)])
        return response.tools
    }

    /// These fixed Slack reads have no provider effect. A failed read can be retried
    /// with a fresh request ID; it never releases or bypasses an effect reservation.
    public func readSlack(tool: String, arguments: [String: ComposioJSONValue], connectionID: String) async throws -> ComposioExecutionResult {
        guard Self.validIdentifier(connectionID), SlackReplyContract.validRead(tool, arguments) else { throw ComposioServiceError.invalidArguments }
        let id = UUID()
        let result: ComposioExecutionResult = try await request("POST", path: "execute", body: .object([
            "tool": .string(tool), "arguments": .object(arguments), "connectionID": .string(connectionID), "requestID": .string(id.uuidString)]))
        guard result.requestID == id, result.successful || result.error != nil else { throw ComposioServiceError.invalidResponse }
        return result
    }

    /// Only the two fixed, bounded Calendar reads. Read retries get a new request
    /// ID and never inspect, release or bypass any local effect reservation.
    public func readGoogleCalendar(tool: String, arguments: [String: ComposioJSONValue], connectionID: String) async throws -> ComposioExecutionResult {
        guard Self.validIdentifier(connectionID), GoogleCalendarReadContract.validRead(tool, arguments) else { throw ComposioServiceError.invalidArguments }
        try Task.checkCancellation()
        let id = UUID()
        let result: ComposioExecutionResult = try await request("POST", path: "execute", body: .object([
            "tool": .string(tool), "arguments": .object(arguments), "connectionID": .string(connectionID), "requestID": .string(id.uuidString)]))
        try Task.checkCancellation()
        guard result.requestID == id, result.successful || result.error != nil else { throw ComposioServiceError.invalidResponse }
        return result
    }

    /// Only fixed current-identity and bounded personal-day Calendly reads.
    /// A fresh read ID never consumes or releases a local write reservation.
    public func readCalendly(tool: String, arguments: [String: ComposioJSONValue], connectionID: String) async throws -> ComposioExecutionResult {
        guard Self.validIdentifier(connectionID), CalendlyDayReadContract.validRead(tool, arguments) else { throw ComposioServiceError.invalidArguments }
        try Task.checkCancellation()
        let id = UUID()
        let result: ComposioExecutionResult = try await request("POST", path: "execute", body: .object([
            "tool": .string(tool), "arguments": .object(arguments), "connectionID": .string(connectionID), "requestID": .string(id.uuidString)]))
        try Task.checkCancellation()
        guard result.requestID == id, result.successful || result.error != nil else { throw ComposioServiceError.invalidResponse }
        return result
    }

    /// Only current Outlook identity, three unread Inbox previews, and a selected
    /// message read. These reads never consume or release a write reservation.
    public func readOutlook(tool: String, arguments: [String: ComposioJSONValue], connectionID: String) async throws -> ComposioExecutionResult {
        guard Self.validIdentifier(connectionID), OutlookInboxReadContract.validRead(tool, arguments) else { throw ComposioServiceError.invalidArguments }
        try Task.checkCancellation()
        let id = UUID()
        let result: ComposioExecutionResult = try await request("POST", path: "execute", body: .object([
            "tool": .string(tool), "arguments": .object(arguments), "connectionID": .string(connectionID), "requestID": .string(id.uuidString)]))
        try Task.checkCancellation()
        guard result.requestID == id, result.successful || result.error != nil else { throw ComposioServiceError.invalidResponse }
        return result
    }

    /// The dedicated route verifies the current provider subject and account metadata.
    /// Its revision is a preflight check, not a conditional Composio credential lease.
    /// An old server is unavailable, never a reason to fall back to a generic send.
    public func slackReplyIdentity(connectionID: String) async throws -> SlackReplyIdentity {
        guard Self.validIdentifier(connectionID) else { throw SlackReplyError.accountChanged }
        do {
            let identity: SlackReplyIdentity = try await request("GET", path: "slack/reply-identity",
                query: [URLQueryItem(name: "connectionID", value: connectionID)])
            try identity.validate()
            guard identity.connectionID == connectionID else { throw SlackReplyError.accountChanged }
            return identity
        } catch ComposioServiceError.backend(let failure) where ["not_found", "slack_identity_unavailable"].contains(failure.code) {
            throw SlackReplyError.serverBindingUnavailable
        } catch ComposioServiceError.invalidResponse {
            throw SlackReplyError.serverBindingUnavailable
        }
    }

    public func sendSlackReply(_ reply: SlackPreparedReply, operationID: UUID) async throws -> ComposioExecutionResult {
        let identity = reply.destination.identity
        try identity.validate()
        let expected: ComposioJSONValue = .object([
            "revision": .string(identity.revision), "teamID": .string(identity.teamID), "userID": .string(identity.userID)
        ].merging(identity.botID.map { ["botID": .string($0)] } ?? [:]) { _, new in new })
        let fields: [String: ComposioJSONValue] = ["expectedIdentity": expected, "channelID": .string(reply.source.channelID),
            "threadTS": .string(reply.source.threadTS), "body": .string(try SlackReplyContract.reply(reply.body))]
        let token: String
        do {
            token = try await installationToken()
            try Task.checkCancellation()
            let key = try executionKey(tool: "SLACK_SEND_MESSAGE", arguments: fields, connectionID: identity.connectionID)
            var ledger = try pendingExecutions()
            if let previous = ledger[key] { throw ComposioServiceError.executionUncertain(previous) }
            ledger[key] = operationID; try saveExecutions(ledger)
        } catch {
            if case ComposioServiceError.executionUncertain = error { throw error }
            throw SlackReplyDispatchError.notDispatched(.journalUnavailable)
        }
        var dispatched = false
        do {
            let response: ComposioExecutionResult = try await request("POST", path: "slack/replies", body: .object(fields.merging([
                "connectionID": .string(identity.connectionID), "requestID": .string(operationID.uuidString)
            ]) { _, new in new }), token: token, onDispatch: { dispatched = true })
            guard response.requestID == operationID, response.successful || response.error != nil else { throw ComposioServiceError.invalidResponse }
            // The conversation's own claim remains until the exact Slack receipt is validated.
            if response.successful { try removePendingExecution(operationID) }
            return response
        } catch ComposioServiceError.backend(let failure) where ["not_found", "slack_identity_unavailable", "slack_identity_changed", "invalid_slack_reply", "unsupported_service", "invalid_json", "json_required", "body_too_large", "unexpected_field", "connection_inactive", "connection_not_found", "tool_account_mismatch"].contains(failure.code) {
            try removePendingExecution(operationID)
            throw SlackReplyDispatchError.notDispatched(failure.code == "not_found" || failure.code == "slack_identity_unavailable" ? .serverBindingUnavailable : (failure.code == "invalid_slack_reply" ? .invalidReply : .accountChanged))
        } catch ComposioServiceError.notAuthorized {
            try removePendingExecution(operationID)
            throw SlackReplyDispatchError.notDispatched(.accountChanged)
        } catch {
            if !dispatched {
                try removePendingExecution(operationID)
                throw SlackReplyDispatchError.notDispatched(.unavailable)
            }
            throw ComposioServiceError.executionUncertain(operationID)
        }
    }

    /// A failed transport after dispatch is never evidence that an external action did not happen.
    public func execute(tool: String, arguments: [String: ComposioJSONValue], connectionID: String,
                        requestID: UUID = UUID()) async throws -> ComposioExecutionResult {
        guard Self.validIdentifier(connectionID), Self.validIdentifier(tool),
              (try JSONEncoder().encode(ComposioJSONValue.object(arguments))).count <= 65_536 else {
            throw ComposioServiceError.invalidArguments
        }
        // Obtain credentials before dispatch so setup/cancellation failures do not imply an effect.
        let token = try await installationToken()
        try Task.checkCancellation()
        let key = try executionKey(tool: tool, arguments: arguments, connectionID: connectionID)
        var ledger = try pendingExecutions()
        if let previous = ledger[key] { throw ComposioServiceError.executionUncertain(previous) }
        // Persist only a fingerprint and request identity, before any possible provider effect.
        ledger[key] = requestID
        try saveExecutions(ledger)
        do {
            let response: ComposioExecutionResult = try await request("POST", path: "execute", body: .object([
                "tool": .string(tool), "arguments": .object(arguments), "connectionID": .string(connectionID),
                "requestID": .string(requestID.uuidString)]), token: token)
            guard response.requestID == requestID,
                  response.successful || response.error != nil else { throw ComposioServiceError.invalidResponse }
            if response.successful { try removePendingExecution(requestID) }
            return response
        } catch let error as ComposioServiceError {
            switch error {
            case .backend(let failure) where ["invalid_execution", "invalid_arguments", "invalid_connection", "tool_account_mismatch", "connection_inactive", "connection_not_found", "unsupported_service", "unexpected_field", "invalid_json", "json_required", "body_too_large"].contains(failure.code):
                try removePendingExecution(requestID); throw error
            case .notAuthorized, .invalidArguments, .notConfigured, .insecureURL, .credentialsUnavailable:
                try removePendingExecution(requestID); throw error
            default: throw ComposioServiceError.executionUncertain(requestID)
            }
        } catch { throw ComposioServiceError.executionUncertain(requestID) }
    }

    public func cancelPendingOperations() {
        generation = UUID()
        installation?.cancel(); installation = nil
        for task in pending.values { task.cancel() }
        pending.removeAll()
    }
    /// Local forgetting does not revoke remote grants; disconnect each account to revoke them.
    public func clearLocalCredentials() throws {
        cancelPendingOperations()
        try tokenStore.clear()
        try executionStore.clear()
    }

    /// Call only after the person has checked the external account and resolved the effect.
    public func reconcileExecution(requestID: UUID) throws { try removePendingExecution(requestID) }

    private func executionKey(tool: String, arguments: [String: ComposioJSONValue], connectionID: String) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(ComposioJSONValue.array([.string(connectionID), .string(tool), .object(arguments)]))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    private func pendingExecutions() throws -> [String: UUID] {
        guard let value = try executionStore.load() else { return [:] }
        guard value.utf8.count <= 65_536,
              let ledger = try? JSONDecoder().decode([String: UUID].self, from: Data(value.utf8)) else {
            throw ComposioServiceError.credentialsUnavailable
        }
        return ledger
    }
    private func saveExecutions(_ value: [String: UUID]) throws {
        let data = try JSONEncoder().encode(value)
        guard data.count <= 65_536 else { throw ComposioServiceError.credentialsUnavailable }
        try executionStore.save(String(decoding: data, as: UTF8.self))
    }
    private func removePendingExecution(_ id: UUID) throws {
        var ledger = try pendingExecutions()
        ledger = ledger.filter { $0.value != id }
        try saveExecutions(ledger)
    }

    private struct Services: Decodable { let services: [ComposioAvailableService] }
    private struct Connections: Decodable { let connections: [ComposioConnection] }
    private struct Tools: Decodable { let tools: [ComposioTool] }
    private struct Installation: Decodable { let token: String }
    private struct FailureEnvelope: Decodable { let error: ComposioFailure }

    private func installationToken() async throws -> String {
        try Task.checkCancellation()
        if let token = try tokenStore.load() { return token }
        if let installation { return try await installation.value }
        let expectedGeneration = generation
        let task = Task { @MainActor in
            let data = try await self.send("POST", path: "installations", body: .object([:]), authenticated: false)
            guard let response = try? JSONDecoder().decode(Installation.self, from: data),
                  (16...2048).contains(response.token.utf8.count),
                  !response.token.contains(where: { $0.isWhitespace || $0.isNewline }) else {
                throw ComposioServiceError.invalidResponse
            }
            try Task.checkCancellation()
            guard self.generation == expectedGeneration else { throw CancellationError() }
            try self.tokenStore.save(response.token)
            return response.token
        }
        installation = task
        defer { if generation == expectedGeneration { installation = nil } }
        return try await task.value
    }

    private func request<Response: Decodable>(_ method: String, path: String,
        body: ComposioJSONValue? = nil, query: [URLQueryItem] = [], token: String? = nil,
        onDispatch: (@MainActor () -> Void)? = nil) async throws -> Response {
        let data = try await send(method, path: path, body: body, query: query, token: token, onDispatch: onDispatch)
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ComposioServiceError.invalidResponse
        }
        return response
    }
    private func send(_ method: String, path: String, body: ComposioJSONValue? = nil,
                      query: [URLQueryItem] = [], authenticated: Bool = true, token: String? = nil,
                      onDispatch: (@MainActor () -> Void)? = nil) async throws -> Data {
        guard let baseURL else { throw ComposioServiceError.notConfigured }
        try Self.validateURL(baseURL)
        guard baseURL.query == nil, baseURL.fragment == nil else { throw ComposioServiceError.insecureURL }
        let expectedGeneration = generation
        let bearer: String?
        if authenticated { bearer = try await tokenValue(token) }
        else { bearer = nil }
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        var components = URLComponents(url: baseURL.appendingPathComponent("v1/" + path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw ComposioServiceError.insecureURL }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = path == "execute" ? 60 : 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bearer { request.setValue("Bearer " + bearer, forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        let id = UUID()
        let transport = transport
        onDispatch?()
        let task = Task { try await transport(request) }
        pending[id] = task
        defer { pending[id] = nil }
        let (data, response) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: { task.cancel() }
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
        guard data.count <= 4_194_304 else { throw ComposioServiceError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 { throw ComposioServiceError.notAuthorized }
            if path == "execute", response.statusCode >= 500 || response.statusCode == 408 {
                throw ComposioServiceError.requestFailed(response.statusCode)
            }
            if let envelope = try? JSONDecoder().decode(FailureEnvelope.self, from: data) {
                throw ComposioServiceError.backend(envelope.error)
            }
            throw ComposioServiceError.requestFailed(response.statusCode)
        }
        return data
    }
    private func tokenValue(_ supplied: String?) async throws -> String {
        if let supplied { return supplied }
        return try await installationToken()
    }
    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-" )).contains($0)
        }
    }
    private static func validateURL(_ url: URL) throws {
        guard url.host != nil, url.user == nil, url.password == nil else { throw ComposioServiceError.insecureURL }
        if url.scheme?.lowercased() == "https" { return }
        #if DEBUG
        if url.scheme?.lowercased() == "http", ["localhost", "127.0.0.1", "::1", "[::1]"].contains(url.host?.lowercased() ?? "") { return }
        #endif
        throw ComposioServiceError.insecureURL
    }
}
