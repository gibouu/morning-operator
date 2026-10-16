import MorningCore
import SwiftUI
import WebKit

/// The page remains visible while MORE performs an approved behavior. Routine callers
/// pass their saved deadline and extension callback; only the standalone debug screen
/// uses a local clock. Closing and reopening a routine does not reset its timer.
struct WebMorningView: View {
    let site: WebMorningSite
    var isStepActive: Bool
    let stepEndsAt: Date?
    let timerPausedAt: Date?
    var onExtend: (() -> Void)?
    var onNext: (() -> Void)?
    var onClose: () -> Void
    var executionPlan: WebMorningExecutionPlan?
    var onExecutionEvent: ((WebMorningExecutionEvent) -> Void)?
    var executionIsAuthorized: (() -> Bool)?
    var executionCanAdvance: (() -> Bool)?
    var onPause: (() -> Void)?
    var onResume: (() -> Void)?
    var onNativeRequest: (() -> Void)?
    var onNewsArticle: ((Int) -> Void)?
    var onNewsReturn: (() -> Void)?
    var onNewsRepeat: (() -> Void)?
    /// A sign-in pass is normal browsing, without routine timers or page readers.
    var onSignInReady: (() -> Void)?
    var learningOnly: Bool
    var onSaveRhythm: ((BrowserRhythmSummary) -> Bool)?
    private let retainsRoutineController: Bool
    @State private var rhythmSaved = false
    @State private var rhythmSaveFailed = false

    @State private var controller: WebMorningController
    @State private var clock: WebMorningStepClock
    @State private var showingAbout = false
    @AppStorage("webMorning.explained") private var explained = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    init(site: WebMorningSite, minutes: Int, initialURL: URL? = nil, isStepActive: Bool = true,
         stepEndsAt: Date? = nil, timerPausedAt: Date? = nil, onExtend: (() -> Void)? = nil,
         onNext: (() -> Void)? = nil, onSignInReady: (() -> Void)? = nil,
         learningOnly: Bool = false, onSaveRhythm: ((BrowserRhythmSummary) -> Bool)? = nil,
         executionPlan: WebMorningExecutionPlan? = nil,
         onExecutionEvent: ((WebMorningExecutionEvent) -> Void)? = nil,
         executionIsAuthorized: (() -> Bool)? = nil, executionCanAdvance: (() -> Bool)? = nil,
         onPause: (() -> Void)? = nil, onResume: (() -> Void)? = nil,
         onNativeRequest: (() -> Void)? = nil,
         retainedController: WebMorningController? = nil,
         onNewsArticle: ((Int) -> Void)? = nil, onNewsReturn: (() -> Void)? = nil, onNewsRepeat: (() -> Void)? = nil,
         onClose: @escaping () -> Void) {
        self.site = site; self.isStepActive = isStepActive; self.stepEndsAt = stepEndsAt; self.timerPausedAt = timerPausedAt
        self.onExtend = onExtend; self.onNext = onNext; self.onClose = onClose
        self.onSignInReady = onSignInReady
        self.learningOnly = learningOnly; self.onSaveRhythm = onSaveRhythm
        self.executionPlan = executionPlan; self.onExecutionEvent = onExecutionEvent
        self.onPause = onPause; self.onResume = onResume
        self.onNativeRequest = onNativeRequest
        self.onNewsArticle = onNewsArticle; self.onNewsReturn = onNewsReturn; self.onNewsRepeat = onNewsRepeat
        self.executionIsAuthorized = executionIsAuthorized; self.executionCanAdvance = executionCanAdvance
        retainsRoutineController = retainedController != nil
        _controller = State(initialValue: retainedController ?? WebMorningController(site: site, initialURL: initialURL))
        _clock = State(initialValue: WebMorningStepClock(start: Date(), minutes: minutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if site == .gmail {
                ScrollView { GmailConnectionView(allowsReading: isStepActive).padding(24) }
            } else {
                WebMorningWebView(webView: controller.webView)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .padding(.horizontal, 10)
                    .accessibilityIdentifier("web.page")
            }
            if site == .gmail { bottomBar }
            else if let onSignInReady {
                HStack(spacing: 12) {
                    Button { controller.reload() } label: {
                        MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).accessibilityLabel(text("Reload page", "Recharger la page"))
                    Spacer()
                    Button(action: onSignInReady) {
                        Text(text("I'm ready", "C’est prêt"))
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("connections.confirmReady")
                }.padding(.horizontal, 18).padding(.vertical, 12)
            } else if learningOnly {
                rhythmControls.padding(.horizontal, 18).padding(.vertical, 12)
            } else { bottomBar }
        }
        .background(MorningPaper(showsSun: false))
        .foregroundStyle(MorningStyle.ink)
        .tint(MorningStyle.accent)
        .sheet(isPresented: $showingAbout) { about }
        .onAppear {
            controller.onExecutionEvent = onExecutionEvent
            controller.executionIsAuthorized = executionIsAuthorized
            controller.executionCanAdvance = executionCanAdvance
            controller.configureExecution(plan: executionPlan, endsAt: stepEndsAt ?? clock.endsAt)
            if site != .gmail { controller.startIfNeeded() }
            controller.actionsEnabled = isStepActive && scenePhase == .active
            controller.learningAllowed = learningOnly && scenePhase == .active
            if site != .gmail && executionPlan == nil && !explained && onSignInReady == nil && !learningOnly { showingAbout = true }
        }
        .onChange(of: scenePhase) { _, phase in
            controller.actionsEnabled = isStepActive && phase == .active && !showingAbout
            controller.learningAllowed = learningOnly && phase == .active && !showingAbout
        }
        .onChange(of: isStepActive) { _, active in controller.actionsEnabled = active && scenePhase == .active && !showingAbout }
        .onChange(of: showingAbout) { _, presented in
            controller.actionsEnabled = !presented && isStepActive && scenePhase == .active
            controller.learningAllowed = learningOnly && !presented && scenePhase == .active
        }
        .onChange(of: executionPlan) { _, plan in
            controller.configureExecution(plan: plan, endsAt: stepEndsAt ?? clock.endsAt)
        }
        .onChange(of: stepEndsAt) { _, deadline in
            controller.configureExecution(plan: executionPlan, endsAt: deadline ?? clock.endsAt)
        }
        .onDisappear {
            if retainsRoutineController { controller.suspendPresentation() }
            else {
                controller.actionsEnabled = false; controller.learningAllowed = false
                controller.stopExecution()
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                MorningDottedIcon(systemName: "xmark").frame(width: 23, height: 23).frame(width: 44, height: 44)
            }.accessibilityLabel(text("Close", "Fermer")).accessibilityIdentifier("web.close")
            Text(controller.isSyntheticNews ? controller.sourceLabel : site == .gmail || controller.displayedHost.isEmpty ? site.displayName : controller.displayedHost)
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).lineLimit(1)
                .accessibilityIdentifier("web.host")
            Spacer(minLength: 4)
            if onSignInReady == nil && !learningOnly { TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, (stepEndsAt ?? clock.endsAt).timeIntervalSince(timerPausedAt ?? context.date))
                Text(Duration.seconds(left.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .font(.raleway(.subheadline).monospacedDigit())
                    .foregroundStyle(left == 0 ? MorningStyle.accent : MorningStyle.ink)
                    .accessibilityIdentifier("web.remaining")
            } } else {
                Text(learningOnly ? text("Learning", "Apprentissage") : text("Sign in", "Connexion"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 12).padding(.vertical, 4)
    }

    private var rhythmControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.isLearning {
                HStack(spacing: 8) {
                    MorningDottedIcon(systemName: "record.circle.fill").frame(width: 18, height: 18)
                    Text(text("Learning your scroll and tap rhythm", "Apprentissage du rythme de vos gestes"))
                        .font(.raleway(.caption))
                }.foregroundStyle(MorningStyle.accent)
                Button(text("Stop learning", "Arrêter l’apprentissage")) { controller.stopLearning() }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("web.learningStop")
            } else if let summary = controller.learningSummary {
                Text(text("\(summary.totals.scrollBursts) scrolls · \(summary.totals.clicks) taps",
                          "\(summary.totals.scrollBursts) séquences de défilement · \(summary.totals.clicks) appuis"))
                    .font(.raleway(.subheadline))
                if let trace = summary.learningTrace {
                    ScrollView {
                        Text(trace.segments.indices.map { trace.proposedTitle(at: $0, french: locale.language.languageCode?.identifier == "fr") }.joined(separator: "\n"))
                            .font(.raleway(.caption)).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: 90).accessibilityIdentifier("web.learnedActivities")
                }
                if let speed = summary.averageMovingSpeed {
                    Text(speed > 800 ? text("A quick scrolling rhythm", "Un défilement rapide")
                         : speed > 250 ? text("A steady scrolling rhythm", "Un défilement régulier")
                         : text("A gentle scrolling rhythm", "Un défilement tranquille"))
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
                HStack(spacing: 12) {
                    if let onSaveRhythm {
                        Button(rhythmSaved ? text("Saved to Learn", "Enregistré") : text("Save to Learn", "Garder pour apprendre")) {
                            rhythmSaved = onSaveRhythm(summary)
                            rhythmSaveFailed = !rhythmSaved
                        }.buttonStyle(PrimaryButtonStyle()).disabled(rhythmSaved || controller.isFinishingLearning)
                    }
                    Button(text("Try again", "Recommencer")) { controller.discardLearning(); rhythmSaved = false; rhythmSaveFailed = false }
                        .buttonStyle(QuietButtonStyle())
                }
                Text(text("Only known page categories and gestures here. Review MORE’s proposed actions in Learn before approval.",
                          "Uniquement les catégories de pages connues et vos gestes ici. Examinez les actions proposées dans Apprendre avant de les valider."))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if rhythmSaveFailed {
                    Text(text("Couldn't save yet. Try Save again.", "Enregistrement impossible. Réessayez."))
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.accent)
                }
            } else {
                Text(text("Browse as you normally do. MORE counts gestures here, without saving page text or form entries.",
                          "Naviguez à votre rythme. MORE compte ici les gestes, sans garder le texte ni les champs saisis."))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                Button(text("Learn my pace", "Apprendre mon rythme")) {
                    Task { _ = await controller.startLearning() }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!controller.canLearn)
                    .accessibilityIdentifier("web.learningStart")
                if !controller.canLearn {
                    Text(text("Finish signing in and wait for the page to load.", "Terminez la connexion et attendez le chargement."))
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if site == .news {
                if let snapshot = controller.newsSnapshot, let onNewsArticle {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(snapshot.links.indices, id: \.self) { index in
                                Button { onNewsArticle(index + 1) } label: {
                                    Text("\(index + 1). \(snapshot.links[index].title)").font(.raleway(.subheadline))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.disabled(controller.articleBusy).accessibilityIdentifier("web.article.\(index + 1)")
                            }
                        }
                    }.frame(maxHeight: 140).accessibilityIdentifier("web.articleChoices")
                }
                if controller.needsArticleReturn {
                    HStack {
                        if let onNewsReturn {
                            Button(text("Back to headlines", "Retour aux titres"), action: onNewsReturn)
                                .accessibilityIdentifier("web.articleReturn")
                        }
                        if controller.articleText != nil, let onNewsRepeat {
                            Button(text("Read again", "Relire"), action: onNewsRepeat)
                                .accessibilityIdentifier("web.articleRepeat")
                        }
                    }.font(.raleway(.subheadline))
                }
            }
            if let line = resultLine {
                if case .headlines = controller.outcome {
                    ScrollView { Text(line).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 110).accessibilityIdentifier("web.result")
                        .accessibilityValue(resultDiagnostic)
                } else {
                    Text(line).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("web.result")
                        .accessibilityValue(resultDiagnostic)
                }
            }
            HStack(spacing: 4) {
                if executionPlan == nil { ForEach(site.table.tasks, id: \.self) { task in
                    Button { Task { await controller.run(task) } } label: {
                        MorningDottedIcon(systemName: symbol(for: task)).frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(title(for: task))
                    .disabled(controller.isRunning || controller.isLearning || controller.isClearing || controller.isSignInPage || !controller.actionsEnabled)
                    .accessibilityIdentifier("web.\(task.rawValue)")
                } }
                if executionPlan != nil {
                    if let onNativeRequest {
                        Button(action: onNativeRequest) {
                            MorningDottedIcon(systemName: "calendar.badge.plus").frame(width: 23, height: 23).frame(width: 44, height: 44)
                        }.accessibilityLabel(text("Reminders and Calendar", "Rappels et calendrier"))
                            .accessibilityIdentifier("web.nativeRequest")
                    }
                    if isStepActive, let onPause {
                        Button(action: onPause) {
                            MorningDottedIcon(systemName: "pause.fill").frame(width: 23, height: 23).frame(width: 44, height: 44)
                        }.accessibilityLabel(text("Pause my morning", "Mettre mon matin en pause"))
                            .accessibilityIdentifier("web.pause")
                    } else if !isStepActive, let onResume {
                        Button(action: onResume) {
                            MorningDottedIcon(systemName: "play.fill").frame(width: 23, height: 23).frame(width: 44, height: 44)
                        }.accessibilityLabel(text("Resume my morning", "Reprendre mon matin"))
                            .accessibilityIdentifier("web.resume")
                    }
                }
                if site != .gmail {
                    Button { controller.reload() } label: {
                        MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 23, height: 23).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("Reload page", "Recharger la page")).accessibilityIdentifier("web.reload")
                    Button { showingAbout = true } label: {
                        MorningDottedIcon(systemName: "info.circle").frame(width: 23, height: 23).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("About this screen", "À propos de cet écran"))
                }
                Spacer(minLength: 0)
                Button {
                    if let onExtend { onExtend() } else { clock.extend(at: Date()) }
                } label: { Text("+2").font(.raleway(.subheadline).monospacedDigit()).frame(width: 44, height: 44) }
                    .accessibilityLabel(text("Add two minutes", "Ajouter deux minutes"))
                    .disabled(!isStepActive).accessibilityIdentifier("web.extend")
                if let onNext {
                    Button(action: onNext) {
                        MorningDottedIcon(systemName: "arrow.right").frame(width: 25, height: 25).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("Next step", "Étape suivante"))
                        .disabled(!isStepActive && executionPlan == nil).accessibilityIdentifier("web.nextMoment")
                }
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var resultLine: String? {
        if site == .gmail { return nil }
        if let message = controller.articleMessage { return message }
        if let event = controller.executionEvent, executionPlan != nil {
            switch event.state {
            case .waitingForPage: return text("Preparing your content…", "Préparation de vos contenus…")
            case .running:
                return text("MORE is taking care of this · \(event.observedContentCount) contents viewed",
                            "MORE s’en occupe · \(event.observedContentCount) contenus parcourus")
            case .performingAction: return text("Checking this like…", "Vérification de ce j’aime…")
            case .paused: return text("Paused · \(event.observedContentCount) contents viewed. Resume when you're ready.",
                                      "En pause · \(event.observedContentCount) contenus parcourus. Reprenez quand vous le souhaitez.")
            case .needsSignIn: return text("Sign in on the page. MORE will resume here.", "Connectez-vous sur la page. MORE reprendra ici.")
            case .needsChoice:
                if controller.pageAccessRefusal == .consentRequired {
                    return text("This page requires a cookie choice. Choose on the page, then resume, or skip this moment.",
                        "Cette page demande un choix sur les cookies. Faites votre choix sur la page, puis reprenez, ou passez ce moment.")
                }
                return text("This page needs your choice. Choose on the page, then resume, or skip this moment.", "Cette page attend votre choix. Faites votre choix sur la page, puis reprenez, ou passez ce moment.")
            case .unavailable:
                if !controller.savedContentProgressIsAvailable {
                    return text("Saved progress for this moment is unavailable. Skip this moment to continue your morning.",
                        "La progression sauvegardée de ce moment est indisponible. Passez au moment suivant pour poursuivre votre matin.")
                }
                return text("MORE couldn't continue on this page. Reload or skip this moment.", "MORE ne peut pas continuer sur cette page. Rechargez ou passez ce moment.")
            case .uncertainAction: return text("This like couldn't be verified. MORE has stopped to avoid repeating it.", "Ce j’aime n’a pas pu être vérifié. MORE s’est arrêté pour éviter de le répéter.")
            case .finished: return text("This moment is complete · \(event.observedContentCount) contents viewed", "Ce moment est terminé · \(event.observedContentCount) contenus parcourus")
            case .cancelled: return text("MORE has stopped on this page.", "MORE s’est arrêté sur cette page.")
            }
        }
        if controller.loadFailed { return text("Page unavailable. Try reload.", "Page indisponible. Réessayez.") }
        if controller.isSignInPage { return text("Sign in on the page.", "Connectez-vous sur la page.") }
        switch controller.outcome {
        case .count(let n): return text("Visible unread: \(n)", "Non lus visibles : \(n)")
        case .headlines(let list): return list.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .scrollRequested: return text("Scroll requested. Check the page.", "Défilement demandé. Vérifiez la page.")
        case .unsupported(let reason):
            return reason == "signin" ? text("Sign in first.", "Connectez-vous d’abord.")
                : text("Reading unavailable on this page.", "Lecture indisponible sur cette page.")
        case .refused(.notTheFeed): return text("Opening videos… Tap when ready.", "Ouverture des vidéos… Touchez quand elles sont prêtes.")
        case .refused: return text("Not on this page.", "Pas sur cette page.")
        case nil: return nil
        }
    }

    private var resultDiagnostic: String {
        #if DEBUG
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return "" }
        let source = controller.executionEvent?.contextText ?? []
        let position = Int(controller.webView.scrollView.contentOffset.y.rounded())
        let execution = "\(controller.executionDiagnostic) pageState=\(controller.executionEvent?.state.rawValue ?? "none") pageAccessRefusal=\(controller.pageAccessRefusal?.rawValue ?? "none") articleRefusal=\(controller.articleRefusal?.rawValue ?? "none") viewportY=\(position) sourceItems=\(source.count) sourceIdentity=\(source.hashValue)"
        guard controller.isSyntheticNews else { return execution }
        // Keep identity, budget and Repeat receipts ahead of admission detail
        // so bounded accessibility snapshots retain the proof's essential fields.
        let budget = "endsAtBits=\(stepEndsAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) } ?? "none") pausedAtBits=\(timerPausedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) } ?? "none")"
        return "\(budget) viewportY=\(position) \(controller.syntheticNewsDiagnostic) \(execution)"
        #else
        return ""
        #endif
    }

    private func title(for task: WebMorningTask) -> String {
        switch task {
        case .unreadCount: text("Unread", "Non lus")
        case .headlines: text("Headlines", "Titres")
        case .nextVideo: text("Next video", "Vidéo suivante")
        }
    }

    private func symbol(for task: WebMorningTask) -> String {
        switch task {
        case .unreadCount: "envelope.badge"
        case .headlines: "newspaper"
        case .nextVideo: "arrow.down"
        }
    }

    private var about: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(text(executionPlan == nil ? "You sign in and browse here. A validated routine can let MORE take care of this moment." : "MORE follows the behavior you approved. You can pause or stop at any time.",
                              executionPlan == nil ? "Connectez-vous et naviguez ici. Une routine validée peut confier ce moment à MORE." : "MORE suit le comportement que vous avez validé. Vous pouvez le mettre en pause ou l’arrêter à tout moment."))
                        .font(MorningTheme.Typography.body)
                    DisclosureGroup(text("Privacy & website controls", "Confidentialité et commandes du site")) {
                        Text(text("MORE does not read passwords or send messages from these pages. Likes run only when included in the approved behavior, up to three per moment. Sign-in stays in this browser.",
                                  "MORE ne lit pas les mots de passe et n’envoie pas de message depuis ces pages. Les j’aime sont réalisés seulement s’ils font partie du comportement validé, au maximum trois par moment. La connexion reste dans ce navigateur."))
                            .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).padding(.top, 8)
                    }.font(.raleway(.subheadline))
                    Button(text("Clear all website sign-ins", "Effacer toutes les connexions aux sites"), role: .destructive) {
                        Task { await controller.forgetSignIns() }
                    }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("web.forget")
                }.padding(24)
            }
            .background(MorningPaper(showsSun: false)).navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { explained = true; showingAbout = false } label: {
                        MorningDottedIcon(systemName: "xmark").frame(width: 23, height: 23).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("Got it", "Compris")).accessibilityIdentifier("web.aboutDone")
                }
            }
        }.presentationDetents([.medium, .large])
    }

    private func text(_ english: String, _ french: String) -> String {
        locale.language.languageCode?.identifier == "fr" ? french : english
    }
}

private struct WebMorningWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
