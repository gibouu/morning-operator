import SwiftUI
import MorningCore
import MorningApple

/// The same normal Screen Time path appears in Learn and Settings. It never swaps
/// in samples when access is unavailable. The read and daily results stay local.
struct MorningScreenTimeView: View {
    @Bindable var store: MorningStore
    var returnsToLearn = false
    var onEdit: (() -> Void)? = nil
    @State private var showingReview = false
    @State private var showingObservations = false
    @State private var learnAfterObservations = false
    @State private var editAfterObservations = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("Start with your app use").font(MorningTheme.Typography.heading)
                Text("Connect Screen Time, then show MORE a moment of your morning.")
                    .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                if let day = store.screenTimeDailyUsage.first {
                    dailyUse(day)
                    if store.screenTimeDailyUsage.count > 1 {
                        DisclosureGroup("Earlier days") {
                            ForEach(store.screenTimeDailyUsage.dropFirst()) { dailyUse($0).padding(.vertical, 8) }
                        }.font(MorningTheme.Typography.note)
                    }
                }
                if store.screenTimeBusy {
                    HStack { ProgressView(); Text("Reading your last mornings…") }
                        .font(MorningTheme.Typography.note).accessibilityIdentifier("learn.screenTime.reading")
                } else {
                    Button(store.screenTimeAccess == .approved ? AppLanguage.localized("Refresh app use") : AppLanguage.localized("Connect Screen Time")) {
                        store.learnFromScreenTime()
                    }.buttonStyle(PrimaryButtonStyle())
                        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.screenTimeAccess == .unavailable)
                        .accessibilityIdentifier("learn.screenTime.start")
                }
                if let proposal = store.pendingScreenTimeProposal {
                    Text("Suggestion ready: \(proposal.steps.count) apps from \(proposal.morningsUsed) mornings.")
                        .font(MorningTheme.Typography.note).accessibilityIdentifier("learn.screenTime.ready")
                    Button("Review suggestion") { showingReview = true }
                        .buttonStyle(SecondaryButtonStyle()).disabled(store.busy || store.screenTimeBusy)
                        .accessibilityIdentifier("learn.screenTime.review")
                }
                if store.observationArchive.entries.contains(where: { $0.screenTimeEvidence != nil }) {
                    Button(AppLanguage.isFrench ? "Réunir les observations choisies" : "Combine selected observations") {
                        showingObservations = true
                    }.buttonStyle(SecondaryButtonStyle())
                        .disabled(store.busy || store.screenTimeBusy || store.sessionActive)
                        .accessibilityIdentifier("learn.screenTime.observations")
                    Text(AppLanguage.isFrench
                        ? "Les agrégats enregistrés sont disponibles avec vos vidéos et leçons navigateur. Choisissez les sources avant de demander une proposition commune."
                        : "Saved aggregates are available beside your videos and browser lessons. Choose the sources before requesting a combined suggestion.")
                        .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                }
                if let message = store.screenTimeMessage {
                    Text(message).font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("learn.screenTime.message")
                } else if store.screenTimeAccess == .unavailable {
                    Text(store.screenTimeAccessExplanation).font(MorningTheme.Typography.note)
                        .foregroundStyle(MorningStyle.muted)
                }
                DisclosureGroup("What Screen Time can show") {
                    Text("App minutes and pickup counts. It does not show taps, messages or scrolling speed.")
                    Text("Access depends on your iPhone and Apple Account region. Only one app can hold this access at a time.")
                }.font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
            }
        }
        .onAppear { store.refreshScreenTimeAccess() }
        .fullScreenCover(isPresented: $showingReview) { ScreenTimeProposalView(store: store) }
        .sheet(isPresented: $showingObservations, onDismiss: {
            if editAfterObservations {
                editAfterObservations = false
                if let onEdit { onEdit() } else { store.tab = .routine }
            } else if learnAfterObservations {
                learnAfterObservations = false
                if returnsToLearn { dismiss() } else { store.tab = .learn }
            }
        }) {
            NavigationStack {
                ObservationHistoryView(store: store, onLearn: {
                    learnAfterObservations = true; showingObservations = false
                }, onEdit: {
                    editAfterObservations = true; showingObservations = false
                })
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingObservations = false } } }
            }
        }
        .onChange(of: store.dataGeneration) { _, _ in showingReview = false; showingObservations = false }
    }

    private func dailyUse(_ day: ScreenTimeDailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.day.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted).locale(AppLanguage.locale))).font(MorningTheme.Typography.label)
            ForEach(day.summary.apps.prefix(5)) { app in
                HStack {
                    Text(app.name)
                    Spacer()
                    Text(app.roundedMinutes == 0 ? AppLanguage.localized("Less than 1 min") : AppLanguage.localized("\(app.roundedMinutes) min")).monospacedDigit()
                }.font(MorningTheme.Typography.note)
            }
            Text("Returned app use. Missing days stay unknown.")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
        }.accessibilityIdentifier("screenTime.daily.\(day.day.timeIntervalSinceReferenceDate)")
    }
}

/// First-run destination: connect the one useful source, then review its real
/// proposal. The full learning toolbox remains an explicit Settings destination.
struct MorningRoutinePreparationView: View {
    @Bindable var store: MorningStore
    var onClose: () -> Void
    @State private var checkedExistingAccess = false

    var body: some View {
        Group {
            if store.pendingScreenTimeProposal != nil {
                ScreenTimeProposalView(store: store, embedded: true, onFinished: onClose)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        MorningQuietLandscape(scene: MorningThemeClock.shared.celestial,
                                              weather: MorningThemeClock.shared.weatherScene,
                                              animated: false, active: false)
                            .frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 24))
                            .accessibilityHidden(true)
                        Text("Your morning takes shape.").font(MorningTheme.Typography.title)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("routinePreparation.heading")
                        Text("MORE uses the app-use times you allow to suggest a routine. You review it before anything starts.")
                            .foregroundStyle(MorningStyle.muted)
                        if store.screenTimeBusy {
                            HStack(spacing: 12) { ProgressView(); Text("Reading your last mornings…") }
                                .accessibilityIdentifier("routinePreparation.reading")
                        } else {
                            if let message = store.screenTimeMessage {
                                Text(message).font(MorningTheme.Typography.note)
                                    .accessibilityIdentifier("routinePreparation.message")
                            } else if store.screenTimeAccess == .unavailable {
                                Text(store.screenTimeAccessExplanation).font(MorningTheme.Typography.note)
                            }
                            Button(store.screenTimeAccess == .approved ? AppLanguage.localized("Refresh app use") : AppLanguage.localized("Connect Screen Time")) {
                                store.learnFromScreenTime()
                            }.buttonStyle(PrimaryButtonStyle())
                                .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.screenTimeAccess == .unavailable)
                                .accessibilityIdentifier("routinePreparation.connect")
                        }
                        Text("No data yet? You can continue and return to Your routine in Settings. Nothing is guessed or started for you.")
                            .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                        Button("Continue for now", action: onClose)
                            .buttonStyle(SecondaryButtonStyle())
                            .accessibilityIdentifier("routinePreparation.later")
                    }.frame(maxWidth: 560, alignment: .leading).padding(28).frame(maxWidth: .infinity)
                }.scrollBounceBehavior(.basedOnSize)
                    .accessibilityIdentifier("routinePreparation.content")
            }
        }
        .background { MorningEntryBackdrop() }
        .foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .font(MorningTheme.Typography.body)
        .navigationTitle("Your morning").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard !checkedExistingAccess else { return }
            checkedExistingAccess = true
            store.refreshScreenTimeAccess()
            // Reuse a saved review on relaunch. Reading never means approval.
            if store.pendingScreenTimeProposal == nil, store.screenTimeAccess == .approved {
                store.learnFromScreenTime()
            }
        }
    }
}

/// Approval installs precisely the reviewed rows. Screen Time order and any
/// apportioned partial-hour minutes remain marked as estimates.
struct ScreenTimeProposalView: View {
    @Bindable var store: MorningStore
    var embedded = false
    var onFinished: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var showingDetails = false

    private func finish() {
        if let onFinished { onFinished() } else { dismiss() }
    }

    @ViewBuilder var body: some View {
        if embedded { proposalContent }
        else { NavigationStack { proposalContent } }
    }

    private var proposalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let proposal = store.pendingScreenTimeProposal {
                    Text("Here is what your morning looks like.")
                        .font(MorningTheme.Typography.title).accessibilityAddTraits(.isHeader)
                    Text("From \(proposal.morningsUsed) comparable mornings. Order is estimated.")
                        .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("screenTimeProposal.sources")
                    ForEach(Array(proposal.steps.enumerated()), id: \.element.id) { index, step in
                        Card { stepRow(step, index: index) }
                    }
                    Text("You can connect your websites later in Settings. Approving this routine does not start it.")
                        .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("screenTimeProposal.connectionsLater")
                    Text(AppLanguage.isFrench ? "MORE s’occupe des actions présentées ici. Vous pouvez l’interrompre à tout moment." : "MORE takes care of the actions shown here. You can interrupt at any time.")
                        .font(MorningTheme.Typography.note)
                    DisclosureGroup("About this suggestion", isExpanded: $showingDetails) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Measured minutes come from complete hourly segments inside the detected morning. Other minutes are estimated from a partial hour.")
                            Text("Long app use does not prove scrolling. Choose the budget you want.")
                            Text("Your current routine stays ready until you approve. Approving replaces it with the moments you keep here.")
                        }.padding(.top, 12)
                    }.font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                } else {
                    Text("Your routine may have changed. Learn from Screen Time again for a fresh suggestion.")
                        .accessibilityIdentifier("screenTimeProposal.unavailable")
                }
                if let notice = store.notice { Text(notice).font(MorningTheme.Typography.note) }
            }.frame(maxWidth: 560, alignment: .leading).padding(24).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background { MorningEntryBackdrop() }
        .navigationTitle("Your morning").navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done", action: finish).accessibilityIdentifier("screenTimeProposal.close")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                // First-run Later retains the proposal for the next visit.
                Button(embedded ? AppLanguage.localized("Later") : AppLanguage.localized("Keep current")) {
                    if embedded || store.discardPendingScreenTimeProposal() { finish() }
                }
                .disabled(store.busy || store.screenTimeBusy)
                .accessibilityIdentifier(embedded ? "routinePreparation.later" : "screenTimeProposal.keepCurrent")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let proposal = store.pendingScreenTimeProposal {
                Button(AppLanguage.isFrench ? "Confier ce matin à MORE" : "Let MORE take care of this morning") {
                    if store.approvePendingScreenTimeProposal() { finish(); store.tab = .today }
                }.buttonStyle(PrimaryButtonStyle()).padding(20).frame(maxWidth: .infinity)
                    .background(MorningStyle.background)
                    .disabled(store.busy || store.screenTimeBusy || store.sessionActive || !store.storageIsAvailable || proposal.includedSteps.isEmpty || !proposal.isCurrent(preferences: store.routinePreferences))
                    .accessibilityIdentifier("screenTimeProposal.approve")
            }
        }
    }

    private func stepRow(_ step: ScreenTimeRoutineProposal.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { step.included }, set: { value in
                store.editPendingScreenTimeProposal { $0.setIncluded(value, stepID: step.id) }
            })) {
                Text(step.suggestedStep.title).font(MorningTheme.Typography.heading)
                    .accessibilityIdentifier("screenTimeProposal.step.\(index)")
            }.accessibilityIdentifier("screenTimeProposal.include.\(index)")
            if step.retainedStep != nil {
                Text(AppLanguage.isFrench ? "Gardé selon votre choix" : "Kept by your choice")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if !step.suggestedStep.detail.isEmpty {
                    Text(step.suggestedStep.detail).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                }
            } else {
                Text(step.minutesMeasured ? AppLanguage.localized("Minutes measured") : AppLanguage.localized("Minutes estimated"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("screenTimeProposal.label.\(index)")
            }
            Text(step.suggestedStep.executionDescription).font(.raleway(.subheadline))
                .accessibilityIdentifier("screenTimeProposal.execution.\(index)")
            if let explanation = step.executionExplanation {
                Text(explanation).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if let target = step.suggestedTarget {
                Text("Opens \(target.destination.displayName)").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if step.included {
                Stepper("\(step.minutes) min planned", value: Binding(get: { step.minutes }, set: { value in
                    store.editPendingScreenTimeProposal { $0.setMinutes(value, stepID: step.id) }
                }), in: step.allowedMinutesRange)
                    .font(MorningTheme.Typography.note).accessibilityIdentifier("screenTimeProposal.minutes.\(index)")
            }
        }
    }
}
