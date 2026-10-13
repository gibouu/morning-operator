import SwiftUI
import MorningCore

/// What happened in one ended morning, in plain sentences, rebuilt from the session each
/// time it is shown. It reads the run only: nothing here changes the routine or the saved
/// choices. "Saved" is stated from the store's real save result.
struct MorningRecapView: View {
    @Bindable var store: MorningStore
    let session: RoutineSession
    /// The day page already lists every moment under the recap, so it leaves the names out.
    var showsMomentNames = true

    var body: some View {
        let recap = store.recap(for: session)
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recap").font(.headline).accessibilityAddTraits(.isHeader)
                Text(endingText(recap.ending)).font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recap.ending")
                if let title = stoppedAtTitle(recap) {
                    line("It stopped at “\(title)”.")
                }
                if session.routine.isSynthetic {
                    line("Sample routine · not observed behavior").accessibilityIdentifier("recap.sample")
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                group("\(recap.completedSteps.count) moments completed", recap.completedSteps, id: "recap.completed")
                if !recap.skippedSteps.isEmpty {
                    group("\(recap.skippedSteps.count) moments skipped", recap.skippedSteps, id: "recap.skipped")
                }
                if !recap.unfinishedSteps.isEmpty {
                    group("\(recap.unfinishedSteps.count) moments not reached", recap.unfinishedSteps, id: "recap.unfinished")
                }
            }
            saveState(recap.saveState)
            MorningRecapFeedback(store: store, session: session)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recap.block")
    }

    private func endingText(_ ending: RoutineSessionEnding) -> LocalizedStringKey {
        switch ending {
        case .completed: "You reached the end of the routine."
        case .stopped: "You stopped before the end."
        case .stoppedWhilePaused: "You stopped while the routine was paused."
        case .neverStarted: "The routine was not started."
        case .inProgress: "The routine is still going."
        }
    }

    private func stoppedAtTitle(_ recap: RoutineSessionRecap) -> String? {
        guard showsMomentNames, let id = recap.stoppedAtStepID else { return nil }
        return session.routine.steps.first { $0.id == id }?.title
    }

    private func group(_ count: LocalizedStringKey, _ steps: [RoutineStep], id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(count).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if showsMomentNames {
                ForEach(steps) { step in
                    Text(step.title).font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // One element per group: the count, then the names it covers.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder private func saveState(_ state: RoutineSessionRecapSaveState) -> some View {
        switch state {
        case .saved:
            line("Saved on this device.").accessibilityIdentifier("recap.saved")
        case .notSaved:
            VStack(alignment: .leading, spacing: 8) {
                line("This morning is not saved yet.").accessibilityIdentifier("recap.notSaved")
                Button("Try saving again") { store.retrySavingMorning() }
                    .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    .disabled(!store.storageIsAvailable)
                    .accessibilityIdentifier("recap.retrySave")
            }
        }
    }

    private func line(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.footnote).foregroundStyle(MorningStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The recap of the run that ended today, at the top of Review. A run that was never
/// started has nothing to recap here; its day in history still shows it.
struct MorningRecapCard: View {
    @Bindable var store: MorningStore

    var body: some View {
        if let session = store.endedSession, endedToday(session),
           store.recap(for: session).ending != .neverStarted {
            Card { MorningRecapView(store: store, session: session) }
        }
    }
}

private extension MorningRecapCard {
    /// An earlier day's run is read from its day in history, not announced here again.
    func endedToday(_ session: RoutineSession) -> Bool {
        session.events.last.map { Calendar.current.isDateInToday($0.occurredAt) } ?? false
    }
}

/// Two optional questions. Nothing is selected to begin with, and leaving them alone
/// stores nothing. An answer is kept as its own feedback record and changes nothing else.
private struct MorningRecapFeedback: View {
    @Bindable var store: MorningStore
    let session: RoutineSession

    var body: some View {
        let saved = store.feedback(for: session)
        VStack(alignment: .leading, spacing: 12) {
            Text("Two optional questions. Answer one, both or neither.")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            question("Was it useful?", id: "recap.useful", selected: saved?.wasUseful) { answer in
                store.answerFeedback(for: session, wasUseful: answer, wasEnjoyable: saved?.wasEnjoyable)
            }
            question("Was it enjoyable?", id: "recap.enjoyable", selected: saved?.wasEnjoyable) { answer in
                store.answerFeedback(for: session, wasUseful: saved?.wasUseful, wasEnjoyable: answer)
            }
            if saved != nil {
                Text("Your answer is saved with this morning. It changes nothing else.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recap.feedbackSaved")
            }
        }
    }

    private func question(_ title: LocalizedStringKey, id: String, selected: RoutineFeedbackAnswer?,
                          answer: @escaping (RoutineFeedbackAnswer?) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            // Side by side when the three fit; one under the other at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { answers(title, id: id, selected: selected, answer: answer) }
                VStack(alignment: .leading, spacing: 10) { answers(title, id: id, selected: selected, answer: answer) }
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func answers(_ title: LocalizedStringKey, id: String, selected: RoutineFeedbackAnswer?,
                                      answer: @escaping (RoutineFeedbackAnswer?) -> Void) -> some View {
        ForEach(RoutineFeedbackAnswer.allCases, id: \.self) { option in
            let isSelected = option == selected
            // Choosing the selected answer again clears it.
            Button { answer(isSelected ? nil : option) } label: {
                Label {
                    Text(label(option)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!store.storageIsAvailable)
            .accessibilityLabel(Text(title))
            .accessibilityValue(Text(label(option)))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? Text("Choose it again to clear your answer.") : Text(verbatim: ""))
            .accessibilityIdentifier("\(id).\(option.rawValue)")
        }
    }

    private func label(_ answer: RoutineFeedbackAnswer) -> LocalizedStringKey {
        switch answer {
        case .yes: "Yes"
        case .somewhat: "Somewhat"
        case .no: "No"
        }
    }
}
