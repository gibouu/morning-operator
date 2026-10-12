import SwiftUI
import MorningCore
import MorningApple

/// A dated archive of saved evidence, separate from completed routine runs.
struct ObservationHistoryView: View {
    @Bindable var store: MorningStore
    var onlyUndated = false
    var onLearn: () -> Void
    @ViewState<Bool> private var confirmingClear = false
    @ViewState<Bool> private var choosingMornings = false
    @ViewState<Set<UUID>> private var selectedIDs = []
    @ViewState<Bool> private var showingProposal = false
    @ViewState<Bool> private var learnAfterProposalDismissal = false
    @ViewState<Bool> private var awaitingSuggestion = false
    @ViewState<UUID?> private var proposalBeforeRequest = nil

    private var entries: [ObservationAcquisition] {
        store.observationArchive.entries
            .filter { !onlyUndated || $0.observedDate == nil }
            .sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }
    }

    private var selectedEntries: [ObservationAcquisition] { entries.filter { selectedIDs.contains($0.id) } }
    private var holdsEntry: Bool { choosingMornings || confirmingClear || learnAfterProposalDismissal }
    private var selectionIssue: String? {
        guard !selectedIDs.isEmpty else { return String(localized: "Choose one to five observations.") }
        guard selectedIDs.count <= 5 else { return String(localized: "Choose at most five observations for one update.") }
        guard selectedEntries.count == selectedIDs.count else { return String(localized: "A selected observation was removed. Clear the selection and choose again.") }
        if selectedEntries.contains(where: { eligibilityIssue($0) != nil }) { return String(localized: "Check the date, origin and notes of your selected observations.") }
        guard Set(selectedEntries.compactMap { $0.observedDate?.timeZoneIdentifier }).count == 1 else { return String(localized: "Choose observations from one time zone for this update.") }
        guard Set(selectedEntries.map { $0.origin.rawValue }).count == 1 else { return String(localized: "Choose personal mornings or samples separately.") }
        return nil
    }
    private var selectionSummary: String {
        let days = Set(selectedEntries.compactMap { $0.observedDate?.dayKey }).count
        let prefix = selectedEntries.first?.origin == .synthetic ? String(localized: "Sample update · ") : ""
        let count = selectedIDs.count
        return prefix + String(localized: "\(count) observations across \(days) dated days")
    }

    var body: some View {
        List {
            Section {
                Text(onlyUndated
                     ? "These observations need a day before they can appear in your morning history. The day a file was imported doesn't tell us when it was recorded."
                     : "Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use.")
                    .font(.subheadline).foregroundStyle(.secondary)
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
                        .font(.subheadline).foregroundStyle(.secondary)
                    if store.usesSyntheticProposalFixture {
                        Text("Synthetic suggestion test — no Apple model call")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("observations.fixtureMode")
                    }
                    if !store.canSuggestSavedObservations {
                        Text("\(store.intelligence.capabilitySummary) Your saved observations remain available.")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("observations.modelUnavailable")
                    }
                    if store.busy {
                        ProgressView(store.analysisStatus).font(.subheadline)
                        Button("Stop analysis") { store.cancelAnalysis() }
                            .accessibilityIdentifier("observations.cancelAnalysis")
                    }
                }
            }
            if entries.isEmpty {
                ContentUnavailableView(onlyUndated ? "Every observation has a date" : "No saved observations",
                    systemImage: "sun.horizon", description: Text(onlyUndated ? "New undated imports will appear here." : "Record or import a little of your morning in Learn."))
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
            if !onlyUndated, !entries.isEmpty, !choosingMornings {
                Section {
                    Button("Delete all observations", role: .destructive) { confirmingClear = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observations.deleteAll")
                }
            }
            if let notice = store.notice {
                Section { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle(onlyUndated ? "Date needed" : "Observations")
        .accessibilityIdentifier("observations.list")
        .toolbar {
            if !onlyUndated, !entries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(choosingMornings ? "Done choosing" : "Choose mornings") { choosingMornings.toggle() }
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
        .sheet(isPresented: $showingProposal, onDismiss: {
            if learnAfterProposalDismissal {
                onLearn()
                learnAfterProposalDismissal = false
            }
        }) {
            RoutineEvidenceProposalView(store: store, onLearn: {
                learnAfterProposalDismissal = true
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
                    .font(.title3).frame(width: 36, height: 44)
            }
            .buttonStyle(.borderless)
            .disabled(store.busy || store.sessionActive || (!selected && (issue != nil || selectedIDs.count >= 5)))
            .accessibilityLabel("Select \(entry.sourceLabel)")
            .accessibilityValue(selected ? "Selected" : "Not selected")
            .accessibilityIdentifier("observation.select.\(entry.id.uuidString)")
            NavigationLink {
                ObservationHistoryDetail(store: store, observationID: entry.id, onLearn: onLearn)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    ObservationHistoryRow(entry: entry)
                    if let issue { Text(issue).font(.caption).foregroundStyle(.secondary) }
                }
            }.accessibilityIdentifier("observation.row.\(entry.id.uuidString)")
        }
    }

    private var suggestionControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(selectionSummary).font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("observations.selectionSummary")
                Spacer()
                if !selectedIDs.isEmpty {
                    Button("Clear selection") { selectedIDs.removeAll() }
                        .font(.caption).disabled(store.busy).accessibilityIdentifier("observations.clearSelection")
                }
            }
            if let selectionIssue { Text(selectionIssue).font(.caption).foregroundStyle(.secondary) }
            Button {
                proposalBeforeRequest = store.pendingRoutineProposal?.id
                awaitingSuggestion = true
                store.suggestRoutine(from: selectedIDs)
                finishSuggestionIfReady()
            } label: {
                Label("Suggest an update", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large)
            .disabled(selectionIssue != nil || store.busy || store.sessionActive || !store.storageIsAvailable || !store.canSuggestSavedObservations)
            .accessibilityIdentifier("observations.suggestUpdate")
        }.padding(20).background(.regularMaterial)
    }

    private func eligibilityIssue(_ entry: ObservationAcquisition) -> String? {
        if entry.observedDate == nil { return String(localized: "Set the observed day before using this observation.") }
        if entry.origin == .unknown { return String(localized: "Confirm whether this is your morning or a sample.") }
        if entry.origin == .automated { return String(localized: "Automated activity isn't used to learn a personal morning.") }
        if entry.effectiveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return String(localized: "Add readable notes before using this observation.") }
        return nil
    }

    private func compatibilityIssue(_ entry: ObservationAcquisition) -> String? {
        guard !selectedIDs.contains(entry.id), let first = selectedEntries.first else { return nil }
        if first.origin != entry.origin { return String(localized: "Choose personal mornings and samples separately.") }
        if first.observedDate?.timeZoneIdentifier != entry.observedDate?.timeZoneIdentifier { return String(localized: "Choose observations from the same time zone.") }
        if selectedIDs.count >= 5 { return String(localized: "Five observations selected; remove one to choose another.") }
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
            Text(entry.sourceLabel).font(.subheadline.weight(.medium)).lineLimit(2)
            Text(observationDateLabel(entry)).font(.caption).foregroundStyle(.secondary)
            if let zone = entry.observedDate?.timeZoneIdentifier {
                Text(zone.replacingOccurrences(of: "_", with: " "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if entry.origin != .human {
                Text(observationOriginLabel(entry.origin)).font(.caption).foregroundStyle(.secondary)
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
        List {
            if let entry {
                Section {
                    Text(entry.sourceLabel).font(.headline)
                    LabeledContent("Observed day", value: observationDateLabel(entry))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Observed day")
                        .accessibilityValue(observationDateLabel(entry))
                        .accessibilityIdentifier("observation.observedDate")
                    if let date = entry.observedDate {
                        LabeledContent("Time zone", value: date.timeZoneIdentifier)
                        Text(date.provenance == .recordingSession ? "Day recorded by this recording session." : "Day assigned by you.")
                            .font(.caption).foregroundStyle(.secondary)
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
                    Button(entry.observedDate == nil ? "Set observed day" : "Change day or origin") { assigningDate = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.setDate")
                } footer: {
                    Text("Import time is separate from the day you observed. These dates don't establish how long you used your phone.")
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
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button { preparingNarration = true } label: {
                        Label("Read a saved moment", systemImage: "speaker.wave.2")
                    }
                    .disabled(store.busy || store.sessionActive || !store.storageIsAvailable)
                    .accessibilityIdentifier("observation.prepareNarration")
                    Button {
                        if store.selectObservation(id: observationID) { onLearn() }
                    } label: { Label("Edit in Learn", systemImage: "pencil") }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.edit")
                    DisclosureGroup("Current notes") {
                        Text(entry.effectiveText.isEmpty ? String(localized: "No notes saved.") : entry.effectiveText)
                            .textSelection(.enabled).font(.subheadline)
                            .accessibilityIdentifier("observation.currentText")
                    }
                    DisclosureGroup("Original extracted text") {
                        Text(entry.originalText.isEmpty ? String(localized: "No original text was retained.") : entry.originalText)
                            .textSelection(.enabled).font(.subheadline)
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
                            Text(warning.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Delete this observation", role: .destructive) { confirmingDelete = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("observation.delete")
                    if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                }
            } else {
                ContentUnavailableView("Observation removed", systemImage: "doc", description: Text("Your routines and saved runs are still available."))
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle("Observation")
        .accessibilityIdentifier("observation.detail")
        .onAppear { if managesEntryOccupancy { store.observationDetailPresented = true } }
        .onDisappear { if managesEntryOccupancy { store.observationDetailPresented = false } }
        .sheet(isPresented: $assigningDate) {
            if let entry { ObservationDateEditor(store: store, entry: entry) }
        }
        .sheet(isPresented: $preparingNarration) {
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
            Form {
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
                if let notice = store.notice { Section { Text(notice).font(.caption).foregroundStyle(.secondary) } }
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
        List {
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
    guard let value = entry.observedDate else { return String(localized: "Date needed") }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: value.timeZoneIdentifier)
    return formatter.string(from: value.date)
}

private func observationOriginLabel(_ origin: ObservationAcquisitionOrigin) -> String {
    switch origin {
    case .human: String(localized: "My morning")
    case .synthetic: String(localized: "Sample or test")
    case .automated: String(localized: "Automated activity")
    case .unknown: String(localized: "Origin unsure")
    }
}

private func observationImportDateLabel(_ entry: ObservationAcquisition) -> String {
    entry.importedAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Import date unknown")
}

private func observationRecordingStartLabel(_ context: ObservationRecordingContext) -> String {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = TimeZone(identifier: context.timeZoneIdentifier)
    return formatter.string(from: context.startedAt)
}

private func observationClassificationLabel(_ status: ObservationContextInferenceStatus) -> String {
    switch status {
    case .completed: String(localized: "Screen interpretation saved; unclear samples remain unknown.")
    case .noEligibleFrames: String(localized: "No samples have enough complete text to recognize a screen.")
    case .unavailable: String(localized: "Screen interpretation unavailable; original evidence is retained.")
    case .partialFailure: String(localized: "Some screen interpretations failed; those samples remain unknown.")
    case .failed: String(localized: "Screen interpretation failed; original evidence is retained.")
    }
}
