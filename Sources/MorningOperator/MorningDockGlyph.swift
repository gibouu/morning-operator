import SwiftUI

/// A small, app-owned family for the dock's six actions.
enum MorningDockSymbol: Sendable {
    case play, pause, review, learn, history, settings
}

/// Decorative vector artwork; the enclosing button supplies its accessible name.
/// Place in a square frame. The inherited foreground style and stroke both scale
/// with that frame; the design's reference size is 24 points.
struct MorningDockGlyph: View {
    let symbol: MorningDockSymbol

    var body: some View {
        GeometryReader { geometry in
            let side = max(0, min(geometry.size.width, geometry.size.height))
            ZStack {
                MorningDockOutline(symbol: symbol)
                    .stroke(style: StrokeStyle(
                        lineWidth: side * (1.7 / 24),
                        lineCap: .round,
                        lineJoin: .round
                    ))
                MorningDockAccent(symbol: symbol)
                    .fill(.foreground)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

private struct MorningDockOutline: Shape {
    let symbol: MorningDockSymbol

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch symbol {
        case .play:
            // The triangle sits slightly right of center for optical balance.
            path.move(to: CGPoint(x: 7, y: 4.5))
            path.addLine(to: CGPoint(x: 19, y: 12))
            path.addLine(to: CGPoint(x: 7, y: 19.5))
            path.closeSubpath()

        case .pause:
            path.move(to: CGPoint(x: 8.25, y: 5))
            path.addLine(to: CGPoint(x: 8.25, y: 19))
            path.move(to: CGPoint(x: 15.75, y: 5))
            path.addLine(to: CGPoint(x: 15.75, y: 19))

        case .review:
            path.addEllipse(in: CGRect(x: 4, y: 4, width: 16, height: 16))
            path.move(to: CGPoint(x: 7.8, y: 12.1))
            path.addLine(to: CGPoint(x: 10.7, y: 15))
            path.addLine(to: CGPoint(x: 16.4, y: 9.1))

        case .learn:
            // Open observing arcs around one point, distinct from a record button.
            path.move(to: CGPoint(x: 4.1, y: 10.5))
            path.addCurve(to: CGPoint(x: 19.9, y: 10.5),
                          control1: CGPoint(x: 8.1, y: 3.7),
                          control2: CGPoint(x: 15.9, y: 3.7))
            path.move(to: CGPoint(x: 4.1, y: 13.5))
            path.addCurve(to: CGPoint(x: 19.9, y: 13.5),
                          control1: CGPoint(x: 8.1, y: 20.3),
                          control2: CGPoint(x: 15.9, y: 20.3))

        case .history:
            path.addRoundedRect(in: CGRect(x: 4, y: 5.5, width: 16, height: 14.5),
                                cornerSize: CGSize(width: 3, height: 3))
            path.move(to: CGPoint(x: 8, y: 3.5))
            path.addLine(to: CGPoint(x: 8, y: 7.5))
            path.move(to: CGPoint(x: 16, y: 3.5))
            path.addLine(to: CGPoint(x: 16, y: 7.5))
            path.move(to: CGPoint(x: 4.2, y: 10))
            path.addLine(to: CGPoint(x: 19.8, y: 10))
            path.move(to: CGPoint(x: 8, y: 13.5))
            path.addLine(to: CGPoint(x: 16, y: 13.5))
            path.move(to: CGPoint(x: 8, y: 16.5))
            path.addLine(to: CGPoint(x: 12.5, y: 16.5))

        case .settings:
            // Split each rail at the knob so the open circles stay clear.
            for (y, centerX) in [(6.0, 15.0), (12.0, 9.0), (18.0, 14.0)] {
                let radius = 2.1
                path.move(to: CGPoint(x: 4, y: y))
                path.addLine(to: CGPoint(x: centerX - radius, y: y))
                path.move(to: CGPoint(x: centerX + radius, y: y))
                path.addLine(to: CGPoint(x: 20, y: y))
                path.addEllipse(in: CGRect(x: centerX - radius, y: y - radius,
                                           width: radius * 2, height: radius * 2))
            }
        }
        return fittedDockPath(path, in: rect)
    }
}

private struct MorningDockAccent: Shape {
    let symbol: MorningDockSymbol

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if case .learn = symbol {
            path.addEllipse(in: CGRect(x: 10.15, y: 10.15, width: 3.7, height: 3.7))
        }
        return fittedDockPath(path, in: rect)
    }
}

private func fittedDockPath(_ path: Path, in rect: CGRect) -> Path {
    let side = max(0, min(rect.width, rect.height))
    let scale = side / 24
    return path.applying(CGAffineTransform(
        a: scale, b: 0, c: 0, d: scale,
        tx: rect.midX - side / 2, ty: rect.midY - side / 2
    ))
}
