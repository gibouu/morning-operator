import Foundation
import Testing
@testable import MorningCore

@Suite("Foreground morning entry")
struct MorningEntryTests {
    let now = Date(timeIntervalSince1970: 10_000)

    @Test("Inactive scenes and occupied screens defer rather than consume a start")
    func defersUntilReady() {
        let request = MorningEntryRequest(requestedAt: now)
        var context = ready()
        context.sceneIsActive = false
        #expect(decision(request, context) == .wait)
        context.sceneIsActive = true
        context.isOccupied = true
        #expect(decision(request, context) == .wait)
        context.isOccupied = false
        #expect(decision(request, context) == .start)
    }

    @Test("Deferred expiry and clock rollback reveal the ordinary morning without executing")
    func expiration() {
        let request = MorningEntryRequest(requestedAt: now)
        #expect(MorningEntryPolicy.destination(for: request, context: ready(), consumedIDs: [],
            now: now.addingTimeInterval(60)) == .revealMorning)
        #expect(MorningEntryPolicy.destination(for: request, context: ready(), consumedIDs: [],
            now: now.addingTimeInterval(-1)) == .revealMorning)
        #expect(MorningEntryRequest(requestedAt: now, lifetime: 9_000).expiresAt == now.addingTimeInterval(60))
    }

    @Test("Drafts and empty workspaces open review or learning without granting approval")
    func approvalRequired() {
        let request = MorningEntryRequest(requestedAt: now)
        var context = ready()
        context.routineIsApproved = false
        #expect(decision(request, context) == .reviewDraft)
        context.hasRoutine = false
        #expect(decision(request, context) == .learn)
    }

    @Test("Running sessions are revealed; paused sessions resume; terminal sessions may start")
    func sessionRouting() {
        let request = MorningEntryRequest(requestedAt: now)
        var context = ready()
        for (status, expected) in [(SessionStatus.running, MorningEntryDestination.revealMorning),
                                    (.paused, .resume), (.ready, .start), (.stopped, .start), (.completed, .start)] {
            context.sessionStatus = status
            #expect(decision(request, context) == expected)
        }
    }

    @Test("Consumed entries and unavailable storage never request automatic execution")
    func unavailableOrReplayed() {
        let request = MorningEntryRequest(requestedAt: now)
        #expect(MorningEntryPolicy.destination(for: request, context: ready(), consumedIDs: [request.id], now: now) == .revealMorning)
        var context = ready()
        context.storageIsAvailable = false
        #expect(decision(request, context) == .revealMorning)
    }

    private func ready() -> MorningEntryContext {
        .init(sceneIsActive: true, isOccupied: false, storageIsAvailable: true,
              hasRoutine: true, routineIsApproved: true, sessionStatus: nil)
    }

    private func decision(_ request: MorningEntryRequest, _ context: MorningEntryContext) -> MorningEntryDestination {
        MorningEntryPolicy.destination(for: request, context: context, consumedIDs: [], now: now)
    }
}
