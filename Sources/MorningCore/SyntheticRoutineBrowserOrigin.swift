import Foundation

/// Private document input for the ordinary executor, never a saved destination
/// or action grant. Release builds cannot create this capability.
public struct SyntheticRoutineBrowserOrigin: Sendable, Equatable {
    public static let flag = "--ui-testing-private-routine-browser"
    public static let scheme = "more-qa-routine"
    public let workspaceID: UUID
    public let site: WebMorningSite
    public let isMusic: Bool

    public static func requested(arguments: [String], directory: URL, site: WebMorningSite,
                                 stepID: UUID) -> Self? {
        #if DEBUG
        let workspaces = arguments.filter { $0.hasPrefix("--ui-testing-workspace=") }
        guard arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
              arguments.contains(flag), workspaces.count == 1,
              let id = UUID(uuidString: String(workspaces[0].dropFirst("--ui-testing-workspace=".count))),
              directory.standardizedFileURL == FileManager.default.temporaryDirectory
                .appendingPathComponent("MorningOperatorUITests-\(id.uuidString)", isDirectory: true).standardizedFileURL else { return nil }
        // The frozen synthetic scenario has exactly these web moments. An
        // unrelated step cannot silently acquire a substitute page.
        let key = stepID.uuidString.lowercased()
        guard (site == .reddit && key == "90000000-0000-4000-8000-000000000005") ||
              (site == .youtube && ["90000000-0000-4000-8000-000000000006",
                                    "90000000-0000-4000-8000-000000000009"].contains(key)) else { return nil }
        return Self(workspaceID: id, site: site, isMusic: key.hasSuffix("000000000009"))
        #else
        return nil
        #endif
    }

    public var path: String { site == .reddit ? "/feed" : isMusic ? "/music" : "/videos" }
    public var startURL: URL { URL(string: "\(Self.scheme)://\(workspaceID.uuidString.lowercased())\(path)")! }
    public func permits(_ url: URL?) -> Bool {
        guard let url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == Self.scheme && parts.host == workspaceID.uuidString.lowercased() &&
            parts.user == nil && parts.password == nil && parts.port == nil && parts.query == nil && parts.fragment == nil &&
            parts.percentEncodedPath == path
    }

    func javascriptPermits(_ name: String) -> String {
        let encoded: (String) -> String = { value in
            String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
        }
        return "(\(name).protocol===\(encoded(Self.scheme + ":")) && \(name).hostname===\(encoded(workspaceID.uuidString.lowercased())) && !\(name).port && !\(name).username && !\(name).password && !\(name).search && !\(name).hash && \(name).pathname===\(encoded(path)))"
    }
}
