import Foundation

/// Only the Instagram browser opts into this rule. Account authorization and
/// explicit native routes elsewhere keep their own navigation policy.
public struct InstagramBrowserNavigation: Sendable {
    public enum Kind: Sendable { case other, link, form, history }
    public enum Decision: Equatable, Sendable { case allow, cancel, load(URL) }
    private var pendingLoad: URL?
    private var replayCount = 0

    public init() {}

    /// A public WKWebView.load request does not try universal app links. Replay
    /// web-initiated GETs in the Instagram browser through that API, accepting its next callback
    /// once. Each redirect gets the same check; POST sign-in requests keep their body.
    public mutating func decide(url: URL, kind: Kind, method: String = "GET",
                                committedURL: URL? = nil,
                                isTopLevel: Bool = true, isNewWindow: Bool = false,
                                isDownload: Bool = false) -> Decision {
        guard url.user == nil, url.password == nil, !isDownload else { return .cancel }
        if url.scheme?.lowercased() == "instagram" {
            guard isTopLevel, method == "GET", let destination = Self.webURL(for: url) else { return .cancel }
            return load(destination)
        }
        guard url.scheme?.lowercased() == "https" else { return .cancel }
        // An Instagram redirect may lead to an app-store or link-wrapper host.
        // Keeping this whole browser's GET chain in WebKit closes that escape too.
        guard isTopLevel else { return .allow }
        if !isNewWindow, kind == .other, method == "GET", pendingLoad == url {
            pendingLoad = nil
            return .allow
        }
        pendingLoad = nil
        if method != "GET" {
            // Same-host forms cannot trigger WebKit's app-link route. A
            // cross-host form can, and its credential body may be unavailable
            // for a safe replay, so leave the current page in place.
            guard let host = url.host?.lowercased(), committedURL?.host?.lowercased() == host else { return .cancel }
            return .allow
        }
        guard kind != .history else { return .allow }
        return load(url)
    }

    private mutating func load(_ url: URL) -> Decision {
        // Replaying must not turn a server redirect loop into unlimited fresh
        // loads. The controller resets this chain on finish, failure or Reload.
        guard replayCount < 16 else { pendingLoad = nil; return .cancel }
        replayCount += 1
        pendingLoad = url
        return .load(url)
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
