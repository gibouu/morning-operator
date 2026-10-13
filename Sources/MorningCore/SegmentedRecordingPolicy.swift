import Foundation

public enum SegmentedRecordingPolicyError: Error, Sendable, Equatable {
    case invalidPolicy
}

/// How one long recording is cut into segments and how much of it may be kept.
///
/// **Every number in `provisional` is a placeholder**, chosen on 13 October 2026 so the
/// session manifest could be built before the phone pilot. None has been measured on a
/// device. The pilot in `docs/LONG-RECORDING-TEST-PLAN.md` replaces them here, in this one
/// value, and nowhere else: no other file may hold a segment size or a session budget.
///
/// A manifest stores the policy it was recorded under, so changing these numbers never
/// invalidates a session that already exists.
public struct SegmentedRecordingPolicy: Codable, Equatable, Sendable {
    /// Names the set of numbers, so a result can say which policy produced it.
    public let identifier: String
    /// A segment is sealed when it reaches this length or `maximumSegmentBytes`, whichever
    /// comes first.
    public let maximumSegmentDurationSeconds: Double
    public let maximumSegmentBytes: Int64
    /// How far past `maximumSegmentBytes` a file may run before the writer stops. The size
    /// monitor asks for a stop once a second; it is not a ceiling.
    public let segmentByteOvershootAllowance: Int64
    public let maximumSessionDurationSeconds: Double
    /// How much longer a segment's file may be than the segment on the session's clock,
    /// and how far past that length a frame may sit. The two clocks are not aligned by
    /// measurement.
    public let segmentTimingToleranceSeconds: Double
    /// Sampled frames requested from one segment.
    public let framesPerSegment: Int
    public let maximumSessionFrames: Int
    public let maximumSessionTextCharacters: Int
    /// Sealed segments whose raw file may still be on disk while another is being written.
    public let maximumUnreleasedRawSegments: Int
    /// Free space that must remain beyond the next segment before it may start.
    public let minimumFreeBytesReserve: Int64
    /// How long a raw file stays after its derived text is saved. Zero releases it at once.
    public let analysedRawRetentionSeconds: Double
    public let maximumAnalysisAttempts: Int

    public static let mebibyte: Int64 = 1_024 * 1_024

    /// Provisional, with the reason for each number:
    /// - **5 minutes / 64 MiB per segment**: the owner's decision of 13 October 2026. Five
    ///   minutes bounds what a crash can lose and equals the shortest existing preset. At the
    ///   rate implied by today's 256 MiB per 30 minutes (about 43 MiB per 5 minutes) the
    ///   duration comes first; the size guards high-motion content.
    /// - **4 MiB overshoot**: an allowance for the one-second size monitor. Unmeasured.
    /// - **90 minutes per session**: the upper end of the morning asked for in issue #27.
    /// - **2 seconds of timing tolerance**: twice the own-interface margin. Unmeasured.
    /// - **12 frames per segment, 216 per session**: one request every 25 seconds instead of
    ///   every 78 (24 frames over 30 minutes), within the existing 24 frames per file.
    /// - **180,000 Characters per session**: 10,000 per segment, an equal share so dense early
    ///   segments cannot leave later ones without room; 120 requests of 1,500 Characters,
    ///   within the existing 768.
    /// - **18 unreleased raw segments**: whether analysis can run while the phone records in
    ///   the background is unverified, so a whole session may wait for it.
    /// - **256 MiB reserve**: room for atomic saves and the rest of the phone. Unmeasured.
    /// - **No raw retention after analysis**: as today, the raw file goes once its evidence
    ///   is saved. Keeping it for a denser second pass needs an explicit scope and expiry.
    /// - **3 analysis attempts** before a failed segment stops being retried by itself.
    public static let provisional = try! SegmentedRecordingPolicy(
        identifier: "provisional-2026-10-13",
        maximumSegmentDurationSeconds: 5 * 60,
        maximumSegmentBytes: 64 * mebibyte,
        segmentByteOvershootAllowance: 4 * mebibyte,
        maximumSessionDurationSeconds: 90 * 60,
        segmentTimingToleranceSeconds: 2,
        framesPerSegment: 12,
        maximumSessionFrames: 216,
        maximumSessionTextCharacters: 180_000,
        maximumUnreleasedRawSegments: 18,
        minimumFreeBytesReserve: 256 * mebibyte,
        analysedRawRetentionSeconds: 0,
        maximumAnalysisAttempts: 3)

    public init(identifier: String, maximumSegmentDurationSeconds: Double, maximumSegmentBytes: Int64,
                segmentByteOvershootAllowance: Int64, maximumSessionDurationSeconds: Double,
                segmentTimingToleranceSeconds: Double, framesPerSegment: Int, maximumSessionFrames: Int, maximumSessionTextCharacters: Int,
                maximumUnreleasedRawSegments: Int, minimumFreeBytesReserve: Int64,
                analysedRawRetentionSeconds: Double, maximumAnalysisAttempts: Int) throws {
        // A segment is one file for the existing import path: it must fit that path's
        // duration, size and frame bounds, which this policy never raises.
        guard !identifier.isEmpty, identifier.count <= 64,
              maximumSegmentDurationSeconds.isFinite, maximumSegmentDurationSeconds > 0,
              maximumSegmentDurationSeconds <= ObservationVideoEvidence.maximumDurationSeconds,
              maximumSessionDurationSeconds.isFinite,
              maximumSessionDurationSeconds >= maximumSegmentDurationSeconds,
              maximumSessionDurationSeconds / maximumSegmentDurationSeconds
                  <= Double(RecordingSessionManifest.maximumSegments),
              segmentTimingToleranceSeconds.isFinite, segmentTimingToleranceSeconds >= 0,
              segmentTimingToleranceSeconds <= RecordingSessionManifest.ownInterfaceCarrySeconds / 2,
              maximumSegmentBytes > 0, segmentByteOvershootAllowance >= 0,
              maximumSegmentBytes <= RecordingSessionManifest.maximumSegmentFileBytes,
              segmentByteOvershootAllowance <= RecordingSessionManifest.maximumSegmentFileBytes - maximumSegmentBytes,
              (1...ObservationVideoEvidence.maximumFrames).contains(framesPerSegment),
              maximumSessionFrames >= framesPerSegment, maximumSessionFrames <= 100_000,
              maximumSessionTextCharacters > 0, maximumSessionTextCharacters <= 10_000_000,
              maximumUnreleasedRawSegments >= 1,
              maximumUnreleasedRawSegments <= RecordingSessionManifest.maximumSegments,
              minimumFreeBytesReserve >= 0, minimumFreeBytesReserve <= 1_024 * 1_024 * Self.mebibyte,
              analysedRawRetentionSeconds.isFinite, analysedRawRetentionSeconds >= 0,
              (1...16).contains(maximumAnalysisAttempts) else {
            throw SegmentedRecordingPolicyError.invalidPolicy
        }
        self.identifier = identifier
        self.maximumSegmentDurationSeconds = maximumSegmentDurationSeconds
        self.maximumSegmentBytes = maximumSegmentBytes
        self.segmentByteOvershootAllowance = segmentByteOvershootAllowance
        self.maximumSessionDurationSeconds = maximumSessionDurationSeconds
        self.segmentTimingToleranceSeconds = segmentTimingToleranceSeconds
        self.framesPerSegment = framesPerSegment
        self.maximumSessionFrames = maximumSessionFrames
        self.maximumSessionTextCharacters = maximumSessionTextCharacters
        self.maximumUnreleasedRawSegments = maximumUnreleasedRawSegments
        self.minimumFreeBytesReserve = minimumFreeBytesReserve
        self.analysedRawRetentionSeconds = analysedRawRetentionSeconds
        self.maximumAnalysisAttempts = maximumAnalysisAttempts
    }

    /// A session ends when it has used this many segments, even if segments sealed early on
    /// size leave time on the clock. This is what bounds the session's bytes.
    public var maximumSegmentCount: Int {
        Int((maximumSessionDurationSeconds / maximumSegmentDurationSeconds).rounded(.up))
    }

    public var worstCaseSegmentBytes: Int64 { maximumSegmentBytes + segmentByteOvershootAllowance }

    /// An equal share of the session's text for every segment, within what one file's
    /// extraction may hold today.
    public var textCharactersPerSegment: Int {
        min(ObservationVideoEvidence.maximumOCRCharacters, maximumSessionTextCharacters / maximumSegmentCount)
    }

    public var storageEstimate: SegmentedRecordingStorageEstimate { .init(policy: self) }

    private enum CodingKeys: String, CodingKey {
        case identifier, maximumSegmentDurationSeconds, maximumSegmentBytes, segmentByteOvershootAllowance
        case maximumSessionDurationSeconds, segmentTimingToleranceSeconds, framesPerSegment, maximumSessionFrames, maximumSessionTextCharacters
        case maximumUnreleasedRawSegments, minimumFreeBytesReserve, analysedRawRetentionSeconds, maximumAnalysisAttempts
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            identifier: values.decode(String.self, forKey: .identifier),
            maximumSegmentDurationSeconds: values.decode(Double.self, forKey: .maximumSegmentDurationSeconds),
            maximumSegmentBytes: values.decode(Int64.self, forKey: .maximumSegmentBytes),
            segmentByteOvershootAllowance: values.decode(Int64.self, forKey: .segmentByteOvershootAllowance),
            maximumSessionDurationSeconds: values.decode(Double.self, forKey: .maximumSessionDurationSeconds),
            segmentTimingToleranceSeconds: values.decode(Double.self, forKey: .segmentTimingToleranceSeconds),
            framesPerSegment: values.decode(Int.self, forKey: .framesPerSegment),
            maximumSessionFrames: values.decode(Int.self, forKey: .maximumSessionFrames),
            maximumSessionTextCharacters: values.decode(Int.self, forKey: .maximumSessionTextCharacters),
            maximumUnreleasedRawSegments: values.decode(Int.self, forKey: .maximumUnreleasedRawSegments),
            minimumFreeBytesReserve: values.decode(Int64.self, forKey: .minimumFreeBytesReserve),
            analysedRawRetentionSeconds: values.decode(Double.self, forKey: .analysedRawRetentionSeconds),
            maximumAnalysisAttempts: values.decode(Int.self, forKey: .maximumAnalysisAttempts))
    }
}

/// Worst-case disk use of one session under a policy, for the screen that will show it.
/// These are upper bounds computed from the policy, not measurements. Derived text is not
/// counted here: it lives in the observation archive, within that archive's own limits.
public struct SegmentedRecordingStorageEstimate: Equatable, Sendable {
    public let maximumSegmentCount: Int
    public let worstCaseSegmentBytes: Int64
    /// Every segment full and none released: analysis only starts after capture ends.
    public let worstCaseRawBytesIfNothingIsReleased: Int64
    /// The most raw bytes on disk at once when the backlog limit is respected: the segment
    /// being written plus the sealed ones allowed to wait.
    public let worstCaseRawBytesWithinBacklogLimit: Int64
    /// The manifest and the staged copy made by an atomic save.
    public let manifestBytesAllowance: Int64
    /// Free space required before one more segment may start.
    public let freeBytesNeededToStartASegment: Int64
    /// Free space that lets a whole session finish without releasing anything.
    public let freeBytesNeededForAWholeSession: Int64

    public init(policy: SegmentedRecordingPolicy) {
        let count = policy.maximumSegmentCount
        maximumSegmentCount = count
        worstCaseSegmentBytes = policy.worstCaseSegmentBytes
        worstCaseRawBytesIfNothingIsReleased = Int64(count) * policy.worstCaseSegmentBytes
        worstCaseRawBytesWithinBacklogLimit =
            Int64(min(count, policy.maximumUnreleasedRawSegments + 1)) * policy.worstCaseSegmentBytes
        manifestBytesAllowance = 2 * Int64(RecordingSessionManifest.maximumEncodedBytes)
        freeBytesNeededToStartASegment = policy.worstCaseSegmentBytes + policy.minimumFreeBytesReserve
        freeBytesNeededForAWholeSession = worstCaseRawBytesIfNothingIsReleased
            + manifestBytesAllowance + policy.minimumFreeBytesReserve
    }
}
