import CryptoKit
import Foundation
import MorningCore
import Security

/// Public iOS OAuth client configuration only. No client secret belongs in an installed app.
public struct GmailOAuthConfiguration: Sendable, Equatable {
    public let clientID: String
    public let callbackScheme: String
    public let redirectURI: URL

    public init(clientID: String, registeredURLSchemes: [String]) throws {
        guard !clientID.isEmpty else { throw GmailConnectionError.configurationMissing }
        let suffix = ".apps.googleusercontent.com"
        let prefix = String(clientID.dropLast(suffix.count))
        guard clientID.hasSuffix(suffix), !prefix.isEmpty, prefix.utf8.count <= 512,
              prefix.utf8.allSatisfy({ Self.clientCharacters.contains($0) }) else {
            throw GmailConnectionError.configurationInvalid
        }
        let scheme = "com.googleusercontent.apps.\(prefix)"
        guard registeredURLSchemes.contains(scheme),
              let redirectURI = URL(string: "\(scheme):/oauth2redirect") else {
            throw GmailConnectionError.configurationInvalid
        }
        self.clientID = clientID
        self.callbackScheme = scheme
        self.redirectURI = redirectURI
    }

    private static let clientCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-".utf8)
}

/// Explicit capabilities requested by this visible connection attempt. Reading is
/// a separate user action; a count-only connection never silently upgrades itself.
public enum GmailAuthorizationAccess: Sendable, Equatable {
    case metadata, readMessages

    fileprivate var scope: String {
        self == .metadata ? GmailConnectionService.metadataScope : GmailConnectionService.readonlyScope
    }
}

/// One browser attempt, with a fresh state and S256 verifier. Do not log the authorization URL
/// or callback, and release this attempt when the browser closes. A callback is consumed once.
@MainActor
public final class GmailAuthorizationRequest: CustomStringConvertible, CustomDebugStringConvertible {
    public let authorizationURL: URL
    public let callbackScheme: String
    fileprivate let configuration: GmailOAuthConfiguration
    fileprivate let verifier: String
    fileprivate let access: GmailAuthorizationAccess
    private let state: String
    private var consumed = false
    public nonisolated var description: String { "GmailAuthorizationRequest(redacted)" }
    public nonisolated var debugDescription: String { description }

    public convenience init(configuration: GmailOAuthConfiguration, access: GmailAuthorizationAccess = .metadata) throws {
        try self.init(configuration: configuration, verifier: Self.randomValue(), state: Self.randomValue(), access: access)
    }

    // Internal deterministic entry point for component tests; production always uses secure random bytes.
    init(configuration: GmailOAuthConfiguration, verifier: String, state: String, access: GmailAuthorizationAccess = .metadata) throws {
        let unreserved = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
        guard (43...128).contains(verifier.utf8.count), verifier.utf8.allSatisfy(unreserved.contains),
              (32...128).contains(state.utf8.count), state.utf8.allSatisfy(unreserved.contains) else {
            throw GmailConnectionError.authorizationFailed
        }
        self.configuration = configuration
        self.callbackScheme = configuration.callbackScheme
        self.verifier = verifier
        self.access = access
        self.state = state
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: access.scope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        if access == .readMessages {
            url.queryItems?.append(contentsOf: [
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent")
            ])
        }
        self.authorizationURL = url.url!
    }

    fileprivate func consumeCode(from callback: URL) throws -> String {
        guard !consumed else { throw GmailConnectionError.invalidCallback }
        consumed = true
        guard callback.absoluteString.utf8.count <= 16_384,
              let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              parts.scheme == callbackScheme, parts.host == nil, parts.user == nil, parts.password == nil,
              parts.port == nil, parts.percentEncodedPath == "/oauth2redirect", parts.fragment == nil else {
            throw GmailConnectionError.invalidCallback
        }
        let items = parts.queryItems ?? []
        let states = items.filter { $0.name == "state" }
        guard states.count == 1, states.first?.value == state else { throw GmailConnectionError.invalidCallback }
        let codes = items.filter { $0.name == "code" }
        let errors = items.filter { $0.name == "error" }
        if errors.count == 1, codes.isEmpty {
            throw errors.first?.value == "access_denied" ? GmailConnectionError.permissionDenied : .authorizationFailed
        }
        guard errors.isEmpty, codes.count == 1, let code = codes.first?.value,
              !code.isEmpty, code.utf8.count <= 4_096,
              !code.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw GmailConnectionError.invalidCallback
        }
        return code
    }

    private static func randomValue() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw GmailConnectionError.authorizationFailed
        }
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Access is memory-only and clears with screen content. An explicit saved
/// read-only connection stores only its private refresh credential in Keychain.
public struct GmailAccessSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let accessToken: String
    fileprivate let refreshToken: String?
    fileprivate let authorizationClientID: String
    fileprivate let savedCredentialID: UUID?
    public let expiresAt: Date
    public let canReadMessages: Bool
    public var canStayConnected: Bool { canReadMessages && refreshToken != nil }
    public var description: String { "GmailAccessSession(redacted)" }
    public var debugDescription: String { description }
}

public struct GmailInboxSnapshot: Sendable, Equatable {
    public let unreadMessageCount: Int
    public let retrievedAt: Date

    public func isCurrent(at date: Date) -> Bool {
        let age = date.timeIntervalSince(retrievedAt)
        return age.isFinite && age >= 0 && age < 60
    }
}

public enum GmailConnectionError: LocalizedError, Sendable, Equatable {
    case configurationMissing, configurationInvalid, authorizationFailed, invalidCallback
    case permissionDenied, sessionExpired, networkUnavailable, rateLimited, serviceUnavailable
    case invalidResponse, redirectRejected, readAccessRequired, messageUnavailable, messageTooLarge
    case credentialStorageUnavailable, savedConnectionInvalid, connectionChanged

    public var errorDescription: String? {
        switch self {
        case .configurationMissing:
            String(localized: "This build needs a Google iOS OAuth client before Gmail can connect.", bundle: .module)
        case .configurationInvalid:
            String(localized: "This build's Google OAuth client and callback scheme need checking.", bundle: .module)
        case .authorizationFailed:
            String(localized: "Google could not authorize Gmail access. Check the app's Google setup and try again.", bundle: .module)
        case .invalidCallback:
            String(localized: "The Google sign-in response could not be verified. Connect again.", bundle: .module)
        case .permissionDenied:
            String(localized: "Gmail access was not granted. Check Google consent and account policy.", bundle: .module)
        case .sessionExpired:
            String(localized: "This Gmail session has expired. Connect again.", bundle: .module)
        case .networkUnavailable:
            String(localized: "Gmail could not connect. Try again when a connection is available.", bundle: .module)
        case .rateLimited:
            String(localized: "Gmail is limiting requests. Wait before refreshing.", bundle: .module)
        case .serviceUnavailable:
            String(localized: "Gmail is unavailable right now. Your morning can continue without it.", bundle: .module)
        case .invalidResponse:
            String(localized: "Gmail returned an incomplete response. No inbox count is available.", bundle: .module)
        case .redirectRejected:
            String(localized: "Gmail returned an unexpected redirect. No inbox count is available.", bundle: .module)
        case .readAccessRequired:
            String(localized: "Choose Read messages and grant Gmail read-only access first.", bundle: .module)
        case .messageUnavailable:
            String(localized: "This Gmail message is no longer available.", bundle: .module)
        case .messageTooLarge:
            String(localized: "This Gmail message exceeds the supported reading limits.", bundle: .module)
        case .credentialStorageUnavailable:
            String(localized: "Saved Gmail access is unavailable on this device. Unlock it and try again.", bundle: .module)
        case .savedConnectionInvalid:
            String(localized: "This saved Gmail connection needs to be connected again.", bundle: .module)
        case .connectionChanged:
            String(localized: "The Gmail connection changed. Open Gmail again to continue.", bundle: .module)
        }
    }
}

/// Token exchange and explicit read-only INBOX/message GET requests. No send, label writes,
/// background polling, mail persistence, telemetry, automatic retries or remote revocation.
@MainActor
public final class GmailConnectionService {
    public nonisolated static let metadataScope = "https://www.googleapis.com/auth/gmail.metadata"
    public nonisolated static let readonlyScope = "https://www.googleapis.com/auth/gmail.readonly"
    public typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let now: @MainActor () -> Date
    private let credentialStorage: any GmailCredentialStorage
    private let privacyControl: LocalDataControl
    private let configurationProvider: @MainActor () throws -> GmailOAuthConfiguration
    private let installationID: @MainActor () throws -> UUID

    public convenience init() {
        let http = GmailEphemeralTransport()
        self.init(transport: { try await http.data(for: $0) })
    }

    public convenience init(transport: @escaping Transport, now: @escaping @MainActor () -> Date = { Date() }) {
        self.init(transport: transport, now: now, credentialStorage: GmailKeychainCredentialStorage(),
                  privacyControl: LocalDataControl(directory: LocalDataControl.defaultDirectory),
                  configurationProvider: Self.bundleConfiguration,
                  installationID: GmailInstallationIdentifier.current)
    }

    // Test-only injection avoids live credentials, preferences and app privacy state.
    init(transport: @escaping Transport, now: @escaping @MainActor () -> Date,
         credentialStorage: any GmailCredentialStorage, privacyControl: LocalDataControl,
         configurationProvider: @escaping @MainActor () throws -> GmailOAuthConfiguration,
         installationID: @escaping @MainActor () throws -> UUID) {
        self.transport = transport
        self.now = now
        self.credentialStorage = credentialStorage
        self.privacyControl = privacyControl
        self.configurationProvider = configurationProvider
        self.installationID = installationID
    }

    public func completeAuthorization(_ attempt: GmailAuthorizationRequest, callbackURL: URL) async throws -> GmailAccessSession {
        try Task.checkCancellation()
        let code = try attempt.consumeCode(from: callbackURL)
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let values = ["client_id": attempt.configuration.clientID, "redirect_uri": attempt.configuration.redirectURI.absoluteString,
                      "code": code, "code_verifier": attempt.verifier, "grant_type": "authorization_code"]
        request.httpBody = Self.formBody(values)
        let data = try await perform(request, exchangingCode: true)
        let token = try validatedToken(data, fallbackScope: nil)
        let scopes = Set(token.scope.split(separator: " ").map(String.init))
        let hasRequiredScope = attempt.access == .readMessages
            ? scopes.contains(Self.readonlyScope)
            : scopes.contains(Self.metadataScope) || scopes.contains(Self.readonlyScope)
        guard hasRequiredScope else { throw GmailConnectionError.permissionDenied }
        return GmailAccessSession(accessToken: token.accessToken,
                                  refreshToken: attempt.access == .readMessages ? token.refreshToken : nil,
                                  authorizationClientID: attempt.configuration.clientID, savedCredentialID: nil,
                                  expiresAt: now().addingTimeInterval(TimeInterval(token.expiresIn)),
                                  canReadMessages: attempt.access == .readMessages)
    }

    /// Explicit authorization persistence. The privacy lock covers both generation
    /// validation and the actual Keychain write; no late callback can cross Forget.
    public func saveConnection(session: GmailAccessSession, generation: UUID?) throws {
        try Task.checkCancellation()
        guard session.canStayConnected, let refresh = session.refreshToken,
              session.expiresAt > now() else { throw GmailConnectionError.savedConnectionInvalid }
        let configuration = try configurationProvider()
        guard configuration.clientID == session.authorizationClientID else { throw GmailConnectionError.savedConnectionInvalid }
        try withCurrentGeneration(generation) {
            if let expectedID = session.savedCredentialID {
                guard let current = try credentialStorage.load(),
                      let saved = try? JSONDecoder().decode(GmailSavedCredential.self, from: current),
                      saved.id == expectedID else { throw GmailConnectionError.connectionChanged }
            }
            let saved = GmailSavedCredential(clientID: configuration.clientID, refreshToken: refresh,
                                            generation: generation, installationID: try installationID())
            try credentialStorage.save(JSONEncoder().encode(saved))
        }
    }

    /// Restores authorization, not mail. Network/lock/storage/parse failures keep
    /// the saved credential intact so Retry never becomes another browser login.
    public func restoreConnection(generation: UUID?) async throws -> GmailAccessSession? {
        try Task.checkCancellation()
        let loaded: (Data, GmailSavedCredential)? = try withCurrentGeneration(generation) {
            guard let data = try credentialStorage.load() else { return nil }
            guard data.count <= 16_384,
                  let saved = try? JSONDecoder().decode(GmailSavedCredential.self, from: data),
                  saved.schemaVersion == 1 else { throw GmailConnectionError.savedConnectionInvalid }
            guard saved.installationID == (try installationID()) else {
                try credentialStorage.remove()
                return nil
            }
            guard saved.generation == generation else { throw GmailConnectionError.connectionChanged }
            let configuration = try configurationProvider()
            guard saved.clientID == configuration.clientID, saved.scope == Self.readonlyScope,
                  Self.validToken(saved.refreshToken) else { throw GmailConnectionError.savedConnectionInvalid }
            return (data, saved)
        }
        guard let (original, saved) = loaded else { return nil }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.formBody(["client_id": saved.clientID, "refresh_token": saved.refreshToken,
                                         "grant_type": "refresh_token"])
        let data: Data
        do { data = try await perform(request, refreshing: true) }
        catch GmailRefreshError.revoked {
            try withCurrentGeneration(generation) {
                guard try credentialStorage.load() == original else { throw GmailConnectionError.connectionChanged }
                try credentialStorage.remove()
            }
            return nil
        }
        let token = try validatedToken(data, fallbackScope: saved.scope)
        guard token.scope.split(separator: " ").contains(Substring(Self.readonlyScope)) else {
            // A successfully refreshed grant that explicitly lost read access
            // needs consent again; Retry cannot restore a permission it lacks.
            try withCurrentGeneration(generation) {
                guard try credentialStorage.load() == original else { throw GmailConnectionError.connectionChanged }
                try credentialStorage.remove()
            }
            return nil
        }
        return try withCurrentGeneration(generation) {
            try Task.checkCancellation()
            guard try credentialStorage.load() == original else { throw GmailConnectionError.connectionChanged }
            var current = saved
            if let rotated = token.refreshToken, rotated != saved.refreshToken {
                current = GmailSavedCredential(clientID: saved.clientID, refreshToken: rotated,
                                               generation: generation, installationID: saved.installationID)
                try credentialStorage.save(JSONEncoder().encode(current))
            }
            return GmailAccessSession(accessToken: token.accessToken, refreshToken: current.refreshToken,
                                      authorizationClientID: saved.clientID, savedCredentialID: current.id,
                                      expiresAt: now().addingTimeInterval(TimeInterval(token.expiresIn)), canReadMessages: true)
        }
    }

    public func disconnect() throws {
        do { try credentialStorage.remove() }
        catch { throw GmailConnectionError.credentialStorageUnavailable }
    }

    private func withCurrentGeneration<T>(_ generation: UUID?, _ body: () throws -> T) throws -> T {
        try Task.checkCancellation()
        do {
            return try privacyControl.withReadyAccess { state in
                try Task.checkCancellation()
                guard state.generation == generation else { throw GmailConnectionError.connectionChanged }
                return try body()
            }
        } catch is CancellationError { throw CancellationError() }
        catch is LocalDataControlError { throw GmailConnectionError.connectionChanged }
        catch let error as GmailConnectionError { throw error }
        catch { throw GmailConnectionError.credentialStorageUnavailable }
    }

    private static func bundleConfiguration() throws -> GmailOAuthConfiguration {
        let schemes = (Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? [])
            .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        return try GmailOAuthConfiguration(clientID: Bundle.main.object(forInfoDictionaryKey: "MOREGoogleClientID") as? String ?? "",
                                           registeredURLSchemes: schemes)
    }

    private struct ValidatedToken {
        let accessToken: String
        let refreshToken: String?
        let scope: String
        let expiresIn: Int
    }

    private func validatedToken(_ data: Data, fallbackScope: String?) throws -> ValidatedToken {
        struct Response: Decodable {
            let access_token: String
            let token_type: String
            let expires_in: Int
            let scope: String?
            let refresh_token: String?
        }
        guard let token = try? JSONDecoder().decode(Response.self, from: data),
              token.token_type == "Bearer", token.expires_in > 0, token.expires_in <= 86_400,
              Self.validToken(token.access_token), let scope = token.scope ?? fallbackScope,
              !scope.isEmpty, scope.utf8.count <= 4_096 else { throw GmailConnectionError.invalidResponse }
        if let refresh = token.refresh_token, !Self.validToken(refresh) { throw GmailConnectionError.invalidResponse }
        return ValidatedToken(accessToken: token.access_token, refreshToken: token.refresh_token,
                              scope: scope, expiresIn: token.expires_in)
    }

    private static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.count <= 8_192 && token.utf8.allSatisfy(Self.bearerCharacters.contains)
    }

    public func inboxUnreadCount(session: GmailAccessSession) async throws -> GmailInboxSnapshot {
        try Task.checkCancellation()
        guard session.expiresAt.timeIntervalSince(now()) > 30 else { throw GmailConnectionError.sessionExpired }
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX?fields=id,messagesUnread")!,
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await perform(request)
        struct InboxLabel: Decodable { let id: String; let messagesUnread: Int }
        guard let label = try? JSONDecoder().decode(InboxLabel.self, from: data),
              label.id == "INBOX", label.messagesUnread >= 0 else { throw GmailConnectionError.invalidResponse }
        guard session.expiresAt > now() else { throw GmailConnectionError.sessionExpired }
        return GmailInboxSnapshot(unreadMessageCount: label.messagesUnread, retrievedAt: now())
    }

    /// Reads at most five unread Inbox message headers. A missing/failed header
    /// read is counted, never transformed into an empty Inbox. No body is requested.
    public func unreadInboxMessages(session: GmailAccessSession) async throws -> GmailUnreadMessagesSnapshot {
        try requireReading(session)
        let request = try messageRequest(path: "messages", query: [
            .init(name: "labelIds", value: "INBOX"), .init(name: "labelIds", value: "UNREAD"),
            .init(name: "maxResults", value: "5"), .init(name: "includeSpamTrash", value: "false"),
            .init(name: "fields", value: "messages(id),nextPageToken,resultSizeEstimate")
        ], session: session)
        let listing = try GmailMessageDecoder.list(from: await perform(request))
        var messages: [GmailMessageSummary] = []
        var failed = 0
        for id in listing.ids {
            try requireReading(session)
            do {
                let metadata = try messageRequest(path: "messages/\(id)", query: [
                    .init(name: "format", value: "metadata"),
                    .init(name: "metadataHeaders", value: "From"), .init(name: "metadataHeaders", value: "Subject"),
                    .init(name: "fields", value: "id,internalDate,payload(headers)")
                ], session: session)
                let data = try await perform(metadata)
                try requireReading(session)
                messages.append(try GmailMessageDecoder.summary(from: data, expectedID: id))
            } catch {
                try Task.checkCancellation()
                if error is CancellationError { throw CancellationError() }
                if let error = error as? GmailConnectionError,
                   [.permissionDenied, .sessionExpired, .readAccessRequired].contains(error) { throw error }
                failed += 1
            }
        }
        try requireReading(session)
        return GmailUnreadMessagesSnapshot(messages: messages, failedMessageCount: failed,
                                          hasMore: listing.hasMore, retrievedAt: now())
    }

    /// Fetches just the selected message. MIME extraction produces bounded text;
    /// HTML is never rendered, and attachment IDs are never followed.
    public func message(id: String, session: GmailAccessSession) async throws -> GmailMessage {
        try requireReading(session)
        guard GmailMessageDecoder.validID(id) else { throw GmailConnectionError.invalidResponse }
        let request = try messageRequest(path: "messages/\(id)", query: [
            .init(name: "format", value: "full"), .init(name: "fields", value: "id,internalDate,payload")
        ], session: session)
        let data = try await perform(request, maximumBytes: GmailMessageLimits.maximumWireBytes)
        try requireReading(session)
        return try GmailMessageDecoder.message(from: data, expectedID: id, retrievedAt: now())
    }

    private func requireReading(_ session: GmailAccessSession) throws {
        try Task.checkCancellation()
        guard session.canReadMessages else { throw GmailConnectionError.readAccessRequired }
        guard session.expiresAt.timeIntervalSince(now()) > 30 else { throw GmailConnectionError.sessionExpired }
    }

    private func messageRequest(path: String, query: [URLQueryItem], session: GmailAccessSession) throws -> URLRequest {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/\(path)")!
        components.queryItems = query
        guard let url = components.url else { throw GmailConnectionError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func perform(_ request: URLRequest, exchangingCode: Bool = false, refreshing: Bool = false, maximumBytes: Int = 65_536) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
            try Task.checkCancellation()
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if let error = error as? GmailConnectionError { throw error }
            if error is URLError { throw GmailConnectionError.networkUnavailable }
            throw GmailConnectionError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw GmailConnectionError.invalidResponse
        }
        if refreshing, http.statusCode == 400, data.count <= maximumBytes, http.mimeType == "application/json",
           let error = try? JSONDecoder().decode(GmailRefreshFailure.self, from: data), error.error == "invalid_grant" {
            throw GmailRefreshError.revoked
        }
        switch http.statusCode {
        case 200: break
        case 300...399: throw GmailConnectionError.redirectRejected
        case 401: throw GmailConnectionError.sessionExpired
        case 403: throw GmailConnectionError.permissionDenied
        case 404: throw GmailConnectionError.messageUnavailable
        case 429: throw GmailConnectionError.rateLimited
        case 400 where exchangingCode: throw GmailConnectionError.authorizationFailed
        default: throw GmailConnectionError.serviceUnavailable
        }
        guard data.count <= maximumBytes else { throw GmailConnectionError.messageTooLarge }
        guard http.mimeType == "application/json" else { throw GmailConnectionError.invalidResponse }
        return data
    }

    private static let bearerCharacters = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~+/=".utf8)

    private static func formBody(_ values: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let form = values.keys.sorted().map { key in
            "\(key)=\(values[key]!.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
        return Data(form.utf8)
    }
}

/// All redirects are refused, including same-host redirects, so the bearer token is
/// never forwarded to a new URL. This session also has no persistent cache or cookies.
final class GmailRedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
private final class GmailEphemeralTransport {
    private let session: URLSession

    init() {
        session = URLSession(configuration: Self.configuration(), delegate: GmailRedirectBlocker(), delegateQueue: nil)
    }

    static func configuration() -> URLSessionConfiguration {
        let value = URLSessionConfiguration.ephemeral
        value.urlCache = nil
        value.httpCookieStorage = nil
        value.urlCredentialStorage = nil
        value.httpShouldSetCookies = false
        value.requestCachePolicy = .reloadIgnoringLocalCacheData
        value.timeoutIntervalForRequest = 20
        value.timeoutIntervalForResource = 30
        return value
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard response.expectedContentLength <= GmailMessageLimits.maximumWireBytes else {
            throw GmailConnectionError.messageTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            if data.count.isMultiple(of: 4_096) { try Task.checkCancellation() }
            guard data.count < GmailMessageLimits.maximumWireBytes else { throw GmailConnectionError.messageTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response)
    }

    deinit { session.invalidateAndCancel() }
}

private enum GmailRefreshError: Error { case revoked }
private struct GmailRefreshFailure: Decodable { let error: String }
