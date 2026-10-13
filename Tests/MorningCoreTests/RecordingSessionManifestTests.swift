import Foundation
import Testing
@testable import MorningCore

private let mebibyte = SegmentedRecordingPolicy.mebibyte

private func fingerprint(_ number: Int, bytes: Int64 = 1_000) throws -> ObservationFileFingerprint {
    try ObservationFileFingerprint(sha256: String(format: "%064x", number), byteCount: bytes)
}

private func sessionContext(intervals: OwnInterfaceIntervals? = nil) throws -> ObservationRecordingContext {
    try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_791_000_000),
                                    timeZoneIdentifier: "Europe/Paris", ownInterfaceIntervals: intervals)
}

/// A session of sealed segments with the given bounds, on the session's clock.
private func sealedSession(_ ranges: [(Double, Double)], policy: SegmentedRecordingPolicy = .provisional,
                           intervals: OwnInterfaceIntervals? = nil) throws -> RecordingSessionManifest {
    var manifest = RecordingSessionManifest(context: try sessionContext(intervals: intervals), policy: policy)
    for (number, range) in ranges.enumerated() {
        try manifest.beginSegment(startSeconds: range.0)
        try manifest.sealOpenSegment(endSeconds: range.1, fingerprint: fingerprint(number + 1))
    }
    return manifest
}

private func derivation(frames: Int = 12, characters: Int = 400, acquisition: UUID? = UUID(),
                        at date: Date = Date(timeIntervalSince1970: 1_791_010_000)) -> RecordingSegmentDerivation {
    .init(acquisitionID: acquisition, sampledFrameCount: frames, textCharacterCount: characters, analysedAt: date)
}

private func decodeEdited(_ manifest: RecordingSessionManifest,
                          _ edit: (inout [String: Any]) -> Void) throws -> RecordingSessionManifest {
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any])
    edit(&object)
    return try JSONDecoder().decode(RecordingSessionManifest.self,
                                    from: JSONSerialization.data(withJSONObject: object))
}

private func editSegment(_ object: inout [String: Any], _ index: Int, _ edit: (inout [String: Any]) -> Void) {
    var segments = object["segments"] as! [[String: Any]]
    edit(&segments[index])
    object["segments"] = segments
}

@Suite("Segmented recording policy")
struct SegmentedRecordingPolicyTests {
    @Test("The provisional policy is 5 minutes or 64 MiB per segment, 90 minutes per session")
    func provisionalNumbers() {
        let policy = SegmentedRecordingPolicy.provisional
        #expect(policy.identifier == "provisional-2026-10-13")
        #expect(policy.maximumSegmentDurationSeconds == 300)
        #expect(policy.maximumSegmentBytes == 64 * mebibyte)
        #expect(policy.maximumSessionDurationSeconds == 5_400)
        #expect(policy.maximumSegmentCount == 18)
        #expect(policy.segmentTimingToleranceSeconds == 2)
        #expect(policy.framesPerSegment == 12)
        #expect(policy.maximumSessionFrames == 18 * 12)
        #expect(policy.maximumSessionTextCharacters == 180_000)
        #expect(policy.textCharactersPerSegment == 10_000)
        #expect(policy.analysedRawRetentionSeconds == 0)
    }

    @Test("Worst-case disk use of a 90-minute session")
    func storageNumbers() throws {
        let estimate = SegmentedRecordingPolicy.provisional.storageEstimate
        #expect(estimate.maximumSegmentCount == 18)
        #expect(estimate.worstCaseSegmentBytes == 68 * mebibyte)
        #expect(estimate.worstCaseRawBytesIfNothingIsReleased == 1_224 * mebibyte)
        // The provisional backlog limit lets the whole session wait for analysis.
        #expect(estimate.worstCaseRawBytesWithinBacklogLimit == 1_224 * mebibyte)
        #expect(estimate.manifestBytesAllowance == 2 * mebibyte)
        #expect(estimate.freeBytesNeededToStartASegment == 324 * mebibyte)
        #expect(estimate.freeBytesNeededForAWholeSession == 1_482 * mebibyte)

        // If the pilot shows analysis keeps pace, a backlog of two bounds the peak.
        let paced = try policy(maximumUnreleasedRawSegments: 2).storageEstimate
        #expect(paced.worstCaseRawBytesWithinBacklogLimit == 204 * mebibyte)
        #expect(paced.worstCaseRawBytesIfNothingIsReleased == 1_224 * mebibyte)
    }

    @Test("A policy cannot ask for a segment the existing import path would refuse")
    func refusesValuesBeyondExistingLimits() {
        #expect(throws: SegmentedRecordingPolicyError.invalidPolicy) { try policy(segmentSeconds: 32 * 60) }
        #expect(throws: SegmentedRecordingPolicyError.invalidPolicy) { try policy(framesPerSegment: 25) }
        #expect(throws: SegmentedRecordingPolicyError.invalidPolicy) { try policy(segmentBytes: 513 * mebibyte) }
        #expect(throws: SegmentedRecordingPolicyError.invalidPolicy) { try policy(sessionSeconds: 60) }
    }

    @Test func surviveEncoding() throws {
        let data = try JSONEncoder().encode(SegmentedRecordingPolicy.provisional)
        #expect(try JSONDecoder().decode(SegmentedRecordingPolicy.self, from: data) == .provisional)
    }
}

private func policy(segmentSeconds: Double = 300, segmentBytes: Int64 = 64 * mebibyte, sessionSeconds: Double = 5_400,
                    framesPerSegment: Int = 12, maximumUnreleasedRawSegments: Int = 18,
                    retentionSeconds: Double = 0) throws -> SegmentedRecordingPolicy {
    try SegmentedRecordingPolicy(identifier: "test", maximumSegmentDurationSeconds: segmentSeconds,
        maximumSegmentBytes: segmentBytes, segmentByteOvershootAllowance: 4 * mebibyte,
        maximumSessionDurationSeconds: sessionSeconds, segmentTimingToleranceSeconds: 2,
        framesPerSegment: framesPerSegment,
        maximumSessionFrames: 216, maximumSessionTextCharacters: 180_000,
        maximumUnreleasedRawSegments: maximumUnreleasedRawSegments, minimumFreeBytesReserve: 256 * mebibyte,
        analysedRawRetentionSeconds: retentionSeconds, maximumAnalysisAttempts: 3)
}

@Suite("Recording session manifest")
struct RecordingSessionManifestTests {
    @Test("A segment is sealed before the next one starts")
    func sealedBeforeNext() throws {
        var manifest = RecordingSessionManifest(context: try sessionContext())
        try manifest.beginSegment(startSeconds: 0)
        #expect(throws: RecordingSessionManifestError.segmentStillOpen(0)) {
            try manifest.beginSegment(startSeconds: 300)
        }
        #expect(manifest.segments.count == 1)
        try manifest.sealOpenSegment(endSeconds: 300, fingerprint: fingerprint(1))
        let next = try manifest.beginSegment(startSeconds: 300)
        #expect(next.index == 1)
        #expect(manifest.segments.map(\.state) == [.sealed, .writing])
        #expect(throws: RecordingSessionManifestError.noOpenSegment) {
            var sealed = try sealedSession([(0, 300)])
            try sealed.sealOpenSegment(endSeconds: 400, fingerprint: fingerprint(9))
        }
    }

    @Test("A segment rolls over on duration or size, whichever comes first")
    func rollover() throws {
        var manifest = RecordingSessionManifest(context: try sessionContext())
        #expect(!manifest.shouldSealOpenSegment(atSeconds: 400, writtenBytes: 0), "Nothing is open.")
        try manifest.beginSegment(startSeconds: 10)
        #expect(!manifest.shouldSealOpenSegment(atSeconds: 309.9, writtenBytes: 64 * mebibyte - 1))
        #expect(manifest.shouldSealOpenSegment(atSeconds: 310, writtenBytes: 0))
        #expect(manifest.shouldSealOpenSegment(atSeconds: 20, writtenBytes: 64 * mebibyte))
    }

    @Test("The next segment starts only within the session, backlog and storage limits")
    func admission() throws {
        let needed = 324 * mebibyte
        var manifest = RecordingSessionManifest(context: try sessionContext())
        #expect(manifest.admission(atSeconds: 0, freeBytes: needed)
                == .start(maximumDurationSeconds: 300, maximumBytes: 64 * mebibyte))
        #expect(manifest.admission(atSeconds: 0, freeBytes: needed - 1) == .stop(.storageReserve))
        #expect(manifest.admission(atSeconds: 0, freeBytes: nil) == .stop(.freeSpaceUnknown))
        #expect(manifest.admission(atSeconds: 5_300, freeBytes: needed)
                == .start(maximumDurationSeconds: 100, maximumBytes: 64 * mebibyte))
        #expect(manifest.admission(atSeconds: 5_400, freeBytes: needed) == .stop(.sessionDurationLimit))
        try manifest.beginSegment(startSeconds: 0)
        #expect(manifest.admission(atSeconds: 10, freeBytes: needed) == .sealFirst(index: 0))

        // Segments sealed early on size still count: eighteen is the bound on bytes.
        let full = try sealedSession((0..<18).map { (Double($0) * 10, Double($0) * 10 + 10) })
        #expect(full.admission(atSeconds: 180, freeBytes: needed) == .stop(.segmentCountLimit))
        var overfull = full
        #expect(throws: RecordingSessionManifestError.sessionLimitReached) {
            try overfull.beginSegment(startSeconds: 180)
        }

        let paced = try sealedSession([(0, 300), (300, 600)], policy: policy(maximumUnreleasedRawSegments: 2))
        #expect(paced.admission(atSeconds: 600, freeBytes: needed) == .stop(.analysisBacklog))
        var released = paced
        try released.markAnalysed(index: 0, derivation: derivation())
        try released.expireRaw(index: 0)
        #expect(released.admission(atSeconds: 600, freeBytes: needed)
                == .start(maximumDurationSeconds: 300, maximumBytes: 64 * mebibyte))

        var ended = try sealedSession([(0, 300)])
        try ended.end(reason: .stoppedByPerson, atSeconds: 300)
        #expect(ended.admission(atSeconds: 300, freeBytes: needed) == .stop(.stoppedByPerson))
        #expect(throws: RecordingSessionManifestError.sessionEnded) { try ended.beginSegment(startSeconds: 300) }
    }

    @Test("A session cannot end while a segment is open, except by interruption")
    func ending() throws {
        var manifest = RecordingSessionManifest(context: try sessionContext())
        try manifest.beginSegment(startSeconds: 0)
        #expect(throws: RecordingSessionManifestError.invalidSessionEnd) {
            try manifest.end(reason: .stoppedByPerson, atSeconds: 120)
        }
        #expect(manifest.isOpen)
        try manifest.end(reason: .interrupted, atSeconds: nil)
        #expect(!manifest.isOpen)
        // Recovery may still seal the file the writer had completed.
        try manifest.sealOpenSegment(endSeconds: 120, fingerprint: fingerprint(1))
        #expect(manifest.segments[0].state == .sealed)
    }

    @Test("A manifest survives encoding unchanged")
    func roundTrip() throws {
        var manifest = try sealedSession([(0, 300), (300, 600), (600, 900)],
            intervals: OwnInterfaceIntervals([.init(startSeconds: 12, endSeconds: 40)]))
        try manifest.markAnalysed(index: 0, derivation: derivation())
        try manifest.expireRaw(index: 0)
        try manifest.markFailed(index: 1, reason: .extractionFailed, at: Date(timeIntervalSince1970: 1_791_020_000))
        try manifest.beginSegment(startSeconds: 900)
        let decoded = try JSONDecoder().decode(RecordingSessionManifest.self, from: JSONEncoder().encode(manifest))
        #expect(decoded == manifest)
        #expect(decoded.formatVersion == 1)
        #expect(decoded.policy == .provisional)
    }

    @Test("Decoding refuses an unknown version, gaps, repeats, overlaps and backwards ranges")
    func decodingFailsClosed() throws {
        let manifest = try sealedSession([(0, 300), (300, 600), (600, 900)])
        typealias Failure = RecordingSessionManifestError
        #expect(throws: Failure.unsupportedVersion(2)) { try decodeEdited(manifest) { $0["formatVersion"] = 2 } }
        #expect(throws: Failure.segmentIndexGap(expected: 1, found: 2)) {
            try decodeEdited(manifest) { object in
                var segments = object["segments"] as! [[String: Any]]
                segments.remove(at: 1)
                object["segments"] = segments
            }
        }
        #expect(throws: Failure.duplicateSegmentIndex(0)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["index"] = 0 } }
        }
        #expect(throws: Failure.segmentIndexGap(expected: 0, found: -1)) {
            try decodeEdited(manifest) { editSegment(&$0, 0) { $0["index"] = -1 } }
        }
        #expect(throws: Failure.overlappingTimeRanges(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["startSeconds"] = 299.5 } }
        }
        #expect(throws: Failure.invalidTimeRange(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["endSeconds"] = 300 } }
        }
        #expect(throws: Failure.invalidTimeRange(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["endSeconds"] = 250 } }
        }
        #expect(throws: Failure.invalidTimeRange(0)) {
            try decodeEdited(manifest) { editSegment(&$0, 0) { $0["startSeconds"] = -1 } }
        }
        #expect(throws: Failure.invalidTimeRange(2)) {
            try decodeEdited(manifest) { editSegment(&$0, 2) { $0["startSeconds"] = 5_400; $0["endSeconds"] = 5_500 } }
        }
        #expect(throws: Failure.duplicateSegmentIdentity(2)) {
            try decodeEdited(manifest) { object in
                let first = (object["segments"] as! [[String: Any]])[0]["id"]!
                editSegment(&object, 2) { $0["id"] = first }
            }
        }
        #expect(throws: Failure.duplicateFile(2)) {
            try decodeEdited(manifest) { object in
                let first = (object["segments"] as! [[String: Any]])[0]["fingerprint"]!
                editSegment(&object, 2) { $0["fingerprint"] = first }
            }
        }
        // An open segment that is not the last would mean a segment started before the one ahead was sealed.
        #expect(throws: Failure.unknownEndBeforeLastSegment(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) {
                $0["state"] = "writing"; $0["endSeconds"] = nil; $0["fingerprint"] = nil
            } }
        }
        #expect(throws: Failure.inconsistentSegment(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["fingerprint"] = nil } }
        }
        #expect(throws: Failure.inconsistentSegment(1)) {
            try decodeEdited(manifest) { editSegment(&$0, 1) { $0["state"] = "analysed" } }
        }
        #expect(throws: Failure.invalidSessionEnd) {
            try decodeEdited(manifest) { $0["endReason"] = "stoppedByPerson"; $0["endedAtSeconds"] = 100 }
        }
        #expect(throws: (any Error).self) { try decodeEdited(manifest) { editSegment(&$0, 1) { $0["state"] = "paused" } } }
    }

    @Test("A refused change leaves the manifest as it was")
    func refusedChangesAreNotApplied() throws {
        var manifest = try sealedSession([(0, 300), (300, 600)])
        let before = manifest
        #expect(throws: RecordingSessionManifestError.overlappingTimeRanges(2)) {
            try manifest.beginSegment(startSeconds: 599)
        }
        #expect(throws: RecordingSessionManifestError.unknownSegment(7)) {
            try manifest.markAnalysed(index: 7, derivation: derivation())
        }
        #expect(throws: RecordingSessionManifestError.budgetExceeded(0)) {
            try manifest.markAnalysed(index: 0, derivation: derivation(frames: 13))
        }
        #expect(throws: RecordingSessionManifestError.budgetExceeded(0)) {
            try manifest.markAnalysed(index: 0, derivation: derivation(characters: 10_001))
        }
        #expect(throws: RecordingSessionManifestError.invalidTransition(index: 0, from: .sealed)) {
            try manifest.expireRaw(index: 0)
        }
        // "Analysed" must describe a real sampling: frames were read, and text and an
        // archive entry come together or not at all.
        #expect(throws: RecordingSessionManifestError.inconsistentSegment(0)) {
            try manifest.markAnalysed(index: 0, derivation: derivation(frames: 0, characters: 0, acquisition: nil))
        }
        #expect(throws: RecordingSessionManifestError.inconsistentSegment(0)) {
            try manifest.markAnalysed(index: 0, derivation: derivation(characters: 400, acquisition: nil))
        }
        #expect(throws: RecordingSessionManifestError.inconsistentSegment(0)) {
            try manifest.markAnalysed(index: 0, derivation: derivation(characters: 0))
        }
        try manifest.beginSegment(startSeconds: 600)
        #expect(throws: RecordingSessionManifestError.invalidTransition(index: 2, from: .writing)) {
            try manifest.markAnalysed(index: 2, derivation: derivation())
        }
        #expect(throws: RecordingSessionManifestError.invalidTimeRange(2)) {
            try manifest.sealOpenSegment(endSeconds: 600, fingerprint: fingerprint(3))
        }
        #expect(throws: RecordingSessionManifestError.duplicateFile(2)) {
            try manifest.sealOpenSegment(endSeconds: 900, fingerprint: fingerprint(1))
        }
        #expect(manifest.segments.dropLast() == before.segments[...])
        #expect(manifest.segments[2].state == .writing)
    }

    @Test("A failed segment is reported as a missing range and the rest stays analysed")
    func coverageNamesMissingRanges() throws {
        var manifest = try sealedSession([(0, 300), (300, 600), (600, 900), (905, 1_200)])
        let acquisition = UUID()
        try manifest.markAnalysed(index: 0, derivation: derivation(acquisition: acquisition))
        try manifest.markFailed(index: 1, reason: .extractionFailed, at: Date(timeIntervalSince1970: 1_791_020_000))
        // Sampled, and no frame held readable text: a result, not a gap.
        try manifest.markAnalysed(index: 2, derivation: derivation(characters: 0, acquisition: nil))
        try manifest.end(reason: .stoppedByPerson, atSeconds: 1_210)

        let coverage = manifest.coverage
        #expect(coverage.analysed == [
            .init(segmentIndex: 0, range: .init(startSeconds: 0, endSeconds: 300), acquisitionID: acquisition),
            .init(segmentIndex: 2, range: .init(startSeconds: 600, endSeconds: 900), acquisitionID: nil)
        ])
        #expect(coverage.analysed.map(\.hasReadableText) == [true, false])
        #expect(coverage.waiting == [
            .init(segmentIndex: 3, range: .init(startSeconds: 905, endSeconds: 1_200), isBeingWritten: false)
        ])
        #expect(coverage.missing == [
            .init(segmentIndex: 1, range: .init(startSeconds: 300, endSeconds: 600), reason: .analysisFailed, canRetry: true),
            .init(segmentIndex: nil, range: .init(startSeconds: 900, endSeconds: 905), reason: .notCaptured, canRetry: false),
            .init(segmentIndex: nil, range: .init(startSeconds: 1_200, endSeconds: 1_210), reason: .notCaptured, canRetry: false)
        ])
        #expect(!coverage.isComplete)
        #expect(coverage.analysedSeconds == 600)
        #expect(coverage.missingSeconds == 315)
        // The failed segment did not change what its neighbours hold.
        #expect(manifest.segments.map(\.state) == [.analysed, .failed, .analysed, .sealed])
    }

    @Test("A failed segment is retried a bounded number of times")
    func boundedRetries() throws {
        var manifest = try sealedSession([(0, 300), (300, 600)])
        let date = Date(timeIntervalSince1970: 1_791_020_000)
        for attempt in 1...3 {
            #expect(manifest.segmentsAwaitingAnalysis.map(\.index) == [0, 1])
            try manifest.markFailed(index: 0, reason: .extractionFailed, at: date)
            #expect(manifest.segments[0].failure?.attempts == attempt)
        }
        #expect(manifest.segmentsAwaitingAnalysis.map(\.index) == [1])
        #expect(manifest.coverage.missing.first?.canRetry == false)
        // A later explicit retry that succeeds clears the failure.
        try manifest.markAnalysed(index: 0, derivation: derivation())
        #expect(manifest.segments[0].failure == nil)
    }

    @Test("An interrupted open segment is an unknown tail, never a complete recovery")
    func interruptedTail() throws {
        var manifest = try sealedSession([(0, 300)])
        try manifest.beginSegment(startSeconds: 300)
        try manifest.end(reason: .interrupted, atSeconds: nil)
        try manifest.discard(index: 1, reason: .interruptedWhileWriting)
        let coverage = manifest.coverage
        #expect(coverage.missing == [
            .init(segmentIndex: 1, range: .init(startSeconds: 300, endSeconds: nil),
                  reason: .interruptedWhileWriting, canRetry: false)
        ])
        #expect(coverage.missingSeconds == nil)
        #expect(coverage.waiting.map(\.segmentIndex) == [0], "The sealed segment remains analysable.")
        #expect(manifest.segmentsAwaitingAnalysis.map(\.index) == [0])

        // Interrupted between two segments: the time after the last sealed file is unknown too.
        var between = try sealedSession([(0, 300)])
        try between.end(reason: .interrupted, atSeconds: nil)
        #expect(between.coverage.missing == [
            .init(segmentIndex: nil, range: .init(startSeconds: 300, endSeconds: nil),
                  reason: .interruptedWhileWriting, canRetry: false)
        ])
    }

    @Test("Raw media expires on its own; the derived text and the entry stay")
    func rawExpiresIndependently() throws {
        let analysedAt = Date(timeIntervalSince1970: 1_791_010_000)
        var manifest = try sealedSession([(0, 300), (300, 600)], policy: policy(retentionSeconds: 3_600))
        let kept = derivation(at: analysedAt)
        try manifest.markAnalysed(index: 0, derivation: kept)
        #expect(manifest.segmentsWithReleasableRaw(at: analysedAt.addingTimeInterval(3_599)).isEmpty)
        #expect(manifest.segmentsWithReleasableRaw(at: analysedAt.addingTimeInterval(3_600)).map(\.index) == [0])
        try manifest.expireRaw(index: 0)
        #expect(manifest.segments[0].state == .rawExpired)
        #expect(!manifest.segments[0].state.expectsRawMedia)
        #expect(manifest.segments[0].derivation == kept)
        #expect(manifest.coverage.analysed.map(\.segmentIndex) == [0])
        #expect(manifest.unreleasedSealedSegmentCount == 1)
        #expect(manifest.retainedRawByteCount == 1_000, "Only the sealed segment's file is still expected on disk.")
        // A sealed segment's raw file is never released by time: its text is not saved yet.
        #expect(manifest.segmentsWithReleasableRaw(at: .distantFuture).isEmpty)

        // Forgetting the whole segment is different: its derived text goes too.
        try manifest.discard(index: 0, reason: .discardedByPerson)
        #expect(manifest.segments[0].derivation == nil)
        #expect(manifest.coverage.missing.map(\.reason) == [.discardedByPerson])
    }

    @Test("The session's budgets are shared out, not spent by the first segments")
    func budgets() throws {
        var manifest = try sealedSession([(0, 300), (300, 600)])
        #expect(manifest.frameBudgetForNextAnalysis == 12)
        #expect(manifest.textCharacterBudgetForNextAnalysis == 10_000)
        try manifest.markAnalysed(index: 0, derivation: derivation(frames: 12, characters: 10_000))
        #expect(manifest.usedFrameCount == 12)
        #expect(manifest.usedTextCharacterCount == 10_000)
        #expect(manifest.frameBudgetForNextAnalysis == 12, "A dense first segment leaves the second its share.")
        #expect(manifest.textCharacterBudgetForNextAnalysis == 10_000)
    }

    @Test("Own-interface spans known so far are checkpointed when a segment is sealed")
    func spansCheckpointedAtSeal() throws {
        var manifest = RecordingSessionManifest(context: try sessionContext())
        #expect(manifest.context.ownInterfaceIntervals == nil)
        try manifest.beginSegment(startSeconds: 0)
        let known = OwnInterfaceIntervals([.init(startSeconds: 100, endSeconds: 120)])
        try manifest.sealOpenSegment(endSeconds: 300, fingerprint: fingerprint(1), ownInterfaceIntervals: known)
        #expect(manifest.context.ownInterfaceIntervals == known)
        try manifest.beginSegment(startSeconds: 300)
        try manifest.sealOpenSegment(endSeconds: 600, fingerprint: fingerprint(2))
        #expect(manifest.context.ownInterfaceIntervals == known, "No new reading keeps the last checkpoint.")
        #expect(manifest.context.startedAt == Date(timeIntervalSince1970: 1_791_000_000))
    }
}

@Suite("Session time and segment time")
struct RecordingSessionTimelineTests {
    /// Two segments that share the instant 300, then a five-second gap before the third.
    private func session(intervals: OwnInterfaceIntervals? = nil) throws -> RecordingSessionManifest {
        try sealedSession([(0, 300), (300, 600), (605, 900)], intervals: intervals)
    }

    @Test("Frame times map from a segment's file to the session and back")
    func frameTimes() throws {
        let manifest = try session()
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: 0) == 0)
        #expect(manifest.sessionSeconds(forSegment: 1, mediaSeconds: 0) == 300)
        #expect(manifest.sessionSeconds(forSegment: 1, mediaSeconds: 12.5) == 312.5)
        #expect(manifest.sessionSeconds(forSegment: 2, mediaSeconds: 295) == 900)
        // A frame may sit exactly at the end of its file, and no further.
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: 300) == 300)
        // A file may run slightly longer than its segment: the policy's tolerance, no more.
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: 302) == 302)
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: 302.001) == nil)
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: -0.001) == nil)
        #expect(manifest.sessionSeconds(forSegment: 3, mediaSeconds: 0) == nil)
        #expect(manifest.sessionSeconds(forSegment: 0, mediaSeconds: .nan) == nil)

        for index in 0..<3 {
            for media in [0.25, 1, 150, 294.75] {
                let instant = try #require(manifest.sessionSeconds(forSegment: index, mediaSeconds: media))
                #expect(manifest.location(atSessionSeconds: instant) == .segment(index: index, mediaSeconds: media))
            }
        }
    }

    @Test("Boundary instants belong to exactly one segment")
    func boundaries() throws {
        let manifest = try session()
        #expect(manifest.location(atSessionSeconds: 0) == .segment(index: 0, mediaSeconds: 0))
        #expect(manifest.location(atSessionSeconds: 299.999) == .segment(index: 0, mediaSeconds: 299.999))
        // Shared by two segments: the later one, at the start of its file.
        #expect(manifest.location(atSessionSeconds: 300) == .segment(index: 1, mediaSeconds: 0))
        // An end no segment continues stays with the segment that ends there.
        #expect(manifest.location(atSessionSeconds: 600) == .segment(index: 1, mediaSeconds: 300))
        #expect(manifest.location(atSessionSeconds: 600.001) == .outsideSegments(afterSegment: 1))
        #expect(manifest.location(atSessionSeconds: 604.999) == .outsideSegments(afterSegment: 1))
        #expect(manifest.location(atSessionSeconds: 605) == .segment(index: 2, mediaSeconds: 0))
        #expect(manifest.location(atSessionSeconds: 900) == .segment(index: 2, mediaSeconds: 295))
        #expect(manifest.location(atSessionSeconds: 900.001) == .outsideSegments(afterSegment: 2))
        #expect(manifest.location(atSessionSeconds: -1) == .invalid)
        #expect(manifest.location(atSessionSeconds: .infinity) == .invalid)

        var late = RecordingSessionManifest(context: try sessionContext())
        try late.beginSegment(startSeconds: 2)
        #expect(late.location(atSessionSeconds: 1) == .outsideSegments(afterSegment: nil))
        #expect(late.location(atSessionSeconds: 50) == .segment(index: 0, mediaSeconds: 48), "An open segment has no end yet.")
    }

    @Test("A span crossing a segment boundary is cut into one piece per segment")
    func spanAcrossBoundary() throws {
        let manifest = try session()
        #expect(manifest.pieces(ofSessionRangeFrom: 298, to: 302) == [
            .init(segmentIndex: 0, startMediaSeconds: 298, endMediaSeconds: 300),
            .init(segmentIndex: 1, startMediaSeconds: 0, endMediaSeconds: 2)
        ])
        // Across the gap: the five uncaptured seconds belong to no piece.
        #expect(manifest.pieces(ofSessionRangeFrom: 598, to: 607) == [
            .init(segmentIndex: 1, startMediaSeconds: 298, endMediaSeconds: 300),
            .init(segmentIndex: 2, startMediaSeconds: 0, endMediaSeconds: 2)
        ])
        #expect(manifest.pieces(ofSessionRangeFrom: 300, to: 600) == [
            .init(segmentIndex: 1, startMediaSeconds: 0, endMediaSeconds: 300)
        ])
        #expect(manifest.pieces(ofSessionRangeFrom: 880, to: nil) == [
            .init(segmentIndex: 2, startMediaSeconds: 275, endMediaSeconds: 295)
        ])
        #expect(manifest.pieces(ofSessionRangeFrom: 601, to: 604).isEmpty)
        #expect(manifest.pieces(ofSessionRangeFrom: 10, to: 5).isEmpty)
    }

    @Test("A frame is excluded in its segment exactly when it is on the session's clock")
    func ownInterfaceSpansKeepTheirMeaning() throws {
        // One span ends just before the first boundary, one crosses the second boundary and
        // the gap, one is still open when capture ends.
        let spans = OwnInterfaceIntervals([
            .init(startSeconds: 100, endSeconds: 299.75),
            .init(startSeconds: 450, endSeconds: 452),
            .init(startSeconds: 598, endSeconds: 607),
            .init(startSeconds: 880)
        ])
        let manifest = try session(intervals: spans)
        for margin in [0.0, 1, 30] {
            for segment in manifest.segments {
                let local = try #require(manifest.ownInterfaceIntervals(forSegment: segment.index))
                var media = 0.0
                while media <= segment.durationSeconds! {
                    let instant = try #require(manifest.sessionSeconds(forSegment: segment.index, mediaSeconds: media))
                    #expect(local.contains(mediaSeconds: media, marginSeconds: margin)
                            == spans.contains(mediaSeconds: instant, marginSeconds: margin),
                            "segment \(segment.index), media \(media), margin \(margin)")
                    media += 0.25
                }
            }
        }
        // The case a cut at the boundary would get wrong: MORE left the front a quarter of a
        // second before the second file began, and that file's first frames are still within
        // the margin of it.
        let second = try #require(manifest.ownInterfaceIntervals(forSegment: 1))
        #expect(second.contains(mediaSeconds: 0.5))
        #expect(!second.contains(mediaSeconds: 1))
        // The span that crosses into the third file excludes that file's first frames.
        let third = try #require(manifest.ownInterfaceIntervals(forSegment: 2))
        #expect(third.contains(mediaSeconds: 2.5))
        #expect(!third.contains(mediaSeconds: 3.5))
        #expect(third.contains(mediaSeconds: 280), "Still in front when capture ended.")
        // A span far from a segment is not carried into it.
        let first = try #require(manifest.ownInterfaceIntervals(forSegment: 0))
        #expect(first.intervals.count == 1)
    }

    @Test("Unknown spans stay unknown in every segment")
    func unknownSpans() throws {
        let manifest = try session()
        #expect(manifest.ownInterfaceIntervals(forSegment: 0) == nil)
        #expect(try #require(manifest.recordingContext(forSegment: 1)).ownInterfaceIntervals == nil)
        // Known and empty is different: MORE was never in front.
        let never = try session(intervals: OwnInterfaceIntervals([]))
        #expect(never.ownInterfaceIntervals(forSegment: 2) == OwnInterfaceIntervals([]))
    }

    @Test("Each segment has its own context and a reference to its place in the session")
    func segmentContextAndReference() throws {
        let manifest = try session()
        let context = try #require(manifest.recordingContext(forSegment: 2))
        #expect(context.id == manifest.segments[2].id)
        #expect(context.startedAt == Date(timeIntervalSince1970: 1_791_000_605))
        #expect(context.timeZoneIdentifier == "Europe/Paris")
        let reference = try #require(manifest.reference(forSegment: 2))
        #expect(reference == (try ObservationSessionSegmentReference(sessionID: manifest.id, segmentIndex: 2,
                                                                      startSeconds: 605, endSeconds: 900)))
        var open = manifest
        try open.beginSegment(startSeconds: 900)
        #expect(open.reference(forSegment: 3) == nil, "An open segment has no end to refer to.")
        #expect(manifest.reference(forSegment: 9) == nil)

        #expect(throws: ObservationSessionSegmentReferenceError.invalidReference) {
            try ObservationSessionSegmentReference(sessionID: UUID(), segmentIndex: 256, startSeconds: 0, endSeconds: 1)
        }
        #expect(throws: ObservationSessionSegmentReferenceError.invalidReference) {
            try ObservationSessionSegmentReference(sessionID: UUID(), segmentIndex: 0, startSeconds: 5, endSeconds: 5)
        }
    }
}
