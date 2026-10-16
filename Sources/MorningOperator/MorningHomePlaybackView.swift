import SwiftUI
import MorningCore
import MorningApple

/// The landscape remains Home. Only spoken passages and a few controls sit over it.
struct MorningHomePlaybackView: View {
    @Bindable var store: MorningStore
    let openSettings: () -> Void
    @State private var displayedCaption: String?
    @State private var isUserCaption = false
    @State private var controlsVisible = false
    @State private var controlsInteraction = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    private var french: Bool { AppLanguage.isFrench }
    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return reduceMotion
    }
    private var fallback: String {
        #if MORE_JURY_DEMO
        if store.currentStep?.detail == "Sommeil et météo préparés pour cette démonstration." {
            return String(localized: "Sleep, weather and a few tips to start your day.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
        #endif
        if let opening = store.currentOpening {
            return opening.briefText ?? opening.opening?.displayText
                ?? (french ? "Je prépare votre journée…" : "Preparing your day…")
        }
        return store.connectedActionStatus ?? store.currentStep?.detail ?? ""
    }
    private var caption: String {
        guard scenePhase != .background, !store.privacyBlocksWork else { return "" }
        #if MORE_JURY_DEMO
        if store.juryDemoVoice.state == .failed { return store.juryDemoVoice.message }
        if !store.juryDemoCaption.isEmpty { return store.juryDemoCaption }
        if store.juryDemoVoice.isActive { return store.juryDemoVoice.message }
        #else
        if store.cloudVoice.isActive, let text = store.cloudVoice.userCaption { return SpeechCoordinator.inputCaption(text) }
        if store.cloudVoice.isActive, let text = store.cloudVoice.caption, !text.isEmpty { return text }
        #endif
        if isUserCaption, let displayedCaption { return displayedCaption }
        if let notice = store.notice, !notice.isEmpty { return notice }
        if let displayedCaption { return displayedCaption }
        let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 110 else { return text }
        let preview = text.prefix(110)
        let end = preview.lastIndex(where: { $0.isWhitespace }) ?? preview.endIndex
        return String(preview[..<end]) + "…"
    }
    private var showingInput: Bool {
        #if MORE_JURY_DEMO
        return isUserCaption || !store.juryDemoVoice.transcript.isEmpty
        #else
        return isUserCaption || (store.cloudVoice.isActive && store.cloudVoice.userCaption != nil)
        #endif
    }
    private var controlsLabel: String {
        controlsVisible ? (french ? "Masquer les commandes" : "Hide controls")
            : (french ? "Afficher les commandes" : "Show controls")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView {
                    Text(verbatim: caption)
                        .font(.raleway(.title2)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 540, minHeight: max(0, geometry.size.height - 160), alignment: .leading)
                        .padding(.horizontal, 28).padding(.vertical, 80)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.opacity)
                        .animation(showingInput ? nil : .easeOut(duration: still ? 0.12 : 0.22), value: caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("morning.caption")
                        #if DEBUG
                        .accessibilityValue(store.uiTestSessionSnapshot)
                        #endif
                        .accessibilityAction(named: Text(controlsLabel), toggleControls)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleControls)
                .accessibilityIdentifier("morning.captions")
                #if DEBUG
                .accessibilityValue(ProcessInfo.processInfo.arguments.contains("--ui-testing")
                    ? "\(store.session?.id.uuidString ?? "")|\(store.currentStep?.id.uuidString ?? "")" : "")
                #endif
                .accessibilityAction(named: Text(controlsLabel), toggleControls)

                if controlsVisible {
                    controls
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: store.speech.captionRevision, initial: true) { _, _ in
            guard let text = store.speech.currentCaption, !text.isEmpty else { return }
            isUserCaption = false
            // The spoken step label is metadata; Home shows only its content.
            let prefix = (store.currentStep?.title ?? "") + "."
            displayedCaption = text.hasPrefix(prefix)
                ? String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines) : text
        }
        .onChange(of: store.handsFreeVoice.transcriptRevision) { _, _ in
            let text = store.handsFreeVoice.transcript
            if !text.isEmpty { showInput(text) }
            else if isUserCaption { clearCaption() }
        }
        .onChange(of: AppLanguage.code) { _, _ in clearCaption(); controlsVisible = false }
        .onChange(of: store.dataGeneration) { _, _ in clearCaption() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clearCaption(); controlsVisible = false }
        }
        .onChange(of: store.briefing.settings.includesHealth) { wasIncluded, included in
            if wasIncluded && !included { clearCaption() }
        }
        .onDisappear { clearCaption(); controlsVisible = false }
        #if DEBUG
        .task { await playCaptionFixtureIfRequested() }
        #endif
        .onChange(of: voiceOverEnabled) { _, _ in if controlsVisible { controlsInteraction = UUID() } }
        .task(id: controlsInteraction) {
            guard controlsVisible, !voiceOverEnabled else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !voiceOverEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
        }
    }

    private func showInput(_ text: String) {
        displayedCaption = SpeechCoordinator.inputCaption(text)
        isUserCaption = true
    }

    private func clearCaption() { displayedCaption = nil; isUserCaption = false }

    #if DEBUG
    /// Presentation-only hypotheses; this fixture does not exercise a microphone.
    private func playCaptionFixtureIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("--ui-testing"),
              ProcessInfo.processInfo.arguments.contains("--ui-testing-live-captions") else { return }
        let hypotheses = ["Je", "Je voudrais", "Je voudrais connaître mon prochain rendez-vous.",
            "Je voudrais connaître mes prochains rendez-vous.",
            String(repeating: "Je voudrais revoir les messages de ce matin, ", count: 8)
                + "puis prépare une réponse pour demain matin."]
        do {
            for text in hypotheses {
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                showInput(text)
            }
            try await Task.sleep(for: .seconds(4))
            try Task.checkCancellation()
            isUserCaption = false
            displayedCaption = "Votre prochain rendez-vous est à neuf heures."
        } catch { }
    }
    #endif

    private func toggleControls() {
        withAnimation(.easeOut(duration: 0.15)) { controlsVisible.toggle() }
        controlsInteraction = UUID()
    }

    private func keepControlsVisible() {
        controlsVisible = true
        controlsInteraction = UUID()
    }

    private var controls: some View {
        ZStack {
            let offersPlay = store.currentOpening != nil || store.session?.status == .paused
            Button {
                keepControlsVisible()
                if store.currentOpening != nil { store.chooseOpening(.ritual) }
                else if store.session?.status == .paused { store.resume() }
                else { store.pause() }
            } label: {
                MorningFloatingGlassSymbol(symbol: offersPlay ? .play : .pause, size: 48)
                    .frame(width: 88, height: 88).contentShape(Rectangle())
            }
            .accessibilityLabel(offersPlay ? (french ? "Continuer" : "Continue") : "Pause")
            .accessibilityIdentifier("morning.playback")

            Button(action: openSettings) {
                MorningFloatingGlassSymbol(symbol: .settings, size: 28)
                    .frame(width: 48, height: 48).contentShape(Rectangle())
            }
            .accessibilityLabel(french ? "Paramètres" : "Settings")
            .accessibilityIdentifier("morning.settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, 20).padding(.trailing, 20)
        }
        .buttonStyle(.plain)
    }
}

/// Session commands live in Settings; Home keeps only playback and navigation.
struct MorningRoutineControlsView: View {
    @Bindable var store: MorningStore
    @State private var showingDetails = false
    @Environment(\.scenePhase) private var scenePhase
    private var french: Bool { AppLanguage.isFrench }
    private var fallback: String {
        if let opening = store.currentOpening {
            return opening.briefText ?? opening.opening?.displayText
                ?? (french ? "Je prépare votre journée…" : "Preparing your day…")
        }
        return store.connectedActionStatus ?? store.currentStep?.detail ?? ""
    }

    var body: some View {
        Group {
            if store.sessionActive {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        if store.currentOpening != nil { store.chooseOpening(.ritual) }
                        else if store.session?.status == .paused { store.resume() }
                        else { store.pause() }
                    } label: {
                        Label(store.currentOpening != nil || store.session?.status == .paused
                              ? (french ? "Continuer" : "Continue") : "Pause",
                              systemImage: store.currentOpening != nil || store.session?.status == .paused ? "play.fill" : "pause.fill")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("morning.playback")
                    Button {
                        store.nextTargetStep(sessionID: store.session?.id, stepID: store.currentStep?.id)
                    } label: {
                        Label(french ? "Suivant" : "Next", systemImage: "forward.end")
                            .frame(minHeight: 44)
                    }.accessibilityIdentifier("morning.next")
                    if let timer = store.activeStepTimer {
                        Button {
                            Task { await store.extendStepTimer(expectedTimer: timer) }
                        } label: {
                            Text("+2 min").frame(minHeight: 44)
                        }.accessibilityIdentifier("morning.extend")
                    }
                    if case let .inAppWeb(url) = store.currentStep?.target {
                        Button {
                            store.pendingWebTarget = url
                        } label: {
                            Text(french ? "Ouvrir la page" : "Open page").frame(minHeight: 44)
                        }.accessibilityIdentifier("stepTimer.openPage")
                    }
                    Button { showingDetails = true } label: {
                        Text(french ? "Interagir" : "Interact").frame(minHeight: 44)
                    }.accessibilityIdentifier("morning.details")
                    Button(role: .destructive) { store.stop() } label: {
                        Text(french ? "Arrêter mon matin" : "Stop my morning").frame(minHeight: 44)
                    }.accessibilityIdentifier("morning.stop")
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: showingDetails) { _, presented in
            store.morningDetailPresented = presented
            if presented { store.pause() }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { showingDetails = false } }
        .onChange(of: AppLanguage.code) { _, _ in showingDetails = false }
        .onChange(of: store.currentStep?.id) { _, _ in showingDetails = false }
        .onChange(of: store.sessionActive) { _, active in if !active { showingDetails = false } }
        .onChange(of: store.dataGeneration) { _, _ in showingDetails = false }
        .onDisappear { store.morningDetailPresented = false }
        .sheet(isPresented: $showingDetails) { interaction }
    }

    private var interaction: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !fallback.isEmpty {
                        Text(fallback).textSelection(.enabled)
                            .accessibilityIdentifier(store.connectedActionStatus == nil ? "moment.instructions" : "moment.connectedResult")
                    }
                    if store.currentStep?.automation == .gmailInbox { MorningMailMomentView(store: store) }
                    NativeMomentReviewView(store: store)
                    if store.currentSlackContext != nil { SlackMomentReplyView(store: store) }
                    if store.currentGoogleCalendarDayContext != nil { GoogleCalendarDayMomentView(store: store) }
                    if store.currentCalendlyDayContext != nil { CalendlyDayMomentView(store: store) }
                    if store.currentOutlookInboxContext != nil { OutlookInboxMomentView(store: store) }
                    if store.session?.status == .paused,
                       store.currentStep?.automation == .todayCalendar || store.currentStep?.automation == .morningBriefing {
                        Button(String(localized: "Update this recap", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { store.updateCurrentBriefing() }
                            .disabled(store.nativeMoment.isActive || store.voiceInputBlocksPlayback)
                            .accessibilityIdentifier("briefing.updateCurrent")
                    }
                    Text(store.handsFreeVoiceStatus).font(.caption).accessibilityIdentifier("morning.voiceStatus")
                }.padding(24).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            .background(MorningPaper(showsSun: false))
            .navigationTitle(store.currentStep?.title ?? "MORE").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(french ? "Fermer" : "Close") { showingDetails = false }
                    .accessibilityIdentifier("morning.closeDetails")
            } }
        }
    }
}
