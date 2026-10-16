import Foundation

/// Only the Instagram browser opts into this rule. Account authorization and
/// explicit native routes elsewhere keep their own navigation policy.
public struct InstagramBrowserNavigation: Sendable {
    public enum Kind: Sendable { case other, link, form, history }
    public enum Decision: Equatable, Sendable { case allow, cancel, load(URL) }
    private var pendingLoad: URL?

    public init() {}

    /// A public WKWebView.load request does not try universal app links. Replay
    /// web-initiated Instagram GETs through that API, accepting its next callback
    /// once. Each redirect gets the same check; POST sign-in requests keep their body.
    public mutating func decide(url: URL, kind: Kind, method: String = "GET",
                                isTopLevel: Bool = true, isNewWindow: Bool = false,
                                isDownload: Bool = false) -> Decision {
        guard url.user == nil, url.password == nil, !isDownload else { return .cancel }
        if url.scheme?.lowercased() == "instagram" {
            guard isTopLevel, method == "GET", let destination = Self.webURL(for: url) else { return .cancel }
            pendingLoad = destination
            return .load(destination)
        }
        guard url.scheme?.lowercased() == "https" else { return .cancel }
        guard isTopLevel, Self.isInstagramURL(url) else { return .allow }
        if !isNewWindow, kind == .other, method == "GET", pendingLoad == url {
            pendingLoad = nil
            return .allow
        }
        pendingLoad = nil
        guard method == "GET", kind == .link || kind == .other else { return .allow }
        pendingLoad = url
        return .load(url)
    }

    private static func isInstagramURL(_ url: URL) -> Bool {
        guard url.port == nil || url.port == 443, let host = url.host?.lowercased() else { return false }
        return host == "instagram.com" || host.hasSuffix(".instagram.com")
    }

    /// Only browser equivalents with an unambiguous destination are translated.
    /// Unknown app actions (sharing, camera, authorization callbacks) stay refused.
    private static func webURL(for url: URL) -> URL? {
        guard url.port == nil, url.path.isEmpty || url.path == "/",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch url.host?.lowercased() {
        case "app":
            guard components.queryItems?.isEmpty != false else { return nil }
            return WebMorningSite.instagram.table.startURL
        case "user":
            guard let items = components.queryItems, items.count == 1, items[0].name == "username",
                  let value = items[0].value, let username = StepApp.username(value) else { return nil }
            return URL(string: "https://www.instagram.com/\(username)/")
        default: return nil
        }
    }
}
