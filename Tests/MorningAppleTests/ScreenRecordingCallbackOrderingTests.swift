import Foundation
import Testing
@testable import MorningApple

@Suite("Recording callback-entry provenance ordering")
struct ScreenRecordingCallbackOrderingTests {
    @Test("Finalization preserves an observed start even when its MainActor delivery is last",
          arguments: [true, false])
    func finalizationBeforeStartDelivery(writerFinishesFirst: Bool) throws {
        let fixture = Fixture()
        // Native start callback runs, but its UI/state delivery is deliberately withheld.
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID, startedAt: fixture.start,
                                             timeZoneIdentifier: "Europe/Paris")
        #expect(fixture.context.context == nil, "The start task has not been delivered.")
        var writerFinished = false
        var streamStopped = false
        for writerEvent in [writerFinishesFirst, !writerFinishesFirst] {
            if writerEvent { writerFinished = true } else { streamStopped = true }
            guard writerFinished && streamStopped else { continue }
            // This is the exact synchronous reconcile used by finishIfReady before it
            // releases output/delegate IDs and calls the durable handoff callback.
            #expect(fixture.reconcile(closing: true))
            let handoff = try #require(fixture.context.context)
            fixture.callbacks.invalidate()
            fixture.context.clear()
            // Delivering the old start task now cannot recreate state after handoff.
            #expect(!fixture.reconcile())
            #expect(fixture.context.context == nil)
            #expect(handoff.startedAt == fixture.start && handoff.id == fixture.sessionID)
            #expect(handoff.timeZoneIdentifier == "Europe/Paris")
        }
    }

    @Test("Finish with no observed native start remains unknown, including a late post-release callback")
    func missingStartIsNotFilledFromFinalizationOrLateDelivery() {
        let fixture = Fixture()
        #expect(!fixture.reconcile(closing: true))
        #expect(fixture.context.context == nil)
        fixture.callbacks.invalidate()
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID, startedAt: fixture.start,
                                             timeZoneIdentifier: "UTC")
        #expect(!fixture.reconcile() && fixture.context.context == nil)
    }

    @Test("Only the bound output and exact session can contribute callback evidence")
    func wrongOutputAndStaleSessionDoNotContribute() {
        let fixture = Fixture()
        let otherOutput = NSObject()
        defer { withExtendedLifetime(otherOutput) {} }
        fixture.callbacks.recordingDidStart(outputID: ObjectIdentifier(otherOutput), startedAt: fixture.start,
                                             timeZoneIdentifier: "UTC")
        #expect(!fixture.reconcile() && fixture.context.context == nil)
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID, startedAt: fixture.start,
                                             timeZoneIdentifier: "Europe/Paris")
        let staleSessionAccepted = fixture.callbacks.reconcile(into: &fixture.context, sessionID: UUID(), outputID: fixture.outputID)
        let wrongOutputAccepted = fixture.callbacks.reconcile(into: &fixture.context, sessionID: fixture.sessionID,
                                                               outputID: ObjectIdentifier(otherOutput))
        #expect(!staleSessionAccepted && !wrongOutputAccepted)
        #expect(fixture.context.context == nil)
        #expect(fixture.reconcile() && fixture.context.context?.startedAt == fixture.start)
    }

    @Test("Duplicate callbacks cannot shift the first actual callback's date or zone")
    func duplicateStartKeepsFirstEvidenceAndResourceReleaseKeepsAcceptedContext() throws {
        let fixture = Fixture()
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID, startedAt: fixture.start,
                                             timeZoneIdentifier: "Europe/Paris")
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID,
            startedAt: fixture.start.addingTimeInterval(30), timeZoneIdentifier: "UTC")
        #expect(fixture.reconcile())
        let accepted = try #require(fixture.context.context)
        fixture.callbacks.invalidate()
        #expect(fixture.context.context == accepted, "Resource release is separate from URL handoff/discard.")
        #expect(accepted.startedAt == fixture.start && accepted.timeZoneIdentifier == "Europe/Paris")
    }

    @Test("Invalid first-start metadata stays unknown instead of borrowing a later duplicate's instant",
          arguments: [true, false])
    func invalidFirstMetadataDoesNotBecomeAGuessedStart(invalidDate: Bool) {
        let fixture = Fixture()
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID,
            startedAt: invalidDate ? Date(timeIntervalSinceReferenceDate: .nan) : fixture.start,
            timeZoneIdentifier: invalidDate ? "UTC" : "Invalid/SyntheticZone")
        fixture.callbacks.recordingDidStart(outputID: fixture.outputID,
            startedAt: fixture.start.addingTimeInterval(30), timeZoneIdentifier: "UTC")
        #expect(fixture.reconcile(), "The writer-start acknowledgement remains real even when its date is unusable.")
        #expect(fixture.context.context == nil)
    }

    @Test("An attempt cannot be rebound and a closed bridge cannot affect a replacement recording")
    func rebindingAndReplacementAreIsolated() {
        let first = Fixture()
        let second = Fixture()
        first.callbacks.bind(outputID: second.outputID)
        first.callbacks.recordingDidStart(outputID: second.outputID, startedAt: first.start, timeZoneIdentifier: "UTC")
        #expect(!first.reconcile())
        first.callbacks.invalidate()
        first.callbacks.bind(outputID: second.outputID)
        first.callbacks.recordingDidStart(outputID: second.outputID, startedAt: first.start, timeZoneIdentifier: "UTC")
        let oldBridgeAccepted = first.callbacks.reconcile(into: &second.context, sessionID: second.sessionID, outputID: second.outputID)
        #expect(!oldBridgeAccepted)
        #expect(second.context.context == nil)
        second.callbacks.recordingDidStart(outputID: second.outputID, startedAt: second.start,
                                          timeZoneIdentifier: "UTC")
        #expect(second.reconcile() && second.context.context?.id == second.sessionID)
    }

    /// Plain deterministic lifecycle fixture, not a ScreenCaptureKit or hardware simulation.
    private final class Fixture {
        let sessionID = UUID()
        let output = NSObject()
        let start = Date(timeIntervalSince1970: 1_728_000_000)
        let callbacks: ScreenRecordingCallbackProvenance
        var context = ScreenRecordingContextState()
        var outputID: ObjectIdentifier { ObjectIdentifier(output) }

        init() {
            callbacks = ScreenRecordingCallbackProvenance(sessionID: sessionID)
            callbacks.bind(outputID: ObjectIdentifier(output))
            context.begin(sessionID: sessionID)
        }

        func reconcile(closing: Bool = false) -> Bool {
            callbacks.reconcile(into: &context, sessionID: sessionID, outputID: outputID, closing: closing)
        }
    }
}
