import SwiftUI
import MorningCore

/// The same normal Screen Time path appears in Learn and Settings. It never swaps
/// in samples when access is unavailable. The read and daily results stay local.
struct MorningScreenTimeView: View {
    @Bindable var store: MorningStore
    @State private var showingReview = false
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
                    Button(store.screenTimeAccess == .approved ? String(localized: "Refresh app use") : String(localized: "Connect Screen Time")) {
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
        .onChange(of: store.dataGeneration) { _, _ in showingReview = false }
    }

    private func dailyUse(_ day: ScreenTimeDailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(day.day.formatted(date: .abbreviated, time: .omitted)).font(MorningTheme.Typography.label)
            ForEach(day.summary.apps.prefix(5)) { app in
                HStack {
                    Text(app.name)
                    Spacer()
                    Text(app.roundedMinutes == 0 ? String(localized: "Less than 1 min") : String(localized: "\(app.roundedMinutes) min")).monospacedDigit()
                }.font(MorningTheme.Typography.note)
            }
            Text("Returned app use. Missing days stay unknown.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
        }.accessibilityIdentifier("screenTime.daily.\(day.day.timeIntervalSinceReferenceDate)")
    }
}

/// Approval installs precisely the reviewed rows. Screen Time order and any
/// apportioned partial-hour minutes remain marked as estimates.
struct ScreenTimeProposalView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MorningList {
                if let proposal = store.pendingScreenTimeProposal {
                    Section {
                        Text("Your morning, from Screen Time").font(MorningTheme.Typography.heading)
                        Text("From \(proposal.morningsUsed) comparable mornings. Order is estimated.")
                            .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                        ForEach(Array(proposal.steps.enumerated()), id: \.element.id) { index, step in
                            stepRow(step, index: index)
                        }
                    }
                    Section {
                        Text("Measured minutes come from complete hourly segments inside the detected morning. Other minutes are estimated from a partial hour.")
                        Text("Long app use does not prove scrolling. Choose the budget you want.")
                        Text("Your current routine stays ready until you approve. Approving replaces it with the apps you keep here.")
                    }.font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                } else {
                    Text("Your routine may have changed. Learn from Screen Time again for a fresh suggestion.")
                        .accessibilityIdentifier("screenTimeProposal.unavailable")
                }
                if let notice = store.notice { Text(notice).font(MorningTheme.Typography.note) }
            }
            .navigationTitle("Your morning, from Screen Time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Keep current") { if store.discardPendingScreenTimeProposal() { dismiss() } }
                        .disabled(store.busy || store.screenTimeBusy).accessibilityIdentifier("screenTimeProposal.keep")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let proposal = store.pendingScreenTimeProposal {
                    Button("Approve update") {
                        if store.approvePendingScreenTimeProposal() { dismiss(); store.tab = .today }
                    }.buttonStyle(PrimaryButtonStyle()).padding(20).frame(maxWidth: .infinity)
                        .background(MorningStyle.background)
                        .disabled(store.busy || store.screenTimeBusy || store.sessionActive || !store.storageIsAvailable || proposal.includedSteps.isEmpty)
                        .accessibilityIdentifier("screenTimeProposal.approve")
                }
            }
        }
    }

    private func stepRow(_ step: ScreenTimeRoutineProposal.Step, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { step.included }, set: { value in
                store.editPendingScreenTimeProposal { $0.setIncluded(value, stepID: step.id) }
            })) { Text(step.title).font(MorningTheme.Typography.heading) }
                .accessibilityIdentifier("screenTimeProposal.include.\(index)")
            Text(step.minutesMeasured ? String(localized: "Minutes measured") : String(localized: "Minutes estimated"))
                .font(.caption).foregroundStyle(MorningStyle.muted)
            if let target = step.suggestedTarget {
                Text("Opens \(target.destination.displayName)").font(.caption).foregroundStyle(MorningStyle.muted)
            } else {
                Text("Choose an app or page in your routine.").font(.caption).foregroundStyle(MorningStyle.muted)
            }
            if step.included {
                Stepper("\(step.minutes) min planned", value: Binding(get: { step.minutes }, set: { value in
                    store.editPendingScreenTimeProposal { $0.setMinutes(value, stepID: step.id) }
                }), in: ScreenTimeRoutineProposal.minutesRange)
                    .font(MorningTheme.Typography.note).accessibilityIdentifier("screenTimeProposal.minutes.\(index)")
            }
        }.padding(.vertical, 8)
    }
}
