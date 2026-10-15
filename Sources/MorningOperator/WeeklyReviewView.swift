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
        return "\(start.formatted(.dateTime.month(.abbreviated).day())) – \(periodEnd.formatted(.dateTime.month(.abbreviated).day().year()))"
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
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
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
                    Text(periodTitle).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
                    MorningDottedIcon(systemName: showingDays ? "chevron.up" : "chevron.down").frame(width: 16, height: 16).font(.caption2.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44)
            }
            .accessibilityLabel(showingDays ? "\(periodTitle), hide days" : "\(periodTitle), show days")
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
            }.font(.subheadline).tint(MorningStyle.accent)
        }
    }

    private func weekSummary(_ week: SevenDaySummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let average = week.averageActiveDurationSeconds {
                Text("Average routine time").font(.subheadline).foregroundStyle(MorningStyle.muted)
                Text(MorningStyle.duration(average))
                    .scaledFont(44, relativeTo: .largeTitle, weight: .regular, design: .default)
                    .accessibilityIdentifier("review.average")
                Text("Across \(week.timedRunCount) timed runs")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
                Text("Time in your routine, excluding pauses. Other app use isn't measured here.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            } else {
                Text(week.runCount == 0 ? (hasObservationsInPeriod ? "A morning, remembered." : "Your mornings will find their shape.") : "A morning saved. Time still unknown.")
                    .font(.system(.title2, design: .default, weight: .medium))
                Text(week.runCount == 0
                     ? (hasObservationsInPeriod
                        ? "Explore the screens you saved below. Routine time begins with a completed run."
                        : "Finish a morning to begin your history. Days without a saved run stay empty.")
                     : "\(week.runCount) saved runs have no complete timing. They stay out of the average.")
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
            }
            if week.runCount > week.timedRunCount, week.timedRunCount > 0 {
                Text("Runs with incomplete timing are excluded from this average.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }
            if hasSampleRunsInPeriod {
                Label { Text("Sample runs stay out of your personal averages.") } icon: { MorningDottedIcon(systemName: "sparkles").frame(width: 18, height: 18) }
                    .font(.caption).foregroundStyle(MorningStyle.muted)
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
                            Text(day.date.formatted(.dateTime.weekday(.wide))).font(.subheadline.weight(.medium))
                            Text(day.date.formatted(.dateTime.month(.abbreviated).day())).font(.caption).foregroundStyle(MorningStyle.muted)
                        }
                        Spacer()
                        Text(daySummaryText(day))
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                        MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).font(.caption2).foregroundStyle(.tertiary)
                    }.padding(.vertical, 13).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("review.day.\(day.dayKey)")
                if day.id != week.days.first?.id { Divider() }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("review.days")
    }

    private func daySummaryText(_ day: MorningDaySummary) -> String {
        let observations = store.observationArchive.entries.filter { $0.observedDate?.dayKey == day.dayKey }.count
        let observationSummary = String(localized: "\(observations) observations")
        guard day.runCount > 0 else {
            if observations > 0 { return observationSummary }
            return day.hasEvidence ? String(localized: "App observations") : String(localized: "Nothing saved")
        }
        if observations > 0 { return String(localized: "\(day.runCount) runs · \(observations) observations") }
        let time = day.timedRunCount == day.runCount
            ? MorningStyle.duration(day.totalActiveDurationSeconds) : String(localized: "incomplete timing")
        return String(localized: "\(day.runCount) runs · \(time)")
    }

    private var observationArchiveLinks: some View {
        VStack(spacing: 0) {
            let undatedCount = store.observationArchive.entries.filter { $0.observedDate == nil }.count
            if undatedCount > 0 {
                NavigationLink {
                    ObservationHistoryView(store: store, onlyUndated: true, onLearn: onLearn)
                } label: {
                    actionRow(String(localized: "Date needed"), detail: String(localized: "\(undatedCount) observations need an observed day"), symbol: "calendar.badge.questionmark")
                }.accessibilityIdentifier("review.undatedObservations")
                Divider()
            }
            NavigationLink {
                ObservationHistoryView(store: store, onLearn: onLearn)
            } label: {
                actionRow(String(localized: "Saved observations"), detail: store.observationArchive.entries.isEmpty
                          ? String(localized: "Original evidence and your corrections") : String(localized: "\(store.observationArchive.entries.count) saved · separate from routine runs"),
                          symbol: "doc.text.image")
            }.accessibilityIdentifier("review.observations")
        }.buttonStyle(.plain)
    }

    private var reviewActions: some View {
        VStack(spacing: 0) {
            Button { showingRoutineEditor = true } label: {
                actionRow(String(localized: "Your routine"), detail: routineDetail, symbol: "list.bullet")
            }.accessibilityIdentifier("review.routine")
            Divider()
            Button(action: onLearn) {
                actionRow(store.hasImportedObservation ? String(localized: "Review your observation") : String(localized: "Learn from a morning"),
                          detail: store.hasPendingRecording ? String(localized: "A saved recording needs attention") : String(localized: "Record, describe or refine"), symbol: "sparkles")
            }.accessibilityIdentifier("review.learn")
            Divider()
            NavigationLink {
                CapturesView(store: store).navigationTitle("Saved thoughts").background(MorningStyle.background)
            } label: {
                actionRow(String(localized: "Saved thoughts"), detail: store.captures.isEmpty ? String(localized: "A place for what comes to mind") : String(localized: "\(store.captures.count) saved"), symbol: "text.bubble")
            }.accessibilityIdentifier("review.thoughts")
            Divider()
            NavigationLink {
                ScrollView { AppActivityView().padding(24).frame(maxWidth: 680).frame(maxWidth: .infinity) }
                    .background(MorningStyle.background).navigationTitle("App activity")
            } label: {
                actionRow(String(localized: "App activity"), detail: String(localized: "Today's connected app entries"), symbol: "arrow.triangle.2.circlepath")
            }.accessibilityIdentifier("review.appActivity")
            Divider()
            Button(action: onSettings) {
                actionRow(String(localized: "Settings & connections"), detail: String(localized: "Voice, calendar and preferences"), symbol: "slider.horizontal.3")
            }.accessibilityIdentifier("navigation.setup")
        }.buttonStyle(.plain)
    }

    private var routineDetail: String {
        guard let routine = store.routine else { return String(localized: "Build a routine that feels like you") }
        return routine.isApproved ? String(localized: "\(routine.steps.count) moments · approved") : String(localized: "\(routine.steps.count) moments · ready for your review")
    }

    private func actionRow(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            MorningDottedIcon(systemName: symbol).frame(width: 24, height: 24).font(.body).foregroundStyle(MorningStyle.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(MorningStyle.muted) }
            }
            Spacer(minLength: 8)
            MorningDottedIcon(systemName: "chevron.right").frame(width: 16, height: 16).font(.caption2).foregroundStyle(.tertiary)
        }.padding(.vertical, 16).contentShape(Rectangle()).foregroundStyle(.primary)
    }

    private func observedApp(_ app: AppUsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Text(app.appName); Spacer(); Text(MorningStyle.duration(app.averageObservedDurationSeconds)) }
            Text("Average across \(app.daysWithDurationEvidence) days with time evidence. \(app.partialWindowDayCount) partial windows; \(app.unknownCoverageDayCount) with unknown coverage.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
        }.padding(.top, 12)
    }

    private func changeWeek(by offset: Int) {
        withAnimation(reduceMotion ? nil : .snappy) {
            weekOffset = min(0, weekOffset + offset)
            showingRoutineTiming = false
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
                    .font(.subheadline).foregroundStyle(MorningStyle.muted)
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
                if store.routinePreferences.entries.isEmpty {
                    ContentUnavailableView("No saved choices", systemImage: "heart",
                        description: Text("Future suggestions can vary. Keep a moment or its duration when editing your routine."))
                        .accessibilityIdentifier("preferences.empty")
                }
            }
            if let notice = store.notice { Text(notice).font(.caption).foregroundStyle(MorningStyle.muted) }
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
                    Text("No observation dated to this day.").foregroundStyle(MorningStyle.muted)
                }
            } else {
                ObservedMorningDaySections(store: store, dayKey: day.dayKey, onLearn: onLearn)
            }
            if day.runs.isEmpty {
                Section {
                    Text("No routine saved for this day.").font(MorningTheme.Typography.heading)
                    Text("A missing run stays unknown. It isn't counted as a zero-minute morning.")
                        .font(.subheadline).foregroundStyle(MorningStyle.muted)
                } header: { Text("Routine runs") }
            }
            ForEach(Array(day.runs.enumerated()), id: \.element.id) { index, run in
                Section {
                    MorningRecapView(store: store, session: run.session, showsMomentNames: false)
                    LabeledContent("Active routine time", value: MorningStyle.duration(run.activeDurationSeconds))
                    LabeledContent("Planned time", value: String(localized: "\(run.plannedDurationMinutes) min"))
                    if run.activeDurationSeconds == nil {
                        Text("Timing is incomplete or unavailable; this run is excluded from time averages.")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                    ForEach(run.routine.steps) { step in
                        HStack(alignment: .top, spacing: 12) {
                            MorningDottedIcon(systemName: run.completedStepIDs.contains(step.id) ? "checkmark.circle" : run.skippedStepIDs.contains(step.id) ? "forward.end.circle" : "circle").frame(width: 20, height: 20)
                                .foregroundStyle(MorningStyle.muted)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(step.title).font(.subheadline)
                                Text(run.completedStepIDs.contains(step.id) ? "Marked complete" : run.skippedStepIDs.contains(step.id) ? "Skipped" : "Not completed")
                                    .font(.caption).foregroundStyle(MorningStyle.muted)
                            }
                            Spacer()
                            Text("\(step.durationMinutes) min planned").font(.caption).foregroundStyle(MorningStyle.muted)
                        }.padding(.vertical, 4)
                    }
                } header: {
                    Text(run.outcome == .completed ? "Routine run \(index + 1) · completed" : "Routine run \(index + 1) · ended early")
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
                                .font(.caption).foregroundStyle(MorningStyle.muted)
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
