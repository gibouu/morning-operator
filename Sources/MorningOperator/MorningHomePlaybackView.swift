import SwiftUI
import MorningCore
import MorningApple

/// The landscape remains Home. Only spoken passages and a few controls sit over it.
struct MorningHomePlaybackView: View {
    @Bindable var store: MorningStore
    let openSettings: () -> Void
    @State private var displayedCaption: String?
    @State private var displayedCaptionBoundary: String?
    @State private var controlsVisible = false
    @State private var controlsInteraction = UUID()
    @State private var captionScrolling = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.scenePhase) private var scenePhase

    private struct ActionStatus {
        let text: String
        var priority = 2
    }

    /// State may change without TTS. Only this exact session/step can supply it;
    /// uncertain effects take precedence over an older dialogue's review/error.
    private var actionStatus: ActionStatus? {
        guard !store.privacyBlocksWork, store.sessionActive, let session = store.session, let step = store.currentStep else { return nil }
        let context = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
        var statuses: [ActionStatus] = []
        let native = store.nativeMoment
        if native.context == context {
            switch native.phase {
            case .writing: statuses.append(.init(text: french ? "Écriture Apple en cours. Attendez son résultat." : "Apple write in progress. Wait for its result.", priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "Le résultat de l’écriture Apple n’est pas confirmé. Vérifiez Rappels ou Calendrier avant une autre tentative." : "The Apple write is unconfirmed. Check Reminders or Calendar before another attempt.", priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Apple est indisponible. Retrouvez les détails dans Interagir." : "This Apple request is unavailable. Open Interact for details.", priority: 0))
            case .completed: statuses.append(.init(text: french ? "Cette demande Apple est terminée." : "This Apple request is finished.", priority: 1))
            case .reviewing, .awaitingConfirmation, .needsDetails, .choosingReminder:
                statuses.append(.init(text: french ? "Une demande Apple attend votre revue ou vos précisions." : "An Apple request is waiting for your review or details."))
            default: break
            }
        }
        if store.currentSlackContext == context, store.slackReply.context == context {
            switch store.slackReply.phase {
            case .sending: statuses.append(.init(text: french ? "Envoi Slack en cours. Attendez son résultat." : "Slack send in progress. Wait for its result.", priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "La publication Slack n’est pas confirmée. MORE ne la relance pas. Vérifiez le fil." : "The Slack post is unconfirmed. MORE will not retry it. Check the thread.", priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Slack est indisponible. Retrouvez les détails dans Interagir." : "This Slack request is unavailable. Open Interact for details.", priority: 0))
            case .completed: statuses.append(.init(text: french ? "La réponse Slack a été publiée. Retrouvez les détails dans Interagir." : "The Slack reply was posted. Open Interact for details.", priority: 1))
            case .preparing: statuses.append(.init(text: french ? "Préparation de votre réponse Slack…" : "Preparing your Slack reply…"))
            case .reviewing, .awaitingConfirmation: statuses.append(.init(text: french ? "Une réponse Slack attend vos précisions ou votre relecture." : "A Slack reply is waiting for your details or review."))
            default: break
            }
        }
        if step.automation == .gmailInbox, store.mailMorning.context == context {
            switch store.mailMorning.state {
            case .preparing: statuses.append(.init(text: french ? "Je prépare votre bilan Gmail…" : "Preparing your Gmail reading…"))
            case .sending: statuses.append(.init(text: french ? "Envoi du mail en cours. Attendez son résultat." : "Mail send in progress. Wait for its result.", priority: 3))
            case .uncertain: statuses.append(.init(text: french ? "L’envoi du mail n’est pas confirmé. MORE ne le relance pas. Vérifiez Gmail." : "The mail send is unconfirmed. MORE will not retry it. Check Gmail.", priority: 4))
            case .unavailable: statuses.append(.init(text: french ? "Cette demande Gmail est indisponible. Retrouvez les détails dans Interagir." : "This Gmail request is unavailable. Open Interact for details.", priority: 0))
            case .completed: statuses.append(.init(text: french ? "Cette demande Gmail est terminée." : "This Gmail request is finished.", priority: 1))
            case .preparingReply: statuses.append(.init(text: french ? "Préparation de votre mail…" : "Preparing your mail…"))
            case .reviewingReply, .reviewingSelfMessage: statuses.append(.init(text: french ? "Un brouillon Gmail attend vos précisions ou votre relecture." : "A Gmail draft is waiting for your details or review."))
            default: break
            }
        }
        return statuses.max { $0.priority < $1.priority }
    }

    private var showingActionStatus: Bool {
        guard let status = actionStatus else { return false }
        return displayedCaption?.isEmpty != false || displayedCaptionBoundary != status.text
    }

    private var french: Bool { AppLanguage.isFrench }
    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return reduceMotion
    }
    private var fallback: String {
        if let opening = store.currentOpening {
            return opening.briefText ?? opening.opening?.displayText
                ?? (french ? "Je prépare votre journée…" : "Preparing your day…")
        }
        return store.connectedActionStatus ?? store.currentStep?.detail ?? ""
    }
    private var caption: String {
        if showingActionStatus, let status = actionStatus { return status.text }
        if actionStatus != nil, let displayedCaption, displayedCaptionBoundary == actionStatus?.text { return displayedCaption }
        if let notice = store.notice, !notice.isEmpty { return notice }
        if let displayedCaption { return displayedCaption }
        let text = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count > 110 else { return text }
        let preview = text.prefix(110)
        let end = preview.lastIndex(where: { $0.isWhitespace }) ?? preview.endIndex
        return String(preview[..<end]) + "…"
    }
    private var controlsLabel: String {
        controlsVisible ? (french ? "Masquer les commandes" : "Hide controls")
            : (french ? "Afficher les commandes" : "Show controls")
    }

    #if DEBUG
    private var uiTestExecutionIdentity: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return "" }
        let identity = "\(store.session?.id.uuidString ?? "")|\(store.currentStep?.id.uuidString ?? "")"
        guard arguments.contains("--ui-testing-ten-moments"), arguments.contains("--ui-testing-automation") else {
            return identity
        }
        return identity + "|\(store.session?.routine.id.uuidString ?? "")|\(store.session?.currentStepIndex ?? -1)"
    }
    #endif

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
                        .animation(.easeOut(duration: still ? 0.12 : 0.22), value: caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(showingActionStatus ? "morning.actionStatus" : "morning.caption")
                        .accessibilityAction(named: Text(controlsLabel), toggleControls)
                }
                .scrollIndicators(.hidden)
                .onScrollPhaseChange { _, phase in
                    let wasScrolling = captionScrolling
                    captionScrolling = phase == .tracking || phase == .interacting || phase == .decelerating
                    if controlsVisible, captionScrolling || wasScrolling { controlsInteraction = UUID() }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: toggleControls)
                .accessibilityIdentifier("morning.captions")
                #if DEBUG
                .accessibilityValue(uiTestExecutionIdentity)
                #endif
                .accessibilityAction(named: Text(controlsLabel), toggleControls)

                if controlsVisible {
                    controls
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: store.speech.captionRevision, initial: true) { _, _ in
            guard !store.privacyBlocksWork, let text = store.speech.currentCaption, !text.isEmpty else { return }
            displayedCaptionBoundary = actionStatus?.text
            // The spoken step label is metadata; Home shows only its content.
            let prefix = store.currentStep.map { $0.title + "." } ?? ""
            displayedCaption = store.speech.caption(omittingInitialPrefix: prefix) ?? ""
        }
        .onChange(of: actionStatus?.text) { _, boundary in
            if displayedCaptionBoundary != boundary { displayedCaption = nil }
        }
        .onChange(of: store.speech.isSpeaking) { _, speaking in
            if !speaking, (actionStatus?.priority ?? -1) >= 3 { displayedCaption = nil; displayedCaptionBoundary = nil }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { displayedCaption = nil; displayedCaptionBoundary = nil; controlsVisible = false; captionScrolling = false }
        }
        .onChange(of: AppLanguage.code) { _, _ in displayedCaption = nil; displayedCaptionBoundary = nil }
        .onDisappear { controlsVisible = false; captionScrolling = false }
        .onChange(of: voiceOverEnabled) { _, _ in if controlsVisible { controlsInteraction = UUID() } }
        .task(id: controlsInteraction) {
            guard controlsVisible, !voiceOverEnabled, !captionScrolling else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !voiceOverEnabled, !captionScrolling else { return }
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
        }
    }

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
        .preferredColorScheme(.light)
    }
}
