import SwiftUI
import MorningCore
import MorningApple

/// A web moment uses the same persisted timer and guarded Next request as an app
/// moment. Reopening its page never starts a second budget.
private struct RoutineWebStepPresenter: ViewModifier {
    @Bindable var store: MorningStore
    @State private var showingNativeRequest = false

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { store.pendingWebTarget != nil },
            set: { if !$0 { closePage() } }
        )) {
            if let url = store.pendingWebTarget,
               let site = WebMorningSite(url: url),
               let step = store.currentStep,
               let timer = store.activeStepTimer,
               let session = store.session {
                let executionID = MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: step.id)
                let controller = store.routineWebMoment.controller(for: executionID, site: site, initialURL: url)
                WebMorningView(site: site, minutes: step.durationMinutes, initialURL: url,
                    isStepActive: store.session?.status == .running,
                    stepEndsAt: timer.endsAt, timerPausedAt: timer.pausedAt,
                    onExtend: { Task { await store.extendStepTimer(expectedTimer: timer) } },
                    onNext: { store.nextTargetStep(sessionID: timer.sessionID, stepID: timer.stepID) },
                    executionPlan: store.webExecutionPlan,
                    onExecutionEvent: { [weak store] event in store?.receiveWebExecution(event) },
                    executionIsAuthorized: { [weak store] in
                        guard let store else { return false }
                        return !store.privacyBlocksWork && store.session?.id == timer.sessionID &&
                        store.currentStep?.id == timer.stepID && store.session?.status == .running && store.automatic
                    },
                    executionCanAdvance: { [weak store] in
                        guard let store else { return false }
                        return !store.speech.isSpeaking && !store.voiceInputBlocksPlayback
                    },
                    onPause: { store.pause() }, onResume: { store.resume() },
                    onNativeRequest: {
                        if store.session?.status == .running { store.pause() }
                        showingNativeRequest = true
                    },
                    retainedController: controller,
                    onNewsArticle: { ordinal in Task { await store.handleWebReadingUtterance("read article \(ordinal)") } },
                    onNewsReturn: { Task { await store.handleWebReadingUtterance("back to headlines") } },
                    onNewsRepeat: {
                        let context = store.handsFreeContext, privacy = store.dataGeneration
                        let generation = controller.syntheticNewsPageGeneration
                        Task {
                            let handled = await store.handleWebReadingUtterance("repeat the article")
                            if handled, let context, store.handsFreeContext == context, store.dataGeneration == privacy {
                                controller.noteSyntheticNewsRepeatCompletion(context: context, privacy: privacy, pageGeneration: generation)
                            }
                        }
                    },
                    onClose: closePage)
                    .id(step.id)
                    .sheet(isPresented: nativeRequestBinding(for: executionID)) { nativeRequestSheet }
                    .onChange(of: store.nativeMoment.context) { _, context in
                        if context == nil { showingNativeRequest = false }
                    }
                    .onChange(of: store.nativeMoment.message) { _, message in
                        if !message.isEmpty, store.nativeMoment.context == executionID,
                           store.session?.status == .paused { showingNativeRequest = true }
                    }
                    .onChange(of: store.session?.status) { _, status in
                        if status != .paused { showingNativeRequest = false }
                    }
                    .onChange(of: store.dataGeneration) { _, _ in showingNativeRequest = false }
                    .onChange(of: step.id) { _, _ in showingNativeRequest = false }
            } else {
                VStack(spacing: 24) {
                    MorningDottedIcon(systemName: "globe").frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                    Text("Page unavailable").font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Button { store.pendingWebTarget = nil } label: {
                        MorningDottedIcon(systemName: "xmark").frame(width: 24, height: 24).frame(width: 44, height: 44)
                    }.accessibilityLabel("Close").buttonStyle(.plain)
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MorningPaper(showsSun: false)).foregroundStyle(MorningStyle.ink)
            }
        }
    }
    private func nativeRequestBinding(for executionID: MorningExecutionID) -> Binding<Bool> {
        Binding(get: {
            !store.privacyBlocksWork && store.session?.status == .paused &&
                showingNativeRequest &&
                (store.nativeMoment.context == nil || store.nativeMoment.context == executionID)
        }, set: { presented in
            guard !presented else { return }
            showingNativeRequest = false
            if store.session?.status == .paused { store.clearNativeMoment() }
        })
    }
    private var nativeRequestSheet: some View {
        NavigationStack {
            ScrollView {
                NativeMomentReviewView(store: store, initiallyExpanded: true)
                    .padding(24).frame(maxWidth: 640).frame(maxWidth: .infinity)
                if !store.nativeMoment.isActive, store.session?.status == .paused {
                    Button(AppLanguage.isFrench ? "Reprendre mon matin" : "Resume my morning") {
                        showingNativeRequest = false
                        store.resume()
                    }.buttonStyle(PrimaryButtonStyle()).padding(.horizontal, 24)
                        .accessibilityIdentifier("web.nativeResume")
                }
            }
            .background(MorningPaper(showsSun: false))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppLanguage.isFrench ? "Fermer la demande" : "Close request") {
                        showingNativeRequest = false
                        store.clearNativeMoment()
                    }.accessibilityIdentifier("web.nativeClose")
                }
            }
        }
    }
    private func closePage() {
        if store.webExecutionPlan != nil, store.session?.status == .running { store.pause() }
        store.pendingWebTarget = nil
    }
}

extension View {
    func routineWebStep(store: MorningStore) -> some View {
        modifier(RoutineWebStepPresenter(store: store))
    }
}
