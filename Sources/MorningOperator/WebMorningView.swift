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

    @State private var controller: WebMorningController
    @State private var clock: WebMorningStepClock
    @State private var showingAbout = false
    @AppStorage("webMorning.explained") private var explained = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    init(site: WebMorningSite, minutes: Int, initialURL: URL? = nil, isStepActive: Bool = true,
         stepEndsAt: Date? = nil, timerPausedAt: Date? = nil, onExtend: (() -> Void)? = nil,
         onNext: (() -> Void)? = nil, onClose: @escaping () -> Void) {
        self.site = site; self.isStepActive = isStepActive; self.stepEndsAt = stepEndsAt; self.timerPausedAt = timerPausedAt
        self.onExtend = onExtend; self.onNext = onNext; self.onClose = onClose
        _controller = State(initialValue: WebMorningController(site: site, initialURL: initialURL))
        _clock = State(initialValue: WebMorningStepClock(start: Date(), minutes: minutes))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            WebMorningWebView(webView: controller.webView).accessibilityIdentifier("web.page")
            Divider()
            bottomBar
        }
        .background(Color(uiColor: .systemBackground))
        .sheet(isPresented: $showingAbout) { about }
        .onAppear {
            controller.startIfNeeded()
            controller.actionsEnabled = isStepActive && scenePhase == .active
            if !explained { showingAbout = true }
        }
        .onChange(of: scenePhase) { _, phase in controller.actionsEnabled = isStepActive && phase == .active && !showingAbout }
        .onChange(of: isStepActive) { _, active in controller.actionsEnabled = active && scenePhase == .active && !showingAbout }
        .onChange(of: showingAbout) { _, presented in controller.actionsEnabled = !presented && isStepActive && scenePhase == .active }
        .onDisappear { controller.actionsEnabled = false }
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button(action: onClose) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                    .accessibilityLabel(text("Close", "Fermer")).accessibilityIdentifier("web.close")
                VStack(alignment: .leading, spacing: 2) {
                    Text(site.displayName).font(.headline).lineLimit(1)
                    Text(controller.displayedHost).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("web.host")
                }
                Spacer(minLength: 4)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, (stepEndsAt ?? clock.endsAt).timeIntervalSince(timerPausedAt ?? context.date))
                    Text(Duration.seconds(left.rounded(.up)), format: .time(pattern: .minuteSecond))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(left == 0 ? Color.orange : Color.secondary)
                        .accessibilityIdentifier("web.remaining")
                }
            }
            HStack {
                Button(text("+2 min", "+2 min")) {
                    if let onExtend { onExtend() } else { clock.extend(at: Date()) }
                }.disabled(!isStepActive).accessibilityIdentifier("web.extend")
                Spacer()
                if let onNext {
                    Button(action: onNext) { Label(text("Next step", "Étape suivante"), systemImage: "arrow.right") }
                        .disabled(!isStepActive).accessibilityIdentifier("web.nextMoment")
                }
            }
        }
        .buttonStyle(.borderless).padding(.horizontal, 16).padding(.bottom, 10)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let line = resultLine {
                ScrollView { Text(line).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 130).accessibilityIdentifier("web.result")
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { actionButtons }
                VStack(alignment: .leading, spacing: 12) { actionButtons }
            }
        }
        .buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var actionButtons: some View {
        ForEach(site.table.tasks, id: \.self) { task in
            Button { Task { await controller.run(task) } } label: { Label(title(for: task), systemImage: symbol(for: task)) }
                .disabled(controller.isRunning || controller.isClearing || controller.isSignInPage || !controller.actionsEnabled)
                .accessibilityIdentifier("web.\(task.rawValue)")
        }
        Button { controller.reload() } label: { Image(systemName: "arrow.clockwise") }
            .accessibilityLabel(text("Reload page", "Recharger la page")).accessibilityIdentifier("web.reload")
        Button { showingAbout = true } label: { Image(systemName: "info.circle") }
            .accessibilityLabel(text("About this screen", "À propos de cet écran"))
    }

    private var resultLine: String? {
        if controller.loadFailed { return text("Page could not load. Try reload.", "La page ne charge pas. Réessayez.") }
        if controller.isSignInPage { return text("Sign in on the page. MORE waits.", "Connectez-vous sur la page. MORE attend.") }
        switch controller.outcome {
        case .count(let n): return text("Unread shown on this page: \(n)", "Non lus affichés sur cette page : \(n)")
        case .headlines(let list): return list.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        case .scrollRequested: return text("Scroll requested. Check the page.", "Défilement demandé. Vérifiez la page.")
        case .unsupported(let reason):
            return reason == "signin" ? text("Sign in first.", "Connectez-vous d’abord.")
                : text("This page isn’t supported right now.", "Cette page n’est pas prise en charge pour l’instant.")
        case .refused(.notTheFeed): return text("Opening videos. Tap again when ready.", "Ouverture des vidéos. Touchez à nouveau quand elles sont prêtes.")
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
                VStack(alignment: .leading, spacing: 14) {
                    Text(text("Sign in on the site’s own page. MORE’s scripts never read password fields. The site keeps its session in this app’s browser.",
                              "Connectez-vous sur la page du site. Les scripts de MORE ne lisent jamais les mots de passe. Le site garde sa session dans ce navigateur."))
                    Text(text("Each MORE action needs a tap: read a count, show headlines, or scroll once. MORE never clicks social buttons or sends messages.",
                              "Chaque action de MORE demande un appui : lire un nombre, afficher les titres ou défiler une fois. MORE ne touche pas aux boutons sociaux et n’envoie pas de message."))
                    Text(text("You can use the website yourself. Its own controls still work.",
                              "Vous pouvez utiliser le site vous-même. Ses propres boutons restent actifs."))
                    Button(text("Clear all website sign-ins", "Effacer toutes les connexions aux sites"), role: .destructive) {
                        Task { await controller.forgetSignIns() }
                    }.accessibilityIdentifier("web.forget")
                }.padding(24)
            }
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
}

private struct WebMorningWebView: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
