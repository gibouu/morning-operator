import SwiftUI
import UniformTypeIdentifiers
import MorningCore

struct LearnView: View {
    @Bindable var store: MorningStore
    var allowsManualRoutineCreation = true
    /// A persistent destination supplies its own return path after explicit approval.
    var onRoutineSaved: (() -> Void)? = nil
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
    @ScaledMetric(relativeTo: .body) private var notesEditorHeight: CGFloat = 136

    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: String(localized: "Your rhythm"), title: String(localized: "Make your morning yours."))

            NavigationLink {
                ScrollView { MorningScreenTimeView(store: store).padding(24) }
                    .background(MorningPaper(showsSun: false)).navigationTitle("Screen Time").navigationBarTitleDisplayMode(.inline)
            } label: {
                LinkRow(title: String(localized: "1 · See your rhythm"),
                        detail: String(localized: "Start with your real Screen Time"), symbol: "clock")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("learn.screenTime")

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
                    sectionTitle(String(localized: "2 · Show your morning"), symbol: "rectangle.on.rectangle")
                    Text("Record a moment, or add a file.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    // Two compact actions side by side; VoiceOver keeps the full labels.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { learnActions }
                        VStack(alignment: .leading, spacing: 12) { learnActions }
                    }
                }
            }

            NavigationLink { MorningConnectionsView(store: store) } label: {
                LinkRow(title: String(localized: "3 · Make yourself at home"),
                        detail: String(localized: "Sign in to your websites, together"), symbol: "globe")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("learn.connections")

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(store.hasImportedObservation ? String(localized: "What we could see") : String(localized: "A few words"), symbol: "pencil.and.outline")
                    Text(store.hasImportedObservation
                         ? "Edit what we found. Your original stays saved."
                         : "What would make a good morning?")
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
            if closeAfterProposal { finishLearning() }
        }) {
            RoutineEvidenceProposalView(store: store, onLearn: { showingProposal = false })
        }
        .onChange(of: store.pendingRoutineProposal?.id) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.busy) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.routine?.id) { _, _ in
            if showingProposal { closeAfterProposal = true }
            else if !store.busy, !awaitingSuggestion { finishLearning() }
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
            Label(store.routinePreferencesIssue ?? (allowsManualRoutineCreation
                  ? String(localized: "On-device suggestions aren't ready here yet. You can build and edit your routine yourself.")
                  : String(localized: "On-device suggestions aren't ready here yet. Your observations stay saved for later.")), systemImage: "info.circle")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.notes.isEmpty {
                Text("A little news, a few messages, time to think…")
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
        .overlay(MorningDottedFrame(cornerRadius: 16).fill(MorningStyle.line))
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
        if allowsManualRoutineCreation {
            Button("Build it myself") { store.useManualRoutine() }
                .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                .disabled(store.busy || store.sessionActive)
        }
    }

    private func finishLearning() {
        if let onRoutineSaved { onRoutineSaved() }
        else { dismiss() }
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
                Label { Text("Record").lineLimit(1) } icon: {
                    MorningDottedIcon(systemName: "record.circle").frame(width: 20, height: 20)
                }
            }.buttonStyle(CompactPrimaryButtonStyle())
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
            Label { Text("Choose").lineLimit(1) } icon: {
                MorningDottedIcon(systemName: "plus").frame(width: 20, height: 20)
            }
        }
        .buttonStyle(SecondaryButtonStyle())
        .disabled(store.busy || store.sessionActive)
        .accessibilityLabel("Choose a recording or file")
        .accessibilityIdentifier("learn.import")
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label { Text(title) } icon: {
            MorningDottedIcon(systemName: symbol).frame(width: 24, height: 24)
        }
            .font(MorningTheme.Typography.heading).foregroundStyle(MorningStyle.ink)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SetupView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var choosingAlarm = false
    @ViewState<Bool> private var choosingVoice = false
    @ViewState<Bool> private var choosingInvitation = false
    @ViewState<Bool> private var showingPrivacy = false
    @ViewState<Bool> private var choosingBriefing = false
    @ViewState<Bool> private var choosingActivity = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            NavigationLink {
                ScrollView { MorningScreenTimeView(store: store).padding(24) }
                    .background(MorningPaper(showsSun: false)).navigationTitle("Screen Time").navigationBarTitleDisplayMode(.inline)
            } label: {
                LinkRow(title: String(localized: "Screen Time"), detail: "", symbol: "clock")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("setup.screenTime")
            NavigationLink { MorningConnectionsView(store: store) } label: {
                LinkRow(title: String(localized: "Your websites"), detail: String(localized: "One guided sign-in pass"), symbol: "globe")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("setup.connections")
            CardButton { choosingAlarm = true } content: {
                LinkRow(title: String(localized: "Morning alarm"), detail: "", symbol: "alarm")
            }.accessibilityIdentifier("setup.alarm")
            NavigationLink { ShortcutTemplatesView() } label: {
                LinkRow(title: String(localized: "Shortcuts & timers"), detail: "", symbol: "timer")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain)
            CardButton { choosingInvitation = true } content: {
                HStack(spacing: 14) {
                    MorningDottedIcon(systemName: "sun.horizon").frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your next morning").font(MorningTheme.Typography.heading)
                        Text(store.invitation.statusText).font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    Spacer()
                    MorningDottedIcon(systemName: "chevron.right").frame(width: 18, height: 18)
                }
            }.accessibilityIdentifier("setup.invitation")

            CardButton { choosingBriefing = true } content: {
                HStack(spacing: 14) {
                    MorningDottedIcon(systemName: "sun.max").frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Calendar & weather").font(MorningTheme.Typography.heading)
                    }
                    Spacer()
                    MorningDottedIcon(systemName: "chevron.right").frame(width: 18, height: 18)
                }
            }.accessibilityIdentifier("setup.briefing")

            CardButton { choosingActivity = true } content: {
                HStack(spacing: 14) {
                    MorningDottedIcon(systemName: "platter.filled.top.iphone").frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lock Screen").font(MorningTheme.Typography.heading)
                    }
                    Spacer()
                    MorningDottedIcon(systemName: "chevron.right").frame(width: 18, height: 18)
                }
            }.accessibilityIdentifier("setup.activity")

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    Button { choosingVoice = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("Voice").font(MorningTheme.Typography.heading)
                                Text(store.speech.selectedVoiceSummary)
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                            Spacer()
                            MorningDottedIcon(systemName: "chevron.right").frame(width: 18, height: 18)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(store.sessionActive)
                        .accessibilityIdentifier("setup.voice")
                    Toggle(isOn: $store.readAloud) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Read each step aloud").font(.subheadline.weight(.medium))
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
                    DisclosureGroup("Audio output") {
                        VStack(alignment: .leading, spacing: 9) {
                        #if os(iOS)
                        HStack(alignment: .top, spacing: 12) {
                            Text("Choose a speaker or HomePod.")
                                .font(.footnote).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                            MorningAudioRoutePicker()
                        }
                        #else
                        Text(String(localized: "Choose a speaker or HomePod from your Mac's sound controls, then try the voice here."))
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        #endif
                        Text("Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        }.padding(.top, 8)
                    }
                }
            }

            CardButton { showingPrivacy = true } content: {
                HStack(spacing: 14) {
                    MorningDottedIcon(systemName: "lock.shield").frame(width: 28, height: 28)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Privacy & data").font(MorningTheme.Typography.heading)
                    }
                    Spacer()
                    MorningDottedIcon(systemName: "chevron.right").frame(width: 18, height: 18)
                }
            }.accessibilityIdentifier("setup.privacy")

            DisclosureGroup("Availability & device details") {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Apple Intelligence", systemImage: "sparkles").font(.subheadline.weight(.semibold))
                        Text(store.modelSummary).font(.footnote).foregroundStyle(MorningStyle.muted)
                        Button("Check again") { store.refreshCapabilities() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Divider()
                    Text("You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable.")
                    Text("MORE guides native app steps. Inside MORE’s browser, you can ask it to read supported pages or move to the next video.")
                }
                .font(.footnote).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            }
            .font(.subheadline.weight(.medium)).tint(MorningStyle.accent)
            .padding(.horizontal, 4)
        }.foregroundStyle(MorningStyle.ink)
        .navigationDestination(isPresented: $showingPrivacy) { MorningPrivacyView(store: store) }
        .task { if store.privacyNeedsCleanup { showingPrivacy = true } }
        .fullScreenCover(isPresented: $choosingBriefing) { MorningBriefingView(store: store) }
        .fullScreenCover(isPresented: $choosingActivity) { MorningActivitySettingsView(store: store) }
        .fullScreenCover(isPresented: $choosingAlarm) { MorningAlarmView() }
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
                            .font(.caption).foregroundStyle(MorningStyle.muted)
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
                        Text("\(step.durationMinutes) minutes")
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
                StepTargetEditor(target: $step.target)
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
            String(localized: "Take this moment at your own pace, then tap Next when you're ready.")
        case .spokenNote:
            String(localized: "Reads the text you approve for this step. Speaking the instructions doesn't carry out the activity they describe.")
        case .todayCalendar:
            String(localized: "Reads today's remaining events from calendars you select in Your day. Calendar access and spoken guidance are required.")
        case .morningBriefing:
            String(localized: "Reads a current recap from the calendars and optional city you choose in Your day. Available sources are prepared before speech; no events are changed.")
        case .savedObservation:
            String(localized: "Reads the dated excerpt you selected. If the source changes or is deleted, playback stops for review. This is a saved observation, not a live inbox.")
        }
    }
}
