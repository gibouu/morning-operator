import Foundation
import Testing
@testable import MorningApple

@Suite("EventKit draft validation without permissions or writes")
struct ReminderDraftTests {
    @Test("Reminder alerts require a date and remain an explicit draft choice")
    func reminderAlertRequiresDate() throws {
        let draft = ReminderDraft(title: "Remember the idea")
        try draft.validate()
        #expect(!draft.notifyAtDueTime)
        #expect(throws: ReminderServiceError.alarmNeedsDate) {
            try ReminderDraft(title: "Remember the idea", notifyAtDueTime: true).validate()
        }
        try ReminderDraft(title: "Call Alex", dueDate: Date(timeIntervalSince1970: 1_800_000_000), notifyAtDueTime: true).validate()
    }

    @Test("Malformed drafts fail before EventKit interaction")
    func malformedDrafts() {
        #expect(throws: ReminderServiceError.invalidTitle) { try ReminderDraft(title: " \n ").validate() }
        #expect(throws: ReminderServiceError.invalidTitle) { try ReminderDraft(title: String(repeating: "x", count: 301)).validate() }
        #expect(throws: ReminderServiceError.notesTooLong) {
            try ReminderDraft(title: "Idea", notes: String(repeating: "x", count: 10_001)).validate()
        }
        #expect(throws: ReminderServiceError.invalidTimeZone) {
            try ReminderDraft(title: "Idea", timeZoneIdentifier: "Not/AZone").validate()
        }
        #expect(throws: ReminderServiceError.invalidDate) {
            try ReminderDraft(title: "Idea", dueDate: Date(timeIntervalSinceReferenceDate: .infinity)).validate()
        }
    }

    @Test("Calendar drafts require a positive, bounded interval")
    func eventInterval() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        try CalendarEventDraft(title: "Coffee", startDate: start, endDate: start.addingTimeInterval(1_800)).validate()
        for end in [start, start.addingTimeInterval(-1), start.addingTimeInterval(32 * 86_400)] {
            #expect(throws: ReminderServiceError.invalidDate) {
                try CalendarEventDraft(title: "Coffee", startDate: start, endDate: end).validate()
            }
        }
    }

    @Test("Reminder components use Gregorian dates and retain the chosen time zone")
    func dueDateComponentsRoundTrip() throws {
        let timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let components = EventKitDraftValidation.reminderDateComponents(date, timeZone: timeZone)
        #expect(components.calendar?.identifier == .gregorian)
        #expect(components.timeZone == timeZone)
        #expect(components.date == date)
        var withoutCalendar = components
        withoutCalendar.calendar = nil
        #expect(EventKitDraftValidation.reminderDueDate(withoutCalendar) == date)
    }
}
