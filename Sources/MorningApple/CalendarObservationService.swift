import MorningCore
import EventKit
import Foundation

public struct CalendarChoice: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let sourceTitle: String

    public init(id: String, title: String, sourceTitle: String) {
        self.id = id; self.title = title; self.sourceTitle = sourceTitle
    }
}

public struct CalendarEventSummary: Sendable, Equatable, Identifiable {
    /// A local calendar/event/occurrence identity, not a permanent server identifier.
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let calendarTitle: String
    public let calendarID: String
    public let sourceTitle: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool,
                calendarTitle: String, calendarID: String = "", sourceTitle: String = "") {
        self.id = id; self.title = title; self.start = start; self.end = end
        self.isAllDay = isAllDay; self.calendarTitle = calendarTitle
        self.calendarID = calendarID; self.sourceTitle = sourceTitle
    }
}

public struct CalendarSnapshot: Sendable, Equatable {
    /// Completion time of a local EventKit read; not the server's last synchronization time.
    public let retrievedAt: Date
    public let dayStart: Date
    public let dayEnd: Date
    public let events: [CalendarEventSummary]
    public let timeZoneIdentifier: String
    public let selectedCalendars: [CalendarChoice]
    /// In-memory EventKit change generation at this read; never a server sync token.
    public let changeRevision: UInt64
    public var selectedCalendarIDs: [String] { selectedCalendars.map(\.id) }
    public var sourceLabels: [String] { Array(Set(selectedCalendars.map(\.sourceTitle))).sorted() }

    public init(retrievedAt: Date, dayStart: Date, dayEnd: Date, events: [CalendarEventSummary],
                timeZoneIdentifier: String = TimeZone.current.identifier,
                selectedCalendars: [CalendarChoice] = [], changeRevision: UInt64 = 0) {
        self.retrievedAt = retrievedAt; self.dayStart = dayStart; self.dayEnd = dayEnd
        self.events = events; self.timeZoneIdentifier = timeZoneIdentifier
        self.selectedCalendars = selectedCalendars
        self.changeRevision = changeRevision
    }
}

/// Value boundary around native events, with no EventKit objects, attendees or write operations.
public struct CalendarObservationEvent: Sendable, Equatable {
    public let id: String
    public let calendarID: String
    public let title: String
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let occurrenceDate: Date?
    public let isCancelled: Bool
    public let currentUserDeclined: Bool
    /// EventKit represents floating dates in its default zone. Nil means dates are already projected.
    public let floatingTimeZoneIdentifier: String?

    public init(id: String, calendarID: String, title: String, start: Date, end: Date,
                isAllDay: Bool = false, occurrenceDate: Date? = nil, isCancelled: Bool = false,
                currentUserDeclined: Bool = false, floatingTimeZoneIdentifier: String? = nil) {
        self.id = id; self.calendarID = calendarID; self.title = title
        self.start = start; self.end = end; self.isAllDay = isAllDay
        self.occurrenceDate = occurrenceDate; self.isCancelled = isCancelled
        self.currentUserDeclined = currentUserDeclined
        self.floatingTimeZoneIdentifier = floatingTimeZoneIdentifier
    }
}

@MainActor
public protocol CalendarObservationProviding {
    var isAuthorized: Bool { get }
    /// Advances when the provider knows its local calendar data changed.
    var changeRevision: UInt64 { get }
    func requestAccess() async throws -> Bool
    func calendarChoices() throws -> [CalendarChoice]
    /// May return extra candidates. The service enforces the exact requested day and selection.
    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent]
}

public extension CalendarObservationProviding {
    /// Providers without a change source retain time-based freshness checks.
    var changeRevision: UInt64 { 0 }
}

public enum CalendarObservationError: LocalizedError, Sendable, Equatable {
    case notAuthorized
    case missingUsageDescription
    case invalidDay
    case selectionRequired
    case selectedCalendarsUnavailable
    case invalidCalendarData
    case invalidEventData
    case changedDuringRead

    public var errorDescription: String? {
        switch self {
        case .notAuthorized:
            AppLanguage.localized("Calendar reading is not authorized. You can continue without a calendar snapshot.", bundle: .module)
        case .missingUsageDescription:
            AppLanguage.localized("This build has no calendar permission description. Use a configured app build before enabling calendar access.", bundle: .module)
        case .invalidDay:
            AppLanguage.localized("The selected calendar day could not be resolved.", bundle: .module)
        case .selectionRequired:
            AppLanguage.localized("Choose at least one calendar before preparing a calendar briefing.", bundle: .module)
        case .selectedCalendarsUnavailable:
            AppLanguage.localized("A selected calendar is no longer available. Review your calendar selection before refreshing.", bundle: .module)
        case .invalidCalendarData:
            AppLanguage.localized("The available calendar list could not be read reliably. Please refresh it.", bundle: .module)
        case .invalidEventData:
            AppLanguage.localized("The selected calendar returned an event that could not be read reliably. Please refresh it.", bundle: .module)
        case .changedDuringRead:
            AppLanguage.localized("Calendar changed while it was being read. Refresh the briefing to use the current schedule.", bundle: .module)
        }
    }
}

/// Read-only full-access EventKit observation. Selection is checked afresh on every read.
@MainActor
public final class CalendarObservationService {
    private let provider: any CalendarObservationProviding
    private let now: @Sendable () -> Date
    private let usageDescription: @Sendable () -> String?

    public convenience init() {
        self.init(provider: EventKitCalendarObservationProvider())
    }

    public init(provider: any CalendarObservationProviding, now: @escaping @Sendable () -> Date = { Date() },
                usageDescription: @escaping @Sendable () -> String? = {
                    Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String
                }) {
        self.provider = provider; self.now = now; self.usageDescription = usageDescription
    }

    public var isAuthorized: Bool { provider.isAuthorized }
    public var changeRevision: UInt64 { provider.changeRevision }

    /// Call only for an explicit Connect Calendar action. Listing and snapshotting never prompt.
    public func requestAccess() async throws {
        if isAuthorized { return }
        guard let description = usageDescription(),
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw CalendarObservationError.missingUsageDescription }
        guard try await provider.requestAccess(), isAuthorized else { throw CalendarObservationError.notAuthorized }
    }

    public func calendarChoices() throws -> [CalendarChoice] {
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        let choices = try provider.calendarChoices()
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        var byID: [String: CalendarChoice] = [:]
        for choice in choices {
            guard !choice.id.isEmpty, byID[choice.id] == nil || byID[choice.id] == choice else {
                throw CalendarObservationError.invalidCalendarData
            }
            byID[choice.id] = choice
        }
        return byID.values.sorted {
            if $0.title != $1.title { return $0.title < $1.title }
            if $0.sourceTitle != $1.sourceTitle { return $0.sourceTitle < $1.sourceTitle }
            return $0.id < $1.id
        }
    }

    /// Kept for source compatibility only. A read must never broaden an absent selection to all calendars.
    @available(*, deprecated, message: "Pass the explicitly selected calendarIDs.")
    public func snapshot(for day: Date = Date(), calendar: Calendar = .current) throws -> CalendarSnapshot {
        throw CalendarObservationError.selectionRequired
    }

    public func snapshot(for day: Date = Date(), calendar: Calendar = .current,
                         calendarIDs: Set<String>) throws -> CalendarSnapshot {
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        guard !calendarIDs.isEmpty, !calendarIDs.contains("") else { throw CalendarObservationError.selectionRequired }
        let readRevision = changeRevision
        let choices = try calendarChoices()
        guard calendarIDs.isSubset(of: Set(choices.map(\.id))) else {
            throw CalendarObservationError.selectedCalendarsUnavailable
        }
        guard day.timeIntervalSinceReferenceDate.isFinite,
              let interval = calendar.dateInterval(of: .day, for: day), interval.duration > 0,
              interval.start.timeIntervalSinceReferenceDate.isFinite,
              interval.end.timeIntervalSinceReferenceDate.isFinite
        else { throw CalendarObservationError.invalidDay }
        let records = try provider.events(in: interval, calendarIDs: calendarIDs)
        // Revocation or a disappeared selection must not become a reassuring empty-day result.
        let refreshed = try calendarChoices()
        guard calendarIDs.isSubset(of: Set(refreshed.map(\.id))) else {
            throw CalendarObservationError.selectedCalendarsUnavailable
        }
        guard changeRevision == readRevision else { throw CalendarObservationError.changedDuringRead }
        let selected = refreshed.filter { calendarIDs.contains($0.id) }
        let selectedByID = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, $0) })
        var events: [CalendarEventSummary] = []
        for record in records {
            guard let choice = selectedByID[record.calendarID], !record.isCancelled, !record.currentUserDeclined else { continue }
            guard !record.id.isEmpty, record.start.timeIntervalSinceReferenceDate.isFinite,
                  record.end.timeIntervalSinceReferenceDate.isFinite, record.end >= record.start,
                  record.occurrenceDate?.timeIntervalSinceReferenceDate.isFinite != false
            else { throw CalendarObservationError.invalidEventData }
            let start = try projected(record.start, event: record, timeZone: calendar.timeZone)
            let end = try projected(record.end, event: record, timeZone: calendar.timeZone)
            guard end >= start else { throw CalendarObservationError.invalidEventData }
            let overlaps = end == start
                ? start >= interval.start && start < interval.end
                : start < interval.end && end > interval.start
            guard overlaps else { continue }
            let occurrence = record.occurrenceDate ?? record.start
            // Length prefixes avoid delimiter collisions; the bit pattern avoids locale/date formatting changes.
            let identity = "\(record.calendarID.utf8.count):\(record.calendarID)\(record.id.utf8.count):\(record.id):\(occurrence.timeIntervalSinceReferenceDate.bitPattern)"
            events.append(CalendarEventSummary(id: identity, title: record.title.isEmpty ? AppLanguage.localized("Untitled event", bundle: .module) : record.title,
                start: start, end: end, isAllDay: record.isAllDay, calendarTitle: choice.title,
                calendarID: choice.id, sourceTitle: choice.sourceTitle))
        }
        // Deterministic tie handling and occurrence deduplication; two calendars remain distinct.
        events.sort(by: Self.eventPrecedes)
        var seen: Set<String> = []
        events = events.filter { seen.insert($0.id).inserted }
        guard changeRevision == readRevision else { throw CalendarObservationError.changedDuringRead }
        return CalendarSnapshot(retrievedAt: now(), dayStart: interval.start, dayEnd: interval.end,
            events: events, timeZoneIdentifier: calendar.timeZone.identifier, selectedCalendars: selected,
            changeRevision: readRevision)
    }

    private static func eventPrecedes(_ lhs: CalendarEventSummary, _ rhs: CalendarEventSummary) -> Bool {
        if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.end != rhs.end { return lhs.end < rhs.end }
        if lhs.title != rhs.title { return lhs.title < rhs.title }
        if lhs.calendarID != rhs.calendarID { return lhs.calendarID < rhs.calendarID }
        return lhs.id < rhs.id
    }

    private func projected(_ date: Date, event: CalendarObservationEvent, timeZone: TimeZone) throws -> Date {
        guard event.isAllDay, let identifier = event.floatingTimeZoneIdentifier else { return date }
        guard let sourceZone = TimeZone(identifier: identifier) else { throw CalendarObservationError.invalidEventData }
        var source = Calendar(identifier: .gregorian); source.timeZone = sourceZone
        var target = Calendar(identifier: .gregorian); target.timeZone = timeZone
        let components = source.dateComponents([.year, .month, .day], from: date)
        guard let projected = target.date(from: components) else { throw CalendarObservationError.invalidEventData }
        return projected
    }
}

@MainActor
final class EventKitCalendarObservationProvider: NSObject, CalendarObservationProviding {
    private let store: EKEventStore
    private(set) var changeRevision: UInt64 = 0

    override convenience init() { self.init(store: EKEventStore()) }

    init(store: EKEventStore, notificationCenter: NotificationCenter = .default) {
        self.store = store
        super.init()
        // EventKit posts this notification on the main actor. Selector observers
        // are removed automatically on deallocation; no closure retains the store.
        notificationCenter.addObserver(self, selector: #selector(eventStoreChanged(_:)),
            name: .EKEventStoreChanged, object: store)
    }

    @objc private func eventStoreChanged(_ notification: Notification) {
        changeRevision &+= 1
    }

    var isAuthorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    func requestAccess() async throws -> Bool { try await store.requestFullAccessToEvents() }

    func calendarChoices() throws -> [CalendarChoice] {
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        return store.calendars(for: .event).map {
            CalendarChoice(id: $0.calendarIdentifier, title: $0.title, sourceTitle: $0.source?.title ?? AppLanguage.localized("Calendar source", bundle: .module))
        }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>) throws -> [CalendarObservationEvent] {
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        guard !calendarIDs.isEmpty else { throw CalendarObservationError.selectionRequired }
        let selected = store.calendars(for: .event).filter { calendarIDs.contains($0.calendarIdentifier) }
        guard Set(selected.map(\.calendarIdentifier)) == calendarIDs else { throw CalendarObservationError.selectedCalendarsUnavailable }
        // Floating all-day dates are returned in the system default zone. Query a bounded margin
        // for zone differences, then reanchor/filter precisely in the service. Timed events stay absolute.
        let predicate = store.predicateForEvents(withStart: interval.start.addingTimeInterval(-172_800),
            end: interval.end.addingTimeInterval(172_800), calendars: selected)
        let floatingZone = NSTimeZone.default.identifier
        let records = try store.events(matching: predicate).map { event -> CalendarObservationEvent in
            guard let start = event.startDate, let end = event.endDate, let nativeCalendar = event.calendar else {
                throw CalendarObservationError.invalidEventData
            }
            return CalendarObservationEvent(id: event.eventIdentifier ?? event.calendarItemIdentifier,
                calendarID: nativeCalendar.calendarIdentifier, title: event.title ?? AppLanguage.localized("Untitled event", bundle: .module),
                start: start, end: end, isAllDay: event.isAllDay, occurrenceDate: event.occurrenceDate,
                isCancelled: event.status == .canceled,
                currentUserDeclined: event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false,
                floatingTimeZoneIdentifier: event.isAllDay ? floatingZone : nil)
        }
        guard isAuthorized else { throw CalendarObservationError.notAuthorized }
        return records
    }
}
