import SwiftUI
import UniformTypeIdentifiers
import MorningCore

struct LearnView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var importing = false
    @ViewState<UUID?> private var importGeneration = nil
    @ViewState<Bool> private var recording = false
    @ViewState<Bool> private var confirmingObservation = false
    @ViewState<Bool> private var showingProposal = false
    @ViewState<Bool> private var awaitingSuggestion = false
    @ViewState<UUID?> private var proposalBeforeRequest = nil
    @ViewState<Bool> private var closeAfterProposal = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var notesFocused: Bool
    @ScaledMetric(relativeTo: .body) private var notesEditorHeight: CGFloat = 220

    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Your rhythm", title: "Make your morning yours.",
                subtitle: "Start with what you already do. You'll review every suggestion before it becomes your routine.")

            if let issue = store.observationIssue {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your recording needs attention", systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.medium))
                        Text(issue).font(.footnote)
                        Text("Any text below belongs to the named saved observation; it may be from an earlier import.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("learn.observationIssue")
                }
            }

            if store.busy {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.analysisStatus, systemImage: "sparkles")
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                        if store.progress > 0 {
                            ProgressView(value: store.progress).tint(MorningStyle.accent)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button("Stop analysis") { store.cancelAnalysis() }
                            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle("Show us your morning", symbol: "rectangle.on.rectangle")
                    Text("Start an explicitly shared recording or bring one you already made. Go through a short part of your morning, then review what we can see.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    // Two compact actions side by side; VoiceOver keeps the full labels.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { learnActions }
                        VStack(alignment: .leading, spacing: 12) { learnActions }
                    }
                    Text("A screenshot or text file works too. Only the file you choose is read; recording never starts automatically.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(store.hasImportedObservation ? "What we could see" : "Add context, if you like", symbol: "pencil.and.outline")
                    Text(store.hasImportedObservation
                         ? "Review the text we found and correct anything we missed. The original stays in Review → Saved observations. Visible words don't always mean you performed an activity."
                         : "What do you check first? What helps you feel ready? Include the small things you want to make time for.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let observation = store.selectedObservation {
                        Text(observation.sourceLabel).font(.caption).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("learn.observationSource")
                    }
                    notesEditor
                    if let evidence = store.observationVideoEvidence {
                        ObservationEvidenceView(evidence: evidence,
                            classification: store.observationContextClassification,
                            isBusy: store.busy, canAnalyze: !store.sessionActive,
                            analyze: store.recognizeObservationScreens)
                    }
                    if let issue = store.observationSaveIssue {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(issue).font(.footnote).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("learn.saveError")
                            Button("Retry saving this observation") { store.saveObservationEdits() }
                                .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                                .accessibilityIdentifier("learn.retrySave")
                        }
                    }
                    if store.selectedObservationID != nil || !store.notes.isEmpty || store.observationVideoEvidence != nil {
                        Button("Clear this observation", role: .destructive) { store.clearObservation() }
                            .buttonStyle(.borderless).font(.caption).disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("learn.clear")
                    }
                    learningReviewControls
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Label("Your routine stays in your hands", systemImage: "hand.raised")
                    .font(.subheadline.weight(.medium)).foregroundStyle(MorningStyle.green)
                Text("Your current routine stays ready while you review a suggestion. Approve it when it fits, or keep the morning you already have.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("About on-device learning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.modelSummary)
                        Text("Each observation is saved on this device, with its original text and your corrections kept separately. Find earlier observations in Review. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it.")
                        Text("A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention.")
                        Text("Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you.")
                        Button("Check availability again") { store.refreshCapabilities() }
                            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    }.font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
                .font(.footnote.weight(.medium)).tint(MorningStyle.accent)
            }.padding(.horizontal, 4)
        }
    }

    var body: some View {
        // Capture the admission value in this presentation's completion closure.
        let pickerGeneration = importGeneration
        learningContent
        .foregroundStyle(MorningStyle.ink)
        .task { store.importUITestObservationIfRequested() }
        #if os(iOS)
        .toolbar { ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                store.saveObservationEdits()
                notesFocused = false
            }.accessibilityIdentifier("input.done")
        } }
        #endif
        .onChange(of: notesFocused) { _, focused in
            if !focused { store.saveObservationEdits() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { _ = store.saveObservationEdits() }
            else { finishSuggestionIfReady() }
        }
        .onDisappear { store.saveObservationEdits() }
        .sheet(isPresented: $recording) {
            RecordMorningView(canStartRecording: store.canStartRecording) { url in
                store.importObservation(url)
            }
        }
        .sheet(isPresented: $confirmingObservation) {
            if let entry = store.selectedObservation {
                ObservationDateEditor(store: store, entry: entry)
            }
        }
        .sheet(isPresented: $showingProposal, onDismiss: {
            if closeAfterProposal { dismiss() }
        }) {
            RoutineEvidenceProposalView(store: store, onLearn: { showingProposal = false })
        }
        .onChange(of: store.pendingRoutineProposal?.id) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.busy) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.routine?.id) { _, _ in
            if showingProposal { closeAfterProposal = true }
            else if !store.busy, !awaitingSuggestion { dismiss() }
        }
        .onChange(of: store.dataGeneration) { _, _ in
            importGeneration = nil
            importing = false
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.movie, .image, .plainText], allowsMultipleSelection: false) { result in
            guard let pickerGeneration, pickerGeneration == store.dataGeneration,
                  !store.privacyBlocksWork else { return }
            importGeneration = nil
            switch result {
            case .success(let urls): if let url = urls.first { store.importObservation(url) }
            case .failure(let error): store.notice = error.localizedDescription
            }
        }
    }

    @ViewBuilder private var learningReviewControls: some View {
        if store.selectedObservation != nil {
            Button("Day and source") { openObservationDetails() }
                .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                .disabled(store.busy || store.sessionActive)
                .accessibilityIdentifier("learn.observationDetails")
        }
        if let issue = store.currentObservationSuggestionIssue, !store.notes.isEmpty {
            Text(issue).font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("learn.suggestionIssue")
        }
        if store.usesSyntheticProposalFixture {
            Text("Synthetic suggestion test — no Apple model call")
                .font(.caption).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("learn.fixtureMode")
        }
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { analyzeControls }
            VStack(alignment: .leading, spacing: 16) { analyzeControls }
        }
        if store.pendingRoutineProposal != nil {
            Button { showingProposal = true } label: {
                Label("Review suggested update", systemImage: "list.bullet.clipboard")
            }.buttonStyle(SecondaryButtonStyle())
                .disabled(store.busy || store.sessionActive)
                .accessibilityIdentifier("learn.reviewProposal")
        }
        if !store.canSuggestSavedObservations {
            Label(store.routinePreferencesIssue ?? "On-device suggestions aren't ready here yet. You can build and edit your routine yourself.", systemImage: "info.circle")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.notes.isEmpty {
                Text("I check my calendar, read a few messages, then spend ten minutes playing chess…")
                    .font(.body).foregroundStyle(MorningStyle.muted.opacity(0.7))
                    .padding(12).allowsHitTesting(false)
            }
            TextEditor(text: Binding(get: { store.notes }, set: { store.updateObservationNotes($0) }))
                .font(.body).scrollContentBackground(.hidden)
                .padding(6).frame(height: notesEditorHeight)
                .accessibilityLabel("Describe your morning").accessibilityIdentifier("learn.notes")
                .focused($notesFocused)
                .disabled(store.busy || store.sessionActive)
        }
        .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(MorningStyle.line))
    }

    @ViewBuilder private var analyzeControls: some View {
        Button { requestSuggestion() } label: {
            Label(store.currentObservationNeedsProvenance ? "Confirm this observation"
                  : store.routine == nil ? "Suggest a routine" : "Suggest an update", systemImage: "sparkles")
        }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(store.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || store.sessionActive ||
                      !store.storageIsAvailable || (!store.currentObservationNeedsProvenance && !store.canSuggestSavedObservations))
            .accessibilityIdentifier("learn.analyze")
        Button("Build it myself") { store.useManualRoutine() }
            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
            .disabled(store.busy || store.sessionActive)
    }

    private func openObservationDetails() {
        notesFocused = false
        if store.prepareCurrentObservationForSuggestion() { confirmingObservation = true }
    }

    private func requestSuggestion() {
        notesFocused = false
        guard store.prepareCurrentObservationForSuggestion() else { return }
        if store.currentObservationNeedsProvenance {
            confirmingObservation = true
            return
        }
        proposalBeforeRequest = store.pendingRoutineProposal?.id
        awaitingSuggestion = true
        store.analyzeNotes()
        finishSuggestionIfReady()
    }

    private func finishSuggestionIfReady() {
        guard awaitingSuggestion, !store.busy, scenePhase == .active else { return }
        awaitingSuggestion = false
        if let id = store.pendingRoutineProposal?.id, id != proposalBeforeRequest { showingProposal = true }
    }

    @ViewBuilder private var learnActions: some View {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            Button { recording = true } label: {
                Label("Record", systemImage: "record.circle").lineLimit(1)
            }.buttonStyle(TintedButtonStyle())
                .disabled(!store.canStartRecording)
                .accessibilityLabel("Record a little of my morning")
                .accessibilityIdentifier("learn.record")
        }
        #endif
        Button {
            guard !store.privacyBlocksWork else { return }
            importGeneration = store.dataGeneration
            importing = true
        } label: {
            Label("Choose", systemImage: "plus").lineLimit(1)
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.busy || store.sessionActive)
        .accessibilityLabel("Choose a recording or file")
        .accessibilityIdentifier("learn.import")
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.title3.weight(.semibold)).foregroundStyle(MorningStyle.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SetupView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var choosingVoice = false
    @ViewState<Bool> private var choosingInvitation = false
    @ViewState<Bool> private var showingPrivacy = false
    @ViewState<Bool> private var choosingBriefing = false
    @ViewState<Bool> private var choosingActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: "Make yourself at home", title: "A few things, your way.",
                subtitle: "Choose what to connect and how you'd like your morning to sound.")

            Card {
                Button { choosingInvitation = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sun.horizon").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your next morning").font(.headline)
                            Text(store.invitation.statusText).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("setup.invitation")
            }

            Card {
                Button { choosingBriefing = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "sun.max").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Your day").font(.headline)
                            Text("A little context before your morning begins.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("setup.briefing")
            }

            Card {
                Button { choosingActivity = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "platter.filled.top.iphone").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Morning at a glance").font(.headline)
                            Text("Keep your place on the Lock Screen.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("setup.activity")
            }

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Label("A voice to guide you", systemImage: "speaker.wave.2")
                        .font(.title3.weight(.semibold))
                    Button { choosingVoice = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Companion voice").font(.subheadline.weight(.semibold))
                                Text(store.speech.selectedVoiceSummary)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption)
                        }
                    }.buttonStyle(.plain).disabled(store.sessionActive)
                        .accessibilityIdentifier("setup.voice")
                    Toggle(isOn: $store.readAloud) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Read each step aloud").font(.subheadline.weight(.medium))
                            Text("Hear the next step as you move through your routine.")
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                        }
                    }
                    .tint(MorningStyle.accent).accessibilityIdentifier("setup.readAloud")
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { voiceControls }
                        VStack(alignment: .leading, spacing: 12) { voiceControls }
                    }
                    Text(store.speech.statusText)
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("setup.speechStatus")
                        .accessibilityValue(store.speech.state.rawValue)
                    Divider().overlay(MorningStyle.line)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Listen where you like").font(.subheadline.weight(.medium))
                        #if os(iOS)
                        HStack(alignment: .top, spacing: 12) {
                            Text("Use the audio output picker to choose an available speaker, including a HomePod on your network.")
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            MorningAudioRoutePicker()
                        }
                        #else
                        Text("Choose a speaker or HomePod from your Mac's sound controls, then try the voice here.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        #endif
                        Text("Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Card {
                Button { showingPrivacy = true } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "lock.shield").font(.title2)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Privacy & data").font(.headline)
                            Text("What stays here, and what you can remove.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                }.buttonStyle(.plain).accessibilityIdentifier("setup.privacy")
            }

            DisclosureGroup("Availability & device details") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apple Intelligence", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                        Text(store.modelSummary).font(.footnote).foregroundStyle(MorningStyle.muted)
                        Button("Check again") { store.refreshCapabilities() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Divider()
                    Text("You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable.")
                    Text("Connecting a phone to a Mac doesn't automatically give this app control of the phone. The separate development test runner is needed for the phone-control experiment.")
                    Text("Messages and email aren't connected here yet. Automatic room detection and continuous voice commands also need further work.")
                }
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            .font(.subheadline.weight(.medium)).tint(MorningStyle.accent)
            .padding(.horizontal, 4)
        }.foregroundStyle(MorningStyle.ink)
        .navigationDestination(isPresented: $showingPrivacy) { MorningPrivacyView(store: store) }
        .task { if store.privacyNeedsCleanup { showingPrivacy = true } }
        .sheet(isPresented: $choosingBriefing) { MorningBriefingView(store: store) }
        .sheet(isPresented: $choosingActivity) { MorningActivitySettingsView(store: store) }
        .sheet(isPresented: $choosingVoice) { VoicePickerView(speech: store.speech) }
        .sheet(isPresented: $choosingInvitation) { MorningInvitationView(service: store.invitation) }
    }

    @ViewBuilder private var voiceControls: some View {
        Button("Try the voice") {
            store.speech.speak(store.speech.previewText)
        }
        .buttonStyle(PrimaryButtonStyle()).disabled(store.sessionActive).accessibilityIdentifier("setup.testVoice")
        Button("Stop") { store.speech.stop() }.buttonStyle(SecondaryButtonStyle()).disabled(store.sessionActive)
    }
}

struct StepEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineStep> var step: RoutineStep
    @ViewState<Bool> private var keepInSuggestions: Bool
    @ViewState<Bool> private var keepDuration: Bool
    @ViewState<Bool> private var choosingRemoval = false
    @ViewState<String?> private var saveError = nil
    let onSave: (RoutineStep, Bool, Bool) -> Bool
    let onDelete: (Bool) -> Bool
    let failureMessage: () -> String

    init(step: RoutineStep, preference: RoutinePreference?,
         onSave: @escaping (RoutineStep, Bool, Bool) -> Bool,
         onDelete: @escaping (Bool) -> Bool, failureMessage: @escaping () -> String) {
        _step = ViewState(initialValue: step)
        _keepInSuggestions = ViewState(initialValue: preference?.presence == .keep)
        _keepDuration = ViewState(initialValue: preference?.durationMinutes != nil)
        self.onSave = onSave; self.onDelete = onDelete; self.failureMessage = failureMessage
    }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    TextField("Give this step a name", text: $step.title)
                        .accessibilityLabel("Step name")
                    if step.automation == .savedObservation {
                        Text(step.detail).textSelection(.enabled)
                        Text("Choose a different excerpt from its observation in Review. Switching to Read this text aloud makes it an ordinary note.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        TextField("What would you like to do?", text: $step.detail, axis: .vertical)
                            .lineLimit(3...7).accessibilityLabel("Step details")
                    }
                } header: {
                    Text("Your moment")
                } footer: {
                    Text("Keep it simple. You can change the order of your steps back in your routine.")
                }
                Section {
                    Picker("Category", selection: $step.kind) {
                        ForEach(StepKind.allCases, id: \.self) { kind in
                            Label(kind.displayName, systemImage: MorningStyle.symbol(for: kind)).tag(kind)
                        }
                    }
                    Stepper(value: $step.durationMinutes, in: 1...120) {
                        Text("\(step.durationMinutes) \(step.durationMinutes == 1 ? "minute" : "minutes")")
                            .monospacedDigit()
                    }
                    .accessibilityLabel("Duration in minutes")
                    .accessibilityIdentifier("step.duration").accessibilityValue("\(step.durationMinutes)")
                } header: {
                    Text("How it fits")
                } footer: {
                    Text("The category organizes your routine. Choose an action below to decide what Morning Operator does.")
                }
                Section {
                    Toggle("Keep in future suggestions", isOn: $keepInSuggestions)
                        .accessibilityIdentifier("step.keepFuture")
                    Toggle("Keep this duration", isOn: $keepDuration)
                        .accessibilityIdentifier("step.keepDuration")
                } header: { Text("Future mornings") } footer: {
                    Text("Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices later in Review.")
                }
                Section {
                    Picker("Action", selection: $step.automation) {
                        Text("User-led moment").tag(Optional<RoutineStepAutomation>.none)
                        Text("Read this text aloud").tag(Optional(RoutineStepAutomation.spokenNote))
                        Text("Read today's calendar").tag(Optional(RoutineStepAutomation.todayCalendar))
                        Text("Read today's briefing").tag(Optional(RoutineStepAutomation.morningBriefing))
                        if step.observationReference != nil {
                            Text("Read saved excerpt").tag(Optional(RoutineStepAutomation.savedObservation))
                        }
                    }
                    .accessibilityIdentifier("step.automation")
                } header: {
                    Text("What Morning Operator does")
                } footer: {
                    Text(automationExplanation)
                }
                Section {
                    Button("Remove this step", role: .destructive) { choosingRemoval = true }
                        .accessibilityIdentifier("step.remove")
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("step.saveError") }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(MorningStyle.background)
            .tint(MorningStyle.accent)
            .navigationTitle("Make it yours")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var edited = step
                        edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if edited.automation != .savedObservation { edited.observationReference = nil }
                        if onSave(edited, keepInSuggestions, keepDuration) { dismiss() }
                        else { saveError = failureMessage() }
                    }
                    .disabled(step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("step.save")
                }
            }
            .onChange(of: step.durationMinutes) { _, _ in keepDuration = true }
            .confirmationDialog("Remove this moment?", isPresented: $choosingRemoval, titleVisibility: .visible) {
                Button("Remove from this draft", role: .destructive) { remove(excluding: false) }
                    .accessibilityIdentifier("step.removeDraft")
                Button("Exclude from future suggestions", role: .destructive) { remove(excluding: true) }
                    .accessibilityIdentifier("step.exclude")
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removing only this draft leaves saved choices intact. Excluding also asks future suggestions to leave this activity out until you clear that choice.")
            }
            #if os(macOS)
            .frame(minWidth: 420, idealWidth: 500, minHeight: 500, idealHeight: 540)
            #endif
        }
    }

    private func remove(excluding: Bool) {
        if onDelete(excluding) { dismiss() }
        else { saveError = failureMessage() }
    }

    private var automationExplanation: String {
        switch step.automation {
        case .none:
            "Take this moment at your own pace, then tap Next when you're ready."
        case .spokenNote:
            "Reads the text you approve for this step. Speaking the instructions doesn't carry out the activity they describe."
        case .todayCalendar:
            "Reads today's remaining events from calendars you select in Your day. Calendar access and spoken guidance are required."
        case .morningBriefing:
            "Reads a current recap from the calendars and optional city you choose in Your day. Available sources are prepared before speech; no events are changed."
        case .savedObservation:
            "Reads the dated excerpt you selected. If the source changes or is deleted, playback stops for review. This is a saved observation, not a live inbox."
        }
    }
}
