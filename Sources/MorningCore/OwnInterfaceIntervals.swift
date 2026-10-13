import Foundation

/// One span of a native recording during which MORE's own scene was not in the background.
/// Bounds are seconds after the recording output acknowledged its start, measured with one
/// monotonic clock. A bound is negative when the scene changed shortly before that callback:
/// the first frames may be slightly older than the callback. A nil end means the scene was still in front when capture ended, so the
/// span runs to the end of the recording: nothing after its start is known to show another app.
public struct OwnInterfaceInterval: Codable, Equatable, Sendable {
    public let startSeconds: Double
    public let endSeconds: Double?

    public init(startSeconds: Double, endSeconds: Double? = nil) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
    }
}

/// The spans of one native recording in which MORE itself was on screen. This is a fact the
/// app observed about its own scene; it is not derived from a frame's text.
///
/// Time base: a sampled frame carries a movie time, counted from the start of the file. These
/// bounds are counted from the output-start callback. The two are compared directly, on the
/// assumption that movie time zero and that callback are close. That alignment is not
/// measured, so `contains` widens every span by a margin on both sides.
///
/// An absent value means the app could not establish the spans (an imported file, an older
/// recording, an unobserved start). An empty value means MORE was never in front.
public struct OwnInterfaceIntervals: Codable, Equatable, Sendable {
    /// Covers the system's open and close animation, during which MORE is still drawn, the
    /// delay of the scene notification, and the unmeasured start alignment. It costs at most
    /// one sample of another app beside each visit to MORE.
    public static let defaultMarginSeconds: Double = 1
    public static let maximumIntervals = 256

    public let intervals: [OwnInterfaceInterval]

    /// Accepts any finite input: spans are sorted, and spans that touch or overlap are
    /// joined. Unusable spans are dropped. Beyond the limit the last kept span is left open,
    /// which excludes more rather than less.
    public init(_ intervals: [OwnInterfaceInterval]) {
        let usable = intervals.compactMap { interval -> OwnInterfaceInterval? in
            let start = interval.startSeconds
            guard start.isFinite else { return nil }
            guard let end = interval.endSeconds else { return .init(startSeconds: start) }
            guard end.isFinite, end >= start else { return nil }
            return .init(startSeconds: start, endSeconds: end)
        }.sorted { $0.startSeconds < $1.startSeconds }
        var joined: [OwnInterfaceInterval] = []
        for interval in usable {
            guard let last = joined.last else { joined.append(interval); continue }
            guard let lastEnd = last.endSeconds else { break }
            if interval.startSeconds <= lastEnd {
                let end = interval.endSeconds.map { max($0, lastEnd) }
                joined[joined.count - 1] = .init(startSeconds: last.startSeconds, endSeconds: end)
            } else if joined.count == Self.maximumIntervals {
                joined[joined.count - 1] = .init(startSeconds: last.startSeconds)
            } else {
                joined.append(interval)
            }
        }
        self.intervals = joined
    }

    /// True when a frame at this movie time must not be used as evidence. Both bounds are
    /// inclusive after widening: a frame exactly `marginSeconds` away from a span is excluded.
    /// An invalid time or margin is never matched by time; the text rule still applies.
    public func contains(mediaSeconds: Double, marginSeconds: Double = Self.defaultMarginSeconds) -> Bool {
        guard mediaSeconds.isFinite, marginSeconds.isFinite, marginSeconds >= 0 else { return false }
        return intervals.contains { interval in
            guard mediaSeconds >= interval.startSeconds - marginSeconds else { return false }
            guard let end = interval.endSeconds else { return true }
            return mediaSeconds <= end + marginSeconds
        }
    }

    private enum CodingKeys: String, CodingKey { case intervals }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try values.decode([OwnInterfaceInterval].self, forKey: .intervals))
    }
}

/// Collects when MORE's scene entered and left the background during one capture attempt.
/// Readings come from one monotonic clock supplied by the caller, in seconds. They are kept
/// as read, so a scene change and the recording-start callback may be delivered in either
/// order; spans are computed only once the start reading is known.
public struct OwnInterfaceIntervalRecorder: Equatable, Sendable {
    // Kept reports plus one open span for lost ones never exceed the span limit.
    public static let maximumTransitions = 2 * (OwnInterfaceIntervals.maximumIntervals - 1)

    private struct Transition: Equatable, Sendable {
        let inFront: Bool
        let reading: Double
    }

    /// The latest report, kept between attempts. Nil until the app has reported once.
    private var inFront: Bool?
    private var inFrontAtBegin: Bool?
    private var transitions: [Transition] = []
    private var collecting = false
    private var overflowed = false

    public init() {}

    /// A new capture attempt. Earlier transitions belong to another recording.
    public mutating func begin() {
        inFrontAtBegin = inFront
        transitions = []
        overflowed = false
        collecting = true
    }

    /// Reports the scene's current state. Repeating the same state changes nothing.
    /// "In front" means not in the background: a scene that is visible but inactive (the
    /// app switcher, a system sheet over MORE) is still drawn, so it does not end a span.
    public mutating func note(inFront value: Bool, at reading: Double) {
        guard value != inFront else { return }
        inFront = value
        guard collecting else { return }
        // A change that cannot be placed in time leaves the state after the last kept one
        // unknown, exactly like a lost report: everything from that one on is excluded, and
        // nothing later is trusted. Dropping the change instead could hide a visit to MORE
        // and let its frames through. The recorder's monotonic clock cannot produce such a
        // reading, so this costs nothing in practice.
        guard !overflowed, reading.isFinite, transitions.count < Self.maximumTransitions else {
            overflowed = true
            return
        }
        // One monotonic clock never goes back. If a reading does, keep the order of reports.
        transitions.append(.init(inFront: value, reading: max(reading, transitions.last?.reading ?? reading)))
    }

    /// The recording is final. Later scene changes are not recorded.
    ///
    /// Call this when the file is closed, not at the moment capture stops. A change reported
    /// just after the stop is kept: a scene report is delivered late, so within the margin
    /// it may describe the last frames, and a later one cannot match any frame. The cost is
    /// that a return to MORE within the margin of the end can exclude the last sample of
    /// another app. The opposite choice could let a frame of MORE through.
    public mutating func end() { collecting = false }

    /// Nil when the spans cannot be established: the start reading is missing, or the app
    /// had not reported its scene state before this attempt began.
    public func intervals(recordingStartedAt start: Double?) -> OwnInterfaceIntervals? {
        guard let start, start.isFinite, let inFrontAtBegin else { return nil }
        var result: [OwnInterfaceInterval] = []
        // A scene in front when the attempt began was in front before any report of it. Its
        // span starts no later than the start callback and no later than its first change.
        // A change just before the callback keeps its negative time, so the margin still
        // covers a first frame that is slightly older than the callback.
        let firstOffset = transitions.first.map { $0.reading - start }
        var openedAt: Double? = inFrontAtBegin ? min(0, firstOffset ?? 0) : nil
        for transition in transitions {
            let offset = transition.reading - start
            if transition.inFront {
                if openedAt == nil { openedAt = offset }
            } else if let opened = openedAt {
                result.append(.init(startSeconds: opened, endSeconds: offset))
                openedAt = nil
            }
        }
        if overflowed {
            // Reports were lost, so the state after the last kept one is unknown.
            let last = transitions.last.map { $0.reading - start } ?? 0
            result.append(.init(startSeconds: min(openedAt ?? last, last)))
        } else if let openedAt {
            result.append(.init(startSeconds: openedAt))
        }
        return OwnInterfaceIntervals(result)
    }
}
