import SwiftUI
import MorningCore

/// Every element of this mark is a separate circle. No stroked path, symbol font,
/// raster texture or runtime image download is used.
struct MorningDottedSunrise: Shape {
    enum Part { case sun, rays, all }
    var part: Part = .all

    func path(in rect: CGRect) -> Path {
        var path = Path()
        func dot(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) {
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
        if part != .rays {
            for row in 0...7 {
                let y = CGFloat(15 + row * 4)
                for column in 0...13 {
                    let x = CGFloat(30 + column * 4)
                    let distance = hypot(x - 56, y - 44) / 25
                    if distance <= 1 {
                        dot(x, y, 1.15 + 0.7 * (1 - distance * distance))
                    }
                }
            }
        }
        if part != .sun {
            // Separated round impressions suggest rays and the horizon.
            for degree in [25.0, 55, 90, 125, 155] {
                let angle = degree * .pi / 180
                for reach in [32.0, 37.0] {
                    dot(56 + cos(angle) * reach, 44 - sin(angle) * reach, 1.6)
                }
            }
            for column in 0...14 { dot(CGFloat(21 + column * 5), 49, 1.6) }
            for column in 0...7 { dot(CGFloat(38 + column * 5), 56, 1.1) }
        }
        let scale = min(rect.width / 112, rect.height / 68)
        return path.applying(CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
            tx: rect.midX - 56 * scale, ty: rect.midY - 34 * scale))
    }
}

/// A printed solar disc or crescent. A regular dot field gives the silhouette a
/// soft edge while each actual impression remains crisp and opaque.
struct MorningDottedDisc: Shape {
    enum Kind { case sun, moon }
    var kind: Kind = .sun
    var cells = 23

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let cell = side / CGFloat(cells)
        var path = Path()
        for row in 0..<cells {
            for column in 0..<cells {
                let x = (CGFloat(column) + 0.5) / CGFloat(cells)
                let y = (CGFloat(row) + 0.5) / CGFloat(cells)
                let distance = hypot(x - 0.5, y - 0.5) / 0.49
                guard distance < 1 else { continue }
                if kind == .moon, hypot(x - 0.68, y - 0.34) < 0.46 { continue }
                let radius = cell * (0.18 + 0.27 * (1 - distance * distance))
                let center = CGPoint(x: origin.x + x * side, y: origin.y + y * side)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

/// Short, separated impressions echo the rays of the app icon.
private struct MorningDottedSunRays: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        var path = Path()
        for ray in 0..<16 {
            let angle = Double(ray) * .pi / 8
            let count = ray.isMultiple(of: 2) ? 3 : 2
            for impression in 0..<count {
                let reach = side * (0.35 + CGFloat(impression) * 0.04)
                let radius = side * 0.01
                let x = rect.midX + cos(angle) * reach
                let y = rect.midY + sin(angle) * reach
                path.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

/// The scene is driven by local time, independently of routine completion.
/// It is decorative: cards and controls remain opaque reading surfaces above it.
struct MorningCelestialArtwork: View {
    let scene: MorningCelestialScene
    /// When the person last touched the sun: its lines ripple, then settle.
    var kick: Date? = nil
    var kicks: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.72, 300)
            ZStack {
                let sunX = geometry.size.width * scene.sun.centerX
                let sunY = geometry.size.height * scene.sun.centerY
                // The sun's darker lower half spreads into the page: densest and darkest
                // against the disc, thinning out to the sides and down.
                // The page colour follows the same fade: deepest rust against the sun's
                // lower half, lightening outwards, wider than tall and further down than up.
                // The sun's own cloud bands carry on across the sky at its height.
                MorningCloudBands(sun: CGPoint(x: sunX, y: sunY), diameter: diameter, kick: kick, kicks: kicks)
                    .opacity(scene.sun.opacity)
                MorningSolarArtwork(opacity: scene.sun.opacity)
                    .frame(width: diameter, height: diameter)

                    // A feathered rim rather than a hard outline.
                    .mask(RadialGradient(stops: [.init(color: .black, location: 0.78), .init(color: .clear, location: 1)],
                                         center: .center, startRadius: 0, endRadius: diameter / 2))
                    .position(x: sunX, y: sunY)

                let moonX = geometry.size.width * scene.moon.centerX
                let moonY = geometry.size.height * scene.moon.centerY
                let moonDiameter = diameter * 0.82
                // Stars above the horizon, faint and fixed.
                MorningStarField(horizon: moonY + moonDiameter * 0.9)
                    .opacity(scene.moon.opacity)
                MorningLunarArtwork()
                    .frame(width: moonDiameter, height: moonDiameter)

                    .opacity(scene.moon.opacity)
                    .position(x: moonX, y: moonY)

            }
            .animation(reduceMotion ? nil : .linear(duration: 60), value: scene)
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A small, fixed sequence of pseudo-random numbers, so the artwork is the same on
/// every launch and every device.
struct MorningSeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> CGFloat {
        state = state &+ 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z = z ^ (z >> 31)
        return CGFloat(z % 1_000_000) / 1_000_000
    }
    mutating func range(_ low: CGFloat, _ high: CGFloat) -> CGFloat { low + (high - low) * next() }
}

/// Long, soft streaks in the sun's own band colours: cream near its top, orange through
/// its middle, rust at its lower edge. They run past the disc so its clouds continue
/// into the sky instead of stopping at the rim.
struct MorningCloudBands: View {
    var sun: CGPoint
    var diameter: CGFloat
    var kick: Date? = nil
    /// How many times the sun was touched: each touch slides the whole sky one step right.
    var kicks: Int = 0

    var body: some View {
        let settling = kick.map { Date().timeIntervalSince($0) < 1.6 } ?? false
        TimelineView(.animation(paused: !settling)) { timeline in
            let t = kick.map { timeline.date.timeIntervalSince($0) } ?? 99
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                var random = MorningSeededRandom(seed: 7)
                context.addFilter(.blur(radius: 2.6))
                // Each touch glides the sky one step to the right, easing to a stop; nearer
                // (lower) lines travel a little further, as if the whole page drifted.
                let progress = 1 - pow(1 - min(1, t / 1.4), 3)
                let shift = 90 * (CGFloat(max(0, kicks - 1)) + (kicks > 0 ? progress : 0))
                for index in 0..<64 {
                    // Spread from the top of the screen to the bottom; colour follows the
                    // sun's bands: pale above it, orange at its middle, rust at and below its edge.
                    let y0 = random.range(-0.02, 1.02) * size.height
                    let band = (y0 - (sun.y - diameter / 2)) / diameter
                    let length = size.width * random.range(0.35, 0.95)
                    let start = random.range(-0.2, 1.0) * (size.width - length * 0.6)
                    let thickness = random.range(2.0, 6.5)
                    // Fainter towards the very top of the screen.
                    let alpha = random.range(0.35, 0.7) * (0.35 + 0.65 * min(1, max(0, y0 / (size.height * 0.35))))
                    let speed = 0.6 + 0.8 * min(1, max(0, y0 / size.height)) + random.range(-0.1, 0.1)
                    let span = size.width + length
                    var x = (start + length + shift * speed).truncatingRemainder(dividingBy: span)
                    if x < 0 { x += span }
                    x -= length
                    let y = y0
                    let colour: Color
                    if band < 0.3 { colour = Color(red: 0.97, green: 0.78, blue: 0.66) }
                    else if band < 0.65 { colour = Color(red: 0.95, green: 0.60, blue: 0.40) }
                    else { colour = Color(red: 0.82, green: 0.38, blue: 0.26) }
                    let rect = CGRect(x: x, y: y, width: length, height: thickness)
                    context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2),
                                 with: .linearGradient(Gradient(stops: [.init(color: colour.opacity(0), location: 0),
                                                                        .init(color: colour.opacity(alpha), location: 0.3),
                                                                        .init(color: colour.opacity(alpha), location: 0.7),
                                                                        .init(color: colour.opacity(0), location: 1)]),
                                                   startPoint: CGPoint(x: rect.minX, y: y), endPoint: CGPoint(x: rect.maxX, y: y)))
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// The sun's reflection on water: rows of short bright glints under the disc. Rows get
/// further apart and wider, glints thinner and fainter, the lower they are, as a sea
/// seen in perspective. With motion allowed, each glint breathes on its own slow beat.
struct MorningWaterGlints: View {
    var sun: CGPoint
    var diameter: CGFloat
    var glint: Color
    var animated: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animated)) { timeline in
            let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                var random = MorningSeededRandom(seed: 21)
                let top = sun.y + diameter * 0.42
                // The path of light: a soft golden column, narrow at the sun, wider below.
                var pillar = context
                pillar.addFilter(.blur(radius: 18))
                var column = Path()
                column.move(to: CGPoint(x: sun.x - diameter * 0.22, y: top))
                column.addLine(to: CGPoint(x: sun.x + diameter * 0.22, y: top))
                column.addLine(to: CGPoint(x: sun.x + diameter * 0.55, y: size.height + 20))
                column.addLine(to: CGPoint(x: sun.x - diameter * 0.55, y: size.height + 20))
                column.closeSubpath()
                pillar.fill(column, with: .linearGradient(Gradient(colors: [glint.opacity(0.55), glint.opacity(0.18), glint.opacity(0.05)]),
                                                           startPoint: CGPoint(x: sun.x, y: top),
                                                           endPoint: CGPoint(x: sun.x, y: size.height)))
                context.addFilter(.blur(radius: 0.9))
                var y = top
                var row = 0
                while y < size.height + 10 {
                    let depth = min(1, max(0, (y - top) / max(1, size.height - top)))
                    let spread = diameter * (0.30 + 0.75 * depth)
                    let count = 3 + Int(random.range(0, 4))
                    for index in 0..<count {
                        // Gathered towards the middle of the path, a few strays outside it.
                        let offset = (random.next() + random.next() + random.next()) / 1.5 - 1
                        let x = sun.x + offset * spread
                        let length = random.range(14, 58) * (1 - 0.25 * depth)
                        let thickness = 1.6 + 2.2 * depth
                        let phase = Double(random.next()) * 6.28 + Double(row) * 0.7 + Double(index)
                        let shimmer = 0.55 + 0.45 * sin(time * 1.4 + phase)
                        let alpha = (0.85 - 0.6 * depth) * (1 - 0.7 * abs(offset)) * shimmer
                        let drift = animated ? CGFloat(sin(time * 0.6 + phase)) * 3 : 0
                        let rect = CGRect(x: x - length / 2 + drift, y: y, width: length, height: thickness)
                        context.fill(Path(roundedRect: rect, cornerRadius: thickness / 2), with: .color(glint.opacity(alpha)))
                    }
                    y += 4 + 12 * depth
                    row += 1
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A few hundred faint stars, fixed in place and thinning towards the horizon.
struct MorningStarField: View {
    var horizon: CGFloat
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var random = MorningSeededRandom(seed: 3)
            let bottom = min(size.height, horizon)
            for _ in 0..<220 {
                let x = random.next() * size.width, y = random.next() * bottom
                let height = 1 - y / max(1, bottom)
                let r = random.range(0.4, 1.3)
                let alpha = random.range(0.25, 0.9) * (0.3 + 0.7 * height)
                context.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                             with: .color(.white.opacity(alpha)))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A radial fade with many stops on an eased curve, so the colour thins out without
/// the visible rings a two- or three-stop gradient draws on a phone screen.
enum MorningSmoothGlow {
    static func gradient(color: Color, strength: Double, radius: CGFloat) -> RadialGradient {
        let steps = 24
        let stops: [Gradient.Stop] = (0...steps).map { index in
            let t = Double(index) / Double(steps)
            // Smootherstep fall-off: flat at the centre, flat as it reaches the page.
            let eased = 1 - (t * t * t * (t * (t * 6 - 15) + 10))
            return .init(color: color.opacity(strength * eased), location: t)
        }
        return RadialGradient(stops: stops, center: .center, startRadius: 0, endRadius: radius)
    }
}

/// A fixed, very fine grain over the page. It breaks up the colour steps a smooth
/// gradient would otherwise show, and reads as paper rather than as a pattern.
struct MorningGrain: View {
    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            var light = Path(), dark = Path()
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
                return CGFloat(seed % 10_000) / 10_000
            }
            let count = Int(size.width * size.height / 9)
            for index in 0..<count {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                if index % 2 == 0 { light.addRect(rect) } else { dark.addRect(rect) }
            }
            context.fill(light, with: .color(.white.opacity(0.10)))
            context.fill(dark, with: .color(.black.opacity(0.06)))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A soft shadow made of dots around a point: near it the dots are large and close to
/// full strength, and they shrink and fade the further they are, so a body melts into
/// the page. Drawn once per size in one Canvas, grouped into a few strength levels.
struct MorningRadiantDots: View {
    var anchor: CGPoint
    var reach: CGFloat
    var color: Color

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: true) { context, size in
            let cell: CGFloat = 3.6
            let levels = 6
            var paths = Array(repeating: Path(), count: levels)
            var y: CGFloat = cell / 2
            var row = 0
            while y < size.height + cell {
                var x: CGFloat = row % 2 == 0 ? cell / 2 : cell
                while x < size.width + cell {
                    let dx = x - anchor.x
                    // Spread wider than tall, and further downwards than upwards.
                    let dy = (y - anchor.y) * (y < anchor.y ? 3.0 : 0.85)
                    let distance = (dx * dx + dy * dy).squareRoot() / reach
                    // Close to the body, and also everywhere lower on the page: the dots
                    // cover the whole screen, finest at the top and fullest at the bottom.
                    let strength = exp(-distance * distance * 1.3)
                    if strength > 0.02 {
                        let radius = 0.3 + 1.15 * strength
                        let level = min(levels - 1, Int(strength * CGFloat(levels)))
                        paths[level].addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    }
                    x += cell
                }
                y += cell * 0.866
                row += 1
            }
            for level in 0..<levels {
                context.fill(paths[level], with: .color(color.opacity(0.06 + 0.62 * Double(level + 1) / Double(levels))))
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// Fine dots in a body's colours, densest under its rim and fading outwards.
struct MorningDotHalo: View {
    var colors: [Color]
    var diameter: CGFloat
    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .mask(MorningHalftone(color: .black, opacity: 1, cell: 4.5, radius: 1.05))
            .mask(RadialGradient(stops: [.init(color: .clear, location: 0.38),
                                         .init(color: .black, location: 0.50),
                                         .init(color: .clear, location: 1)],
                                 center: .center, startRadius: 0, endRadius: diameter * 0.95))
            .frame(width: diameter * 1.9, height: diameter * 1.9)
    }
}

/// A column of fine dots falling from a body to the bottom of the page, strongest in
/// the middle and fading to the sides and towards the bottom.
struct MorningDotTrail: View {
    var colors: [Color]
    var width: CGFloat
    var height: CGFloat
    var body: some View {
        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
            .mask(MorningHalftone(color: .black, opacity: 1, cell: 4.5, radius: 1.05))
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black.opacity(0.75), location: 0.5),
                                         .init(color: .black.opacity(0.35), location: 1)],
                                 startPoint: .top, endPoint: .bottom))
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.5),
                                         .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: height)
    }
}

/// The moon in the sun's manner: a softly lit disc of silver grain with a few faint
/// seas, a feathered rim and fine dots over it. Drawn, not a photograph.
struct MorningLunarArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            let d = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(red: 0.97, green: 0.96, blue: 0.92),
                                                      Color(red: 0.80, green: 0.82, blue: 0.88),
                                                      Color(red: 0.50, green: 0.53, blue: 0.66)],
                                             center: UnitPoint(x: 0.36, y: 0.32), startRadius: 0, endRadius: d * 0.72))
                Group {
                    Circle().frame(width: d * 0.30, height: d * 0.24).offset(x: -d * 0.12, y: -d * 0.08)
                    Circle().frame(width: d * 0.20, height: d * 0.18).offset(x: d * 0.16, y: d * 0.10)
                    Circle().frame(width: d * 0.13, height: d * 0.12).offset(x: -d * 0.04, y: d * 0.22)
                    Circle().frame(width: d * 0.09, height: d * 0.09).offset(x: d * 0.20, y: -d * 0.20)
                }
                .foregroundStyle(Color(red: 0.45, green: 0.48, blue: 0.62).opacity(0.28))
                .blur(radius: d * 0.025)
            }
            .frame(width: d, height: d)
            .mask(RadialGradient(stops: [.init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                 center: .center, startRadius: 0, endRadius: d / 2))
        }
        .accessibilityHidden(true)
    }
}

/// A sparse frame made from round ink impressions. Reading surfaces stay solid;
/// only the edge changes, so the pattern never sits behind a paragraph.
struct MorningDottedFrame: Shape {
    var cornerRadius: CGFloat = 10
    var spacing: CGFloat = 8
    var dotRadius: CGFloat = 0.85

    func path(in rect: CGRect) -> Path {
        // Card edges are drawn by the cards themselves now; no dotted outline.
        return Path()
    }

    private func dottedPath(in rect: CGRect) -> Path {
        let inset = max(1, dotRadius)
        let bounds = rect.insetBy(dx: inset, dy: inset)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let radius = min(cornerRadius, bounds.width / 2, bounds.height / 2)
        let horizontal = max(0, bounds.width - 2 * radius)
        let vertical = max(0, bounds.height - 2 * radius)
        var path = Path()
        func dot(_ point: CGPoint) {
            path.addEllipse(in: CGRect(x: point.x - dotRadius, y: point.y - dotRadius,
                                      width: dotRadius * 2, height: dotRadius * 2))
        }
        func edge(from start: CGPoint, to end: CGPoint, length: CGFloat) {
            let count = max(1, Int((length / max(4, spacing)).rounded()))
            for index in 0...count {
                let t = CGFloat(index) / CGFloat(count)
                dot(CGPoint(x: start.x + (end.x - start.x) * t,
                            y: start.y + (end.y - start.y) * t))
            }
        }
        edge(from: CGPoint(x: bounds.minX + radius, y: bounds.minY), to: CGPoint(x: bounds.maxX - radius, y: bounds.minY), length: horizontal)
        edge(from: CGPoint(x: bounds.minX + radius, y: bounds.maxY), to: CGPoint(x: bounds.maxX - radius, y: bounds.maxY), length: horizontal)
        edge(from: CGPoint(x: bounds.minX, y: bounds.minY + radius), to: CGPoint(x: bounds.minX, y: bounds.maxY - radius), length: vertical)
        edge(from: CGPoint(x: bounds.maxX, y: bounds.minY + radius), to: CGPoint(x: bounds.maxX, y: bounds.maxY - radius), length: vertical)
        let corners: [(CGPoint, Double)] = [
            (CGPoint(x: bounds.maxX - radius, y: bounds.minY + radius), -90),
            (CGPoint(x: bounds.maxX - radius, y: bounds.maxY - radius), 0),
            (CGPoint(x: bounds.minX + radius, y: bounds.maxY - radius), 90),
            (CGPoint(x: bounds.minX + radius, y: bounds.minY + radius), 180)
        ]
        let arcCount = max(2, Int((radius * .pi / 2 / max(4, spacing)).rounded()))
        for (center, degrees) in corners {
            for index in 1..<arcCount {
                let angle = (degrees + Double(index) / Double(arcCount) * 90) * .pi / 180
                dot(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        }
        return path
    }
}

/// Decorative time never moves the solar clock. Paper and celestial bodies stay
/// outside the ambient timeline; the same passing breath bends the little trees.
struct MorningQuietLandscape: View {
    let scene: MorningCelestialScene
    var weather: MorningWeatherScene?
    var animated = true
    var active = true
    var strongInk = false
    @ViewState private var pausedAt: Date?
    @ViewState private var suspendedInterval: TimeInterval = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let night = scene.moon.opacity
            let visibility = weather?.celestialVisibility ?? 1
            let altitude = min(1, max(0, (0.76 - scene.sun.centerY) / 0.58))
            let diameter = min(size.width * 0.30, min(size.height * 0.25, 142))
            let sunlight = LinearGradient(colors: [Color(red: 1, green: 0.85, blue: 0.43),
                Color(red: 0.96, green: 0.38 + 0.34 * altitude, blue: 0.12 + 0.13 * altitude)],
                startPoint: .top, endPoint: .bottom)
            ZStack {
                MorningQuietSky(night: night, weather: weather, strongInk: strongInk)
                MorningWallpaperStars(night: night * (weather?.starVisibility ?? 1), animated: animated,
                                      active: active, pausedAt: pausedAt, suspendedInterval: suspendedInterval)
                ZStack {
                    MorningDottedSunRays().fill(sunlight)
                        .frame(width: diameter * 1.6, height: diameter * 1.6)
                    MorningDottedDisc(cells: 37).fill(sunlight)
                        .frame(width: diameter, height: diameter)
                }
                .position(position(scene.sun, in: size, radius: diameter * 0.72))
                .opacity(scene.sun.opacity * visibility)
                MorningDottedDisc(kind: .moon, cells: 37)
                    .fill(Color(red: 0.92, green: 0.91, blue: 0.81))
                    .frame(width: diameter * 0.88, height: diameter * 0.88)
                    .position(position(scene.moon, in: size, radius: diameter * 0.44))
                    .opacity(night * visibility)
                if let weather {
                    // The expensive dot grids are traced once, outside the timeline.
                    let stamps = cloudStamps(size: size, weather: weather)
                    let moves = weather.cloudCoverage > 0 || weather.precipitation != .none
                        || weather.windIntensity > 0 || weather.windGustIntensity > 0 || weather.atmosphericVeil > 0
                        || weather.atmosphere != .clear || weather.condition == .hot
                    TimelineView(.animation(minimumInterval: 1 / 24,
                                            paused: !MorningSkyAnimation.runs(animated && active && moves))) { timeline in
                        let seconds = MorningSkyAnimation.time(at: pausedAt ?? timeline.date, animated: animated,
                                                              suspendedInterval: suspendedInterval)
                        Canvas(opaque: false, rendersAsynchronously: true) { context, canvas in
                            clouds(stamps, in: context, size: canvas, weather: weather, night: night, seconds: seconds)
                            atmosphere(in: context, size: canvas, weather: weather, night: night, seconds: seconds)
                            precipitation(in: context, size: canvas, weather: weather, night: night, seconds: seconds)
                            wind(in: context, size: canvas, weather: weather, night: night, seconds: seconds)
                            ground(in: context, size: canvas, night: night, weather: weather, seconds: seconds)
                        }
                    }
                } else {
                    Canvas(opaque: false, rendersAsynchronously: true) { context, canvas in
                        ground(in: context, size: canvas, night: night)
                    }
                }
            }
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .onChange(of: active, initial: true) { _, active in
            // Hidden Home freezes its pose and resumes from there, without rewinding.
            if active, let pause = pausedAt {
                suspendedInterval += max(0, Date.now.timeIntervalSince(pause))
                pausedAt = nil
            } else if !active, pausedAt == nil {
                pausedAt = .now
            }
        }
    }

    private func position(_ body: MorningCelestialPosition, in size: CGSize, radius: CGFloat) -> CGPoint {
        let progress = min(1, max(0, (body.centerX - 0.12) / 0.76))
        let height = min(1, max(0, (0.76 - body.centerY) / 0.58))
        let inset = max(size.width * 0.16, radius)
        return CGPoint(x: inset + (size.width - 2 * inset) * progress, y: size.height * (0.61 - 0.23 * height))
    }

    private func dot(_ path: inout Path, x: Double, y: Double, radius: Double) {
        path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
    }

    private struct CloudStamp {
        let dots: Path
        let origin: CGPoint
        let width: Double
        let speed: Double
    }

    private func cloudStamps(size: CGSize, weather: MorningWeatherScene) -> [CloudStamp] {
        guard weather.cloudCoverage > 0 else { return [] }
        let placements = [(0.16, 0.22, 0.74), (0.83, 0.29, 0.9), (0.53, 0.13, 1.0),
                          (0.32, 0.42, 1.1), (0.82, 0.51, 0.85), (0.13, 0.65, 1.0), (0.58, 0.68, 0.8)]
        let count = min(placements.count, max(1, Int(ceil(weather.cloudCoverage * 7))))
        return (0..<count).map { index in
            let placement = placements[index]
            let width = size.width * (0.38 + 0.24 * weather.cloudCoverage) * placement.2
            let height = width * 0.34
            var dots = Path()
            for row in 0...Int(height / 3.7) {
                for column in 0...Int(width / 3.7) {
                    let x = Double(column) * 3.7, y = Double(row) * 3.7
                    let nx = x / width, ny = y / height
                    let base = pow((nx - 0.5) / 0.49, 2) + pow((ny - 0.69) / 0.27, 2)
                    let left = pow((nx - 0.31) / 0.22, 2) + pow((ny - 0.47) / 0.39, 2)
                    let top = pow((nx - 0.57) / 0.25, 2) + pow((ny - 0.39) / 0.44, 2)
                    let edge = min(base, min(left, top))
                    guard edge < 1 else { continue }
                    let grain = Double((row * 37 + column * 13 + index * 7) % 11) / 11
                    dot(&dots, x: x, y: y, radius: (0.42 + grain * 0.49) * (1 - edge * 0.28))
                }
            }
            return CloudStamp(dots: dots,
                              origin: CGPoint(x: size.width * placement.0 - width / 2,
                                              y: size.height * placement.1 - height / 2), width: width,
                              speed: 2.3 * (0.7 + Double(index) * 0.11) + weather.windIntensity * 6)
        }
    }

    private func clouds(_ stamps: [CloudStamp], in context: GraphicsContext, size: CGSize,
                        weather: MorningWeatherScene, night: Double, seconds: Double) {
        let ink = Color(red: 0.36 + night * 0.23, green: 0.40 + night * 0.23, blue: 0.45 + night * 0.29)
            .opacity(strongInk ? 0.75 : 0.44 + weather.cloudCoverage * 0.20)
        for stamp in stamps {
            let span = size.width + stamp.width + 40
            // Wind is reported as the direction it comes FROM. A westerly
            // weather observation therefore carries cloud and rain to the right.
            let drift = seconds * stamp.speed + sin(seconds * 0.28) * weather.windGustIntensity * 8
            let x = MorningSkyAnimation.wrap(stamp.origin.x + stamp.width + 20
                + drift * weather.windHorizontalDirection, span: span)
                - stamp.width - 20
            // Wrap only while the whole cloud is beyond the edge; no visible pop.
            for copy in [-span, 0, span] where x + copy < size.width && x + copy + stamp.width > 0 {
                var cloud = context
                cloud.translateBy(x: x + copy, y: stamp.origin.y)
                cloud.fill(stamp.dots, with: .color(ink))
            }
        }
    }

    private func precipitation(in context: GraphicsContext, size: CGSize, weather: MorningWeatherScene, night: Double, seconds: Double) {
        guard weather.precipitation != .none, weather.precipitationIntensity > 0 else { return }
        var random = MorningSeededRandom(seed: 731)
        var dots = Path()
        let count = Int(25 + 125 * weather.precipitationIntensity)
        let gust = passingBreath(seconds: seconds, intensity: weather.windIntensity,
                                 gust: weather.windGustIntensity)
        for index in 0..<count {
            let seedX = random.range(0.025, 0.975) * size.width
            let seedY = random.range(0.10, 0.94) * size.height
            let icy = weather.precipitation == .freezingRain || weather.precipitation == .hail
            let snow = weather.precipitation == .snow
                || (weather.precipitation == .wintryMix && index.isMultiple(of: 2))
                || (weather.precipitation == .sleet && index.isMultiple(of: 3))
            let depth = 0.65 + Double(index % 7) / 10
            let speed = (snow ? 13 : 70 + weather.precipitationIntensity * 75) * depth
            let slant = (0.07 + weather.windIntensity * 0.85 + gust * 0.22) * weather.windHorizontalDirection
            let sway = snow ? sin(seconds * 0.55 + Double(index)) * 9 : 0
            let x = MorningSkyAnimation.wrap(seedX + 32 + seconds * speed * slant + sway,
                                            span: size.width + 64) - 32
            let y = MorningSkyAnimation.wrap(seedY + 32 + seconds * speed, span: size.height + 64) - 32
            if snow {
                let r = random.range(0.65, 1.35)
                dot(&dots, x: x, y: y, radius: r)
                if index.isMultiple(of: 3) {
                    for offset in [-3.0, 3.0] {
                        dot(&dots, x: x + offset, y: y, radius: 0.55)
                        dot(&dots, x: x, y: y + offset, radius: 0.55)
                    }
                }
            } else if weather.precipitation == .hail {
                dot(&dots, x: x, y: y, radius: 1.7)
                dot(&dots, x: x - 0.8, y: y + 4, radius: 0.55)
            } else {
                let length = 3 + Int(weather.precipitationIntensity * 4)
                for step in 0..<length {
                    let distance = Double(step) * 2.8
                    dot(&dots, x: x + distance * slant,
                        y: y + distance, radius: icy ? 0.88 : 0.64)
                }
                if icy { dot(&dots, x: x - 1, y: y + 8, radius: 1.1) }
            }
        }
        let ink = Color(red: 0.31 + 0.4 * night, green: 0.44 + 0.3 * night, blue: 0.57 + 0.28 * night)
        context.fill(dots, with: .color(ink.opacity(strongInk ? 0.9 : 0.67)))
        if weather.precipitation == .rain, seconds > 0 {
            // Small, staggered rings where the rain meets the printed ground.
            for index in 0..<4 {
                let progress = MorningSkyAnimation.wrap(seconds / 3.6 + Double(index) * 0.27, span: 1)
                let radius = 2 + progress * 7
                var ring = Path()
                for step in 0..<18 {
                    let angle = Double(step) / 18 * .pi * 2
                    dot(&ring, x: size.width * (0.23 + Double(index) * 0.18) + cos(angle) * radius,
                        y: size.height * (0.915 + Double(index % 2) * 0.013) + sin(angle) * radius * 0.24,
                        radius: 0.45)
                }
                context.fill(ring, with: .color(ink.opacity(sin(progress * .pi) * 0.38)))
            }
        }
        if weather.lightning {
            // A printed bolt, never a flashing light.
            var bolt = Path()
            let points = [CGPoint(x: size.width * 0.76, y: size.height * 0.27),
                          CGPoint(x: size.width * 0.70, y: size.height * 0.35),
                          CGPoint(x: size.width * 0.75, y: size.height * 0.34),
                          CGPoint(x: size.width * 0.68, y: size.height * 0.43)]
            for index in 0..<(points.count - 1) {
                for step in 0...12 {
                    let t = Double(step) / 12
                    dot(&bolt, x: points[index].x + (points[index + 1].x - points[index].x) * t,
                        y: points[index].y + (points[index + 1].y - points[index].y) * t, radius: 1.1)
                }
            }
            context.fill(bolt, with: .color(Color(red: 0.91, green: 0.72, blue: 0.37).opacity(0.8)))
        }
    }

    private func atmosphere(in context: GraphicsContext, size: CGSize, weather: MorningWeatherScene, night: Double, seconds: Double) {
        guard weather.atmosphere != .clear || weather.atmosphericVeil > 0
                || weather.condition == .hot || weather.condition == .frigid else { return }
        var dots = Path()
        let fog = weather.atmosphere == .fog
        let veil = max(fog ? 0.6 : 0, weather.atmosphericVeil)
        let bands = 3 + Int(veil * 6)
        for band in 0..<bands {
            let y = size.height * (0.29 + Double(band) * 0.068)
            for column in -4...Int(size.width / 4.8 + 4) {
                for row in 0..<(2 + Int(veil * 5)) {
                    let x = Double(column) * 4.8
                    let wave = sin(x / 50 + Double(band) + seconds * 0.18) * (weather.condition == .hot ? 9 : 2)
                    dot(&dots, x: x + sin(seconds * 0.09 + Double(band)) * (8 + veil * 8),
                        y: y + Double(row) * 4 + wave,
                        radius: 0.43 + Double(abs(column * 7 + row) % 5) * 0.07)
                }
            }
        }
        let warm = weather.atmosphere == .dust || weather.condition == .hot
        let ink = warm ? Color(red: 0.65, green: 0.42, blue: 0.21)
            : Color(red: 0.48 + night * 0.2, green: 0.51 + night * 0.2, blue: 0.55 + night * 0.22)
        context.fill(dots, with: .color(ink.opacity(strongInk ? 0.7 : 0.18 + veil * 0.33)))
        if weather.condition == .frigid {
            var frost = Path()
            for x in stride(from: 18.0, to: size.width, by: 35) {
                for step in -3...3 {
                    dot(&frost, x: x + Double(step) * 2.3, y: size.height * 0.88, radius: 0.75)
                    dot(&frost, x: x, y: size.height * 0.88 + Double(step) * 2.3, radius: 0.75)
                }
            }
            context.fill(frost, with: .color(ink.opacity(0.8)))
        }
    }

    private func wind(in context: GraphicsContext, size: CGSize, weather: MorningWeatherScene, night: Double, seconds: Double) {
        // Calm sustained wind can still carry measured gusts. Keep those breaths
        // occasional and smaller than an equally strong sustained wind.
        let intensity = max(weather.windIntensity, weather.windGustIntensity * 0.35)
        guard intensity > 0 else { return }
        let gust = weather.windGustIntensity
        let count = 2 + Int(ceil(intensity * 5))
        let ink = Color(red: 0.40 + night * 0.27, green: 0.44 + night * 0.26, blue: 0.49 + night * 0.29)
        var random = MorningSeededRandom(seed: 2913)
        for lane in 0..<count {
            // A breeze leaves long quiet gaps. Stronger wind sends larger,
            // overlapping breaths more often, rather than speeding up a loop.
            let period = 19 - intensity * 11 + Double(random.range(-1.5, 1.5))
            let duration = 5.7 - intensity * 1.4
            let offset = Double(random.range(0, 1)) * period
            let elapsed = MorningSkyAnimation.wrap(seconds + offset, span: period)
            let progress = elapsed / duration
            let height = size.height * Double(random.range(0.17, 0.80))
            let phase = Double(random.range(0, .pi * 2))
            guard progress < 1 else { continue }
            let swell = pow(sin(progress * .pi), 1.3)
            let length = size.width * (0.12 + intensity * 0.29 + gust * 0.07)
            let amplitude = 3 + intensity * 12 + swell * gust * 9
            let travel = -length + progress * (size.width + length * 2)
            let strands = 2 + Int(intensity * 2)
            for strand in 0..<strands {
                var ribbon = Path()
                var down = Path()
                let separation = Double(strand) * (3 + intensity * 4)
                let steps = 28 + Int(intensity * 25)
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    let turn = max(0, (t - 0.68) / 0.32) * .pi * 1.35
                    let curl = (4 + intensity * 12) * (1 - Double(strand) * 0.12)
                    let localX = (t - 0.5) * length + (cos(turn) - 1) * curl
                    let x = weather.windHorizontalDirection > 0 ? travel + localX : size.width - travel - localX
                    let y = height + sin(t * .pi * 1.25 + phase) * amplitude
                        - sin(turn) * curl + separation
                    let taper = pow(sin(t * .pi), 0.55)
                    dot(&ribbon, x: x, y: y, radius: (0.35 + intensity * 0.47) * taper)
                    if step.isMultiple(of: 3) {
                        // A few detached impressions make each breath feel soft
                        // and airborne, while retaining the printed dot language.
                        dot(&down, x: x - weather.windHorizontalDirection * 5,
                            y: y + 5 + sin(t * 9 + Double(lane)) * 3,
                            radius: (0.29 + intensity * 0.35) * taper)
                    }
                }
                let opacity = swell * (strongInk ? 0.85 : 0.48 + intensity * 0.20)
                    * (1 - Double(strand) * 0.16)
                context.fill(ribbon, with: .color(ink.opacity(opacity)))
                context.fill(down, with: .color(ink.opacity(opacity * 0.38)))
            }
        }
    }

    /// One slow, smooth pressure wave links the falling rain, grass and trees.
    /// There is no stateful particle simulation to jump on pause or resume.
    private func passingBreath(seconds: Double, intensity: Double, gust: Double) -> Double {
        let wave = (1 + sin(seconds * (0.42 + intensity * 0.28) - 1.2)) / 2
        return pow(wave, 3) * max(intensity, gust)
    }

    private func ground(in context: GraphicsContext, size: CGSize, night: Double,
                        weather: MorningWeatherScene? = nil, seconds: Double = 0) {
        let horizon = size.height * 0.91
        let scale = min(1.4, size.width / 360)
        var land = Path()
        for column in 0...Int(size.width / 4) {
            let x = Double(column) * 4
            dot(&land, x: x, y: horizon + sin(Double(column) * 0.12) * 1.6, radius: 0.65)
            if column.isMultiple(of: 3) { dot(&land, x: x + 1, y: horizon + 10 + sin(Double(column)) * 3, radius: 0.4) }
        }
        for (fraction, proportion) in [(0.09, 0.72), (0.20, 1.0), (0.80, 0.88), (0.91, 0.63)] {
            let x = size.width * fraction
            let base = horizon - 1
            let tree = scale * proportion * 1.17
            let intensity = weather?.windIntensity ?? 0
            let breath = passingBreath(seconds: seconds - fraction * 1.5, intensity: intensity,
                                      gust: weather?.windGustIntensity ?? 0)
            let direction = weather?.windHorizontalDirection ?? 1
            let lean = direction * (intensity * 2 + breath * 8) * tree
            for row in 0...11 {
                let growth = Double(row) / 18
                dot(&land, x: x + lean * growth * growth, y: base - Double(row) * 3.5 * tree, radius: 0.85 * tree)
            }
            for row in 0...14 {
                let y = base - (23 + Double(row) * 2.6) * tree
                let halfWidth = sqrt(max(0, 1 - pow((Double(row) - 7) / 7.5, 2))) * 18 * tree
                for column in -8...8 {
                    let dx = Double(column) * 2.7 * tree
                    guard abs(dx) <= halfWidth else { continue }
                    let grain = Double((row * 13 + (column + 8) * 7) % 9) / 9
                    let height = (base - y) / (62 * tree)
                    let flutter = sin(seconds * 1.8 + Double(row) * 0.4) * intensity * 0.6
                    dot(&land, x: x + dx + lean * height * height + flutter,
                        y: y + abs(lean) * height * 0.07, radius: (0.55 + grain * 0.45) * tree)
                }
            }
        }
        for fraction in [0.29, 0.34, 0.66, 0.72] {
            let breath = passingBreath(seconds: seconds - fraction, intensity: weather?.windIntensity ?? 0,
                                      gust: weather?.windGustIntensity ?? 0)
            for step in 0...3 {
                let growth = Double(step)
                let lean = growth * breath * 1.7 * (weather?.windHorizontalDirection ?? 1)
                dot(&land, x: size.width * fraction + growth + lean,
                    y: horizon - growth * 2 + abs(lean) * 0.25, radius: 0.55)
            }
        }
        let ink = Color(red: 0.43 - 0.03 * night, green: 0.35 + 0.12 * night, blue: 0.25 + 0.34 * night)
        context.fill(land, with: .color(ink.opacity(0.80)))
        if let humidity = weather?.humidity, humidity > 0.82 {
            var dew = Path()
            for fraction in [0.29, 0.34, 0.66, 0.72] {
                let breath = passingBreath(seconds: seconds - fraction, intensity: weather?.windIntensity ?? 0,
                                          gust: weather?.windGustIntensity ?? 0)
                let lean = 3 * breath * 1.7 * (weather?.windHorizontalDirection ?? 1)
                dot(&dew, x: size.width * fraction + 3 + lean,
                    y: horizon - 6 + abs(lean) * 0.25, radius: 1.05)
            }
            context.fill(dew, with: .color(Color(red: 0.71, green: 0.79, blue: 0.78)
                .opacity(min(0.8, (humidity - 0.82) * 4))))
        }
    }
}

private enum MorningSkyAnimation {
    static let epoch = Date.now
    static let previewTime: Double? = {
        #if DEBUG
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--theme-motion-time=") }),
           let time = Double(argument.dropFirst("--theme-motion-time=".count)),
           time.isFinite, (0...86_400).contains(time) { return time }
        #endif
        return nil
    }()

    static func runs(_ animated: Bool) -> Bool { animated && previewTime == nil }
    static func time(at date: Date, animated: Bool, suspendedInterval: TimeInterval) -> Double {
        animated ? (previewTime ?? max(0, date.timeIntervalSince(epoch) - suspendedInterval)) : 0
    }
    static func wrap(_ value: Double, span: Double) -> Double { value - floor(value / span) * span }
}

private struct MorningWallpaperStars: View {
    var night: Double
    var animated: Bool
    var active: Bool
    var pausedAt: Date?
    var suspendedInterval: TimeInterval
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24,
                                paused: !MorningSkyAnimation.runs(animated && active) || night < 0.01)) { timeline in
            let seconds = MorningSkyAnimation.time(at: pausedAt ?? timeline.date, animated: animated,
                                                  suspendedInterval: suspendedInterval)
            Canvas(opaque: false, rendersAsynchronously: true) { context, size in
                var random = MorningSeededRandom(seed: 4701)
                for index in 0..<110 {
                    let point = CGPoint(x: random.range(0.035, 0.965) * size.width,
                                        y: random.range(0.055, 0.96) * size.height)
                    let phase = random.range(0, .pi * 2)
                    let speed = random.range(0.38, 0.85)
                    let pulse = (1 + sin(seconds * speed + phase)) / 2
                    let bright = index.isMultiple(of: 9)
                    let brightness = animated ? 0.22 + (bright ? 0.58 : 0.35) * pow(pulse, 1.4) : 0.64
                    let radius = bright ? 1.15 : random.range(0.4, 0.78)
                    var path = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                    if bright {
                        for reach in [3.2, 5.6] {
                            for axis in [CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 0, y: -1)] {
                                let r = reach < 4 ? 0.6 : 0.35
                                path.addEllipse(in: CGRect(x: point.x + axis.x * reach - r, y: point.y + axis.y * reach - r, width: r * 2, height: r * 2))
                            }
                        }
                    }
                    context.fill(path, with: .color(Color(red: 0.92, green: 0.91, blue: 0.83).opacity(brightness * night)))
                }
                if animated, night > 0.35 { shootingStar(in: context, size: size, seconds: seconds) }
            }
        }
    }

    private func shootingStar(in context: GraphicsContext, size: CGSize, seconds: Double) {
        let cycle = floor(seconds / 47)
        let progress = (seconds - cycle * 47 - 18) / 1.8
        guard (0...1).contains(progress) else { return }
        var random = MorningSeededRandom(seed: UInt64(cycle) &+ 9163)
        let direction = Int(cycle).isMultiple(of: 2) ? 1.0 : -1.0
        let start = CGPoint(x: size.width * random.range(0.25, 0.65), y: size.height * random.range(0.13, 0.29))
        let dx = size.width * 0.29 * direction, dy = size.height * 0.095
        let visibility = pow(sin(progress * .pi), 2) * night
        for step in 0..<18 {
            let tail = Double(step) / 17
            let t = max(0, progress - tail * 0.22)
            let radius = 0.4 + (1 - tail) * 0.65
            let point = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            let dot = Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(Color(red: 0.95, green: 0.91, blue: 0.75)
                .opacity(visibility * (1 - tail) * 0.78)))
        }
    }
}

struct MorningQuietSky: View {
    var night: Double
    var weather: MorningWeatherScene?
    var strongInk = false
    var body: some View {
        let clouds = weather?.cloudCoverage ?? 0
        let apparent = weather?.apparentTemperatureCelsius
        let cold = weather?.precipitation == .snow || weather?.condition == .frigid || (apparent.map { $0 < 2 } ?? false)
        let warmth = apparent.map { min(1, max(0, ($0 - 24) / 16)) } ?? 0
        let sunStrength = min(1, Double(weather?.uvIndex ?? 0) / 11) * (1 - clouds) * (1 - night)
        ZStack {
            Color(red: 1 - clouds * 0.07, green: 0.97 - clouds * 0.035 - warmth * 0.018,
                  blue: cold ? 0.97 : 0.90 + clouds * 0.035 - warmth * 0.035)
            Color(red: 0.055 + clouds * 0.015, green: 0.065 + clouds * 0.015, blue: 0.12 + clouds * 0.025).opacity(night)
            RadialGradient(colors: [Color(red: 1, green: 0.76, blue: 0.40).opacity(sunStrength * 0.13), .clear],
                           center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: 260)
            MorningHalftone(color: night > 0.5 ? Color(red: 0.75, green: 0.77, blue: 0.86) : Color(red: 0.35, green: 0.32, blue: 0.29),
                            opacity: strongInk ? 0.19 : 0.11, cell: 5, radius: 0.36)
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
