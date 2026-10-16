import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple
import UIKit

struct MorningRootView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var showingInvitation = false
    @ViewState<Bool> private var learnAfterRoutineDismissal = false
    @ViewState<UUID> private var reviewRootIdentity = UUID()
    @ViewState<Bool> private var resetReviewAfterSettingsDismissal = false
    @ViewState<Bool> private var presentingIntentCapture = false
    @ViewState<Bool> private var pendingObservationReview = false
    @ViewState<Bool> private var testObservedBackground = false
    @ViewState<Bool> private var showingActions = false
    @ViewState<Bool> private var actionTransitionPending = false
    private enum EntryPresentation: Hashable { case settings, learn, routine, invitation }
    @ViewState<Set<EntryPresentation>> private var activeEntryPresentations = []
    @ViewState<CGFloat> private var dockWidth = 430
    @ViewState<StepTimer?> private var externalAppDeparture: StepTimer? = nil
    @Environment(\.scenePhase) private var scenePhase

    // No tab bar: Home is the root, and every other destination is a screen pushed on
    // it. These flags keep their old meaning ("that destination is showing").
    private enum HomeRoute: Hashable { case settings, routine, routinePreparation, learn, history }
    @ViewState<[HomeRoute]> private var path: [HomeRoute] = []
    private func route(_ route: HomeRoute) -> Bool { path.contains(route) }
    private func setRoute(_ route: HomeRoute, _ visible: Bool) {
        if visible {
            if let index = path.firstIndex(of: route) { path.removeSubrange((index + 1)...) }
            else { path.append(route) }
        }
        else if let index = path.firstIndex(of: route) { path.removeSubrange(index...) }
    }
    private var showingSettings: Bool {
        get { route(.settings) } nonmutating set { setRoute(.settings, newValue) }
    }
    private var showingRoutineEditor: Bool {
        get { route(.routine) } nonmutating set { setRoute(.routine, newValue) }
    }
    private var showingRoutinePreparation: Bool {
        get { route(.routinePreparation) } nonmutating set { setRoute(.routinePreparation, newValue) }
    }
    private var learnPushed: Bool {
        get { route(.learn) } nonmutating set { setRoute(.learn, newValue) }
    }
    private var historyPushed: Bool {
        get { route(.history) } nonmutating set { setRoute(.history, newValue) }
    }
    private var showingLearn: Bool {
        get { learnPushed } nonmutating set { learnPushed = newValue }
    }
    /// Icons only, as in Instagram's bar; the name stays for VoiceOver.
    private func tabIcon(_ title: LocalizedStringKey, systemImage: String, id: String) -> some View {
        Label(title, systemImage: systemImage).labelStyle(.iconOnly).accessibilityIdentifier(id)
    }

    private func show(_ tab: MorningTab, _ visible: Bool) {
        if visible { store.tab = tab } else if store.tab == tab { store.tab = .today }
    }

    private var routineProgress: Double {
        guard let session = store.session, !session.routine.steps.isEmpty else { return 0 }
        return Double(session.completedStepIDs.count) / Double(session.routine.steps.count)
    }

    // The landscape and utility screens follow the same solar day.
    private var homeSkyIsVisible: Bool {
        path.isEmpty && !store.permissionSetup.isPresented && !showingInvitation && !store.capturePresented && !store.voiceCommandPresented
            && !store.captureVoicePresented && store.pendingWebTarget == nil && !store.privacyBlocksWork
    }
    private var nightAppearance: Bool {
        MorningThemeClock.shared.celestial.moon.opacity > 0.57
    }

    private var presentedContent: some View {
        NavigationStack(path: Binding(get: { path }, set: { path = $0 })) {
            MorningSunHome(actionsShown: $showingActions,
                           openSettings: { showingActions = false; showingSettings = true },
                           motionAllowed: homeSkyIsVisible,
                           notice: store.notice,
                           session: store.session,
                           testingSessionSnapshot: store.uiTestSessionSnapshot,
                           playback: store.sessionActive && !store.privacyBlocksWork ? AnyView(MorningHomePlaybackView(store: store, openSettings: { showingActions = false; showingSettings = true }).id(store.currentStep?.id)) : nil,
                           begin: {
                               guard !store.sessionActive else { return }
                               // No saved routine: show the proposal path, not the learning toolbox.
                               guard let routine = store.routine else { showingRoutinePreparation = true; return }
                               guard routine.isApproved else { showingRoutineEditor = true; return }
                               // A refused start leaves its notice on Home; it never sends a person
                               // with a routine back to Learn.
                               if store.start() { showingActions = false }
                           })
                // Light status bar text over the night sky.
                .toolbarColorScheme(nightAppearance ? .dark : .light, for: .navigationBar)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: HomeRoute.self) { route in
                    switch route {
                    case .settings:
                        SetupView(store: store,
                                  openRoutine: { if store.routine == nil { showingRoutinePreparation = true } else { showingRoutineEditor = true } },
                                  openLearning: { showingLearn = true },
                                  openHistory: { historyPushed = true })
                            .navigationTitle(String(localized: "Settings", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .navigationBarTitleDisplayMode(.large)
                            .toolbar(.visible, for: .navigationBar)
                    case .routinePreparation:
                        MorningRoutinePreparationView(store: store, onClose: { showingRoutinePreparation = false })
                    case .routine:
                        RoutineReviewEditor(store: store, onLearn: { showingLearn = true }, showsClose: false)
                    case .learn:
                        destinationContent(AppLanguage.localized("Learn my morning"), displayTitle: AppLanguage.localized("Learn")) {
                            LearnView(store: store, onClose: { learnPushed = false; if store.routine != nil { showingRoutineEditor = true } })
                        }
                    case .history:
                        WeeklyReviewView(store: store, onLearn: { showingLearn = true },
                                         onSettings: {
                                             if store.voiceInputBlocksPlayback { store.voiceCommandPresented = true }
                                             else { showingSettings = true }
                                         }, showingRoutineEditor: Binding(get: { showingRoutineEditor },
                                                                          set: { showingRoutineEditor = $0 }))
                            .background(MorningStyle.background)
                            .id(reviewRootIdentity)
                    }
                }
        }
        .preferredColorScheme(nightAppearance ? .dark : .light)
        .background(MorningPaper(showsSun: false))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { dockWidth = $0 }
        .background {
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *) {
                MorningRecordingCoordinator(store: store, canProcessRecording: recordingCanProcess,
                                            onStarted: { showingLearn = false },
                                            onReview: requestObservationReview)
            }
            #endif
        }
        .tint(MorningStyle.accent)
        .foregroundStyle(MorningStyle.ink)
        .font(MorningTheme.Typography.body)
        .fullScreenCover(isPresented: Binding(get: { store.permissionSetup.isPresented }, set: { store.permissionSetup.isPresented = $0 }), onDismiss: {
            if store.permissionSetup.takeRoutineReviewRequest(), !store.privacyBlocksWork {
                showPreparedRoutine()
            } else {
                processPendingEntries()
            }
            Task { await store.prepareDayIfConfigured(); synchronizeHomeWeather() }
        }) {
            MorningPermissionSetupView(store: store)
                .preferredColorScheme(nightAppearance ? .dark : .light)
                .onAppear { store.suspendHandsFreeVoice() }
        }
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
            externalAppDeparture = nil
            showingActions = false
            actionTransitionPending = false
            showingLearn = false; showingRoutinePreparation = false; showingRoutineEditor = false; showingInvitation = false
            learnAfterRoutineDismissal = false
            presentingIntentCapture = false; pendingObservationReview = false
            // Keep the presenting Review stack stable while Privacy is open.
            // Replacing its tab identity during confirmation dismissal can strand
            // the old presentation over a fast cleanup failure. Successful removal
            // resets Review below; pending cleanup keeps Settings non-dismissible.
            if !showingSettings { reviewRootIdentity = UUID() }
        }
        .onChange(of: store.privacyCompletedID) { _, completed in
            guard completed != nil else { return }
            if showingSettings { resetReviewAfterSettingsDismissal = true }
            else { reviewRootIdentity = UUID() }
            showingSettings = false
            showingInvitation = false
            store.tab = .today
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { store.permissionSetup.presentIfNeeded() }
            if !store.permissionSetup.isPresented, store.permissionSetup.takeRoutineReviewRequest() { showPreparedRoutine() }
        }
        .onChange(of: store.completionInvitationSessionID) { _, _ in processPendingEntries() }
        .onChange(of: store.session?.id) { _, _ in store.completionSessionChanged() }
        .onChange(of: store.tab) { _, value in
            showingActions = false
            switch value {
            case .review, .captures: store.tab = .today; historyPushed = true
            case .learn: store.tab = .today; showingLearn = true
            case .setup: store.tab = .today; showingSettings = true
            case .routine: store.tab = .today; showingRoutineEditor = true
            case .today: break
            }
            if value != .today { store.stopCompletionInvitation() }
            processPendingEntries()
        }
        .onChange(of: store.speech.voiceIdentifier) { store.saveVoicePreference() }
        .onChange(of: store.speech.voiceGender) { store.voicePreferenceChanged() }
        .onChange(of: store.cloudVoice.state) { _, state in
            if state == .failed { store.cloudConversationFailed() }
        }
        .onChange(of: store.readAloud) { store.executionPreferencesChanged() }
        .onChange(of: store.automatic) { store.executionPreferencesChanged(); updateScreenAwake() }
        .onChange(of: store.session?.status, initial: true) { _, _ in
            if store.sessionActive { showingActions = false }
            updateScreenAwake()
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    var body: some View {
        workspaceContent
        .modifier(MorningHaptics(store: store))
        .routineWebStep(store: store)
        #if MORE_JURY_DEMO
        .modifier(JuryDemoBrowserPresenter(store: store))
        #endif
        .modifier(MorningVoicePreparationPresenter(store: store))
        .onChange(of: store.speech.state) { store.handleSpeechInterruption() }
        .onChange(of: store.automation.status) { store.synchronizeMorningActivity() }
        .onChange(of: store.automation.status) { _, status in
            if status == .unavailable || status == .failed { store.recordExecution(.unavailable) }
        }
        .onChange(of: scenePhase) { _, phase in
            updateScreenAwake()
            store.morningActivitySceneChanged(isForeground: phase == .active)
            if phase == .background {
                #if MORE_JURY_DEMO
                store.juryDemoVoice.sceneDidEnterBackground()
                #else
                if store.briefing.settings.includesHealth { store.speech.stop() }
                store.briefing.invalidateHealthForForeground()
                store.briefing.cancelLocationRequest()
                store.permissionSetup.cancelForBackground()
                externalAppDeparture = store.externalAppDeparture
                store.suspendHandsFreeVoice()
                store.clearNativeMoment()
                store.clearSlackReply()
                store.clearGoogleCalendarDay()
                store.clearCalendlyDay()
                store.clearOutlookInbox()
                store.routineWebMoment.discardSourceContext()
                store.webExecutionEvent = nil
                store.preserveMailExecutionBeforeInterruption()
                store.mailMorning.clear()
                store.connectedMoment.discardContent()
                let clearsConnectedResult: Bool = {
                    if store.currentStep?.target?.integrationRoute == .api { return true }
                    return store.currentStep?.target == nil
                }()
                if clearsConnectedResult {
                    store.connectedAPITask?.cancel(); store.connectedAPITask = nil
                    store.connectedActionStatus = nil
                }
                showingActions = false
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") { testObservedBackground = true }
                #endif
                store.discardCompletionReflection()
                store.cancelVoiceCommandTurn()
                if store.session?.status == .running, !store.keepsTimerInBackground { store.pause() }
                #endif
            } else if phase == .active {
                #if MORE_JURY_DEMO
                if store.session?.status == .running {
                    store.beginJuryDemo()
                    if let url = store.juryDemoPendingWebURL {
                        store.juryDemoPendingWebURL = nil
                        store.presentJuryDemoBrowser(url)
                    }
                }
                #endif
                let departure = externalAppDeparture
                externalAppDeparture = nil
                if let departure { store.returnedFromExternalApp(departure) }
                store.startHandsFreeVoice()
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
            #if MORE_JURY_DEMO
            if url.scheme == "more-demo", url.host == "resume",
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let sessionID = components.queryItems?.first(where: { $0.name == "session" })?.value,
               store.session?.id.uuidString == sessionID {
                store.tab = .today
                store.resume()
                return
            }
            #endif
            #if DEBUG
            let ownSchemes = ((Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]) ?? [])
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
            if let scheme = url.scheme, ownSchemes.contains(scheme), url.host == "watch-morning", !store.privacyBlocksWork, store.canStartRecording {
                MorningIntentRouter.shared.requestWatchMorning()
                store.tab = .review; showingLearn = true
                return
            }
            #endif
            if store.handleNativeConnectionURL(url) { return }
            let scheme = Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more"
            if let next = StepNavigation.parseNext(url, scheme: scheme) {
                store.tab = .today
                store.nextTargetStep(sessionID: next.sessionID, stepID: next.stepID)
                return
            }
            guard url.scheme == scheme, url.host == "morning", url.path.isEmpty,
                  url.query == nil, url.fragment == nil, !store.privacyBlocksWork else { return }
            // Revealing progress is not a request to start or resume. Keep any
            // unfinished review sheet intact rather than discarding the draft.
            store.tab = .today
        }
        .onChange(of: store.briefing.currentWeatherLocation, initial: true) { _, location in
            synchronizeHomeWeather()
        }
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            updateScreenAwake()
            synchronizeHomeWeather()
        }
        .onChange(of: store.briefing.prepared) { _, _ in synchronizeHomeWeather() }
        .task {
            await initializeMorning()
            #if DEBUG
            if MorningStore.screenTimeAutoLearnRequested, !store.privacyBlocksWork { store.tab = .review; showingLearn = true }
            #endif
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                MorningThemeClock.shared.refresh()
                await store.refreshHomeWeatherIfNeeded()
                synchronizeHomeWeather()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    private func updateScreenAwake() {
        #if DEBUG
        let recording = MorningThemeClock.shared.isRecordingSolarDay
        #else
        let recording = false
        #endif
        UIApplication.shared.isIdleTimerDisabled = (recording || (store.automatic && store.sessionActive))
            && scenePhase == .active && !store.privacyBlocksWork
    }

    private func synchronizeHomeWeather() {
        MorningThemeClock.shared.setWeather(
            snapshot: store.privacyBlocksWork ? nil : store.briefing.currentWeatherSnapshot,
            status: store.briefing.prepared?.weather.status ?? .notConfigured,
            location: store.privacyBlocksWork ? nil : store.briefing.currentWeatherLocation)
    }

    private func initializeMorning() async {
        store.morningActivitySceneChanged(isForeground: scenePhase == .active)
        store.armStepTimer()
        if store.privacyNeedsCleanup {
            showingSettings = true
            if store.privacyHasInterruptedRemoval { await store.forgetLocalData() }
            return
        }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { store.permissionSetup.presentIfNeeded() }
        // Voice may already be authorized, so no cover dismissal will arrive.
        if !store.permissionSetup.isPresented, store.permissionSetup.takeRoutineReviewRequest() { showPreparedRoutine() }
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

    private func showPreparedRoutine() {
        if store.routine != nil { showingRoutineEditor = true }
        else { showingRoutinePreparation = true }
    }

    private func openRoutineReview() {
        showingRoutineEditor = true
    }

    private func presentPendingIntentCapture() {
        guard !store.privacyBlocksWork, !store.permissionSetup.isPresented, !store.permissionSetup.needsInitialSetup, activeEntryPresentations.isEmpty, scenePhase == .active, !presentingIntentCapture, !store.capturePresented, !store.captureVoicePresented, !store.hasPendingSpokenCapture,
              !store.voiceInputBlocksPlayback, !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending,
              !store.morningDetailPresented,
              !showingLearn, !showingRoutinePreparation, !showingRoutineEditor, !learnAfterRoutineDismissal, !store.voiceCommandPresented,
              !store.observationDetailPresented, !store.observationSelectionPresented, !store.routineProposalPresented,
              let text = MorningIntentRouter.shared.pendingCaptureText else { return }
        presentingIntentCapture = true
        store.openCapture(text: text, source: .siri)
    }

    private func captureReviewDismissed() {
        store.capturePrefill = ""
        store.captureSource = .typed
        store.closingReviewEnded()
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
        showingLearn = true
    }

    /// Unlike start-entry occupancy, a saved raw recording must not block its own
    /// review. Watch this eligibility separately so closing another detail or
    /// ending a session resumes review even when a failed recording stays pending.
    private var observationReviewCanPresent: Bool {
        guard activeEntryPresentations.isEmpty || (showingLearn && activeEntryPresentations == [.learn]) else { return false }
        guard !store.privacyBlocksWork, !store.permissionSetup.isPresented, !store.permissionSetup.needsInitialSetup,
              scenePhase == .active, !store.busy, !store.sessionActive,
              !showingSettings, !showingInvitation, !showingActions, !actionTransitionPending, !showingRoutinePreparation, !showingRoutineEditor, !learnAfterRoutineDismissal, !presentingIntentCapture,
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

    private var entryIsOccupied: Bool {
        var recordingBusy = false
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) { recordingBusy = ScreenRecordingService.shared.isBusy }
        #endif
        return store.privacyBlocksWork || store.permissionSetup.isPresented || store.permissionSetup.needsInitialSetup || !activeEntryPresentations.isEmpty || showingActions || actionTransitionPending || showingSettings || showingInvitation || showingLearn || showingRoutinePreparation || showingRoutineEditor || learnAfterRoutineDismissal || presentingIntentCapture ||
            store.capturePresented || store.voiceCommandPresented || store.captureVoicePresented ||
            store.hasPendingSpokenCapture || store.morningDetailPresented || store.observationDetailPresented ||
            store.observationSelectionPresented || store.routineProposalPresented || store.voiceInputBlocksPlayback ||
            store.busy || store.captureBusy || store.calendarBusy || store.hasPendingRecording ||
            recordingBusy || store.invitation.isBusy
    }

    private var recordingCanProcess: Bool {
        !store.privacyBlocksWork && !store.permissionSetup.isPresented && !store.permissionSetup.needsInitialSetup && activeEntryPresentations.isEmpty && !showingActions && !actionTransitionPending && !showingSettings && !showingInvitation && !showingLearn && !showingRoutinePreparation && !showingRoutineEditor && !learnAfterRoutineDismissal && !presentingIntentCapture &&
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
        if scenePhase == .active, !entryIsOccupied, let command = router.takeCommand() {
            store.performMorningCommand(command)
        }
        guard let request = router.pendingStart else {
            if scenePhase == .active, !entryIsOccupied, store.tab == .today {
                store.speakQueuedCompletionInvitation()
            }
            return
        }
        var destination = MorningEntryPolicy.destination(for: request,
            context: .init(sceneIsActive: scenePhase == .active, isOccupied: entryIsOccupied,
                storageIsAvailable: store.storageIsAvailable, hasRoutine: store.routine != nil,
                routineIsApproved: store.routine?.isApproved == true, sessionStatus: store.session?.status),
            consumedIDs: store.consumedMorningEntryIDs)
        let waitingNotice = AppLanguage.localized("Your morning is waiting. Finish what you're doing here, then MORE can begin.")
        guard destination != .wait else {
            if scenePhase == .active, store.notice == nil { store.notice = waitingNotice }
            return
        }
        if store.notice == waitingNotice { store.notice = nil }
        if Date.now >= request.expiresAt {
            store.notice = AppLanguage.localized("Your morning is ready when you are. Tap Start to begin.")
        }
        if let payload = router.invitationPayload {
            do {
                // A learning window's reminder only brings the person to MORE. It never
                // starts the routine, and it cannot start a recording.
                let used = try store.invitation.consume(payload)
                if used == nil || used?.learningTarget != nil { destination = .revealMorning }
            } catch {
                destination = .revealMorning
                store.notice = AppLanguage.localized("Your invitation couldn't be saved. Start your morning when you're ready.")
            }
        }
        // Acknowledge before navigation changes trigger another view update. The
        // synchronous store transition saves its receipt before executing a step.
        router.finishStart(request.id)
        guard store.handleMorningEntry(request, destination: destination) else {
            store.tab = .today
            return
        }
        switch destination {
        case .reviewDraft: openRoutineReview()
        case .learn: showingRoutinePreparation = true
        default: store.tab = .today
        }
    }

    private func destinationPage<Content: View>(_ title: String, displayTitle: String? = nil,
                                               @ViewBuilder content: () -> Content) -> some View {
        NavigationStack { destinationContent(title, displayTitle: displayTitle, content: content) }
    }

    private func destinationContent<Content: View>(_ title: String, displayTitle: String? = nil,
                                                  @ViewBuilder content: () -> Content) -> some View {
            ScrollView {
                VStack(spacing: 20) {
                    content()
                    if let notice = store.notice { NoticeView(text: notice, dismiss: { store.notice = nil }) }
                }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
            }
            .background(MorningPaper(showsSun: false)).navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text(displayTitle ?? title).font(MorningTheme.Typography.title) }
            }
    }
}

/// A quiet, movable morning with no scrolling at ordinary phone text sizes.
/// Larger accessibility text and short landscape windows get a scroll fallback rather
/// than clipped controls or shrunken type. Review retains the complete routine.
struct TodayView: View {
    @Bindable var store: MorningStore
    var showLearn: () -> Void
    var reviewObservation: () -> Void
    var showReview: () -> Void
    var editRoutine: () -> Void
    var showInvitation: () -> Void
    var canEditInvitation: Bool
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
                                .font(.serif(.title3)).foregroundStyle(MorningStyle.accent)
                                .frame(width: 48, height: 48)
                                .background(MorningStyle.selected, in: Circle())
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.serif(.title3, .semibold))
                                Text("\(step.durationMinutes) min").font(.raleway(.caption).monospacedDigit())
                                    .foregroundStyle(MorningStyle.muted)
                            }
                        }
                        Text(purpose(for: step)).font(.raleway(.body))
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("moment.purpose")
                        if let briefing = store.preparedBriefing(for: step) {
                            MorningBriefingDocumentView(document: briefing, operation: step.automation)
                        } else if step.automation == .spokenNote || step.automation == .savedObservation {
                            Text(step.detail).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("run.detail")
                        } else if !step.detail.isEmpty {
                            DisclosureGroup(isFrench ? "Détails enregistrés" : "Saved details") {
                                Text(step.detail).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                                    .accessibilityIdentifier("run.detail")
                            }.font(.raleway(.subheadline)).tint(MorningStyle.accent)
                        }
                        if step.automation == nil, step.target?.isConnectedAction != true {
                            Label { Text(step.kind == .messages ? (isFrench ? "Non connecté" : "Not connected") : (isFrench ? "À votre rythme" : "At your pace")) } icon: {
                                MorningDottedIcon(systemName: step.kind == .messages ? "arrow.up.forward.app" : "hand.tap").frame(width: 18, height: 18)
                            }
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("moment.manual")
                        }
                        if store.currentStep?.id == step.id, let status = store.connectedActionStatus {
                            Text(status).font(.raleway(.subheadline)).textSelection(.enabled)
                                .accessibilityIdentifier("moment.connectedResult")
                        }
                        if store.currentStep?.id == step.id, step.automation == .gmailInbox, store.sessionActive {
                            MorningMailMomentView(store: store)
                        }
                        if store.currentStep?.id == step.id, store.sessionActive, store.pendingWebTarget == nil {
                            NativeMomentReviewView(store: store)
                        }
                        if store.currentStep?.id == step.id, store.currentSlackContext != nil {
                            SlackMomentReplyView(store: store)
                        }
                        if store.currentStep?.id == step.id, store.currentGoogleCalendarDayContext != nil {
                            GoogleCalendarDayMomentView(store: store)
                        }
                        if store.currentStep?.id == step.id, store.currentCalendlyDayContext != nil {
                            CalendlyDayMomentView(store: store)
                        }
                        if store.currentStep?.id == step.id, store.currentOutlookInboxContext != nil {
                            OutlookInboxMomentView(store: store)
                        }
                        if store.session?.status == .paused,
                           store.currentStep?.id == step.id,
                           step.automation == .morningBriefing || step.automation == .todayCalendar {
                            Button("Update this recap") { store.updateCurrentBriefing() }
                                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("briefing.updateCurrent")
                        }
                        if store.session?.status == .paused {
                            Text("Your morning is paused.").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                                .accessibilityIdentifier("run.detailPaused")
                        }
                        if store.sessionActive, store.currentStep?.id == step.id {
                            currentStepCommands
                        }
                        if canArrange, let routine = store.routine,
                           let index = routine.steps.firstIndex(where: { $0.id == step.id }) {
                            let generation = store.dataGeneration
                            HStack(spacing: 12) {
                                Text("Move").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
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
                    .font(.raleway(.caption, .medium))
            }.buttonStyle(QuietButtonStyle()).accessibilityIdentifier("observation.review")
        }
    }

    private func page(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            dateHeader
            if let routine = store.routine {
                if !store.sessionActive { routineHeading(routine, compact: compact) }
                if let opening = store.currentOpening { MorningOpeningView(store: store, presentation: opening) }
                // The first moment's card waits with the routine: it appears once the
                // opening gives way, by a choice or on its own when hands free (issue #99).
                else if store.sessionActive { nowPlaying(compact: compact) }
                if store.session?.status == .completed { closingMoment }
                compactTimeline(routine, compact: compact)
                // While a morning runs, the Now card carries this label (issue #67),
                // except at accessibility sizes, where the page scrolls anyway.
                if routine.isSynthetic, !sampleLabelInNowCard { sampleLabel.padding(.horizontal, 4) }
                Spacer(minLength: 4)
                if store.sessionActive { actionArea(routine) }
            } else {
                Spacer(minLength: 12)
                welcome
                HStack(spacing: 12) {
                    Button(action: showLearn) {
                        Label { Text("Learn my morning") } icon: { MorningDottedIcon(systemName: "record.circle").frame(width: 24, height: 24) }
                            .padding(.horizontal, 8).padding(.vertical, 8)
                    }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("learn.begin")
                    Button("Try a sample") { store.loadSample() }
                        .font(.raleway(.subheadline)).frame(minHeight: 44)
                        .accessibilityIdentifier("routine.sample")
                }.padding(.top, 14)
                Spacer(minLength: 24)
            }
        }
    }

    private var dateHeader: some View {
        HStack {
            Button(action: showReview) {
                HStack(spacing: 8) {
                    Text(Date.now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(AppLanguage.locale)))
                        .font(.raleway(.caption, .medium))
                    MorningDottedIcon(systemName: "chevron.down").frame(width: 16, height: 16).font(.raleway(.caption2, .regular))
                }.foregroundStyle(MorningStyle.ink).frame(minHeight: 44).contentShape(Rectangle())
                    .background(MorningStyle.background)
            }.buttonStyle(.plain).accessibilityIdentifier("morning.date")
                .accessibilityHint("Review this week and previous mornings")
            Spacer()
            #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
            if #available(iOS 27.0, *), ScreenRecordingService.shared.captureMayBeActive {
                Button { showingNotice = true } label: {
                    Label { Text("MORE · Recording") } icon: { MorningDottedIcon(systemName: "record.circle.fill").frame(width: 18, height: 18) }.font(.raleway(.caption, .medium)).foregroundStyle(.red)
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

    private var welcome: some View {
        // The morning artwork carries this empty state; Learn and Sample are its actions.
        Color.clear.frame(height: 24).accessibilityHidden(true)
    }

    @ViewBuilder private func routineHeading(_ routine: RoutineVersion, compact: Bool) -> some View {
        let heading = Text(isFrench ? "bonjour" : "good morning").font(MorningTheme.Typography.title)
            .accessibilityIdentifier("morning.heading")
            .accessibilityValue(store.session?.status == .stopped ? String(localized: "Stopped", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "")
        if dynamicType.isAccessibilitySize {
            // At accessibility sizes the greeting takes its own full-width line, so it
            // wraps between words instead of breaking inside one (issue #89).
            VStack(alignment: .leading, spacing: 0) {
                heading.fixedSize(horizontal: false, vertical: true)
                HStack(alignment: .firstTextBaseline) { routineHeadingDetails(routine) }
            }.padding(.bottom, 2)
        } else {
            HStack(alignment: .firstTextBaseline) {
                heading
                routineHeadingDetails(routine)
            }.padding(.bottom, 2)
        }
    }

    @ViewBuilder private func routineHeadingDetails(_ routine: RoutineVersion) -> some View {
        morningInvitationButton
        if !routine.isApproved {
            Text("Draft").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("morning.draft")
                .accessibilityLabel("Draft, review before starting")
        }
        Spacer(minLength: 8)
        Text("\(routine.totalDurationMinutes) min").font(.raleway(.caption).monospacedDigit()).foregroundStyle(MorningStyle.muted)
            .accessibilityLabel("\(routine.totalDurationMinutes) minutes planned")
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
                        Text(upcoming.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: AppLanguage.locale))).monospacedDigit()
                    }
                }.font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    .background(MorningStyle.background)
            }.buttonStyle(.plain)
                .accessibilityLabel(upcoming == nil ? AppLanguage.localized("Set morning invitation") : AppLanguage.localized("Edit morning invitation"))
                .accessibilityValue(upcoming?.formatted(Date.FormatStyle(date: .complete, time: .shortened, locale: AppLanguage.locale)) ?? AppLanguage.localized("No upcoming invitation"))
                .accessibilityIdentifier("morning.invitation")
                .disabled(!canEditInvitation || !store.storageIsAvailable)
        }
    }

    private var isFrench: Bool { AppLanguage.isFrench }

    private func purpose(for step: RoutineStep) -> String {
        func text(_ english: String, _ french: String) -> String { isFrench ? french : english }
        switch step.automation {
        case .spokenNote: return text("Listen to your saved words.", "Écoutez vos mots enregistrés.")
        case .todayCalendar: return text("Hear what’s on your calendar today.", "Écoutez votre programme du jour.")
        case .morningBriefing: return text("Your day ahead, in a few words.", "Votre journée, en quelques mots.")
        case .savedObservation: return text("Listen back to the observation you saved.", "Réécoutez l’observation enregistrée.")
        case .timedMoment, .gmailInbox: return step.executionDescription
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
                Button { if current() { store.resume() } } label: { Label { Text("Continue") } icon: { MorningDottedIcon(systemName: "play.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailResume")
            } else {
                Button { if current() { store.pause() } } label: { Label { Text("Pause") } icon: { MorningDottedIcon(systemName: "pause.fill").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailPause")
                Button {
                    guard current() else { return }
                    viewingStep = nil
                    store.advance()
                } label: { Label { Text("Next") } icon: { MorningDottedIcon(systemName: "arrow.right").frame(width: 20, height: 20) } }
                    .accessibilityIdentifier("run.detailNext")
            }
            Button { if current() { store.readCurrent() } } label: { Label { Text("Again") } icon: { MorningDottedIcon(systemName: "arrow.clockwise").frame(width: 20, height: 20) } }
                .accessibilityIdentifier("run.detailAgain")
        }.buttonStyle(SecondaryButtonStyle())
            .disabled(store.privacyBlocksWork || store.voiceInputBlocksPlayback)
    }

    private var canArrange: Bool {
        !store.sessionActive && !store.busy && !store.privacyBlocksWork && store.storageIsAvailable
    }

    private func compactTimeline(_ routine: RoutineVersion, compact: Bool) -> some View {
        let generation = store.dataGeneration
        let dense = compact || routine.steps.count > 6 || store.sessionActive || terminal
        let spacing: CGFloat = store.sessionActive && compact ? 3 : 7
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
                        .font(.raleway(.caption)).frame(minHeight: 44)
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
        let symbol = MorningDottedIcon(systemName: complete ? "checkmark" : skipped ? "forward.end" : MorningStyle.symbol(for: step.kind))
            .frame(width: 20, height: 20)
            .foregroundStyle(complete || skipped ? MorningStyle.muted : MorningStyle.ink)
        let title = Text(step.title).font(.raleway(.subheadline, .medium))
        let duration = Text("\(step.durationMinutes) min")
            .font(.raleway(.caption).monospacedDigit()).foregroundStyle(current ? MorningStyle.ink : MorningStyle.muted)
        return Button { viewingStep = step } label: {
            Group {
                if dynamicType.isAccessibilitySize {
                    // At accessibility sizes the title gets the tile's full width under its
                    // symbol, so it wraps between words and nothing overlaps it (issue #89).
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) { symbol; Spacer(minLength: 4); duration }
                        title.fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 13) {
                        symbol.frame(width: 25)
                        // A long title, as in French, wraps to a second line instead of being cut (issue #89).
                        title.lineLimit(2)
                        Spacer(minLength: 4)
                        duration
                    }
                }
            }
            .foregroundStyle(MorningStyle.ink)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        }
        .buttonStyle(.plain)
        .background(current ? MorningStyle.selected : MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        .overlay(MorningDottedFrame(cornerRadius: MorningTheme.Space.radius).fill(current ? MorningStyle.ink : MorningStyle.line))
        .accessibilityLabel(complete ? String(localized: "\(index + 1). \(step.title), \(step.durationMinutes) minutes, completed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : skipped ? String(localized: "\(index + 1). \(step.title), \(step.durationMinutes) minutes, skipped", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "\(index + 1). \(step.title), \(step.durationMinutes) minutes", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
        .accessibilityHint(canArrange ? String(localized: "Opens details. Hold to move this moment.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Opens details", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
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

    /// Only while the Now card is on screen: the opening hides it (issue #99).
    private var sampleLabelInNowCard: Bool {
        store.sessionActive && store.currentOpening == nil && !dynamicType.isAccessibilitySize
    }

    private var sampleLabel: some View {
        Text("Sample morning").font(.raleway(.caption2)).foregroundStyle(MorningStyle.muted)
            .accessibilityIdentifier("routine.source")
            .accessibilityLabel("Sample morning, not your observed activity")
    }

    private func nowPlaying(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    MorningDottedIcon(systemName: store.session?.status == .paused ? "pause.fill" : "waveform").frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    Text(store.session?.status == .paused ? String(localized: "Paused", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Now", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                        .accessibilityIdentifier("run.state").accessibilityValue(store.stateLabel)
                }.font(.raleway(.caption, .medium)).foregroundStyle(MorningStyle.accent)
                Spacer()
                // In the card's own header row, so a running sample morning stays
                // labelled without a line of its own: ten moments fit (issue #67).
                if store.routine?.isSynthetic == true, sampleLabelInNowCard { sampleLabel }
            }
            Text(store.currentStep?.title ?? AppLanguage.localized("Your morning"))
                .font(.serif(.headline)).accessibilityIdentifier("run.step")
                .accessibilityValue(store.openingRoutineStartObservation)
            if compact {
                EmptyView()
            } else if store.automatic, !store.automation.message.isEmpty {
                Text(store.automation.message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .lineLimit(dynamicType.isAccessibilitySize ? nil : compact ? 2 : 3)
            }
        }.padding(compact ? 11 : 14).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            .overlay(RoundedRectangle(cornerRadius: MorningTheme.Space.radius).strokeBorder(MorningStyle.line))
    }

    private var closingMoment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let question = store.currentClosingQuestion {
                    // One closing question at a time, in the app's language.
                    Text(verbatim: question.prompt(french: AppLanguage.isFrench))
                } else {
                    Text(store.shouldOfferCompletionReflection ? String(localized: "Save a thought?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Morning complete.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                }
            }
            .font(.serif(.headline)).accessibilityIdentifier("run.step")
            .accessibilityValue(store.currentClosingQuestion?.rawValue ?? "")
            Text(store.stateLabel).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
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
        Button { store.answerClosingQuestionInWriting() } label: {
            Label { Text("Write") } icon: { MorningDottedIcon(systemName: "square.and.pencil").frame(width: 20, height: 20) }
        }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.reflect")
        if store.currentClosingQuestion != nil {
            // "No" to this question; the next one follows.
            Button("Skip") { store.skipClosingQuestion() }
                .buttonStyle(.borderless).accessibilityIdentifier("morning.skipQuestion")
        }
        Button("Not now") { store.discardCompletionReflection() }
            .buttonStyle(.borderless).accessibilityIdentifier("morning.dismissReflection")
    }

    @ViewBuilder private func actionArea(_ routine: RoutineVersion) -> some View {
        StepTimerView(store: store)
        if store.sessionActive {
            // Pause and Continue are as tall as the round buttons beside them, so the row
            // is no taller than it needs to be (issue #67).
            HStack(spacing: 12) {
                if store.session?.status == .paused {
                    Button { store.resume() } label: { Label { Text("Continue") } icon: { MorningDottedIcon(systemName: "play.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("run.resume")
                        .disabled(store.voiceInputBlocksPlayback)
                } else {
                    Button { store.pause() } label: { Label { Text("Pause") } icon: { MorningDottedIcon(systemName: "pause.fill").frame(width: 22, height: 22) }.frame(maxWidth: .infinity).padding(.vertical, 6) }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("run.pause")
                    if !store.automatic || [.waitingForUser, .unavailable, .failed].contains(store.automation.status) {
                        Button { store.advance() } label: { MorningDottedIcon(systemName: "arrow.right").frame(width: 25, height: 25).frame(width: 32, height: 32) }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityLabel("Next moment").accessibilityIdentifier("run.next")
                    }
                }
                Menu {
                    Button("End morning", systemImage: "stop") { store.stop() }.accessibilityIdentifier("run.stop")
                    Button("Speak a command", systemImage: "mic") { store.openVoiceCommands() }
                        .accessibilityIdentifier("run.speakCommand")
                    Button("About this moment") { viewingStep = store.currentStep }
                        .accessibilityIdentifier("run.about")
                    Toggle("Hands free", isOn: $store.automatic)
                    Button("Next moment") { store.advance() }.disabled(store.session?.status != .running)
                    Button("Skip this moment") { store.advance(skipping: true) }.disabled(store.session?.status != .running)
                    Button("Read aloud") { store.readCurrent() }.disabled(store.voiceInputBlocksPlayback)
                    Button("Save a thought") { store.openCapture() }
                } label: { MorningDottedIcon(systemName: "ellipsis").frame(width: 25, height: 25).frame(width: 32, height: 32) }
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
            Text(text).font(.raleway(.caption)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(action: dismiss) { MorningDottedIcon(systemName: "xmark").frame(width: 18, height: 18).padding(5) }.accessibilityLabel("Dismiss message")
        }.foregroundStyle(MorningStyle.muted).padding(16).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("app.notice")
    }
}

/// Four quiet destinations. Playback appears only when the morning sun is opened.
private struct MorningActionDock: View {
    @Bindable var store: MorningStore
    @Binding var expanded: Bool
    @Binding var transitionPending: Bool
    var availableWidth: CGFloat
    var edit: () -> Void
    @ViewState<RoutineVersion?> private var readyRoutine = nil
    @ViewState<UUID?> private var readyGeneration = nil
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var barWidth: CGFloat {
        min(max(0, availableWidth - 40), dynamicType.isAccessibilitySize ? 360 : 286)
    }

    var body: some View {
        VStack(spacing: 10) {
            if expanded {
                actionBar
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(MorningDottedFrame(cornerRadius: 12).fill(MorningStyle.line))
                    .accessibilityAction(.escape) { expanded = false }
            }
            HStack(spacing: 12) {
                Button {
                    expanded.toggle()
                } label: {
                    MorningDockGlyph(symbol: .morning).frame(width: 28, height: 28)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }
                .buttonStyle(SunriseTouchStyle())
                .accessibilityLabel("Morning")
                .accessibilityValue(expanded ? String(localized: "Expanded", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Collapsed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                .accessibilityHint("Opens playback controls")
                .accessibilityIdentifier("morning.actions")
                .disabled(store.privacyBlocksWork || transitionPending)
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .foregroundStyle(MorningStyle.ink)
            .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 10))
            .overlay(MorningDottedFrame(cornerRadius: 10, spacing: 7).fill(MorningStyle.line))
        }
        .frame(maxWidth: 320)
        .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: expanded)
        .onChange(of: expanded) { _, open in if !open { clearReadyState() } }
        .onChange(of: store.routine) { _, _ in clearReadyState() }
        .onChange(of: store.sessionActive) { _, active in if active { collapse() } }
        .onChange(of: store.dataGeneration) { _, _ in collapse() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { collapse() } }
    }

    private var actionBar: some View {
        Group {
            if let routine = readyRoutine {
                readyBar(routine)
            } else if dynamicType.isAccessibilitySize || barWidth < 248 {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) { actionItems }.padding(dynamicType.isAccessibilitySize ? 8 : 4)
                }.scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("morning.actionsScroll")
            } else {
                HStack(spacing: 0) { actionItems }.padding(4)
            }
        }.frame(width: readyRoutine != nil ? barWidth : 64,
                height: readyRoutine != nil ? nil : 58)
    }

    @ViewBuilder private var actionItems: some View {
        if let session = store.session, store.sessionActive {
            let intendsResume = session.status == .paused
            action(intendsResume ? AppLanguage.localized("Continue") : AppLanguage.localized("Pause"), symbol: intendsResume ? .play : .pause,
                   id: "morning.playback") {
                // Honor the displayed command and original session, never toggle
                // whatever state an interruption may have produced meanwhile.
                guard store.session?.id == session.id else { return }
                if intendsResume {
                    guard store.session?.status == .paused else { return }
                    store.resume()
                } else {
                    guard store.session?.status == .running else { return }
                    store.pause()
                }
            }
        } else if let routine = store.routine {
            let generation = store.dataGeneration
            action(routine.isApproved ? AppLanguage.localized("Play") : AppLanguage.localized("Review"),
                   symbol: routine.isApproved ? .play : .review,
                   id: routine.isApproved ? "run.start" : "morning.reviewDraft",
                   keepsExpanded: routine.isApproved) {
                guard store.routine == routine, !store.sessionActive else { return }
                if routine.isApproved {
                    readyRoutine = routine
                    readyGeneration = generation
                } else { edit() }
            }
        } else {
            action(AppLanguage.localized("Sample"), symbol: .play, id: "morning.sample") { store.loadSample() }
        }
    }

    private func action(_ title: String, symbol: MorningDockSymbol, id: String, disabled: Bool = false,
                        keepsExpanded: Bool = false, _ perform: @escaping () -> Void) -> some View {
        let generation = store.dataGeneration
        return Button {
            guard generation == store.dataGeneration, scenePhase == .active,
                  !store.privacyBlocksWork, !store.busy, !transitionPending else { return }
            // Establish the destination synchronously before releasing entry
            // occupancy; no timer or delayed closure can reopen a forgotten session.
            transitionPending = true
            perform()
            if !keepsExpanded { expanded = false }
            transitionPending = false
        } label: {
            MorningDockGlyph(symbol: symbol).frame(width: 27, height: 27)
            .foregroundStyle(MorningStyle.ink)
            .frame(minWidth: 54, maxWidth: dynamicType.isAccessibilitySize ? nil : .infinity, minHeight: 48)
            .padding(.horizontal, 3)
            .contentShape(Capsule())
        }.buttonStyle(DockActionTouchStyle())
            .disabled(disabled || store.busy || store.privacyBlocksWork || transitionPending)
            .opacity(disabled ? 0.4 : 1).accessibilityLabel(title).accessibilityIdentifier(id)
    }

    private func readyBar(_ routine: RoutineVersion) -> some View {
        // The question sits above its two answers so neither has to squeeze the other.
        return VStack(spacing: 2) {
            Text(routine.isSynthetic ? String(localized: "Ready for this sample morning?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Ready for your morning?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                .font(.raleway(.caption, .medium)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("morning.ready")
            HStack(spacing: 28) {
                Button("Cancel") { clearReadyState() }
                    .font(.raleway(.caption)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("morning.cancelStart")
                Button("Start") {
                    guard readyGeneration == store.dataGeneration, store.routine == routine,
                          routine.isApproved, !store.sessionActive, scenePhase == .active,
                          !store.privacyBlocksWork, !store.busy, !store.voiceInputBlocksPlayback else {
                        clearReadyState()
                        return
                    }
                    transitionPending = true
                    store.start()
                    clearReadyState()
                    expanded = false
                    transitionPending = false
                }.font(.raleway(.subheadline, .semibold)).foregroundStyle(MorningStyle.accent)
                    .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: 48, minHeight: 44)
                    .accessibilityIdentifier("morning.confirmStart")
            }.buttonStyle(.plain)
                .disabled(store.busy || store.privacyBlocksWork || transitionPending || store.voiceInputBlocksPlayback)
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
    }

    private func clearReadyState() {
        readyRoutine = nil
        readyGeneration = nil
    }

    private func collapse() {
        clearReadyState()
        transitionPending = false
        expanded = false
    }
}

private struct SunriseTouchStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.95 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct DockActionTouchStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// Haptics mark the moments that matter: a light tap when a morning starts, and the
/// system's success feedback when a morning finishes or a routine is approved. Each
/// follows a store counter that rises only after a successful save (issue #80). The
/// system skips them when haptics are off.
private struct MorningHaptics: ViewModifier {
    let store: MorningStore
    func body(content: Content) -> some View {
        content
            .sensoryFeedback(.impact(weight: .light), trigger: store.morningStartCount)
            .sensoryFeedback(.success, trigger: store.morningCompletionCount)
            .sensoryFeedback(.success, trigger: store.approvalCount)
    }
}

/// Home stays a quiet landscape until the person asks for their controls.
private struct MorningSunHome: View {
    @Binding var actionsShown: Bool
    var openSettings: () -> Void
    var motionAllowed: Bool
    var notice: String?
    var session: RoutineSession?
    var testingSessionSnapshot = ""
    var playback: AnyView? = nil
    /// Plays the saved routine, or opens the onboarding when there is none yet.
    var begin: () -> Void
    @State private var controlsInteraction = UUID()
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    private var isFrench: Bool { AppLanguage.isFrench }
    private var finishedToday: Bool {
        guard let done = session?.completedAt else { return false }
        return Calendar.current.isDateInToday(done)
    }
    private var still: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return reduceMotion
    }

    private var strongInk: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-transparency") { return true }
        #endif
        return reduceTransparency || contrast == .increased
    }

    private var sessionAccessibilityStatus: String {
        switch session?.status {
        case .ready: isFrench ? "Matin prêt" : "Morning ready"
        case .running: isFrench ? "Matin en cours" : "Morning running"
        case .paused: isFrench ? "Matin en pause" : "Morning paused"
        case .completed: isFrench ? "Matin terminé" : "Morning complete"
        case .stopped: isFrench ? "Matin arrêté" : "Morning stopped"
        case nil: isFrench ? "Matin non commencé" : "Morning not started"
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let clock = MorningThemeClock.shared
            let night = clock.celestial.moon.opacity
            ZStack(alignment: .bottom) {
                Button {
                    withAnimation(still ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22)) {
                        actionsShown.toggle()
                    }
                    controlsInteraction = UUID()
                } label: {
                    MorningQuietLandscape(scene: clock.celestial, weather: clock.weatherScene,
                                          animated: !still, active: motionAllowed && scenePhase == .active,
                                          strongInk: strongInk)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .ignoresSafeArea()
                .allowsHitTesting(playback == nil)
                .accessibilityHidden(playback != nil)
                .accessibilityIdentifier("morning.actions")
                .accessibilityLabel(actionsShown
                    ? (isFrench ? "Masquer les commandes" : "Hide controls")
                    : (isFrench ? "Afficher les commandes" : "Show controls"))
                .accessibilityValue("\(sessionAccessibilityStatus). \(clock.skyAccessibilityDescription)"
                    + (testingSessionSnapshot.isEmpty ? "" : "\n\(testingSessionSnapshot)"))
                .accessibilityHint(isFrench ? "Le paysage suit l’heure de votre iPhone." : "The landscape follows your iPhone’s time.")

                if let playback {
                    VStack(spacing: 0) {
                        playback
                            .shadow(color: night > 0.5 ? .black.opacity(0.65) : .clear, radius: 2, y: 1)
                    }
                } else if actionsShown {
                    Button {
                        actionsShown = false
                        begin()
                    } label: {
                        MorningFloatingGlassSymbol(symbol: .play, size: 48, prefersOpaque: strongInk)
                            .frame(width: 88, height: 88).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFrench ? "Commencer mon matin" : "Start my morning")
                    .accessibilityIdentifier("morning.begin")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)

                    Button {
                        actionsShown = false
                        openSettings()
                    } label: {
                        MorningFloatingGlassSymbol(symbol: .settings, size: 28, prefersOpaque: strongInk)
                            .frame(width: 48, height: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isFrench ? "Paramètres" : "Settings")
                    .accessibilityIdentifier("morning.settings")
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                } else if finishedToday {
                    Text(isFrench ? "bonne journée" : "have a good day")
                        .font(.raleway(.title2)).padding(28)
                        .frame(maxWidth: 640, maxHeight: .infinity, alignment: .leading)
                        .accessibilityIdentifier("morning.complete")
                }
                if playback == nil, let notice, !notice.isEmpty {
                    Text(notice).font(.raleway(.subheadline))
                        .padding(28).frame(maxWidth: 540)
                        .accessibilityIdentifier("app.notice")
                }
            }
            .foregroundStyle(night > 0.5 ? Color(red: 0.91, green: 0.91, blue: 0.96) : MorningStyle.ink)
        }
        .onChange(of: actionsShown) { _, _ in controlsInteraction = UUID() }
        .onChange(of: voiceOverEnabled) { _, _ in controlsInteraction = UUID() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { actionsShown = false } }
        .task(id: controlsInteraction) {
            guard actionsShown, !voiceOverEnabled else { return }
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard !Task.isCancelled, !voiceOverEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) { actionsShown = false }
        }
    }



}
