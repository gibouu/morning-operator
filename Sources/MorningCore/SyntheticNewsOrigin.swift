import Foundation

/// Volatile private QA capability. It is neither a saved target nor a learned
/// identity, and cannot authorize a network URL or any non-news behavior.
public struct SyntheticNewsOrigin: Sendable, Equatable {
    public static let scheme = "more-qa-news"
    public static let paths = ["/headlines", "/article/one", "/article/two", "/article/three"]
    public let workspaceID: UUID
    private init(workspaceID: UUID) { self.workspaceID = workspaceID }

    public static func requested(arguments: [String], directory: URL) -> Self? {
        #if DEBUG
        let workspaces = arguments.filter { $0.hasPrefix("--ui-testing-workspace=") }
        guard arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
              arguments.contains("--ui-testing-private-news"), workspaces.count == 1,
              let id = UUID(uuidString: String(workspaces[0].dropFirst("--ui-testing-workspace=".count))) else { return nil }
        let expected = FileManager.default.temporaryDirectory.appendingPathComponent("MorningOperatorUITests-\(id.uuidString)", isDirectory: true)
        guard directory.standardizedFileURL == expected.standardizedFileURL else { return nil }
        return Self(workspaceID: id)
        #else
        return nil
        #endif
    }

    public var startURL: URL { url(path: Self.paths[0]) }
    private func url(path: String) -> URL {
        // All callers supply a registered literal; unregistered URLs still fail permits.
        URL(string: "\(Self.scheme)://\(workspaceID.uuidString.lowercased())\(path)")!
    }
    public func permits(_ url: URL?) -> Bool {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == Self.scheme && parts.host == workspaceID.uuidString.lowercased() &&
            parts.user == nil && parts.password == nil && parts.port == nil && parts.query == nil && parts.fragment == nil &&
            Self.paths.contains(parts.percentEncodedPath)
    }

    // A custom scheme must not inherit the browser's opaque URL.origin equality.
    func javascriptPermits(_ name: String) -> String {
        let encoded: (Any) -> String = { value in
            String(decoding: (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])) ?? Data("null".utf8), as: UTF8.self)
        }
        return "(\(name).protocol===\(encoded(Self.scheme + ":")) && \(name).hostname===\(encoded(workspaceID.uuidString.lowercased())) && !\(name).port && !\(name).username && !\(name).password && !\(name).search && !\(name).hash && \(encoded(Self.paths)).includes(\(name).pathname))"
    }
}
