import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct LearnView: View {
    #if DEBUG
    @MainActor static var autoLearnStarted = false
    #endif
    @Bindable var store: MorningStore
    /// Where to go when learning is done. Without it, Learn dismisses itself.
    var onClose: (() -> Void)? = nil
    @ViewState<Bool> private var importing = false
    @ViewState<UUID?> private var importGeneration = nil
    @ViewState<Bool> private var recording = false
    @ViewState<Bool> private var recordingStartsAtOnce = false
    @ViewState<Bool> private var confirmingObservation = false
    @ViewState<Bool> private var showingProposal = false
    @ViewState<Bool> private var awaitingSuggestion = false
    @ViewState<UUID?> private var proposalBeforeRequest = nil
    @ViewState<Bool> private var closeAfterProposal = false
    @ViewState<Bool> private var showingSavedObservations = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var notesFocused: Bool
    @ScaledMetric(relativeTo: .body) private var notesEditorHeight: CGFloat = 136

    private var learningContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            PageHeading(eyebrow: AppLanguage.localized("Your rhythm"), title: AppLanguage.localized("Make your morning yours."))

            NavigationLink {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        MorningScreenTimeView(store: store, returnsToLearn: true, onEdit: { close() })
                        // Then show the morning itself: a recording or a file.
                        showMorningCard
                    }.padding(24)
                }
                    .background(MorningPaper(showsSun: false)).navigationTitle("Screen Time").navigationBarTitleDisplayMode(.inline)
            } label: {
                LinkRow(title: AppLanguage.localized("1 · See your rhythm"),
                        detail: AppLanguage.localized("Start with your real Screen Time"), symbol: "clock")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("learn.screenTime")

            if let issue = store.observationIssue {
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Your recording needs attention", systemImage: "exclamationmark.circle")
                            .font(.raleway(.subheadline, .medium))
                        Text(issue).font(.raleway(.footnote))
                        Text("Any text below belongs to the named saved observation; it may be from an earlier import.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("learn.observationIssue")
                }
            }

            if store.busy {
                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(store.analysisStatus, systemImage: "sparkles")
                            .font(.raleway(.subheadline, .medium))
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

            NavigationLink { MorningConnectionsView(store: store) } label: {
                LinkRow(title: AppLanguage.localized("2 · Make yourself at home"),
                        detail: AppLanguage.localized("Connect the apps you use"), symbol: "link")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("learn.connections")

            Button { showingSavedObservations = true } label: {
                LinkRow(title: AppLanguage.localized("Saved observations"),
                        detail: AppLanguage.isFrench ? "Réunir les matinées que vous avez enregistrées" : "Bring your saved mornings together", symbol: "doc.text.image")
                    .padding(MorningTheme.Space.card)
                    .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            }.buttonStyle(.plain).accessibilityIdentifier("learn.savedObservations")

            Card {
                VStack(alignment: .leading, spacing: 18) {
                    sectionTitle(store.hasImportedObservation ? AppLanguage.localized("What we could see") : AppLanguage.localized("A few words"), symbol: "pencil.and.outline")
                    Text(store.hasImportedObservation
                         ? String(localized: "Edit what we found. Your original stays saved.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                         : String(localized: "What would make a good morning?", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let observation = store.selectedObservation {
                        Text(observation.sourceLabel).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("learn.observationSource")
                    }
                    if let observation = store.selectedObservation, store.observationVideoEvidence != nil,
                       case let openings = ObservationAppTimeline.openings(for: observation), !openings.isEmpty {
                        // A recording reads as the apps it opened; the raw screen text stays
                        // available to correct, folded away.
                        appOpenings(openings)
                        DisclosureGroup("Text read on screen") { notesEditor.padding(.top, 8) }
                            .font(.subheadline).tint(MorningStyle.accent)
                    } else {
                        notesEditor
                    }
                    if let evidence = store.observationVideoEvidence {
                        ObservationEvidenceView(evidence: evidence,
                            classification: store.observationContextClassification,
                            acquisition: store.selectedObservation,
                            isBusy: store.busy, canAnalyze: !store.sessionActive,
                            analyze: store.recognizeObservationScreens)
                    }
                    if let issue = store.observationSaveIssue {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(issue).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("learn.saveError")
                            Button("Retry saving this observation") { store.saveObservationEdits() }
                                .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                                .accessibilityIdentifier("learn.retrySave")
                        }
                    }
                    if store.selectedObservationID != nil || !store.notes.isEmpty || store.observationVideoEvidence != nil {
                        Button("Clear this observation", role: .destructive) { store.clearObservation() }
                            .buttonStyle(.borderless).font(.raleway(.caption)).disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("learn.clear")
                    }
                    learningReviewControls
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("About on-device learning") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(store.modelSummary)
                        Text(store.canRecognizeAppsInImages
                             ? String(localized: "App recognition in screen recordings: available on this device.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                             : String(localized: "App recognition in screen recordings: unavailable here. Apps can still come from your Shortcuts automations or your labels.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                            .accessibilityIdentifier("setup.imageAppRecognition")
                        Text("Each observation is saved on this device, with its original text and your corrections kept separately. Find earlier observations in Review. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it.")
                        Text("A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention.")
                        Text("Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you.")
                        Button("Check availability again") { store.refreshCapabilities() }
                            .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                    }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                }
                .font(.raleway(.footnote, .medium)).tint(MorningStyle.accent)
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
        .navigationDestination(isPresented: $showingSavedObservations) {
            ObservationHistoryView(store: store, onLearn: { showingSavedObservations = false }, onEdit: { close() })
        }
        .sheet(isPresented: $recording, onDismiss: { recordingStartsAtOnce = false }) {
            RecordMorningView(canStartRecording: store.canStartRecording, startsAtOnce: recordingStartsAtOnce) { url in
                store.importObservation(url)
            }
        }
        #if DEBUG
        .onChange(of: MorningIntentRouter.shared.pendingWatchMorning, initial: true) { _, pending in
            guard pending, MorningIntentRouter.shared.consumeWatchMorning(), !recording else { return }
            recordingStartsAtOnce = true; recording = true
        }
        #endif
        .sheet(isPresented: $confirmingObservation) {
            if let entry = store.selectedObservation {
                ObservationDateEditor(store: store, entry: entry)
            }
        }
        .sheet(isPresented: $showingProposal, onDismiss: {
            if closeAfterProposal { close() }
        }) {
            RoutineEvidenceProposalView(store: store, onLearn: { showingProposal = false }, onEdit: {
                closeAfterProposal = true
                showingProposal = false
            })
        }
        #if DEBUG
        .task {
            guard MorningStore.screenTimeAutoLearnRequested, !LearnView.autoLearnStarted else { return }
            LearnView.autoLearnStarted = true
            store.learnFromScreenTime()
        }
        #endif
        .onChange(of: store.pendingRoutineProposal?.id) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.busy) { _, _ in finishSuggestionIfReady() }
        .onChange(of: store.routine?.id) { _, _ in
            if showingProposal { closeAfterProposal = true }
            else if !showingSavedObservations, !store.busy, !awaitingSuggestion { close() }
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
            case .failure(let error): store.notice = error.moreDescription
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
            Text(issue).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("learn.suggestionIssue")
        }
        if store.usesSyntheticProposalFixture {
            Text("Synthetic suggestion test — no Apple model call")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
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
            Label(store.routinePreferencesIssue ?? AppLanguage.localized("On-device suggestions aren't ready here yet. You can build and edit your routine yourself."), systemImage: "info.circle")
                .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var notesEditor: some View {
        ZStack(alignment: .topLeading) {
            if store.notes.isEmpty {
                Text("A little news, a few messages, time to think…")
                    .font(.raleway(.body)).foregroundStyle(MorningStyle.muted.opacity(0.7))
                    .padding(12).allowsHitTesting(false)
            }
            TextEditor(text: Binding(get: { store.notes }, set: { store.updateObservationNotes($0) }))
                .font(.raleway(.body)).scrollContentBackground(.hidden)
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
            Label(store.currentObservationNeedsProvenance ? String(localized: "Confirm this observation", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                  : store.routine == nil ? String(localized: "Suggest a routine", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Suggest an update", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), systemImage: "sparkles")
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

    private func close() {
        if let onClose { onClose() } else { dismiss() }
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

    private var showMorningCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 18) {
                sectionTitle(AppLanguage.localized("Show your morning"), symbol: "rectangle.on.rectangle")
                Text("Record a moment, or add a file.")
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                // Two compact actions side by side; VoiceOver keeps the full labels.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { learnActions }
                    VStack(alignment: .leading, spacing: 12) { learnActions }
                }
            }
        }
    }

    private func appOpenings(_ openings: [ObservationAppOpening]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(openings) { opening in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(opening.wallClock.map { $0.formatted(.dateTime.hour().minute().locale(AppLanguage.locale)) }
                         ?? String(format: "%d:%02d", Int(opening.timeSeconds) / 60, Int(opening.timeSeconds) % 60))
                        .monospacedDigit().foregroundStyle(MorningStyle.muted)
                    Text("Opened \(opening.app.displayName)").foregroundStyle(MorningStyle.ink)
                }.font(.raleway(.subheadline))
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("learn.appOpenings")
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
    var openRoutine: (() -> Void)? = nil
    var openLearning: (() -> Void)? = nil
    var openHistory: (() -> Void)? = nil
    @State private var choosingVoice = false
    @State private var preparingVoiceAccess = false
    @State private var choosingInvitation = false
    @State private var showingPrivacy = false
    @State private var choosingBriefing = false
    @State private var choosingHealth = false
    @State private var choosingConversation = false
    @Environment(\.colorScheme) private var colorScheme
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        MorningForm {
            if store.sessionActive {
                Section(french ? "Matin en cours" : "Current morning") {
                    MorningRoutineControlsView(store: store)
                }
            }
            completion
            Section {
                if let openRoutine {
                    settingsButton(String(localized: "Your routine", bundle: AppLanguage.bundle(), locale: AppLanguage.locale),
                        detail: store.routine.map { String(localized: "\($0.steps.count) moments · \($0.totalDurationMinutes) min", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) } ?? "",
                        symbol: "list.bullet", action: openRoutine)
                        .accessibilityIdentifier("setup.routine")
                }
                if let openHistory {
                    settingsButton(String(localized: "History", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), symbol: "clock.arrow.circlepath", action: openHistory)
                        .accessibilityIdentifier("setup.history")
                }
                settingsButton(french ? "Noter une pensée" : "Note a thought", symbol: "square.and.pencil") { store.openCapture() }
                    .accessibilityIdentifier("morning.reflect")
            }
            Section("Sources") {
                if let openLearning {
                    settingsButton(french ? "Affiner mon matin" : "Refine my morning",
                                   symbol: "sparkles", action: openLearning)
                        .accessibilityIdentifier("setup.learning")
                }
                NavigationLink {
                    ScrollView { MorningScreenTimeView(store: store, onEdit: openRoutine).padding(24) }
                        .background(MorningPaper(showsSun: false)).navigationTitle("Screen Time").navigationBarTitleDisplayMode(.inline)
                } label: {
                    settingsLabel(String(localized: "Screen Time", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), symbol: "clock")
                }.accessibilityIdentifier("setup.screenTime")
                NavigationLink { MorningConnectionsView(store: store) } label: {
                    settingsLabel(String(localized: "Apps & accounts", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), symbol: "link")
                }.accessibilityIdentifier("setup.connections")
                settingsButton(MorningPermissionSetup.text("Calendar & weather", "Calendrier et météo"), symbol: "sun.max") { choosingBriefing = true }
                    .accessibilityIdentifier("setup.briefing")
                settingsButton(MorningPermissionSetup.text("Health", "Santé"), symbol: "heart") { choosingHealth = true }
                    .accessibilityIdentifier("setup.health")
            }
            Section("Language") {
                Picker("Language", selection: Binding(
                    get: { AppLanguage.code },
                    set: { store.setAppLanguage($0) })) {
                    Text(verbatim: "Français").tag("fr")
                    Text(verbatim: "English").tag("en")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("setup.language")
            }
            Section(french ? "Voix et lecture" : "Voice & playback") {
                #if !MORE_JURY_DEMO
                settingsButton(french ? "Parler avec MORE" : "Talk with MORE",
                               symbol: "sparkles") { choosingConversation = true }
                    .accessibilityIdentifier("setup.conversation")
                #endif
                NavigationLink { MorningIntelligenceView(store: store) } label: {
                    settingsLabel(french ? "Intelligence et mémoire" : "Intelligence & memory", symbol: "sparkles")
                }.accessibilityIdentifier("setup.intelligence")
                settingsButton(String(localized: "Voice", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), detail: store.speech.selectedVoiceSummary,
                               symbol: "waveform") { choosingVoice = true }
                    .disabled(store.sessionActive).accessibilityIdentifier("setup.voice")
                Toggle(isOn: $store.automatic) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Hands free")
                        Text(french
                            ? "MORE enchaîne votre routine. Préparez l’écoute pour l’interrompre à la voix."
                            : "MORE continues your routine. Prepare listening to interrupt it by voice.")
                            .font(.footnote).foregroundStyle(MorningStyle.muted)
                    }
                }.tint(.green).accessibilityIdentifier("setup.handsFree")
                Button {
                    store.voiceAccess.refresh(language: store.voicePreparationLanguage)
                    preparingVoiceAccess = true
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(french ? "Préparer l’écoute" : "Prepare listening")
                        MorningVoiceAccessStatusView(access: store.voiceAccess)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }.buttonStyle(.plain).disabled(store.sessionActive || store.privacyBlocksWork)
                    .accessibilityIdentifier("setup.voiceAccess")
                Toggle("Read each step aloud", isOn: $store.readAloud).tint(.green).accessibilityIdentifier("setup.readAloud")
                Text(store.speech.statusText).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("setup.speechStatus").accessibilityValue(store.speech.statusText)
                DisclosureGroup("Audio output") {
                    VStack(alignment: .leading, spacing: 9) {
                        #if os(iOS)
                        HStack(alignment: .top, spacing: 12) {
                            Text("Choose a speaker or HomePod.").fixedSize(horizontal: false, vertical: true)
                            MorningAudioRoutePicker()
                        }
                        #else
                        Text(AppLanguage.localized("Choose a speaker or HomePod from your Mac's sound controls, then try the voice here."))
                        #endif
                        Text("Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet.")
                            .fixedSize(horizontal: false, vertical: true)
                    }.font(.footnote).foregroundStyle(MorningStyle.muted).padding(.vertical, 8)
                }
            }
            Section {
                settingsButton(String(localized: "Your next morning", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), detail: store.invitation.statusText,
                               symbol: "sun.horizon") { choosingInvitation = true }
                    .accessibilityIdentifier("setup.invitation")
                settingsButton(MorningPermissionSetup.text("iPhone permissions", "Accès iPhone"),
                               symbol: "hand.raised") { store.permissionSetup.revisit() }
                    .accessibilityIdentifier("setup.permissions")
                settingsButton(String(localized: "Privacy & data", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), symbol: "lock.shield") { showingPrivacy = true }
                    .accessibilityIdentifier("setup.privacy")
                DisclosureGroup("Availability & device details") {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(french ? "Intelligence" : "Intelligence", systemImage: "sparkles").font(.headline)
                            Text(store.modelSummary)
                            Button("Check again") { store.refreshCapabilities() }.buttonStyle(SecondaryButtonStyle())
                        }
                        Text("You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable.")
                        Text("MORE guides native app steps. Inside MORE’s browser, you can ask it to read supported pages or move to the next video.")
                    }.font(.footnote).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 8)
                }
            }
        }
        .font(.body).foregroundStyle(MorningStyle.ink).tint(MorningStyle.accent)
        .accessibilityIdentifier("settings.appearance")
        .accessibilityValue(testAppearance)
        .navigationDestination(isPresented: $showingPrivacy) { MorningPrivacyView(store: store) }
        .task { if store.privacyNeedsCleanup { showingPrivacy = true } }
        .fullScreenCover(isPresented: $choosingBriefing) { MorningBriefingView(store: store) }
        .sheet(isPresented: $choosingHealth) { MorningHealthView(store: store) }
        .sheet(isPresented: $choosingConversation) { MorningConversationView(store: store) }
        .sheet(isPresented: $choosingVoice) { VoicePickerView(store: store) }
        .sheet(isPresented: $preparingVoiceAccess) { MorningVoicePreparationView(store: store) }
        .sheet(isPresented: $choosingInvitation) { MorningInvitationView(service: store.invitation) }
        .onAppear { store.voiceAccess.refresh(language: store.voicePreparationLanguage) }
    }

    private var testAppearance: String {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { return colorScheme == .dark ? "night" : "day" }
        #endif
        return ""
    }

    private func settingsLabel(_ title: String, detail: String = "", symbol: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                if !detail.isEmpty { Text(detail).font(.footnote).foregroundStyle(MorningStyle.muted) }
            }.fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).font(.body).frame(width: 24)
        }.padding(.vertical, 4)
    }

    private func settingsButton(_ title: String, detail: String = "", symbol: String,
                                action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                settingsLabel(title, detail: detail, symbol: symbol)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(MorningStyle.muted)
            }.frame(maxWidth: .infinity, minHeight: 32, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }

    @ViewBuilder private var completion: some View {
        if let session = store.session, let completed = session.completedAt, Calendar.current.isDateInToday(completed) {
            Section(french ? "Votre matin" : "Your morning") {
                let elapsed = MorningStyle.duration(session.activeDuration(until: completed))
                Text(french ? "\(session.completedStepIDs.count) moments · temps écoulé : \(elapsed)"
                            : "\(session.completedStepIDs.count) moments · elapsed: \(elapsed)")
                    .accessibilityIdentifier("morning.completeSummary")
                if let summary = store.executionSummary { Text(summary).accessibilityIdentifier("morning.executionSummary") }
                if store.shouldOfferCompletionReflection {
                    if let question = store.currentClosingQuestion {
                        Text(verbatim: question.prompt(french: french))
                            .accessibilityIdentifier("morning.closingQuestion")
                    }
                    Button { store.openCompletionCapture() } label: {
                        Label(french ? "Dire une pensée" : "Speak a thought", systemImage: "mic")
                    }.disabled(store.voiceInputBlocksPlayback).accessibilityIdentifier("morning.speakReflection")
                    Button(french ? "Écrire" : "Write") { store.answerClosingQuestionInWriting() }
                        .accessibilityIdentifier("morning.reflect")
                    if store.currentClosingQuestion != nil {
                        Button(french ? "Passer" : "Skip") { store.skipClosingQuestion() }
                            .accessibilityIdentifier("morning.skipQuestion")
                    }
                    Button(french ? "Plus tard" : "Not now") { store.discardCompletionReflection() }
                        .accessibilityIdentifier("morning.dismissReflection")
                }
            }
        }
    }

}

struct StepEditor: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineStep> var step: RoutineStep
    @ViewState<Bool> private var keepInSuggestions: Bool
    @ViewState<Bool> private var keepDuration: Bool
    @ViewState<Bool> private var choosingRemoval = false
    @ViewState<String?> private var saveError = nil
    @ViewState<Bool> private var choosingSlack = false
    let assignmentContext: RoutineStepAssignmentContext?
    let onSave: (RoutineStep, Bool, Bool) -> Bool
    let onDelete: (Bool) -> Bool
    let failureMessage: () -> String

    init(store: MorningStore, step: RoutineStep, preference: RoutinePreference?, assignmentContext: RoutineStepAssignmentContext?,
         onSave: @escaping (RoutineStep, Bool, Bool) -> Bool,
         onDelete: @escaping (Bool) -> Bool, failureMessage: @escaping () -> String) {
        _step = ViewState(initialValue: step)
        self.store = store; self.assignmentContext = assignmentContext
        _keepInSuggestions = ViewState(initialValue: preference?.presence == .keep)
        _keepDuration = ViewState(initialValue: preference?.durationMinutes != nil)
        self.onSave = onSave; self.onDelete = onDelete; self.failureMessage = failureMessage
    }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    TextField("Give this step a name", text: $step.title)
                        .accessibilityLabel("Step name").accessibilityIdentifier("step.name")
                    if step.target?.integrationRoute == .api {
                        Text(step.detail).textSelection(.enabled)
                    } else if step.automation == .savedObservation {
                        Text(step.detail).textSelection(.enabled)
                        Text("Choose a different excerpt from its observation in Review. Switching to Read this text aloud makes it an ordinary note.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
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
                        Text(step.target == nil ? AppLanguage.localized("User-led moment")
                             : (AppLanguage.isFrench ? "Action choisie ci-dessous" : "Action chosen below"))
                            .tag(Optional<RoutineStepAutomation>.none)
                        Text("Read this text aloud").tag(Optional(RoutineStepAutomation.spokenNote))
                        Text("Read today's calendar").tag(Optional(RoutineStepAutomation.todayCalendar))
                        Text("Read today's briefing").tag(Optional(RoutineStepAutomation.morningBriefing))
                        Text(AppLanguage.isFrench ? "Prendre ce temps, puis continuer" : "Keep this time, then continue").tag(Optional(RoutineStepAutomation.timedMoment))
                        Text(AppLanguage.isFrench ? "Lire mes mails et m’aider à répondre" : "Read my mail and help me reply").tag(Optional(RoutineStepAutomation.gmailInbox))
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
                StepTargetEditor(target: $step.target, reviewedDetail: step.detail)
                if assignmentContext != nil {
                    Section {
                        Button(AppLanguage.isFrench ? "Choisir un compte et un canal Slack" : "Choose a Slack account and channel") { choosingSlack = true }
                            .disabled(store.busy || store.sessionActive || store.privacyBlocksWork)
                            .accessibilityIdentifier("step.chooseSlack")
                        if let sourceLabel = step.reviewedSourceLabel {
                            Text(AppLanguage.isFrench ? "Source choisie" : "Selected source").font(.caption)
                            Text(sourceLabel).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("step.selectedSlackSource")
                            Text(AppLanguage.isFrench ? "Votre note personnelle est conservée. Enregistrez, puis relisez et validez la routine."
                                : "Your personal note is retained. Save, then review and approve the routine.")
                                .font(.footnote)
                        }
                    } header: { Text(AppLanguage.isFrench ? "Pour ce moment" : "For this moment") }
                }
                if case let .inAppWeb(url) = step.target, let site = WebMorningSite(url: url), site != .gmail {
                    Section {
                        Picker(AppLanguage.isFrench ? "Ce que MORE fait" : "What MORE does", selection: $step.webBehavior) {
                            Text(AppLanguage.isFrench ? "Je navigue moi-même" : "I browse myself").tag(Optional<WebMorningBehavior>.none)
                            ForEach(WebMorningBehavior.availableBehaviors(for: site), id: \.self) { behavior in
                                Text(behavior.displayName).tag(Optional(behavior))
                            }
                        }.accessibilityIdentifier("step.webBehavior")
                        if step.webBehavior != nil {
                            if let behavior = step.webBehavior, WebMorningBehavior.permitsLikes(for: site, behavior: behavior) {
                                Toggle(AppLanguage.isFrench ? "Aimer jusqu’à 3 contenus affichés" : "Like up to 3 displayed contents", isOn: Binding(
                                    get: { step.webLikesAllowed == true }, set: { step.webLikesAllowed = $0 }))
                                    .accessibilityIdentifier("step.webLikes")
                            }
                            Text(step.executionDescription).font(.footnote).foregroundStyle(MorningStyle.muted)
                        }
                    } header: { Text(AppLanguage.isFrench ? "Pendant la navigation" : "While browsing") }
                }
                Section {
                    Button("Remove this step", role: .destructive) { choosingRemoval = true }
                        .accessibilityIdentifier("step.remove")
                }
                if let saveError {
                    Section { Text(saveError).foregroundStyle(.red).accessibilityIdentifier("step.saveError") }
                }
            }
            .accessibilityIdentifier("step.editor.form")
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
                        do { try edited.target?.validateIntegration() }
                        catch { saveError = error.moreDescription; return }
                        edited.title = edited.title.trimmingCharacters(in: .whitespacesAndNewlines)
                        if edited.automation != .savedObservation && edited.reviewedSourceLabel == nil { edited.observationReference = nil }
                        if edited.target != nil { edited.automation = nil }
                        if case let .inAppWeb(url) = edited.target, let site = WebMorningSite(url: url), let behavior = edited.webBehavior {
                            guard WebMorningBehavior.availableBehaviors(for: site).contains(behavior) else {
                                saveError = AppLanguage.isFrench ? "Choisissez un comportement disponible pour ce site." : "Choose an available behavior for this site."; return
                            }
                            if !WebMorningBehavior.permitsLikes(for: site, behavior: behavior) { edited.webLikesAllowed = false }
                        }
                        if case .inAppWeb = edited.target { } else { edited.webBehavior = nil; edited.webLikesAllowed = nil }
                        if onSave(edited, keepInSuggestions, keepDuration) { dismiss() }
                        else { saveError = failureMessage() }
                    }
                    .disabled(step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("step.save")
                }
            }
            .onChange(of: step.durationMinutes) { _, _ in keepDuration = true }
            .onChange(of: step.target) { _, target in
                step.webLikesAllowed = false
                if case let .inAppWeb(url) = target, let site = WebMorningSite(url: url) {
                    step.webBehavior = WebMorningBehavior.defaultBehavior(for: site)
                    step.automation = nil
                } else { step.webBehavior = nil }
            }
            .onChange(of: step.automation) { _, operation in
                if operation != nil { step.target = nil; step.webBehavior = nil; step.webLikesAllowed = nil }
            }
            .confirmationDialog("Remove this moment?", isPresented: $choosingRemoval, titleVisibility: .visible) {
                Button("Remove from this draft", role: .destructive) { remove(excluding: false) }
                    .accessibilityIdentifier("step.removeDraft")
                Button("Exclude from future suggestions", role: .destructive) { remove(excluding: true) }
                    .accessibilityIdentifier("step.exclude")
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Removing only this draft leaves saved choices intact. Excluding also asks future suggestions to leave this activity out until you clear that choice.")
            }
            .sheet(isPresented: $choosingSlack) {
                NavigationStack {
                    SlackRoutineSetupView(store: store, assignmentContext: assignmentContext, onUse: { target, sourceLabel in
                        guard let assignmentContext else { return false }
                        do {
                            step = try assignmentContext.assigning(target, to: step, routine: store.routine,
                                generation: store.dataGeneration, sourceLabel: sourceLabel)
                            choosingSlack = false
                            return true
                        } catch { saveError = error.moreDescription; return false }
                    })
                    .toolbar { ToolbarItem(placement: .cancellationAction) {
                        Button(AppLanguage.isFrench ? "Annuler" : "Cancel") { choosingSlack = false }
                    } }
                }
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
        if step.target != nil { return step.executionDescription }
        return switch step.automation {
        case .none:
            AppLanguage.localized("Take this moment at your own pace, then tap Next when you're ready.")
        case .spokenNote:
            AppLanguage.localized("Reads the text you approve for this step. Speaking the instructions doesn't carry out the activity they describe.")
        case .todayCalendar:
            AppLanguage.localized("Reads today's remaining events from calendars you select in Your day. Calendar access and spoken guidance are required.")
        case .morningBriefing:
            AppLanguage.localized("Reads a current recap from the calendars and optional city you choose in Your day. Available sources are prepared before speech; no events are changed.")
        case .savedObservation:
            AppLanguage.localized("Reads the dated excerpt you selected. If the source changes or is deleted, playback stops for review. This is a saved observation, not a live inbox.")
        case .timedMoment, .gmailInbox:
            step.executionDescription
        }
    }
}
