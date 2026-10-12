import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Live Activity ownership — injected provider only")
@MainActor
struct MorningLiveActivityCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func snapshot(id: UUID = UUID(), status: MorningActivityStatus = .running,
                          completed: Int = 0, at date: Date? = nil) throws -> MorningActivitySnapshot {
        .init(sessionID: id, state: try .init(category: .custom, status: status,
            completedSteps: completed, totalSteps: 3, updatedAt: date ?? now))
    }

    @Test func noStartWithoutOptInForegroundAndExplicitPermission() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: false, isForeground: true, allowStart: true)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: false, allowStart: true)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true)
        #expect(provider.requests == 0)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.requests == 1 && coordinator.status == .active)
        #expect(provider.staleDates == [now.addingTimeInterval(60)])
    }

    @Test func relaunchEndsOldActivityBeforeExplicitNewRequest() async throws {
        let provider = ActivityProviderDouble()
        provider.items = [.init(id: "old", sessionID: UUID(), state: .active)]
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true)
        #expect(provider.events == ["end:old"] && provider.requests == 0)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.events == ["end:old", "request"])
    }

    @Test func progressUpdatesInBackgroundButTimestampAloneDoesNotExtendFreshness() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now.addingTimeInterval(10) })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        let unchanged = try snapshot(id: value.sessionID, at: now.addingTimeInterval(5))
        try await coordinator.synchronize(snapshot: unchanged, enabled: true, isForeground: false)
        #expect(provider.updates.isEmpty && coordinator.currentSnapshot == value)
        let paused = try snapshot(id: value.sessionID, status: .paused, completed: 1, at: now.addingTimeInterval(10))
        try await coordinator.synchronize(snapshot: paused, enabled: true, isForeground: false)
        #expect(provider.updates == [paused] && provider.requests == 1)
        #expect(provider.staleDates.last == now.addingTimeInterval(70))
    }

    @Test func foregroundConfirmsStaleStateButBackgroundCannotRefreshUnchangedProgress() async throws {
        let provider = ActivityProviderDouble()
        var clock = now
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { clock })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        let record = try #require(provider.items.first)
        provider.items = [.init(id: record.id, sessionID: record.sessionID, state: .stale)]
        clock = now.addingTimeInterval(60)
        let confirmed = try snapshot(id: value.sessionID, at: clock)
        try await coordinator.synchronize(snapshot: confirmed, enabled: true, isForeground: false)
        #expect(provider.updates.isEmpty && coordinator.status == .stale)
        try await coordinator.synchronize(snapshot: confirmed, enabled: true, isForeground: true)
        #expect(provider.updates == [confirmed] && coordinator.currentSnapshot == confirmed)
        #expect(provider.staleDates.last == clock.addingTimeInterval(60))
    }

    @Test(arguments: [true, false])
    func dismissalAndDeniedAuthorizationAreNotRecreatedByRepeatedPermit(dismissed: Bool) async throws {
        let provider = ActivityProviderDouble()
        provider.authorizationEnabled = dismissed
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        if dismissed { provider.items = [] } else { provider.authorizationEnabled = true }
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.requests == (dismissed ? 1 : 0))
        #expect(coordinator.activeActivityID == nil)
    }

    @Test func newExplicitGrantRetriesButSameGrantCannotRecreateAfterDismissal() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        let firstGrant = UUID()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: firstGrant)
        provider.items = []
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: firstGrant)
        #expect(provider.requests == 1)
        try await coordinator.synchronize(snapshot: value, enabled: false, isForeground: true)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: UUID())
        #expect(provider.requests == 2 && coordinator.status == .active)
    }

    @Test func grantWhileHealthyIsConsumedAndCannotBeReusedAfterDismissal() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: UUID())
        let resumeGrant = UUID()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: resumeGrant)
        #expect(provider.requests == 1)
        provider.items = []
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: resumeGrant)
        #expect(provider.requests == 1 && coordinator.activeActivityID == nil)
    }

    @Test func failedRequestConsumesItsGrantAndExplicitRetryUsesANewOne() async throws {
        let provider = ActivityProviderDouble()
        provider.failRequest = true
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot(), firstGrant = UUID()
        await #expect(throws: MorningLiveActivityError.requestFailed) {
            try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
                allowStart: true, startRequestID: firstGrant)
        }
        provider.failRequest = false
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: firstGrant)
        #expect(provider.requests == 1 && provider.items.isEmpty)
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true,
            allowStart: true, startRequestID: UUID())
        #expect(provider.requests == 2 && coordinator.status == .active)
    }

    @Test func disabledAndTerminalStateImmediatelyEndOwnedActivity() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        try await coordinator.synchronize(snapshot: value, enabled: false, isForeground: false)
        #expect(provider.items.isEmpty && coordinator.currentSnapshot == nil)
        let next = try snapshot()
        try await coordinator.synchronize(snapshot: next, enabled: true, isForeground: true, allowStart: true)
        try await coordinator.synchronize(snapshot: nil, enabled: true, isForeground: false)
        #expect(provider.items.isEmpty && coordinator.status == .inactive && provider.requests == 2)
    }

    @Test func privacyWaitsForLateRequestThenEndsItBeforeReturning() async throws {
        let provider = ActivityProviderDouble()
        let gate = ActivityRequestGate()
        provider.requestGate = gate
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        let starting = Task { try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true) }
        await gate.waitUntilPaused()
        let forgetting = Task { try await coordinator.endAllForPrivacy() }
        while coordinator.status != .ending { await Task.yield() }
        #expect(provider.items.isEmpty, "The pending request has not returned an owned activity yet.")
        gate.resume()
        try await starting.value; try await forgetting.value
        #expect(provider.items.isEmpty && provider.events == ["request", "end:activity-1"])
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.requests == 1 && coordinator.currentSnapshot == nil)
    }

    @Test func progressArrivingDuringRequestUsesSameActivityInsteadOfDroppingIt() async throws {
        let provider = ActivityProviderDouble()
        let gate = ActivityRequestGate()
        provider.requestGate = gate
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        let starting = Task { try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true) }
        await gate.waitUntilPaused()
        let changed = try snapshot(id: value.sessionID, status: .paused)
        let updating = Task { try await coordinator.synchronize(snapshot: changed, enabled: true, isForeground: true) }
        await Task.yield()
        gate.resume()
        try await starting.value; try await updating.value
        #expect(provider.requests == 1 && provider.updates == [changed] && provider.items.count == 1)
        #expect(coordinator.currentSnapshot == changed)
    }

    @Test func failedPrivacyEndStaysBlockedAndRetryable() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        provider.failEnd = true
        await #expect(throws: MorningLiveActivityError.endFailed) { try await coordinator.endAllForPrivacy() }
        #expect(coordinator.lastError == .endFailed && !provider.items.isEmpty)
        #expect(throws: MorningLiveActivityError.privacyBlocked) { try coordinator.resetAfterPrivacyCleanup() }
        provider.failEnd = false
        try await coordinator.endAllForPrivacy()
        try coordinator.resetAfterPrivacyCleanup()
        #expect(provider.items.isEmpty && coordinator.lastError == nil)
    }

    @Test func differentSessionEndsOldActivityBeforeCreatingAnother() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let first = try snapshot(), second = try snapshot()
        try await coordinator.synchronize(snapshot: first, enabled: true, isForeground: true, allowStart: true)
        try await coordinator.synchronize(snapshot: second, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.events == ["request", "end:activity-1", "request"])
        #expect(provider.items.count == 1 && provider.items.first?.sessionID == second.sessionID)
    }

    @Test func endReturningWithoutDismissalCannotReportPrivacySuccess() async throws {
        let provider = ActivityProviderDouble()
        let coordinator = MorningLiveActivityCoordinator(provider: provider, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        provider.ignoreEnd = true
        await #expect(throws: MorningLiveActivityError.endUnconfirmed) { try await coordinator.endAllForPrivacy() }
        #expect(throws: MorningLiveActivityError.privacyBlocked) { try coordinator.resetAfterPrivacyCleanup() }
        provider.ignoreEnd = false
        try await coordinator.endAllForPrivacy()
        #expect(provider.items.isEmpty && coordinator.currentSnapshot == nil)
    }

    @Test func closedDurableGateEndsExistingActivityAndRejectsStaleInput() async throws {
        let provider = ActivityProviderDouble()
        var permitted = true
        let coordinator = MorningLiveActivityCoordinator(provider: provider, canPublish: { permitted }, now: { self.now })
        let value = try snapshot()
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        permitted = false
        try await coordinator.synchronize(snapshot: value, enabled: true, isForeground: true, allowStart: true)
        #expect(provider.items.isEmpty && provider.requests == 1)
        permitted = true
        let stale = try snapshot(at: now.addingTimeInterval(-60))
        await #expect(throws: MorningLiveActivityError.invalidSnapshot) {
            try await coordinator.synchronize(snapshot: stale, enabled: true, isForeground: true, allowStart: true)
        }
        #expect(provider.requests == 1)
    }
}

@MainActor private final class ActivityProviderDouble: MorningLiveActivityProviding {
    var isSupported = true
    var authorizationEnabled = true
    var items: [MorningLiveActivityRecord] = []
    var records: [MorningLiveActivityRecord] { items }
    var requests = 0
    var updates: [MorningActivitySnapshot] = []
    var staleDates: [Date] = []
    var events: [String] = []
    var failRequest = false
    var failEnd = false
    var ignoreEnd = false
    var requestGate: ActivityRequestGate?
    func request(snapshot: MorningActivitySnapshot, staleDate: Date) async throws -> String {
        requests += 1; events.append("request"); staleDates.append(staleDate)
        if failRequest { throw MorningLiveActivityError.requestFailed }
        let id = "activity-\(requests)"
        if let requestGate { await requestGate.pause() }
        items.append(.init(id: id, sessionID: snapshot.sessionID, state: .active))
        return id
    }
    func update(id: String, snapshot: MorningActivitySnapshot, staleDate: Date) async throws {
        updates.append(snapshot); staleDates.append(staleDate); events.append("update:\(id)")
    }
    func end(id: String) async throws {
        if failEnd { throw MorningLiveActivityError.endFailed }
        events.append("end:\(id)")
        if !ignoreEnd { items.removeAll { $0.id == id } }
    }
}

@MainActor private final class ActivityRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; ready?.resume(); ready = nil
        }
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func resume() { let value = continuation; continuation = nil; value?.resume() }
}
