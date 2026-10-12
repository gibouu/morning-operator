import Foundation
import Testing
@testable import MorningApple

@Suite("Explicit selected-calendar observation")
@MainActor
struct CalendarObservationServiceTests {
    private let work = CalendarChoice(id: "synthetic-work", title: "Work", sourceTitle: "Synthetic account")
    private let home = CalendarChoice(id: "synthetic-home", title: "Home", sourceTitle: "On device")

    @Test func readingRequiresFullAccessAndNeverRequestsItImplicitly() throws {
        let provider = CalendarFixtureProvider(choices: [work], authorized: false)
        let service = CalendarObservationService(provider: provider)
        #expect(throws: CalendarObservationError.notAuthorized) { try service.calendarChoices() }
        #expect(throws: CalendarObservationError.notAuthorized) {
            try service.snapshot(calendarIDs: [work.id])
        }
        #expect(provider.permissionRequests == 0)
        #expect(provider.eventReads == 0)
    }

    @Test func explicitPermissionNeedsConfiguredPurposeAndActualFullAccess() async throws {
        let provider = CalendarFixtureProvider(choices: [work], authorized: false)
        let unconfigured = CalendarObservationService(provider: provider, usageDescription: { nil })
        await #expect(throws: CalendarObservationError.missingUsageDescription) { try await unconfigured.requestAccess() }
        #expect(provider.permissionRequests == 0)
        let service = CalendarObservationService(provider: provider, usageDescription: { "Read selected calendars." })
        provider.permissionResult = true
        await #expect(throws: CalendarObservationError.notAuthorized) { try await service.requestAccess() }
        provider.authorizeOnRequest = true
        try await service.requestAccess()
        #expect(service.isAuthorized)
        #expect(provider.permissionRequests == 2)
    }

    @Test func emptyOrMissingSelectionNeverFallsBackToOtherCalendars() throws {
        let provider = CalendarFixtureProvider(choices: [work, home])
        let service = CalendarObservationService(provider: provider)
        #expect(throws: CalendarObservationError.selectionRequired) { try service.snapshot(calendarIDs: []) }
        #expect(throws: CalendarObservationError.selectedCalendarsUnavailable) {
            try service.snapshot(calendarIDs: [work.id, "removed-calendar"])
        }
        #expect(provider.eventReads == 0)
        provider.choices = [home] // A formerly selected calendar disappeared between refreshes.
        #expect(throws: CalendarObservationError.selectedCalendarsUnavailable) {
            try service.snapshot(calendarIDs: [work.id])
        }
        #expect(provider.eventReads == 0)
    }

    @Test func revocationOrDisappearanceDuringReadCannotReturnAnEmptySuccess() throws {
        let provider = CalendarFixtureProvider(choices: [work])
        let service = CalendarObservationService(provider: provider)
        provider.onRead = { provider.authorized = false }
        #expect(throws: CalendarObservationError.notAuthorized) { try service.snapshot(calendarIDs: [work.id]) }
        provider.authorized = true
        provider.onRead = { provider.choices = [] }
        #expect(throws: CalendarObservationError.selectedCalendarsUnavailable) {
            try service.snapshot(calendarIDs: [work.id])
        }
    }

    @Test func daylightSavingDaysUseLocalCalendarBoundariesAndReadCompletionTime() throws {
        let provider = CalendarFixtureProvider(choices: [work])
        let completed = instant("2026-03-29T10:00:05Z")
        let service = CalendarObservationService(provider: provider, now: { completed })
        let paris = calendar("Europe/Paris")
        let spring = try service.snapshot(for: instant("2026-03-29T10:00:00Z"), calendar: paris, calendarIDs: [work.id])
        #expect(spring.dayStart == instant("2026-03-28T23:00:00Z"))
        #expect(spring.dayEnd == instant("2026-03-29T22:00:00Z"))
        #expect(spring.dayEnd.timeIntervalSince(spring.dayStart) == 23 * 3_600)
        #expect(spring.retrievedAt == completed)
        #expect(spring.timeZoneIdentifier == "Europe/Paris")
        #expect(spring.selectedCalendars == [work])
        #expect(spring.selectedCalendarIDs == [work.id])
        #expect(spring.sourceLabels == ["Synthetic account"])
        #expect(provider.lastInterval == DateInterval(start: spring.dayStart, end: spring.dayEnd))
        #expect(provider.lastCalendarIDs == [work.id])
        let autumn = try service.snapshot(for: instant("2026-10-25T12:00:00Z"), calendar: paris, calendarIDs: [work.id])
        #expect(autumn.dayEnd.timeIntervalSince(autumn.dayStart) == 25 * 3_600)
    }

    @Test func halfOpenDayIncludesOverlapsAndPointEventsButNotAdjacentDays() throws {
        let start = instant("2026-10-10T00:00:00Z")
        let end = start.addingTimeInterval(86_400)
        let provider = CalendarFixtureProvider(choices: [work, home], events: [
            event("ends-at-start", start: start.addingTimeInterval(-3_600), end: start),
            event("starts-at-end", start: end, end: end.addingTimeInterval(3_600)),
            event("ongoing", start: start.addingTimeInterval(-3_600), end: start.addingTimeInterval(3_600)),
            event("multi-day", start: start.addingTimeInterval(-86_400), end: end.addingTimeInterval(86_400)),
            event("all-day", start: start, end: end, allDay: true),
            event("point-at-start", start: start, end: start),
            event("point-at-end", start: end, end: end),
            CalendarObservationEvent(id: "not-selected", calendarID: home.id, title: "Excluded calendar", start: start, end: end)
        ])
        let result = try CalendarObservationService(provider: provider).snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id])
        #expect(result.events.map(\.title) == ["all-day", "multi-day", "ongoing", "point-at-start"])
        #expect(result.events[1].start < result.dayStart)
        #expect(result.events[1].end > result.dayEnd)
        #expect(result.events.allSatisfy { $0.calendarID == work.id && $0.sourceTitle == work.sourceTitle })
    }

    @Test func floatingAllDayDatesProjectIntoSelectedZoneWithoutMovingTimedEvents() throws {
        let rawStart = instant("2026-03-29T07:00:00Z") // March 29 midnight in Los Angeles.
        let rawEnd = instant("2026-03-30T07:00:00Z")
        let provider = CalendarFixtureProvider(choices: [work], events: [
            CalendarObservationEvent(id: "floating", calendarID: work.id, title: "All day", start: rawStart,
                end: rawEnd, isAllDay: true, floatingTimeZoneIdentifier: "America/Los_Angeles"),
            CalendarObservationEvent(id: "timed", calendarID: work.id, title: "Timed", start: rawStart,
                end: rawStart.addingTimeInterval(600))
        ])
        let result = try CalendarObservationService(provider: provider).snapshot(
            for: instant("2026-03-29T03:00:00Z"), calendar: calendar("Asia/Tokyo"), calendarIDs: [work.id])
        #expect(result.events.count == 2)
        #expect(result.events[0].start == instant("2026-03-28T15:00:00Z"))
        #expect(result.events[0].end == instant("2026-03-29T15:00:00Z"))
        #expect(result.events[1].start == rawStart)
        #expect(result.events[1].end == rawStart.addingTimeInterval(600))
        let paris = try CalendarObservationService(provider: provider).snapshot(
            for: instant("2026-03-29T12:00:00Z"), calendar: calendar("Europe/Paris"), calendarIDs: [work.id])
        #expect(paris.events[0].start == instant("2026-03-28T23:00:00Z"))
        #expect(paris.events[0].end == instant("2026-03-29T22:00:00Z"))
        #expect(paris.events[0].end.timeIntervalSince(paris.events[0].start) == 23 * 3_600)
    }

    @Test func cancelledAndSelfDeclinedAreExcludedWithoutGuessingOtherAttendance() throws {
        let start = instant("2026-10-10T08:00:00Z")
        let end = start.addingTimeInterval(3_600)
        let provider = CalendarFixtureProvider(choices: [work], events: [
            CalendarObservationEvent(id: "cancelled", calendarID: work.id, title: "Cancelled", start: start, end: end, isCancelled: true),
            CalendarObservationEvent(id: "declined", calendarID: work.id, title: "Declined", start: start, end: end, currentUserDeclined: true),
            CalendarObservationEvent(id: "ordinary", calendarID: work.id, title: "Still included", start: start, end: end)
        ])
        let snapshot = try CalendarObservationService(provider: provider).snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id])
        #expect(snapshot.events.map(\.title) == ["Still included"])
    }

    @Test func orderingAndDeduplicationKeepRecurringOccurrencesAndCalendarCopiesDistinct() throws {
        let start = instant("2026-10-10T08:00:00Z")
        let later = start.addingTimeInterval(3_600)
        let first = event("series", start: start, end: later)
        let second = event("series", start: later, end: later.addingTimeInterval(600))
        let copy = CalendarObservationEvent(id: "series", calendarID: home.id, title: "series", start: start, end: later)
        let provider = CalendarFixtureProvider(choices: [work, home, work], events: [second, first, copy, first])
        let service = CalendarObservationService(provider: provider, now: { start })
        let original = try service.snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id, home.id])
        provider.records.reverse(); provider.choices.reverse()
        let reversed = try service.snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id, home.id])
        #expect(original == reversed)
        #expect(original.events.count == 3)
        #expect(Set(original.events.map(\.id)).count == 3)
        #expect(original.selectedCalendarIDs == [home.id, work.id])
        #expect(original.sourceLabels == ["On device", "Synthetic account"])
    }

    @Test func movedRecurringOccurrenceKeepsItsLocalIdentity() throws {
        let start = instant("2026-10-10T08:00:00Z")
        let provider = CalendarFixtureProvider(choices: [work], events: [
            CalendarObservationEvent(id: "series", calendarID: work.id, title: "Moved", start: start,
                end: start.addingTimeInterval(600), occurrenceDate: start)
        ])
        let service = CalendarObservationService(provider: provider)
        let before = try service.snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id])
        provider.records = [CalendarObservationEvent(id: "series", calendarID: work.id, title: "Moved", start: start.addingTimeInterval(600),
            end: start.addingTimeInterval(1_200), occurrenceDate: start)]
        let after = try service.snapshot(for: start, calendar: calendar("UTC"), calendarIDs: [work.id])
        #expect(before.events[0].id == after.events[0].id)
        #expect(before.events[0].start != after.events[0].start)
    }

    @Test func invalidDatesAndConflictingCalendarIDsFailWithoutInventingAnEmptyDay() throws {
        let start = instant("2026-10-10T08:00:00Z")
        let provider = CalendarFixtureProvider(choices: [work])
        let service = CalendarObservationService(provider: provider)
        #expect(throws: CalendarObservationError.invalidDay) {
            try service.snapshot(for: Date(timeIntervalSinceReferenceDate: .nan), calendarIDs: [work.id])
        }
        provider.records = [event("reversed", start: start, end: start.addingTimeInterval(-1))]
        #expect(throws: CalendarObservationError.invalidEventData) {
            try service.snapshot(for: start, calendarIDs: [work.id])
        }
        provider.choices.append(CalendarChoice(id: work.id, title: "Conflicting title", sourceTitle: "Other"))
        #expect(throws: CalendarObservationError.invalidCalendarData) { try service.calendarChoices() }
    }

    private func event(_ id: String, start: Date, end: Date, allDay: Bool = false) -> CalendarObservationEvent {
        CalendarObservationEvent(id: id, calendarID: work.id, title: id, start: start, end: end, isAllDay: allDay)
    }

    private func calendar(_ identifier: String) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: identifier)!
        return result
    }

    private func instant(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}

@MainActor
private final class CalendarFixtureProvider: CalendarObservationProviding {
    var authorized: Bool
    var choices: [CalendarChoice]
    var records: [CalendarObservationEvent]
    var permissionResult = false
    var authorizeOnRequest = false
    var permissionRequests = 0
    var eventReads = 0
    var lastInterval: DateInterval?
    var lastCalendarIDs: Set<String>?
    var onRead: (() -> Void)?
    var isAuthorized: Bool { authorized }

    init(choices: [CalendarChoice], events: [CalendarObservationEvent] = [], authorized: Bool = true) {
        self.choices = choices; self.records = events; self.authorized = authorized
    }
    func requestAccess() async throws -> Bool {
        permissionRequests += 1
        if authorizeOnRequest { authorized = true }
        return permissionResult
    }
    func calendarChoices() throws -> [CalendarChoice] { choices }
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] {
        eventReads += 1; lastInterval = interval; lastCalendarIDs = calendarIDs
        onRead?()
        return records
    }
}
