import SwiftUI
import MorningCore

/// A web moment uses the same persisted timer and guarded Next request as an app
/// moment. Reopening its page never starts a second budget.
private struct RoutineWebStepPresenter: ViewModifier {
    @Bindable var store: MorningStore

    func body(content: Content) -> some View {
        content.fullScreenCover(isPresented: Binding(
            get: { store.pendingWebTarget != nil },
            set: { if !$0 { store.pendingWebTarget = nil } }
        )) {
            if let url = store.pendingWebTarget,
               let site = WebMorningSite(url: url),
               let step = store.currentStep,
               let timer = store.activeStepTimer {
                WebMorningView(site: site, minutes: step.durationMinutes, initialURL: url,
                    isStepActive: store.session?.status == .running,
                    stepEndsAt: timer.endsAt, timerPausedAt: timer.pausedAt,
                    onExtend: { Task { await store.extendStepTimer(expectedTimer: timer) } },
                    onNext: { store.nextTargetStep(sessionID: timer.sessionID, stepID: timer.stepID) },
                    onClose: { store.pendingWebTarget = nil })
                    .id(step.id)
            } else {
                VStack(spacing: 24) {
                    ContentUnavailableView("Page unavailable", systemImage: "globe",
                        description: Text("Choose another website in your routine."))
                    Button("Close") { store.pendingWebTarget = nil }
                        .buttonStyle(PrimaryButtonStyle())
                }.padding(24)
            }
        }
    }
}

extension View {
    func routineWebStep(store: MorningStore) -> some View {
        modifier(RoutineWebStepPresenter(store: store))
    }
}
