import SwiftUI
import MorningCore
import MorningApple

/// A separately saved suggestion. Reading or dismissing it never replaces the ready routine.
struct RoutineEvidenceProposalView: View {
    @Bindable var store: MorningStore
    /// The presenting view dismisses this sheet before opening the existing Learn sheet.
    var onLearn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MorningList {
                if let proposal = store.pendingRoutineProposal {
                    summary(proposal)
                    if proposal.baseRoutineID != nil, let current = store.routine {
                        Section {
                            DisclosureGroup("Compare with current routine") {
                                ForEach(current.steps) { step in
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text(step.title).font(.subheadline)
                                        Spacer(minLength: 8)
                                        Text("\(step.durationMinutes) min planned").font(.caption).foregroundStyle(MorningStyle.muted)
                                    }.padding(.vertical, 4)
                                }
                            }
                        }
                    }
                    if !proposal.omissions.isEmpty {
                        Section {
                            DisclosureGroup("Samples not used (\(proposal.omissions.count))") {
                                Text("These samples weren't used to suggest activities. Missing or unsuitable evidence stays unknown.")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                                ForEach(proposal.sourceSnapshots, id: \.acquisitionID) { source in
                                    let omitted = proposal.omissions.filter { $0.acquisitionID == source.acquisitionID }
                                    if !omitted.isEmpty {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(source.sourceLabel).font(.subheadline)
                                            let incomplete = omitted.filter { $0.reason == .unavailableOrTruncatedFrame }.count
                                            let unsupported = omitted.filter { $0.reason == .unsupportedVisualContext }.count
                                            let ownInterface = omitted.filter { $0.reason == .ownInterfaceInFront }.count
                                            let reviewedUnknown = omitted.filter { $0.reason == .explicitlyReviewedUnknown }.count
                                            if reviewedUnknown > 0 { Text("\(reviewedUnknown) samples you kept unknown").font(.caption).foregroundStyle(MorningStyle.muted) }
                                            if incomplete > 0 { Text("\(incomplete) unavailable or incomplete samples").font(.caption).foregroundStyle(MorningStyle.muted) }
                                            if unsupported > 0 { Text("\(unsupported) samples without suitable activity context").font(.caption).foregroundStyle(MorningStyle.muted) }
                                            if ownInterface > 0 { Text("\(ownInterface) samples left out because MORE itself was in front").font(.caption).foregroundStyle(MorningStyle.muted) }
                                        }.padding(.vertical, 5)
                                    }
                                }
                            }
                        }
                    }
                    ForEach(Array(proposal.routine.steps.enumerated()), id: \.element.id) { index, step in
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(step.title).font(.headline)
                                    .accessibilityLabel("Suggested moment \(index + 1)")
                                    .accessibilityValue(step.title)
                                    .accessibilityIdentifier("proposal.step.\(index)")
                                if !briefDetail(step).isEmpty { Text(briefDetail(step)).font(.subheadline).foregroundStyle(MorningStyle.muted) }
                                Text("\(step.durationMinutes) minutes planned")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }.padding(.vertical, 3)
                            if let support = proposal.support.first(where: { $0.stepID == step.id }) {
                                if support.reason == .preservedUserDecision {
                            Label("Kept by your choice", systemImage: "heart")
                                        .font(.caption).foregroundStyle(MorningStyle.muted)
                                } else {
                                    if support.reason == .inferredEvidenceWithUserPreference {
                                        Label("Your saved timing choice", systemImage: "clock.badge.checkmark")
                                            .font(.caption).foregroundStyle(MorningStyle.muted)
                                            .accessibilityIdentifier("proposal.userTiming")
                                    }
                                    DisclosureGroup("Why this suggestion?") {
                                        ForEach(Array(support.citations.enumerated()), id: \.offset) { quoteIndex, citation in
                                            VStack(alignment: .leading, spacing: 8) {
                                                Text("“\(citation.quote)”").font(.subheadline).textSelection(.enabled)
                                                    .accessibilityIdentifier("proposal.quote.\(step.id.uuidString).\(quoteIndex)")
                                                if let source = proposal.sourceSnapshots.first(where: { $0.acquisitionID == citation.acquisitionID }) {
                                                    Text("\(proposalDateLabel(source.observedDate)) · \(citation.sourceLayer.displayName)")
                                                        .font(.caption).foregroundStyle(MorningStyle.muted)
                                                    Text(source.sourceLabel).font(.caption).foregroundStyle(MorningStyle.muted)
                                                }
                                            }.padding(.vertical, 6)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Section {
                        ForEach(proposal.sourceSnapshots, id: \.acquisitionID) { source in
                            NavigationLink {
                                ObservationHistoryDetail(store: store, observationID: source.acquisitionID,
                                    onLearn: onLearn, managesEntryOccupancy: false)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.sourceLabel).font(.subheadline)
                                    Text("\(proposalDateLabel(source.observedDate)) · \(source.sourceLayer.displayName)")
                                        .font(.caption).foregroundStyle(MorningStyle.muted)
                                }
                            }.accessibilityIdentifier("proposal.source.\(source.acquisitionID.uuidString)")
                        }
                    } header: { Text("Selected observations") } footer: {
                        Text("Correct a source in Learn to request a new suggestion.")
                    }
                    Section {
                        DisclosureGroup("About this suggestion") {
                            Text("Minutes are planned, not measured averages. Visible words don't prove an action or a repeated habit.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                            Text("Done saves this suggestion for later. You can edit your current routine under Review → Your routine.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                            if proposal.sourceSnapshots.first?.origin == .synthetic {
                                Text("Sample observations stay separate from your personal habit history.")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Suggestion no longer available", systemImage: "doc.text.magnifyingglass",
                        description: Text("The observations or your routine may have changed. Choose the mornings again to make a fresh suggestion."))
                        .accessibilityIdentifier("proposal.unavailable")
                }
                if let notice = store.notice {
                    Section { Text(notice).font(.caption).foregroundStyle(MorningStyle.muted) }
                }
            }
            .scrollContentBackground(.hidden).background(MorningStyle.background)
            .navigationTitle("Suggested update")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.accessibilityIdentifier("proposal.close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let proposal = store.pendingRoutineProposal {
                    VStack(alignment: .leading, spacing: 10) {
                        if store.sessionActive {
                            Text("Finish or end your current morning before approving an update.")
                                .font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                        HStack(spacing: 12) {
                            Button(store.routine == nil ? "Discard" : "Keep current") {
                                if store.discardPendingRoutineProposal() { dismiss() }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                            .disabled(store.busy || !store.storageIsAvailable)
                            .accessibilityIdentifier("proposal.keepCurrent")
                            Button {
                                if store.approvePendingRoutineProposal() {
                                    dismiss()
                                    store.tab = .today
                                }
                            } label: {
                                Label("Approve update", systemImage: "checkmark").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(store.busy || store.sessionActive || !store.storageIsAvailable || store.routinePreferencesIssue != nil || proposal.routine.steps.isEmpty)
                            .accessibilityIdentifier("proposal.approve")
                        }
                    }.padding(20).background(.regularMaterial)
                }
            }
        }
        .onAppear { store.routineProposalPresented = true }
        .onDisappear { store.routineProposalPresented = false }
    }

    private func summary(_ proposal: EvidenceRoutineProposal) -> some View {
        let dayCount = Set(proposal.sourceSnapshots.map { $0.observedDate.dayKey }).count
        let isSample = proposal.sourceSnapshots.first?.origin == .synthetic
        return Section {
            VStack(alignment: .leading, spacing: 10) {
                Text(isSample ? "Sample morning" : "Your next morning")
                    .font(.system(.title2, design: .serif, weight: .medium))
                Text("Selected: \(proposal.sourceSnapshots.count) observations across \(dayCount) dated days")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("proposal.sources")
                Text(store.routine == nil ? "Review your moments, then approve when ready."
                     : "Your current routine stays ready until you approve.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                if store.usesSyntheticProposalFixture {
                    Text("Synthetic suggestion test — no Apple model call")
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("proposal.fixtureMode")
                }
            }.padding(.vertical, 4)
        }
    }

    private func briefDetail(_ step: RoutineStep) -> String {
        guard let support = store.pendingRoutineProposal?.support.first(where: { $0.stepID == step.id }),
              support.reason == .inferredEvidence,
              let description = EvidenceDetailText.description(of: step.detail,
                  citing: support.citations.map(\.quote)) else { return step.detail }
        return description.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func proposalDateLabel(_ value: ObservationObservedDate) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: value.timeZoneIdentifier)
    return formatter.string(from: value.date)
}
