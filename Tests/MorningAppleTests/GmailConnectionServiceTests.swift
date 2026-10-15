import Foundation
import Synchronization
import Testing
@testable import MorningApple

/// Offline protocol/component proof only. No Google account or Gmail API is contacted.
@Suite("Gmail read-only connection — synthetic HTTP responses only")
@MainActor
struct GmailConnectionServiceTests {
    private static let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private static let clientID = "123456789-synthetic.apps.googleusercontent.com"
    private static let scheme = "com.googleusercontent.apps.123456789-synthetic"
    private static let state = String(repeating: "s", count: 43)
    private static let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    private static let tokenJSON = #"{"access_token":"SYNTHETIC_TOKEN","token_type":"Bearer","expires_in":3600,"scope":"https://www.googleapis.com/auth/gmail.metadata","refresh_token":"DISCARD_SYNTHETIC_REFRESH_TOKEN"}"#

    @Test func configurationFailsBeforeAnyAuthorizationForMissingOrMismatchedClient() throws {
        #expect(throws: GmailConnectionError.configurationMissing) {
            try GmailOAuthConfiguration(clientID: "", registeredURLSchemes: [])
        }
        for client in ["synthetic", " https://example.invalid", "bad/name.apps.googleusercontent.com", ".apps.googleusercontent.com"] {
            #expect(throws: GmailConnectionError.configurationInvalid) {
                try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [Self.scheme])
            }
        }
        #expect(throws: GmailConnectionError.configurationInvalid) {
            try GmailOAuthConfiguration(clientID: Self.clientID, registeredURLSchemes: ["unrelated.scheme"])
        }
        let configuration = try configuration()
        #expect(configuration.callbackScheme == Self.scheme)
        #expect(configuration.redirectURI.absoluteString == "\(Self.scheme):/oauth2redirect")
    }

    @Test func authorizationUsesNarrowScopeStateAndKnownS256ChallengeWithoutOfflineAccess() throws {
        let attempt = try attempt()
        let url = try #require(URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false))
        let values = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(url.scheme == "https" && url.host == "accounts.google.com" && url.path == "/o/oauth2/v2/auth")
        #expect(values["client_id"] == Self.clientID && values["response_type"] == "code")
        #expect(values["scope"] == GmailConnectionService.metadataScope && values["state"] == Self.state)
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["code_challenge"] == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        #expect(values["code_verifier"] == nil && values["access_type"] == nil && values["client_secret"] == nil)
        #expect(!String(reflecting: attempt).contains(Self.verifier))
        let freshA = try GmailAuthorizationRequest(configuration: configuration())
        let freshB = try GmailAuthorizationRequest(configuration: configuration())
        #expect(freshA.authorizationURL != freshB.authorizationURL, "Each real attempt must use new state and PKCE values.")
    }

    @Test func callbackMustMatchTheAttemptBeforeTokenExchangeAndCannotBeReused() async throws {
        var calls = 0
        let service = GmailConnectionService(transport: { request in
            calls += 1
            return Self.response(for: request, body: Self.tokenJSON)
        }, now: { Self.instant })
        let badCallbacks = [
            "unrelated.scheme:/oauth2redirect?state=\(Self.state)&code=fake",
            "\(Self.scheme)://host/oauth2redirect?state=\(Self.state)&code=fake",
            "\(Self.scheme):/other?state=\(Self.state)&code=fake",
            "\(Self.scheme):/oauth2redirect?state=wrong&code=fake",
            "\(Self.scheme):/oauth2redirect?state=\(Self.state)&state=\(Self.state)&code=fake",
            "\(Self.scheme):/oauth2redirect?state=\(Self.state)&code=one&code=two",
            "\(Self.scheme):/oauth2redirect?state=\(Self.state)&code=fake&error=access_denied",
            "\(Self.scheme):/oauth2redirect?state=\(Self.state)&code=fake#fragment",
            "\(Self.scheme):/oauth2redirect?state=\(Self.state)&code=line%0Abreak"
        ]
        for callback in badCallbacks {
            let current = try attempt()
            await #expect(throws: GmailConnectionError.invalidCallback) {
                try await service.completeAuthorization(current, callbackURL: URL(string: callback)!)
            }
        }
        #expect(calls == 0)
        let current = try attempt()
        _ = try await service.completeAuthorization(current, callbackURL: callback())
        await #expect(throws: GmailConnectionError.invalidCallback) {
            try await service.completeAuthorization(current, callbackURL: callback())
        }
        #expect(calls == 1)
        let denied = try attempt()
        await #expect(throws: GmailConnectionError.permissionDenied) {
            try await service.completeAuthorization(denied,
                callbackURL: URL(string: "\(Self.scheme):/oauth2redirect?state=\(Self.state)&error=access_denied")!)
        }
        #expect(calls == 1)
    }

    @Test func exchangeEncodesCodeAndVerifierAndKeepsOnlyValidatedMemoryAccessSession() async throws {
        var requests: [URLRequest] = []
        let service = GmailConnectionService(transport: { request in
            requests.append(request)
            return Self.response(for: request, body: Self.tokenJSON)
        }, now: { Self.instant })
        let session = try await service.completeAuthorization(attempt(), callbackURL: callback(code: "fake+code/=&"))
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.httpMethod == "POST" && request.timeoutInterval == 20)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains("code=fake%2Bcode%2F%3D%26") && body.contains("code_verifier=\(Self.verifier)"))
        #expect(body.contains("grant_type=authorization_code") && !body.contains("client_secret") && !body.contains("refresh_token"))
        #expect(session.expiresAt == Self.instant.addingTimeInterval(3_600))
        #expect(!String(reflecting: session).contains("SYNTHETIC_TOKEN"))
        #expect(!String(reflecting: session).contains("DISCARD_SYNTHETIC_REFRESH_TOKEN"))
    }

    @Test func missingGrantMalformedOrUnsafeTokenNeverCreatesASession() async throws {
        let invalid = [
            #"{"access_token":"fake","token_type":"Bearer","expires_in":3600}"#,
            #"{"access_token":"fake","token_type":"Other","expires_in":3600,"scope":"https://www.googleapis.com/auth/gmail.metadata"}"#,
            #"{"access_token":"fake\nInjected","token_type":"Bearer","expires_in":3600,"scope":"https://www.googleapis.com/auth/gmail.metadata"}"#,
            #"{"access_token":"fake","token_type":"Bearer","expires_in":0,"scope":"https://www.googleapis.com/auth/gmail.metadata"}"#
        ]
        for body in invalid {
            let service = GmailConnectionService(transport: { Self.response(for: $0, body: body) })
            await #expect(throws: GmailConnectionError.invalidResponse) {
                try await service.completeAuthorization(attempt(), callbackURL: callback())
            }
        }
        let noGrant = GmailConnectionService(transport: {
            Self.response(for: $0, body: Self.tokenJSON.replacingOccurrences(of: GmailConnectionService.metadataScope, with: "unrelated.scope"))
        })
        await #expect(throws: GmailConnectionError.permissionDenied) {
            try await noGrant.completeAuthorization(attempt(), callbackURL: callback())
        }
    }

    @Test func inboxReadUsesOnlyExactLabelAndZeroNeedsASuccessfulActualField() async throws {
        let session = try await session()
        for count in [0, 42] {
            var requests: [URLRequest] = []
            let service = GmailConnectionService(transport: { request in
                requests.append(request)
                return Self.response(for: request, body: "{\"id\":\"INBOX\",\"messagesUnread\":\(count)}")
            }, now: { Self.instant })
            let snapshot = try await service.inboxUnreadCount(session: session)
            #expect(snapshot.unreadMessageCount == count && snapshot.retrievedAt == Self.instant)
            #expect(snapshot.isCurrent(at: Self.instant.addingTimeInterval(59)))
            #expect(!snapshot.isCurrent(at: Self.instant.addingTimeInterval(60)))
            #expect(!snapshot.isCurrent(at: Self.instant.addingTimeInterval(-1)))
            let request = try #require(requests.first)
            #expect(request.url?.absoluteString == "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX?fields=id,messagesUnread")
            #expect(request.httpMethod == "GET" && request.httpBody == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer SYNTHETIC_TOKEN")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData && request.timeoutInterval == 20)
        }
        for body in [#"{"id":"INBOX"}"#, #"{"id":"OTHER","messagesUnread":0}"#,
                     #"{"id":"INBOX","messagesUnread":-1}"#, #"{"id":"INBOX","messagesUnread":1.5}"#,
                     #"{"id":"INBOX","messagesUnread":null}"#, #"{"id":"INBOX","messagesUnread":"0"}"#] {
            let service = GmailConnectionService(transport: { Self.response(for: $0, body: body) }, now: { Self.instant })
            await #expect(throws: GmailConnectionError.invalidResponse) { try await service.inboxUnreadCount(session: session) }
        }
    }

    @Test func expiredAccessNeverContactsGmailAndExpiryDuringReadCannotSucceed() async throws {
        let session = try await session()
        var calls = 0
        let expired = GmailConnectionService(transport: { request in
            calls += 1
            return Self.response(for: request, body: #"{"id":"INBOX","messagesUnread":0}"#)
        }, now: { Self.instant.addingTimeInterval(3_571) })
        await #expect(throws: GmailConnectionError.sessionExpired) { try await expired.inboxUnreadCount(session: session) }
        #expect(calls == 0)
        var clock = Self.instant
        let duringRead = GmailConnectionService(transport: { request in
            clock = Self.instant.addingTimeInterval(3_601)
            return Self.response(for: request, body: #"{"id":"INBOX","messagesUnread":0}"#)
        }, now: { clock })
        await #expect(throws: GmailConnectionError.sessionExpired) { try await duringRead.inboxUnreadCount(session: session) }
    }

    @Test func failuresAreBoundedStaticAndNeverExposeRemoteErrorBodies() async throws {
        let session = try await session()
        let expected: [(Int, GmailConnectionError)] = [(302, .redirectRejected), (401, .sessionExpired),
            (403, .permissionDenied), (429, .rateLimited), (500, .serviceUnavailable)]
        for (status, error) in expected {
            let service = GmailConnectionService(transport: {
                Self.response(for: $0, body: "PRIVATE_SYNTHETIC_REMOTE_BODY", status: status)
            }, now: { Self.instant })
            await #expect(throws: error) { try await service.inboxUnreadCount(session: session) }
            #expect(!error.localizedDescription.contains("PRIVATE_SYNTHETIC"))
        }
        let badURL = GmailConnectionService(transport: { request in
            let response = HTTPURLResponse(url: URL(string: "https://example.invalid/unexpected")!, statusCode: 200,
                                           httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            return (Data(#"{"id":"INBOX","messagesUnread":0}"#.utf8), response)
        }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.invalidResponse) { try await badURL.inboxUnreadCount(session: session) }
        let offline = GmailConnectionService(transport: { _ in throw URLError(.notConnectedToInternet) }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.networkUnavailable) { try await offline.inboxUnreadCount(session: session) }
        let privateError = GmailConnectionService(transport: { _ in
            throw NSError(domain: "Synthetic", code: 7, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SYNTHETIC_REMOTE_ERROR"])
        }, now: { Self.instant })
        await #expect(throws: GmailConnectionError.serviceUnavailable) { try await privateError.inboxUnreadCount(session: session) }
    }

    @Test func cancellationSurvivesAnInFlightTransportAndLateIgnoredCancellation() async throws {
        let session = try await session()
        var entered = false
        let service = GmailConnectionService(transport: { request in
            entered = true
            try? await Task.sleep(for: .seconds(30)) // An uncooperative synthetic provider.
            return Self.response(for: request, body: #"{"id":"INBOX","messagesUnread":0}"#)
        }, now: { Self.instant })
        let read = Task { try await service.inboxUnreadCount(session: session) }
        while !entered { await Task.yield() }
        read.cancel()
        await #expect(throws: CancellationError.self) { try await read.value }
    }

    @Test func redirectDelegateRefusesToForwardBearerToAnyNewURL() {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/labels/INBOX")!)
        let task = session.dataTask(with: original) // Never resumed; no network request.
        let response = HTTPURLResponse(url: original.url!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        for destination in ["https://example.invalid/steal", "https://gmail.googleapis.com/other"] {
            var proposed = URLRequest(url: URL(string: destination)!)
            proposed.setValue("Bearer SYNTHETIC_TOKEN", forHTTPHeaderField: "Authorization")
            let rejected = Mutex(false)
            GmailRedirectBlocker().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: proposed) { value in
                rejected.withLock { $0 = value == nil }
            }
            #expect(rejected.withLock { $0 })
        }
    }

    private func configuration() throws -> GmailOAuthConfiguration {
        try GmailOAuthConfiguration(clientID: Self.clientID, registeredURLSchemes: [Self.scheme])
    }

    private func attempt() throws -> GmailAuthorizationRequest {
        try GmailAuthorizationRequest(configuration: configuration(), verifier: Self.verifier, state: Self.state)
    }

    private func callback(code: String = "synthetic-code") -> URL {
        var parts = URLComponents(string: "\(Self.scheme):/oauth2redirect")!
        parts.queryItems = [URLQueryItem(name: "state", value: Self.state), URLQueryItem(name: "code", value: code)]
        return parts.url!
    }

    private func session() async throws -> GmailAccessSession {
        let service = GmailConnectionService(transport: { Self.response(for: $0, body: Self.tokenJSON) }, now: { Self.instant })
        return try await service.completeAuthorization(attempt(), callbackURL: callback())
    }

    private static func response(for request: URLRequest, body: String, status: Int = 200) -> (Data, URLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                        headerFields: ["Content-Type": "application/json; charset=UTF-8"])!)
    }
}
