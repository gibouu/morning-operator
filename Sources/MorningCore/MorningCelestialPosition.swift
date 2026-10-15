import Foundation

/// Decorative positions only. Values describe a drawing in unit screen coordinates;
/// they do not describe measured sky positions, light exposure, or screen brightness.
public struct MorningCelestialPosition: Sendable, Equatable {
    public let centerX: Double
    public let centerY: Double
    public let opacity: Double
}

public struct MorningCelestialScene: Sendable, Equatable {
    public let sun: MorningCelestialPosition
    public let moon: MorningCelestialPosition
}

/// A continuous, local-time journey along a circle: the sun rises at the left horizon,
/// arcs over the screen and sets at the right; at night the moon takes the same arc.
/// Fixed reference hours are used until the app has a real solar-time provider.
public enum MorningCelestialClock {
    /// The arc's centre sits on the horizon, near the bottom of the screen.
    static let horizonY = 0.84
    /// Horizontal radius in screen widths: the arc starts and ends at the screen's sides.
    static let radiusX = 0.5
    /// Width over height of a typical iPhone screen, so the arc is a circle on the phone
    /// rather than an ellipse stretched to the screen's height.
    static let referenceAspect = 0.46
    /// How far past each horizon a body keeps moving before it waits, hidden.
    static let overrun = 0.2

    public static func scene(atMinute minute: Double, solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let usable = solar.sunriseMinute.isFinite && solar.sunsetMinute.isFinite
            && solar.sunriseMinute >= 75 && solar.sunsetMinute <= 1320
            && solar.sunsetMinute - solar.sunriseMinute >= 120
        let day = usable ? solar : .fixed
        let safeMinute = minute.isFinite ? minute : 12 * 60
        let wrapped = safeMinute.truncatingRemainder(dividingBy: 1440)
        let t = wrapped < 0 ? wrapped + 1440 : wrapped
        let rise = day.sunriseMinute, set = day.sunsetMinute
        let daylight = set - rise
        let nightLength = 1440 - daylight
        let visible = smooth((t - rise + 45) / 60) * (1 - smooth((t - set + 15) / 60))
        let sun = arc(progress(since: rise, over: daylight, at: t))
        let moon = arc(progress(since: set, over: nightLength, at: t))
        return MorningCelestialScene(
            sun: .init(centerX: sun.x, centerY: sun.y, opacity: visible),
            moon: .init(centerX: moon.x, centerY: moon.y, opacity: 1 - visible))
    }

    /// 0 at the left horizon, 1 at the right. Outside its own span a body keeps going a
    /// little below the horizon, then waits; it changes sides halfway through the other
    /// span, where it is fully hidden and both sides sit at the same height.
    private static func progress(since start: Double, over span: Double, at t: Double) -> Double {
        var elapsed = (t - start).truncatingRemainder(dividingBy: 1440)
        if elapsed < 0 { elapsed += 1440 }
        let rest = 1440 - span
        if elapsed > span + rest / 2 { elapsed -= 1440 }
        return min(1 + overrun, max(-overrun, elapsed / span))
    }

    private static func arc(_ progress: Double) -> (x: Double, y: Double) {
        let angle = Double.pi * (1 - progress)
        return (0.5 + radiusX * cos(angle), horizonY - radiusX * referenceAspect * sin(angle))
    }

    public static func scene(at date: Date, calendar: Calendar = .current,
                             solar: MorningSolarDay = .fixed) -> MorningCelestialScene {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return scene(atMinute: Double(parts.hour ?? 12) * 60 + Double(parts.minute ?? 0)
                     + Double(parts.second ?? 0) / 60, solar: solar)
    }

    /// Pinning a theme in debug previews also pins its artwork to a representative time.
    public static func scene(for phase: MorningDayPhase) -> MorningCelestialScene {
        let minute: Double
        switch phase {
        case .dawn: minute = 6 * 60 + 45
        case .morning: minute = 9 * 60
        case .day: minute = 13 * 60
        case .evening: minute = 18 * 60 + 45
        case .night: minute = 23 * 60
        }
        return scene(atMinute: minute)
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
    private static func smooth(_ value: Double) -> Double {
        let t = clamp(value)
        return t * t * (3 - 2 * t)
    }
}
