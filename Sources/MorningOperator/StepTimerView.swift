import SwiftUI
import MorningCore

struct StepTimerView: View {
    @Bindable var store: MorningStore
    var canOperate: () -> Bool = { true }
    var body: some View {
        if let timer = store.activeStepTimer {
            HStack {
                Text(store.currentStep?.target?.destination.displayName ?? "MORE")
                    .font(.raleway(.subheadline, .semibold))
                if case let .inAppWeb(url) = store.currentStep?.target?.routineExecutionTarget {
                    Button { if canOperate() { store.pendingWebTarget = url } } label: {
                        MorningDottedIcon(systemName: "globe").frame(width: 23, height: 23).frame(width: 44, height: 44)
                    }.accessibilityLabel("Open page").accessibilityIdentifier("stepTimer.openPage")
                        .disabled(!canOperate())
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(timer.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                        .monospacedDigit().accessibilityIdentifier("stepTimer.remaining")
                        #if DEBUG
                        .accessibilityValue(["com.gibouu.morningoperator.qa", "com.gibouu.morningoperator.systemqa"].contains(Bundle.main.bundleIdentifier ?? "")
                            ? UserDefaults.standard.string(forKey: "qa.stepIntentOutcome") ?? "noIntentResult" : "")
                        #endif
                }
                Button { Task {
                    guard canOperate() else { return }
                    await store.extendStepTimer(expectedTimer: timer)
                } } label: {
                    Text("+2").font(.raleway(.subheadline).monospacedDigit()).frame(width: 44, height: 44)
                }.accessibilityLabel("Add two minutes").accessibilityIdentifier("stepTimer.extend")
                    .disabled(!canOperate())
            }
            .font(.raleway(.subheadline)).buttonStyle(.plain).foregroundStyle(MorningStyle.ink).padding(.vertical, 4)
        }
    }
}
