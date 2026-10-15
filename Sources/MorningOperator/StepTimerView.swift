import SwiftUI
import MorningCore

struct StepTimerView: View {
    @Bindable var store: MorningStore
    var body: some View {
        if let timer = store.activeStepTimer {
            HStack {
                Text(store.currentStep?.target?.destination.displayName ?? "MORE")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(timer.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                        .monospacedDigit().accessibilityIdentifier("stepTimer.remaining")
                }
                Button("+2 min") { Task { await store.extendStepTimer() } }
                    .accessibilityIdentifier("stepTimer.extend")
            }
            .font(.subheadline).padding(.vertical, 10)
        }
    }
}
