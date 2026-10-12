import Testing
@testable import MorningApple

/// Exercises the authoritative completion policy used by the native recorder.
/// These callback sequences are deterministic; they do not run ScreenCaptureKit.
@Suite("Recording finalization retention")
struct ScreenRecordingFinalizationTests {
    @Test("A deadline followed by successful writer completion retains the recording")
    func lateSuccessfulCloseRemainsRecoverable() {
        var state = ScreenRecordingFinalizationState()
        state.finalizationTimedOut()
        #expect(state.deadlineExceeded)
        #expect(state.disposition(streamStopped: true, startPending: false) == .waiting)
        #expect(!state.discardRequested && state.failureDetail == nil)

        state.writerDidFinish(error: nil)
        #expect(state.disposition(streamStopped: true, startPending: false) == .retain)
        // Retrying a deadline cannot turn an acknowledged success into a failure.
        state.finalizationTimedOut()
        #expect(state.disposition(streamStopped: true, startPending: false) == .retain)
    }

    @Test("Explicit discard or privacy cleanup wins over a late successful close",
          arguments: [true, false])
    func discardRemainsSticky(discardBeforeDeadline: Bool) {
        var state = ScreenRecordingFinalizationState()
        if discardBeforeDeadline { state.requestDiscard() }
        state.finalizationTimedOut()
        if !discardBeforeDeadline { state.requestDiscard() }
        #expect(state.disposition(streamStopped: true, startPending: false) == .waiting,
                "Do not remove a file while its writer still owns it.")
        state.writerDidFinish(error: nil)
        #expect(state.disposition(streamStopped: true, startPending: false) == .discard)
        #expect(state.failureDetail == nil, "The person's discard is not a writer error.")
    }

    @Test("Actual writer failure remains terminal even if a success callback follows",
          arguments: [true, false])
    func actualFailureCannotBeClearedByLateSuccess(failureBeforeDeadline: Bool) {
        var state = ScreenRecordingFinalizationState()
        if failureBeforeDeadline { state.writerDidFinish(error: "Synthetic writer failure") }
        state.finalizationTimedOut()
        if !failureBeforeDeadline { state.writerDidFinish(error: "Synthetic writer failure") }
        state.writerDidFinish(error: nil)
        #expect(state.failureDetail == "Synthetic writer failure")
        #expect(state.disposition(streamStopped: true, startPending: false) == .discard)
    }

    @Test("Writer completion alone never releases an unresolved stream or start",
          arguments: [true, false])
    func resourcesMustBeSettledBeforeAnyDisposition(discard: Bool) {
        var state = ScreenRecordingFinalizationState()
        if discard { state.requestDiscard() }
        state.finalizationTimedOut()
        state.writerDidFinish(error: nil)
        #expect(state.disposition(streamStopped: false, startPending: false) == .waiting)
        #expect(state.disposition(streamStopped: true, startPending: true) == .waiting)
        #expect(state.disposition(streamStopped: false, startPending: true) == .waiting)
        #expect(state.disposition(streamStopped: true, startPending: false) == (discard ? .discard : .retain))
    }

    @Test("A genuine start failure cannot be rescued by a finalization timeout or success")
    func startFailureIsNotDowngradedToSlowFinalization() {
        var state = ScreenRecordingFinalizationState()
        state.fail("Synthetic start failure")
        state.finalizationTimedOut()
        state.writerDidFinish(error: nil)
        #expect(state.failureDetail == "Synthetic start failure")
        #expect(state.disposition(streamStopped: true, startPending: false) == .discard)
    }
}
