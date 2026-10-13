import Foundation
import MorningCore
import Synchronization

/// One native attempt's callback-entry evidence, independent of MainActor delivery order.
/// The recording delegate writes synchronously before scheduling its UI/state task. Writer
/// finalization can therefore recover an already observed start even if its task runs first.
/// This never supplies a picker time, finish time, file date or a guessed missing start.
final class ScreenRecordingCallbackProvenance: Sendable {
    private struct State: Sendable {
        var outputID: ObjectIdentifier?
        var observedStart = false
        var context: ObservationRecordingContext?
        var monotonicStartSeconds: Double?
        var isClosed = false
    }

    private let sessionID: UUID
    private let state = Mutex(State())

    init(sessionID: UUID) { self.sessionID = sessionID }

    /// Bind before adding the writer to the stream. A delegate cannot accept a callback
    /// from a different output or be repurposed for another capture after finalization.
    func bind(outputID: ObjectIdentifier) {
        state.withLock { value in
            guard !value.isClosed, value.outputID == nil else { return }
            value.outputID = outputID
        }
    }

    /// `monotonicStartSeconds` is read from the clock that also times scene changes. Without
    /// it the start cannot be aligned with them, and no own-interface span is recorded.
    func recordingDidStart(outputID: ObjectIdentifier, startedAt: Date, timeZoneIdentifier: String,
                           monotonicStartSeconds: Double? = nil) {
        state.withLock { value in
            guard !value.isClosed, value.outputID == outputID, !value.observedStart else { return }
            value.observedStart = true
            value.monotonicStartSeconds = monotonicStartSeconds
            // The first matching callback remains the source even if its metadata is invalid.
            // A duplicate callback must not invent a later replacement wall-clock instant.
            value.context = try? ObservationRecordingContext(id: sessionID, startedAt: startedAt,
                                                             timeZoneIdentifier: timeZoneIdentifier)
        }
    }

    /// Called by MainActor lifecycle handling, including immediately before resource release.
    /// Returns whether a writer-start callback was observed, independently of date validity.
    /// Closing snapshots and rejects future callbacks under one lock, so finalization cannot
    /// lose an observed start in a gap between its last read and delegate cleanup.
    @discardableResult
    func reconcile(into provenance: inout ScreenRecordingContextState,
                   sessionID requestedSessionID: UUID, outputID: ObjectIdentifier,
                   closing: Bool = false) -> Bool {
        guard requestedSessionID == sessionID else { return false }
        let snapshot = state.withLock { value -> (Bool, ObservationRecordingContext?, Double?) in
            guard !value.isClosed, value.outputID == outputID else { return (false, nil, nil) }
            let snapshot = (value.observedStart, value.context, value.monotonicStartSeconds)
            if closing {
                value.isClosed = true
                value.outputID = nil
                value.observedStart = false
                value.context = nil
                value.monotonicStartSeconds = nil
            }
            return snapshot
        }
        if let context = snapshot.1 {
            provenance.recordingDidStart(sessionID: context.id, startedAt: context.startedAt,
                                          timeZoneIdentifier: context.timeZoneIdentifier,
                                          monotonicStartSeconds: snapshot.2)
        }
        return snapshot.0
    }

    /// Resource cleanup closes this attempt permanently; late callbacks cannot repopulate it.
    /// The main-actor provenance keeps an accepted context until handoff/discard separately.
    func invalidate() {
        state.withLock { value in
            value.isClosed = true
            value.outputID = nil
            value.observedStart = false
            value.context = nil
            value.monotonicStartSeconds = nil
        }
    }
}
