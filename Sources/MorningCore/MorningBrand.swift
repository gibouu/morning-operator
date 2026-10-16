import Foundation

/// The branding follows the same solar moon-visibility threshold as MORE's scene.
public enum MorningBrandAppearance: String, Codable, Hashable, Sendable, CaseIterable {
    case day, night

    public static func resolve(moonOpacity: Double) -> Self {
        moonOpacity > 0.57 ? .night : .day
    }
}

public enum MorningBrandPalette {
    public static let paper: UInt32 = 0xF3ECDD
    public static let ink: UInt32 = 0x1B2F73
    public static let rust: UInt32 = 0xB84C25
    public static let night: UInt32 = 0x0C1226
    public static let moon: UInt32 = 0xEAD8B4
    public static let crater: UInt32 = 0xA2ABC0
}

public struct MorningBrandDot: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let radius: Double
    public let color: UInt32
}

public struct MorningBrandBounds: Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
}

/// Approved dotted artwork: custom m/r/e, with a complete sun or moon as the o.
/// Coordinates and three-decimal radii preserve the approved v02 SVG exactly.
public enum MorningBrandArtwork {
    // Both appearances use the same bounds, including all eight sun rays.
    public static let wordmarkBounds = MorningBrandBounds(x: -0.4, y: -2.4, width: 71.8, height: 18.8)
    public static let symbolBounds = MorningBrandBounds(x: 0, y: 0, width: 112, height: 68)

    public static func wordmark(appearance: MorningBrandAppearance, contrasting: Bool = false) -> [MorningBrandDot] {
        let ink = appearance == .night || contrasting ? MorningBrandPalette.paper : MorningBrandPalette.ink
        var dots = glyphs.flatMap { offset, rows in
            rows.enumerated().flatMap { row, columns in
                columns.enumerated().compactMap { column, value in
                    value == "#" ? MorningBrandDot(x: offset + Double(column), y: Double(row), radius: 0.38, color: ink) : nil
                }
            }
        }
        let radius = appearance == .day ? 5.9 : 7.25
        for y in -7...7 {
            for x in -7...7 {
                let distance = hypot(Double(x), Double(y))
                guard distance <= radius else { continue }
                let crater = hypot(Double(x) + 2.4, Double(y) + 1.6) < 1.7
                    || hypot(Double(x) - 1.9, Double(y) - 2.1) < 2.1
                    || hypot(Double(x) - 2.6, Double(y) + 2.9) < 1.2
                let color = appearance == .day
                    ? mix(0xD78A42, MorningBrandPalette.rust, (Double(y) + radius) / (radius * 2))
                    : (crater ? MorningBrandPalette.crater : MorningBrandPalette.moon)
                dots.append(MorningBrandDot(x: 31.5 + Double(x), y: 7 + Double(y),
                    radius: rounded(0.365 + 0.035 * (1 - distance / radius)), color: color))
            }
        }
        if appearance == .day {
            for (x, y) in [(0, -9), (6, -6), (9, 0), (6, 6), (0, 9), (-6, 6), (-9, 0), (-6, -6)] {
                dots.append(MorningBrandDot(x: 31.5 + Double(x), y: 7 + Double(y), radius: 0.4, color: MorningBrandPalette.rust))
            }
        }
        return dots
    }

    /// The standalone mark retains the approved sunrise icon by day, full moon by night.
    public static func symbol(appearance: MorningBrandAppearance, contrasting: Bool = false) -> [MorningBrandDot] {
        var dots: [MorningBrandDot] = []
        func dot(_ x: Double, _ y: Double, _ radius: Double, _ color: UInt32) {
            dots.append(MorningBrandDot(x: rounded(x), y: rounded(y), radius: rounded(radius), color: color))
        }
        if appearance == .day {
            let ink = contrasting ? MorningBrandPalette.paper : MorningBrandPalette.ink
            for row in 0...7 {
                for column in 0...13 {
                    let x = 30 + Double(column) * 4, y = 15 + Double(row) * 4
                    let distance = hypot(x - 56, y - 44) / 25
                    if distance <= 1 { dot(x, y, 1.15 + 0.7 * (1 - distance * distance), MorningBrandPalette.rust) }
                }
            }
            for degree in [25.0, 55, 90, 125, 155] {
                let angle = degree * .pi / 180
                for reach in [32.0, 37] { dot(56 + cos(angle) * reach, 44 - sin(angle) * reach, 1.6, ink) }
            }
            for column in 0...14 { dot(21 + Double(column) * 5, 49, 1.6, ink) }
            for column in 0...7 { dot(38 + Double(column) * 5, 56, 1.1, ink) }
        } else {
            for row in -7...7 {
                for column in -7...7 {
                    let x = Double(column) * 3.8, y = Double(row) * 3.8
                    let distance = hypot(x, y) / 26.5
                    guard distance <= 1 else { continue }
                    let crater = hypot(x + 9, y + 6) < 6.4 || hypot(x - 7, y - 8) < 8 || hypot(x - 10, y + 11) < 4.5
                    dot(56 + x, 32 + y, (1.14 + 0.48 * (1 - distance * distance)) * (crater ? 0.86 : 1),
                        crater ? MorningBrandPalette.crater : MorningBrandPalette.moon)
                }
            }
        }
        return dots
    }

    private static func rounded(_ value: Double) -> Double { (value * 1_000).rounded() / 1_000 }

    private static func mix(_ first: UInt32, _ second: UInt32, _ fraction: Double) -> UInt32 {
        [16, 8, 0].reduce(0) { color, shift in
            let start = Double((first >> shift) & 255), end = Double((second >> shift) & 255)
            return color | (UInt32((start + (end - start) * fraction).rounded()) << shift)
        }
    }

    // Frozen approved letter grid, independent of installed fonts or rendering scale.
    private static let glyphs: [(Double, [String])] = [
        (0, [
            "###.####.....####....",
            "##########.########..",
            "####################.",
            "####....#####....###.",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###",
            "###......###......###"
        ]),
        (43, [
            "#########...",
            "###########.",
            "###########.",
            "####.....###",
            "###......###",
            "###......###",
            "###.........",
            "###.........",
            "###.........",
            "###.........",
            "###.........",
            "###.........",
            "###.........",
            "###.........",
            "###........."
        ]),
        (57, [
            "....#######....",
            "...#########...",
            "..###########..",
            ".####.....####.",
            ".###.......###.",
            "###.........###",
            "###############",
            "###############",
            "##############.",
            "###............",
            ".###...........",
            ".####......##..",
            "..#####..####..",
            "...##########..",
            "....#######...."
        ])
    ]
}
