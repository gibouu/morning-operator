import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

private enum MorningShellDestination: Equatable { case home, routine, settings }

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<MorningShellDestination> private var selectedDestination = .home
    @ViewState<Bool> private var learningRequested = false
    @ViewState<Bool> private var routineInteractionBusy = false
    @ViewState<Bool> private var settingsInteractionBusy = false
    @ViewState<Date> private var currentDate = .now
    @ViewState<Bool> private var showingInvitation = false
    @ViewState<Date> private var selectedDay = .now
    @ViewState<Bool> private var showingDays = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @ViewState<Bool> private var pendingObservationReview = false
    @ViewState<Bool> private var testObservedBackground = false
    @ViewState<MorningHomeStartConfirmation?> private var homeStartConfirmation = nil
    @ViewState<Bool> private var actionTransitionPending = false
    private enum EntryPresentation: Hashable { case invitation }
    @ViewState<Set<EntryPresentation>> private var activeEntryPresentations = []
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.timeZone) private var timeZone

    private var confirmingHomeStart: Bool { homeStartConfirmation != nil }

    private var routineProgress: Double {
        guard let session = store.session, !session.routine.steps.isEmpty else { return 0 }
        return Double(session.completedStepIDs.count) / Double(session.routine.steps.count)
    }

    private var presentedContent: some View {
        Group {
            switch selectedDestination {
            case .home:
                NavigationStack {
                    TodayView(store: store, reviewObservation: requestObservationReview,
                              editRoutine: openRoutineReview, showInvitation: openMorningInvitation,
                              canEditInvitation: !entryIsOccupied,
                              isViewingToday: isViewingToday,
                              canOperateMorning: canOperateMorning,
                              canStartMorning: canStartMorning,
                              startConfirmation: $homeStartConfirmation,
                              transitionPending: $actionTransitionPending) {
                        homeDateBrowser
                    }
                    .background(MorningPaper(progress: routineProgress))
                    .toolbar(.hidden, for: .navigationBar)
                }
            case .routine:
                MorningRoutineDestination(store: store, learningRequested: $learningRequested,
                                          onInteractionChanged: { routineInteractionBusy = $0 })
            case .settings:
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            SetupView(store: store, onInteractionChanged: { settingsInteractionBusy = $0 })
                            if let notice = store.notice {
                                NoticeView(text: notice, dismiss: { store.notice = nil })
                            }
                        }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
                    }
                    .background(MorningPaper(showsSun: false))
                    .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 84) }
        .background(MorningPaper(progress: routineProgress))
        .overlay(alignment: .bottom) {
            MorningActionDock(store: store, selection: selectedDestination, transitionPending: $actionTransitionPending,
                              home: returnHome, routine: openRoutineReview, settings: openSettings)
                .padding(.horizontal, 20).padding(.bottom, 8)
                .frame(maxWidth: .infinity)
        }
        .background {
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *) {
                MorningRecordingCoordinator(store: store, canProcessRecording: recordingCanProcess,
                                            onStarted: returnHome,
                                            onReview: requestObservationReview)
            }
            #endif
        }
        .tint(MorningStyle.accent)
        .foregroundStyle(MorningStyle.ink)
        .font(.body)
        .sheet(isPresented: $showingInvitation, onDismiss: {
            activeEntryPresentations.remove(.invitation)
            processPendingEntries()
        }) {
            MorningInvitationView(service: store.invitation)
                .interactiveDismissDisabled(store.privacyBlocksWork)
                .onAppear { activeEntryPresentations.insert(.invitation) }
        }
        .sheet(isPresented: $store.capturePresented, onDismiss: captureReviewDismissed) {
            QuickCaptureView(store: store)
        }
        .sheet(isPresented: $store.voiceCommandPresented, onDismiss: {
            store.cancelVoiceCommandTurn()
            processPendingEntries()
        }) { MorningVoiceCommandView(store: store) }
        .sheet(isPresented: $store.captureVoicePresented, onDismiss: {
            store.completionCaptureDismissed(allowReview: scenePhase == .active)
            processPendingEntries()
        }) { MorningCaptureVoiceView(store: store) }
    }

    private var workspaceContent: some View {
        presentedContent
        .onChange(of: store.dataGeneration) { _, _ in
            homeStartConfirmation = nil
            actionTransitionPending = false
            learningRequested = false
            routineInteractionBusy = false; settingsInteractionBusy = false
            showingInvitation = false
            if selectedDestination != .settings { selectedDestination = .home }
            presentingIntentCapture = false; pendingObservationReview = false
            // Home keeps one stable identity while Privacy completes or retries.
            selectedDay = .now
            showingDays = false
        }
        .onChange(of: store.privacyCompletedID) { _, completed in
            guard completed != nil else { return }
            selectedDestination = .home
            showingInvitation = false
            store.tab = .today
        }
        .onChange(of: store.completionInvitationSessionID) { _, _ in processPendingEntries() }
        .onChange(of: store.routine) { _, _ in homeStartConfirmation = nil }
        .onChange(of: store.sessionActive) { _, _ in homeStartConfirmation = nil }
        .onChange(of: store.session?.id) { _, _ in
            homeStartConfirmation = nil
            store.completionSessionChanged()
        }
        .onChange(of: store.tab, initial: true) { _, value in
            // Legacy routes select one of the three destinations; there is no history hub.
            if value != .today {
                store.tab = .today
                store.stopCompletionInvitation()
                switch value {
                case .learn: requestObservationReview()
                case .review: openRoutineReview()
                case .setup: openSettings()
                case .captures, .today: break
                }
            }
            processPendingEntries()
        }
        .onChange(of: selectedDestination) { _, _ in
            homeStartConfirmation = nil
            processPendingEntries()
        }
        .onChange(of: selectedDay) { _, _ in selectionChanged() }
        .onChange(of: isViewingToday) { _, _ in selectionChanged() }
        .onChange(of: timeZone) { _, _ in selectionChanged() }
        .onChange(of: environmentCalendar) { _, _ in selectionChanged() }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged() }
    }

    var body: some View {
        workspaceContent
        .modifier(MorningHaptics(store: store))
        .routineWebStep(store: store)
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: store.automation.status) { store.synchronizeMorningActivity() }
        .onChange(of: scenePhase) { _, phase in
            store.morningActivitySceneChanged(isForeground: phase == .active)
            if phase != .active { homeStartConfirmation = nil }
            if phase == .background {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { testObservedBackground = true }
                #endif
                store.discardCompletionReflection()
                store.cancelVoiceCommandTurn()
                if store.session?.status == .running, !store.keepsTimerInBackground { store.pause() }
            } else if phase == .active {
                refreshCurrentDate()
                MorningThemeClock.shared.refresh()
                store.armStepTimer()
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if testObservedBackground, args.contains("--ui-testing"), args.contains("--ui-testing-start-entry-on-return") {
                    testObservedBackground = false
                    MorningIntentRouter.shared.requestStart()
                }
                #endif
                Task { await store.invitation.reconcile(); processPendingEntries() }
                Task { await store.prepareDayIfConfigured() }
            }
        }
        .onChange(of: MorningIntentRouter.shared.pendingCaptureText, initial: true) { _, _ in
            presentPendingIntentCapture()
        }
        .onChange(of: MorningIntentRouter.shared.pendingCommand, initial: true) { _, _ in processPendingEntries() }
        .onChange(of: MorningIntentRouter.shared.pendingStart, initial: true) { _, _ in processPendingEntries() }
        .onChange(of: entryIsOccupied) { _, occupied in
            if occupied { store.stopCompletionInvitation() }
            else { processPendingEntries() }
        }
        .onChange(of: observationReviewCanPresent) { _, ready in if ready { processPendingEntries() } }
        .onChange(of: store.busy) { _, busy in if !busy { processPendingEntries() } }
        .onOpenURL { url in
            let scheme = Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more"
            if let next = StepNavigation.parseNext(url, scheme: scheme) {
                guard canOperateMorning(), !entryIsOccupied else { return }
                store.tab = .today
                store.nextTargetStep(sessionID: next.sessionID, stepID: next.stepID)
                return
            }
            guard url.scheme == scheme, url.host == "morning", url.path.isEmpty,
                  url.query == nil, url.fragment == nil, !store.privacyBlocksWork else { return }
            // Revealing progress is not a request to start or resume. Keep any
            // unfinished review sheet intact rather than discarding the draft.
            if canOpenShellDestination { returnHome() }
        }
        .task { await initializeMorning() }
        .task {
            while !Task.isCancelled {
                refreshCurrentDate()
                MorningThemeClock.shared.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func initializeMorning() async {
        store.morningActivitySceneChanged(isForeground: scenePhase == .active)
        store.armStepTimer()
        if store.privacyNeedsCleanup {
            selectedDestination = .settings
            if store.privacyHasInterruptedRemoval { await store.forgetLocalData() }
            return
        }
        Task { await store.prepareDayIfConfigured() }
        await store.invitation.reconcile()
        #if DEBUG
        // Explicit isolated fixture entry tests exercise routing, not Siri or
        // notification delivery. They never request notification permission.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--ui-testing"), args.contains("--ui-testing-start-entry") {
            MorningIntentRouter.shared.requestStart()
        }
        #endif
        processPendingEntries()
    }

    private func openMorningInvitation() {
        guard scenePhase == .active, !entryIsOccupied, store.storageIsAvailable else { return }
        showingInvitation = true
    }

    private var displayCalendar: Calendar {
        var calendar = environmentCalendar
        calendar.timeZone = timeZone
        return calendar
    }

    private var isViewingToday: Bool {
        displayCalendar.isDate(selectedDay, inSameDayAs: currentDate)
    }

    /// Re-read the clock when an action is executed, including after midnight.
    private func canOperateMorning() -> Bool {
        selectedDestination == .home && scenePhase == .active &&
        displayCalendar.isDate(selectedDay, inSameDayAs: .now) && !store.privacyBlocksWork
    }

    private func canStartMorning() -> Bool {
        canOperateMorning() && !workIsOccupied && !actionTransitionPending
    }

    private func refreshCurrentDate() {
        let now = Date.now
        // Follow a live Today across midnight before applying the read-only guard.
        // An explicitly browsed past day keeps its saved selection.
        if displayCalendar.isDate(selectedDay, inSameDayAs: currentDate),
           !displayCalendar.isDate(currentDate, inSameDayAs: now) {
            selectedDay = now
        }
        currentDate = now
        selectionChanged()
    }

    private func selectionChanged() {
        homeStartConfirmation = nil
        if !displayCalendar.isDate(selectedDay, inSameDayAs: .now), store.session?.status == .running {
            // A browsed day is read-only. Cancel automatic handover before showing it.
            store.pause()
        }
        processPendingEntries()
    }

    private func returnHome() {
        guard canOpenShellDestination else { return }
        homeStartConfirmation = nil
        selectedDestination = .home
        store.tab = .today
        currentDate = .now
        selectedDay = currentDate
        showingDays = false
    }

    private func openRoutineReview() {
        guard canOpenShellDestination else { return }
        homeStartConfirmation = nil
        selectedDestination = .routine
        store.tab = .today
    }

    private func openLearning() {
        homeStartConfirmation = nil
        learningRequested = true
        selectedDestination = .routine
        store.tab = .today
    }

    private func openSettings() {
        guard canOpenShellDestination else { return }
        homeStartConfirmation = nil
        if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
        else { selectedDestination = .settings }
    }

    /// Teaching occupancy queues work, but must never trap the person in Learn.
    /// Only an actual modal, in-flight operation or privacy removal blocks the dock.
    private var canOpenShellDestination: Bool {
        scenePhase == .active && !store.privacyBlocksWork && !store.busy &&
        activeEntryPresentations.isEmpty && !showingInvitation &&
        !presentingIntentCapture && !store.capturePresented &&
        !store.captureVoicePresented && !store.hasPendingSpokenCapture &&
        !store.voiceCommandPresented && !store.morningDetailPresented &&
        !store.observationDetailPresented && !store.observationSelectionPresented &&
        !store.routineProposalPresented && !store.captureBusy && !store.calendarBusy
    }

    @ViewBuilder private var homeDateBrowser: some View {
        if store.storageIsAvailable {
            if let evidence = try? store.observationArchive.inlineDayEvidence {
                MorningInlineDayStrip(selectedDate: $selectedDay, isExpanded: $showingDays,
                                      history: store.history, observations: evidence)
                    .disabled(store.privacyBlocksWork)
            } else {
                dayEvidenceUnavailable
            }
        } else {
            dayEvidenceUnavailable
        }
    }

    private var dayEvidenceUnavailable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Saved days are unavailable. Try again later.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Today") {
                currentDate = .now
                selectedDay = currentDate
                showingDays = false
            }.frame(minHeight: 44).disabled(store.privacyBlocksWork)
        }.accessibilityIdentifier("morning.days.unavailable")
    }

    private func presentPendingIntentCapture() {
        guard !store.privacyBlocksWork, !workIsOccupied, !confirmingHomeStart, !actionTransitionPending,
              selectedDestination == .home, scenePhase == .active,
              let text = MorningIntentRouter.shared.pendingCaptureText else { return }
        presentingIntentCapture = true
        store.openCapture(text: text, source: .siri)
    }

    private func captureReviewDismissed() {
        store.capturePrefill = ""
        store.captureSource = .typed
        if presentingIntentCapture {
            MorningIntentRouter.shared.finishCaptureReview()
            presentingIntentCapture = false
        }
        processPendingEntries()
    }

    private func requestObservationReview() {
        pendingObservationReview = true
        processPendingEntries()
    }

    private func presentPendingObservationReview() {
        guard pendingObservationReview, observationReviewCanPresent else { return }
        // Learn may already be visible because the person opened the saved recording.
        // Consume the request once; don't reopen it after they dismiss it.
        pendingObservationReview = false
        openLearning()
    }

    /// Unlike start-entry occupancy, a saved raw recording must not block its own
    /// review. Watch this eligibility separately so closing another detail or
    /// ending a session resumes review even when a failed recording stays pending.
    private var observationReviewCanPresent: Bool {
        guard !store.privacyBlocksWork, scenePhase == .active, !store.busy, !store.sessionActive,
              selectedDestination != .settings, !settingsInteractionBusy,
              activeEntryPresentations.isEmpty, !showingInvitation,
              !confirmingHomeStart, !actionTransitionPending, !presentingIntentCapture,
              !store.capturePresented, !store.voiceCommandPresented, !store.captureVoicePresented,
              !store.hasPendingSpokenCapture, !store.voiceInputBlocksPlayback,
              !store.morningDetailPresented, !store.observationDetailPresented,
              !store.observationSelectionPresented, !store.routineProposalPresented,
              !store.captureBusy, !store.calendarBusy else { return false }
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *), ScreenRecordingService.shared.isBusy { return false }
        #endif
        return true
    }

    /// Presentation occupancy is separate from date/start occupancy: a saved
    /// recording must remain reviewable and the dock must remain navigable.
    private var workIsOccupied: Bool {
        var recordingBusy = false
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { recordingBusy = ScreenRecordingService.shared.isBusy }
        #endif
        return store.privacyBlocksWork || !activeEntryPresentations.isEmpty || showingInvitation ||
            routineInteractionBusy || settingsInteractionBusy || presentingIntentCapture ||
            store.capturePresented || store.voiceCommandPresented || store.captureVoicePresented ||
            store.hasPendingSpokenCapture || store.morningDetailPresented || store.observationDetailPresented ||
            store.observationSelectionPresented || store.routineProposalPresented || store.voiceInputBlocksPlayback ||
            store.busy || store.captureBusy || store.calendarBusy || store.hasPendingRecording ||
            recordingBusy || store.invitation.isBusy
    }

    private var entryIsOccupied: Bool {
        workIsOccupied || selectedDestination != .home || !isViewingToday ||
        confirmingHomeStart || actionTransitionPending
    }

    private var recordingCanProcess: Bool {
        // A retained raw recording is the work to process, so it is not a blocker here.
        selectedDestination == .home && !routineInteractionBusy && !settingsInteractionBusy &&
        !store.privacyBlocksWork && activeEntryPresentations.isEmpty &&
        !confirmingHomeStart && !actionTransitionPending && !showingInvitation && !presentingIntentCapture &&
        !store.capturePresented && !store.voiceCommandPresented && !store.captureVoicePresented &&
        !store.hasPendingSpokenCapture && !store.voiceInputBlocksPlayback &&
        !store.morningDetailPresented && !store.observationDetailPresented &&
        !store.observationSelectionPresented && !store.routineProposalPresented &&
        !store.captureBusy && !store.calendarBusy
    }

    private func processPendingEntries() {
        guard !store.privacyBlocksWork else { return }
        // A thought already waiting for review keeps priority over a start request.
        presentPendingIntentCapture()
        presentPendingObservationReview()
        let router = MorningIntentRouter.shared
        if scenePhase == .active, !workIsOccupied,
           (canOperateMorning() || router.pendingCommand?.action == .end),
           !confirmingHomeStart, !actionTransitionPending, let command = router.takeCommand() {
            store.performMorningCommand(command)
        }
        guard let request = router.pendingStart else {
            if scenePhase == .active, !entryIsOccupied, store.tab == .today {
                store.speakQueuedCompletionInvitation()
            }
            return
        }
        var destination = MorningEntryPolicy.destination(for: request,
            context: .init(sceneIsActive: scenePhase == .active, isOccupied: entryIsOccupied || !canOperateMorning(),
                storageIsAvailable: store.storageIsAvailable, hasRoutine: store.routine != nil,
                routineIsApproved: store.routine?.isApproved == true, sessionStatus: store.session?.status),
            consumedIDs: store.consumedMorningEntryIDs)
        let waitingNotice = String(localized: "Your morning is waiting. Finish what you're doing here, then MORE can begin.")
        guard destination != .wait else {
            if scenePhase == .active, store.notice == nil { store.notice = waitingNotice }
            return
        }
        if store.notice == waitingNotice { store.notice = nil }
        if Date.now >= request.expiresAt {
            store.notice = String(localized: "Your morning is ready when you are. Tap Start to begin.")
        }
        if let payload = router.invitationPayload {
            do {
                // A learning window's reminder only brings the person to MORE. It never
                // starts the routine, and it cannot start a recording.
                let used = try store.invitation.consume(payload)
                if used == nil || used?.learningTarget != nil { destination = .revealMorning }
            } catch {
                destination = .revealMorning
                store.notice = String(localized: "Your invitation couldn't be saved. Start your morning when you're ready.")
            }
        }
        // Acknowledge before navigation changes trigger another view update. The
        // synchronous store transition saves its receipt before executing a step.
        guard canOperateMorning(), !entryIsOccupied else { return }
        router.finishStart(request.id)
        guard store.handleMorningEntry(request, destination: destination) else {
            store.tab = .today
            return
        }
        switch destination {
        case .reviewDraft: openRoutineReview()
        case .learn: openLearning()
        default: returnHome()
        }
    }

}

/// A quiet, movable morning with no scrolling at ordinary phone text sizes.
/// Larger accessibility text and short landscape windows get a scroll fallback rather
/// than clipped controls or shrunken type. Review retains the complete routine.
struct TodayView<DayBrowser: View>: View {
    @Bindable var store: MorningStore
    var reviewObservation: () -> Void
    var editRoutine: () -> Void
    var showInvitation: () -> Void
    var canEditInvitation: Bool
    var isViewingToday: Bool
    var canOperateMorning: () -> Bool
    var canStartMorning: () -> Bool
    @Binding var startConfirmation: MorningHomeStartConfirmation?
    @Binding var transitionPending: Bool
    @ViewBuilder var dayBrowser: () -> DayBrowser
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.locale) private var locale
    @ViewState<Bool> private var showingNotice = false
    @ViewState<Bool> private var learnAfterNoticeDismissal = false
    @ViewState<RoutineStep?> private var viewingStep = nil
    private var terminal: Bool { store.session?.status == .completed || store.session?.status == .stopped }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if dynamicType.isAccessibilitySize || geometry.size.height < 470 {
                    ScrollView { page(compact: true).padding(.vertical, 12) }
                        .accessibilityIdentifier("morning.accessibleScroll")
                } else {
                    ViewThatFits(in: .vertical) {
                        page(compact: false)
                        page(compact: true)
                        ScrollView { page(compact: true) }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 0).padding(.bottom, 8)
            .frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onChange(of: store.routine?.id) { _, _ in viewingStep = nil }
        .onChange(of: store.dataGeneration) { _, _ in viewingStep = nil; showingNotice = false }
        .onChange(of: viewingStep != nil || showingNotice, initial: true) { _, presented in
            store.morningDetailPresented = presented
        }
        .sheet(item: $viewingStep) { selection in
            NavigationStack {
                if let step = store.routine?.steps.first(where: { $0.id == selection.id }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .center, spacing: 14) {
                            MorningDottedIcon(systemName: MorningStyle.symbol(for: step.kind)).frame(width: 26, height: 26)
                                .font(.title3).foregroundStyle(MorningStyle.accent)
                                .frame(width: 48, height: 48)
                                .background(MorningStyle.selected, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.title3.weight(.semibold))
                                Text("\(step.durationMinutes) min").font(.caption.monospacedDigit())
                                    .foregroundStyle(MorningStyle.muted)
                            }
                        }
                        Text(purpose(for: step)).font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("moment.purpose")
                        if let briefing = store.preparedBriefing(for: step) {
                            MorningBriefingDocumentView(document: briefing, operation: step.automation, synthetic: store.usesSyntheticBriefing)
                        } else if step.automation == .spokenNote || step.automation == .savedObservation {
                            Text(step.detail).font(.subheadline).textSelection(.enabled)
                                .accessibilityIdentifier("run.detail")
                        } else if !step.detail.isEmpty {
                            DisclosureGroup(isFrench ? "Détails enregistrés" : "Saved details") {
                                Text(step.detail).font(.subheadline).foregroundStyle(MorningStyle.muted)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                    .accessibilityIdentifier("run.detail")
                            }.font(.subheadline).tint(MorningStyle.accent)
                        }
                        if step.automation == nil {
                            Label { Text(step.kind == .messages ? (isFrench ? "Non connecté" : "Not connected") : (isFrench ? "À votre rythme" : "At your pace")) } icon: {
                                MorningDottedIcon(systemName: step.kind == .messages ? "arrow.up.forward.app" : "hand.tap").frame(width: 18, height: 18)
                            }
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("moment.manual")
                        }
                        if store.session?.status == .paused,
                           store.currentStep?.id == step.id,
                           step.automation == .morningBriefing || step.automation == .todayCalendar {
                            Button("Update this recap") { if canOperateMorning() { store.updateCurrentBriefing() } }
                                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("briefing.updateCurrent")
                        }
                        if store.session?.status == .paused {
                            Text("Your morning is paused.").font(.caption).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("run.detailPaused")
                        }
                        if store.sessionActive, store.currentStep?.id == step.id {
                            currentStepCommands
                        }
                        if canArrange, let routine = store.routine,
                           let index = routine.steps.firstIndex(where: { $0.id == step.id }) {
                            let generation = store.dataGeneration
                            HStack(spacing: 12) {
                                Text("Move").font(.caption).foregroundStyle(MorningStyle.muted)
                                Spacer()
                                if index > 0 {
                                    Button {
                                        store.moveStep(step.id, onto: routine.steps[index - 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    } label: { MorningDottedIcon(systemName: "arrow.up").frame(width: 22, height: 22) }
                                        .accessibilityLabel("Move earlier").frame(minWidth: 44, minHeight: 44)
                                        .accessibilityIdentifier("morning.moveEarlier")
                                }
                                if index + 1 < routine.steps.count {
                                    Button {
                                        store.moveStep(step.id, onto: routine.steps[index + 1].id,
                                            expectedRoutineID: routine.id, expectedGeneration: generation)
                                    } label: { MorningDottedIcon(systemName: "arrow.down").frame(width: 22, height: 22) }
                                        .accessibilityLabel("Move later").frame(minWidth: 44, minHeight: 44)
                                        .accessibilityIdentifier("morning.moveLater")
                                }
                            }.buttonStyle(SecondaryButtonStyle())
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { viewingStep = nil } } }
                }
            }.presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingNotice, onDismiss: {
            guard learnAfterNoticeDismissal else { return }
            learnAfterNoticeDismissal = false
            reviewObservation()
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if let notice = store.notice { Text(notice).textSelection(.enabled) }
                        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
                        if #available(iOS 27.0, *) {
                            MorningRecordingStatus(store: store, onReview: reviewAfterNotice)
                        } else { storedObservationStatus }
                        #else
                        storedObservationStatus
                        #endif
                    }.padding(24)
                }.navigationTitle("").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingNotice = false } } }
            }.presentationDetents([.medium, .large])
        }
    }

    private func reviewAfterNotice() {
        learnAfterNoticeDismissal = true
        showingNotice = false
    }

    @ViewBuilder private var storedObservationStatus: some View {
        if store.hasPendingRecording {
            SavedRecordingRecoveryView(store: store, onReview: reviewAfterNotice)
        } else { savedObservationReview }
    }

    /// Reviewing an imported file does not require the native recording framework.
    @ViewBuilder private var savedObservationReview: some View {
        if store.hasImportedObservation {
            Button(action: reviewAfterNotice) {
                Label { Text("Review your saved observation") } icon: { MorningDottedIcon(systemName: "text.viewfinder").frame(width: 18, height: 18) }
                    .font(.caption.weight(.medium))
            }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("observation.review")
        }
    }

    private func page(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            dateHeader
            if !isViewingToday {
                Text("Past days show saved activity. Return to Today to continue your morning.")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if store.sessionActive {
                    Button("End morning", systemImage: "stop") { store.stop() }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("run.stop")
                }
                Spacer(minLength: 12)
            } else if let routine = store.routine {
                if !store.sessionActive { routineHeading(routine, compact: compact) }
                if let opening = store.currentOpening { MorningOpeningView(store: store, presentation: opening, canOperate: canOperateMorning) }
                // The first moment's card waits with the routine: it appears once the
                // opening gives way, by a choice or on its own when hands free (issue #99).
                else if store.sessionActive { nowPlaying(compact: compact) }
                if store.session?.status == .completed { closingMoment }
                compactTimeline(routine, compact: compact)
                if routine.isSynthetic {
                    Text("Sample morning").font(.caption2).foregroundStyle(MorningStyle.muted)
                        .padding(.horizontal, 4).accessibilityIdentifier("routine.source")
                        .accessibilityLabel("Sample morning, not your observed activity")
                }
                Spacer(minLength: 4)
                if store.sessionActive { actionArea(routine) }
                else if routine.isApproved {
                    MorningHomePlayback(store: store, canOperate: canStartMorning, startConfirmation: $startConfirmation,
                                        transitionPending: $transitionPending)
                }
            } else {
                Spacer(minLength: 12)
                // The center Learn destination is the single first-use action.
                Spacer(minLength: 24)
            }
        }
    }

    private var dateHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            dayBrowser().frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Spacer()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *), ScreenRecordingService.shared.captureMayBeActive {
                Button { showingNotice = true } label: {
                    Label { Text("MORE · Recording") } icon: { MorningDottedIcon(systemName: "record.circle.fill").frame(width: 18, height: 18) }.font(.caption.weight(.medium)).foregroundStyle(.red)
                }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("morning.recording")
            }
            #endif
            if store.busy {
                Button { showingNotice = true } label: { ProgressView().controlSize(.small) }
                    .accessibilityLabel("Understanding your morning. View progress")
            } else if store.notice != nil || store.observationIssue != nil || store.hasPendingRecording {
                Button { showingNotice = true } label: { MorningDottedIcon(systemName: "exclamationmark.circle").frame(width: 24, height: 24).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).accessibilityLabel("Your morning needs attention")
                    .accessibilityIdentifier("morning.attention")
            }
            }
        }
    }

    private func routineHeading(_ routine: RoutineVersion, compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(isFrench ? "bonjour" : "good morning").font(MorningTheme.Typography.title)
                .background(MorningStyle.background)
                .accessibilityIdentifier("morning.heading")
                .accessibilityValue(store.session?.status == .stopped ? "stopped" : "")
            morningInvitationButton
            if !routine.isApproved {
                Text("Draft").font(.caption2).foregroundStyle(MorningStyle.muted)
                    .background(MorningStyle.background)
                    .accessibilityIdentifier("morning.draft")
                    .accessibilityLabel("Draft, review before starting")
            }
            Spacer(minLength: 8)
            Text("\(routine.totalDurationMinutes) min").font(.caption.monospacedDigit()).foregroundStyle(MorningStyle.muted)
                .background(MorningStyle.background)
                .accessibilityLabel("\(routine.totalDurationMinutes) minutes planned")
        }.padding(.bottom, 2)
    }

    private var morningInvitationButton: some View {
        // A saved preference or the editor's suggested time is not a registered
        // invitation. Only show the future instant confirmed by the service.
        let scheduled = store.invitation.isScheduled && store.invitation.invitation?.disposition == .enabled
            ? store.invitation.invitation?.scheduledAt : nil
        return TimelineView(.everyMinute) { context in
            let upcoming = scheduled.flatMap { $0 > context.date ? $0 : nil }
            Button(action: showInvitation) {
                HStack(spacing: 4) {
                    MorningDottedIcon(systemName: "clock").frame(width: 18, height: 18)
                    if let upcoming {
                        Text(upcoming.formatted(date: .omitted, time: .shortened)).monospacedDigit()
                    }
                }.font(.caption2).foregroundStyle(MorningStyle.muted).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .background(MorningStyle.background)
            }.buttonStyle(.plain)
                .accessibilityLabel(upcoming == nil ? "Set morning invitation" : "Edit morning invitation")
                .accessibilityValue(upcoming?.formatted(date: .complete, time: .shortened) ?? String(localized: "No upcoming invitation"))
                .accessibilityIdentifier("morning.invitation")
                .disabled(!canEditInvitation || !store.storageIsAvailable)
        }
    }

    private var isFrench: Bool { locale.language.languageCode?.identifier == "fr" }

    private func purpose(for step: RoutineStep) -> String {
        func text(_ english: String, _ french: String) -> String { isFrench ? french : english }
        switch step.automation {
        case .spokenNote: return text("Listen to your saved words.", "Écoutez vos mots enregistrés.")
        case .todayCalendar: return text("Hear what’s on your calendar today.", "Écoutez votre programme du jour.")
        case .morningBriefing: return text("Your day ahead, in a few words.", "Votre journée, en quelques mots.")
        case .savedObservation: return text("Listen back to the observation you saved.", "Réécoutez l’observation enregistrée.")
        case nil:
            switch step.kind {
            case .messages:
                return text("Read your messages. Reply in the app.",
                            "Retrouvez vos messages. Répondez dans l’application.")
            case .entertainment:
                return text("Make room for something you enjoy. You choose when to move on.",
                            "Un moment pour ce qui vous plaît. Vous choisissez quand passer à la suite.")
            case .briefing, .calendar:
                return text("See what’s ahead. Check your calendar and weather in their apps.",
                            "Préparez la journée. Consultez le calendrier et la météo dans leurs applications.")
            case .custom, .wellbeing:
                return text("A moment you’ve made room for.",
                            "Un moment que vous avez choisi.")
            }
        }
    }

    private var currentStepCommands: some View {
        let sessionID = store.session?.id
        let stepID = store.currentStep?.id
        let generation = store.dataGeneration
        let current = { store.session?.id == sessionID && store.currentStep?.id == stepID && store.dataGeneration == generation }
        let layout = dynamicType.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            if store.session?.status == .paused {
                Button { if current(), canOperateMorning() { store.resume() } } label: { Label { Text("Continue") } icon: { MorningDottedIcon(systemName: "play.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailResume")
            } else {
                Button { if current() { store.pause() } } label: { Label { Text("Pause") } icon: { MorningDottedIcon(systemName: "pause.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailPause")
                Button {
                    guard current(), canOperateMorning() else { return }
                    viewingStep = nil
                    store.advance()
                } label: { Label { Text("Next") } icon: { MorningDottedIcon(systemName: "arrow.right").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailNext")
            }
            Button { if current(), canOperateMorning() { store.readCurrent() } } label: { Label { Text("Again") } icon: { MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 20, height: 20) } }
                .accessibilityIdentifier("run.detailAgain")
        }.buttonStyle(SecondaryButtonStyle())
            .disabled(store.privacyBlocksWork || store.voiceInputBlocksPlayback)
    }

    private var canArrange: Bool {
        canOperateMorning() && !store.sessionActive && !store.busy && !store.privacyBlocksWork && store.storageIsAvailable
    }

    private func compactTimeline(_ routine: RoutineVersion, compact: Bool) -> some View {
        let generation = store.dataGeneration
        let dense = compact || routine.steps.count > 6 || store.sessionActive || terminal
        let spacing: CGFloat = store.sessionActive && compact ? 4 : 7
        return Group {
            VStack(spacing: spacing) {
                if #available(iOS 27.0, macOS 27.0, *) {
                    VStack(spacing: spacing) {
                        ForEach(Array(routine.steps.prefix(10))) { step in
                            momentTile(step, routine: routine, generation: generation, dense: dense)
                        }.reorderable()
                    }
                    .reorderContainer(for: RoutineStep.self, isEnabled: canArrange) { difference in
                        guard store.routine == routine, store.dataGeneration == generation else { return }
                        let selected = Set(difference.sources)
                        guard !selected.isEmpty, selected.count == difference.sources.count,
                              selected.isSubset(of: Set(routine.steps.map(\.id))) else { return }
                        let moving = routine.steps.map(\.id).filter { selected.contains($0) }
                        var remaining = routine.steps.map(\.id).filter { !selected.contains($0) }
                        switch difference.destination.position {
                        case .before(let target):
                            guard let index = remaining.firstIndex(of: target) else { return }
                            remaining.insert(contentsOf: moving, at: index)
                        case .end:
                            // The compact surface shows ten. End means after the
                            // last visible moment, never after hidden moments.
                            let visible = Set(routine.steps.prefix(10).map(\.id))
                            let index = remaining.firstIndex(where: { !visible.contains($0) }) ?? remaining.endIndex
                            remaining.insert(contentsOf: moving, at: index)
                        }
                        store.reorderSteps(remaining, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                } else {
                    ForEach(Array(routine.steps.prefix(10))) { step in
                        momentTile(step, routine: routine, generation: generation, dense: dense)
                    }
                }
                if routine.steps.count > 10 {
                    Button("See all \(routine.steps.count) moments", action: editRoutine)
                        .font(.caption).frame(minHeight: 44)
                }
            }
        }
        .id("\(routine.id)-\(generation)-\(canArrange)")
    }

    private func momentTile(_ step: RoutineStep, routine: RoutineVersion, generation: UUID, dense: Bool) -> some View {
        let index = routine.steps.firstIndex(where: { $0.id == step.id }) ?? 0
        let complete = store.session?.completedStepIDs.contains(step.id) == true
        let skipped = store.session?.skippedStepIDs.contains(step.id) == true
        let current = store.sessionActive && store.currentStep?.id == step.id
        return Button { viewingStep = step } label: {
            HStack(spacing: 13) {
                MorningDottedIcon(systemName: complete ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind)).frame(width: 20, height: 20)
                    .scaledFont(16, relativeTo: .body, weight: .regular)
                    .foregroundStyle(complete || skipped ? MorningStyle.muted : MorningStyle.ink).frame(width: 25)
                Text(step.title).font(.subheadline.weight(.medium))
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : 1)
                Spacer(minLength: 4)
                Text("\(step.durationMinutes) min")
                    .font(.caption.monospacedDigit()).foregroundStyle(current ? MorningStyle.ink : MorningStyle.muted)
            }
            .foregroundStyle(MorningStyle.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        }
        .buttonStyle(.plain)
        .background(current ? MorningStyle.selected : MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        .overlay(MorningDottedFrame(cornerRadius: MorningTheme.Space.radius).fill(current ? MorningStyle.ink : MorningStyle.line))
        .accessibilityLabel(complete ? "\(index + 1). \(step.title), \(step.durationMinutes) minutes, completed" : skipped ? "\(index + 1). \(step.title), \(step.durationMinutes) minutes, skipped" : "\(index + 1). \(step.title), \(step.durationMinutes) minutes")
        .accessibilityHint(canArrange ? "Opens details. Hold to move this moment." : "Opens details")
        .accessibilityIdentifier("morning.step.\(index)")
        .accessibilityActions {
            if canArrange {
                if index > 0 {
                    Button("Move earlier") {
                        store.moveStep(step.id, onto: routine.steps[index - 1].id, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                }
                if index + 1 < routine.steps.count {
                    Button("Move later") {
                        store.moveStep(step.id, onto: routine.steps[index + 1].id, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                }
            }
        }
    }

    private func nowPlaying(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    MorningDottedIcon(systemName: store.session?.status == .paused ? "pause.fill" : "waveform").frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(store.session?.status == .paused ? "Paused" : "Now")
                        .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                }.font(.caption.weight(.medium)).foregroundStyle(MorningStyle.accent)
                Spacer()
            }
            Text(store.currentStep?.title ?? String(localized: "Your morning"))
                .font(.headline).accessibilityIdentifier("run.step")
                .accessibilityValue(store.openingRoutineStartObservation)
            if compact {
                EmptyView()
            } else if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.caption).foregroundStyle(MorningStyle.muted)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : compact ? 2 : 3)
            }
        }.padding(compact ? 11 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            .overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
    }

    private var closingMoment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.shouldOfferCompletionReflection ? "Save a thought?" : "Morning complete.")
                .font(.headline).accessibilityIdentifier("run.step")
            Text(store.stateLabel).font(.caption).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
            if store.shouldOfferCompletionReflection {
                if dynamicType.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) { reflectionButtons }
                } else { HStack(spacing: 18) { reflectionButtons } }
            }
        }.padding(.vertical, 4)
    }

    @ViewBuilder private var reflectionButtons: some View {
        Button { store.openCompletionCapture() } label: {
            Label { Text("Speak") } icon: { MorningDottedIcon(systemName: "mic").frame(width: 22, height: 22) }
        }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.voiceInputBlocksPlayback).accessibilityIdentifier("morning.speakReflection")
        Button { store.openCapture() } label: {
            Label { Text("Write") } icon: { MorningDottedIcon(systemName: "square.and.pencil").frame(width: 20, height: 20) }
        }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.reflect")
        Button("Not now") { store.discardCompletionReflection() }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.dismissReflection")
    }

    @ViewBuilder private func actionArea(_ routine: RoutineVersion) -> some View {
        let sessionID = store.session?.id
        let stepID = store.currentStep?.id
        let generation = store.dataGeneration
        let current = { store.session?.id == sessionID && store.currentStep?.id == stepID && store.dataGeneration == generation }
        StepTimerView(store: store, canOperate: canOperateMorning)
        if store.sessionActive {
            HStack(spacing: 12) {
                if store.session?.status == .paused {
                    Button { if current(), canOperateMorning(), store.session?.status == .paused { store.resume() } } label: { Label { Text("Continue") } icon: { Image(systemName: "play.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.resume")
                        .disabled(store.voiceInputBlocksPlayback)
                } else {
                    Button { if current(), store.session?.status == .running { store.pause() } } label: { Label { Text("Pause") } icon: { Image(systemName: "pause.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 9) }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("run.pause")
                    if !store.automatic || [.waitingForUser, .unavailable, .failed].contains(store.automation.status) {
                        Button { if current(), canOperateMorning() { store.advance() } } label: { Image(systemName: "arrow.right").frame(width: 25, height: 25).frame(width: 32, height: 32) }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityLabel("Next moment").accessibilityIdentifier("run.next")
                    }
                }
                Menu {
                    Button("End morning", systemImage: "stop") { store.stop() }.accessibilityIdentifier("run.stop")
                    Button("Speak a command", systemImage: "mic") { store.openVoiceCommands() }
                        .accessibilityIdentifier("run.speakCommand")
                    Button("About this moment") { viewingStep = store.currentStep }
                        .accessibilityIdentifier("run.about")
                    Toggle("Hands free", isOn: Binding(get: { store.automatic }, set: { if current(), canOperateMorning() { store.automatic = $0 } }))
                    Button("Next moment") { if current(), canOperateMorning() { store.advance() } }.disabled(store.session?.status != .running)
                    Button("Skip this moment") { if current(), canOperateMorning() { store.advance(skipping: true) } }.disabled(store.session?.status != .running)
                    Button("Read aloud") { if current(), canOperateMorning() { store.readCurrent() } }.disabled(store.voiceInputBlocksPlayback)
                    Button("Save a thought") { store.openCapture() }
                } label: { Image(systemName: "ellipsis").frame(width: 25, height: 25).frame(width: 32, height: 32) }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityLabel("Morning controls").accessibilityIdentifier("run.controls")
            }.controlSize(.large)
        }
    }
}

struct NoticeView: View {
    let text: String
    let dismiss: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MorningDottedIcon(systemName: "info.circle").frame(width: 20, height: 20)
            Text(text).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { MorningDottedIcon(systemName: "xmark").frame(width: 18, height: 18).padding(5) }.accessibilityLabel("Dismiss message")
        }.foregroundStyle(MorningStyle.muted).padding(16).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("app.notice")
    }
}

/// Home, one Learn-or-Routine destination, and Settings. Home only returns Home.
private struct MorningActionDock: View {
    @Bindable var store: MorningStore
    var selection: MorningShellDestination
    @Binding var transitionPending: Bool
    var home: () -> Void
    var routine: () -> Void
    var settings: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        MorningNavigationGlassGroup {
            MorningNavigationSurface {
                HStack(spacing: 8) {
                    action(String(localized: "Home"), symbol: .morning, id: "morning.home", selected: selection == .home, home)
                    action(store.routine == nil ? String(localized: "Learn") : String(localized: "Routine"),
                           symbol: store.routine == nil ? .learn : .review,
                           id: store.routine == nil ? "morning.learn" : "morning.review", selected: selection == .routine, routine)
                    action(String(localized: "Settings"), symbol: .settings, id: "morning.settings", selected: selection == .settings, settings)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .foregroundStyle(.primary)
            }
        }.frame(maxWidth: 260)
    }

    private func action(_ title: String, symbol: MorningDockSymbol, id: String, selected: Bool = false,
                        _ perform: @escaping () -> Void) -> some View {
        let generation = store.dataGeneration
        return Button {
            guard generation == store.dataGeneration, scenePhase == .active,
                  !store.privacyBlocksWork, !store.busy, !transitionPending else { return }
            transitionPending = true
            perform()
            transitionPending = false
        } label: {
            MorningDockGlyph(symbol: symbol).frame(width: 27, height: 27)
                .frame(minWidth: 54, maxWidth: .infinity, minHeight: 48)
                .background(selected ? Color.primary.opacity(0.08) : .clear, in: Circle())
                .contentShape(Capsule())
        }.buttonStyle(.borderless)
            .disabled(store.busy || store.privacyBlocksWork || transitionPending)
            .accessibilityLabel(title).accessibilityIdentifier(id)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Root owns this snapshot so Home's adaptive layout cannot lose confirmation
/// occupancy when ViewThatFits switches between its compact and scroll variants.
struct MorningHomeStartConfirmation: Equatable {
    let routine: RoutineVersion
    let generation: UUID
}

/// An approved morning can be started here on Home, with an explicit confirmation.
/// Its snapshot and occupancy binding protect against late entry and capture work.
private struct MorningHomePlayback: View {
    @Bindable var store: MorningStore
    var canOperate: () -> Bool
    @Binding var startConfirmation: MorningHomeStartConfirmation?
    @Binding var transitionPending: Bool
    @Environment(\.scenePhase) private var scenePhase

    private var blocked: Bool {
        !canOperate() || store.busy || store.privacyBlocksWork || transitionPending ||
        store.voiceInputBlocksPlayback || store.captureVoicePresented ||
        store.hasPendingSpokenCapture || !store.storageIsAvailable
    }

    var body: some View {
        MorningNavigationSurface {
            Group {
                if let confirmation = startConfirmation {
                    readyBar(confirmation)
                } else {
                    Button {
                        guard !blocked, scenePhase == .active,
                              let routine = store.routine, routine.isApproved, !store.sessionActive else { return }
                        startConfirmation = MorningHomeStartConfirmation(routine: routine, generation: store.dataGeneration)
                    } label: {
                        Label("Play morning", systemImage: "play.fill")
                            .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.borderless)
                        .accessibilityIdentifier("run.start")
                        .disabled(blocked)
                }
            }
        }
        .frame(maxWidth: 360).frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityAction(.escape) { clearReadyState() }
    }

    private func readyBar(_ confirmation: MorningHomeStartConfirmation) -> some View {
        let routine = confirmation.routine
        return VStack(spacing: 2) {
            Text(routine.isSynthetic ? "Ready for this sample morning?" : "Ready for your morning?")
                .font(.caption.weight(.medium)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("morning.ready")
            HStack(spacing: 28) {
                Button("Cancel") { clearReadyState() }
                    .font(.caption).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("morning.cancelStart")
                Button("Start") {
                    guard startConfirmation == confirmation, confirmation.generation == store.dataGeneration, store.routine == routine,
                          routine.isApproved, !store.sessionActive, scenePhase == .active, !blocked else {
                        clearReadyState()
                        return
                    }
                    transitionPending = true
                    store.start()
                    clearReadyState()
                    transitionPending = false
                }.font(.subheadline.weight(.semibold)).foregroundStyle(MorningStyle.accent)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 48, minHeight: 44)
                    .accessibilityIdentifier("morning.confirmStart")
            }.buttonStyle(.plain).disabled(blocked)
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
    }

    private func clearReadyState() {
        startConfirmation = nil
    }
}

/// Light haptics mark the moments that matter: a morning starts, a morning finishes,
/// a routine is approved. The system skips them when haptics are off.
private struct MorningHaptics: ViewModifier {
    let store: MorningStore
    func body(content: Content) -> some View {
        let completed: Bool = store.session?.status == .completed
        return content
            .sensoryFeedback(.impact, trigger: store.morningStartCount)
            .sensoryFeedback(.success, trigger: completed) { (old: Bool, new: Bool) -> Bool in !old && new }
            .sensoryFeedback(.success, trigger: store.approvalCount)
    }
}
