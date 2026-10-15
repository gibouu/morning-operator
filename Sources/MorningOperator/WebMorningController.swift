import Foundation
import MorningCore
import Observation
import OSLog
import WebKit

/// One visible browser. Each script needs one foreground user request. No injected
/// user scripts, message handlers, background readers or automatic page actions.
@MainActor @Observable
final class WebMorningController: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let storeIdentifier: UUID = {
        // Match the already validated, stable fixture workspace. A privacy UI test
        // must never clear the owner's real website sign-ins.
        let name = LocalDataControl.defaultDirectory.lastPathComponent
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           name.hasPrefix("MorningOperatorUITests-"),
           let id = UUID(uuidString: String(name.dropFirst("MorningOperatorUITests-".count))) {
            return id
        }
        return UUID(uuidString: "6D6F7265-7765-6262-726F-777365720001")!
    }()
    private static let log = Logger(subsystem: "com.gibouu.morningoperator", category: "WebMorning")
    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

    let site: WebMorningSite
    @ObservationIgnored let webView: WKWebView
    private(set) var outcome: WebMorningOutcome?
    private(set) var isRunning = false
    private(set) var isSignInPage = true
    private(set) var loadFailed = false
    private(set) var displayedHost = ""
    private(set) var isClearing = false
    /// The presenting view revokes this whenever it leaves the foreground.
    var actionsEnabled = false
    @ObservationIgnored private var pageGeneration = 0
    @ObservationIgnored private let privacyAtCreation: LocalDataControlState?
    @ObservationIgnored private let startURL: URL
    @ObservationIgnored private var hasStarted = false

    private var privacyIsCurrent: Bool {
        guard let created = privacyAtCreation, !created.forgetPending,
              let current = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !current.forgetPending, current.generation == created.generation else { return false }
        return true
    }

    init(site: WebMorningSite, initialURL: URL? = nil) {
        self.site = site
        startURL = initialURL.flatMap { WebMorningSite(url: $0) == site ? $0 : nil } ?? site.table.startURL
        privacyAtCreation = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status()
        Self.excludeWebDataFromBackup()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
        configuration.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if site.table.usesDesktopUserAgent { webView.customUserAgent = Self.desktopUserAgent }
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        displayedHost = startURL.host ?? ""
    }

    /// SwiftUI may construct and discard an initial State value while rendering.
    /// Only the retained, visible controller starts a network navigation.
    func startIfNeeded() {
        guard !hasStarted, privacyIsCurrent else { return }
        hasStarted = true
        webView.load(URLRequest(url: startURL))
    }

    @discardableResult
    func run(_ task: WebMorningTask) async -> WebMorningOutcome {
        guard privacyIsCurrent, actionsEnabled, !isRunning, !isClearing, !webView.isLoading else { return .refused(.notOffered) }
        let result = await evaluate(task)
        outcome = result
        Self.record(result.logLine(site: site, task: task))
        return result
    }

    private func evaluate(_ task: WebMorningTask) async -> WebMorningOutcome {
        let page = webView.url
        let generation = pageGeneration
        if let refusal = WebMorningPolicy.refusal(for: task, on: site, at: page) {
            // One tap may open the feed. It never also runs a script after navigation.
            if refusal == .notTheFeed, let feed = site.table.feedURL { webView.load(URLRequest(url: feed)) }
            return .refused(refusal)
        }
        guard !isSignInPage, let script = WebMorningPolicy.script(for: task, on: site) else { return .refused(.notOffered) }
        isRunning = true
        defer { isRunning = false }
        let value = try? await webView.evaluateJavaScript(script, contentWorld: .defaultClient)
        guard privacyIsCurrent, actionsEnabled, generation == pageGeneration, webView.url == page else { return .unsupported("layout") }
        return WebMorningOutcome.parse(value, task: task)
    }

    /// Clears every site's session in this app's dedicated WebKit store.
    static func clearAllSignIns() async {
        await WKWebsiteDataStore(forIdentifier: storeIdentifier).removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    func forgetSignIns() async {
        guard privacyIsCurrent, !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        actionsEnabled = false
        webView.stopLoading()
        pageGeneration += 1
        outcome = nil
        await Self.clearAllSignIns()
        guard privacyIsCurrent else { return }
        webView.load(URLRequest(url: site.table.startURL))
    }

    func reload() { if privacyIsCurrent { webView.reload() } }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Website links may navigate to a sign-in provider. MORE never runs scripts there.
        // Do not launch native social apps, custom schemes, insecure pages or downloads.
        guard privacyIsCurrent, let url = navigationAction.request.url, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil else { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame != false {
            pageGeneration += 1
            displayedHost = url.host ?? ""
            isSignInPage = true
            outcome = nil
            loadFailed = false
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Keep a user-opened link visible in the same browser, including sign-in pages.
        if privacyIsCurrent, navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.scheme?.lowercased() == "https", url.user == nil, url.password == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        displayedHost = webView.url?.host ?? ""
        isSignInPage = WebMorningPolicy.isSignInPage(webView.url) || WebMorningSite(url: webView.url ?? site.table.startURL) != site
        loadFailed = false
        let kind = isSignInPage ? "blocked" : "site"
        Self.record("WEBMORNING site=\(site.rawValue) page=\(kind)")
        Self.excludeWebDataFromBackup()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { failed(error) }

    private func failed(_ error: any Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        loadFailed = true
        isSignInPage = true
        Self.record("WEBMORNING site=\(site.rawValue) load=failed code=\(code)")
    }

    private static func record(_ line: String) {
        log.info("\(line, privacy: .public)")
        #if DEBUG
        print(line)
        #endif
    }

    /// Best-effort exclusion for WebKit's app-library folders. WebKit owns its storage
    /// layout; device backup/restore still needs a real check before claiming exclusion.
    private static func excludeWebDataFromBackup() {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        for name in ["WebKit", "Cookies"] {
            var folder = library.appendingPathComponent(name, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try folder.setResourceValues(values)
            } catch { record("WEBMORNING backupExclusion=unverified") }
        }
    }
}
