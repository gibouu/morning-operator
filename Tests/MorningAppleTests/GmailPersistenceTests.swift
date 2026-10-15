import Foundation
import MorningCore
import Synchronization
import Testing
@testable import MorningApple

/// Synthetic tokens/in-memory credentials/temp privacy gate only. No live
/// Keychain, preferences, Google account, mail, network or app fixture access.
@Suite("Gmail saved connection — synthetic credential/HTTP proof only")
@MainActor
struct GmailPersistenceTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private let client = "123456789-synthetic.apps.googleusercontent.com"
    private let scheme = "com.googleusercontent.apps.123456789-synthetic"
    private let state = String(repeating: "s", count: 43)

    @Test func damagedInstallationMarkerRecoversWithoutReusingOldIdentity() throws {
        let suite = "MORE.GmailSyntheticDefaults.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for malformed: Any in [42, "not-a-uuid"] {
            defaults.set(malformed, forKey: "gmail.installationIdentifier.v1")
            let repaired = try GmailInstallationIdentifier.current(defaults: defaults)
            #expect(try GmailInstallationIdentifier.current(defaults: defaults) == repaired)
            #expect(defaults.string(forKey: "gmail.installationIdentifier.v1") == repaired.uuidString)
        }
    }

    @Test func onlyExplicitReadAuthorizationRequestsOfflineConsentAndKeepsPrivateRefresh() async throws {
        for access: GmailAuthorizationAccess in [.metadata, .readMessages] {
            let attempt = try attempt(access)
            let query = URLComponents(url: attempt.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(query.first(where: { $0.name == "access_type" })?.value == (access == .readMessages ? "offline" : nil))
            #expect(query.first(where: { $0.name == "prompt" })?.value == (access == .readMessages ? "consent" : nil))
            #expect(query.first(where: { $0.name == "scope" })?.value == (access == .readMessages ? GmailConnectionService.readonlyScope : GmailConnectionService.metadataScope))
        }
        let context = try Context()
        defer { context.cleanup() }
        let reader = service(context) { response($0, token(refresh: "SYNTHETIC_REFRESH")) }
        let read = try await reader.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        #expect(read.canReadMessages && read.canStayConnected)
        #expect(!String(reflecting: read).contains("SYNTHETIC"))
        try reader.saveConnection(session: read, generation: nil)
        let data = try #require(try context.storage.load())
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["refreshToken"] as? String == "SYNTHETIC_REFRESH")
        #expect(object["accessToken"] == nil && object["messages"] == nil && object["draft"] == nil)
        let noRefresh = service(context) { response($0, token()) }
        let ephemeral = try await noRefresh.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        #expect(!ephemeral.canStayConnected)
        #expect(throws: GmailConnectionError.savedConnectionInvalid) { try noRefresh.saveConnection(session: ephemeral, generation: nil) }
        let metadata = service(context) { response($0, token(scope: GmailConnectionService.metadataScope, refresh: "SYNTHETIC_DISCARD")) }
        let count = try await metadata.completeAuthorization(attempt(.metadata), callbackURL: callback())
        #expect(!count.canStayConnected)
        #expect(throws: GmailConnectionError.savedConnectionInvalid) { try metadata.saveConnection(session: count, generation: nil) }
    }

    @Test func newServiceRestoresWithoutBrowserAndRotatesOnlyRefreshCredential() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context, refresh: "SYNTHETIC_OLD_REFRESH")
        var requests: [URLRequest] = []
        let reader = service(context) { request in
            requests.append(request)
            return response(request, token(refresh: "SYNTHETIC_ROTATED_REFRESH"))
        }
        let session = try #require(try await reader.restoreConnection(generation: nil))
        #expect(session.canReadMessages && session.canStayConnected)
        #expect(session.expiresAt == instant.addingTimeInterval(3_600))
        #expect(requests.count == 1 && requests[0].httpMethod == "POST")
        #expect(requests[0].url?.absoluteString == "https://oauth2.googleapis.com/token")
        let body = String(data: requests[0].httpBody!, encoding: .utf8)!
        #expect(body.contains("grant_type=refresh_token") && body.contains("refresh_token=SYNTHETIC_OLD_REFRESH"))
        #expect(!body.contains("client_secret") && !body.contains("authorization_code"))
        let saved = try #require(try context.storage.load())
        #expect(String(data: saved, encoding: .utf8)?.contains("SYNTHETIC_ROTATED_REFRESH") == true)
        #expect(!String(reflecting: session).contains("SYNTHETIC"))
        let same = service(context) { request in
            #expect(String(data: request.httpBody!, encoding: .utf8)!.contains("SYNTHETIC_ROTATED_REFRESH"))
            var value = token()
            value.removeValue(forKey: "scope") // OAuth refresh may omit unchanged scope.
            return response(request, value)
        }
        #expect(try await same.restoreConnection(generation: nil)?.canReadMessages == true)
        #expect(try context.storage.load() == saved)
    }

    @Test func missingCredentialDoesNotReadConfigurationOrContactServer() async throws {
        let context = try Context()
        defer { context.cleanup() }
        var calls = 0
        let reader = GmailConnectionService(transport: { request in calls += 1; return response(request, [:]) }, now: { instant },
            credentialStorage: context.storage, privacyControl: context.privacy,
            configurationProvider: { throw GmailConnectionError.configurationMissing }, installationID: { context.installation })
        #expect(try await reader.restoreConnection(generation: nil) == nil)
        #expect(calls == 0)
    }

    @Test func invalidGrantRemovesCredentialAndReturnsReconnectWithoutRemoteErrorText() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        let reader = service(context) { response($0, ["error": "invalid_grant", "error_description": "PRIVATE_SYNTHETIC_REMOTE_ERROR"], status: 400) }
        #expect(try await reader.restoreConnection(generation: nil) == nil)
        #expect(try context.storage.load() == nil)
    }

    @Test func transientHTTPNetworkAndMalformedFailuresPreserveCredential() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        let original = try context.storage.load()
        for (status, expected): (Int, GmailConnectionError) in [(429, .rateLimited), (500, .serviceUnavailable), (403, .permissionDenied), (302, .redirectRejected)] {
            let reader = service(context) { response($0, ["error": "PRIVATE_SYNTHETIC_ERROR"], status: status) }
            await #expect(throws: expected) { try await reader.restoreConnection(generation: nil) }
            #expect(try context.storage.load() == original)
        }
        let offline = service(context) { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: GmailConnectionError.networkUnavailable) { try await offline.restoreConnection(generation: nil) }
        #expect(try context.storage.load() == original)
        for object: [String: Any] in [["access_token": "SYNTHETIC"], token(refresh: "unsafe\nrefresh")] {
            let reader = service(context) { response($0, object) }
            await #expect(throws: GmailConnectionError.self) { try await reader.restoreConnection(generation: nil) }
            #expect(try context.storage.load() == original)
        }
    }

    @Test func confirmedReadScopeLossRemovesCredentialAndRequestsOneReconnect() async throws {
        for scope in ["unrelated.scope", GmailConnectionService.metadataScope] {
            let context = try Context()
            defer { context.cleanup() }
            try await save(context)
            let reader = service(context) { response($0, token(scope: scope)) }
            #expect(try await reader.restoreConnection(generation: nil) == nil)
            #expect(try context.storage.load() == nil)
        }
    }

    @Test func generationChangesRejectFreshSaveAndLateRotationUnderThePrivacyLock() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        var release: CheckedContinuation<Void, Never>?
        let reader = service(context) { request in
            await withCheckedContinuation { release = $0 }
            return response(request, token(refresh: "SYNTHETIC_LATE_ROTATION"))
        }
        let restore = Task { try await reader.restoreConnection(generation: nil) }
        while release == nil { await Task.yield() }
        let forget = try context.privacy.beginForget()
        try context.storage.remove()
        try context.privacy.finishForget(expectedGeneration: #require(forget.generation))
        release?.resume()
        await #expect(throws: GmailConnectionError.connectionChanged) { try await restore.value }
        #expect(try context.storage.load() == nil)
        let authorizer = service(context) { response($0, token(refresh: "SYNTHETIC_FRESH")) }
        let session = try await authorizer.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        #expect(throws: GmailConnectionError.connectionChanged) { try authorizer.saveConnection(session: session, generation: nil) }
        #expect(try context.storage.load() == nil)
    }

    @Test func newConsentAfterCompletedForgetCanSaveAndRestoreItsNewGeneration() async throws {
        let context = try Context()
        defer { context.cleanup() }
        let pending = try context.privacy.beginForget()
        let generation = try #require(pending.generation)
        try context.privacy.finishForget(expectedGeneration: generation)
        let reader = service(context) { response($0, token(refresh: "SYNTHETIC_POST_FORGET")) }
        let session = try await reader.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        try reader.saveConnection(session: session, generation: generation)
        #expect(try await reader.restoreConnection(generation: generation)?.canReadMessages == true)
    }

    @Test func disconnectDuringRefreshCannotBeUndoneByItsLateResponse() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        var release: CheckedContinuation<Void, Never>?
        let reader = service(context) { request in
            await withCheckedContinuation { release = $0 }
            return response(request, token(refresh: "SYNTHETIC_LATE"))
        }
        let restore = Task { try await reader.restoreConnection(generation: nil) }
        while release == nil { await Task.yield() }
        try reader.disconnect()
        release?.resume()
        await #expect(throws: GmailConnectionError.connectionChanged) { try await restore.value }
        #expect(try context.storage.load() == nil)
    }

    @Test func replacementAuthorizationDuringRefreshCannotBeOverwrittenOrDeleted() async throws {
        for status in [200, 400] {
            let context = try Context()
            defer { context.cleanup() }
            try await save(context)
            var release: CheckedContinuation<Void, Never>?
            let reader = service(context) { request in
                await withCheckedContinuation { release = $0 }
                return response(request, status == 200 ? token(refresh: "SYNTHETIC_LATE") : ["error": "invalid_grant"], status: status)
            }
            let restore = Task { try await reader.restoreConnection(generation: nil) }
            while release == nil { await Task.yield() }
            try await save(context, refresh: "SYNTHETIC_REPLACEMENT")
            let replacement = try context.storage.load()
            release?.resume()
            await #expect(throws: GmailConnectionError.connectionChanged) { try await restore.value }
            #expect(try context.storage.load() == replacement)
        }
    }

    @Test func cancellationNeverRotatesOrDeletesSavedCredential() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        let original = try context.storage.load()
        var release: CheckedContinuation<Void, Never>?
        let reader = service(context) { request in
            await withCheckedContinuation { release = $0 }
            return response(request, token(refresh: "SYNTHETIC_CANCELLED"))
        }
        let restore = Task { try await reader.restoreConnection(generation: nil) }
        while release == nil { await Task.yield() }
        restore.cancel(); release?.resume()
        await #expect(throws: CancellationError.self) { try await restore.value }
        #expect(try context.storage.load() == original)
    }

    @Test func newInstallationWithNilGenerationRemovesSurvivingKeychainWithoutRefresh() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        let newInstallation = UUID()
        var calls = 0
        let reader = GmailConnectionService(transport: { request in calls += 1; return response(request, token()) }, now: { instant },
            credentialStorage: context.storage, privacyControl: context.privacy,
            configurationProvider: configuration, installationID: { newInstallation })
        #expect(try await reader.restoreConnection(generation: nil) == nil)
        #expect(try context.storage.load() == nil && calls == 0)
    }

    @Test func corruptedScopeClientGenerationAndStorageErrorsStayStaticAndFailClosed() async throws {
        let context = try Context()
        defer { context.cleanup() }
        try await save(context)
        let original = try #require(try context.storage.load())
        for (key, value): (String, Any) in [("scope", "https://mail.google.com/"), ("clientID", "different.apps.googleusercontent.com"), ("generation", UUID().uuidString)] {
            var object = try #require(try JSONSerialization.jsonObject(with: original) as? [String: Any])
            object[key] = value
            let modified = try JSONSerialization.data(withJSONObject: object)
            try context.storage.save(modified)
            let reader = service(context) { request in Issue.record("No HTTP call permitted"); return response(request, token()) }
            await #expect(throws: GmailConnectionError.self) { try await reader.restoreConnection(generation: nil) }
            #expect(try context.storage.load() == modified)
        }
        try context.storage.save(original)
        context.storage.fail = true
        let reader = service(context) { response($0, token()) }
        await #expect(throws: GmailConnectionError.credentialStorageUnavailable) { try await reader.restoreConnection(generation: nil) }
        #expect(throws: GmailConnectionError.credentialStorageUnavailable) { try reader.disconnect() }
        #expect(!GmailConnectionError.credentialStorageUnavailable.localizedDescription.contains("PRIVATE"))
        context.storage.fail = false
        #expect(try context.storage.load() == original)
    }

    private func save(_ context: Context, refresh: String = "SYNTHETIC_REFRESH") async throws {
        let reader = service(context) { response($0, token(refresh: refresh)) }
        let session = try await reader.completeAuthorization(attempt(.readMessages), callbackURL: callback())
        try reader.saveConnection(session: session, generation: nil)
    }
    private func service(_ context: Context, transport: @escaping GmailConnectionService.Transport) -> GmailConnectionService {
        GmailConnectionService(transport: transport, now: { instant }, credentialStorage: context.storage,
            privacyControl: context.privacy, configurationProvider: configuration, installationID: { context.installation })
    }
    private func configuration() throws -> GmailOAuthConfiguration { try GmailOAuthConfiguration(clientID: client, registeredURLSchemes: [scheme]) }
    private func attempt(_ access: GmailAuthorizationAccess) throws -> GmailAuthorizationRequest {
        try GmailAuthorizationRequest(configuration: configuration(), verifier: String(repeating: "v", count: 43), state: state, access: access)
    }
    private func callback() -> URL { URL(string: "\(scheme):/oauth2redirect?state=\(state)&code=synthetic")! }
    private func token(scope: String = GmailConnectionService.readonlyScope, refresh: String? = nil) -> [String: Any] {
        var object: [String: Any] = ["access_token": "SYNTHETIC_ACCESS", "token_type": "Bearer", "expires_in": 3_600, "scope": scope]
        if let refresh { object["refresh_token"] = refresh }
        return object
    }
    private func response(_ request: URLRequest, _ object: [String: Any], status: Int = 200) -> (Data, URLResponse) {
        (try! JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }

    private struct Context {
        let privacy: LocalDataControl
        let storage = MemoryCredentials()
        let installation = UUID()
        init() throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("GmailPersistenceTests-\(UUID().uuidString)", isDirectory: true)
            privacy = LocalDataControl(directory: directory)
            _ = try privacy.status()
        }
        func cleanup() { try? FileManager.default.removeItem(at: privacy.directory) }
    }
}

private final class MemoryCredentials: GmailCredentialStorage, @unchecked Sendable {
    private let value = Mutex<Data?>(nil)
    private let failing = Mutex(false)
    var fail: Bool { get { failing.withLock { $0 } } set { failing.withLock { $0 = newValue } } }
    func load() throws -> Data? { try check(); return value.withLock { $0 } }
    func save(_ data: Data) throws { try check(); value.withLock { $0 = data } }
    func remove() throws { try check(); value.withLock { $0 = nil } }
    private func check() throws {
        if fail { throw NSError(domain: "Synthetic", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE_SYNTHETIC_STORAGE_ERROR"]) }
    }
}
