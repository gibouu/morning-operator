import SwiftUI
import MorningCore
import MorningApple

/// A dated archive of saved evidence, separate from completed routine runs.
struct ObservationHistoryView: View {
    @Bindable var store: MorningStore
    var onlyUndated = false
    var onLearn: () -> Void
    var onEdit: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewState<Bool> private var confirmingClear = false
    @ViewState<Bool> private var choosingMornings = false
    @ViewState<Set<UUID>> private var selectedIDs = []
    @ViewState<Bool> private var showingProposal = false
    @ViewState<Bool> private var learnAfterProposalDismissal = false
    @ViewState<Bool> private var editAfterProposalDismissal = false
    @ViewState<Bool> private var awaitingSuggestion = false
    @ViewState<UUID?> private var proposalBeforeRequest = nil
    @ViewState<Date> private var screenTimeReferenceDate = Date()
    @ViewState<Set<String>?> private var includedScreenTimeApps = nil
    @ViewState<Bool> private var showingPersonalChoices = true

    private var entries: [ObservationAcquisition] {
        store.observationArchive.entries
            .filter { !onlyUndated || $0.observedDate == nil }
            .sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }
    }

    private var selectedEntries: [ObservationAcquisition] { entries.filter { selectedIDs.contains($0.id) } }
    private var screenTimeSelection: ScreenTimeMomentSelection? {
        guard selectedEntries.contains(where: { $0.correctedText == nil && $0.screenTimeEvidence != nil }) else { return nil }
        return try? .init(referenceDate: screenTimeReferenceDate, includedBundleIdentifiers: includedScreenTimeApps)
    }
    private var screenTimeChoices: [ScreenTimeAppMomentChoice] {
        guard let screenTimeSelection else { return [] }
        return (try? LearningEvidencePreparation.screenTimeAppChoices(acquisitions: selectedEntries, selection: screenTimeSelection)) ?? []
    }
    private var screenTimeReviewRevision: String? {
        try? LearningEvidencePreparation.screenTimeSelectionReviewRevision(acquisitions: selectedEntries,
            routine: store.routine, preferences: store.routinePreferences)
    }
    private var holdsEntry: Bool { choosingMornings || confirmingClear || learnAfterProposalDismissal || editAfterProposalDismissal }
    private var selectionIssue: String? {
        guard !selectedIDs.isEmpty else { return AppLanguage.localized("Choose one to five observations.") }
        guard selectedIDs.count <= 5 else { return AppLanguage.localized("Choose at most five observations for one update.") }
        guard selectedEntries.count == selectedIDs.count else { return AppLanguage.localized("A selected observation was removed. Clear the selection and choose again.") }
        if selectedEntries.contains(where: { eligibilityIssue($0) != nil }) { return AppLanguage.localized("Check the date, origin and notes of your selected observations.") }
        guard Set(selectedEntries.compactMap { $0.observedDate?.timeZoneIdentifier }).count == 1 else { return AppLanguage.localized("Choose observations from one time zone for this update.") }
        guard Set(selectedEntries.map { $0.origin.rawValue }).count == 1 else { return AppLanguage.localized("Choose personal mornings or samples separately.") }
        return nil
    }
    private var selectionSummary: String {
        let days = Set(selectedEntries.compactMap { $0.observedDate?.dayKey }).count
        let prefix = selectedEntries.first?.origin == .synthetic ? AppLanguage.localized("Sample update · ") : ""
        let count = selectedIDs.count
        return prefix + AppLanguage.localized("\(count) observations across \(days) dated days")
    }

    var body: some View {
        MorningList {
            Section {
                Text(onlyUndated
                     ? String(localized: "These observations need a day before they can appear in your morning history. The day a file was imported doesn't tell us when it was recorded.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                     : String(localized: "Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
            if store.pendingRoutineProposal != nil {
                Section {
                    Button { showingProposal = true } label: {
                        Label("Review suggested update", systemImage: "list.bullet.clipboard")
                    }.accessibilityIdentifier("observations.reviewProposal")
                } footer: { Text("Your current routine stays in place until you approve the update.") }
            }
            if choosingMornings {
                Section {
                    Text("Choose dated observations from your own mornings, or a separate set of samples. Nothing is selected automatically.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Text(AppLanguage.isFrench ? "Vous pouvez réunir les agrégats Screen Time, vidéos et leçons navigateur sélectionnés."
                        : "You can combine the selected Screen Time aggregates, videos and browser lessons.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    if dynamicTypeSize.isAccessibilitySize { selectionDetails }
                    if store.usesSyntheticProposalFixture {
                        Text("Synthetic suggestion test — no Apple model call")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("observations.fixtureMode")
                    }
                    if !store.canSuggestSavedObservations {
                        Text("\(store.intelligence.capabilitySummary) Your saved observations remain available.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("observations.modelUnavailable")
                    }
                    if store.busy {
                        ProgressView(store.analysisStatus).font(.raleway(.subheadline))
                        Button("Stop analysis") { store.cancelAnalysis() }
                            .accessibilityIdentifier("observations.cancelAnalysis")
                    }
                }
            }
            if entries.isEmpty {
                ContentUnavailableView(onlyUndated ? String(localized: "Every observation has a date", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "No saved observations", bundle: AppLanguage.bundle(), locale: AppLanguage.locale),
                    systemImage: "sun.horizon", description: Text(onlyUndated ? String(localized: "New undated imports will appear here.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Record or import a little of your morning in Learn.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
            } else {
                Section {
                    ForEach(entries) { entry in
                        if choosingMornings { selectionRow(entry) }
                        else {
                            NavigationLink {
                                ObservationHistoryDetail(store: store, observationID: entry.id, onLearn: onLearn)
                            } label: {
                                ObservationHistoryRow(entry: entry)
                            }.accessibilityIdentifier("observation.row.\(entry.id.uuidString)")
                        }
                    }
                }
            }
            if choosingMornings, !screenTimeChoices.isEmpty { screenTimeAppChoices }
            if !onlyUndated, !entries.isEmpty, !choosingMornings {
                Section {
                    Button("Delete all observations", role: .destructive) { confirmingClear = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observations.deleteAll")
                }
            }
            if let notice = store.notice {
                Section { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("observations.notice") }
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle(onlyUndated ? String(localized: "Date needed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Observations", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
        .accessibilityIdentifier("observations.list")
        .toolbar {
            if !onlyUndated, !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(choosingMornings ? String(localized: "Done choosing", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Choose mornings", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { choosingMornings.toggle() }
                        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable)
                        .accessibilityIdentifier("observations.choose")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if choosingMornings { suggestionControls }
        }
        .onChange(of: holdsEntry) { _, presented in store.observationSelectionPresented = presented }
        .onAppear { if holdsEntry { store.observationSelectionPresented = true } }
        .onDisappear { if holdsEntry { store.observationSelectionPresented = false } }
        .onChange(of: store.pendingRoutineProposal?.id) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.busy) { _, _ in finishSuggestionIfReady() }
        .onChange(of: selectedIDs) { _, _ in
            screenTimeReferenceDate = Date()
            includedScreenTimeApps = nil
        }
        .onChange(of: screenTimeReviewRevision) { _, _ in
            screenTimeReferenceDate = Date()
            includedScreenTimeApps = nil
        }
        .morningSheet(isPresented: $showingProposal, onDismiss: {
            if editAfterProposalDismissal {
                editAfterProposalDismissal = false
                choosingMornings = false
                if let onEdit { onEdit() } else { store.tab = .routine }
            } else if learnAfterProposalDismissal {
                onLearn()
                learnAfterProposalDismissal = false
            }
        }) {
            RoutineEvidenceProposalView(store: store, onLearn: {
                learnAfterProposalDismissal = true
                showingProposal = false
            }, onEdit: {
                editAfterProposalDismissal = true
                showingProposal = false
            })
        }
        .alert("Delete all observations?", isPresented: $confirmingClear) {
            Button("Delete all", role: .destructive) { _ = store.clearAllObservations() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all saved original text, corrections, sampled frame evidence and screen interpretations. Your routines, saved runs and any recording awaiting recovery remain.")
        }
    }

    private func selectionRow(_ entry: ObservationAcquisition) -> some View {
        let selected = selectedIDs.contains(entry.id)
        let issue = eligibilityIssue(entry) ?? compatibilityIssue(entry)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                if selected { selectedIDs.remove(entry.id) }
                else { selectedIDs.insert(entry.id) }
            } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.serif(.title3)).frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(store.busy || store.sessionActive || (!selected && (issue != nil || selectedIDs.count >= 5)))
            .accessibilityLabel("Select \(entry.sourceLabel)")
            .accessibilityValue(selected ? String(localized: "Selected", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Not selected", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
            .accessibilityIdentifier("observation.select.\(entry.id.uuidString)")
            NavigationLink {
                ObservationHistoryDetail(store: store, observationID: entry.id, onLearn: onLearn)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    ObservationHistoryRow(entry: entry)
                    if let issue { Text(issue).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                }
            }.accessibilityIdentifier("observation.row.\(entry.id.uuidString)")
        }
    }

    private var suggestionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !dynamicTypeSize.isAccessibilitySize { selectionDetails }
            Button {
                proposalBeforeRequest = store.pendingRoutineProposal?.id
                awaitingSuggestion = true
                screenTimeReferenceDate = Date()
                store.suggestRoutine(from: selectedIDs, screenTimeSelection: screenTimeSelection)
                finishSuggestionIfReady()
            } label: {
                Label(dynamicTypeSize.isAccessibilitySize
                      ? (AppLanguage.isFrench ? "Proposer" : "Suggest") : AppLanguage.localized("Suggest an update"), systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Suggest an update")
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectionIssue != nil || store.busy || store.sessionActive || !store.storageIsAvailable || !store.canSuggestSavedObservations)
            .accessibilityIdentifier("observations.suggestUpdate")
        }.padding(20).background(.regularMaterial)
    }

    private var selectionDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectionSummary).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("observations.selectionSummary")
                Spacer()
                if !selectedIDs.isEmpty {
                    Button("Clear selection") { selectedIDs.removeAll() }
                        .font(.raleway(.caption)).disabled(store.busy).accessibilityIdentifier("observations.clearSelection")
                }
            }
            if let selectionIssue { Text(selectionIssue).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
        }
    }

    private var screenTimeAppChoices: some View {
        Section {
            Text(AppLanguage.isFrench
                ? "Choisissez les apps à ajouter comme moments distincts. Les séquences observées et vos rituels gardés restent dans le plan. Jusqu’à huit moments d’app peuvent être ajoutés."
                : "Choose apps to add as separate moments. Observed sequences and your kept rituals stay in the plan. Up to eight app moments can be added.")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            if !store.routinePreferences.entries.isEmpty {
                DisclosureGroup(AppLanguage.isFrench ? "Vos choix personnels conservés" : "Your saved personal choices",
                    isExpanded: $showingPersonalChoices) {
                    ForEach(store.routinePreferences.entries) { choice in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(choice.targetTitle).font(.raleway(.subheadline))
                            Text(choice.presence == .keep ? (AppLanguage.isFrench ? "Garder" : "Keep")
                                : choice.presence == .exclude ? (AppLanguage.isFrench ? "Exclure" : "Exclude")
                                : (AppLanguage.isFrench ? "Durée personnalisée" : "Custom duration"))
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            if let minutes = choice.durationMinutes ?? choice.retainedStep?.durationMinutes {
                                Text(AppLanguage.isFrench ? "\(minutes) min conservées" : "\(minutes) min retained")
                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            }
                        }
                    }
                }.accessibilityIdentifier("observations.screenTime.personalChoices")
                Text(AppLanguage.isFrench
                    ? "Un ancien nom peut ne plus désigner une app connue. Relisez ces choix et les apps ci-dessous. Confirmer les apps de cette suggestion ne modifie aucun choix personnel et ne valide pas la routine."
                    : "An earlier name may no longer identify a known app. Review these choices and the apps below. Confirming apps for this suggestion changes no personal choice and does not approve the routine.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            ForEach(screenTimeChoices.filter(\.isEligible)) { choice in
                Toggle(isOn: Binding(get: { choice.isIncluded }, set: { included in
                    var ids = includedScreenTimeApps ?? Set(screenTimeChoices.filter { $0.isEligible && !$0.isAmbiguous }.map(\.id))
                    if included { ids.insert(choice.id) } else { ids.remove(choice.id) }
                    includedScreenTimeApps = ids
                })) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(choice.name).font(.raleway(.subheadline))
                        Text(AppLanguage.isFrench ? "\(choice.plannedMinutes ?? 0) min prévues · ordre estimé" : "\(choice.plannedMinutes ?? 0) min planned · estimated order")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        if choice.isAmbiguous {
                            Text(AppLanguage.isFrench ? "Ces apps portent le même nom. Relisez leurs sources ou ajoutez une vidéo ou une leçon navigateur pour les distinguer."
                                : "These apps share the same name. Review their sources or add a video or browser lesson to distinguish them.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                }.disabled(store.busy || store.sessionActive || choice.isAmbiguous)
                    .accessibilityIdentifier("observations.screenTime.app.\(choice.id)")
            }
            if screenTimeChoices.contains(where: { $0.isEligible && !$0.isAmbiguous }) {
                Button(AppLanguage.isFrench ? "Confirmer les apps de cette suggestion" : "Confirm apps for this suggestion") {
                    includedScreenTimeApps = Set(screenTimeChoices.filter { $0.isIncluded }.map(\.id))
                }.disabled(store.busy || store.sessionActive)
                    .accessibilityIdentifier("observations.screenTime.confirmApps")
                if includedScreenTimeApps != nil {
                    Text(AppLanguage.isFrench ? "Choix d’apps confirmé pour cette suggestion. La routine attend toujours votre validation."
                        : "App choices confirmed for this suggestion. The routine still needs your approval.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("observations.screenTime.appsConfirmed")
                }
            }
            if screenTimeChoices.contains(where: { !$0.isEligible }) {
                DisclosureGroup(AppLanguage.isFrench ? "Apps conservées comme sources uniquement" : "Apps kept as sources only") {
                    Text(ScreenTimeAppMomentChoice.policyExplanation)
                    ForEach(screenTimeChoices.filter { !$0.isEligible }) { choice in Text(choice.name) }
                }.font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            Text(AppLanguage.isFrench
                ? "Ce choix concerne les nouveaux moments. Les agrégats peuvent toujours éclairer une séquence observée de la même app ; aucun total n’est réparti entre les gestes."
                : "This choice concerns new moments. Aggregates may still support an observed sequence of the same app; no total is divided between gestures.")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
        } header: {
            Text(AppLanguage.isFrench ? "Moments d’app depuis Screen Time" : "App moments from Screen Time")
        }
    }

    private func eligibilityIssue(_ entry: ObservationAcquisition) -> String? {
        if entry.observedDate == nil { return AppLanguage.localized("Set the observed day before using this observation.") }
        if entry.origin == .unknown { return AppLanguage.localized("Confirm whether this is your morning or a sample.") }
        if entry.origin == .automated { return AppLanguage.localized("Automated activity isn't used to learn a personal morning.") }
        if entry.effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return AppLanguage.localized("Add readable notes before using this observation.") }
        return nil
    }

    private func compatibilityIssue(_ entry: ObservationAcquisition) -> String? {
        guard !selectedIDs.contains(entry.id), let first = selectedEntries.first else { return nil }
        if first.origin != entry.origin { return AppLanguage.localized("Choose personal mornings and samples separately.") }
        if first.observedDate?.timeZoneIdentifier != entry.observedDate?.timeZoneIdentifier { return AppLanguage.localized("Choose observations from the same time zone.") }
        if selectedIDs.count >= 5 { return AppLanguage.localized("Five observations selected; remove one to choose another.") }
        return nil
    }

    private func finishSuggestionIfReady() {
        guard awaitingSuggestion, !store.busy else { return }
        awaitingSuggestion = false
        if let id = store.pendingRoutineProposal?.id, id != proposalBeforeRequest {
            choosingMornings = false
            showingProposal = true
        }
    }
}

struct ObservationHistoryRow: View {
    let entry: ObservationAcquisition

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(entry.sourceLabel).font(.raleway(.subheadline, .medium)).lineLimit(2)
            Text(observationDateLabel(entry)).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            if let zone = entry.observedDate?.timeZoneIdentifier {
                Text(zone.replacingOccurrences(of: "_", with: " "))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if entry.origin != .human {
                Text(observationOriginLabel(entry.origin)).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if let evidence = entry.screenTimeEvidence {
                Text(evidence.hasMorningEvidence
                    ? (AppLanguage.isFrench ? "Agrégats du matin · ordre estimé" : "Morning aggregates · estimated order")
                    : (AppLanguage.isFrench ? "Fenêtre du matin inconnue" : "Morning window unknown"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
        }.padding(.vertical, 4)
    }
}

struct ObservationHistoryDetail: View {
    @Bindable var store: MorningStore
    let observationID: UUID
    var onLearn: () -> Void
    var managesEntryOccupancy = true
    @ViewState<Bool> private var assigningDate = false
    @ViewState<Bool> private var confirmingDelete = false
    @ViewState<Bool> private var preparingNarration = false
    @Environment(\.dismiss) private var dismiss

    private var entry: ObservationAcquisition? { store.observationArchive.entry(id: observationID) }

    var body: some View {
        MorningList {
            if let entry {
                Section {
                    Text(entry.sourceLabel).font(.serif(.headline))
                    LabeledContent("Observed day", value: observationDateLabel(entry))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Observed day")
                        .accessibilityValue(observationDateLabel(entry))
                        .accessibilityIdentifier("observation.observedDate")
                    if let date = entry.observedDate {
                        LabeledContent("Time zone", value: date.timeZoneIdentifier)
                        Text(date.provenance == .screenTimeReport
                             ? (AppLanguage.isFrench ? "Jour et fuseau du rapport Screen Time." : "Day and time zone of the Screen Time report.")
                             : (date.provenance == .recordingSession ? String(localized: "Day recorded by this recording session.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Day assigned by you.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)))
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    LabeledContent("Origin", value: observationOriginLabel(entry.origin))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Origin")
                        .accessibilityValue(observationOriginLabel(entry.origin))
                        .accessibilityIdentifier("observation.origin")
                    LabeledContent("Imported", value: observationImportDateLabel(entry))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Imported")
                        .accessibilityValue(observationImportDateLabel(entry))
                        .accessibilityIdentifier("observation.importedDate")
                    if entry.screenTimeEvidence == nil {
                        Button(entry.observedDate == nil ? String(localized: "Set observed day", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Change day or origin", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) { assigningDate = true }
                            .disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("observation.setDate")
                    }
                } footer: {
                    Text("Import time is separate from the day you observed. These dates don't establish how long you used your phone.")
                }

                if let evidence = entry.screenTimeEvidence {
                    Section {
                        Text(evidence.hasMorningEvidence
                            ? (AppLanguage.isFrench ? "Fenêtre du matin retenue ; ordre des apps estimé." : "Retained morning window; app order is estimated.")
                            : (AppLanguage.isFrench ? "Fenêtre du matin inconnue. Ces agrégats ne proposent aucune habitude ; vous pouvez les choisir avec une vidéo ou une leçon valide." : "Morning window unknown. These aggregates propose no habit; you can select them beside a valid video or lesson."))
                            .accessibilityIdentifier("observation.screenTime.coverage")
                        Text(AppLanguage.isFrench ? "Les périodes absentes restent inconnues. Aucun contenu, geste ni usage continu n’est établi." : "Missing periods remain unknown. No content, gesture or continuous use is established.")
                        DisclosureGroup(AppLanguage.isFrench ? "Couverture du rapport" : "Report coverage") {
                            Text((AppLanguage.isFrench ? "Intervalle demandé : " : "Requested interval: ")
                                + reportIntervalLabel(evidence.requestedWindow, zone: evidence.timeZoneIdentifier))
                            Text((AppLanguage.isFrench ? "Intervalles renvoyés : " : "Returned intervals: ") + "\(evidence.returnedIntervals.count)")
                            ForEach(Array(evidence.returnedIntervals.enumerated()), id: \.offset) { _, interval in
                                Text(reportIntervalLabel(interval, zone: evidence.timeZoneIdentifier))
                            }
                            Text((AppLanguage.isFrench ? "Dernière lecture : " : "Last read: ")
                                + reportIntervalLabel(.init(start: evidence.retrievedAt, duration: 0), zone: evidence.timeZoneIdentifier))
                        }
                    }.font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                }

                if let context = entry.recordingContext {
                    Section {
                        DisclosureGroup("Recording details") {
                            LabeledContent("Started", value: observationRecordingStartLabel(context))
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("Recording started")
                                .accessibilityValue(observationRecordingStartLabel(context))
                                .accessibilityIdentifier("observation.recordingStart")
                            LabeledContent("Recording time zone", value: context.timeZoneIdentifier)
                                .accessibilityIdentifier("observation.recordingTimeZone")
                            Text("Saved when recording began. Changing the observed day keeps this information. It doesn't measure time spent in apps.")
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                }

                Section {
                    if entry.screenTimeEvidence == nil || entry.correctedText != nil {
                        Button { preparingNarration = true } label: {
                            Label("Read a saved moment", systemImage: "speaker.wave.2")
                        }
                        .disabled(store.busy || store.sessionActive || !store.storageIsAvailable)
                        .accessibilityIdentifier("observation.prepareNarration")
                    }
                    Button {
                        if store.selectObservation(id: observationID) { onLearn() }
                    } label: { Label("Edit in Learn", systemImage: "pencil") }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.edit")
                    DisclosureGroup("Current notes") {
                        Text(entry.effectiveText.isEmpty ? AppLanguage.localized("No notes saved.") : entry.effectiveText)
                            .textSelection(.enabled).font(.raleway(.subheadline))
                            .accessibilityIdentifier("observation.currentText")
                    }
                    DisclosureGroup("Original extracted text") {
                        Text(entry.originalText.isEmpty ? AppLanguage.localized("No original text was retained.") : entry.originalText)
                            .textSelection(.enabled).font(.raleway(.subheadline))
                            .accessibilityIdentifier("observation.originalText")
                    }
                } footer: {
                    Text("Corrections change the notes used for suggestions. The original evidence stays available here.")
                }

                if entry.videoEvidence != nil {
                    Section {
                        ObservationClipTimelineView(store: store, acquisition: entry)
                    } header: { Text("Recording evidence") }
                }

                if !entry.warnings.isEmpty {
                    Section {
                        ForEach(entry.warnings, id: \.rawValue) { warning in
                            Text(warning.message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                }

                Section {
                    ForgetObservationButton(store: store, observationID: observationID) { dismiss() }
                    Button("Delete this observation", role: .destructive) { confirmingDelete = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.delete")
                    if let notice = store.notice { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
                }
            } else {
                ContentUnavailableView("Observation removed", systemImage: "doc", description: Text("Your routines and saved runs are still available."))
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle("Observation")
        .accessibilityIdentifier("observation.detail")
        .onAppear { if managesEntryOccupancy { store.observationDetailPresented = true } }
        .onDisappear { if managesEntryOccupancy { store.observationDetailPresented = false } }
        .morningSheet(isPresented: $assigningDate) {
            if let entry { ObservationDateEditor(store: store, entry: entry) }
        }
        .morningSheet(isPresented: $preparingNarration) {
            ObservationNarrationView(store: store, observationID: observationID)
        }
        .alert("Delete this observation?", isPresented: $confirmingDelete) {
            Button("Delete observation", role: .destructive) {
                if store.deleteObservation(id: observationID) { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes this observation's original text, corrections, sampled frame evidence and screen interpretation. Routines and saved runs keep their existing content.")
        }
    }

    private func reportIntervalLabel(_ interval: DateInterval, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.locale
        formatter.timeZone = TimeZone(identifier: zone)
        formatter.setLocalizedDateFormatFromTemplate("dMMMyyyyjmm")
        let start = formatter.string(from: interval.start)
        return interval.duration == 0 ? start : start + " – " + formatter.string(from: interval.end)
    }
}

struct ObservationDateEditor: View {
    @Bindable var store: MorningStore
    let entry: ObservationAcquisition
    @ViewState<Date> private var date: Date
    @ViewState<String> private var zoneIdentifier: String
    @ViewState<ObservationAcquisitionOrigin> private var origin: ObservationAcquisitionOrigin
    @Environment(\.dismiss) private var dismiss

    init(store: MorningStore, entry: ObservationAcquisition) {
        self.store = store
        self.entry = entry
        _date = ViewState(initialValue: entry.observedDate?.date ?? Date())
        _zoneIdentifier = ViewState(initialValue: entry.observedDate?.timeZoneIdentifier ?? TimeZone.current.identifier)
        _origin = ViewState(initialValue: entry.origin)
    }

    private var zone: TimeZone { TimeZone(identifier: zoneIdentifier) ?? .current }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar
    }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    DatePicker("Observed day", selection: $date, displayedComponents: .date)
                        .environment(\.timeZone, zone).environment(\.calendar, calendar)
                        .accessibilityIdentifier("observation.datePicker")
                    NavigationLink {
                        ObservationTimeZonePicker(selection: $zoneIdentifier)
                    } label: { LabeledContent("Time zone", value: zoneIdentifier.replacingOccurrences(of: "_", with: " ")) }
                        .accessibilityIdentifier("observation.timeZone")
                } footer: {
                    Text("Choose the day this activity happened, in the time zone where it happened. Import time isn't used to guess this day.")
                }
                Section {
                    Picker("Whose activity is this?", selection: $origin) {
                        Text("My morning").tag(ObservationAcquisitionOrigin.human)
                        Text("Sample or test").tag(ObservationAcquisitionOrigin.synthetic)
                        Text("Automated").tag(ObservationAcquisitionOrigin.automated)
                        Text("Unsure").tag(ObservationAcquisitionOrigin.unknown)
                    }.pickerStyle(.menu).accessibilityIdentifier("observation.originPicker")
                } footer: {
                    Text("A recording doesn't tell us whether a person or automation caused the activity. Keep Unsure when you don't know.")
                }
                if entry.observedDate != nil {
                    Section {
                        Button("Leave the date unknown") {
                            if store.assignObservationDate(id: entry.id, date: nil, timeZoneIdentifier: zoneIdentifier, origin: origin) { dismiss() }
                        }.disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("observation.removeDate")
                    } footer: { Text("Moves this observation to Date needed without deleting its evidence.") }
                }
                if let notice = store.notice { Section { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) } }
            }
            .navigationTitle("Observed day")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if store.assignObservationDate(id: entry.id, date: date, timeZoneIdentifier: zoneIdentifier, origin: origin) { dismiss() }
                    }.disabled(store.busy || store.sessionActive).accessibilityIdentifier("observation.saveDate")
                }
            }
            .onChange(of: zoneIdentifier) { old, new in
                // Changing the zone must not silently move the chosen calendar day.
                var oldCalendar = Calendar(identifier: .gregorian)
                oldCalendar.timeZone = TimeZone(identifier: old) ?? .current
                var fields = oldCalendar.dateComponents([.year, .month, .day], from: date)
                fields.hour = 12
                var newCalendar = Calendar(identifier: .gregorian)
                newCalendar.timeZone = TimeZone(identifier: new) ?? .current
                if let sameDay = newCalendar.date(from: fields) { date = sameDay }
            }
        }
    }
}

private struct ObservationTimeZonePicker: View {
    @Binding var selection: String
    @ViewState<String> private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var identifiers: [String] {
        TimeZone.knownTimeZoneIdentifiers.filter { search.isEmpty || $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        MorningList {
            Section {
                Button("Use current time zone: \(TimeZone.current.identifier)") { selection = TimeZone.current.identifier; dismiss() }
            }
            Section {
                ForEach(identifiers, id: \.self) { identifier in
                    Button { selection = identifier; dismiss() } label: {
                        HStack {
                            Text(identifier.replacingOccurrences(of: "_", with: " ")).foregroundStyle(.primary)
                            Spacer()
                            if identifier == selection { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }.searchable(text: $search, prompt: "Search city or region").navigationTitle("Time zone")
    }
}

private func observationDateLabel(_ entry: ObservationAcquisition) -> String {
    guard let value = entry.observedDate else { return AppLanguage.localized("Date needed") }
    let formatter = DateFormatter()
    formatter.locale = AppLanguage.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: value.timeZoneIdentifier)
    return formatter.string(from: value.date)
}

private func observationOriginLabel(_ origin: ObservationAcquisitionOrigin) -> String {
    switch origin {
    case .human: AppLanguage.localized("My morning")
    case .synthetic: AppLanguage.localized("Sample or test")
    case .automated: AppLanguage.localized("Automated activity")
    case .unknown: AppLanguage.localized("Origin unsure")
    }
}

private func observationImportDateLabel(_ entry: ObservationAcquisition) -> String {
    entry.importedAt?.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale)) ?? AppLanguage.localized("Import date unknown")
}

private func observationRecordingStartLabel(_ context: ObservationRecordingContext) -> String {
    let formatter = DateFormatter()
    formatter.locale = AppLanguage.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: context.timeZoneIdentifier)
    return formatter.string(from: context.startedAt)
}

private func observationClassificationLabel(_ status: ObservationContextInferenceStatus) -> String {
    switch status {
    case .completed: AppLanguage.localized("Screen interpretation saved; unclear samples remain unknown.")
    case .noEligibleFrames: AppLanguage.localized("No samples have enough complete text to recognize a screen.")
    case .unavailable: AppLanguage.localized("Screen interpretation unavailable; original evidence is retained.")
    case .partialFailure: AppLanguage.localized("Some screen interpretations failed; those samples remain unknown.")
    case .failed: AppLanguage.localized("Screen interpretation failed; original evidence is retained.")
    }
}
