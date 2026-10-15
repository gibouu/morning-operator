import Foundation

/// A website a routine step can open inside MORE's own browser.
/// The person signs in themselves, sees the page the whole time and starts every action.
/// MORE only reads a number or headlines and scrolls to the next video. It never clicks,
/// types, posts, likes, follows or sends, and it never runs a script on a sign-in page.
public enum WebMorningSite: String, Codable, CaseIterable, Sendable, Identifiable {
    case instagram, youtube, news, whatsapp, gmail
    public var id: String { rawValue }
    public var displayName: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube Shorts"
        case .news: "Le Monde"
        case .whatsapp: "WhatsApp"
        case .gmail: "Gmail"
        }
    }
    public var table: WebMorningSiteTable { WebMorningSiteTable.table(for: self) }
}

/// What the person can ask MORE to do on a page. Every task is read-only or a scroll.
public enum WebMorningTask: String, Sendable, CaseIterable {
    /// Read one unread number (messages, chats or mail).
    case unreadCount
    /// Read the first five headlines.
    case headlines
    /// Scroll to the next short video.
    case nextVideo
}

/// How an unread number is found on a page.
public enum WebMorningCountRule: Sendable, Equatable {
    /// The first matching element's label or text holds the number; no digits means zero.
    case badge([String])
    /// The number of elements matching any selector inside the ready root.
    case matches([String])
    /// A regular expression on the document title. Group 1 is the number; absent means zero.
    case title(String)
}

/// One site's selectors and limits, kept together so markup changes are a one-table edit.
public struct WebMorningSiteTable: Sendable, Equatable {
    public let site: WebMorningSite
    public let startURL: URL
    /// Where short videos play, when the site has a feed MORE may scroll.
    public let feedURL: URL?
    public let allowedHosts: Set<String>
    /// Scrolling is refused unless the page path starts with this prefix.
    public let feedPathPrefix: String?
    /// Some sites only serve their full web app to a desktop browser.
    public let usesDesktopUserAgent: Bool
    /// At least one of these must exist, proving the signed-in page MORE expects.
    /// No match means the layout changed or the person is not signed in: fail closed.
    public let readyRoot: [String]
    public let count: WebMorningCountRule?
    public let headlines: [String]?
    /// Selector for the video elements of the feed.
    public let video: String?

    public var tasks: [WebMorningTask] {
        var tasks: [WebMorningTask] = []
        if count != nil { tasks.append(.unreadCount) }
        if headlines != nil { tasks.append(.headlines) }
        if video != nil, feedPathPrefix != nil { tasks.append(.nextVideo) }
        return tasks
    }

    // swiftlint:disable force_unwrapping
    static func table(for site: WebMorningSite) -> WebMorningSiteTable {
        switch site {
        case .instagram:
            WebMorningSiteTable(site: site, startURL: URL(string: "https://www.instagram.com/")!,
                feedURL: URL(string: "https://www.instagram.com/reels/")!,
                allowedHosts: ["www.instagram.com", "instagram.com"], feedPathPrefix: "/reel",
                usesDesktopUserAgent: false,
                readyRoot: ["a[href^=\"/direct/\"]", "video"],
                count: .badge(["a[href=\"/direct/inbox/\"]", "a[href^=\"/direct/\"]"]),
                headlines: nil, video: "video")
        case .youtube:
            WebMorningSiteTable(site: site, startURL: URL(string: "https://m.youtube.com/shorts")!,
                feedURL: URL(string: "https://m.youtube.com/shorts")!,
                allowedHosts: ["m.youtube.com", "www.youtube.com", "youtube.com"], feedPathPrefix: "/shorts",
                usesDesktopUserAgent: false,
                readyRoot: ["video"], count: nil, headlines: nil, video: "video")
        case .news:
            WebMorningSiteTable(site: site, startURL: URL(string: "https://www.lemonde.fr/")!,
                feedURL: nil, allowedHosts: ["www.lemonde.fr"], feedPathPrefix: nil,
                usesDesktopUserAgent: false,
                readyRoot: ["main", "body"], count: nil,
                headlines: [".ds-card__title__text", ".article__title", "article h3", "article h2"],
                video: nil)
        case .whatsapp:
            WebMorningSiteTable(site: site, startURL: URL(string: "https://web.whatsapp.com/")!,
                feedURL: nil, allowedHosts: ["web.whatsapp.com"], feedPathPrefix: nil,
                usesDesktopUserAgent: true,
                readyRoot: ["#pane-side"],
                count: .matches(["span[aria-label*=\"unread\" i]", "span[aria-label*=\"non lu\" i]"]),
                headlines: nil, video: nil)
        case .gmail:
            WebMorningSiteTable(site: site, startURL: URL(string: "https://mail.google.com/mail/mu/")!,
                feedURL: nil, allowedHosts: ["mail.google.com"], feedPathPrefix: nil,
                usesDesktopUserAgent: false,
                readyRoot: ["body"],
                count: .title("^(?:Inbox|Boîte de réception)(?:\\s*\\((\\d+)\\))?"),
                headlines: nil, video: nil)
        }
    }
    // swiftlint:enable force_unwrapping
}

/// Why MORE refused to run a script on the current page.
public enum WebMorningRefusal: String, Sendable, Equatable {
    case noPage, notSecure, otherSite, signInPage, notTheFeed, notOffered
}

public enum WebMorningPolicy {
    /// Path fragments that mark sign-in, consent, verification and recovery pages.
    static let signInPathFragments = [
        "login", "signin", "sign-in", "sign_in", "signup", "auth", "oauth", "challenge", "two_factor",
        "2fa", "checkpoint", "verify", "password", "recover", "consent", "connexion", "/accounts/"
    ]
    static let signInHosts = ["accounts.google.com", "accounts.youtube.com", "login.lemonde.fr",
                              "secure.lemonde.fr", "www.facebook.com", "m.facebook.com", "consent.youtube.com",
                              "consent.google.com"]

    public static func isSignInPage(_ url: URL?) -> Bool {
        guard let url, let host = url.host?.lowercased() else { return true }
        if signInHosts.contains(host) { return true }
        let path = url.path.lowercased() + "/"
        return signInPathFragments.contains { path.contains($0) }
    }

    /// The only gate before any script runs. A nil result means the task may run once, now.
    public static func refusal(for task: WebMorningTask, on site: WebMorningSite, at url: URL?) -> WebMorningRefusal? {
        let table = site.table
        guard let url else { return .noPage }
        guard url.scheme?.lowercased() == "https" else { return .notSecure }
        guard let host = url.host?.lowercased(), table.allowedHosts.contains(host) else { return .otherSite }
        guard !isSignInPage(url) else { return .signInPage }
        guard table.tasks.contains(task) else { return .notOffered }
        if task == .nextVideo, let prefix = table.feedPathPrefix, !url.path.hasPrefix(prefix) { return .notTheFeed }
        return nil
    }

    /// A self-contained, read-only script for the task, or nil when the site does not offer it.
    /// It returns one JSON string and fails closed with `unsupported` when the page does not match.
    public static func script(for task: WebMorningTask, on site: WebMorningSite) -> String? {
        let table = site.table
        guard table.tasks.contains(task) else { return nil }
        let body: String
        switch task {
        case .unreadCount:
            guard let rule = table.count else { return nil }
            switch rule {
            case .badge(let selectors):
                body = """
                const el = first(\(json(selectors)));
                if (!el) return out({status: "unsupported", reason: "layout"});
                const text = (el.getAttribute("aria-label") || "") + " " + (el.innerText || "");
                const m = text.match(/\\d+/);
                return out({status: "ok", count: m ? Math.min(parseInt(m[0], 10), 9999) : 0});
                """
            case .matches(let selectors):
                body = """
                let n = 0;
                for (const s of \(json(selectors))) { try { n = Math.max(n, root.querySelectorAll(s).length); } catch (_) {} }
                return out({status: "ok", count: Math.min(n, 9999)});
                """
            case .title(let pattern):
                body = """
                const m = (document.title || "").match(new RegExp(\(json(pattern))));
                if (!m) return out({status: "unsupported", reason: "layout"});
                return out({status: "ok", count: m[1] ? Math.min(parseInt(m[1], 10), 9999) : 0});
                """
            }
        case .headlines:
            guard let selectors = table.headlines else { return nil }
            body = """
            for (const s of \(json(selectors))) {
              let nodes = [];
              try { nodes = Array.from(document.querySelectorAll(s)); } catch (_) { continue; }
              const seen = new Set(); const list = [];
              for (const node of nodes) {
                const t = (node.innerText || node.textContent || "").replace(/\\s+/g, " ").trim();
                if (t.length < 8 || t.length > 200 || seen.has(t)) continue;
                seen.add(t); list.push(t);
                if (list.length === 5) break;
              }
              if (list.length) return out({status: "ok", headlines: list});
            }
            return out({status: "unsupported", reason: "layout"});
            """
        case .nextVideo:
            guard let video = table.video else { return nil }
            body = """
            const h = window.innerHeight;
            const vids = Array.from(document.querySelectorAll(\(json(video))));
            const v = vids.find(x => { const r = x.getBoundingClientRect(); return r.height > 0 && r.top < h / 2 && r.bottom > h / 2; });
            if (!v) return out({status: "unsupported", reason: "layout"});
            const key = location.pathname + "|" + String(v.currentSrc || v.src || "").slice(-64) + "|" + vids.indexOf(v);
            let hash = 5381; for (let i = 0; i < key.length; i++) { hash = ((hash * 33) ^ key.charCodeAt(i)) >>> 0; }
            let el = v.parentElement, scroller = null;
            while (el && el !== document.body && el !== document.documentElement) {
              const st = getComputedStyle(el);
              if (/(auto|scroll)/.test(st.overflowY) && el.scrollHeight > el.clientHeight + 10) { scroller = el; break; }
              el = el.parentElement;
            }
            let method;
            if (scroller) { scroller.scrollBy({top: scroller.clientHeight, behavior: "smooth"}); method = "container"; }
            else if (document.scrollingElement && document.scrollingElement.scrollHeight > h + 10) { window.scrollBy({top: h, behavior: "smooth"}); method = "window"; }
            else { document.dispatchEvent(new KeyboardEvent("keydown", {key: "ArrowDown", code: "ArrowDown", keyCode: 40, bubbles: true})); method = "key"; }
            return out({status: "ok", token: hash.toString(16), method: method});
            """
        }
        return """
        (() => {
        const out = (o) => JSON.stringify(o);
        if (document.querySelector('input[type="password"], input[autocomplete="one-time-code"], input[autocomplete="current-password"]'))
          return out({status: "unsupported", reason: "signin"});
        const first = (list) => { for (const s of list) { try { const e = document.querySelector(s); if (e) return e; } catch (_) {} } return null; };
        const root = first(\(json(table.readyRoot)));
        if (!root) return out({status: "unsupported", reason: "layout"});
        \(body)
        })()
        """
    }

    private static func json(_ value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let text = String(data: data, encoding: .utf8) else { return "[]" }
        return text
    }
}

/// The parsed, bounded result of one script run. Anything unexpected is `unsupported`.
public enum WebMorningOutcome: Sendable, Equatable {
    case count(Int)
    case headlines([String])
    case scrolled(token: String, method: String)
    case unsupported(String)
    case refused(WebMorningRefusal)

    public static func parse(_ value: Any?, task: WebMorningTask) -> WebMorningOutcome {
        guard let text = value as? String, text.utf8.count <= 4_096, let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = object["status"] as? String else { return .unsupported("malformed") }
        guard status == "ok" else {
            let reason = object["reason"] as? String ?? ""
            return .unsupported(["signin", "layout"].contains(reason) ? reason : "malformed")
        }
        switch task {
        case .unreadCount:
            guard let count = object["count"] as? Int, (0...9_999).contains(count) else { return .unsupported("malformed") }
            return .count(count)
        case .headlines:
            guard let list = object["headlines"] as? [String], (1...5).contains(list.count),
                  list.allSatisfy({ !$0.isEmpty && $0.count <= 200 }) else { return .unsupported("malformed") }
            return .headlines(list)
        case .nextVideo:
            guard let token = object["token"] as? String, (1...8).contains(token.count),
                  token.allSatisfy(\.isHexDigit),
                  let method = object["method"] as? String, ["container", "window", "key"].contains(method)
            else { return .unsupported("malformed") }
            return .scrolled(token: token, method: method)
        }
    }

    /// One log line with no page content: counts and outcome names only, never text or URLs.
    public func logLine(site: WebMorningSite, task: WebMorningTask) -> String {
        let prefix = "WEBMORNING site=\(site.rawValue) task=\(task.rawValue)"
        switch self {
        case .count(let n): return "\(prefix) result=ok count=\(n)"
        case .headlines(let list): return "\(prefix) result=ok headlines=\(list.count)"
        case .scrolled(_, let method): return "\(prefix) result=ok method=\(method)"
        case .unsupported(let reason): return "\(prefix) result=unsupported reason=\(reason)"
        case .refused(let refusal): return "\(prefix) result=refused reason=\(refusal.rawValue)"
        }
    }
}

/// Counts real advances: a scroll counts once the next run sees a different video.
public struct WebMorningAdvanceTracker: Sendable, Equatable {
    public private(set) var attempts = 0
    public private(set) var advanced = 0
    private var lastToken: String?
    public init() {}
    public mutating func record(_ outcome: WebMorningOutcome) {
        guard case .scrolled(let token, _) = outcome else { return }
        if let lastToken, lastToken != token { advanced += 1 }
        lastToken = token
        attempts += 1
    }
}

/// The time a routine step gives the page. It only counts down; +2 min adds time.
public struct WebMorningStepClock: Sendable, Equatable {
    public static let extensionMinutes = 2
    public static let autoAdvanceSeconds = 3...60
    public private(set) var endsAt: Date
    public init(start: Date, minutes: Int) {
        endsAt = start.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }
    public func remaining(at now: Date) -> TimeInterval { max(0, endsAt.timeIntervalSince(now)) }
    public func isOver(at now: Date) -> Bool { remaining(at: now) == 0 }
    /// Adds two minutes to whatever is left, or to now when the time already ran out.
    public mutating func extend(at now: Date) {
        endsAt = max(endsAt, now).addingTimeInterval(TimeInterval(Self.extensionMinutes * 60))
    }
}
