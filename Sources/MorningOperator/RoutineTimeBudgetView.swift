import SwiftUI
import MorningCore

/// The optional time budget in the routine editor. Without a target it offers only the
/// way to set one. With a target it states the planned total against it and offers the
/// report's own choices. It never removes, shortens or reorders a step: both choices
/// leave the routine exactly as it is.
struct RoutineTimeBudgetSection: View {
    @Bindable var store: MorningStore
    var isDisabled = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The report the person chose to keep editing for. A new report clears the hint.
    @ViewState<RoutineTimeBudget?> private var editingFor = nil

    private var controlsDisabled: Bool { isDisabled || !store.canChangeTimeBudget }

    var body: some View {
        if let target = store.timeBudgetTargetMinutes {
            Section {
                targetControl(target)
                if let report = store.timeBudget {
                    reportBlock(report)
                    if !store.timeBudgetLongerPlanAccepted {
                        ForEach(report.choices, id: \.self) { choice in choiceButton(choice, report: report) }
                        if editingFor == report {
                            note("Change any moment above when you like. Nothing is removed, shortened or moved for you.")
                                .accessibilityIdentifier("budget.editHint")
                        }
                    }
                }
                Button("Remove the target") { store.setTimeBudgetTarget(nil) }
                    .disabled(controlsDisabled)
                    .accessibilityIdentifier("budget.clearTarget")
            } header: {
                Text("Morning length")
            } footer: {
                Text("Optional. A target only compares planned minutes; it never changes your routine.")
            }
        } else {
            Section {
                Button("Set a target length", systemImage: "clock") {
                    store.setTimeBudgetTarget(store.suggestedTimeBudgetTargetMinutes)
                }
                .disabled(controlsDisabled)
                .accessibilityIdentifier("budget.setTarget")
            }
        }
    }

    /// At the largest text sizes the label takes its own line, so the stepper never
    /// squeezes it into a narrow column that breaks words.
    @ViewBuilder private func targetControl(_ target: Int) -> some View {
        let stepper = Stepper(value: Binding(get: { target }, set: { store.setTimeBudgetTarget($0) }),
                              in: RoutineBudgetAndFeedback.targetMinutesRange,
                              step: RoutineBudgetAndFeedback.targetMinutesStep) {
            Text("Target: \(target) minutes").fixedSize(horizontal: false, vertical: true)
        }
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Target: \(target) minutes").fixedSize(horizontal: false, vertical: true)
                        .accessibilityHidden(true)
                    stepper.labelsHidden()
                }
            } else { stepper }
        }
        .disabled(controlsDisabled)
        .accessibilityLabel("Target length in minutes")
        .accessibilityValue("\(target)")
        .accessibilityIdentifier("budget.target")
    }

    private func reportBlock(_ report: RoutineTimeBudget) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Planned: \(report.totalMinutes) minutes").font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("budget.total")
            switch report.fit {
            case .withinTarget:
                note("Within your target.").accessibilityIdentifier("budget.within")
            case .overTarget:
                note("That is \(report.minutesOverTarget) minutes more than your target.")
                    .accessibilityIdentifier("budget.over")
            case .requiredAloneOverTarget:
                note("That is \(report.minutesOverTarget) minutes more than your target.")
                    .accessibilityIdentifier("budget.over")
                note("The moments you chose to keep take \(report.requiredMinutes) minutes.")
                note("On their own they are \(report.requiredMinutesOverTarget) minutes more than your target.")
                    .accessibilityIdentifier("budget.requiredOver")
            }
            if store.timeBudgetLongerPlanAccepted {
                note("You kept this longer plan. This note returns when the routine changes.")
                    .accessibilityIdentifier("budget.accepted")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("budget.report")
    }

    private func choiceButton(_ choice: RoutineTimeBudgetChoice, report: RoutineTimeBudget) -> some View {
        Button(choice.displayName) {
            switch choice {
            case .editRoutine: editingFor = report
            case .acceptLongerPlan: store.acceptLongerPlan()
            }
        }
        .disabled(controlsDisabled)
        .accessibilityIdentifier("budget.choice.\(choice.rawValue)")
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(MorningStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
