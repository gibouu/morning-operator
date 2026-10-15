import MorningCore
import SwiftUI
import WebKit

/// The page remains visible and each MORE action requires one tap. Routine callers
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
    /// A sign-in pass is normal browsing, without routine timers or page readers.
    var onSignInReady: (() -> Void)?
    var learningOnly: Bool
    var onSaveRhythm: ((BrowserRhythmSummary) -> Bool)?
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
         onClose: @escaping () -> Void) {
        self.site = site; self.isStepActive = isStepActive; self.stepEndsAt = stepEndsAt; self.timerPausedAt = timerPausedAt
        self.onExtend = onExtend; self.onNext = onNext; self.onClose = onClose
        self.onSignInReady = onSignInReady
        self.learningOnly = learningOnly; self.onSaveRhythm = onSaveRhythm
        _controller = State(initialValue: WebMorningController(site: site, initialURL: initialURL))
        _clock = State(initialValue: WebMorningStepClock(start: Date(), minutes: minutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            WebMorningWebView(webView: controller.webView)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 10)
                .accessibilityIdentifier("web.page")
            if let onSignInReady {
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
            controller.startIfNeeded()
            controller.actionsEnabled = isStepActive && scenePhase == .active
            controller.learningAllowed = learningOnly && scenePhase == .active
            if !explained && onSignInReady == nil && !learningOnly { showingAbout = true }
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
        .onDisappear { controller.actionsEnabled = false; controller.learningAllowed = false }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                MorningDottedIcon(systemName: "xmark").frame(width: 23, height: 23).frame(width: 44, height: 44)
            }.accessibilityLabel(text("Close", "Fermer")).accessibilityIdentifier("web.close")
            Text(controller.displayedHost.isEmpty ? site.displayName : controller.displayedHost)
                .font(.caption).foregroundStyle(MorningStyle.muted).lineLimit(1)
                .accessibilityIdentifier("web.host")
            Spacer(minLength: 4)
            if onSignInReady == nil && !learningOnly { TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = max(0, (stepEndsAt ?? clock.endsAt).timeIntervalSince(timerPausedAt ?? context.date))
                Text(Duration.seconds(left.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(left == 0 ? MorningStyle.accent : MorningStyle.ink)
                    .accessibilityIdentifier("web.remaining")
            } } else {
                Text(learningOnly ? text("Learning", "Apprentissage") : text("Sign in", "Connexion"))
                    .font(.caption).foregroundStyle(MorningStyle.muted)
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
                        .font(.caption)
                }.foregroundStyle(MorningStyle.accent)
                Button(text("Stop learning", "Arrêter l’apprentissage")) { controller.stopLearning() }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("web.learningStop")
            } else if let summary = controller.learningSummary {
                Text(text("\(summary.totals.scrollBursts) scrolls · \(summary.totals.clicks) taps",
                          "\(summary.totals.scrollBursts) séquences de défilement · \(summary.totals.clicks) appuis"))
                    .font(.subheadline)
                if let speed = summary.averageMovingSpeed {
                    Text(speed > 800 ? text("A quick scrolling rhythm", "Un défilement rapide")
                         : speed > 250 ? text("A steady scrolling rhythm", "Un défilement régulier")
                         : text("A gentle scrolling rhythm", "Un défilement tranquille"))
                        .font(.caption).foregroundStyle(MorningStyle.muted)
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
                Text(text("Only this page. This estimate does not replay your gestures.",
                          "Cette page seulement. Cette estimation ne reproduit pas vos gestes."))
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                if rhythmSaveFailed {
                    Text(text("Couldn't save yet. Try Save again.", "Enregistrement impossible. Réessayez."))
                        .font(.caption).foregroundStyle(MorningStyle.accent)
                }
            } else {
                Text(text("Browse as you normally do. MORE counts gestures here, without saving page text or form entries.",
                          "Naviguez à votre rythme. MORE compte ici les gestes, sans garder le texte ni les champs saisis."))
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                Button(text("Learn my pace", "Apprendre mon rythme")) {
                    Task { _ = await controller.startLearning() }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!controller.canLearn)
                    .accessibilityIdentifier("web.learningStart")
                if !controller.canLearn {
                    Text(text("Finish signing in and wait for the page to load.", "Terminez la connexion et attendez le chargement."))
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let line = resultLine {
                if case .headlines = controller.outcome {
                    ScrollView { Text(line).font(.footnote).foregroundStyle(MorningStyle.muted).frame(maxWidth: .infinity, alignment: .leading) }
                        .frame(maxHeight: 110).accessibilityIdentifier("web.result")
                } else {
                    Text(line).font(.footnote).foregroundStyle(MorningStyle.muted)
                        .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("web.result")
                }
            }
            HStack(spacing: 4) {
                ForEach(site.table.tasks, id: \.self) { task in
                    Button { Task { await controller.run(task) } } label: {
                        MorningDottedIcon(systemName: symbol(for: task)).frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(title(for: task))
                    .disabled(controller.isRunning || controller.isLearning || controller.isClearing || controller.isSignInPage || !controller.actionsEnabled)
                    .accessibilityIdentifier("web.\(task.rawValue)")
                }
                Button { controller.reload() } label: {
                    MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 23, height: 23).frame(width: 44, height: 44)
                }.accessibilityLabel(text("Reload page", "Recharger la page")).accessibilityIdentifier("web.reload")
                Button { showingAbout = true } label: {
                    MorningDottedIcon(systemName: "info.circle").frame(width: 23, height: 23).frame(width: 44, height: 44)
                }.accessibilityLabel(text("About this screen", "À propos de cet écran"))
                Spacer(minLength: 0)
                Button {
                    if let onExtend { onExtend() } else { clock.extend(at: Date()) }
                } label: { Text("+2").font(.subheadline.monospacedDigit()).frame(width: 44, height: 44) }
                    .accessibilityLabel(text("Add two minutes", "Ajouter deux minutes"))
                    .disabled(!isStepActive).accessibilityIdentifier("web.extend")
                if let onNext {
                    Button(action: onNext) {
                        MorningDottedIcon(systemName: "arrow.right").frame(width: 25, height: 25).frame(width: 44, height: 44)
                    }.accessibilityLabel(text("Next step", "Étape suivante"))
                        .disabled(!isStepActive).accessibilityIdentifier("web.nextMoment")
                }
            }
        }
        .buttonStyle(.plain).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var resultLine: String? {
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
                    Text(text("You sign in. Each MORE action needs a tap.",
                              "Vous vous connectez. Chaque action de MORE demande un appui."))
                        .font(MorningTheme.Typography.body)
                    DisclosureGroup(text("Privacy & website controls", "Confidentialité et commandes du site")) {
                        Text(text("MORE’s scripts never read password fields or send messages. The site keeps its sign-in in this browser. Its own controls still work.",
                                  "Les scripts de MORE ne lisent jamais les mots de passe et n’envoient pas de message. Le site garde sa session dans ce navigateur. Ses propres boutons restent actifs."))
                            .font(.footnote).foregroundStyle(MorningStyle.muted).padding(.top, 8)
                    }.font(.subheadline)
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
