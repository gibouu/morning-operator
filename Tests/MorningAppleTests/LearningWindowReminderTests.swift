import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// The reminder of a learning window goes through the one-time invitation service, with a
/// notification fixture in place of the system. No notification is requested or delivered.
@Suite("Learning window reminders: one at a time, never claimed, never a start")
@MainActor
struct LearningWindowReminderTests {
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        return try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute)))
    }
    private func key(_ day: Int) -> String { String(format: "2026-10-%02d", day) }

    private struct Setup {
        let clock: ReminderClock
        let storage: ReminderMemoryStorage
        let client: ReminderNotificationFixture
        let service: MorningInvitationService
        let planner: LearningWindowReminderPlanner
        var window: LearningWindow
    }

    /// 07:00 to 07:05 in Paris, every day, three mornings, started on Monday 12 October at 06:00.
    private func setup(_ authorization: MorningInvitationAuthorization = .authorized) throws -> Setup {
        let clock = ReminderClock(try at(12, 6))
        let storage = ReminderMemoryStorage()
        let client = ReminderNotificationFixture(authorization: authorization)
        let service = MorningInvitationService(storage: storage, notifications: client, now: { clock.date })
        var window = try LearningWindow(startMinuteOfDay: 7 * 60, durationSeconds: 300,
            weekdays: Set(LearningWindowWeekday.allCases), timeZoneIdentifier: "Europe/Paris", morningCount: 3,
            createdAt: at(11, 20), limits: .currentCapture)
        try window.start(at: clock.date)
        return .init(clock: clock, storage: storage, client: client, service: service,
                     planner: .init(invitations: service, now: { clock.date }), window: window)
    }

    @Test func eachMorningGetsOneReminderAndTheNextFollowsWhenThePreviousIsUsedOrMissed() async throws {
        let test = try setup(.notDetermined)
        test.client.authorizationAfterRequest = .authorized

        // Pressing Start on the window is the person's request: it may ask for permission, once.
        var outcome = await test.planner.refresh(for: test.window, personRequested: true)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))
        #expect(test.client.permissionRequests == 1)
        let monday = MorningInvitationLearningTarget(windowID: test.window.id, dayKey: key(12))
        #expect(test.client.added.map(\.learningTarget) == [monday])
        try #expect(test.client.pending?.scheduledAt == (at(12, 7)))
        #expect(test.storage.value?.timeZoneIdentifier == "Europe/Paris")

        // Refreshing again changes nothing: still one reminder, not a second one.
        outcome = await test.planner.refresh(for: test.window)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))
        #expect(test.client.added.count == 1)

        // 07:01: delivered and not yet answered. It is left alone.
        test.clock.date = try at(12, 7, 1)
        outcome = await test.planner.refresh(for: test.window)
        try #expect(outcome == .awaitingResponse(dayKey: key(12), at: at(12, 7)))
        #expect(test.client.added.count == 1)

        // The person taps it. The app learns it was a learning reminder, not a morning start.
        let payload = try #require(test.service.invitation?.payload)
        let used = try #require(try test.service.consume(payload))
        #expect(used.learningTarget == monday && used.disposition == .consumed)
        outcome = await test.planner.refresh(for: test.window)
        try #expect(outcome == .scheduled(dayKey: key(13), at: at(13, 7)))
        #expect(test.client.added.map(\.learningTarget?.dayKey) == [key(12), key(13)])
        try #expect(test.client.pending?.scheduledAt == (at(13, 7)))

        // Tuesday's reminder is never answered. It expires two hours later, and Wednesday's follows.
        test.clock.date = try at(13, 9, 30)
        outcome = await test.planner.refresh(for: test.window)
        try #expect(outcome == .scheduled(dayKey: key(14), at: at(14, 7)))
        #expect(test.client.added.count == 3)

        // After the last morning there is nothing left to announce.
        test.clock.date = try at(14, 9, 30)
        outcome = await test.planner.refresh(for: test.window)
        #expect(outcome == .nothingToSchedule)
        #expect(test.client.pending == nil)
        #expect(test.client.added.count == 3)
        // Only the person's own request ever asked for permission.
        #expect(test.client.permissionRequests == 1)
    }

    @Test func aDeniedQuietOrUnaskedPermissionIsReportedAndNothingIsClaimedAsScheduled() async throws {
        let denied = try setup(.denied)
        var outcome = await denied.planner.refresh(for: denied.window, personRequested: true)
        try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .notificationsDenied))
        #expect(denied.client.added.isEmpty && denied.client.pending == nil)
        #expect(denied.client.permissionRequests == 0)
        #expect(!denied.service.isScheduled)

        let quiet = try setup(.provisional)
        outcome = await quiet.planner.refresh(for: quiet.window, personRequested: true)
        try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .notificationsQuiet))
        #expect(quiet.client.added.isEmpty && quiet.client.pending == nil)

        // At 07:01 there is still nothing on screen to answer: it is not "awaiting a response".
        denied.clock.date = try at(12, 7, 1)
        outcome = await denied.planner.refresh(for: denied.window)
        try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .notificationsDenied))
        denied.clock.date = try at(12, 6)

        // Without the person's request nothing prompts, however often the app refreshes.
        let unasked = try setup(.notDetermined)
        for _ in 0..<3 {
            outcome = await unasked.planner.refresh(for: unasked.window)
            try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .permissionNotRequested))
        }
        #expect(unasked.client.permissionRequests == 0)
        #expect(unasked.client.added.isEmpty)

        // The system accepts the request and then does not hold it: not confirmed, not scheduled.
        let lost = try setup()
        lost.client.dropAdds = true
        outcome = await lost.planner.refresh(for: lost.window, personRequested: true)
        try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .notConfirmed))

        // Once the person allows notifications in Settings, the next refresh registers it.
        denied.client.authorization = .authorized
        outcome = await denied.planner.refresh(for: denied.window)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))
        #expect(denied.client.added.count == 1 && denied.client.permissionRequests == 0)
    }

    @Test func stopAndPauseRemoveThePendingReminderAndStartAgainRestoresOneWithoutPrompting() async throws {
        var test = try setup()
        var outcome = await test.planner.refresh(for: test.window, personRequested: true)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))

        test.clock.date = try at(12, 6, 30)
        try test.window.pause(at: test.clock.date)
        outcome = await test.planner.refresh(for: test.window)
        #expect(outcome == .nothingToSchedule)
        #expect(test.client.pending == nil && test.storage.value?.disposition == .cancelled)

        test.clock.date = try at(12, 6, 40)
        try test.window.start(at: test.clock.date)
        outcome = await test.planner.refresh(for: test.window)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))
        #expect(test.client.permissionRequests == 0)

        test.window.stop(at: try at(12, 6, 50))
        test.clock.date = try at(12, 6, 50)
        outcome = await test.planner.refresh(for: test.window)
        #expect(outcome == .nothingToSchedule)
        #expect(test.client.pending == nil && test.storage.value?.disposition == .cancelled)
        #expect(!test.service.isScheduled)
        // A stopped window never gets another reminder.
        test.clock.date = try at(12, 6, 55)
        outcome = await test.planner.refresh(for: test.window, personRequested: true)
        #expect(outcome == .nothingToSchedule)
        #expect(test.client.pending == nil && test.client.added.count == 2)
    }

    @Test func thePersonsOwnInvitationIsNeverReplacedOrCancelledByAWindow() async throws {
        var test = try setup()
        await test.service.schedule(at: try at(12, 6, 30))
        let own = try #require(test.storage.value)
        #expect(own.learningTarget == nil && test.service.isScheduled)

        var outcome = await test.planner.refresh(for: test.window, personRequested: true)
        try #expect(outcome == .notScheduled(dayKey: key(12), at: at(12, 7), obstacle: .personalInvitationPending))
        #expect(test.storage.value == own && test.client.added.count == 1)

        test.window.stop(at: test.clock.date)
        outcome = await test.planner.refresh(for: test.window)
        #expect(outcome == .nothingToSchedule)
        #expect(test.storage.value == own, "Stopping a window leaves the person's invitation alone.")
        #expect(test.client.pending?.payload == own.payload)
    }

    @Test func aMorningAlreadyRecordedNeedsNoReminder() async throws {
        let test = try setup()
        var outcome = await test.planner.refresh(for: test.window, personRequested: true)
        try #expect(outcome == .scheduled(dayKey: key(12), at: at(12, 7)))
        // The person started recording at 06:58 without waiting for the reminder.
        test.clock.date = try at(12, 6, 58)
        outcome = await test.planner.refresh(for: test.window, observedDayKeys: [key(12)])
        try #expect(outcome == .scheduled(dayKey: key(13), at: at(13, 7)))
        try #expect(test.client.pending?.scheduledAt == (at(13, 7)))
        #expect(test.client.added.count == 2)
    }

    @Test func anInvitationSavedBeforeLearningWindowsIsStillThePersonsOwn() throws {
        let scheduled = try at(12, 7)
        let old = """
        {"id":"7B0E6A53-5D0C-4B7E-9C1E-0A6B1F2D3C4E","scheduledAt":\(scheduled.timeIntervalSinceReferenceDate),
         "timeZoneIdentifier":"Europe/Paris","expiresAt":\(scheduled.timeIntervalSinceReferenceDate + 7_200),
         "disposition":"enabled"}
        """
        let loaded = try JSONDecoder().decode(MorningInvitation.self, from: Data(old.utf8))
        #expect(loaded.learningTarget == nil && loaded.disposition == .enabled)
        let encoder = JSONEncoder()
        try #expect(!#require(String(data: encoder.encode(loaded), encoding: .utf8)).contains("learningTarget"))

        let target = MorningInvitationLearningTarget(windowID: UUID(), dayKey: key(12))
        let reminder = try MorningInvitation(scheduledAt: scheduled, timeZoneIdentifier: "Europe/Paris",
                                             now: try at(12, 6), learningTarget: target)
        try #expect(JSONDecoder().decode(MorningInvitation.self, from: encoder.encode(reminder)) == reminder)
        // A reminder whose target cannot be read is refused, never turned into a morning start.
        var object = try #require(JSONSerialization.jsonObject(with: encoder.encode(reminder)) as? [String: Any])
        object["learningTarget"] = ["windowID": 7]
        #expect(throws: (any Error).self) {
            try JSONDecoder().decode(MorningInvitation.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }
}

@MainActor private final class ReminderClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor private final class ReminderMemoryStorage: MorningInvitationStorage {
    var value: MorningInvitation?
    func load() throws -> MorningInvitation? { value }
    func save(_ invitation: MorningInvitation?) throws { value = invitation }
}

@MainActor private final class ReminderNotificationFixture: MorningInvitationNotificationClient {
    var authorization: MorningInvitationAuthorization
    var authorizationAfterRequest: MorningInvitationAuthorization?
    var pending: MorningInvitationPendingRequest?
    var added: [MorningInvitation] = []
    var permissionRequests = 0
    /// The system accepts a request and then holds nothing.
    var dropAdds = false

    init(authorization: MorningInvitationAuthorization) { self.authorization = authorization }
    func settings() async -> MorningInvitationNotificationSettings {
        .init(authorization: authorization, alertsEnabled: authorization == .authorized, soundsEnabled: authorization == .authorized)
    }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if let authorizationAfterRequest { authorization = authorizationAfterRequest }
        return authorization == .authorized
    }
    func pendingInvitation() async -> MorningInvitationPendingRequest? { pending }
    func add(_ invitation: MorningInvitation, sound: Bool) async throws {
        added.append(invitation)
        if !dropAdds { pending = .init(payload: invitation.payload, scheduledAt: invitation.scheduledAt) }
    }
    func removePendingInvitation() async { pending = nil }
    func removeDeliveredInvitation() async {}
    func hasDeliveredInvitation() async -> Bool { false }
}
