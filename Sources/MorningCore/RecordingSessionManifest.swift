import Foundation

/// Why a manifest was refused, on decoding or on a change. A refused change leaves the
/// manifest as it was.
public enum RecordingSessionManifestError: Error, Sendable, Equatable {
    case unsupportedVersion(Int)
    case tooManySegments
    case segmentIndexGap(expected: Int, found: Int)
    case duplicateSegmentIndex(Int)
    case duplicateSegmentIdentity(Int)
    /// Two segments claim the same file bytes.
    case duplicateFile(Int)
    /// A bound that is not finite, is negative, or ends at or before its start.
    case invalidTimeRange(Int)
    /// A segment starts before the one ahead of it ended.
    case overlappingTimeRanges(Int)
    case unknownEndBeforeLastSegment(Int)
    /// The segment's fields do not fit its state.
    case inconsistentSegment(Int)
    case invalidSessionEnd
    case budgetExceeded(Int)
    case sessionEnded
    case segmentStillOpen(Int)
    case noOpenSegment
    case unknownSegment(Int)
    case invalidTransition(index: Int, from: RecordingSegmentState)
    case sessionLimitReached
}

public enum RecordingSegmentState: String, Codable, Sendable, CaseIterable {
    /// The writer has this segment's file open. Nothing about its content is durable yet.
    case writing
    /// The file is closed and fingerprinted. It can be analysed, now or after a relaunch.
    case sealed
    /// Its derived text is durably saved. The raw file may still be on disk.
    case analysed
    /// Analysis did not complete. The raw file is kept for another attempt.
    case failed
    /// Nothing of this segment remains: no raw file and no derived text.
    case discarded
    /// The raw file is gone; the derived text and this entry remain.
    case rawExpired

    /// Whether a raw file for this segment is supposed to be on disk.
    public var expectsRawMedia: Bool {
        switch self {
        case .writing, .sealed, .analysed, .failed: true
        case .discarded, .rawExpired: false
        }
    }
}

public enum RecordingSegmentLossReason: String, Codable, Sendable {
    /// The app stopped while the segment was being written.
    case interruptedWhileWriting
    case captureFailed
    case rawMediaMissing
    /// The file no longer holds the bytes that were sealed.
    case rawMediaChanged
    case discardedByPerson
}

public enum RecordingSegmentFailureReason: String, Codable, Sendable {
    case extractionFailed
    /// The analysis returned more than the segment's budget allows.
    case derivedEvidenceRejected
}

public struct RecordingSegmentFailure: Codable, Equatable, Sendable {
    public let reason: RecordingSegmentFailureReason
    public let attempts: Int
    public let failedAt: Date
}

/// What was kept from one segment once its analysis was saved.
public struct RecordingSegmentDerivation: Codable, Equatable, Sendable {
    /// The archive entry holding the segment's text. Nil when frames were sampled and none
    /// held readable text: that is a result, not a missing range.
    public let acquisitionID: UUID?
    public let sampledFrameCount: Int
    public let textCharacterCount: Int
    public let analysedAt: Date

    public init(acquisitionID: UUID?, sampledFrameCount: Int, textCharacterCount: Int, analysedAt: Date) {
        self.acquisitionID = acquisitionID
        self.sampledFrameCount = sampledFrameCount
        self.textCharacterCount = textCharacterCount
        self.analysedAt = analysedAt
    }
}

/// One file of a session. Its bounds are seconds on the session's clock: the monotonic
/// clock whose zero is the session's start. No path or file name is stored; the store
/// derives the name from the index.
public struct RecordingSegment: Codable, Equatable, Sendable, Identifiable {
    /// Also the identity of the archive entry and recording context made from this segment.
    public let id: UUID
    public let index: Int
    public let startSeconds: Double
    /// Nil while writing, and for a segment lost before its end was known.
    public let endSeconds: Double?
    /// SHA-256 and size of the sealed file, as the existing stores identify a file.
    public let fingerprint: ObservationFileFingerprint?
    public let state: RecordingSegmentState
    public let derivation: RecordingSegmentDerivation?
    public let failure: RecordingSegmentFailure?
    public let lossReason: RecordingSegmentLossReason?

    public var byteCount: Int64? { fingerprint?.byteCount }
    public var durationSeconds: Double? { endSeconds.map { $0 - startSeconds } }

    fileprivate func with(endSeconds: Double?? = nil, fingerprint: ObservationFileFingerprint?? = nil,
                          state: RecordingSegmentState, derivation: RecordingSegmentDerivation?? = nil,
                          failure: RecordingSegmentFailure?? = nil,
                          lossReason: RecordingSegmentLossReason?? = nil) -> Self {
        .init(id: id, index: index, startSeconds: startSeconds, endSeconds: endSeconds ?? self.endSeconds,
              fingerprint: fingerprint ?? self.fingerprint, state: state,
              derivation: derivation ?? self.derivation, failure: failure ?? self.failure,
              lossReason: lossReason ?? self.lossReason)
    }
}

public enum RecordingSessionEndReason: String, Codable, Sendable {
    case stoppedByPerson, systemStopped, captureFailed
    case sessionDurationLimit, segmentCountLimit
    /// Too many sealed segments were still waiting for analysis.
    case analysisBacklog
    case storageReserve
    /// Free space could not be read, so the next segment was not started.
    case freeSpaceUnknown
    /// Found open at relaunch: the app stopped while the session was running.
    case interrupted
}

/// What one more segment may use, or why it may not start.
public enum RecordingSegmentAdmission: Equatable, Sendable {
    case start(maximumDurationSeconds: Double, maximumBytes: Int64)
    /// The open segment must be sealed or given up before another starts.
    case sealFirst(index: Int)
    case stop(RecordingSessionEndReason)
}

/// The durable record of one long recording: its start, its policy and its ordered
/// segments. The value is pure; `RecordingSessionStore` saves it atomically after each change.
///
/// Rules it enforces, on every change and again when decoded:
/// - indexes run 0, 1, 2… with no gap and no repeat;
/// - a segment is sealed (or given up) before the next one starts, so only the last
///   segment can be open or of unknown end;
/// - time ranges are finite, forward, in order and never overlap. A gap between two
///   segments is allowed and reported as time that was not captured;
/// - a segment's fields fit its state, and the frame and text budgets hold.
public struct RecordingSessionManifest: Codable, Equatable, Sendable, Identifiable {
    public static let currentFormatVersion = 1
    public static let maximumSegments = 256
    public static let maximumEncodedBytes = 1_024 * 1_024
    /// The existing bound of the file fingerprint service, which every segment passes through.
    public static let maximumSegmentFileBytes: Int64 = 512 * 1_024 * 1_024

    public let formatVersion: Int
    /// Session identity, start instant and zone. Its own-interface spans are seconds on the
    /// session's clock; they are checkpointed at each seal so a crash keeps what was known.
    public private(set) var context: ObservationRecordingContext
    public let policy: SegmentedRecordingPolicy
    public private(set) var segments: [RecordingSegment]
    public private(set) var endReason: RecordingSessionEndReason?
    /// Nil while the session runs, and when it was interrupted: that end is unknown.
    public private(set) var endedAtSeconds: Double?

    public var id: UUID { context.id }
    public var isOpen: Bool { endReason == nil }
    public var openSegment: RecordingSegment? { segments.last.flatMap { $0.state == .writing ? $0 : nil } }

    public init(context: ObservationRecordingContext, policy: SegmentedRecordingPolicy = .provisional) {
        formatVersion = Self.currentFormatVersion
        self.context = context
        self.policy = policy
        segments = []
    }

    // MARK: Capture

    /// Starts the next segment. Refused while another is open: a segment is sealed first.
    @discardableResult
    public mutating func beginSegment(id: UUID = UUID(), startSeconds: Double) throws -> RecordingSegment {
        guard isOpen else { throw RecordingSessionManifestError.sessionEnded }
        if let open = openSegment { throw RecordingSessionManifestError.segmentStillOpen(open.index) }
        guard segments.count < policy.maximumSegmentCount,
              !(startSeconds >= policy.maximumSessionDurationSeconds) else {
            throw RecordingSessionManifestError.sessionLimitReached
        }
        let segment = RecordingSegment(id: id, index: segments.count, startSeconds: startSeconds, endSeconds: nil,
            fingerprint: nil, state: .writing, derivation: nil, failure: nil, lossReason: nil)
        try change { $0.segments.append(segment) }
        return segment
    }

    /// Records the closed file of the open segment. `ownInterfaceIntervals` are the spans
    /// known so far, on the session's clock; nil keeps the last checkpoint.
    public mutating func sealOpenSegment(endSeconds: Double, fingerprint: ObservationFileFingerprint,
                                         ownInterfaceIntervals: OwnInterfaceIntervals? = nil) throws {
        guard let open = openSegment else { throw RecordingSessionManifestError.noOpenSegment }
        try change {
            $0.segments[open.index] = open.with(endSeconds: endSeconds, fingerprint: fingerprint, state: .sealed)
            if let ownInterfaceIntervals { $0.context = $0.context.withOwnInterfaceIntervals(ownInterfaceIntervals) }
        }
    }

    /// True when the open segment has reached its duration or size, whichever comes first,
    /// or the session has reached its own duration.
    public func shouldSealOpenSegment(atSeconds now: Double, writtenBytes: Int64) -> Bool {
        guard let open = openSegment else { return false }
        return now - open.startSeconds >= policy.maximumSegmentDurationSeconds
            || writtenBytes >= policy.maximumSegmentBytes
            || now >= policy.maximumSessionDurationSeconds
    }

    /// Whether one more segment may start. Unknown free space refuses: the reserve cannot
    /// be shown to hold.
    public func admission(atSeconds now: Double, freeBytes: Int64?) -> RecordingSegmentAdmission {
        if let endReason { return .stop(endReason) }
        if let open = openSegment { return .sealFirst(index: open.index) }
        guard now.isFinite, now >= 0 else { return .stop(.captureFailed) }
        if now >= policy.maximumSessionDurationSeconds { return .stop(.sessionDurationLimit) }
        if segments.count >= policy.maximumSegmentCount { return .stop(.segmentCountLimit) }
        if unreleasedSealedSegmentCount >= policy.maximumUnreleasedRawSegments { return .stop(.analysisBacklog) }
        guard let freeBytes else { return .stop(.freeSpaceUnknown) }
        if freeBytes < policy.storageEstimate.freeBytesNeededToStartASegment { return .stop(.storageReserve) }
        return .start(
            maximumDurationSeconds: min(policy.maximumSegmentDurationSeconds, policy.maximumSessionDurationSeconds - now),
            maximumBytes: policy.maximumSegmentBytes)
    }

    /// Ends the session. The end instant is unknown after an interruption.
    public mutating func end(reason: RecordingSessionEndReason, atSeconds: Double?) throws {
        guard isOpen else { throw RecordingSessionManifestError.sessionEnded }
        try change { $0.endReason = reason; $0.endedAtSeconds = atSeconds }
    }

    public mutating func setOwnInterfaceIntervals(_ intervals: OwnInterfaceIntervals?) {
        context = context.withOwnInterfaceIntervals(intervals)
    }

    // MARK: Analysis and retention

    /// Call only after the derived text is durably saved. Until then the segment stays
    /// sealed and its raw file cannot be released.
    public mutating func markAnalysed(index: Int, derivation: RecordingSegmentDerivation) throws {
        let segment = try required(index, in: [.sealed, .failed])
        try change {
            $0.segments[index] = segment.with(state: .analysed, derivation: .some(derivation), failure: .some(nil))
        }
    }

    public mutating func markFailed(index: Int, reason: RecordingSegmentFailureReason, at date: Date) throws {
        let segment = try required(index, in: [.sealed, .failed])
        let failure = RecordingSegmentFailure(reason: reason, attempts: (segment.failure?.attempts ?? 0) + 1,
                                              failedAt: date)
        try change { $0.segments[index] = segment.with(state: .failed, failure: .some(failure)) }
    }

    /// The raw file is gone or may go; the derived text and this entry stay.
    public mutating func expireRaw(index: Int) throws {
        let segment = try required(index, in: [.analysed])
        try change { $0.segments[index] = segment.with(state: .rawExpired) }
    }

    /// Gives the whole segment up, raw file and derived text. Its time range becomes missing.
    /// `endSeconds` supplies the end of an open segment when it is known.
    public mutating func discard(index: Int, reason: RecordingSegmentLossReason, endSeconds: Double? = nil) throws {
        let segment = try required(index, in: [.writing, .sealed, .analysed, .failed, .rawExpired])
        try change {
            $0.segments[index] = segment.with(endSeconds: segment.endSeconds == nil ? .some(endSeconds) : nil,
                state: .discarded, derivation: .some(nil), lossReason: .some(reason))
        }
    }

    /// Sealed and failed segments that analysis may still take, in order.
    public var segmentsAwaitingAnalysis: [RecordingSegment] {
        segments.filter {
            $0.state == .sealed || ($0.state == .failed && ($0.failure?.attempts ?? 0) < policy.maximumAnalysisAttempts)
        }
    }

    /// Sealed segments whose raw file is still expected on disk.
    public var unreleasedSealedSegmentCount: Int {
        segments.filter { $0.state == .sealed || $0.state == .analysed || $0.state == .failed }.count
    }

    /// Raw files that may be removed now: analysed, and past the policy's retention. A
    /// sealed or failed segment never appears here; only a person discards those.
    public func segmentsWithReleasableRaw(at now: Date) -> [RecordingSegment] {
        segments.filter { segment in
            guard segment.state == .analysed, let derivation = segment.derivation else { return false }
            return now >= derivation.analysedAt.addingTimeInterval(policy.analysedRawRetentionSeconds)
        }
    }

    /// Bytes of sealed raw files the manifest still expects on disk. The open segment's
    /// file is not counted: its size is unknown until it is sealed.
    public var retainedRawByteCount: Int64 {
        segments.reduce(0) { $0 + ($1.state.expectsRawMedia ? ($1.byteCount ?? 0) : 0) }
    }

    public var usedFrameCount: Int { segments.reduce(0) { $0 + ($1.derivation?.sampledFrameCount ?? 0) } }
    public var usedTextCharacterCount: Int { segments.reduce(0) { $0 + ($1.derivation?.textCharacterCount ?? 0) } }

    /// Frames one more analysis may request: the segment's share, within what the session has left.
    public var frameBudgetForNextAnalysis: Int {
        max(0, min(policy.framesPerSegment, policy.maximumSessionFrames - usedFrameCount))
    }
    public var textCharacterBudgetForNextAnalysis: Int {
        max(0, min(policy.textCharactersPerSegment, policy.maximumSessionTextCharacters - usedTextCharacterCount))
    }

    // MARK: Validation

    private func required(_ index: Int, in states: [RecordingSegmentState]) throws -> RecordingSegment {
        guard segments.indices.contains(index) else { throw RecordingSessionManifestError.unknownSegment(index) }
        let segment = segments[index]
        guard states.contains(segment.state) else {
            throw RecordingSessionManifestError.invalidTransition(index: index, from: segment.state)
        }
        return segment
    }

    private mutating func change(_ body: (inout Self) -> Void) throws {
        var next = self
        body(&next)
        try next.validate()
        self = next
    }

    private func validate() throws {
        typealias Failure = RecordingSessionManifestError
        guard formatVersion == Self.currentFormatVersion else { throw Failure.unsupportedVersion(formatVersion) }
        guard segments.count <= Self.maximumSegments, segments.count <= policy.maximumSegmentCount else {
            throw Failure.tooManySegments
        }
        var identities = Set<UUID>()
        var files = Set<String>()
        var previousEnd: Double = 0
        for (position, segment) in segments.enumerated() {
            let index = segment.index
            guard index == position else {
                throw index < position && index >= 0 ? Failure.duplicateSegmentIndex(index)
                    : Failure.segmentIndexGap(expected: position, found: index)
            }
            guard identities.insert(segment.id).inserted else { throw Failure.duplicateSegmentIdentity(index) }
            guard segment.startSeconds.isFinite, segment.startSeconds >= 0,
                  segment.startSeconds < policy.maximumSessionDurationSeconds else { throw Failure.invalidTimeRange(index) }
            if let end = segment.endSeconds {
                guard end.isFinite, end > segment.startSeconds,
                      end - segment.startSeconds <= ObservationVideoEvidence.maximumDurationSeconds else {
                    throw Failure.invalidTimeRange(index)
                }
            } else if position != segments.count - 1 {
                throw Failure.unknownEndBeforeLastSegment(index)
            }
            guard segment.startSeconds >= previousEnd else { throw Failure.overlappingTimeRanges(index) }
            previousEnd = segment.endSeconds ?? segment.startSeconds
            if let fingerprint = segment.fingerprint {
                guard fingerprint.byteCount <= Self.maximumSegmentFileBytes else { throw Failure.inconsistentSegment(index) }
                guard files.insert(fingerprint.sha256).inserted else { throw Failure.duplicateFile(index) }
            }
            let sealed = segment.endSeconds != nil && segment.fingerprint != nil
            let consistent: Bool
            switch segment.state {
            case .writing:
                consistent = segment.endSeconds == nil && segment.fingerprint == nil && segment.derivation == nil
                    && segment.failure == nil && segment.lossReason == nil
            case .sealed:
                consistent = sealed && segment.derivation == nil && segment.failure == nil && segment.lossReason == nil
            case .failed:
                consistent = sealed && segment.derivation == nil && segment.lossReason == nil
                    && (segment.failure.map { $0.attempts >= 1 } ?? false)
            case .analysed, .rawExpired:
                consistent = sealed && segment.derivation != nil && segment.failure == nil && segment.lossReason == nil
            case .discarded:
                consistent = segment.derivation == nil && segment.lossReason != nil
            }
            guard consistent else { throw Failure.inconsistentSegment(index) }
            if let derivation = segment.derivation {
                // Analysed means frames were sampled; text and an archive entry go together.
                guard (derivation.acquisitionID == nil) == (derivation.textCharacterCount == 0),
                      derivation.sampledFrameCount >= 1 else { throw Failure.inconsistentSegment(index) }
                guard derivation.sampledFrameCount <= policy.framesPerSegment,
                      (0...policy.textCharactersPerSegment).contains(derivation.textCharacterCount),
                      derivation.analysedAt.timeIntervalSinceReferenceDate.isFinite else {
                    throw Failure.budgetExceeded(index)
                }
            }
        }
        guard usedFrameCount <= policy.maximumSessionFrames,
              usedTextCharacterCount <= policy.maximumSessionTextCharacters else {
            throw Failure.budgetExceeded(segments.count - 1)
        }
        switch endReason {
        case nil:
            guard endedAtSeconds == nil else { throw Failure.invalidSessionEnd }
        case .interrupted:
            // The end is unknown. An open segment may remain until recovery settles it.
            guard endedAtSeconds == nil else { throw Failure.invalidSessionEnd }
        default:
            guard let end = endedAtSeconds, end.isFinite, end >= previousEnd, openSegment == nil else {
                throw Failure.invalidSessionEnd
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, context, policy, segments, endReason, endedAtSeconds
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        // Read the version alone first: a later format is refused before its fields are read.
        formatVersion = try values.decode(Int.self, forKey: .formatVersion)
        guard formatVersion == Self.currentFormatVersion else {
            throw RecordingSessionManifestError.unsupportedVersion(formatVersion)
        }
        context = try values.decode(ObservationRecordingContext.self, forKey: .context)
        policy = try values.decode(SegmentedRecordingPolicy.self, forKey: .policy)
        segments = try values.decode([RecordingSegment].self, forKey: .segments)
        endReason = try values.decodeIfPresent(RecordingSessionEndReason.self, forKey: .endReason)
        endedAtSeconds = try values.decodeIfPresent(Double.self, forKey: .endedAtSeconds)
        try validate()
    }
}
