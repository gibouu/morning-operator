import SwiftUI
import MorningCore
import MorningApple

/// The landscape remains Home. Only spoken passages and a few controls sit over it.
struct MorningHomePlaybackView: View {
    @Bindable var store: MorningStore
    let openSettings: () -> Void
    @State private var displayedCaption: String?
    @State private var displayedCaptionBoundary: String?
    @State private var pendingCloudCaption: String?
    @State private var isUserCaption = false
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
        guard !showingInput, let status = actionStatus else { return false }
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
        #if !MORE_JURY_DEMO
        if store.cloudVoice.isActive, let text = store.cloudVoice.userCaption { return SpeechCoordinator.inputCaption(text) }
        #endif
        if isUserCaption, let displayedCaption { return displayedCaption }
        if showingActionStatus, let status = actionStatus { return status.text }
        if actionStatus != nil, let displayedCaption, displayedCaptionBoundary == actionStatus?.text { return displayedCaption }
        if actionStatus == nil {
            #if MORE_JURY_DEMO
            if store.juryDemoVoice.state == .failed { return store.juryDemoVoice.message }
            if !store.juryDemoCaption.isEmpty { return store.juryDemoCaption }
            if store.juryDemoVoice.isActive { return store.juryDemoVoice.message }
            #else
            if store.cloudVoice.isActive, let text = store.cloudVoice.caption, !text.isEmpty { return text }
            #endif
        }
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

    #if DEBUG
    private var uiTestExecutionIdentity: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return "" }
        let identity = "\(store.session?.id.uuidString ?? "")|\(store.currentStep?.id.uuidString ?? "")"
        guard (arguments.contains("--ui-testing-ten-moments") && arguments.contains("--ui-testing-automation")) ||
                SlackSetupUITestFixture.integratedJourneyRequested else {
            return identity
        }
        let execution = identity + "|\(store.session?.routine.id.uuidString ?? "")|\(store.session?.currentStepIndex ?? -1)"
        guard SlackSetupUITestFixture.integratedJourneyRequested else { return execution }
        // Private mixed-journey proof only. No title, caption or message body;
        // exact Date bits distinguish a retained remainder from a fresh budget.
        guard let timer = store.activeStepTimer else { return execution + "|none|none|none" }
        let start = String(timer.startedAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
        let end = String(timer.endsAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
        let paused = timer.pausedAt.map { String($0.timeIntervalSinceReferenceDate.bitPattern, radix: 16) } ?? "none"
        return execution + "|\(start)|\(end)|\(paused)"
    }
    #endif

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width.isFinite ? max(0, geometry.size.width) : 0
            let height = geometry.size.height.isFinite ? max(0, geometry.size.height) : 0
            // Reserve the same reading viewport with controls shown or hidden.
            // The central 88 pt hit target keeps 20 pt clear of every passage;
            // a short landscape uses the left side to retain scrollable height.
            let readingBounds = height < 400
                ? CGRect(x: 0, y: 0, width: max(0, width / 2 - 64), height: height)
                : CGRect(x: 0, y: 84, width: width, height: max(0, height / 2 - 148))
            ZStack {
                Color.clear.contentShape(Rectangle())
                    .onTapGesture(perform: toggleControls)
                    .accessibilityHidden(true)
                ScrollView {
                    Text(verbatim: caption)
                        .font(.raleway(.title2)).lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 540, minHeight: max(0, readingBounds.height - 32), alignment: .leading)
                        .padding(.horizontal, min(28, readingBounds.width / 8)).padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.opacity)
                        .animation(showingInput ? nil : .easeOut(duration: still ? 0.12 : 0.22), value: caption)
                        .textSelection(.enabled)
                        .accessibilityIdentifier(showingActionStatus ? "morning.actionStatus" : "morning.caption")
                        #if DEBUG
                        .accessibilityValue(store.uiTestSessionSnapshot)
                        #endif
                        .accessibilityAction(named: Text(controlsLabel), toggleControls)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
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
                .frame(width: readingBounds.width, height: readingBounds.height)
                .position(x: readingBounds.midX, y: readingBounds.midY)

                if controlsVisible {
                    controls
                        .transition(.opacity)
                }
            }
        }
        .onChange(of: store.speech.captionRevision, initial: true) { _, _ in
            guard !store.privacyBlocksWork, let text = store.speech.currentCaption, !text.isEmpty else { return }
            isUserCaption = false
            displayedCaptionBoundary = actionStatus?.text
            // The spoken step label is metadata; Home shows only its content.
            let prefix = store.currentStep.map { $0.title + "." } ?? ""
            displayedCaption = store.speech.caption(omittingInitialPrefix: prefix) ?? ""
        }
        .onChange(of: actionStatus?.text) { _, boundary in
            if displayedCaptionBoundary != boundary { clearCaption() }
            pendingCloudCaption = nil
        }
        .onChange(of: store.speech.isSpeaking) { _, speaking in
            if !speaking, (actionStatus?.priority ?? -1) >= 3 { clearCaption() }
        }
        #if !MORE_JURY_DEMO
        .onChange(of: store.cloudVoice.caption) { _, text in
            pendingCloudCaption = text
            receiveCloudCaption()
        }
        .onChange(of: store.cloudVoice.state) { _, state in
            if state == .speaking { receiveCloudCaption() }
            else {
                pendingCloudCaption = nil
                if (actionStatus?.priority ?? -1) >= 3 { clearCaption() }
            }
        }
        #endif
        .onChange(of: store.handsFreeVoice.transcriptRevision) { _, _ in
            let text = store.handsFreeVoice.transcript
            if !text.isEmpty { showInput(text) }
            else if isUserCaption { clearCaption() }
        }
        .onChange(of: AppLanguage.code) { _, _ in clearCaption(); controlsVisible = false }
        .onChange(of: store.dataGeneration) { _, _ in clearCaption() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { clearCaption(); controlsVisible = false; captionScrolling = false }
        }
        .onChange(of: store.briefing.settings.includesHealth) { wasIncluded, included in
            if wasIncluded && !included { clearCaption() }
        }
        .onDisappear { clearCaption(); controlsVisible = false; captionScrolling = false }
        #if DEBUG
        .task { await playCaptionFixtureIfRequested() }
        #endif
        .onChange(of: voiceOverEnabled) { _, _ in if controlsVisible { controlsInteraction = UUID() } }
        .task(id: controlsInteraction) {
            guard controlsVisible, !voiceOverEnabled, !captionScrolling else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !voiceOverEnabled, !captionScrolling else { return }
            withAnimation(.easeOut(duration: 0.15)) { controlsVisible = false }
        }
    }

    #if !MORE_JURY_DEMO
    private func receiveCloudCaption() {
        guard !store.privacyBlocksWork, store.cloudVoice.state == .speaking,
              let text = pendingCloudCaption, text == store.cloudVoice.caption, !text.isEmpty else { return }
        // The SDK may keep the previous caption while listening. Only a new
        // passage observed in this boundary may replace the current action state.
        isUserCaption = false
        displayedCaptionBoundary = actionStatus?.text
        displayedCaption = text
    }
    #endif

    private func showInput(_ text: String) {
        displayedCaptionBoundary = actionStatus?.text
        pendingCloudCaption = nil
        displayedCaption = SpeechCoordinator.inputCaption(text)
        isUserCaption = true
    }

    private func clearCaption() {
        displayedCaption = nil; displayedCaptionBoundary = nil; pendingCloudCaption = nil; isUserCaption = false
    }

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
        if let session = store.session, let step = store.currentStep, step.automation == .gmailInbox {
            let mail = store.mailMorning
            if mail.context == MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id),
               mail.state == .askingToReply, mail.attentionSelection != nil, !mail.isComposingSelfMessage,
               let first = mail.messageChoices.first, mail.selectedMessageID == first.id {
                // The attributed summaries and quotes are already in the message list.
                // Keep the full narration and every draft/error/result in their own state.
                return french
                    ? "Choisissez un mail à examiner. Vous pouvez aussi préparer une note à vous-même ou continuer votre matin."
                    : "Choose a message to review. You can also prepare a note to yourself or continue your morning."
            }
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
                    if case let .inAppWeb(url) = store.currentStep?.target?.routineExecutionTarget {
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
        .morningSheet(isPresented: $showingDetails) { interaction }
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
            .scrollDismissesKeyboard(.interactively)
            .background(MorningPaper(showsSun: false))
            .navigationTitle(store.currentStep?.title ?? "MORE").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(french ? "Fermer" : "Close") { showingDetails = false }
                    .accessibilityIdentifier("morning.closeDetails")
            } }
        }
    }
}
