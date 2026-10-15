import SwiftUI

/// The closed dock is a small piece of the morning, without a control surface.
/// Alternatives are available only to isolated debug previews, never as app settings.
enum MorningSunriseDesign: String, CaseIterable {
    case horizon, halo, radiance, ember

    static var current: Self {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
           let option = arguments.first(where: { $0.hasPrefix("--sunrise-design=") }),
           let design = Self(rawValue: String(option.dropFirst("--sunrise-design=".count))) {
            return design
        }
        #endif
        return .horizon
    }
}

struct MorningSunriseMark: View {
    var design: MorningSunriseDesign = .current
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var gold: Color { MorningStyle.ink }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let scale = min(size.width / 112, size.height / 64)
                context.translateBy(x: (size.width - 112 * scale) / 2,
                                    y: (size.height - 64 * scale) / 2)
                context.scaleBy(x: scale, y: scale)
                let stroke = StrokeStyle(lineWidth: contrast == .increased ? 2.4 : 1.8,
                                         lineCap: .round, lineJoin: .round)
                let color = GraphicsContext.Shading.color(gold)
                let sun = GraphicsContext.Shading.color(MorningStyle.mark)

                switch design {
                case .horizon:
                    context.fill(halfSun(radius: 18, horizon: 40), with: sun)
                    context.stroke(rays(radius: 26, length: 5, angles: [25, 57.5, 90, 122.5, 155], horizon: 40),
                                   with: color, style: stroke)
                    context.stroke(line(25, 44, 87, 44), with: color, style: stroke)
                    context.stroke(line(43, 50, 69, 50), with: .color(gold.opacity(0.38)), style: stroke)
                case .halo:
                    context.fill(halfSun(radius: 15, horizon: 41), with: sun)
                    var halo = Path()
                    halo.addArc(center: CGPoint(x: 56, y: 41), radius: 25,
                                startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                    context.stroke(halo, with: color, style: stroke)
                    context.stroke(line(25, 45, 87, 45), with: color, style: stroke)
                case .radiance:
                    context.fill(halfSun(radius: 16, horizon: 40), with: sun)
                    context.stroke(rays(radius: 24, length: 9, angles: [20, 55, 90, 125, 160], horizon: 40),
                                   with: color, style: stroke)
                    context.stroke(line(21, 45, 91, 45), with: color, style: stroke)
                case .ember:
                    context.fill(halfSun(radius: 22, horizon: 41), with: sun)
                    context.stroke(line(21, 46, 91, 46), with: color, style: stroke)
                    context.stroke(line(38, 52, 74, 52), with: .color(gold.opacity(0.44)), style: stroke)
                }
            }
            .frame(width: 112, height: 64)
        }
        .frame(width: 112, height: 68)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func halfSun(radius: CGFloat, horizon: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: 56, y: horizon), radius: radius,
                    startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        path.closeSubpath()
        return path
    }

    private func rays(radius: CGFloat, length: CGFloat, angles: [Double], horizon: CGFloat) -> Path {
        var path = Path()
        for angle in angles {
            let radians = angle * .pi / 180
            path.move(to: CGPoint(x: 56 + cos(radians) * radius, y: horizon - sin(radians) * radius))
            path.addLine(to: CGPoint(x: 56 + cos(radians) * (radius + length),
                                    y: horizon - sin(radians) * (radius + length)))
        }
        return path
    }

    private func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x1, y: y1))
            path.addLine(to: CGPoint(x: x2, y: y2))
        }
    }
}
