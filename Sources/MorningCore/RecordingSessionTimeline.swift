import Foundation

public enum ObservationSessionSegmentReferenceError: Error, Sendable, Equatable {
    case invalidReference
}

/// Says that an observation is one segment of a longer recording session, and where that
/// segment sits on the session's clock. Observations sharing a `sessionID` are one recording
/// kept as several files; the index gives their order.
public struct ObservationSessionSegmentReference: Codable, Equatable, Hashable, Sendable {
    public let sessionID: UUID
    public let segmentIndex: Int
    public let startSeconds: Double
    public let endSeconds: Double

    public init(sessionID: UUID, segmentIndex: Int, startSeconds: Double, endSeconds: Double) throws {
        guard (0..<RecordingSessionManifest.maximumSegments).contains(segmentIndex),
              startSeconds.isFinite, endSeconds.isFinite, startSeconds >= 0, endSeconds > startSeconds else {
            throw ObservationSessionSegmentReferenceError.invalidReference
        }
        self.sessionID = sessionID
        self.segmentIndex = segmentIndex
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }

    private enum CodingKeys: String, CodingKey { case sessionID, segmentIndex, startSeconds, endSeconds }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sessionID: values.decode(UUID.self, forKey: .sessionID),
                      segmentIndex: values.decode(Int.self, forKey: .segmentIndex),
                      startSeconds: values.decode(Double.self, forKey: .startSeconds),
                      endSeconds: values.decode(Double.self, forKey: .endSeconds))
    }
}

/// Seconds on the session's clock. A nil end is an end that is not known.
public struct RecordingSessionTimeRange: Equatable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double?
    public init(startSeconds: Double, endSeconds: Double?) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

public enum RecordingSessionMissingReason: String, Sendable, Equatable {
    /// No segment covers this time: a gap at a rollover, or before the first or after the last file.
    case notCaptured
    case interruptedWhileWriting, captureFailed, rawMediaMissing, rawMediaChanged, discardedByPerson
    case analysisFailed
}

/// What a session's analysis covers, range by range. A range that is missing or waiting is
/// time nothing is known about. It is never a range in which nothing happened.
public struct RecordingSessionCoverage: Equatable, Sendable {
    public struct Analysed: Equatable, Sendable {
        public let segmentIndex: Int
        public let range: RecordingSessionTimeRange
        /// Nil when frames were sampled and none held readable text.
        public let acquisitionID: UUID?
        public var hasReadableText: Bool { acquisitionID != nil }
        public init(segmentIndex: Int, range: RecordingSessionTimeRange, acquisitionID: UUID?) {
            self.segmentIndex = segmentIndex; self.range = range; self.acquisitionID = acquisitionID
        }
    }
    public struct Waiting: Equatable, Sendable {
        public let segmentIndex: Int
        public let range: RecordingSessionTimeRange
        /// Still being written, as opposed to sealed and waiting for analysis.
        public let isBeingWritten: Bool
        public init(segmentIndex: Int, range: RecordingSessionTimeRange, isBeingWritten: Bool) {
            self.segmentIndex = segmentIndex; self.range = range; self.isBeingWritten = isBeingWritten
        }
    }
    public struct Missing: Equatable, Sendable {
        /// Nil for time between segments.
        public let segmentIndex: Int?
        public let range: RecordingSessionTimeRange
        public let reason: RecordingSessionMissingReason
        /// A failed analysis whose raw file is kept and may be tried again.
        public let canRetry: Bool
        public init(segmentIndex: Int?, range: RecordingSessionTimeRange,
                    reason: RecordingSessionMissingReason, canRetry: Bool) {
            self.segmentIndex = segmentIndex; self.range = range; self.reason = reason; self.canRetry = canRetry
        }
    }

    public let analysed: [Analysed]
    public let waiting: [Waiting]
    public let missing: [Missing]

    public var isComplete: Bool { waiting.isEmpty && missing.isEmpty }
    public var analysedSeconds: Double {
        analysed.reduce(0) { $0 + (($1.range.endSeconds ?? $1.range.startSeconds) - $1.range.startSeconds) }
    }
    /// Nil when a missing range has no known end: the amount missing is then unknown too.
    public var missingSeconds: Double? {
        var total = 0.0
        for item in missing {
            guard let end = item.range.endSeconds else { return nil }
            total += end - item.range.startSeconds
        }
        return total
    }
}

/// Where an instant of the session falls.
public enum RecordingSessionTimeLocation: Equatable, Sendable {
    /// `mediaSeconds` counts from the start of that segment's file.
    case segment(index: Int, mediaSeconds: Double)
    /// No segment covers the instant. `afterSegment` is the last one that ended before it.
    case outsideSegments(afterSegment: Int?)
    case invalid
}

/// One part of a session range that lies inside one segment, in that segment's media time.
public struct RecordingSegmentPiece: Equatable, Sendable {
    public let segmentIndex: Int
    public let startMediaSeconds: Double
    /// Nil when neither the range nor the segment has a known end.
    public let endMediaSeconds: Double?
    public init(segmentIndex: Int, startMediaSeconds: Double, endMediaSeconds: Double?) {
        self.segmentIndex = segmentIndex
        self.startMediaSeconds = startMediaSeconds
        self.endMediaSeconds = endMediaSeconds
    }
}

extension RecordingSessionManifest {
    /// Spans within this many seconds of a segment are carried into it, so a frame near a
    /// boundary is still excluded by a span that ended just before its file began. The
    /// result matches the session's own answer for any margin up to this value.
    public static let ownInterfaceCarrySeconds: Double = 60
    /// Carried spans are widened by this much so that rounding in the shift can only
    /// exclude a frame, never admit one.
    static let ownInterfaceRoundingSeconds: Double = 1e-6

    public var coverage: RecordingSessionCoverage {
        var analysed: [RecordingSessionCoverage.Analysed] = []
        var waiting: [RecordingSessionCoverage.Waiting] = []
        var missing: [RecordingSessionCoverage.Missing] = []
        var cursor: Double = 0
        for segment in segments {
            if segment.startSeconds > cursor {
                missing.append(.init(segmentIndex: nil,
                    range: .init(startSeconds: cursor, endSeconds: segment.startSeconds),
                    reason: .notCaptured, canRetry: false))
            }
            let range = RecordingSessionTimeRange(startSeconds: segment.startSeconds, endSeconds: segment.endSeconds)
            switch segment.state {
            case .writing:
                // A session that is no longer running cannot finish this file.
                if isOpen { waiting.append(.init(segmentIndex: segment.index, range: range, isBeingWritten: true)) }
                else {
                    missing.append(.init(segmentIndex: segment.index, range: range,
                                         reason: .interruptedWhileWriting, canRetry: false))
                }
            case .sealed:
                waiting.append(.init(segmentIndex: segment.index, range: range, isBeingWritten: false))
            case .analysed, .rawExpired:
                analysed.append(.init(segmentIndex: segment.index, range: range,
                                      acquisitionID: segment.derivation?.acquisitionID))
            case .failed:
                missing.append(.init(segmentIndex: segment.index, range: range, reason: .analysisFailed,
                    canRetry: (segment.failure?.attempts ?? 0) < policy.maximumAnalysisAttempts))
            case .discarded:
                let reason: RecordingSessionMissingReason
                switch segment.lossReason {
                case .interruptedWhileWriting, nil: reason = .interruptedWhileWriting
                case .captureFailed: reason = .captureFailed
                case .rawMediaMissing: reason = .rawMediaMissing
                case .rawMediaChanged: reason = .rawMediaChanged
                case .discardedByPerson: reason = .discardedByPerson
                }
                missing.append(.init(segmentIndex: segment.index, range: range, reason: reason, canRetry: false))
            }
            cursor = segment.endSeconds ?? segment.startSeconds
        }
        let lastEndIsKnown = segments.last.map { $0.endSeconds != nil } ?? true
        if lastEndIsKnown {
            if let end = endedAtSeconds {
                if end > cursor {
                    missing.append(.init(segmentIndex: nil, range: .init(startSeconds: cursor, endSeconds: end),
                                         reason: .notCaptured, canRetry: false))
                }
            } else if endReason == .interrupted {
                // The session stopped at an unknown instant after its last sealed file.
                missing.append(.init(segmentIndex: nil, range: .init(startSeconds: cursor, endSeconds: nil),
                                     reason: .interruptedWhileWriting, canRetry: false))
            }
        }
        return .init(analysed: analysed, waiting: waiting, missing: missing)
    }

    // MARK: Session time and segment time

    /// The session instant of a media time in one segment's file. Media time runs from zero
    /// to the segment's length, both included: a sampled frame may sit exactly at the end.
    public func sessionSeconds(forSegment index: Int, mediaSeconds: Double) -> Double? {
        guard segments.indices.contains(index), mediaSeconds.isFinite, mediaSeconds >= 0 else { return nil }
        let segment = segments[index]
        if let duration = segment.durationSeconds, mediaSeconds > duration { return nil }
        return segment.startSeconds + mediaSeconds
    }

    /// The segment that covers a session instant. An instant shared by two segments, the
    /// end of one and the start of the next, belongs to the later one at media time zero.
    /// An end that no segment continues belongs to the segment that ends there. A frame
    /// keeps the segment it was sampled from; this lookup is never used to move it.
    public func location(atSessionSeconds seconds: Double) -> RecordingSessionTimeLocation {
        guard seconds.isFinite, seconds >= 0 else { return .invalid }
        var previous: Int?
        for (position, segment) in segments.enumerated() {
            if seconds < segment.startSeconds { return .outsideSegments(afterSegment: previous) }
            guard let end = segment.endSeconds else {
                return .segment(index: segment.index, mediaSeconds: seconds - segment.startSeconds)
            }
            if seconds < end { return .segment(index: segment.index, mediaSeconds: seconds - segment.startSeconds) }
            if seconds == end {
                let continued = position + 1 < segments.count && segments[position + 1].startSeconds == end
                if !continued { return .segment(index: segment.index, mediaSeconds: seconds - segment.startSeconds) }
            }
            previous = segment.index
        }
        return .outsideSegments(afterSegment: previous)
    }

    /// Cuts a session range at segment boundaries. Parts that no segment covers are left
    /// out. A nil end runs to the end of the session.
    public func pieces(ofSessionRangeFrom start: Double, to end: Double?) -> [RecordingSegmentPiece] {
        guard start.isFinite, end.map({ $0.isFinite && $0 >= start }) ?? true else { return [] }
        return segments.compactMap { segment in
            let from = max(start, segment.startSeconds)
            let until: Double?
            switch (end, segment.endSeconds) {
            case let (a?, b?): until = min(a, b)
            case let (a?, nil): until = a
            case let (nil, b?): until = b
            case (nil, nil): until = nil
            }
            if let until, until <= from { return nil }
            return RecordingSegmentPiece(segmentIndex: segment.index,
                startMediaSeconds: from - segment.startSeconds,
                endMediaSeconds: until.map { $0 - segment.startSeconds })
        }
    }

    /// The session's own-interface spans in one segment's media time, for the existing
    /// evidence preparation, which compares a frame's media time with these bounds.
    ///
    /// Spans are shifted, never cut at the segment's bounds: a span that ended half a second
    /// before the file began must still exclude that file's first frame, as it does on the
    /// session's clock. A shifted span may therefore start below zero or end past the file.
    /// Nil when the session did not establish its spans: unknown stays unknown.
    public func ownInterfaceIntervals(forSegment index: Int) -> OwnInterfaceIntervals? {
        guard segments.indices.contains(index), let session = context.ownInterfaceIntervals else { return nil }
        let segment = segments[index]
        let carry = Self.ownInterfaceCarrySeconds
        let rounding = Self.ownInterfaceRoundingSeconds
        let shifted = session.intervals.compactMap { span -> OwnInterfaceInterval? in
            if let segmentEnd = segment.endSeconds, span.startSeconds > segmentEnd + carry { return nil }
            if let spanEnd = span.endSeconds, spanEnd < segment.startSeconds - carry { return nil }
            return OwnInterfaceInterval(startSeconds: span.startSeconds - segment.startSeconds - rounding,
                endSeconds: span.endSeconds.map { $0 - segment.startSeconds + rounding })
        }
        return OwnInterfaceIntervals(shifted)
    }

    /// The recording context of one segment's file: its own identity and start instant, the
    /// session's zone, and the spans in its media time. The start is the session's start
    /// plus the segment's offset on the session's clock; like the session's, it is not
    /// measured against the file's first frame.
    public func recordingContext(forSegment index: Int) -> ObservationRecordingContext? {
        guard segments.indices.contains(index) else { return nil }
        let segment = segments[index]
        return try? ObservationRecordingContext(id: segment.id,
            startedAt: context.startedAt.addingTimeInterval(segment.startSeconds),
            timeZoneIdentifier: context.timeZoneIdentifier,
            ownInterfaceIntervals: ownInterfaceIntervals(forSegment: index))
    }

    /// Nil until the segment's end is known.
    public func reference(forSegment index: Int) -> ObservationSessionSegmentReference? {
        guard segments.indices.contains(index), let end = segments[index].endSeconds else { return nil }
        return try? ObservationSessionSegmentReference(sessionID: id, segmentIndex: index,
            startSeconds: segments[index].startSeconds, endSeconds: end)
    }
}
