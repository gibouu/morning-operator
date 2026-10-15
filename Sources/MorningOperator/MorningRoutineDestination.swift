import SwiftUI
import MorningCore

/// The center destination owns one reusable routine. The shell supplies its tab
/// label from `store.routine == nil`: Learn before creation, Routine afterward.
/// Selecting this destination never creates, approves or starts a routine.
struct MorningRoutineDestination: View {
    @Bindable var store: MorningStore
    @Binding var learningRequested: Bool
    /// Feed this into the shell's pending-entry occupancy guard.
    var onInteractionChanged: (Bool) -> Void
    @ViewState<Bool> private var refining = false
    @ViewState<Bool> private var editingMoment = false
    @ViewState<Bool> private var isVisible = false

    init(store: MorningStore, learningRequested: Binding<Bool> = .constant(false),
         onInteractionChanged: @escaping (Bool) -> Void = { _ in }) {
        self.store = store
        _learningRequested = learningRequested
        self.onInteractionChanged = onInteractionChanged
    }

    private var isInteracting: Bool { store.routine == nil || refining || editingMoment }

    var body: some View {
        NavigationStack {
            Group {
                if store.routine == nil {
                    learningPage
                } else {
                    RoutineReviewContent(store: store, onLearn: { refining = true },
                                         onEditorPresentationChanged: { editingMoment = $0 })
                }
            }
            .navigationDestination(isPresented: $refining) { learningPage }
        }
        .onAppear {
            isVisible = true
            openRequestedLearning()
            onInteractionChanged(isInteracting)
        }
        .onChange(of: learningRequested) { _, _ in openRequestedLearning() }
        .onChange(of: isVisible && isInteracting) { _, value in onInteractionChanged(value) }
        .onChange(of: store.dataGeneration) { _, _ in
            learningRequested = false
            refining = false
            editingMoment = false
        }
        .onDisappear {
            isVisible = false
            onInteractionChanged(false)
        }
    }

    private func openRequestedLearning() {
        guard learningRequested else { return }
        learningRequested = false
        if store.routine != nil { refining = true }
    }

    private var learningPage: some View {
        RoutineLearningPage(store: store, onRoutineSaved: { refining = false })
    }
}

/// Compatibility presentation for existing review links. The center tab embeds
/// RoutineReviewContent directly, so it has no modal close or extra editing mode.
struct RoutineReviewEditor: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.routine == nil {
                    RoutineLearningPage(store: store, onRoutineSaved: { })
                } else {
                    RoutineReviewContent(store: store, onLearn: onLearn, onApproved: {
                        dismiss()
                        store.tab = .today
                    })
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", systemImage: "xmark") { dismiss() }
                        .accessibilityIdentifier("destination.close")
                        .disabled(store.privacyBlocksWork)
                }
            }
        }
    }
}

private struct RoutineLearningPage: View {
    @Bindable var store: MorningStore
    var onRoutineSaved: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LearnView(store: store, allowsManualRoutineCreation: false,
                          onRoutineSaved: onRoutineSaved)
                if let notice = store.notice {
                    NoticeView(text: notice, dismiss: { store.notice = nil })
                }
            }
            .padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false))
        .navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("routine.learning")
    }
}

/// Content shared by the persistent center destination and legacy modal links.
/// Tapping a moment edits it immediately. Native move handles are always available.
struct RoutineReviewContent: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    var onApproved: () -> Void = { }
    var onEditorPresentationChanged: (Bool) -> Void = { _ in }
    @ViewState<RoutineStepEdit?> private var editingStep = nil
    @ViewState<Bool> private var isVisible = false

    private var editsDisabled: Bool {
        store.busy || store.sessionActive || store.privacyBlocksWork || !store.storageIsAvailable
    }

    var body: some View {
        let generation = store.dataGeneration
        MorningList {
            if let routine = store.routine {
                Section {
                    RoutineReviewSummary(routine: routine, sessionActive: store.sessionActive)
                }
                Section {
                    ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                        Button { openStep(step, in: routine, generation: generation) } label: {
                            RoutineMomentRow(step: step)
                        }
                        .buttonStyle(.plain).disabled(editsDisabled)
                        .accessibilityIdentifier("routine.step.\(index)")
                        .accessibilityHint("Edit this moment")
                        .accessibilityAction(named: "Move earlier") {
                            move(step, by: -1, in: routine, generation: generation)
                        }
                        .accessibilityAction(named: "Move later") {
                            move(step, by: 1, in: routine, generation: generation)
                        }
                    }
                    .onMove { source, destination in
                        var ids = routine.steps.map(\.id)
                        ids.move(fromOffsets: source, toOffset: destination)
                        _ = store.reorderSteps(ids, expectedRoutineID: routine.id, expectedGeneration: generation)
                    }
                    .moveDisabled(editsDisabled)

                    Button("Add a moment", systemImage: "plus") {
                        openStep(RoutineStep(title: "", kind: .custom, durationMinutes: 5),
                                 in: routine, generation: generation)
                    }
                    .disabled(editsDisabled).accessibilityIdentifier("routine.add")
                } header: {
                    Text("Your moments")
                } footer: {
                    Text("Tap a moment to edit. Drag to change the order. Changes save as a draft and need your approval.")
                }

                RoutineTimeBudgetSection(store: store, isDisabled: editsDisabled)
                Section {
                    Button("Learn from an observation", systemImage: "sparkles", action: onLearn)
                        .disabled(editsDisabled).accessibilityIdentifier("learn.refine")
                    if !store.routinePreferences.entries.isEmpty || store.routinePreferencesIssue != nil {
                        NavigationLink { RoutinePreferencesView(store: store) } label: {
                            Label(store.routinePreferencesIssue == nil ? "Saved choices" : "Saved choices need review",
                                  systemImage: "heart.text.clipboard")
                        }
                        .disabled(store.privacyBlocksWork).accessibilityIdentifier("routine.preferences")
                    }
                    if store.previousRoutine != nil {
                        Button("Restore previous routine") { store.restorePreviousRoutine() }
                            .disabled(editsDisabled).accessibilityIdentifier("routine.restore")
                    }
                }
                if routine.isSynthetic {
                    Label("Sample routine · not observed behavior", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("routine.source")
                }
            }
            if let notice = store.notice {
                Text(notice).font(.caption).foregroundStyle(MorningStyle.muted)
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(editsDisabled ? .inactive : .active))
        #endif
        .scrollContentBackground(.hidden).background(MorningStyle.background)
        .navigationTitle("Routine").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("routine.editor")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let routine = store.routine, !routine.isApproved {
                Button("Approve this routine", systemImage: "checkmark") {
                    guard store.dataGeneration == generation, store.routine == routine else { return }
                    guard store.approve(), store.routine?.isApproved == true else { return }
                    onApproved()
                }
                .frame(maxWidth: .infinity).buttonStyle(PrimaryButtonStyle())
                .disabled(editsDisabled || routine.steps.isEmpty || store.routinePreferencesIssue != nil)
                .accessibilityIdentifier("routine.approve")
                .padding(20).background(MorningStyle.background)
            }
        }
        .sheet(item: $editingStep) { selection in
            StepEditor(step: selection.step, preference: store.savedPreference(for: selection.step),
                       onSave: { edited, keep, timing in
                guard accepts(selection) else { return false }
                return store.saveStep(edited, keepInSuggestions: keep, keepDuration: timing)
            }, onDelete: { exclude in
                guard accepts(selection) else { return false }
                return store.removeStep(selection.step, excludeFromSuggestions: exclude)
            }, failureMessage: { store.notice ?? String(localized: "Your change couldn't be saved. Try again.") })
        }
        .onAppear {
            isVisible = true
            onEditorPresentationChanged(editingStep != nil)
        }
        .onChange(of: isVisible && editingStep != nil) { _, value in onEditorPresentationChanged(value) }
        .onChange(of: store.dataGeneration) { _, _ in editingStep = nil }
        .onDisappear {
            isVisible = false
            onEditorPresentationChanged(false)
        }
    }

    private func openStep(_ step: RoutineStep, in routine: RoutineVersion, generation: UUID) {
        guard !editsDisabled, store.dataGeneration == generation, store.routine == routine else { return }
        editingStep = RoutineStepEdit(step: step, baseRoutine: routine, generation: generation)
    }

    private func accepts(_ selection: RoutineStepEdit) -> Bool {
        guard !editsDisabled else {
            store.notice = String(localized: "Your change couldn't be saved right now. Finish the current activity and check local storage before trying again.")
            return false
        }
        guard selection.generation == store.dataGeneration, store.routine == selection.baseRoutine else {
            store.notice = String(localized: "Your routine changed while this moment was open. Cancel and reopen the moment to edit the current version.")
            return false
        }
        return true
    }

    private func move(_ step: RoutineStep, by offset: Int, in routine: RoutineVersion, generation: UUID) {
        guard !editsDisabled, let index = routine.steps.firstIndex(where: { $0.id == step.id }),
              routine.steps.indices.contains(index + offset) else { return }
        var ids = routine.steps.map(\.id)
        ids.swapAt(index, index + offset)
        _ = store.reorderSteps(ids, expectedRoutineID: routine.id, expectedGeneration: generation)
    }
}

private struct RoutineStepEdit: Identifiable {
    let id = UUID()
    let step: RoutineStep
    let baseRoutine: RoutineVersion
    let generation: UUID
}
