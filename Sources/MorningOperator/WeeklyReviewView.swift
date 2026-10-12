import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct WeeklyReviewView: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    var onSettings: () -> Void
    @Binding var showingRoutineEditor: Bool
    @ViewState<Int> private var weekOffset = 0
    @ViewState<Date> private var today = Date()
    @ViewState<Bool> private var showingDays = false
    @ViewState<Bool> private var showingRoutineTiming = false
    @ViewState<Bool> private var learnAfterDismissal = false
    @Environment(\.scenePhase) private var scenePhase

    private var periodEnd: Date {
        Calendar.current.date(byAdding: .day, value: weekOffset * 7, to: today) ?? today
    }
    private var week: SevenDaySummary? { try? store.history.sevenDaySummary(endingOn: periodEnd) }
    private var observedPeriod: ObservationReviewPeriod? {
        try? ObservationReviewPeriod(archive: store.observationArchive, endingOn: periodEnd,
                                     calendarTimeZoneIdentifier: TimeZone.current.identifier)
    }
    private var periodTitle: String {
        let start = Calendar.current.date(byAdding: .day, value: -6, to: periodEnd) ?? periodEnd
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(periodEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                periodSelector
                activeRecordingStatus
                if let week {
                    if showingDays { days(in: week) }
                    if let observedPeriod, !observedPeriod.partitions.isEmpty {
                        ObservedMorningOverviewView(store: store, report: observedPeriod,
                                                    endingOn: periodEnd, onLearn: onLearn)
                        DisclosureGroup(isExpanded: $showingRoutineTiming) {
                            weekSummary(week).padding(.top, 12)
                        } label: {
                            Text("Routine-run timing")
                                .font(.subheadline.weight(.medium))
                                .accessibilityValue(showingRoutineTiming ? "Expanded" : "Collapsed")
                                .accessibilityIdentifier("review.routineTiming")
                        }.tint(MorningStyle.accent)
                    } else {
                        weekSummary(week)
                    }
                    observedAppTimes(week)
                } else {
                    Text("This period couldn't be displayed. Your saved mornings are unchanged.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                observationArchiveLinks
                reviewActions
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("review.week")
        .sheet(isPresented: $showingRoutineEditor, onDismiss: {
            if learnAfterDismissal { learnAfterDismissal = false; onLearn() }
        }) {
            RoutineReviewEditor(store: store, onLearn: {
                learnAfterDismissal = true
                showingRoutineEditor = false
            })
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { today = Date() } }
    }

    @ViewBuilder private var activeRecordingStatus: some View {
        #if os(iOS) && !targetEnvironment(macCatalyst) && canImport(ScreenCaptureKit)
        if #available(iOS 27.0, *) {
            let recording = ScreenRecordingService.shared
            if recording.captureMayBeActive || recording.hasRecordingToReview || recording.state == .failed
                || store.busy || store.hasPendingRecording || store.observationIssue != nil {
                MorningRecordingStatus(store: store, onReview: onLearn)
            }
        } else if store.hasPendingRecording {
            SavedRecordingRecoveryView(store: store, onReview: onLearn)
        }
        #else
        if store.hasPendingRecording {
            SavedRecordingRecoveryView(store: store, onReview: onLearn)
        }
        #endif
    }

    private var periodSelector: some View {
        HStack(spacing: 8) {
            Button { changeWeek(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous seven days").accessibilityIdentifier("review.previousWeek")
            Button {
                withAnimation(.snappy) { showingDays.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(periodTitle).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    Image(systemName: showingDays ? "chevron.up" : "chevron.down").font(.caption2.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel("\(periodTitle), \(showingDays ? "hide" : "show") days")
            .accessibilityIdentifier("review.period")
            Button { changeWeek(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(weekOffset == 0)
            .accessibilityLabel("Next seven days").accessibilityIdentifier("review.nextWeek")
        }
        .buttonStyle(.plain).foregroundStyle(MorningStyle.accent)
        .background(.regularMaterial, in: Capsule())
        .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            changeWeek(by: value.translation.width > 0 ? -1 : 1)
        })
    }

    @ViewBuilder private func observedAppTimes(_ week: SevenDaySummary) -> some View {
        if !week.apps.isEmpty {
            DisclosureGroup("Observed app time") {
                ForEach(week.apps) { app in observedApp(app) }
            }.font(.subheadline).tint(MorningStyle.accent)
        }
    }

    private func weekSummary(_ week: SevenDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let average = week.averageActiveDurationSeconds {
                Text("Average routine time").font(.subheadline).foregroundStyle(.secondary)
                Text(MorningStyle.duration(average))
                    .font(.system(size: 44, weight: .regular, design: .serif))
                    .accessibilityIdentifier("review.average")
                Text("Across \(week.timedRunCount) timed \(week.timedRunCount == 1 ? "run" : "runs")")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("Time in your routine, excluding pauses. Other app use isn't measured here.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(week.runCount == 0 ? (hasObservationsInPeriod ? "A morning, remembered." : "Your mornings will find their shape.") : "A morning saved. Time still unknown.")
                    .font(.system(.title2, design: .serif, weight: .medium))
                Text(week.runCount == 0
                     ? (hasObservationsInPeriod
                        ? "Explore the screens you saved below. Routine time begins with a completed run."
                        : "Finish a morning to begin your history. Days without a saved run stay empty.")
                     : "\(week.runCount) saved \(week.runCount == 1 ? "run has" : "runs have") no complete timing. They stay out of the average.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if week.runCount > week.timedRunCount, week.timedRunCount > 0 {
                Text("Runs with incomplete timing are excluded from this average.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if hasSampleRunsInPeriod {
                Label("Sample runs stay out of your personal averages.", systemImage: "sparkles")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 26))
    }

    private var hasSampleRunsInPeriod: Bool {
        guard let days = week?.days, let first = days.first?.dayKey, let last = days.last?.dayKey else { return false }
        return store.history.runs.contains { $0.isSynthetic && $0.dayKey >= first && $0.dayKey <= last }
    }

    private var hasObservationsInPeriod: Bool {
        guard let days = week?.days, let first = days.first?.dayKey, let last = days.last?.dayKey else { return false }
        return store.observationArchive.entries.contains { entry in
            guard let key = entry.observedDate?.dayKey else { return false }
            return key >= first && key <= last
        }
    }

    private func days(in week: SevenDaySummary) -> some View {
        VStack(spacing: 0) {
            ForEach(week.days.reversed()) { day in
                NavigationLink {
                    ReviewDayDetail(store: store, day: day, onLearn: onLearn)
                } label: {
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(day.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.medium))
                            Text(day.date.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(daySummaryText(day))
                            .font(.caption).foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 13).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("review.day.\(day.dayKey)")
                if day.id != week.days.first?.id { Divider() }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("review.days")
    }

    private func daySummaryText(_ day: MorningDaySummary) -> String {
        let observations = store.observationArchive.entries.filter { $0.observedDate?.dayKey == day.dayKey }.count
        let observationSummary = "\(observations) \(observations == 1 ? "observation" : "observations")"
        guard day.runCount > 0 else {
            if observations > 0 { return observationSummary }
            return day.hasEvidence ? "App observations" : "Nothing saved"
        }
        if observations > 0 { return "\(day.runCount) \(day.runCount == 1 ? "run" : "runs") · \(observationSummary)" }
        let time = day.timedRunCount == day.runCount
            ? MorningStyle.duration(day.totalActiveDurationSeconds) : "incomplete timing"
        return "\(day.runCount) \(day.runCount == 1 ? "run" : "runs") · \(time)"
    }

    private var observationArchiveLinks: some View {
        VStack(spacing: 0) {
            let undatedCount = store.observationArchive.entries.filter { $0.observedDate == nil }.count
            if undatedCount > 0 {
                NavigationLink {
                    ObservationHistoryView(store: store, onlyUndated: true, onLearn: onLearn)
                } label: {
                    actionRow("Date needed", detail: "\(undatedCount) \(undatedCount == 1 ? "observation needs" : "observations need") an observed day", symbol: "calendar.badge.questionmark")
                }.accessibilityIdentifier("review.undatedObservations")
                Divider()
            }
            NavigationLink {
                ObservationHistoryView(store: store, onLearn: onLearn)
            } label: {
                actionRow("Saved observations", detail: store.observationArchive.entries.isEmpty
                          ? "Original evidence and your corrections" : "\(store.observationArchive.entries.count) saved · separate from routine runs",
                          symbol: "doc.text.image")
            }.accessibilityIdentifier("review.observations")
        }.buttonStyle(.plain)
    }

    private var reviewActions: some View {
        VStack(spacing: 0) {
            Button { showingRoutineEditor = true } label: {
                actionRow("Your routine", detail: routineDetail, symbol: "list.bullet")
            }.accessibilityIdentifier("review.routine")
            Divider()
            Button(action: onLearn) {
                actionRow(store.hasImportedObservation ? "Review your observation" : "Learn from a morning",
                          detail: store.hasPendingRecording ? "A saved recording needs attention" : "Record, describe or refine", symbol: "sparkles")
            }.accessibilityIdentifier("review.learn")
            Divider()
            NavigationLink {
                CapturesView(store: store).navigationTitle("Saved thoughts").background(MorningStyle.background)
            } label: {
                actionRow("Saved thoughts", detail: store.captures.isEmpty ? "A place for what comes to mind" : "\(store.captures.count) saved", symbol: "text.bubble")
            }.accessibilityIdentifier("review.thoughts")
            Divider()
            NavigationLink {
                ScrollView { AppActivityView().padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                    .background(MorningStyle.background).navigationTitle("App activity")
            } label: {
                actionRow("App activity", detail: "Today's connected app entries", symbol: "arrow.triangle.2.circlepath")
            }.accessibilityIdentifier("review.appActivity")
            Divider()
            Button(action: onSettings) {
                actionRow("Settings & connections", detail: "Voice, calendar and preferences", symbol: "slider.horizontal.3")
            }.accessibilityIdentifier("navigation.setup")
        }.buttonStyle(.plain)
    }

    private var routineDetail: String {
        guard let routine = store.routine else { return "Build a routine that feels like you" }
        return "\(routine.steps.count) moments · \(routine.isApproved ? "approved" : "ready for your review")"
    }

    private func actionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.body).foregroundStyle(MorningStyle.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 16).contentShape(Rectangle()).foregroundStyle(.primary)
    }

    private func observedApp(_ app: AppUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(app.appName); Spacer(); Text(MorningStyle.duration(app.averageObservedDurationSeconds)) }
            Text("Average across \(app.daysWithDurationEvidence) days with time evidence. \(app.partialWindowDayCount) partial windows; \(app.unknownCoverageDayCount) with unknown coverage.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.top, 12)
    }

    private func changeWeek(by offset: Int) {
        withAnimation(.snappy) {
            weekOffset = min(0, weekOffset + offset)
            showingRoutineTiming = false
        }
    }
}

private struct RoutineReviewEditor: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState<RoutineStep?> private var editingStep = nil
    @ViewState<RoutineVersion?> private var exportSnapshot = nil
    @ViewState<Bool> private var importing = false
    @ViewState<UUID?> private var importGeneration = nil
    @ViewState<RoutineImportPreview?> private var importPreview = nil
    @ViewState<RoutineImportPreview?> private var loadedImport = nil
    @ViewState<Bool> private var importLoading = false
    @ViewState<String?> private var importError = nil
    @ViewState<Task<Void, Never>?> private var importTask = nil
    @ViewState<UUID?> private var importAttempt = nil

    var body: some View {
        let pickerGeneration = importGeneration
        NavigationStack {
            MorningList {
                if let routine = store.routine {
                    Section {
                        ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                            Button { editingStep = step } label: { stepRow(step) }
                                .buttonStyle(.plain).disabled(store.busy || store.sessionActive || importLoading)
                                .accessibilityIdentifier("routine.step.\(index)")
                        }
                        .onMove { source, destination in
                            var steps = store.routine?.steps ?? []
                            steps.move(fromOffsets: source, toOffset: destination)
                            store.updateSteps(steps)
                        }
                        .moveDisabled(store.busy || store.sessionActive || importLoading)
                        Button {
                            editingStep = RoutineStep(title: "", kind: .custom, durationMinutes: 5)
                        } label: { Label("Add a moment", systemImage: "plus") }
                            .disabled(store.busy || store.sessionActive || importLoading).accessibilityIdentifier("routine.add")
                    } header: {
                        Text(routine.isApproved ? "Your approved routine" : "A draft for you to review")
                    } footer: {
                        Text("Minutes are planned. Editing creates a new draft; your saved mornings keep their original routine.")
                    }
                    Section {
                        if store.previousRoutine != nil {
                            Button("Restore previous routine") { store.restorePreviousRoutine() }
                                .disabled(store.busy || store.sessionActive || importLoading).accessibilityIdentifier("routine.restore")
                        }
                        savedChoicesLink
                        Button("Export routine", systemImage: "square.and.arrow.up") { exportSnapshot = routine }
                            .disabled(importLoading)
                            .accessibilityIdentifier("routine.export")
                        Button("Learn from an observation", systemImage: "sparkles", action: onLearn)
                            .disabled(store.busy || store.sessionActive || importLoading).accessibilityIdentifier("learn.refine")
                    } footer: {
                        Text("Restoring a routine leaves your saved choices for future suggestions unchanged.")
                    }
                    if routine.isSynthetic {
                        Label("Sample routine · not observed behavior", systemImage: "sparkles")
                            .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("routine.source")
                    }
                } else {
                    Section {
                        Text("Start with a small part of your morning. You can change every step before approving it.")
                            .foregroundStyle(.secondary)
                        Button("Learn my morning", systemImage: "sparkles", action: onLearn)
                            .disabled(importLoading)
                            .accessibilityIdentifier("learn.begin")
                        Button("Build it myself") { store.useManualRoutine() }.disabled(importLoading)
                        Button("Explore a sample") { store.loadSample() }.disabled(importLoading).accessibilityIdentifier("routine.sample")
                        savedChoicesLink
                    }
                }
                Section {
                    Button("Import routine", systemImage: "square.and.arrow.down") {
                        guard !store.privacyBlocksWork else { return }
                        importGeneration = store.dataGeneration
                        importing = true
                    }
                        .disabled(store.busy || store.sessionActive || importLoading)
                        .accessibilityIdentifier("routine.import")
                    #if DEBUG
                    if let url = routineImportFixtureURL {
                        Button("Open staged routine file") { openRoutineFile(url, generation: store.dataGeneration) }
                            .disabled(store.busy || store.sessionActive || importLoading)
                            .accessibilityIdentifier("routine.importFixture")
                    }
                    #endif
                    if importLoading { ProgressView("Opening your routine…") }
                    if let importError {
                        Text(importError).font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("routine.importError")
                    }
                } footer: {
                    Text("Open a saved MORE plan and review it before making any changes.")
                }
                if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(MorningStyle.background)
            .navigationTitle("Your routine")
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(store.routine == nil || store.busy || store.sessionActive || importLoading)
                        .accessibilityIdentifier("routine.edit")
                }
                #endif
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let routine = store.routine, !routine.isApproved {
                    Button {
                        guard store.approve(), store.routine?.isApproved == true else { return }
                        dismiss()
                        store.tab = .today
                    } label: {
                        Label("Approve this routine", systemImage: "checkmark").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(MorningStyle.controlTint).controlSize(.large)
                    .disabled(store.busy || store.sessionActive || importLoading || routine.steps.isEmpty || store.routinePreferencesIssue != nil)
                    .accessibilityIdentifier("routine.approve")
                    .padding(20).background(.regularMaterial)
                }
            }
            .sheet(item: $editingStep) { step in
                StepEditor(step: step, preference: store.savedPreference(for: step), onSave: { edited, keep, timing in
                    store.saveStep(edited, keepInSuggestions: keep, keepDuration: timing)
                }, onDelete: { exclude in
                    store.removeStep(step, excludeFromSuggestions: exclude)
                }, failureMessage: { store.notice ?? "Your change couldn't be saved. Try again." })
            }
            .sheet(item: $exportSnapshot) { routine in RoutineExportView(routine: routine) }
            .sheet(item: $importPreview) { preview in
                RoutineImportView(document: preview.document, onUse: { document in
                    guard preview.generation == store.dataGeneration, !store.privacyBlocksWork,
                          store.useImportedRoutine(document, replacing: preview.baseRoutine) else { return false }
                    importPreview = nil
                    return true
                }, errorMessage: { store.notice }, onCancel: { importPreview = nil })
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                guard let pickerGeneration, pickerGeneration == store.dataGeneration,
                      !store.privacyBlocksWork else { return }
                importGeneration = nil
                switch result {
                case .success(let urls): if let url = urls.first { openRoutineFile(url, generation: pickerGeneration) }
                case .failure(let error): importError = error.localizedDescription
                }
            }
            .onChange(of: importing) { _, presenting in if !presenting { presentLoadedImport() } }
        }
        .onChange(of: store.dataGeneration) { _, _ in
            importGeneration = nil
            importing = false
            importAttempt = nil
            importPreview = nil
            loadedImport = nil
            importLoading = false
            importError = nil
            importTask?.cancel()
            importTask = nil
        }
        .onDisappear {
            importAttempt = nil
            loadedImport = nil
            importLoading = false
            importTask?.cancel()
            importTask = nil
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 580)
        #endif
    }

    private func openRoutineFile(_ url: URL, generation: UUID) {
        guard generation == store.dataGeneration, !store.privacyBlocksWork,
              !store.busy, !store.sessionActive, !importLoading else { return }
        let attempt = UUID()
        let base = store.routine
        importAttempt = attempt
        importLoading = true
        importError = nil
        importTask = Task { @MainActor in
            do {
                let document = try await RoutineDocumentReader().read(url)
                guard !Task.isCancelled, importAttempt == attempt, store.dataGeneration == generation, !store.privacyBlocksWork else { return }
                loadedImport = RoutineImportPreview(document: document, baseRoutine: base, generation: generation)
                presentLoadedImport()
            } catch {
                guard !Task.isCancelled, importAttempt == attempt, store.dataGeneration == generation, !store.privacyBlocksWork else { return }
                importLoading = false
                importError = "This file couldn't be opened: \(error.localizedDescription) Your current routine is unchanged."
            }
            importTask = nil
        }
    }

    private func presentLoadedImport() {
        guard !store.privacyBlocksWork, !importing, editingStep == nil, exportSnapshot == nil,
              let loadedImport, loadedImport.generation == store.dataGeneration else { return }
        self.loadedImport = nil
        importLoading = false
        importPreview = loadedImport
    }

    #if DEBUG
    private var routineImportFixtureURL: URL? {
        let process = ProcessInfo.processInfo
        guard process.arguments.contains("--ui-testing"), process.environment["MO_ROUTINE_IMPORT_TEST"] == "1",
              let workspace = process.arguments.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              UUID(uuidString: String(workspace.dropFirst("--ui-testing-workspace=".count))) != nil,
              let path = process.environment["MO_ROUTINE_IMPORT_FILE"], !path.isEmpty else { return nil }
        return path.hasPrefix("/") ? URL(fileURLWithPath: path)
            : FileManager.default.temporaryDirectory.appendingPathComponent(path)
    }
    #endif

    private func stepRow(_ step: RoutineStep) -> some View {
        HStack(spacing: 12) {
            Image(systemName: MorningStyle.symbol(for: step.kind))
                .font(.body).frame(width: 34, height: 34)
                .background(MorningStyle.color(for: step.kind), in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.subheadline.weight(.medium))
                Text("\(step.durationMinutes) min planned · \(step.automation == nil ? "Your own pace" : "Spoken guidance")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }.foregroundStyle(.primary).padding(.vertical, 4)
    }

    @ViewBuilder private var savedChoicesLink: some View {
        if !store.routinePreferences.entries.isEmpty || store.routinePreferencesIssue != nil {
            NavigationLink { RoutinePreferencesView(store: store) } label: {
                Label(store.routinePreferencesIssue == nil ? "Saved choices" : "Saved choices need review",
                      systemImage: store.routinePreferencesIssue == nil ? "heart.text.clipboard" : "exclamationmark.circle")
            }.accessibilityIdentifier("routine.preferences")
                .disabled(importLoading)
        }
    }
}

private struct RoutineImportPreview: Identifiable {
    let id = UUID()
    let document: PortableRoutineDocument
    let baseRoutine: RoutineVersion?
    let generation: UUID
}

private struct RoutinePreferencesView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var confirmingReset = false

    var body: some View {
        MorningList {
            Section {
                Text("These are choices you've made for future suggestions. Clearing a choice leaves your current routine unchanged.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let issue = store.routinePreferencesIssue {
                Section {
                    Text(issue).accessibilityIdentifier("preferences.issue")
                    Button("Reset saved choices", role: .destructive) { confirmingReset = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("preferences.reset")
                }
            } else {
                ForEach(store.routinePreferences.entries) { preference in
                    Section {
                        Text(preference.targetTitle).font(.headline)
                            .accessibilityIdentifier("preferences.title.\(preference.targetID.uuidString)")
                        if preference.presence == .exclude {
                            Text("Leave out of future suggestions")
                        } else if preference.presence == .keep {
                            Text("Keep in future suggestions")
                        }
                        if let minutes = preference.durationMinutes { Text("\(minutes) planned minutes, chosen by you") }
                        Button("Clear this choice") { _ = store.clearRoutinePreference(targetID: preference.targetID) }
                            .disabled(store.busy || store.sessionActive)
                            .accessibilityIdentifier("preferences.clear.\(preference.targetID.uuidString)")
                    }
                }
                if store.routinePreferences.entries.isEmpty {
                    ContentUnavailableView("No saved choices", systemImage: "heart",
                        description: Text("Future suggestions can vary. Keep a moment or its duration when editing your routine."))
                        .accessibilityIdentifier("preferences.empty")
                }
            }
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle("Saved choices").navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset unreadable choices?", isPresented: $confirmingReset, titleVisibility: .visible) {
            Button("Reset choices", role: .destructive) { _ = store.resetUnreadableRoutinePreferences() }
                .accessibilityIdentifier("preferences.confirmReset")
            Button("Cancel", role: .cancel) { }
        } message: { Text("This removes the unreadable choices. Your routine and observations stay saved. You can choose what to keep again.") }
    }
}

private struct ReviewDayDetail: View {
    @Bindable var store: MorningStore
    let day: MorningDaySummary
    var onLearn: () -> Void

    private var observations: [ObservationAcquisition] {
        store.observationArchive.entries.filter { $0.observedDate?.dayKey == day.dayKey }
            .sorted { ($0.importedAt ?? .distantPast) > ($1.importedAt ?? .distantPast) }
    }

    var body: some View {
        MorningList {
            if observations.isEmpty {
                Section("Observed mornings") {
                    Text("No observation dated to this day.").foregroundStyle(.secondary)
                }
            } else {
                ObservedMorningDaySections(store: store, dayKey: day.dayKey, onLearn: onLearn)
            }
            if day.runs.isEmpty {
                Section {
                    Text("No routine saved for this day.").font(.headline)
                    Text("A missing run stays unknown. It isn't counted as a zero-minute morning.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } header: { Text("Routine runs") }
            }
            ForEach(Array(day.runs.enumerated()), id: \.element.id) { index, run in
                Section {
                    LabeledContent("Active routine time", value: MorningStyle.duration(run.activeDurationSeconds))
                    LabeledContent("Planned time", value: "\(run.plannedDurationMinutes) min")
                    if run.activeDurationSeconds == nil {
                        Text("Timing is incomplete or unavailable; this run is excluded from time averages.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(run.routine.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: run.completedStepIDs.contains(step.id) ? "checkmark.circle" : run.skippedStepIDs.contains(step.id) ? "forward.end.circle" : "circle")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.subheadline)
                                Text(run.completedStepIDs.contains(step.id) ? "Marked complete" : run.skippedStepIDs.contains(step.id) ? "Skipped" : "Not completed")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(step.durationMinutes) min planned").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 4)
                    }
                } header: {
                    Text("Routine run \(index + 1) · \(run.outcome == .completed ? "completed" : "ended early")")
                } footer: {
                    Text("Saved routine version \(run.routineVersionNumber). Active time excludes pauses and doesn't measure activity in other apps.")
                }
            }
            if !day.appObservations.isEmpty {
                Section("App observations") {
                    ForEach(day.appObservations) { observation in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(observation.appName, value: MorningStyle.duration(observation.observedDurationSeconds))
                            Text(observation.coverage == .completeWindow ? "Complete for the declared observation window" : observation.coverage == .partialWindow ? "Partial observation window" : "Coverage unknown")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle(day.date.formatted(.dateTime.month(.abbreviated).day()))
        .accessibilityIdentifier("review.dayDetail")
    }
}
