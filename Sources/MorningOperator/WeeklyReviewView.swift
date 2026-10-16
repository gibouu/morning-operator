import SwiftUI
import UniformTypeIdentifiers
import MorningCore
import MorningApple

struct WeeklyReviewView: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    var onSettings: () -> Void
    @Binding var showingRoutineEditor: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState<Int> private var weekOffset = 0
    @ViewState<Date> private var today = Date()
    @ViewState<Bool> private var showingDays = false
    @ViewState<Bool> private var showingRoutineTiming = false
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
        return "\(start.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale))) – \(periodEnd.formatted(.dateTime.month(.abbreviated).day().year().locale(AppLanguage.locale)))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                periodSelector
                activeRecordingStatus
                MorningRecapCard(store: store)
                if let week {
                    if showingDays { days(in: week) }
                    if let observedPeriod, !observedPeriod.partitions.isEmpty {
                        ObservedMorningOverviewView(store: store, report: observedPeriod,
                                                    endingOn: periodEnd, onLearn: onLearn)
                        DisclosureGroup(isExpanded: $showingRoutineTiming) {
                            weekSummary(week).padding(.top, 12)
                        } label: {
                            Text("Routine-run timing")
                                .font(.raleway(.subheadline, .medium))
                                .accessibilityValue(showingRoutineTiming ? String(localized: "Expanded", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Collapsed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                                .accessibilityIdentifier("review.routineTiming")
                        }.tint(MorningStyle.accent)
                    } else {
                        weekSummary(week)
                    }
                    observedAppTimes(week)
                } else {
                    Text("This period couldn't be displayed. Your saved mornings are unchanged.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                }
                observationArchiveLinks
                reviewActions
            }.padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("review.week")
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
                MorningDottedIcon(systemName: "chevron.left").frame(width: 18, height: 18).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous seven days").accessibilityIdentifier("review.previousWeek")
            Button {
                withAnimation(reduceMotion ? nil : .snappy) { showingDays.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text(periodTitle).font(.raleway(.subheadline, .medium)).multilineTextAlignment(.center)
                    MorningDottedIcon(systemName: showingDays ? "chevron.up" : "chevron.down").frame(width: 16, height: 16).font(.raleway(.caption2, .semibold))
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(showingDays ? String(localized: "\(periodTitle), hide days", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "\(periodTitle), show days", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
            .accessibilityIdentifier("review.period")
            Button { changeWeek(by: 1) } label: {
                MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).frame(width: 44, height: 44)
            }
            .disabled(weekOffset == 0)
            .accessibilityLabel("Next seven days").accessibilityIdentifier("review.nextWeek")
        }
        // A dark pill anchors the week, matching the primary buttons.
        .buttonStyle(.plain).foregroundStyle(MorningStyle.onControl)
        .background(MorningStyle.controlTint, in: Capsule())
        .simultaneousGesture(DragGesture(minimumDistance: 55).onEnded { value in
            guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            changeWeek(by: value.translation.width > 0 ? -1 : 1)
        })
    }

    @ViewBuilder private func observedAppTimes(_ week: SevenDaySummary) -> some View {
        if !week.apps.isEmpty {
            DisclosureGroup("Observed app time") {
                ForEach(week.apps) { app in observedApp(app) }
            }.font(.raleway(.subheadline)).tint(MorningStyle.accent)
        }
    }

    private func weekSummary(_ week: SevenDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let average = week.averageActiveDurationSeconds {
                Text("Average routine time").font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                Text(MorningStyle.duration(average))
                    .scaledFont(44, relativeTo: .largeTitle, weight: .regular, design: .default)
                    .accessibilityIdentifier("review.average")
                Text("Across \(week.timedRunCount) timed runs")
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                Text("Time in your routine, excluding pauses. Other app use isn't measured here.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            } else {
                Text(week.runCount == 0 ? (hasObservationsInPeriod ? String(localized: "A morning, remembered.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Your mornings will find their shape.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) : String(localized: "A morning saved. Time still unknown.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    .font(.serif(.title2, .medium))
                Text(week.runCount == 0
                     ? (hasObservationsInPeriod
                        ? String(localized: "Explore the screens you saved below. Routine time begins with a completed run.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                        : String(localized: "Finish a morning to begin your history. Days without a saved run stay empty.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                     : String(localized: "\(week.runCount) saved runs have no complete timing. They stay out of the average.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
            if week.runCount > week.timedRunCount, week.timedRunCount > 0 {
                Text("Runs with incomplete timing are excluded from this average.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            if hasSampleRunsInPeriod {
                Label { Text("Sample runs stay out of your personal averages.") } icon: { MorningDottedIcon(systemName: "sparkles").frame(width: 18, height: 18) }
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22).background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
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
                            Text(day.date.formatted(.dateTime.weekday(.wide).locale(AppLanguage.locale))).font(.raleway(.subheadline, .medium))
                            Text(day.date.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale))).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                        Spacer()
                        Text(daySummaryText(day))
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).font(.raleway(.caption2)).foregroundStyle(.tertiary)
                    }.padding(.vertical, 13).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("review.day.\(day.dayKey)")
                if day.id != week.days.first?.id { Divider() }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("review.days")
    }

    private func daySummaryText(_ day: MorningDaySummary) -> String {
        let observations = store.observationArchive.entries.filter { $0.observedDate?.dayKey == day.dayKey }.count
        let observationSummary = AppLanguage.localized("\(observations) observations")
        guard day.runCount > 0 else {
            if observations > 0 { return observationSummary }
            return day.hasEvidence ? AppLanguage.localized("App observations") : AppLanguage.localized("Nothing saved")
        }
        if observations > 0 { return AppLanguage.localized("\(day.runCount) runs · \(observations) observations") }
        let time = day.timedRunCount == day.runCount
            ? MorningStyle.duration(day.totalActiveDurationSeconds) : AppLanguage.localized("incomplete timing")
        return AppLanguage.localized("\(day.runCount) runs · \(time)")
    }

    private var observationArchiveLinks: some View {
        VStack(spacing: 0) {
            let undatedCount = store.observationArchive.entries.filter { $0.observedDate == nil }.count
            if undatedCount > 0 {
                NavigationLink {
                    ObservationHistoryView(store: store, onlyUndated: true, onLearn: onLearn)
                } label: {
                    actionRow(AppLanguage.localized("Date needed"), detail: AppLanguage.localized("\(undatedCount) observations need an observed day"), symbol: "calendar.badge.questionmark")
                }.accessibilityIdentifier("review.undatedObservations")
                Divider()
            }
            NavigationLink {
                ObservationHistoryView(store: store, onLearn: onLearn)
            } label: {
                actionRow(AppLanguage.localized("Saved observations"), detail: store.observationArchive.entries.isEmpty
                          ? AppLanguage.localized("Original evidence and your corrections") : AppLanguage.localized("\(store.observationArchive.entries.count) saved · separate from routine runs"),
                          symbol: "doc.text.image")
            }.accessibilityIdentifier("review.observations")
        }.buttonStyle(.plain)
    }

    private var reviewActions: some View {
        VStack(spacing: 0) {
            Button { showingRoutineEditor = true } label: {
                actionRow(AppLanguage.localized("Your routine"), detail: routineDetail, symbol: "list.bullet")
            }.accessibilityIdentifier("review.routine")
            Divider()
            Button(action: onLearn) {
                actionRow(store.hasImportedObservation ? AppLanguage.localized("Review your observation") : AppLanguage.localized("Learn from a morning"),
                          detail: store.hasPendingRecording ? AppLanguage.localized("A saved recording needs attention") : AppLanguage.localized("Record, describe or refine"), symbol: "sparkles")
            }.accessibilityIdentifier("review.learn")
            Divider()
            NavigationLink {
                CapturesView(store: store).navigationTitle("Saved thoughts").background(MorningStyle.background)
            } label: {
                actionRow(AppLanguage.localized("Saved thoughts"), detail: store.captures.isEmpty ? AppLanguage.localized("A place for what comes to mind") : AppLanguage.localized("\(store.captures.count) saved"), symbol: "text.bubble")
            }.accessibilityIdentifier("review.thoughts")
            Divider()
            NavigationLink {
                ScrollView { AppActivityView().padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                    .background(MorningStyle.background).navigationTitle("App activity")
            } label: {
                actionRow(AppLanguage.localized("App activity"), detail: AppLanguage.localized("Today's connected app entries"), symbol: "arrow.triangle.2.circlepath")
            }.accessibilityIdentifier("review.appActivity")
            Divider()
            Button(action: onSettings) {
                actionRow(AppLanguage.localized("Settings & connections"), detail: AppLanguage.localized("Voice, calendar and preferences"), symbol: "slider.horizontal.3")
            }.accessibilityIdentifier("navigation.setup")
        }.buttonStyle(.plain)
    }

    private var routineDetail: String {
        guard let routine = store.routine else { return AppLanguage.localized("Build a routine that feels like you") }
        return routine.isApproved ? AppLanguage.localized("\(routine.steps.count) moments · approved") : AppLanguage.localized("\(routine.steps.count) moments · ready for your review")
    }

    private func actionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            MorningDottedIcon(systemName: symbol).frame(width: 24, height: 24).font(.raleway(.body)).foregroundStyle(MorningStyle.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.raleway(.subheadline, .medium))
                if !detail.isEmpty { Text(detail).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
            }
            Spacer(minLength: 8)
            MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).font(.raleway(.caption2)).foregroundStyle(.tertiary)
        }.padding(.vertical, 16).contentShape(Rectangle()).foregroundStyle(.primary)
    }

    private func observedApp(_ app: AppUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(app.appName); Spacer(); Text(MorningStyle.duration(app.averageObservedDurationSeconds)) }
            Text("Average across \(app.daysWithDurationEvidence) days with time evidence. \(app.partialWindowDayCount) partial windows; \(app.unknownCoverageDayCount) with unknown coverage.")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
        }.padding(.top, 12)
    }

    private func changeWeek(by offset: Int) {
        withAnimation(reduceMotion ? nil : .snappy) {
            weekOffset = min(0, weekOffset + offset)
            showingRoutineTiming = false
        }
    }
}

struct RoutineReviewEditor: View {
    @Bindable var store: MorningStore
    var onLearn: () -> Void
    /// Off when the editor is a tab of its own rather than a cover over Home.
    var showsClose = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewState<RoutineStep?> private var editingStep = nil
    @ViewState<RoutineStepAssignmentContext?> private var editingAssignment = nil

    var body: some View {
        OptionalNavigationStack(enabled: showsClose) {
            MorningList {
                if let routine = store.routine {
                    Section {
                        Text(dynamicTypeSize.isAccessibilitySize
                            ? (AppLanguage.isFrench ? "Votre matin" : "Your morning")
                            : (AppLanguage.isFrench ? "Voici à quoi ressemble votre matin." : "Here is what your morning looks like."))
                            .font(MorningTheme.Typography.heading)
                        Text(AppLanguage.isFrench ? "MORE s’occupe des actions présentées ici. Vous pouvez l’interrompre, prolonger un moment ou arrêter à la voix." : "MORE takes care of the actions shown here. You can interrupt, extend a moment or stop by voice.")
                            .font(.subheadline).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("routine.delegation")
                    }
                    Section {
                        ForEach(Array(routine.steps.enumerated()), id: \.element.id) { index, step in
                            Button {
                                editingAssignment = .init(routineVersionID: routine.id, stepID: step.id, privacyGeneration: store.dataGeneration)
                                editingStep = step
                            } label: { stepRow(step) }
                                .buttonStyle(.plain).disabled(store.busy || store.sessionActive)
                                .accessibilityIdentifier("routine.step.\(index)")
                        }
                        .onMove { source, destination in
                            var steps = routine.steps
                            steps.move(fromOffsets: source, toOffset: destination)
                            _ = store.reorderSteps(steps.map(\.id), expectedRoutineID: routine.id,
                                expectedGeneration: store.dataGeneration)
                        }
                        .moveDisabled(store.busy || store.sessionActive)
                        Button {
                            editingAssignment = nil
                            editingStep = RoutineStep(title: "", kind: .custom, durationMinutes: 5)
                        } label: { Label { Text("Add a moment") } icon: { MorningDottedIcon(systemName: "plus").frame(width: 22, height: 22) } }
                            .disabled(store.busy || store.sessionActive).accessibilityIdentifier("routine.add")
                    }
                    RoutineTimeBudgetSection(store: store, isDisabled: false)
                    Section {
                        if store.previousRoutine != nil {
                            Button("Restore previous routine") { store.restorePreviousRoutine() }
                                .disabled(store.busy || store.sessionActive).accessibilityIdentifier("routine.restore")
                        }
                        savedChoicesLink
                        Button(action: onLearn) {
                            Label { Text("Learn from an observation") } icon: { MorningDottedIcon(systemName: "sparkles").frame(width: 22, height: 22) }
                        }
                            .disabled(store.busy || store.sessionActive).accessibilityIdentifier("learn.refine")
                    }
                    if routine.isSynthetic {
                        Label { Text("Sample routine · not observed behavior") } icon: { MorningDottedIcon(systemName: "sparkles").frame(width: 18, height: 18) }
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).accessibilityIdentifier("routine.source")
                    }
                } else {
                    Section {
                        Button(action: onLearn) {
                            Label { Text("Learn my morning") } icon: { MorningDottedIcon(systemName: "sparkles").frame(width: 22, height: 22) }
                        }
                            .accessibilityIdentifier("learn.begin")
                        Button("Build it myself") { store.useManualRoutine() }
                        Button("Explore a sample") { store.loadSample() }.accessibilityIdentifier("routine.sample")
                        savedChoicesLink
                    }
                }
                Section {
                    DisclosureGroup("About this routine") {
                        Text("Minutes are planned. Editing creates a new draft; your saved mornings keep their original routine.")
                    }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                }
                if let notice = store.notice { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
            }
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
            .accessibilityIdentifier("routine.editor")
            .navigationTitle("Your routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { Text("Routine").font(MorningTheme.Typography.title) }
                #if os(iOS)
                ToolbarItem(placement: .primaryAction) {
                    EditButton().disabled(store.routine == nil || store.busy || store.sessionActive)
                        .accessibilityIdentifier("routine.edit")
                }
                #endif
                if showsClose {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            MorningDottedIcon(systemName: "xmark").frame(width: 24, height: 24).frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundStyle(MorningStyle.ink)
                            .accessibilityLabel("Done").accessibilityIdentifier("destination.close")
                    }.sharedBackgroundVisibility(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let routine = store.routine, !routine.isApproved {
                    Button {
                        guard store.approve(), store.routine?.isApproved == true else { return }
                        dismiss()
                        store.tab = .today
                    } label: {
                        Label { Text(dynamicTypeSize.isAccessibilitySize
                            ? (AppLanguage.isFrench ? "Confier à MORE" : "Let MORE do it")
                            : (AppLanguage.isFrench ? "Confier mon matin à MORE" : "Let MORE take care of my morning"))
                        } icon: { MorningDottedIcon(systemName: "checkmark").frame(width: 22, height: 22) }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(store.busy || store.sessionActive || routine.steps.isEmpty || store.routinePreferencesIssue != nil)
                    .accessibilityIdentifier("routine.approve")
                    .padding(20).background(MorningStyle.background)
                }
            }
            .sheet(item: $editingStep) { step in
                let assignment = editingAssignment
                StepEditor(store: store, step: step, preference: store.savedPreference(for: step), assignmentContext: assignment, onSave: { edited, keep, timing in
                    store.saveStep(edited, keepInSuggestions: keep, keepDuration: timing, assignmentContext: assignment)
                }, onDelete: { exclude in
                    store.removeStep(step, excludeFromSuggestions: exclude)
                }, failureMessage: { store.notice ?? AppLanguage.localized("Your change couldn't be saved. Try again.") })
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 580)
        #endif
    }

    private func stepRow(_ step: RoutineStep) -> some View {
        HStack(spacing: 12) {
            MorningDottedIcon(systemName: MorningStyle.symbol(for: step.kind)).frame(width: 22, height: 22)
                .font(.raleway(.body)).frame(width: 34, height: 34)
                .background(MorningStyle.selected, in: RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title).font(.raleway(.subheadline, .medium))
                Text("\(step.durationMinutes) min · \(step.executionDescription)")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if let sourceLabel = step.reviewedSourceLabel {
                    Text(sourceLabel).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
                if let target = step.target, target.integrationRoute == .api {
                    Text(step.detail).font(.footnote).foregroundStyle(MorningStyle.muted)
                    Text(RoutineConnectedReview.summary(for: target) ?? String(localized: "Review unavailable", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                        .font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).font(.raleway(.caption2)).foregroundStyle(.tertiary)
        }.foregroundStyle(.primary).padding(.vertical, 4)
    }

    @ViewBuilder private var savedChoicesLink: some View {
        // Saved choices remain inspectable and individually reversible, including
        // an order-only journal. An unreadable journal exposes its recovery here.
        if store.routinePreferencesIssue != nil || !store.routinePreferences.entries.isEmpty || store.routinePreferences.order != nil {
            NavigationLink { RoutinePreferencesView(store: store) } label: {
                Label { Text(store.routinePreferencesIssue == nil ? String(localized: "Saved choices", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Saved choices need review", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)) } icon: {
                    MorningDottedIcon(systemName: store.routinePreferencesIssue == nil ? "heart.text.clipboard" : "exclamationmark.circle").frame(width: 22, height: 22)
                }
            }.accessibilityIdentifier("routine.preferences")
        }
    }
}

struct RoutinePreferencesView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var confirmingReset = false

    var body: some View {
        MorningList {
            Section {
                Text("These are choices you've made for future suggestions. Clearing a choice leaves your current routine unchanged.")
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
            if let issue = store.routinePreferencesIssue {
                Section {
                    Text(issue).accessibilityIdentifier("preferences.issue")
                    Button("Reset saved choices", role: .destructive) { confirmingReset = true }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("preferences.reset")
                }
            } else {
                if let order = store.routinePreferences.order {
                    Section {
                        Text(verbatim: AppLanguage.isFrench ? "Ordre enregistré" : "Saved order")
                            .font(MorningTheme.Typography.heading)
                        Text(verbatim: AppLanguage.isFrench
                            ? "Les moments retrouvés dans vos prochaines suggestions gardent cet ordre. Les nouveaux moments restent à vérifier."
                            : "Matching moments keep this order in future suggestions. New moments still need your review.")
                            .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                        ForEach(Array(order.enumerated()), id: \.element.targetID) { index, moment in
                            Text(verbatim: "\(index + 1). \(moment.targetTitle)")
                        }
                        Button(AppLanguage.isFrench ? "Ne plus conserver cet ordre" : "Forget saved order") {
                            _ = store.clearSavedRoutineOrder()
                        }
                        .disabled(store.busy || store.sessionActive)
                        .accessibilityIdentifier("preferences.clearOrder")
                    }
                    .accessibilityIdentifier("preferences.savedOrder")
                }
                ForEach(store.routinePreferences.entries) { preference in
                    Section {
                        Text(preference.targetTitle).font(MorningTheme.Typography.heading)
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
                if store.routinePreferences.entries.isEmpty && store.routinePreferences.order == nil {
                    ContentUnavailableView("No saved choices", systemImage: "heart",
                        description: Text("Future suggestions can vary. Keep a moment or its duration when editing your routine."))
                        .accessibilityIdentifier("preferences.empty")
                }
            }
            if let notice = store.notice { Text(notice).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted) }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
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
                    Text("No observation dated to this day.").foregroundStyle(MorningStyle.muted)
                }
            } else {
                ObservedMorningDaySections(store: store, dayKey: day.dayKey, onLearn: onLearn)
            }
            if day.runs.isEmpty {
                Section {
                    Text("No routine saved for this day.").font(MorningTheme.Typography.heading)
                    Text("A missing run stays unknown. It isn't counted as a zero-minute morning.")
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                } header: { Text("Routine runs") }
            }
            ForEach(Array(day.runs.enumerated()), id: \.element.id) { index, run in
                Section {
                    MorningRecapView(store: store, session: run.session, showsMomentNames: false)
                    LabeledContent("Active routine time", value: MorningStyle.duration(run.activeDurationSeconds))
                    LabeledContent("Planned time", value: AppLanguage.localized("\(run.plannedDurationMinutes) min"))
                    if run.activeDurationSeconds == nil {
                        Text("Timing is incomplete or unavailable; this run is excluded from time averages.")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    }
                    ForEach(run.routine.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            MorningDottedIcon(systemName: run.completedStepIDs.contains(step.id) ? "checkmark.circle" : run.skippedStepIDs.contains(step.id) ? "forward.end.circle" : "circle").frame(width: 20, height: 20)
                                .foregroundStyle(MorningStyle.muted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.raleway(.subheadline))
                                Text(run.completedStepIDs.contains(step.id) ? String(localized: "Marked complete", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : run.skippedStepIDs.contains(step.id) ? String(localized: "Skipped", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Not completed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            }
                            Spacer()
                            Text("\(step.durationMinutes) min planned").font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }.padding(.vertical, 4)
                    }
                } header: {
                    Text(run.outcome == .completed ? String(localized: "Routine run \(index + 1) · completed", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Routine run \(index + 1) · ended early", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                } footer: {
                    Text("Saved routine version \(run.routineVersionNumber). Active time excludes pauses and doesn't measure activity in other apps.")
                }
            }
            if !day.appObservations.isEmpty {
                Section("App observations") {
                    ForEach(day.appObservations) { observation in
                        VStack(alignment: .leading, spacing: 6) {
                            LabeledContent(observation.appName, value: MorningStyle.duration(observation.observedDurationSeconds))
                            Text(observation.coverage == .completeWindow ? String(localized: "Complete for the declared observation window", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : observation.coverage == .partialWindow ? String(localized: "Partial observation window", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Coverage unknown", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        .navigationTitle(day.date.formatted(.dateTime.month(.abbreviated).day().locale(AppLanguage.locale)))
        .accessibilityIdentifier("review.dayDetail")
    }
}

/// Its own stack when presented over the app; none when pushed onto an existing one.
private struct OptionalNavigationStack<Content: View>: View {
    var enabled: Bool
    @ViewBuilder var content: Content
    var body: some View {
        if enabled { NavigationStack { content } } else { content }
    }
}
