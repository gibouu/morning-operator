#if DEBUG
import Foundation

/// A filming-only wall-clock-minute mapping. It never supplies dates to a
/// provider, changes a routine timer, or advances ambient animation time.
/// This type and its launch-argument parser are absent from Release builds.
public struct MorningSolarRecordingTimeline: Sendable, Equatable {
    public let duration: TimeInterval
    public let startMinute: Double
    public let endMinute: Double

    private init(duration: TimeInterval, startHour: Double, endHour: Double) {
        self.duration = duration
        startMinute = startHour * 60
        endMinute = endHour * 60
    }

    /// Opt-in only: `--theme-recording-seconds=300`, optionally accompanied by
    /// `--theme-recording-start-hour=6` / `--theme-recording-end-hour=23`.
    /// Invalid or repeated recording options disable the entire override.
    public static func from(arguments: [String]) -> Self? {
        let durationKey = "--theme-recording-seconds="
        let startKey = "--theme-recording-start-hour="
        let endKey = "--theme-recording-end-hour="
        func value(_ key: String, default fallback: Double? = nil) -> Double? {
            let matches = arguments.filter { $0.hasPrefix(key) }
            guard matches.count <= 1 else { return nil }
            guard let argument = matches.first else { return fallback }
            guard let number = Double(argument.dropFirst(key.count)), number.isFinite else { return nil }
            return number
        }
        guard let duration = value(durationKey), (10...1_800).contains(duration),
              let startHour = value(startKey, default: 6), (0...24).contains(startHour),
              let endHour = value(endKey, default: 23), (0...24).contains(endHour),
              startHour < endHour else { return nil }
        return Self(duration: duration, startHour: startHour, endHour: endHour)
    }

    /// The caller supplies monotonic elapsed seconds, independent of Date.now.
    /// Hold the final night frame rather than looping back to the morning.
    public func minute(atElapsed elapsed: TimeInterval) -> Double {
        let safeElapsed = elapsed.isNaN ? 0 : elapsed
        let progress = min(1, max(0, safeElapsed / duration))
        return startMinute + (endMinute - startMinute) * progress
    }
}
#endif
