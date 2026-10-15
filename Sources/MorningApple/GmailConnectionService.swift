import CryptoKit
import Foundation
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

/// One browser attempt, with a fresh state and S256 verifier. Do not log the authorization URL
/// or callback, and release this attempt when the browser closes. A callback is consumed once.
@MainActor
public final class GmailAuthorizationRequest: CustomStringConvertible, CustomDebugStringConvertible {
    public let authorizationURL: URL
    public let callbackScheme: String
    fileprivate let configuration: GmailOAuthConfiguration
    fileprivate let verifier: String
    private let state: String
    private var consumed = false
    public nonisolated var description: String { "GmailAuthorizationRequest(redacted)" }
    public nonisolated var debugDescription: String { description }

    public convenience init(configuration: GmailOAuthConfiguration) throws {
        try self.init(configuration: configuration, verifier: Self.randomValue(), state: Self.randomValue())
    }

    // Internal deterministic entry point for component tests; production always uses secure random bytes.
    init(configuration: GmailOAuthConfiguration, verifier: String, state: String) throws {
        let unreserved = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8)
        guard (43...128).contains(verifier.utf8.count), verifier.utf8.allSatisfy(unreserved.contains),
              (32...128).contains(state.utf8.count), state.utf8.allSatisfy(unreserved.contains) else {
            throw GmailConnectionError.authorizationFailed
        }
        self.configuration = configuration
        self.callbackScheme = configuration.callbackScheme
        self.verifier = verifier
        self.state = state
        var url = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        url.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GmailConnectionService.metadataScope),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
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

/// Memory-only access. Intentionally neither Codable nor backed by Keychain/UserDefaults.
/// Drop it on screen dismissal/background/disconnect. A refresh token, if returned, is discarded.
public struct GmailAccessSession: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let accessToken: String
    public let expiresAt: Date
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
    case invalidResponse, redirectRejected

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
        }
    }
}

/// Only token exchange and GET of the INBOX label. No messages, send, label writes,
/// background refresh, credentials store, telemetry, automatic retries or remote revocation.
@MainActor
public final class GmailConnectionService {
    public nonisolated static let metadataScope = "https://www.googleapis.com/auth/gmail.metadata"
    public typealias Transport = @MainActor (URLRequest) async throws -> (Data, URLResponse)
    private let transport: Transport
    private let now: @MainActor () -> Date

    public convenience init() {
        let http = GmailEphemeralTransport()
        self.init(transport: { try await http.data(for: $0) })
    }

    public init(transport: @escaping Transport, now: @escaping @MainActor () -> Date = { Date() }) {
        self.transport = transport
        self.now = now
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
        struct TokenResponse: Decodable {
            let access_token: String
            let token_type: String
            let expires_in: Int
            let scope: String
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              token.token_type == "Bearer", token.expires_in > 0, token.expires_in <= 86_400,
              !token.access_token.isEmpty, token.access_token.utf8.count <= 8_192,
              token.access_token.utf8.allSatisfy(Self.bearerCharacters.contains) else {
            throw GmailConnectionError.invalidResponse
        }
        guard token.scope.split(separator: " ").contains(Substring(Self.metadataScope)) else {
            throw GmailConnectionError.permissionDenied
        }
        return GmailAccessSession(accessToken: token.access_token, expiresAt: now().addingTimeInterval(TimeInterval(token.expires_in)))
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

    private func perform(_ request: URLRequest, exchangingCode: Bool = false) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
            try Task.checkCancellation()
        } catch {
            try Task.checkCancellation()
            if error is CancellationError || (error as? URLError)?.code == .cancelled { throw CancellationError() }
            if error is URLError { throw GmailConnectionError.networkUnavailable }
            throw GmailConnectionError.serviceUnavailable
        }
        guard let http = response as? HTTPURLResponse, http.url == request.url else {
            throw GmailConnectionError.invalidResponse
        }
        switch http.statusCode {
        case 200: break
        case 300...399: throw GmailConnectionError.redirectRejected
        case 401: throw GmailConnectionError.sessionExpired
        case 403: throw GmailConnectionError.permissionDenied
        case 429: throw GmailConnectionError.rateLimited
        case 400 where exchangingCode: throw GmailConnectionError.authorizationFailed
        default: throw GmailConnectionError.serviceUnavailable
        }
        guard data.count <= 65_536, http.mimeType == "application/json" else { throw GmailConnectionError.invalidResponse }
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
        try await session.data(for: request)
    }

    deinit { session.invalidateAndCancel() }
}
