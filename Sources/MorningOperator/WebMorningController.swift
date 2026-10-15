import Foundation
import MorningCore
import Observation
import OSLog
import WebKit

/// Owns the one web view of an in-app browser moment. Every script goes through
/// `WebMorningPolicy` first, runs in an isolated content world the page cannot reach,
/// and returns a bounded `WebMorningOutcome`. Logs carry outcome names and counts only.
@MainActor @Observable
final class WebMorningController: NSObject, WKNavigationDelegate {
    /// One persistent store for every site, so the person signs in once.
    /// Its folders are excluded from device backups (see `excludeWebDataFromBackup`).
    static let storeIdentifier = UUID(uuidString: "6D6F7265-7765-6262-726F-777365720001") ?? UUID()
    private static let log = Logger(subsystem: "com.gibouu.morningoperator", category: "WebMorning")
    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    let site: WebMorningSite
    @ObservationIgnored let webView: WKWebView
    private(set) var outcome: WebMorningOutcome?
    private(set) var tracker = WebMorningAdvanceTracker()
    private(set) var isAutoAdvancing = false
    private(set) var isRunning = false
    private(set) var isSignInPage = false
    private(set) var pageLoads = 0
    @ObservationIgnored private var autoTask: Task<Void, Never>?
    /// When the moment's time runs out. Auto-advance never moves after it.
    @ObservationIgnored var stepEndsAt = Date.distantPast

    init(site: WebMorningSite) {
        self.site = site
        Self.excludeWebDataFromBackup()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if site.table.usesDesktopUserAgent { webView.customUserAgent = Self.desktopUserAgent }
        super.init()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: site.table.startURL))
    }

    /// Runs one task now, after the policy allows it for the page on screen.
    @discardableResult
    func run(_ task: WebMorningTask) async -> WebMorningOutcome {
        let result = await evaluate(task)
        outcome = result
        if task == .nextVideo { tracker.record(result) }
        Self.record(result.logLine(site: site, task: task))
        return result
    }

    private func evaluate(_ task: WebMorningTask) async -> WebMorningOutcome {
        let page = webView.url
        if let refusal = WebMorningPolicy.refusal(for: task, on: site, at: page) {
            // Asking for the next video away from the feed opens the feed: a navigation, no script.
            if refusal == .notTheFeed, let feed = site.table.feedURL { webView.load(URLRequest(url: feed)) }
            return .refused(refusal)
        }
        guard !isSignInPage, let script = WebMorningPolicy.script(for: task, on: site) else { return .refused(.notOffered) }
        isRunning = true
        defer { isRunning = false }
        let value = try? await webView.evaluateJavaScript(script, contentWorld: .defaultClient)
        // A page that changed while the script ran gives no result.
        guard webView.url == page else { return .unsupported("layout") }
        return WebMorningOutcome.parse(value, task: task)
    }

    /// Moves to the next video every `seconds` until the moment's time runs out. The view
    /// also stops it when the moment ends, the screen goes away or the phone locks. The first
    /// move waits one interval, so the video on screen when the person turns it on plays first.
    func startAutoAdvance(every seconds: Int) {
        stopAutoAdvance()
        let interval = min(max(seconds, WebMorningStepClock.autoAdvanceSeconds.lowerBound),
                           WebMorningStepClock.autoAdvanceSeconds.upperBound)
        isAutoAdvancing = true
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard let self, !Task.isCancelled, Date() < self.stepEndsAt else { break }
                guard case .scrolled = await self.run(.nextVideo) else { break }
            }
            self?.isAutoAdvancing = false
            self?.autoTask = nil
        }
    }

    func stopAutoAdvance() {
        autoTask?.cancel()
        autoTask = nil
        isAutoAdvancing = false
    }

    func openFeed() {
        guard let feed = site.table.feedURL else { return }
        webView.load(URLRequest(url: feed))
    }

    /// Signs out of every site by clearing the shared store, then reloads the start page.
    func forgetSignIns() async {
        stopAutoAdvance()
        await webView.configuration.websiteDataStore.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        outcome = nil
        webView.load(URLRequest(url: site.table.startURL))
    }

    // MARK: Navigation

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { pageDidChange() }
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        MainActor.assumeIsolated { pageDidChange() }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        let code = (error as NSError).code
        MainActor.assumeIsolated { Self.record("WEBMORNING site=\(site.rawValue) load=failed code=\(code)") }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                             withError error: any Error) {
        let code = (error as NSError).code
        MainActor.assumeIsolated { Self.record("WEBMORNING site=\(site.rawValue) load=failed code=\(code)") }
    }

    private func pageDidChange() {
        let url = webView.url
        let host = url?.host?.lowercased() ?? "none"
        isSignInPage = WebMorningPolicy.isSignInPage(url) || !(site.table.allowedHosts.contains(host))
        if isSignInPage { stopAutoAdvance() }
        pageLoads += 1
        // The host is the only part of an address logged: paths and queries can carry an email.
        let kind = WebMorningPolicy.isSignInPage(url) ? "signin" : site.table.allowedHosts.contains(host) ? "site" : "other"
        Self.record("WEBMORNING site=\(site.rawValue) page=\(kind) host=\(host)")
    }

    private static func record(_ line: String) {
        log.info("\(line, privacy: .public)")
        #if DEBUG
        print(line)
        #endif
    }

    /// Sign-in cookies and site data must not travel in device or iCloud backups.
    /// WebKit keeps them under Library/WebKit and Library/Cookies; excluding a folder
    /// excludes everything in it, including files created later.
    static func excludeWebDataFromBackup() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for name in ["WebKit", "Cookies"] {
            var folder = library.appendingPathComponent(name, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? folder.setResourceValues(values)
        }
    }
}
