import Foundation
import Testing
@testable import MorningCore

/// A clock the test moves by hand. No test here waits for real time.
private final class ManualClock {
    private(set) var seconds: Double
    init(_ seconds: Double) { self.seconds = seconds }
    func advance(_ by: Double) { seconds += by }
}

@Suite("Spans in which MORE's own scene was in front")
struct OwnInterfaceIntervalsTests {
    @Test("A frame just inside, exactly on and just outside each widened bound")
    func boundaries() {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 10, endSeconds: 20)])
        // The default margin is one second on each side, and both bounds are inclusive.
        #expect(OwnInterfaceIntervals.defaultMarginSeconds == 1)
        #expect(!spans.contains(mediaSeconds: 8.999))
        #expect(spans.contains(mediaSeconds: 9))
        #expect(spans.contains(mediaSeconds: 9.001))
        #expect(spans.contains(mediaSeconds: 15))
        #expect(spans.contains(mediaSeconds: 20.999))
        #expect(spans.contains(mediaSeconds: 21))
        #expect(!spans.contains(mediaSeconds: 21.001))
        // Without a margin the recorded bounds themselves are the limit.
        #expect(!spans.contains(mediaSeconds: 9.999, marginSeconds: 0))
        #expect(spans.contains(mediaSeconds: 10, marginSeconds: 0))
        #expect(spans.contains(mediaSeconds: 20, marginSeconds: 0))
        #expect(!spans.contains(mediaSeconds: 20.001, marginSeconds: 0))
        #expect(spans.contains(mediaSeconds: 7, marginSeconds: 3))
        #expect(!spans.contains(mediaSeconds: 6.999, marginSeconds: 3))
    }

    @Test("An invalid time or margin is never matched, and no span matches nothing")
    func invalidInputs() {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0)])
        #expect(!spans.contains(mediaSeconds: .nan))
        #expect(!spans.contains(mediaSeconds: .infinity))
        #expect(!spans.contains(mediaSeconds: 5, marginSeconds: -1))
        #expect(!spans.contains(mediaSeconds: 5, marginSeconds: .nan))
        #expect(!OwnInterfaceIntervals([]).contains(mediaSeconds: 0))
    }

    @Test("A span left open runs to the end of the recording")
    func openSpan() {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
        #expect(spans.contains(mediaSeconds: 0))
        #expect(!spans.contains(mediaSeconds: 30))
        #expect(!spans.contains(mediaSeconds: 58.999))
        #expect(spans.contains(mediaSeconds: 59))
        #expect(spans.contains(mediaSeconds: 1_860))
    }

    @Test("Any finite input becomes ordered, joined spans; unusable spans are dropped")
    func normalization() {
        let spans = OwnInterfaceIntervals([
            .init(startSeconds: 30, endSeconds: 40), .init(startSeconds: -5, endSeconds: 2),
            .init(startSeconds: 35, endSeconds: 50), .init(startSeconds: .nan, endSeconds: 3),
            .init(startSeconds: 70, endSeconds: 60), .init(startSeconds: 80, endSeconds: .infinity),
            .init(startSeconds: 50, endSeconds: 51)
        ])
        #expect(spans.intervals == [.init(startSeconds: -5, endSeconds: 2), .init(startSeconds: 30, endSeconds: 51)])
        let open = OwnInterfaceIntervals([.init(startSeconds: 5), .init(startSeconds: 9, endSeconds: 12)])
        #expect(open.intervals == [.init(startSeconds: 5)])
        let many = OwnInterfaceIntervals((0..<300).map { .init(startSeconds: Double($0) * 10, endSeconds: Double($0) * 10 + 1) })
        #expect(many.intervals.count == OwnInterfaceIntervals.maximumIntervals)
        #expect(many.intervals.last?.endSeconds == nil, "Beyond the limit the rest of the recording is excluded.")
        #expect(many.contains(mediaSeconds: 2_995))
    }

    @Test("The usual recording: it starts in MORE, another app is used, and it is stopped in MORE")
    func typicalRecording() {
        let clock = ManualClock(500)
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: clock.seconds)
        clock.advance(20)
        recorder.begin()
        clock.advance(3)
        let start = clock.seconds
        clock.advance(4)
        recorder.note(inFront: false, at: clock.seconds)
        clock.advance(56)
        recorder.note(inFront: true, at: clock.seconds)
        clock.advance(5)
        recorder.end()
        let spans = recorder.intervals(recordingStartedAt: start)
        #expect(spans?.intervals == [.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
    }

    @Test("A scene that stays in the background yields an empty value, not an unknown one")
    func neverInFront() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: false, at: 1)
        recorder.begin()
        recorder.end()
        #expect(recorder.intervals(recordingStartedAt: 2) == OwnInterfaceIntervals([]))
    }

    @Test("Without a reported scene state or a start reading nothing is established")
    func unknownStaysUnknown() {
        var silent = OwnInterfaceIntervalRecorder()
        silent.begin()
        #expect(silent.intervals(recordingStartedAt: 10) == nil)
        // A report that arrives only after the attempt began does not tell what came before.
        silent.note(inFront: false, at: 12)
        #expect(silent.intervals(recordingStartedAt: 10) == nil)

        var unaligned = OwnInterfaceIntervalRecorder()
        unaligned.note(inFront: true, at: 1)
        unaligned.begin()
        #expect(unaligned.intervals(recordingStartedAt: nil) == nil)
        #expect(unaligned.intervals(recordingStartedAt: .nan) == nil)
    }

    @Test("A scene change and the start callback may be delivered in either order")
    func orderIndependence() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: 0)
        recorder.begin()
        // The scene change at 105 is reported before the start reading of 100 is known.
        recorder.note(inFront: false, at: 105)
        #expect(recorder.intervals(recordingStartedAt: 100)?.intervals == [.init(startSeconds: 0, endSeconds: 5)])

        var early = OwnInterfaceIntervalRecorder()
        early.note(inFront: true, at: 0)
        early.begin()
        // MORE left the screen well before the start callback: no frame can show it.
        early.note(inFront: false, at: 90)
        let left = early.intervals(recordingStartedAt: 100)
        #expect(left?.intervals == [.init(startSeconds: -10, endSeconds: -10)])
        #expect(left?.contains(mediaSeconds: 0) == false)
        early.note(inFront: true, at: 99)
        early.note(inFront: false, at: 130)
        #expect(early.intervals(recordingStartedAt: 100)?.intervals
            == [.init(startSeconds: -10, endSeconds: -10), .init(startSeconds: -1, endSeconds: 30)])
    }

    @Test("A first frame slightly older than the start callback is still covered by the margin")
    func callbackLaterThanFirstFrame() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: 0)
        recorder.begin()
        // The movie begins at 100.0 showing MORE, MORE leaves at 100.2, the callback reads 100.4.
        recorder.note(inFront: false, at: 100.2)
        let spans = recorder.intervals(recordingStartedAt: 100.4)
        #expect(spans?.intervals.count == 1)
        #expect(spans?.contains(mediaSeconds: 0) == true)
        #expect(spans?.contains(mediaSeconds: 0.7) == true)
        #expect(spans?.contains(mediaSeconds: 0.9) == false)
    }

    @Test("Scene changes after capture ended do not alter the saved spans")
    func sealedAfterEnd() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: 0)
        recorder.begin()
        recorder.note(inFront: false, at: 14)
        recorder.note(inFront: true, at: 50)
        recorder.end()
        let sealed = recorder.intervals(recordingStartedAt: 10)
        recorder.note(inFront: false, at: 70)
        recorder.note(inFront: true, at: 90)
        #expect(recorder.intervals(recordingStartedAt: 10) == sealed)
        #expect(sealed?.intervals == [.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 40)])
        // The next attempt starts from the latest reported state, with none of these spans.
        recorder.begin()
        #expect(recorder.intervals(recordingStartedAt: 100)?.intervals == [.init(startSeconds: 0)])
    }

    @Test("A return to MORE reported just after capture stopped is kept, and costs at most the last second")
    func lateReturnIsKeptConservatively() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: 0)
        recorder.begin()
        recorder.note(inFront: false, at: 104)
        // Capture stops near 130.2 in another app; MORE's return is read at 130.5, before the file closes.
        recorder.note(inFront: true, at: 130.5)
        recorder.end()
        let spans = recorder.intervals(recordingStartedAt: 100)
        #expect(spans?.intervals == [.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 30.5)])
        #expect(spans?.contains(mediaSeconds: 29.3) == false, "Earlier frames of the other app stay eligible.")
        #expect(spans?.contains(mediaSeconds: 30.1) == true, "The report may be late, so the last frame is left out.")
    }

    @Test("An inactive scene is still in front: only the background ends a span")
    func inactiveDoesNotEndASpan() {
        // The app reports `scenePhase != .background`, so active and inactive both read true.
        enum Phase { case active, inactive, background
            var inFront: Bool { self != .background } }
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: Phase.active.inFront, at: 0)
        recorder.begin()
        // A system sheet covers MORE, then leaves; later the app switcher, then another app.
        recorder.note(inFront: Phase.inactive.inFront, at: 102)
        recorder.note(inFront: Phase.active.inFront, at: 103)
        recorder.note(inFront: Phase.inactive.inFront, at: 110)
        #expect(recorder.intervals(recordingStartedAt: 100)?.intervals == [.init(startSeconds: 0)])
        recorder.note(inFront: Phase.background.inFront, at: 111)
        // Returning passes through inactive first, and that already opens the next span.
        recorder.note(inFront: Phase.inactive.inFront, at: 150)
        recorder.note(inFront: Phase.active.inFront, at: 151)
        #expect(recorder.intervals(recordingStartedAt: 100)?.intervals
            == [.init(startSeconds: 0, endSeconds: 11), .init(startSeconds: 50)])
    }

    @Test("A change with an unusable reading leaves what follows unknown, so it is excluded")
    func nonFiniteReading() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: true, at: 0)
        recorder.begin()
        recorder.note(inFront: false, at: 104)
        // A visit to MORE whose start cannot be placed in time, then a valid return to another app.
        recorder.note(inFront: true, at: .nan)
        recorder.note(inFront: false, at: 140)
        let spans = recorder.intervals(recordingStartedAt: 100)
        // The visit began somewhere after 104, so everything from that last placed change is left out.
        #expect(spans?.intervals == [.init(startSeconds: 0)])
        #expect(spans?.contains(mediaSeconds: 20) == true)
        #expect(spans?.contains(mediaSeconds: 60) == true)
    }

    @Test("Repeated reports of one state add nothing, and lost reports exclude what follows")
    func repeatsAndOverflow() {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: false, at: 0)
        recorder.begin()
        recorder.note(inFront: false, at: 1)
        recorder.note(inFront: true, at: 2)
        recorder.note(inFront: true, at: 3)
        recorder.note(inFront: false, at: 4)
        #expect(recorder.intervals(recordingStartedAt: 0)?.intervals == [.init(startSeconds: 2, endSeconds: 4)])

        var busy = OwnInterfaceIntervalRecorder()
        busy.note(inFront: false, at: 0)
        busy.begin()
        for index in 0..<(OwnInterfaceIntervalRecorder.maximumTransitions + 4) {
            busy.note(inFront: index.isMultiple(of: 2), at: Double(index + 1))
        }
        let spans = busy.intervals(recordingStartedAt: 0)
        let lastKept = Double(OwnInterfaceIntervalRecorder.maximumTransitions)
        // The last kept report closed a span at `lastKept`; what follows is unknown, so it stays open.
        #expect(spans?.intervals.last == .init(startSeconds: lastKept - 1))
        #expect(spans?.intervals.count == OwnInterfaceIntervals.maximumIntervals - 1)
        #expect(spans?.contains(mediaSeconds: lastKept + 500) == true)
    }

    @Test("A recording context keeps its spans through encoding, and old data loads unchanged")
    func contextRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_728_000_123)
        let plain = try ObservationRecordingContext(startedAt: start, timeZoneIdentifier: "Europe/Paris")
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
        let marked = plain.withOwnInterfaceIntervals(spans)
        #expect(marked.id == plain.id && marked.startedAt == start && marked.ownInterfaceIntervals == spans)
        #expect(try JSONDecoder().decode(ObservationRecordingContext.self, from: JSONEncoder().encode(marked)) == marked)

        // A context without spans is written exactly as before this field existed.
        let encoded = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(plain)) as? [String: Any])
        #expect(Set(encoded.keys) == ["id", "startedAt", "timeZoneIdentifier"])
        let old = #"{"id":"\#(plain.id.uuidString)","startedAt":\#(start.timeIntervalSinceReferenceDate),"timeZoneIdentifier":"Europe/Paris"}"#
        #expect(try JSONDecoder().decode(ObservationRecordingContext.self, from: Data(old.utf8)) == plain)

        // Unreadable spans become unknown; the session's start is not lost with them.
        let damaged = old.dropLast() + #","ownInterfaceIntervals":{"intervals":"none"}}"#
        #expect(try JSONDecoder().decode(ObservationRecordingContext.self, from: Data(damaged.utf8)) == plain)
    }
}
