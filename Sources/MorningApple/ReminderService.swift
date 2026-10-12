import EventKit
import Foundation

public struct ReminderDraft: Sendable, Equatable {
    public var title: String
    public var notes: String
    public var dueDate: Date?
    public var timeZoneIdentifier: String
    public var notifyAtDueTime: Bool

    public init(title: String, notes: String = "", dueDate: Date? = nil,
                timeZoneIdentifier: String = TimeZone.current.identifier, notifyAtDueTime: Bool = false) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.timeZoneIdentifier = timeZoneIdentifier
        self.notifyAtDueTime = notifyAtDueTime
    }

    public func validate() throws {
        try EventKitDraftValidation.validate(title: title, notes: notes, timeZoneIdentifier: timeZoneIdentifier)
        if let dueDate, !dueDate.timeIntervalSinceReferenceDate.isFinite { throw ReminderServiceError.invalidDate }
        if notifyAtDueTime && dueDate == nil { throw ReminderServiceError.alarmNeedsDate }
    }
}

/// A single timed event, with no attendees, invitations, recurrence, or implicit alerts.
public struct CalendarEventDraft: Sendable, Equatable {
    public var title: String
    public var notes: String
    public var startDate: Date
    public var endDate: Date
    public var timeZoneIdentifier: String

    public init(title: String, notes: String = "", startDate: Date, endDate: Date,
                timeZoneIdentifier: String = TimeZone.current.identifier) {
        self.title = title
        self.notes = notes
        self.startDate = startDate
        self.endDate = endDate
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public func validate() throws {
        try EventKitDraftValidation.validate(title: title, notes: notes, timeZoneIdentifier: timeZoneIdentifier)
        guard startDate.timeIntervalSinceReferenceDate.isFinite, endDate.timeIntervalSinceReferenceDate.isFinite,
              endDate > startDate, endDate.timeIntervalSince(startDate) <= 31 * 86_400
        else { throw ReminderServiceError.invalidDate }
    }
}

public enum EventKitAccess: String, Sendable, Equatable {
    case notDetermined, restricted, denied, writeOnly, fullAccess, unknown
}

public struct ReminderSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let notes: String
    public let dueDate: Date?
    public let listTitle: String
}

public struct EventKitWriteReceipt: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let destination: CaptureDestination
}

public enum ReminderServiceError: LocalizedError, Sendable, Equatable {
    case remindersNotAuthorized, calendarNotAuthorized, missingUsageDescription(String)
    case noWritableReminderList, noWritableCalendar, invalidTitle, notesTooLong, invalidDate
    case invalidTimeZone, alarmNeedsDate, invalidQuery, fetchFailed

    public var errorDescription: String? {
        switch self {
        case .remindersNotAuthorized: "Reminders access is not authorized. Connect Reminders before reading or saving."
        case .calendarNotAuthorized: "Calendar writing is not authorized. Connect Calendar before saving."
        case .missingUsageDescription(let key): "This app build is missing \(key). Use a configured app build before requesting access."
        case .noWritableReminderList: "No writable default Reminders list is available. Set up a list in Reminders first."
        case .noWritableCalendar: "No writable default Calendar is available. Set up a calendar first."
        case .invalidTitle: "Enter a title between 1 and 300 characters."
        case .notesTooLong: "Keep the notes within 10,000 characters."
        case .invalidDate: "Choose valid dates with an event end after its start, lasting at most 31 days."
        case .invalidTimeZone: "Choose a valid time zone."
        case .alarmNeedsDate: "A reminder alert needs a due date and time."
        case .invalidQuery: "Choose a reminder date range of at most 90 days and a result limit from 1 to 200."
        case .fetchFailed: "Reminders could not be read. Access may have changed. Try again after checking permission."
        }
    }
}

enum EventKitDraftValidation {
    static func validate(title: String, notes: String, timeZoneIdentifier: String) throws {
        guard (1...300).contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) else {
            throw ReminderServiceError.invalidTitle
        }
        guard notes.count <= 10_000 else { throw ReminderServiceError.notesTooLong }
        guard TimeZone(identifier: timeZoneIdentifier) != nil else { throw ReminderServiceError.invalidTimeZone }
    }

    /// EventKit requires Gregorian due-date components, regardless of the user's display calendar.
    static func reminderDateComponents(_ date: Date, timeZone: TimeZone) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = calendar
        components.timeZone = timeZone
        return components
    }

    static func reminderDueDate(_ components: DateComponents) -> Date? {
        var calendar = components.calendar ?? Calendar(identifier: .gregorian)
        if let timeZone = components.timeZone { calendar.timeZone = timeZone }
        return calendar.date(from: components)
    }
}

/// OS permissions and effects are explicit operations. Constructing this service or parsing a
/// capture never prompts or saves. The caller must review an editable draft before calling create.
@MainActor
public final class ReminderService {
    private let store = EKEventStore()
    public init() {}

    public var reminderAuthorization: EventKitAccess { Self.access(for: .reminder) }
    public var calendarAuthorization: EventKitAccess { Self.access(for: .event) }
    public var hasReminderAccess: Bool { reminderAuthorization == .fullAccess }
    public var hasCalendarWriteAccess: Bool { calendarAuthorization == .fullAccess || calendarAuthorization == .writeOnly }

    public func requestReminderAccess() async throws {
        if hasReminderAccess { return }
        try requireUsageDescription("NSRemindersFullAccessUsageDescription")
        guard try await store.requestFullAccessToReminders() else { throw ReminderServiceError.remindersNotAuthorized }
    }

    /// Requests the narrower write-only permission. Existing full access remains sufficient.
    public func requestCalendarWriteAccess() async throws {
        if hasCalendarWriteAccess { return }
        try requireUsageDescription("NSCalendarsWriteOnlyAccessUsageDescription")
        guard try await store.requestWriteOnlyAccessToEvents() else { throw ReminderServiceError.calendarNotAuthorized }
    }

    /// Reads incomplete reminders due in a bounded interval. Undated and completed reminders
    /// are excluded. This is a local-store snapshot, not a guarantee of remote account sync.
    public func fetchUpcomingReminders(from start: Date = Date(), through end: Date? = nil,
                                       limit: Int = 100) async throws -> [ReminderSummary] {
        guard hasReminderAccess else { throw ReminderServiceError.remindersNotAuthorized }
        let end = end ?? start.addingTimeInterval(7 * 86_400)
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              end > start, end.timeIntervalSince(start) <= 90 * 86_400, (1...200).contains(limit)
        else { throw ReminderServiceError.invalidQuery }
        try Task.checkCancellation()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        let snapshots: [ReminderSummary] = try await withCheckedThrowingContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                guard let reminders else {
                    continuation.resume(throwing: ReminderServiceError.fetchFailed)
                    return
                }
                // Map EventKit objects inside their callback; only immutable Sendable values cross actors.
                let values = reminders.compactMap { reminder -> ReminderSummary? in
                    guard !reminder.isCompleted, let components = reminder.dueDateComponents,
                          let due = EventKitDraftValidation.reminderDueDate(components),
                          due >= start, due <= end else { return nil }
                    return ReminderSummary(id: reminder.calendarItemIdentifier, title: reminder.title ?? "Untitled reminder",
                        notes: reminder.notes ?? "", dueDate: due, listTitle: reminder.calendar.title)
                }.sorted {
                    if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                    return $0.id < $1.id
                }
                continuation.resume(returning: Array(values.prefix(limit)))
            }
        }
        try Task.checkCancellation()
        guard hasReminderAccess else { throw ReminderServiceError.remindersNotAuthorized }
        return snapshots
    }

    @discardableResult
    public func createReminder(from draft: ReminderDraft) throws -> EventKitWriteReceipt {
        try draft.validate()
        guard hasReminderAccess else { throw ReminderServiceError.remindersNotAuthorized }
        guard let list = store.defaultCalendarForNewReminders(), list.allowsContentModifications else {
            throw ReminderServiceError.noWritableReminderList
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes.isEmpty ? nil : draft.notes
        if let due = draft.dueDate, let timeZone = TimeZone(identifier: draft.timeZoneIdentifier) {
            reminder.dueDateComponents = EventKitDraftValidation.reminderDateComponents(due, timeZone: timeZone)
            if draft.notifyAtDueTime { reminder.addAlarm(EKAlarm(absoluteDate: due)) }
        }
        try store.save(reminder, commit: true)
        return EventKitWriteReceipt(id: reminder.calendarItemIdentifier, title: reminder.title, destination: .reminder)
    }

    @discardableResult
    public func createCalendarEvent(from draft: CalendarEventDraft) throws -> EventKitWriteReceipt {
        try draft.validate()
        guard hasCalendarWriteAccess else { throw ReminderServiceError.calendarNotAuthorized }
        guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw ReminderServiceError.noWritableCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = draft.notes.isEmpty ? nil : draft.notes
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.timeZone = TimeZone(identifier: draft.timeZoneIdentifier)
        event.isAllDay = false
        try store.save(event, span: .thisEvent, commit: true)
        // With write-only access, the identifier is a receipt, not permission to read the event.
        return EventKitWriteReceipt(id: event.calendarItemIdentifier, title: event.title, destination: .calendar)
    }

    private func requireUsageDescription(_ key: String) throws {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw ReminderServiceError.missingUsageDescription(key) }
    }

    private static func access(for entity: EKEntityType) -> EventKitAccess {
        switch EKEventStore.authorizationStatus(for: entity) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .writeOnly: .writeOnly
        case .fullAccess: .fullAccess
        @unknown default: .unknown
        }
    }
}
