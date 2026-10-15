import Foundation
import Security

/// The owner's saved authorization only; no messages, counts, drafts or access
/// tokens belong here. Privacy cleanup calls this even while the data gate is closed.
public enum GmailCredentialStore {
    public nonisolated static func removeSavedConnection() throws {
        try GmailKeychainCredentialStorage().remove()
    }
}

/// Internal injection boundary: protocol tests never read or write live Keychain.
protocol GmailCredentialStorage: Sendable {
    func load() throws -> Data?
    func save(_ data: Data) throws
    func remove() throws
}

struct GmailKeychainCredentialStorage: GmailCredentialStorage {
    private let service: String
    private let account = "gmail-readonly-refresh-v1"

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "MorningOperator") {
        service = "\(bundleIdentifier).gmail.oauth"
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func load() throws -> Data? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data, data.count <= 16_384 else {
            throw GmailConnectionError.credentialStorageUnavailable
        }
        return data
    }

    func save(_ data: Data) throws {
        guard data.count <= 16_384 else { throw GmailConnectionError.savedConnectionInvalid }
        let attributes: [String: Any] = [kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let updated = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw GmailConnectionError.credentialStorageUnavailable }
        var request = query
        for (key, value) in attributes { request[key] = value }
        guard SecItemAdd(request as CFDictionary, nil) == errSecSuccess else {
            throw GmailConnectionError.credentialStorageUnavailable
        }
    }

    func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GmailConnectionError.credentialStorageUnavailable
        }
    }
}

/// A nonsecret installation marker stays in the app container, which is removed
/// on uninstall. Keychain can survive uninstall, so a missing/new marker must not
/// silently restore an older installation's authorization (including nil generations).
@MainActor
enum GmailInstallationIdentifier {
    static func current() throws -> UUID { try current(defaults: .standard) }

    static func current(defaults: UserDefaults) throws -> UUID {
        let key = "gmail.installationIdentifier.v1"
        if let text = defaults.object(forKey: key) as? String, let id = UUID(uuidString: text) {
            return id
        }
        let id = UUID()
        // A damaged marker is equivalent to a fresh installation. Replacing it
        // makes any old Keychain record mismatch safely, without trapping Connect.
        defaults.set(id.uuidString, forKey: key)
        return id
    }
}

struct GmailSavedCredential: Codable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let schemaVersion: Int
    let id: UUID
    let clientID: String
    let scope: String
    let refreshToken: String
    let generation: UUID?
    let installationID: UUID
    var description: String { "GmailSavedCredential(redacted)" }
    var debugDescription: String { description }

    init(clientID: String, refreshToken: String, generation: UUID?, installationID: UUID) {
        schemaVersion = 1
        id = UUID()
        self.clientID = clientID
        scope = GmailConnectionService.readonlyScope
        self.refreshToken = refreshToken
        self.generation = generation
        self.installationID = installationID
    }
}
