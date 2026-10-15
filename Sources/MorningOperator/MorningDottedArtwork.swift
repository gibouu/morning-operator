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

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        let cells = 23
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

/// The scene is driven by local time, independently of routine completion.
/// It is decorative: cards and controls remain opaque reading surfaces above it.
struct MorningCelestialArtwork: View {
    let scene: MorningCelestialScene
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width * 0.72, 300)
            ZStack {
                MorningDottedDisc()
                    .fill(MorningTheme.current.accent)
                    .frame(width: diameter, height: diameter)
                    .position(x: geometry.size.width * scene.sun.centerX,
                              y: geometry.size.height * scene.sun.centerY)
                    .opacity(scene.sun.opacity * (scheme == .dark ? 0.36 : 0.30))
                MorningDottedDisc(kind: .moon)
                    .fill(MorningTheme.current.ink)
                    .frame(width: diameter * 0.78, height: diameter * 0.78)
                    .position(x: geometry.size.width * scene.moon.centerX,
                              y: geometry.size.height * scene.moon.centerY)
                    .opacity(scene.moon.opacity * (scheme == .dark ? 0.42 : 0.34))
            }
            .animation(reduceMotion ? nil : .linear(duration: 60), value: scene)
        }
        .clipped()
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

/// A sparse frame made from round ink impressions. Reading surfaces stay solid;
/// only the edge changes, so the pattern never sits behind a paragraph.
struct MorningDottedFrame: Shape {
    var cornerRadius: CGFloat = 10
    var spacing: CGFloat = 8
    var dotRadius: CGFloat = 0.85

    func path(in rect: CGRect) -> Path {
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
