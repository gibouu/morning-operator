import SwiftUI
import MorningCore
import MorningApple

/// "Keep raw evidence for…" in Privacy (issue #8). Choosing an age removes nothing:
/// it only lists what is older, for review and explicit confirmation.
struct EvidenceRetentionSection: View {
    @Bindable var store: MorningStore
    /// Presented by the list that holds this section (`evidenceRemovalSheet`): a sheet
    /// attached to a section would be attached to each of its rows.
    @Binding var reviewing: EvidenceRemovalReview?

    private struct Choice: Identifiable {
        let days: Int?
        let label: String
        var id: String { days.map(String.init) ?? "off" }
    }

    private var choices: [Choice] {
        [Choice(days: nil, label: String(localized: "Off", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)),
         Choice(days: 30, label: String(localized: "30 days", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)),
         Choice(days: 90, label: String(localized: "90 days", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)),
         Choice(days: 365, label: String(localized: "1 year", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))]
    }

    var body: some View {
        Section {
            ForEach(choices) { choice in
                let selected = store.evidenceRetentionDays == choice.days
                Button { store.setEvidenceRetentionDays(choice.days) } label: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(choice.label).foregroundStyle(MorningStyle.ink)
                        Spacer(minLength: 8)
                        if selected {
                            Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                                .accessibilityHidden(true)
                        }
                    }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!store.canChangeEvidenceRetention)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("privacy.retention.option.\(choice.id)")
            }
            if let review = store.evidenceExpiryReview() {
                if review.isEmpty {
                    Text("Nothing is older than this right now.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("privacy.retention.nothingDue")
                } else {
                    let count = review.acquisitionIDs.count
                    LabeledContent(String(localized: "Older than this", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: String(count))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(String(localized: "Older than this", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                        .accessibilityValue(String(count))
                        .accessibilityIdentifier("privacy.retention.dueCount")
                    Button(String(localized: "Review before removing…", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { reviewing = review }
                        .disabled(store.evidenceRemovalInProgress)
                        .accessibilityIdentifier("privacy.retention.review")
                }
                if !review.unknownAgeAcquisitionIDs.isEmpty {
                    Text("\(review.unknownAgeAcquisitionIDs.count) observations have no saved import date. They are never removed by age.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("privacy.retention.unknownAge")
                }
            }
            if store.hasPendingEvidenceRemoval, !store.evidenceRemovalInProgress {
                Button(String(localized: "Finish the interrupted removal", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { store.resumeEvidenceRemovalIfNeeded() }
                    .accessibilityIdentifier("privacy.retention.resume")
            }
            if let status = store.evidenceRemovalStatus {
                Text(status).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("privacy.retention.status")
            }
        } header: {
            Text("Keep raw evidence for")
        } footer: {
            Text("Off keeps every observation until you remove it. When an age is chosen, nothing is removed until you review the list and confirm. Quotations in a routine you approved and moments you chose to keep stay.")
        }
    }
}

extension View {
    /// The expiry review sheet for `EvidenceRetentionSection`, attached once to its list.
    func evidenceRemovalSheet(store: MorningStore, review: Binding<EvidenceRemovalReview?>) -> some View {
        sheet(isPresented: Binding(get: { review.wrappedValue != nil }, set: { if !$0 { review.wrappedValue = nil } })) {
            if let current = review.wrappedValue {
                EvidenceRemovalSheet(store: store, review: current) { _ in }
            }
        }
    }
}

/// "Forget this observation…" on an observation's detail: the same review for one observation.
struct ForgetObservationButton: View {
    @Bindable var store: MorningStore
    let observationID: UUID
    var onForgotten: () -> Void
    @ViewState private var reviewing: EvidenceRemovalReview?
    @ViewState private var forgotten = false

    var body: some View {
        Button(String(localized: "Forget this observation…", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), role: .destructive) {
            reviewing = store.forgettingReview(observationID)
        }
        .disabled(store.busy || store.sessionActive || !store.privacyInventoryIsReadable || store.evidenceRemovalInProgress)
        .accessibilityIdentifier("observation.forget")
        .morningSheet(isPresented: Binding(get: { reviewing != nil }, set: { if !$0 { reviewing = nil } }), onDismiss: {
            guard forgotten else { return }
            forgotten = false
            onForgotten()
        }) {
            if let review = reviewing {
                EvidenceRemovalSheet(store: store, review: review) { forgotten = $0 }
            }
        }
        Text("Shows every copy of it first. Quotations in an unapproved draft go too; what you approved or kept stays.")
            .font(.caption).foregroundStyle(MorningStyle.muted)
    }
}

/// The review the person confirms before anything is removed. Cancel changes nothing.
struct EvidenceRemovalSheet: View {
    @Bindable var store: MorningStore
    @ViewState private var review: EvidenceRemovalReview
    var onFinished: (Bool) -> Void
    @ViewState private var changed = false
    @ViewState private var applying = false
    @ViewState private var failure: String?
    @Environment(\.dismiss) private var dismiss

    init(store: MorningStore, review: EvidenceRemovalReview, onFinished: @escaping (Bool) -> Void) {
        self.store = store
        _review = ViewState(initialValue: review)
        self.onFinished = onFinished
    }

    private var isSingle: Bool { if case .single = review.scope { true } else { false } }

    /// Copies held inside a suggestion that is set aside go with it and are not listed again.
    private var listed: [EvidenceDependentCopy] {
        review.copies.filter { !(review.setsAsidePendingSuggestion && $0.store == .pendingProposal) }
    }
    private var removed: [EvidenceDependentCopy] { listed.filter { $0.disposition == .removed } }
    private var invalidated: [EvidenceDependentCopy] { listed.filter { $0.disposition == .invalidated } }
    private var retained: [EvidenceDependentCopy] { listed.filter { $0.disposition == .separatelyRetained } }

    var body: some View {
        NavigationStack {
            MorningList {
                // The question sits in the list, not the bar, so it wraps at every text size (#8).
                Section {
                    Text(title).font(.title2.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("retention.title")
                }
                if changed {
                    Section {
                        Text("Your saved data changed after this list was shown, so nothing was removed. This is the updated list.")
                            .font(.subheadline)
                            .accessibilityIdentifier("retention.changed")
                    }
                }
                Section {
                    Text(headline).font(.title3.weight(.semibold))
                        .accessibilityIdentifier("retention.headline")
                    if case .expiry(let days) = review.scope {
                        Text("Imported before \(Date().addingTimeInterval(Double(-days) * 86_400), format: .dateTime.day().month(.wide).year()).")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    }
                    Text("Their original text, corrections, sampled screens and screen labels leave MORE on this device. Nothing else is removed unless it is listed below as removed.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                    countRow(String(localized: "Observations to remove", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), review.acquisitionIDs.count, "retention.count.observations")
                    countRow(String(localized: "Quotations removed with them", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), removed.count, "retention.count.removed")
                    countRow(String(localized: "Links and suggestions set aside", bundle: AppLanguage.bundle(), locale: AppLanguage.locale),
                             invalidated.count + (review.setsAsidePendingSuggestion ? 1 : 0), "retention.count.invalidated")
                    countRow(String(localized: "Copies kept separately", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), retained.count, "retention.count.retained")
                }
                Section {
                    ForEach(Array(review.acquisitionIDs.enumerated()), id: \.element) { index, id in
                        if let entry = store.observationArchive.entry(id: id) {
                            VStack(alignment: .leading, spacing: 4) {
                                ObservationHistoryRow(entry: entry)
                                Text(entry.importedAt.map { String(localized: "Imported: \($0.formatted(date: .abbreviated, time: .omitted))", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) } ?? String(localized: "No import date saved", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                                if let line = entry.effectiveText.split(whereSeparator: \.isNewline)
                                    .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                                    Text("“\(String(line.prefix(160)))”").font(.caption)
                                }
                                DisclosureGroup(String(localized: "Full text", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) {
                                    Text(entry.effectiveText).font(.caption).textSelection(.enabled)
                                }
                                .font(.caption).tint(MorningStyle.accent)
                            }
                                .accessibilityElement(children: .combine)
                                .accessibilityIdentifier("retention.observation.\(index)")
                        }
                    }
                } header: { Text("Observations to remove") }
                if review.removesKeptWords {
                    Section {
                        Text("A step quoting one of these observations also holds words you keep, so nothing can be removed yet. Edit that step in your routine first.")
                            .font(.subheadline)
                            .accessibilityIdentifier("retention.blocked")
                    }
                }
                if !removed.isEmpty {
                    Section {
                        copyRows(removed, prefix: "retention.removed")
                    } header: { Text("Removed with them") }
                }
                if !invalidated.isEmpty || review.setsAsidePendingSuggestion {
                    Section {
                        if review.setsAsidePendingSuggestion {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your pending suggestion").font(.subheadline.weight(.medium))
                                Text("It was prepared from what changes here, so it is set aside and has to be worked out again. Your current routine is unchanged by this.")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("retention.suggestion")
                        }
                        copyRows(invalidated, prefix: "retention.invalidated")
                    } header: { Text("No longer linked") }
                }
                if !retained.isEmpty {
                    Section {
                        copyRows(retained, prefix: "retention.retained")
                    } header: {
                        Text("Kept separately")
                    } footer: {
                        Text("These stay. Remove them where they live if you want them gone too.")
                    }
                }
                if !review.unknownAgeAcquisitionIDs.isEmpty {
                    Section {
                        Text("\(review.unknownAgeAcquisitionIDs.count) observations have no saved import date. They are never removed by age.")
                            .font(.subheadline)
                            .accessibilityIdentifier("retention.unknownAge")
                    }
                }
                if let failure {
                    Section {
                        Text(failure).font(.subheadline).accessibilityIdentifier("retention.failure")
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { dismiss() }
                        .disabled(applying)
                        .accessibilityIdentifier("retention.cancel")
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 10) {
                    if applying {
                        ProgressView(String(localized: "Removing…", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .accessibilityIdentifier("retention.progress")
                    }
                    Button(role: .destructive) { confirm() } label: {
                        Text(confirmTitle).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(applying || review.isEmpty || review.removesKeptWords)
                    .accessibilityIdentifier("retention.confirm")
                }
                .padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .interactiveDismissDisabled(applying)
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        isSingle ? String(localized: "Forget this observation?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Remove old observations?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }

    private var headline: String {
        let count = review.acquisitionIDs.count
        return isSingle ? String(localized: "This observation will be removed.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            : String(localized: "\(count) observations would be removed.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }

    private var confirmTitle: String {
        isSingle ? String(localized: "Forget this observation", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            : String(localized: "Remove \(review.acquisitionIDs.count) observations", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
    }

    private func confirm() {
        guard !applying else { return }
        applying = true
        failure = nil
        let confirmed = review
        Task { @MainActor in
            let outcome = await store.applyEvidenceRemoval(confirmed)
            applying = false
            switch outcome {
            case .removed, .cleanupPending:
                onFinished(true)
                dismiss()
            case .changed(let fresh):
                if let fresh {
                    review = fresh
                    changed = true
                } else {
                    failure = String(localized: "There is nothing left to remove here. Nothing was removed.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                }
            case .notStarted(let message):
                failure = message
            }
        }
    }

    private func countRow(_ title: String, _ value: Int, _ identifier: String) -> some View {
        LabeledContent(title, value: String(value))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(String(value))
            .accessibilityIdentifier(identifier)
    }

    /// Identical copies (the same words for the same reason in the same place, such as
    /// several saved runs) are shown once with their number.
    private func copyRows(_ copies: [EvidenceDependentCopy], prefix: String) -> some View {
        var groups: [(copy: EvidenceDependentCopy, count: Int)] = []
        for copy in copies {
            if let index = groups.firstIndex(where: { $0.copy.store == copy.store && $0.copy.reason == copy.reason
                && $0.copy.quote.map({ Array($0.utf8) }) == copy.quote.map({ Array($0.utf8) }) }) {
                groups[index].count += 1
            } else {
                groups.append((copy, 1))
            }
        }
        return ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
            VStack(alignment: .leading, spacing: 6) {
                Text(place(group.copy.store)).font(.subheadline.weight(.medium))
                if let quote = group.copy.quote {
                    Text("“\(quote)”").font(.subheadline)
                }
                if group.count > 1 {
                    Text("\(group.count) copies").font(.caption).foregroundStyle(MorningStyle.muted)
                }
                Text(group.copy.reason.explanation).font(.caption).foregroundStyle(MorningStyle.muted)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("\(prefix).\(index)")
        }
    }

    private func place(_ store: EvidenceRetentionStore) -> String {
        switch store {
        case .currentRoutine: String(localized: "Your current routine", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .previousRoutine: String(localized: "Your previous routine", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .session: String(localized: "The morning saved with your routine", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .pendingProposal: String(localized: "Your pending suggestion", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .preferenceJournal: String(localized: "A moment you chose to keep", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        case .runHistory: String(localized: "A saved morning", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        }
    }
}
