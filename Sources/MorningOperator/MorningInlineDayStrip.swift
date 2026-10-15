import SwiftUI
import MorningCore

/// Home's read-only date browser. The only writes are to these two presentation
/// bindings; this component has no store, runner, routine editor or navigation API.
struct MorningInlineDayStrip: View {
    @Binding var selectedDate: Date
    @Binding var isExpanded: Bool
    let history: MorningHistory
    var observations: [MorningInlineDayEvidence] = []
    /// Pin only for previews. Ordinary Home leaves this nil so midnight refreshes.
    var referenceDate: Date? = nil

    @Environment(\.calendar) private var environmentCalendar
    @Environment(\.timeZone) private var timeZone
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var dayWidth = 46
    @SwiftUI.State private var firstVisibleDay: Date?
    @SwiftUI.State private var dateSelectionUnavailable = false

    private var calendar: Calendar {
        var value = environmentCalendar
        value.timeZone = timeZone
        return value
    }

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(now: referenceDate ?? context.date)
        }
        // Override the old handwritten/serif type inherited by the current shell.
        .font(.system(.body))
        .buttonStyle(.plain)
        .onChange(of: timeZone) { oldZone, _ in
            var previousCalendar = environmentCalendar
            previousCalendar.timeZone = oldZone
            let now = referenceDate ?? .now
            do {
                let days = try MorningInlineDayCalendar(today: now, calendar: calendar)
                selectedDate = try days.rebasedSelection(selectedDate, from: previousCalendar, at: now)
                dateSelectionUnavailable = false
            } catch {
                dateSelectionUnavailable = true
            }
            firstVisibleDay = nil
        }
        .onChange(of: environmentCalendar) { _, _ in firstVisibleDay = nil }
    }

    @ViewBuilder private func content(now: Date) -> some View {
        if !dateSelectionUnavailable,
           let days = try? MorningInlineDayCalendar(today: now, calendar: calendar),
           let snapshot = try? MorningInlineDaySnapshot(selectedDate: selectedDate, today: now,
                                                        calendar: calendar, history: history,
                                                        observations: observations) {
            VStack(alignment: .leading, spacing: 12) {
                dateButton(snapshot)
                if isExpanded {
                    expandedDays(days, snapshot: snapshot, now: now)
                        .transition(reduceMotion ? .identity : .opacity)
                }
            }
            .onAppear { selectedDate = snapshot.date }
            .onChange(of: days.today) { oldToday, newToday in
                // Follow today at midnight only when the person was viewing today.
                if calendar.isDate(selectedDate, inSameDayAs: oldToday) {
                    selectedDate = newToday
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("This day could not be displayed in the current time zone.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Today") {
                    selectedDate = calendar.startOfDay(for: now)
                    dateSelectionUnavailable = false
                }.frame(minHeight: 44)
            }
        }
    }

    private func dateButton(_ snapshot: MorningInlineDaySnapshot) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Text(formatted(snapshot.date, .dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.system(.subheadline, weight: .medium))
                    .multilineTextAlignment(.leading)
                Image(systemName: "chevron.down")
                    .font(.system(.caption2, weight: .semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(formatted(snapshot.date, .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityHint(isExpanded ? Text("Hides the day strip.") : Text("Shows the day strip here on Home."))
        .accessibilityIdentifier("morning.date")
    }

    private func expandedDays(_ days: MorningInlineDayCalendar,
                              snapshot: MorningInlineDaySnapshot, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                dayArrow("chevron.left", label: "Previous day") {
                    move(-1, days: days)
                }
                Spacer(minLength: 0)
                Button("Today") { select(days.today) }
                    .font(.system(.subheadline, weight: .medium))
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(snapshot.isToday)
                    .accessibilityIdentifier("morning.days.today")
                Spacer(minLength: 0)
                dayArrow("chevron.right", label: "Next day") {
                    move(1, days: days)
                }
                .disabled(snapshot.isToday)
            }
            dayScroller(days, selected: snapshot.date, now: now)
            evidence(snapshot)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("morning.days")
    }

    private func dayScroller(_ days: MorningInlineDayCalendar, selected: Date, now: Date) -> some View {
        let initialStart = (try? days.day(offset: -20, from: selected)) ?? selected
        let start = min(firstVisibleDay ?? initialStart, initialStart)
        let count = max(0, calendar.dateComponents([.day], from: start, to: days.today).day ?? 0)
        let dates = (0...count).compactMap { try? days.day(offset: $0, from: start) }
        return ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 4) {
                    ForEach(dates, id: \.self) { date in
                        if let day = try? MorningInlineDaySnapshot(selectedDate: date, today: now,
                                                                  calendar: calendar, history: history,
                                                                  observations: observations) {
                            dayButton(day, selected: calendar.isDate(date, inSameDayAs: selected))
                                .id(date)
                                .onScrollVisibilityChange { visible in
                                    if visible && date == start {
                                        firstVisibleDay = try? days.day(offset: -21, from: start)
                                    }
                                }
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .defaultScrollAnchor(.trailing)
            .onAppear { proxy.scrollTo(selected, anchor: .trailing) }
            .onChange(of: selected) { _, date in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    proxy.scrollTo(date, anchor: .center)
                }
            }
            .accessibilityIdentifier("morning.days.strip")
        }
    }

    private func dayButton(_ day: MorningInlineDaySnapshot, selected: Bool) -> some View {
        Button { select(day.date) } label: {
            VStack(spacing: 6) {
                Text(formatted(day.date, .dateTime.weekday(.abbreviated)))
                    .font(.system(.caption2, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(formatted(day.date, .dateTime.day()))
                    .font(.system(.body, weight: selected ? .semibold : .regular))
                    .monospacedDigit()
                Image(systemName: stateSymbol(day.state))
                    .font(.system(size: 8, weight: .semibold))
                    .frame(height: 10)
                    .opacity(day.state == .noSavedEvidence ? 0 : 1)
            }
            .frame(minWidth: max(44, dayWidth), minHeight: 76)
            .padding(.vertical, 6)
            .background(selected ? Color.primary.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(.primary.opacity(0.3), lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .accessibilityLabel(formatted(day.date, .dateTime.weekday(.wide).month(.wide).day().year()))
        .accessibilityValue(Text(stateTitle(day.state)))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Shows saved evidence. Does not start the routine.")
        .accessibilityIdentifier("morning.days.\(day.dayKey)")
    }

    private func evidence(_ day: MorningInlineDaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(day.state == .noSavedEvidence ? "No saved personal activity" : "Saved on this day")
                .font(.system(.subheadline, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            if day.state == .noSavedEvidence {
                Text("No personal run or confirmed observation is saved for this day.")
                    .font(.system(.subheadline)).foregroundStyle(.secondary)
                Text("Samples and unconfirmed sources are not included.")
                    .font(.system(.caption)).foregroundStyle(.secondary)
            } else {
                ForEach(day.completedRuns + day.stoppedRuns) { run in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(run.outcome == .completed ? "Routine finished" : "Routine stopped",
                              systemImage: run.outcome == .completed ? "checkmark.circle" : "pause.circle")
                            .font(.system(.subheadline))
                        Text("\(run.completedStepCount) of \(run.totalStepCount) moments completed · \(run.skippedStepCount) skipped")
                            .font(.system(.caption)).foregroundStyle(.secondary)
                    }
                }
                if !day.observations.isEmpty {
                    Label("\(day.observations.count) saved observations", systemImage: "doc.text")
                        .font(.system(.subheadline))
                }
                if !day.appObservations.isEmpty {
                    Label("\(day.appObservations.count) app observations", systemImage: "app")
                        .font(.system(.subheadline))
                }
            }
            if !day.sourceTimeZoneIdentifiers.isEmpty {
                Text("Saved local day · \(day.sourceTimeZoneIdentifiers.joined(separator: ", "))")
                    .font(.system(.caption)).foregroundStyle(.secondary)
            }
            if day.undatedObservationCount > 0 {
                Text("\(day.undatedObservationCount) observations have no saved day and are not shown here.")
                    .font(.system(.caption)).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("morning.days.evidence")
    }

    private func dayArrow(_ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(.subheadline, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.accessibilityLabel(Text(label))
    }

    private func select(_ date: Date) {
        // No animation of evidence itself: its changing height remains readable.
        selectedDate = date
    }

    private func move(_ offset: Int, days: MorningInlineDayCalendar) {
        if let next = try? days.day(offset: offset, from: selectedDate) { select(next) }
    }

    private func formatted(_ date: Date, _ format: Date.FormatStyle) -> String {
        var resolved = format
        resolved.calendar = calendar
        resolved.timeZone = timeZone
        resolved.locale = locale
        return date.formatted(resolved)
    }

    private func stateTitle(_ state: MorningInlineDayState) -> LocalizedStringKey {
        switch state {
        case .completed: "Routine finished"
        case .partial: "Routine stopped"
        case .evidenceOnly: "Saved observations"
        case .noSavedEvidence: "No saved personal activity"
        }
    }

    private func stateSymbol(_ state: MorningInlineDayState) -> String {
        switch state {
        case .completed: "checkmark"
        case .partial: "minus"
        case .evidenceOnly: "circle.fill"
        case .noSavedEvidence: "circle"
        }
    }
}

#if DEBUG
#Preview("Inline days · empty history") {
    InlineDayPreview()
}

private struct InlineDayPreview: View {
    @SwiftUI.State private var selectedDate = Date.now
    @SwiftUI.State private var expanded = true
    var body: some View {
        ScrollView {
            MorningInlineDayStrip(selectedDate: $selectedDate, isExpanded: $expanded,
                                  history: MorningHistory())
                .padding(24)
        }
        .frame(maxWidth: 440)
    }
}
#endif
