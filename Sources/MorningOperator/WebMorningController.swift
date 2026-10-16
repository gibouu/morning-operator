import Foundation
import CoreFoundation
import MorningCore
import MorningApple
import Observation
import OSLog
import UIKit
import WebKit

/// One visible browser. A reviewed routine can drive bounded page actions while
/// foregrounded; learning remains a separate, explicitly enabled operation.
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
    private(set) var newsSnapshot: WebNewsSnapshot?
    private(set) var articleText: WebArticleText?
    private(set) var articleMessage: String?
    private(set) var articleRefusal: WebArticleRefusal?
    private(set) var pageAccessRefusal: WebPageAccessRefusal?
    private(set) var articleBusy = false
    var needsArticleReturn: Bool { articleReturnPoint != nil }
    @ObservationIgnored private let routineContext: MorningVoiceCommandContext?
    @ObservationIgnored private var articleReturnPoint: (item: WKBackForwardListItem, offset: CGPoint)?
    @ObservationIgnored private var articleOperation: UUID?
    @ObservationIgnored private var articleExpectedDestination: URL?
    @ObservationIgnored private var articleResponse: (url: URL, status: Int)?
    @ObservationIgnored private var articleLocalResponse: URL?
    @ObservationIgnored private let syntheticNews: SyntheticNewsOrigin?
    @ObservationIgnored private let syntheticNewsRequested: Bool
    #if DEBUG
    @ObservationIgnored private let syntheticNewsHandler: SyntheticNewsSchemeHandler?
    @ObservationIgnored private var syntheticNewsSnapshotObservation = ""
    private(set) var syntheticNewsRepeatCompletions = 0
    #endif
    var sourceLabel: String { syntheticNews == nil ? site.displayName : "SYNTHETIC Cedar News" }
    var isSyntheticNews: Bool { syntheticNews != nil }
    var syntheticNewsPageGeneration: Int? { syntheticNews == nil ? nil : pageGeneration }
    var syntheticNewsDiagnostic: String {
        guard syntheticNews != nil, let context = routineContext else { return "" }
        #if DEBUG
        return "syntheticNews=1 newsContext=\(context.sessionID)|\(context.routineVersionID)|\(context.stepID) resource=\(webView.url?.path ?? "none") articleParagraphs=\(articleText?.paragraphs.count ?? 0) localLoads=\(syntheticNewsHandler?.deliveryCount ?? 0) newsRepeatCompleted=\(syntheticNewsRepeatCompletions) retainedLinks=\(newsSnapshot?.links.count ?? 0) \(syntheticNewsSnapshotObservation)"
        #else
        return ""
        #endif
    }

    /// Observation only, called after the ordinary async Repeat callback returns.
    /// It certifies neither audible speech nor a successful TTS completion.
    func noteSyntheticNewsRepeatCompletion(context: MorningVoiceCommandContext, privacy: UUID, pageGeneration: Int?) {
        #if DEBUG
        guard syntheticNews != nil, let pageGeneration, pageGeneration == self.pageGeneration,
              routineContext == context, isCurrentPrivacy(runtimeGeneration: privacy),
              needsArticleReturn, articleText != nil, !articleBusy,
              UIApplication.shared.applicationState == .active else { return }
        syntheticNewsRepeatCompletions += 1
        #endif
    }
    /// The presenting view revokes this whenever it leaves the foreground.
    var actionsEnabled = false {
        didSet {
            let enabled = actionsEnabled && !isRetired
            // Retaining a hidden page must not leave its media playing. WebKit
            // suspends playback without inspecting page content or form fields.
            let suspended = !enabled
            if mediaPlaybackSuspended != suspended {
                mediaPlaybackSuspended = suspended
                webView.setAllMediaPlaybackSuspended(suspended, completionHandler: nil)
            }
            if enabled { resumeExecutionIfNeeded() } else { suspendExecution() }
        }
    }
    var learningAllowed = false {
        didSet { if !learningAllowed { stopLearning() } }
    }
    private(set) var isLearning = false
    private(set) var isFinishingLearning = false
    private(set) var learningSummary: BrowserRhythmSummary?
    @ObservationIgnored private var rhythm: BrowserRhythmAccumulator?
    @ObservationIgnored private var learningNonce: UUID?
    @ObservationIgnored private var learningReviewNonce: UUID?
    @ObservationIgnored private var learningStarted = 0.0
    @ObservationIgnored private var learningGeneration = 0
    @ObservationIgnored private var rhythmHandler: BrowserRhythmMessageHandler?
    @ObservationIgnored private var learningMonitor: Task<Void, Never>?
    private static let rhythmWorld = WKContentWorld.world(name: "MOREBrowserRhythm")
    var canLearn: Bool {
        privacyIsCurrent && !syntheticNewsRequested && learningAllowed && UIApplication.shared.applicationState == .active &&
            !isSignInPage && !loadFailed && !isClearing && !isRunning && !isFinishingLearning && !webView.isLoading &&
            BrowserRhythmPolicy.permits(site: site, url: webView.url)
    }
    private(set) var executionEvent: WebMorningExecutionEvent?
    private(set) var executionDiagnostic = ""
    @ObservationIgnored var onExecutionEvent: ((WebMorningExecutionEvent) -> Void)?
    @ObservationIgnored var executionIsAuthorized: (() -> Bool)?
    @ObservationIgnored var executionCanAdvance: (() -> Bool)?
    @ObservationIgnored private var executionPlan: WebMorningExecutionPlan?
    @ObservationIgnored private var executionHistoryPlan: WebMorningExecutionPlan?
    @ObservationIgnored private var executionDeadline: Date?
    @ObservationIgnored private var executionTask: Task<Void, Never>?
    @ObservationIgnored private var executionNonce: UUID?
    @ObservationIgnored private var contentProgress = WebMorningContentProgress()
    @ObservationIgnored private var observedContentCount = 0
    @ObservationIgnored private var confirmedLikeCount = 0
    @ObservationIgnored private var lastSpokenFingerprint: String?
    @ObservationIgnored private var executionFinished = false
    @ObservationIgnored private var actionPending = false
    @ObservationIgnored private var pageGeneration = 0
    @ObservationIgnored private let privacyBinding: WebReadingPrivacyBinding?
    @ObservationIgnored private let startURL: URL
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var executionContextText: [String] = []
    @ObservationIgnored private var isRetired = false
    @ObservationIgnored private var mediaPlaybackSuspended = false
    @ObservationIgnored private var instagramNavigation = InstagramBrowserNavigation()

    var savedContentProgressIsAvailable: Bool { contentProgress.isAvailable }

    private var privacyIsCurrent: Bool {
        isCurrentPrivacy()
    }

    private func isCurrentPrivacy(runtimeGeneration: UUID? = nil) -> Bool {
        !isRetired && privacyBinding?.isCurrent(
            state: try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
            runtimeGeneration: runtimeGeneration) == true
    }

    init(site: WebMorningSite, initialURL: URL? = nil, routineContext: MorningVoiceCommandContext? = nil,
         runtimePrivacyGeneration: UUID? = nil) {
        self.site = site
        self.routineContext = routineContext
        #if DEBUG
        syntheticNewsRequested = site == .news && ProcessInfo.processInfo.arguments.contains("--ui-testing-private-news")
        let source = site == .news && routineContext != nil ? SyntheticNewsOrigin.requested(
            arguments: ProcessInfo.processInfo.arguments, directory: LocalDataControl.defaultDirectory) : nil
        syntheticNewsHandler = source.map { SyntheticNewsSchemeHandler(origin: $0, french: AppLanguage.isFrench) }
        #else
        syntheticNewsRequested = false
        let source: SyntheticNewsOrigin? = nil
        #endif
        syntheticNews = source
        startURL = source?.startURL ?? initialURL.flatMap { WebMorningSite(url: $0) == site ? $0 : nil } ?? site.table.startURL
        privacyBinding = WebReadingPrivacyBinding(runtimeGeneration: runtimePrivacyGeneration,
            stateAtCreation: try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status())
        Self.excludeWebDataFromBackup()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = syntheticNewsRequested ? .nonPersistent() : WKWebsiteDataStore(forIdentifier: Self.storeIdentifier)
        #if DEBUG
        if let syntheticNewsHandler { configuration.setURLSchemeHandler(syntheticNewsHandler, forURLScheme: SyntheticNewsOrigin.scheme) }
        #endif
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        if site == .instagram { webView.allowsLinkPreview = false }
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
        guard !syntheticNewsRequested || syntheticNews != nil else {
            loadFailed = true
            articleMessage = "SYNTHETIC news input refused. No network page was opened."
            return
        }
        let destination = startURL == site.table.startURL ? (executionPlan.flatMap { WebMorningExecutionPolicy.entryURL(site: site, behavior: $0.behavior) } ?? startURL) : startURL
        webView.load(URLRequest(url: destination))
    }

    private func articleAccess(context: MorningVoiceCommandContext, privacy: UUID, allowFailed: Bool = false, authorized: @MainActor () -> Bool) -> Bool {
        isCurrentPrivacy(runtimeGeneration: privacy) && site == .news && routineContext == context &&
            UIApplication.shared.applicationState == .active && !isClearing && (allowFailed || !loadFailed) && authorized() &&
            ((try? WebMorningLikeJournal(directory: LocalDataControl.defaultDirectory).unresolvedKeys().isEmpty) == true)
    }

    func retainedNewsArticle(context: MorningVoiceCommandContext, privacy: UUID,
        authorized: @MainActor () -> Bool) -> WebArticleText? {
        guard articleAccess(context: context, privacy: privacy, authorized: authorized),
              needsArticleReturn, !articleBusy else { return nil }
        return articleText
    }

    /// Close purges private text. A paused reopen observes the displayed list
    /// again without restarting execution, narration, actions or its old budget.
    func restoreDisplayedNewsChoices(context: MorningVoiceCommandContext, privacy: UUID,
        authorized: @MainActor () -> Bool) async {
        func current() -> Bool {
            !Task.isCancelled && articleAccess(context: context, privacy: privacy, authorized: authorized) &&
                !isLearning && !needsArticleReturn && !articleBusy && newsSnapshot == nil
        }
        func displayed() -> Bool {
            executionPlan?.behavior == .readHeadlines && !actionsEnabled &&
                webView.window != nil && !webView.isLoading
        }
        // SwiftUI can start its task before the retained WKView is attached or
        // its onAppear has applied the paused plan. No navigation is requested.
        for _ in 0..<20 {
            guard current() else { return }
            if displayed() { break }
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard current(), displayed(), let page = webView.url,
              WebMorningExecutionPolicy.permits(site: site, url: page, syntheticNews: syntheticNews) else { return }
        let generation = pageGeneration
        let value = try? await webView.evaluateJavaScript(
            WebMorningExecutionPolicy.script(site: .news, behavior: .readHeadlines, syntheticNews: syntheticNews),
            contentWorld: .defaultClient)
        guard current(), displayed(), generation == pageGeneration, page == webView.url,
              let observation = WebMorningPageObservation.parse(value), observation.status == .ready else { return }
        retainNewsSnapshot(observation)
    }

    private func retainNewsSnapshot(_ observation: WebMorningPageObservation) {
        #if DEBUG
        defer { recordSyntheticNewsSnapshotObservation(observation) }
        #endif
        guard site == .news, let context = routineContext, let privacy = privacyBinding?.runtimeGeneration,
              isCurrentPrivacy(runtimeGeneration: privacy),
              let page = webView.url, let fingerprint = observation.fingerprint, let links = observation.articles else {
            newsSnapshot = nil; return
        }
        newsSnapshot = WebNewsSnapshot(context: context, privacyGeneration: privacy, pageGeneration: pageGeneration,
            pageURL: page, fingerprint: fingerprint, links: links, syntheticNews: syntheticNews)
        if !needsArticleReturn && !articleBusy { articleMessage = nil; articleRefusal = nil }
    }

    #if DEBUG
    /// Last builder result plus live retainedLinks distinguishes admission from
    /// later lifecycle clearing. Counts/codes only; no additional DOM query.
    private func recordSyntheticNewsSnapshotObservation(_ observation: WebMorningPageObservation) {
        guard let syntheticNews else { return }
        let articles = observation.articles, page = webView.url
        let admitted = articles?.filter { link in
            page.map { WebArticlePolicy.permits(link.href, from: $0, syntheticNews: syntheticNews) } == true
        }.count ?? 0
        let unique = articles.map { Set($0.map(\.href)).count } ?? 0
        let result: String
        if articles == nil { result = "missingArticles" }
        else if articles?.isEmpty == true { result = "emptyArticles" }
        else { result = newsSnapshot == nil ? "invalidSnapshot" : "retained" }
        syntheticNewsSnapshotObservation = "articlesParsed=\(articles?.count ?? -1) articlesAdmitted=\(admitted) articlesUnique=\(unique) snapshotContext=\(routineContext == nil ? 0 : 1) snapshotPrivacy=\(privacyBinding?.runtimeGeneration == nil ? 0 : 1) snapshotPage=\(page == nil ? 0 : 1) snapshotFingerprint=\(observation.fingerprint == nil ? 0 : 1) snapshotPageAllowed=\(page.map { WebArticlePolicy.isPage($0, syntheticNews: syntheticNews) } == true ? 1 : 0) lastSnapshotResult=\(result)"
    }
    #endif

    func cancelArticleWork() {
        articleRefusal = nil
        articleOperation = nil; articleBusy = false; articleText = nil
        articleExpectedDestination = nil; articleResponse = nil; articleLocalResponse = nil
        if needsArticleReturn { articleMessage = AppLanguage.isFrench ? "Lecture interrompue. Dites retour aux titres ou reprends."
            : "Reading interrupted. Say back to headlines or resume." }
    }

    private func refuseArticle(_ reason: WebArticleRefusal, cancelOperation: Bool = false) {
        articleRefusal = reason; articleText = nil
        articleMessage = reason.message(french: AppLanguage.isFrench)
        if cancelOperation { articleOperation = nil; articleBusy = false }
    }

    /// Selection and the immediate recheck use the observed DOM; a transcript
    /// never supplies a URL. The same WKWebView retains sign-in and list history.
    func openNewsArticle(ordinal: Int, context: MorningVoiceCommandContext, privacy: UUID,
        authorized: @MainActor () -> Bool) async -> WebArticleText? {
        guard articleAccess(context: context, privacy: privacy, authorized: authorized) else { return nil }
        if needsArticleReturn || articleBusy {
            articleMessage = AppLanguage.isFrench ? "Dites retour aux titres avant de choisir un autre article."
                : "Say back to headlines before choosing another article."
            return nil
        }
        guard webView.window != nil, !webView.isLoading, let snapshot = newsSnapshot,
              snapshot.matches(context: context, privacyGeneration: privacy, pageGeneration: pageGeneration, pageURL: webView.url),
              let listItem = webView.backForwardList.currentItem else {
            refuseArticle(.stale); return nil
        }
        guard let selected = snapshot.select(ordinal) else { refuseArticle(.selectionUnavailable); return nil }
        let operation = UUID(); articleOperation = operation; articleBusy = true; articleRefusal = nil
        defer { if articleOperation == operation { articleBusy = false; articleOperation = nil } }
        let value = try? await webView.evaluateJavaScript(WebMorningExecutionPolicy.script(site: .news, behavior: .readHeadlines, syntheticNews: syntheticNews), contentWorld: .defaultClient)
        guard articleOperation == operation, articleAccess(context: context, privacy: privacy, authorized: authorized) else { return nil }
        guard snapshot.matches(context: context, privacyGeneration: privacy, pageGeneration: pageGeneration, pageURL: webView.url) else {
            newsSnapshot = nil; refuseArticle(.stale); return nil
        }
        guard let current = WebMorningPageObservation.parse(value) else { refuseArticle(.invalidScriptResult); return nil }
        guard snapshot.matchesObservation(current) else {
            newsSnapshot = nil; refuseArticle(.stale); return nil
        }
        articleReturnPoint = (listItem, webView.scrollView.contentOffset)
        articleExpectedDestination = selected.href; articleResponse = nil; articleLocalResponse = nil
        articleText = nil; articleMessage = AppLanguage.isFrench ? "Ouverture de l’article observé…" : "Opening the observed article…"
        webView.load(URLRequest(url: selected.href))
        guard await waitForArticleNavigation(operation, context: context, privacy: privacy, authorized: authorized,
            destination: selected.href, requireResponse: true), let page = webView.url,
            articleResponsePermits(selected: selected.href),
            WebArticlePolicy.matchesDestination(page, selected: selected.href, syntheticNews: syntheticNews) else { return nil }
        let generation = pageGeneration
        let body = try? await webView.evaluateJavaScript(WebArticleScript.body(pageURL: page, expiresAt: Date().addingTimeInterval(2)), contentWorld: .defaultClient)
        guard articleOperation == operation, articleAccess(context: context, privacy: privacy, authorized: authorized) else { return nil }
        guard generation == pageGeneration, webView.url == page else { refuseArticle(.stale); return nil }
        guard articleResponsePermits(selected: selected.href) else {
            refuseArticle(.unexpectedDestination); return nil
        }
        switch WebArticleReadResult.parse(body) {
        case .refused(let reason): refuseArticle(reason); return nil
        case .content(let text):
            articleRefusal = nil; articleText = text
            articleMessage = AppLanguage.isFrench ? "Article ouvert dans MORE. Le matin reste en pause."
                : "Article opened in MORE. Your morning remains paused."
            return text
        }
    }

    private func waitForArticleNavigation(_ operation: UUID, context: MorningVoiceCommandContext, privacy: UUID,
        authorized: @MainActor () -> Bool, destination: URL?, requireResponse: Bool = false) async -> Bool {
        for _ in 0..<40 {
            guard articleOperation == operation, articleAccess(context: context, privacy: privacy, allowFailed: destination != nil, authorized: authorized) else { return false }
            if !loadFailed, !webView.isLoading, let page = webView.url,
               destination.map({ WebArticlePolicy.matchesDestination(page, selected: $0, syntheticNews: syntheticNews) }) ?? (page != articleReturnPoint?.item.url), WebArticlePolicy.isPage(page, syntheticNews: syntheticNews) {
                if !requireResponse { return true }
                if let destination, articleResponsePermits(selected: destination) { return true }
            }
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return false }
        }
        guard articleOperation == operation, articleAccess(context: context, privacy: privacy, allowFailed: true, authorized: authorized) else { return false }
        refuseArticle(.navigationTimeout)
        return false
    }

    func returnToNewsList(context: MorningVoiceCommandContext, privacy: UUID,
        authorized: @MainActor () -> Bool) async -> Bool {
        guard articleAccess(context: context, privacy: privacy, allowFailed: true, authorized: authorized) else { return false }
        guard let point = articleReturnPoint else { return !articleBusy }
        let operation = UUID(); articleOperation = operation; articleBusy = true; articleText = nil; newsSnapshot = nil
        articleExpectedDestination = point.item.url; articleResponse = nil; articleLocalResponse = nil; articleRefusal = nil
        defer { if articleOperation == operation { articleBusy = false; articleOperation = nil } }
        webView.stopLoading()
        if webView.backForwardList.currentItem === point.item, webView.url != point.item.url || loadFailed {
            webView.load(URLRequest(url: point.item.url))
            guard await waitForArticleNavigation(operation, context: context, privacy: privacy,
                authorized: authorized, destination: point.item.url) else { return false }
        } else if webView.backForwardList.currentItem !== point.item {
            guard webView.backForwardList.backList.contains(where: { $0 === point.item }) else {
                articleMessage = AppLanguage.isFrench ? "La liste précédente ne peut pas être rétablie. Rechargez la page ou dites suivant."
                    : "The previous list cannot be restored. Reload the page or say next."
                return false
            }
            webView.go(to: point.item)
            guard await waitForArticleNavigation(operation, context: context, privacy: privacy,
                authorized: authorized, destination: point.item.url) else { return false }
        }
        guard articleOperation == operation, articleAccess(context: context, privacy: privacy, authorized: authorized),
              webView.url == point.item.url else { return false }
        webView.scrollView.setContentOffset(point.offset, animated: false)
        articleReturnPoint = nil
        articleExpectedDestination = nil; articleResponse = nil; articleLocalResponse = nil
        articleMessage = AppLanguage.isFrench ? "Retour aux titres. Le temps restant est conservé. Dites reprends pour continuer."
            : "Back at the headlines. Your remaining time is preserved. Say resume to continue."
        let generation = pageGeneration, page = webView.url
        let value = try? await webView.evaluateJavaScript(WebMorningExecutionPolicy.script(site: .news, behavior: .readHeadlines, syntheticNews: syntheticNews), contentWorld: .defaultClient)
        guard articleOperation == operation, articleAccess(context: context, privacy: privacy, authorized: authorized),
              generation == pageGeneration, page == webView.url else { return false }
        if let observation = WebMorningPageObservation.parse(value), observation.status == .ready { retainNewsSnapshot(observation) }
        return true
    }

    private func articleResponsePermits(selected: URL) -> Bool {
        if let syntheticNews {
            #if DEBUG
            return articleLocalResponse == selected && syntheticNews.permits(selected) && syntheticNewsHandler?.deliveredHTML.contains(selected) == true
            #else
            return false
            #endif
        }
        guard let response = articleResponse else { return false }
        return WebArticlePolicy.permitsResponse(selected: selected, observed: response.url, status: response.status)
    }

    @discardableResult
    func run(_ task: WebMorningTask) async -> WebMorningOutcome {
        guard privacyIsCurrent, actionsEnabled, UIApplication.shared.applicationState == .active,
              !loadFailed, !isLearning, !isRunning, !isClearing, !webView.isLoading else { return .refused(.notOffered) }
        let generation = pageGeneration
        let page = webView.url
        let privacyEpoch = privacyBinding?.persistedGeneration
        let result = await evaluate(task)
        // A navigation, opt-out or privacy reset may have happened during the
        // WebKit await. Return to the original caller without publishing its
        // result into the replacement page or writing a stale action log.
        guard let privacy = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !privacy.forgetPending, privacy.generation == privacyEpoch, actionsEnabled,
              UIApplication.shared.applicationState == .active,
              !loadFailed, generation == pageGeneration, page == webView.url else { return result }
        outcome = result
        Self.record(result.logLine(site: site, task: task))
        return result
    }

    @discardableResult func startLearning() async -> Bool {
        guard canLearn, !isLearning, executionPlan == nil else { return false }
        let nonce = UUID()
        learningNonce = nonce; learningGeneration = pageGeneration
        learningReviewNonce = nil
        learningStarted = ProcessInfo.processInfo.systemUptime
        rhythm = BrowserRhythmAccumulator(site: site)
        learningSummary = nil
        isLearning = true
        let handler = BrowserRhythmMessageHandler(owner: self)
        rhythmHandler = handler
        webView.configuration.userContentController.add(handler, contentWorld: Self.rhythmWorld, name: "moreRhythm")
        let installed = try? await webView.evaluateJavaScript(BrowserRhythmPolicy.script(site: site, nonce: nonce), contentWorld: Self.rhythmWorld)
        guard learningNonce == nonce, isLearning, canLearn, installed as? Bool == true else {
            if learningNonce == nonce { stopLearning() }
            return false
        }
        learningMonitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self, self.learningNonce == nonce else { return }
                guard self.privacyIsCurrent else { self.discardLearning(); return }
                if !self.learningAllowed || UIApplication.shared.applicationState != .active ||
                    ProcessInfo.processInfo.systemUptime - self.learningStarted >= 900 {
                    self.stopLearning(); return
                }
            }
        }
        return true
    }

    /// Revoke native acceptance synchronously; remove passive DOM listeners in
    /// their isolated world. No listener is installed automatically on a new page.
    func stopLearning() {
        guard let nonce = learningNonce else { return }
        learningMonitor?.cancel(); learningMonitor = nil
        learningNonce = nil; isLearning = false
        learningReviewNonce = nonce
        isFinishingLearning = true
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "moreRhythm", contentWorld: Self.rhythmWorld)
        rhythmHandler = nil
        let elapsed = ProcessInfo.processInfo.systemUptime - learningStarted
        let finished = rhythm
        if privacyIsCurrent, let rhythm {
            learningSummary = rhythm.summary(durationSeconds: elapsed)
        } else { learningSummary = nil }
        rhythm = nil
        let source = "globalThis.__moreRhythm?.stop('\(nonce.uuidString)')"
        Task { [weak self] in
            guard let self else { return }
            defer { if self.learningReviewNonce == nonce { self.isFinishingLearning = false } }
            let final = try? await self.webView.evaluateJavaScript(source, contentWorld: Self.rhythmWorld)
            let finalElapsed = max(elapsed, ProcessInfo.processInfo.systemUptime - self.learningStarted)
            guard self.learningReviewNonce == nonce, self.privacyIsCurrent,
                  let body = final as? [String: Any],
                  Set(body.keys) == Set(["distance", "movingSeconds", "scrollBursts", "clicks", "segments"]),
                  let snapshot = Self.rhythmSnapshot(body, behavior: BrowserRhythmPolicy.behavior(site: self.site, url: self.webView.url), elapsed: finalElapsed),
                  var finished else { return }
            if finished.update(snapshot.totals, segments: snapshot.segments) {
                self.learningSummary = finished.summary(durationSeconds: finalElapsed)
            }
        }
    }

    func discardLearning() {
        stopLearning()
        learningReviewNonce = nil
        isFinishingLearning = false
        learningSummary = nil
    }

    fileprivate func receiveRhythm(_ message: WKScriptMessage) {
        guard privacyIsCurrent else { discardLearning(); return }
        guard isLearning, learningAllowed, privacyIsCurrent,
              UIApplication.shared.applicationState == .active,
              message.webView === webView, message.frameInfo.isMainFrame,
              message.frameInfo.securityOrigin.protocol == "https",
              site.table.allowedHosts.contains(message.frameInfo.securityOrigin.host.lowercased()),
              message.frameInfo.securityOrigin.port == 0 || message.frameInfo.securityOrigin.port == 443,
              learningGeneration == pageGeneration,
              let body = message.body as? [String: Any],
              let nonce = learningNonce, body["nonce"] as? String == nonce.uuidString else { return }
        if body.count == 2, body["blocked"] as? Bool == true { stopLearning(); return }
        guard BrowserRhythmPolicy.permits(site: site, url: webView.url),
              Set(body.keys) == Set(["nonce", "distance", "movingSeconds", "scrollBursts", "clicks", "segments"]),
              let snapshot = Self.rhythmSnapshot(body, behavior: BrowserRhythmPolicy.behavior(site: site, url: webView.url),
                  elapsed: ProcessInfo.processInfo.systemUptime - learningStarted),
              var rhythm else { return }
        guard rhythm.update(snapshot.totals, segments: snapshot.segments) else { return }
        self.rhythm = rhythm
        if ProcessInfo.processInfo.systemUptime - learningStarted >= 900 { stopLearning() }
    }

    private static func rhythmSnapshot(_ body: [String: Any], behavior: WebMorningBehavior?, elapsed: Double)
        -> (totals: BrowserRhythmTotals, segments: [BrowserLearningSegment])? {
        func number(_ value: Any?) -> Double? {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return number.doubleValue
        }
        func integer(_ value: Any?) -> Int? {
            guard let number = number(value), number.isFinite, number >= 0, number <= 100_000,
                  number.rounded(.towardZero) == number else { return nil }
            return Int(number)
        }
        guard let distance = number(body["distance"]), let seconds = number(body["movingSeconds"]),
              let bursts = integer(body["scrollBursts"]), let clicks = integer(body["clicks"]),
              let totals = BrowserRhythmTotals(distance: distance, movingSeconds: seconds, scrollBursts: bursts, clicks: clicks),
              let rawSegments = body["segments"] as? [[String: Any]], rawSegments.count <= 16 else { return nil }
        var segments: [BrowserLearningSegment] = []
        for raw in rawSegments {
            guard Set(raw.keys) == Set(["behavior", "startSeconds", "endSeconds", "gestures"]),
                  let name = raw["behavior"] as? String, let routeBehavior = WebMorningBehavior(rawValue: name),
                  let start = number(raw["startSeconds"]), let end = number(raw["endSeconds"]),
                  end <= min(900, elapsed + 1), let gestures = integer(raw["gestures"]),
                  let segment = BrowserLearningSegment(behavior: routeBehavior, startSeconds: start, endSeconds: end, gestures: gestures) else { return nil }
            segments.append(segment)
        }
        guard segments.isEmpty || segments.last?.behavior == behavior else { return nil }
        return (totals, segments)
    }

    private func evaluate(_ task: WebMorningTask) async -> WebMorningOutcome {
        guard !loadFailed else { return .refused(.notOffered) }
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
        guard privacyIsCurrent, actionsEnabled, !loadFailed,
              UIApplication.shared.applicationState == .active,
              generation == pageGeneration, webView.url == page else { return .unsupported("layout") }
        return WebMorningOutcome.parse(value, task: task)
    }

    /// The presenter supplies only the behavior from its approved session snapshot.
    /// Changing a deadline never creates a second worker or resets observed results.
    func configureExecution(plan: WebMorningExecutionPlan?, endsAt: Date?) {
        guard !isRetired else { return }
        guard let plan else { stopExecution(); executionPlan = nil; return }
        let changed = executionHistoryPlan?.sessionID != plan.sessionID || executionHistoryPlan?.stepID != plan.stepID ||
            executionHistoryPlan?.behavior != plan.behavior || executionHistoryPlan?.likesAllowed != plan.likesAllowed
        if changed {
            stopExecution()
            contentProgress = plan.initialContentProgress; observedContentCount = contentProgress.observedCount
            confirmedLikeCount = plan.initialConfirmedLikeCount; lastSpokenFingerprint = nil
            executionFinished = false; actionPending = false
            executionContextText = []
        }
        executionPlan = plan
        executionHistoryPlan = plan
        executionDeadline = endsAt
        resumeExecutionIfNeeded()
    }

    /// Closing a retained routine page suspends its worker without discarding the
    /// live page, viewport, spoken-content identity or observed-content set.
    func suspendPresentation() {
        pageAccessRefusal = nil
        newsSnapshot = nil; articleText = nil; cancelArticleWork()
        actionsEnabled = false
        learningAllowed = false
        onExecutionEvent = nil
        executionIsAuthorized = nil
        executionCanAdvance = nil
    }

    /// Clear private snapshot text on backgrounding, preserving content-free
    /// deduplication keys and the actual browser position for a coherent resume.
    func discardSourceContext() {
        newsSnapshot = nil; articleText = nil; cancelArticleWork()
        actionsEnabled = false
        clearSourceText()
    }

    private func clearSourceText() {
        pageAccessRefusal = nil
        newsSnapshot = nil; articleText = nil
        articleResponse = nil; articleLocalResponse = nil
        executionContextText = []
        outcome = nil
        if let plan = executionPlan, let event = executionEvent {
            let cleared = WebMorningExecutionEvent(plan: plan, state: event.state,
                observedContentCount: observedContentCount, confirmedLikeCount: confirmedLikeCount,
                contentProgress: contentProgress)
            if cleared != event {
                executionEvent = cleared
                onExecutionEvent?(cleared)
            }
        }
    }

    /// Revokes every callback before releasing a retired moment. A disappearing
    /// SwiftUI view cannot reactivate this old controller after the store moves on.
    func retire() {
        guard !isRetired else { return }
        isRetired = true
        onExecutionEvent = nil; executionIsAuthorized = nil; executionCanAdvance = nil
        actionsEnabled = false; learningAllowed = false
        discardLearning(); stopExecution()
        executionPlan = nil; executionHistoryPlan = nil; executionContextText = []
        executionEvent = nil; outcome = nil; contentProgress = .init()
        articleOperation = nil; articleBusy = false; articleReturnPoint = nil; articleText = nil; newsSnapshot = nil; articleMessage = nil; articleRefusal = nil
        articleExpectedDestination = nil; articleResponse = nil; articleLocalResponse = nil; pageAccessRefusal = nil
        lastSpokenFingerprint = nil
        webView.stopLoading()
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func stopExecution() {
        executionTask?.cancel(); executionTask = nil; executionNonce = nil
        if executionPlan != nil, !executionFinished, executionEvent?.state != .needsChoice { publishExecution(.cancelled) }
    }

    private func suspendExecution() {
        guard executionTask != nil else { return }
        executionTask?.cancel(); executionTask = nil; executionNonce = nil
        if executionEvent?.state != .needsChoice { publishExecution(.paused) }
    }

    private func resumeExecutionIfNeeded() {
        guard let plan = executionPlan, actionsEnabled, !isClearing, !isLearning,
              !executionFinished, executionTask == nil, privacyIsCurrent, !articleBusy, !needsArticleReturn else { return }
        if executionEvent?.state == .needsChoice { executionEvent = nil; pageAccessRefusal = nil }
        let nonce = UUID(); executionNonce = nonce
        executionTask = Task { [weak self] in
            guard let self else { return }
            await self.execute(plan, nonce: nonce)
            if self.executionNonce == nonce { self.executionTask = nil; self.executionNonce = nil }
        }
    }

    private func executionIsCurrent(_ nonce: UUID) -> Bool {
        !Task.isCancelled && executionNonce == nonce && actionsEnabled && privacyIsCurrent &&
            !isLearning && !isClearing && UIApplication.shared.applicationState == .active &&
            (executionIsAuthorized?() ?? true)
    }

    private func publishExecution(_ state: WebMorningExecutionState, text: [String] = []) {
        guard let plan = executionPlan else { return }
        let hasPending = actionPending || ((try? WebMorningLikeJournal(directory: LocalDataControl.defaultDirectory)
            .unresolvedKeys(sessionID: plan.sessionID, stepID: plan.stepID).isEmpty) == false)
        let safeState: WebMorningExecutionState = hasPending && state != .performingAction ? .uncertainAction : state
        let event = WebMorningExecutionEvent(plan: plan, state: safeState, observedContentCount: observedContentCount,
                                            confirmedLikeCount: confirmedLikeCount, spokenText: text, contextText: executionContextText,
                                            contentProgress: contentProgress)
        if executionEvent != event { executionEvent = event; onExecutionEvent?(event) }
    }

    private func executionWait(_ seconds: TimeInterval, nonce: UUID) async -> Bool {
        do { try await Task.sleep(for: .seconds(seconds)) } catch { return false }
        return executionIsCurrent(nonce)
    }

    private func executionObserve(_ plan: WebMorningExecutionPlan, nonce: UUID) async -> WebMorningPageObservation? {
        guard executionIsCurrent(nonce), !loadFailed, !webView.isLoading,
              WebMorningExecutionPolicy.permits(site: site, url: webView.url, syntheticNews: syntheticNews) else { return nil }
        let generation = pageGeneration, page = webView.url
        let script = WebMorningExecutionPolicy.script(site: site, behavior: plan.behavior, syntheticNews: syntheticNews)
        let started = ProcessInfo.processInfo.systemUptime
        do {
            let value = try await webView.evaluateJavaScript(script, contentWorld: .defaultClient)
            guard executionIsCurrent(nonce), generation == pageGeneration, page == webView.url else { return nil }
            let observation = WebMorningPageObservation.parse(value)
            let milliseconds = Int((ProcessInfo.processInfo.systemUptime - started) * 1_000)
            executionDiagnostic = "status=\(observation?.status.rawValue ?? "invalid") reason=\(observation?.reason ?? "none") evalMs=\(milliseconds) attached=\(webView.window != nil)"
            Self.record("WEBMORNING site=\(site.rawValue) \(executionDiagnostic)")
            return observation
        } catch {
            guard executionIsCurrent(nonce), generation == pageGeneration, page == webView.url else { return nil }
            executionDiagnostic = "evaluationError=\((error as NSError).code) attached=\(webView.window != nil)"
            Self.record("WEBMORNING site=\(site.rawValue) \(executionDiagnostic)")
            return nil
        }
    }

    /// Returns dispatch only. A subsequent independent observation establishes the effect.
    private func executionCommand(_ command: String, observation: WebMorningPageObservation,
                                  plan: WebMorningExecutionPlan, nonce: UUID) async -> Bool {
        guard executionIsCurrent(nonce), !loadFailed, !webView.isLoading,
              WebMorningExecutionPolicy.permits(site: site, url: webView.url, syntheticNews: syntheticNews),
              let fingerprint = observation.fingerprint else { return false }
        let generation = pageGeneration, page = webView.url
        let script = WebMorningExecutionPolicy.script(site: site, behavior: plan.behavior, command: command,
            fingerprint: fingerprint, likesAllowed: plan.likesAllowed, syntheticNews: syntheticNews)
        let value = try? await webView.evaluateJavaScript(script, contentWorld: .defaultClient)
        guard executionIsCurrent(nonce), generation == pageGeneration, page == webView.url,
              let text = value as? String, text.utf8.count < 200,
              let data = text.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return false }
        return result["status"] == "dispatched"
    }

    private func execute(_ plan: WebMorningExecutionPlan, nonce: UUID) async {
        guard executionIsCurrent(nonce) else { return }
        guard contentProgress.isAvailable else {
            executionDiagnostic = "stop=savedContentProgressUnavailable"
            publishExecution(.unavailable)
            return
        }
        guard WebMorningBehavior.availableBehaviors(for: site).contains(plan.behavior) else {
            publishExecution(.unavailable); return
        }
        // Navigation and DOM readiness have different bounds. Slow initial or
        // consent navigation must not consume the subsequent content's retries.
        var navigationAttempts = 0, failedObservations = 0, unreadyAttempts = 0, unchangedAdvances = 0
        var readinessGeneration = pageGeneration
        let journal = WebMorningLikeJournal(directory: LocalDataControl.defaultDirectory)
        while executionIsCurrent(nonce) {
            if readinessGeneration != pageGeneration {
                readinessGeneration = pageGeneration
                navigationAttempts = 0; failedObservations = 0; unreadyAttempts = 0
            }
            let hasUnresolved: Bool
            do { hasUnresolved = try !journal.unresolvedKeys(sessionID: plan.sessionID, stepID: plan.stepID).isEmpty }
            catch { publishExecution(.uncertainAction); return }
            if hasUnresolved { actionPending = true; publishExecution(.performingAction) }
            if let deadline = executionDeadline, Date() >= deadline, !hasUnresolved {
                executionFinished = true
                publishExecution(observedContentCount > 0 ? .finished : .unavailable); return
            }
            if loadFailed { publishExecution(.unavailable); return }
            if webView.isLoading || webView.url == nil {
                publishExecution(.waitingForPage)
                navigationAttempts += 1
                if navigationAttempts > 30 {
                    executionDiagnostic += " stop=navigation attempts=\(navigationAttempts)"
                    publishExecution(.unavailable); return
                }
                guard await executionWait(1, nonce: nonce) else { return }; continue
            }
            navigationAttempts = 0
            if !pageBelongsToSite(webView.url) {
                clearSourceText()
                publishExecution(.needsSignIn)
                guard await executionWait(1, nonce: nonce) else { return }; continue
            }
            guard let observation = await executionObserve(plan, nonce: nonce) else {
                guard executionIsCurrent(nonce) else { return }
                failedObservations += 1
                if failedObservations >= 5 {
                    executionDiagnostic += " stop=observation attempts=\(failedObservations)"
                    clearSourceText(); publishExecution(.unavailable); return
                }
                guard await executionWait(1, nonce: nonce) else { return }; continue
            }
            failedObservations = 0
            pageAccessRefusal = nil
            switch observation.status {
            case .signin:
                unreadyAttempts = 0
                clearSourceText()
                publishExecution(.needsSignIn)
                guard await executionWait(1, nonce: nonce) else { return }; continue
            case .choice:
                unreadyAttempts = 0
                clearSourceText()
                pageAccessRefusal = observation.pageAccessRefusal
                publishExecution(.needsChoice)
                guard await executionWait(1, nonce: nonce) else { return }; continue
            case .loading, .empty:
                clearSourceText()
                if observation.consentCanDismiss == true {
                    _ = await executionCommand("rejectConsent", observation: observation, plan: plan, nonce: nonce)
                }
                unreadyAttempts += 1
                publishExecution(.waitingForPage)
                if unreadyAttempts >= 8 {
                    executionDiagnostic += " stop=contentReadiness attempts=\(unreadyAttempts)"
                    publishExecution(.unavailable); return
                }
                guard await executionWait(1, nonce: nonce) else { return }; continue
            case .unavailable: clearSourceText(); publishExecution(.unavailable); return
            case .ready: break
            }
            unreadyAttempts = 0
            if let route = observation.storyRoute {
                guard route.hasPrefix("/stories/"), let page = webView.url,
                      let next = URL(string: route, relativeTo: page)?.absoluteURL,
                      WebMorningExecutionPolicy.permits(site: site, url: next) else {
                    publishExecution(.unavailable); return
                }
                webView.load(URLRequest(url: next))
                guard await executionWait(1, nonce: nonce) else { return }; continue
            }
            if plan.behavior == .watchVideos || plan.behavior == .watchStories,
               observation.mediaPlaying == false {
                guard await executionCommand("play", observation: observation, plan: plan, nonce: nonce),
                      await executionWait(1, nonce: nonce),
                      let playing = await executionObserve(plan, nonce: nonce), playing.mediaPlaying == true else {
                    if executionIsCurrent(nonce) { publishExecution(.unavailable) }; return
                }
            }
            guard let fingerprint = observation.fingerprint else { publishExecution(.unavailable); return }
            executionContextText = observation.text ?? []
            if site == .news { retainNewsSnapshot(observation) }
            do {
                let isNew = try contentProgress.observe(site: site, fingerprint: fingerprint)
                observedContentCount = contentProgress.observedCount
                executionDiagnostic += " newContent=\(isNew ? 1 : 0) savedCount=\(observedContentCount)"
            } catch {
                executionDiagnostic = "stop=contentProgressCapacity"
                publishExecution(.unavailable)
                return
            }
            let spoken = (plan.behavior == .readHeadlines || plan.behavior == .readUnread) && lastSpokenFingerprint != fingerprint
                ? (newsSnapshot?.numberedTitles ?? observation.text ?? []) : []
            if !spoken.isEmpty { lastSpokenFingerprint = fingerprint }
            if !hasUnresolved { publishExecution(.running, text: spoken) }
            guard executionIsCurrent(nonce) else { return }
            // Reconcile every unresolved browser action before considering another like.
            do {
                let unresolved = try journal.unresolvedKeys()
                if plan.likesAllowed, !unresolved.isEmpty {
                    guard let contentID = observation.contentID, observation.liked == true,
                          unresolved == [WebMorningLikeJournal.key(site: site, contentID: contentID)] else {
                        publishExecution(.uncertainAction); return
                    }
                    try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { state in
                        guard state.generation == privacyBinding?.persistedGeneration else { throw LocalDataControlError.staleGeneration }
                        try journal.confirm(unresolved[0])
                    }
                    actionPending = false
                    confirmedLikeCount = min(plan.maximumLikes, max(confirmedLikeCount,
                        try journal.confirmedCount(sessionID: plan.sessionID, stepID: plan.stepID)))
                    publishExecution(.running)
                }
                guard executionIsCurrent(nonce) else { return }
                if plan.likesAllowed, confirmedLikeCount < plan.maximumLikes,
                   observation.canLike == true, observation.liked != true, let contentID = observation.contentID,
                   try journal.attemptCount(sessionID: plan.sessionID, stepID: plan.stepID) < plan.maximumLikes {
                    let key = WebMorningLikeJournal.key(site: site, contentID: contentID)
                    let reserved = try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { state in
                        guard state.generation == privacyBinding?.persistedGeneration else { throw LocalDataControlError.staleGeneration }
                        return try journal.reserve(key, sessionID: plan.sessionID, stepID: plan.stepID)
                    }
                    if reserved {
                        actionPending = true; publishExecution(.performingAction)
                        // An interrupted or ambiguous dispatch retains the attempt; never toggle again.
                        guard await executionCommand("like", observation: observation, plan: plan, nonce: nonce),
                              await executionWait(1.2, nonce: nonce),
                              let after = await executionObserve(plan, nonce: nonce), after.contentID == contentID,
                              after.liked == true else {
                            if executionIsCurrent(nonce) { publishExecution(.uncertainAction) }; return
                        }
                        try LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess { state in
                            guard state.generation == privacyBinding?.persistedGeneration else { throw LocalDataControlError.staleGeneration }
                            try journal.confirm(key)
                        }
                        actionPending = false
                        confirmedLikeCount = max(confirmedLikeCount,
                            try journal.confirmedCount(sessionID: plan.sessionID, stepID: plan.stepID))
                        publishExecution(.running)
                    }
                }
            } catch { publishExecution(.uncertainAction); return }
            guard await executionWait(plan.dwellSeconds, nonce: nonce) else { return }
            while executionCanAdvance?() == false {
                guard await executionWait(0.5, nonce: nonce) else { return }
            }
            if let deadline = executionDeadline, Date() >= deadline { continue }
            guard let before = await executionObserve(plan, nonce: nonce) else { continue }
            if before.canAdvance == false {
                executionFinished = true; publishExecution(.finished); return
            }
            guard await executionCommand("advance", observation: before, plan: plan, nonce: nonce),
                  await executionWait(1.2, nonce: nonce),
                  let after = await executionObserve(plan, nonce: nonce), after.status == .ready,
                  after.fingerprint != before.fingerprint || after.scrollOffset != before.scrollOffset else {
                guard executionIsCurrent(nonce) else { return }
                unchangedAdvances += 1
                if unchangedAdvances >= 2 { publishExecution(.unavailable); return }
                guard await executionWait(2, nonce: nonce) else { return }; continue
            }
            unchangedAdvances = 0
        }
    }

    /// Clears every site's session and content-free action keys in this app's dedicated store.
    static func clearAllSignIns() async {
        await WKWebsiteDataStore(forIdentifier: storeIdentifier).removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        try? FileManager.default.removeItem(at: LocalDataControl.defaultDirectory.appendingPathComponent("browser-action-journal.json"))
    }

    func forgetSignIns() async {
        guard privacyIsCurrent, !isClearing else { return }
        isClearing = true
        defer { isClearing = false }
        discardLearning()
        discardSourceContext()
        stopExecution()
        actionsEnabled = false
        webView.stopLoading()
        pageGeneration += 1
        outcome = nil
        await Self.clearAllSignIns()
        guard privacyIsCurrent else { return }
        guard !syntheticNewsRequested || syntheticNews != nil else { return }
        webView.load(URLRequest(url: syntheticNews?.startURL ?? site.table.startURL))
    }

    func reload() { if privacyIsCurrent { executionFinished = false; webView.reload() } }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        // Website links may navigate to a sign-in provider. MORE never runs scripts there.
        // Do not launch native social apps, custom schemes, insecure pages or downloads.
        guard privacyIsCurrent, let url = navigationAction.request.url, url.user == nil, url.password == nil else { decisionHandler(.cancel); return }
        if site == .instagram {
            switch instagramDecision(for: navigationAction) {
            case .cancel: decisionHandler(.cancel); return
            case let .load(destination):
                // Cancel before WebKit can attempt the universal link, including
                // target=_blank and JavaScript/redirect navigations. Public load
                // requests keep app links in this WKWebView.
                var request = navigationAction.request
                request.url = destination
                decisionHandler(.cancel)
                if privacyIsCurrent { webView.load(request) }
                return
            case .allow: break
            }
        }
        if syntheticNewsRequested {
            guard let syntheticNews, syntheticNews.permits(url), navigationAction.request.httpMethod == "GET",
                  navigationAction.request.httpBody == nil, !navigationAction.shouldPerformDownload else {
                if articleReturnPoint != nil { refuseArticle(.unexpectedDestination, cancelOperation: true) }
                decisionHandler(.cancel); return
            }
        } else if url.scheme?.lowercased() != "https" { decisionHandler(.cancel); return }
        if navigationAction.targetFrame?.isMainFrame != false, let point = articleReturnPoint,
           (!WebArticlePolicy.isPage(url, syntheticNews: syntheticNews) || url.host?.lowercased() != point.item.url.host?.lowercased() || navigationAction.shouldPerformDownload ||
            articleExpectedDestination.map({ !WebArticlePolicy.matchesDestination(url, selected: $0, syntheticNews: syntheticNews) }) == true) {
            refuseArticle(.unexpectedDestination, cancelOperation: true)
            decisionHandler(.cancel); return
        }
        if articleReturnPoint != nil, !articleBusy, navigationAction.targetFrame?.isMainFrame != false {
            refuseArticle(.stale)
        }
        if navigationAction.targetFrame?.isMainFrame != false {
            stopLearning()
            clearSourceText()
            pageGeneration += 1
            displayedHost = url.host ?? ""
            isSignInPage = true
            outcome = nil
            loadFailed = false
        }
        decisionHandler(privacyIsCurrent ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        if syntheticNewsRequested {
            #if DEBUG
            guard let syntheticNews, let url = navigationResponse.response.url, syntheticNews.permits(url),
                  navigationResponse.response.mimeType == "text/html", syntheticNewsHandler?.deliveredHTML.contains(url) == true else {
                refuseArticle(.unexpectedDestination, cancelOperation: true); decisionHandler(.cancel); return
            }
            if needsArticleReturn, navigationResponse.isForMainFrame {
                guard let selected = articleExpectedDestination,
                      WebArticlePolicy.matchesDestination(url, selected: selected, syntheticNews: syntheticNews) else {
                    refuseArticle(.unexpectedDestination, cancelOperation: true); decisionHandler(.cancel); return
                }
                articleLocalResponse = url
            }
            decisionHandler(privacyIsCurrent ? .allow : .cancel); return
            #else
            decisionHandler(.cancel); return
            #endif
        }
        if needsArticleReturn, navigationResponse.isForMainFrame {
            guard let selected = articleExpectedDestination, let response = navigationResponse.response as? HTTPURLResponse,
                  let url = response.url else {
                articleResponse = nil; refuseArticle(.unexpectedDestination, cancelOperation: true)
                decisionHandler(.cancel); return
            }
            guard WebArticlePolicy.matchesDestination(url, selected: selected) else {
                articleResponse = nil; refuseArticle(.unexpectedDestination, cancelOperation: true)
                decisionHandler(.cancel); return
            }
            guard (200..<300).contains(response.statusCode) else {
                articleResponse = nil; refuseArticle(.httpFailure, cancelOperation: true)
                decisionHandler(.cancel); return
            }
            articleResponse = (url, response.statusCode)
        }
        if needsArticleReturn, navigationResponse.isForMainFrame,
           !["text/html", "application/xhtml+xml"].contains(navigationResponse.response.mimeType?.lowercased() ?? "") {
            refuseArticle(.unsupportedContent, cancelOperation: true)
            decisionHandler(.cancel); return
        }
        decisionHandler(privacyIsCurrent ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // Keep a user-opened link visible in the same browser, including sign-in pages.
        if site == .instagram, privacyIsCurrent, navigationAction.targetFrame == nil {
            switch instagramDecision(for: navigationAction) {
            case .cancel: return nil
            case let .load(destination):
                var request = navigationAction.request
                request.url = destination
                webView.load(request)
                return nil
            case .allow: break
            }
        }
        if privacyIsCurrent, navigationAction.targetFrame == nil, let url = navigationAction.request.url,
           url.user == nil, url.password == nil,
           syntheticNewsRequested ? syntheticNews?.permits(url) == true : url.scheme?.lowercased() == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    private func instagramDecision(for action: WKNavigationAction) -> InstagramBrowserNavigation.Decision {
        guard let url = action.request.url else { return .cancel }
        let kind: InstagramBrowserNavigation.Kind
        switch action.navigationType {
        case .linkActivated: kind = .link
        case .formSubmitted, .formResubmitted: kind = .form
        case .backForward: kind = .history
        default: kind = .other
        }
        return instagramNavigation.decide(url: url, kind: kind,
            method: action.request.httpMethod ?? "GET",
            currentURL: webView.url,
            isTopLevel: action.targetFrame?.isMainFrame != false,
            isNewWindow: action.targetFrame == nil, isDownload: action.shouldPerformDownload)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        instagramNavigation = InstagramBrowserNavigation()
        displayedHost = webView.url?.host ?? ""
        isSignInPage = !pageBelongsToSite(webView.url)
        loadFailed = false
        let kind = isSignInPage ? "blocked" : "site"
        Self.record("WEBMORNING site=\(site.rawValue) page=\(kind)")
        Self.excludeWebDataFromBackup()
        resumeExecutionIfNeeded()
    }

    private func pageBelongsToSite(_ url: URL?) -> Bool {
        if let syntheticNews { return syntheticNews.permits(url) }
        return !WebMorningPolicy.isSignInPage(url) && WebMorningSite(url: url ?? site.table.startURL) == site
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { failed(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        invalidateUnavailablePage()
        Self.record("WEBMORNING site=\(site.rawValue) load=processTerminated")
    }

    private func failed(_ error: any Error) {
        let code = (error as NSError).code
        guard code != NSURLErrorCancelled else { return }
        invalidateUnavailablePage()
        Self.record("WEBMORNING site=\(site.rawValue) load=failed code=\(code)")
    }

    /// A failed or terminated page cannot retain a successful reader result or
    /// finish a cadence lesson. Invalidate awaits even when the URL did not change.
    /// Reload remains an explicit action in the visible browser.
    private func invalidateUnavailablePage() {
        instagramNavigation = InstagramBrowserNavigation()
        pageGeneration += 1
        discardLearning()
        clearSourceText()
        outcome = nil
        loadFailed = true
        isSignInPage = true
        if needsArticleReturn {
            // Keep a precise navigation rejection when WebKit subsequently
            // reports its cancellation. An earlier DOM/staleness refusal must
            // not hide a new load failure after an explicit reload.
            let retained: [WebArticleRefusal] = [.unexpectedDestination, .httpFailure, .unsupportedContent]
            let reason = articleRefusal.flatMap { retained.contains($0) ? $0 : nil } ?? .navigationFailure
            cancelArticleWork()
            refuseArticle(reason)
        }
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

/// Only one pinned routine page is retained, in memory. Standalone browsing and
/// sign-in/learning pages keep their independent controller lifetime.
@MainActor
final class RoutineWebMomentRetainer {
    private var retained: (executionID: MorningExecutionID, privacyGeneration: UUID, site: WebMorningSite, initialURL: URL, controller: WebMorningController)?

    func controller(for executionID: MorningExecutionID, privacyGeneration: UUID,
                    site: WebMorningSite, initialURL: URL) -> WebMorningController {
        if let retained, retained.executionID == executionID, retained.privacyGeneration == privacyGeneration,
           retained.site == site, retained.initialURL == initialURL {
            return retained.controller
        }
        clear()
        let controller = WebMorningController(site: site, initialURL: initialURL,
            routineContext: .init(sessionID: executionID.sessionID, routineVersionID: executionID.routineVersionID, stepID: executionID.stepID),
            runtimePrivacyGeneration: privacyGeneration)
        retained = (executionID, privacyGeneration, site, initialURL, controller)
        return controller
    }

    func hasController(for executionID: MorningExecutionID, privacyGeneration: UUID) -> Bool {
        existingController(for: executionID, privacyGeneration: privacyGeneration) != nil
    }
    func existingController(for executionID: MorningExecutionID, privacyGeneration: UUID) -> WebMorningController? {
        guard let retained else { return nil }
        guard retained.privacyGeneration == privacyGeneration else { clear(); return nil }
        return retained.executionID == executionID ? retained.controller : nil
    }

    func discardSourceContext() { retained?.controller.discardSourceContext() }

    func clear() {
        let previous = retained?.controller
        retained = nil
        previous?.retire()
    }
}

/// WebKit retains the handler; the handler must not retain its browser owner.
@MainActor private final class BrowserRhythmMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebMorningController?
    init(owner: WebMorningController) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receiveRhythm(message)
    }
}
