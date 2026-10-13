import Foundation
import MorningCore

public enum SegmentedSessionEvidenceError: Error, Sendable, Equatable {
    /// The segment is not sealed, or its session's start cannot date an observation.
    case segmentNotAnalysable
    /// The extraction holds more frames or text than the segment's share of the session.
    case budgetExceeded
    /// The extraction is longer than the segment, or holds a frame past its end: it was
    /// not made from this segment's file.
    case evidenceOutsideSegment
    /// No sampled frame could be decoded and read. Nothing is known about the segment:
    /// that is a failure to retry, not a segment without readable text.
    case noFrameCouldBeRead
    /// A frame held text that the extraction dropped to stay within its limits. The
    /// segment did show something, so it is not a segment without readable text.
    case textWasOmitted
}

/// What the extraction of one segment's file amounts to.
public enum RecordingSegmentEvidenceOutcome: Sendable, Equatable {
    /// At least one frame held text: save this observation, then record its derivation.
    case observation(ObservationAcquisition)
    /// Frames were read and none held text (a lock screen, a photo, a dark app). There is
    /// nothing to save in the archive; record this derivation and the raw file can go.
    case noReadableText(RecordingSegmentDerivation)
}

/// Everything the analysis of one sealed segment needs, and nothing about other segments.
public struct RecordingSegmentWork: Sendable, Equatable {
    public let sessionID: UUID
    public let segment: RecordingSegment
    public let fileURL: URL
    public let fingerprint: ObservationFileFingerprint
    public let reference: ObservationSessionSegmentReference
    /// The segment's own context: its spans are in this file's media time.
    public let recordingContext: ObservationRecordingContext
    /// The session's start, for every segment: a session that crosses midnight stays one day.
    public let observedDate: ObservationObservedDate
    public let maximumFrames: Int
    public let maximumTextCharacters: Int
    /// The segment's length on the session's clock plus the policy's timing tolerance.
    public let maximumMediaSeconds: Double
}

/// How a segmented session reaches the existing archive, review and proposal code.
///
/// **One observation per segment, linked by `sessionSegment`.** Everything those types key
/// on belongs to one file: an observation holds one file digest, one extraction of at most
/// 24 frames and 31 minutes whose frame times count from that file's first frame, and one
/// recording context whose spans are compared with those frame times. Reviews, citations
/// and omissions are keyed by observation and frame. A segment is exactly one such file,
/// so it becomes one observation with no existing limit or format changed. A session kept
/// as a single observation would need a second time base and larger limits throughout.
/// It also matches what review already says about separate files: they are shown apart and
/// never joined into one timeline, which is right while a gap at each rollover is unmeasured.
///
/// What this costs today, with the existing limits unchanged: each segment uses one of the
/// archive's 60 entries, one proposal takes at most five observations (25 minutes of one
/// session), and a day holding several segments is excluded from the comparable-morning
/// profile as a day with more than one recording. The reference is what lets those counts
/// become per session later.
///
/// **Condition before the app may create a session:** archive capacity, the
/// five-observation selection and the comparable-morning profile must first count
/// sessions, not segments. Until then a segmented morning can never be a comparable
/// morning, and the fourth one would overflow the 60-entry archive. Nothing in the app
/// creates a session today.
public enum SegmentedSessionEvidence {
    public static func work(forSegment index: Int, in manifest: RecordingSessionManifest,
                            store: RecordingSessionStore) throws -> RecordingSegmentWork {
        guard manifest.segments.indices.contains(index),
              let fingerprint = manifest.segments[index].fingerprint,
              let reference = manifest.reference(forSegment: index),
              let context = manifest.recordingContext(forSegment: index),
              let observedDate = try? ObservationObservedDate(date: manifest.context.startedAt,
                  timeZoneIdentifier: manifest.context.timeZoneIdentifier, provenance: .recordingSession) else {
            throw SegmentedSessionEvidenceError.segmentNotAnalysable
        }
        return RecordingSegmentWork(sessionID: manifest.id, segment: manifest.segments[index],
            fileURL: store.segmentURL(sessionID: manifest.id, index: index), fingerprint: fingerprint,
            reference: reference, recordingContext: context, observedDate: observedDate,
            maximumFrames: manifest.frameBudgetForNextAnalysis,
            maximumTextCharacters: manifest.textCharacterBudgetForNextAnalysis,
            maximumMediaSeconds: reference.endSeconds - reference.startSeconds
                + manifest.policy.segmentTimingToleranceSeconds)
    }

    /// Decides what an extraction is: an observation to save, or a segment whose frames
    /// were read and held no text. The second is a result in its own right. It must not be
    /// turned into a failure, which would keep the raw file and report the range as missing.
    /// The same frame, text and time bounds apply to both.
    public static func outcome(for work: RecordingSegmentWork, evidence: ObservationVideoEvidence,
                               origin: ObservationAcquisitionOrigin, sourceLabel: String,
                               importedAt: Date) throws -> RecordingSegmentEvidenceOutcome {
        if evidence.hasRecognizedText {
            return .observation(try acquisition(for: work, evidence: evidence, origin: origin,
                                                sourceLabel: sourceLabel, importedAt: importedAt))
        }
        try checkBounds(of: evidence, for: work)
        // Only frames read as blank support this result. A frame marked observed here has
        // no text left because it was cut, and releasing its raw file would lose it.
        guard !evidence.frames.contains(where: { $0.outcome == .observed || $0.textWasTruncated }) else {
            throw SegmentedSessionEvidenceError.textWasOmitted
        }
        guard evidence.frames.contains(where: { $0.outcome == .blank }) else {
            throw SegmentedSessionEvidenceError.noFrameCouldBeRead
        }
        return .noReadableText(.init(acquisitionID: nil, sampledFrameCount: evidence.frames.count,
                                     textCharacterCount: 0, analysedAt: importedAt))
    }

    /// The observation for one segment, from the extraction of its file. Its identity is the
    /// segment's, its day is the session's, and its text is the extraction's own rendering.
    /// Evidence with no recognized text has no observation: use `outcome(for:)`.
    public static func acquisition(for work: RecordingSegmentWork, evidence: ObservationVideoEvidence,
                                   origin: ObservationAcquisitionOrigin, sourceLabel: String,
                                   importedAt: Date) throws -> ObservationAcquisition {
        try checkBounds(of: evidence, for: work)
        return try ObservationAcquisition(id: work.segment.id, importedAt: importedAt,
            fileSHA256: work.fingerprint.sha256, observedDate: work.observedDate, origin: origin,
            sourceKind: .video, sourceLabel: sourceLabel, originalText: evidence.renderedText,
            videoEvidence: evidence, recordingContext: work.recordingContext, sessionSegment: work.reference)
    }

    private static func checkBounds(of evidence: ObservationVideoEvidence, for work: RecordingSegmentWork) throws {
        guard evidence.frames.count <= work.maximumFrames,
              evidence.frames.reduce(0, { $0 + $1.text.count }) <= work.maximumTextCharacters else {
            throw SegmentedSessionEvidenceError.budgetExceeded
        }
        // A frame past the segment's end would be compared with spans that were never
        // carried that far, and would have no place on the session's clock.
        guard evidence.durationSeconds <= work.maximumMediaSeconds,
              evidence.frames.allSatisfy({ $0.timeSeconds <= work.maximumMediaSeconds }) else {
            throw SegmentedSessionEvidenceError.evidenceOutsideSegment
        }
    }

    /// Describe the entry the archive actually holds: `ObservationArchive.insert` returns an
    /// existing entry's identifier when the same file bytes were saved before.
    public static func derivation(of acquisition: ObservationAcquisition, analysedAt: Date) -> RecordingSegmentDerivation {
        let frames = acquisition.videoEvidence?.frames ?? []
        return .init(acquisitionID: acquisition.id, sampledFrameCount: frames.count,
                     textCharacterCount: frames.reduce(0) { $0 + $1.text.count }, analysedAt: analysedAt)
    }

    /// The derivation of a segment whose observation is already in the archive: the same
    /// session, index and file bytes. Used on resume, so a segment saved just before an
    /// interruption is recorded as analysed without being analysed or counted again.
    public static func savedDerivation(for work: RecordingSegmentWork, in archive: ObservationArchive,
                                       analysedAt: Date) -> RecordingSegmentDerivation? {
        guard let entry = archive.entries.first(where: {
            $0.sessionSegment?.sessionID == work.sessionID
                && $0.sessionSegment?.segmentIndex == work.reference.segmentIndex
                && $0.fileSHA256 == work.fingerprint.sha256
        }) else { return nil }
        return derivation(of: entry, analysedAt: entry.importedAt ?? analysedAt)
    }
}

/// Analyses a session one sealed segment at a time, in order, saving the manifest after
/// each. It can stop at any point and be run again.
public enum SegmentedSessionAnalysis {
    public struct Result: Sendable, Equatable {
        /// The manifest as last saved.
        public let manifest: RecordingSessionManifest
        /// Analysed by this run.
        public let analysedSegments: [Int]
        /// Found already saved by an earlier, interrupted run. Not analysed again.
        public let recoveredSegments: [Int]
        public let failedSegments: [Int]
        /// Given up because the raw file was gone or no longer the sealed bytes.
        public let discardedSegments: [Int]
        public let stoppedByCancellation: Bool
        /// Which time ranges are analysed, waiting or missing. Never read a missing range as
        /// a range with no activity.
        public var coverage: RecordingSessionCoverage { manifest.coverage }
    }

    /// - Parameters:
    ///   - savedDerivation: looks the segment up in the saved archive. Non-nil means its
    ///     derived text is already durable.
    ///   - analyse: extracts the segment and returns **only after its derived text is
    ///     durably saved**. Build its result with `SegmentedSessionEvidence.outcome`: a
    ///     segment whose frames held no text returns that derivation with nothing to save. Until it returns, the segment stays sealed and its raw file stays.
    ///     A thrown error fails this segment alone; the next one is still analysed.
    ///
    /// Cancellation stops before the next segment. A segment whose `analyse` already
    /// returned is still recorded, since its text is saved. Whatever happens, the manifest
    /// on disk describes exactly the steps that completed.
    public static func run(
        sessionID: UUID, store: RecordingSessionStore,
        fingerprints: ObservationFileFingerprintService = ObservationFileFingerprintService(),
        now: @Sendable () -> Date = { Date() },
        progress: (@Sendable (_ settledSegments: Int, _ totalSegments: Int) async -> Void)? = nil,
        savedDerivation: @Sendable (RecordingSegmentWork) async throws -> RecordingSegmentDerivation?,
        analyse: @Sendable (RecordingSegmentWork) async throws -> RecordingSegmentDerivation
    ) async throws -> Result {
        // An earlier run may have stopped between recording a segment and releasing its file.
        var manifest = try store.releaseExpiredRaw(sessionID: sessionID, now: now())
        let queue = manifest.segmentsAwaitingAnalysis.map(\.index)
        var analysed: [Int] = [], recovered: [Int] = [], failed: [Int] = [], discarded: [Int] = []
        var cancelled = false
        await progress?(0, queue.count)
        for (position, index) in queue.enumerated() {
            if Task.isCancelled { cancelled = true; break }
            let work = try SegmentedSessionEvidence.work(forSegment: index, in: manifest, store: store)

            // The file must still be the bytes that were sealed before anything is derived from it.
            let identity: Identity
            do {
                identity = try await fingerprints.fingerprint(of: work.fileURL) == work.fingerprint ? .same : .changed
            } catch is CancellationError {
                cancelled = true; break
            } catch ObservationFileFingerprintError.unreadableFile {
                identity = .missing
            } catch ObservationFileFingerprintError.fileChanged {
                identity = .unstable
            } catch {
                identity = .changed
            }
            if Task.isCancelled { cancelled = true; break }
            switch identity {
            case .same: break
            case .unstable:
                try manifest.markFailed(index: index, reason: .extractionFailed, at: now())
                try store.save(manifest)
                failed.append(index)
            case .missing, .changed:
                manifest = try store.discardSegment(sessionID: sessionID, index: index,
                    reason: identity == .missing ? .rawMediaMissing : .rawMediaChanged)
                discarded.append(index)
            }
            guard identity == .same else { await progress?(position + 1, queue.count); continue }

            var derivation: RecordingSegmentDerivation?
            var wasSavedEarlier = false
            var failureReason = RecordingSegmentFailureReason.extractionFailed
            if let saved = try await savedDerivation(work) {
                derivation = saved
                wasSavedEarlier = true
            } else {
                do {
                    derivation = try await analyse(work)
                } catch {
                    // Cancellation is not a failure of this segment: it stays sealed.
                    if error is CancellationError || Task.isCancelled { cancelled = true; break }
                    // A full archive is not a fault of this segment's file: say so, so the
                    // person can be told to make room instead of seeing an extraction error.
                    if let full = error as? ObservationArchiveError, full == .archiveFull || full == .archiveTooLarge {
                        failureReason = .archiveFull
                    }
                }
            }
            if let derivation {
                do {
                    try manifest.markAnalysed(index: index, derivation: derivation)
                    if wasSavedEarlier { recovered.append(index) } else { analysed.append(index) }
                } catch {
                    try manifest.markFailed(index: index, reason: .derivedEvidenceRejected, at: now())
                    failed.append(index)
                }
            } else {
                try manifest.markFailed(index: index, reason: failureReason, at: now())
                failed.append(index)
            }
            try store.save(manifest)
            // Only now, with the derived text saved and recorded, may the raw file go.
            manifest = try store.releaseExpiredRaw(sessionID: sessionID, now: now())
            await progress?(position + 1, queue.count)
        }
        return Result(manifest: manifest, analysedSegments: analysed, recoveredSegments: recovered,
                      failedSegments: failed, discardedSegments: discarded,
                      stoppedByCancellation: cancelled)
    }

    private enum Identity { case same, changed, missing, unstable }
}
