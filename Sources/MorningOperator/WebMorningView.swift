import MorningCore
import SwiftUI
import WebKit

/// A routine moment that opens a website inside MORE ("Instagram in MORE · 10 min").
/// The person signs in on the site's own page, sees the page the whole time and starts
/// every action. Auto-advance runs only after they turn it on, and stops when the moment
/// ends, when they leave the screen, or when the phone locks.
struct WebMorningView: View {
    let site: WebMorningSite
    let minutes: Int
    /// True while this moment is the running step of the morning.
    var isStepActive: Bool = true
    /// Moves the morning to its next moment. Nil when the screen is opened on its own.
    var onNext: (() -> Void)?
    var onClose: () -> Void
    #if DEBUG
    /// Measurement runs from a launch argument; never set in a routine.
    var autorun = false
    #endif

    @State private var controller: WebMorningController
    @State private var clock: WebMorningStepClock
    @State private var autoSeconds = 6
    @State private var showingAbout = false
    @AppStorage("webMorning.explained") private var explained = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    init(site: WebMorningSite, minutes: Int, isStepActive: Bool = true,
         onNext: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.site = site; self.minutes = minutes; self.isStepActive = isStepActive
        self.onNext = onNext; self.onClose = onClose
        _controller = State(initialValue: WebMorningController(site: site))
        _clock = State(initialValue: WebMorningStepClock(start: Date(), minutes: minutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            WebMorningWebView(webView: controller.webView)
                .accessibilityIdentifier("web.page")
            Divider()
            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showingAbout) { about }
        .onAppear {
            #if DEBUG
            if autorun { return }
            #endif
            if !explained { showingAbout = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { controller.stopAutoAdvance() } }
        .onChange(of: isStepActive) { _, active in if !active { controller.stopAutoAdvance() } }
        .onDisappear { controller.stopAutoAdvance() }
        #if DEBUG
        .task(id: controller.pageLoads) { if autorun { await measure() } }
        #endif
    }

    // MARK: Bars

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { onClose() } label: { Image(systemName: "xmark").frame(width: 32, height: 32) }
                .accessibilityLabel(text("Close", "Fermer")).accessibilityIdentifier("web.close")
            Text(site.displayName).font(.headline).lineLimit(1)
            Spacer(minLength: 4)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = clock.remaining(at: context.date)
                Text(Duration.seconds(left.rounded(.up)), format: .time(pattern: .minuteSecond))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(left == 0 ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("web.remaining")
                    .onChange(of: left == 0) { _, over in if over { controller.stopAutoAdvance() } }
            }
            Button(text("+2 min", "+2 min")) { clock.extend(at: Date()); controller.stepEndsAt = clock.endsAt }
                .accessibilityIdentifier("web.extend")
            if let onNext {
                Button { controller.stopAutoAdvance(); onNext() } label: {
                    Label(text("Next", "Suivant"), systemImage: "arrow.right")
                }.accessibilityIdentifier("web.nextMoment")
            }
        }
        .buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = resultLine {
                Text(line).font(.footnote).foregroundStyle(.secondary).lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("web.result")
            }
            HStack(spacing: 16) {
                ForEach(site.table.tasks, id: \.self) { task in
                    if task == .nextVideo { videoControls } else {
                        Button { Task { await controller.run(task) } } label: { Label(title(for: task), systemImage: symbol(for: task)) }
                            .disabled(controller.isRunning || controller.isSignInPage)
                            .accessibilityIdentifier("web.\(task.rawValue)")
                    }
                }
                Spacer(minLength: 0)
                Button { showingAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel(text("About this screen", "À propos de cet écran"))
            }
        }
        .buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var videoControls: some View {
        Button { Task { await controller.run(.nextVideo) } } label: {
            Label(text("Next video", "Vidéo suivante"), systemImage: "arrow.down")
        }
        .disabled(controller.isRunning || controller.isSignInPage)
        .accessibilityIdentifier("web.nextVideo")
        if controller.isAutoAdvancing {
            Button { controller.stopAutoAdvance() } label: {
                Label(text("Auto-advance · stop", "Défilement auto · arrêter"), systemImage: "stop.fill")
            }.tint(.orange).accessibilityIdentifier("web.autoStop")
        } else {
            Menu {
                ForEach([4, 6, 10, 20], id: \.self) { seconds in
                    Button(text("Every \(seconds) s", "Toutes les \(seconds) s")) { startAuto(seconds) }
                }
            } label: { Label(text("Auto", "Auto"), systemImage: "timer") }
                .disabled(controller.isSignInPage || !isStepActive || clock.isOver(at: Date()))
                .accessibilityIdentifier("web.autoStart")
        }
    }

    private func startAuto(_ seconds: Int) {
        autoSeconds = seconds
        controller.stepEndsAt = clock.endsAt
        controller.startAutoAdvance(every: seconds)
    }

    // MARK: Text

    private var resultLine: String? {
        let advanced = controller.tracker.attempts > 0
            ? text("Moved \(controller.tracker.advanced) of \(controller.tracker.attempts)",
                   "Avancé \(controller.tracker.advanced) sur \(controller.tracker.attempts)") : nil
        if controller.isSignInPage { return text("Sign in on the page. MORE waits.", "Connectez-vous sur la page. MORE attend.") }
        switch controller.outcome {
        case .count(let n): return text("Unread: \(n)", "Non lus : \(n)")
        case .headlines(let list): return list.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .scrolled: return advanced
        case .unsupported(let reason):
            return reason == "signin" ? text("Sign in first.", "Connectez-vous d’abord.")
                : text("This page isn’t supported right now.", "Cette page n’est pas prise en charge pour l’instant.")
        case .refused(let refusal):
            switch refusal {
            case .notTheFeed: return text("Opening the videos…", "Ouverture des vidéos…")
            case .signInPage: return text("Sign in on the page. MORE waits.", "Connectez-vous sur la page. MORE attend.")
            default: return text("Not on this page.", "Pas sur cette page.")
            }
        case nil: return advanced
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
            VStack(alignment: .leading, spacing: 14) {
                Text(text("You sign in yourself, on \(site.displayName)’s own page. MORE never sees or keeps your password.",
                          "Vous vous connectez vous-même, sur la page de \(site.displayName). MORE ne voit ni ne garde votre mot de passe."))
                Text(text("MORE acts only when you ask: read an unread count, show headlines, or move to the next video.",
                          "MORE n’agit que si vous le demandez : lire un nombre de non lus, afficher les titres, passer à la vidéo suivante."))
                Text(text("It never likes, follows, comments, posts or sends.",
                          "Il n’aime, ne suit, ne commente, ne publie et n’envoie jamais rien."))
                Text(text("Auto-advance runs only while you watch, and stops when this moment ends.",
                          "Le défilement auto ne tourne que pendant que vous regardez, et s’arrête à la fin de ce moment."))
                Spacer()
                Button(text("Sign out of all sites", "Se déconnecter de tous les sites"), role: .destructive) {
                    Task { await controller.forgetSignIns() }
                }.accessibilityIdentifier("web.forget")
            }
            .font(.body).padding(24).frame(maxWidth: .infinity, alignment: .leading)
            .navigationTitle(text("\(site.displayName) in MORE", "\(site.displayName) dans MORE"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Got it", "Compris")) { explained = true; showingAbout = false }
                        .accessibilityIdentifier("web.aboutDone")
                }
            }
        }.presentationDetents([.medium, .large])
    }

    private func text(_ english: String, _ french: String) -> String {
        locale.language.languageCode?.identifier == "fr" ? french : english
    }

    #if DEBUG
    /// Launch-argument measurement: wait for a settled page, then run each offered task.
    /// Logs carry counts only. Nothing runs on a sign-in page.
    private func measure() async {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled, !controller.isSignInPage else { return }
        for task in site.table.tasks where task != .nextVideo { await controller.run(task) }
        guard site.table.tasks.contains(.nextVideo) else { return }
        if WebMorningPolicy.refusal(for: .nextVideo, on: site, at: controller.webView.url) == .notTheFeed {
            controller.openFeed(); return
        }
        controller.stepEndsAt = clock.endsAt
        for _ in 0..<6 {
            guard !Task.isCancelled else { return }
            await controller.run(.nextVideo)
            try? await Task.sleep(for: .seconds(4))
        }
        print("WEBMORNING site=\(site.rawValue) task=nextVideo advanced=\(controller.tracker.advanced) attempts=\(controller.tracker.attempts)")
    }
    #endif
}

private struct WebMorningWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
