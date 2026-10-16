import SwiftUI

/// MORE's original two-arch monogram. The wordmark beside it supplies its accessible name.
struct MorningBrandMark: View {
    var body: some View {
        MorningBrandMonogram()
            .fill(.primary)
            .accessibilityHidden(true)
    }
}

private struct MorningBrandMonogram: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        var path = Path()
        path.move(to: point(0.18, 0.72))
        path.addLine(to: point(0.18, 0.42))
        path.addCurve(to: point(0.50, 0.42), control1: point(0.18, 0.15), control2: point(0.50, 0.15))
        path.addLine(to: point(0.50, 0.72))
        path.move(to: point(0.50, 0.42))
        path.addCurve(to: point(0.82, 0.42), control1: point(0.50, 0.15), control2: point(0.82, 0.15))
        path.addLine(to: point(0.82, 0.72))
        return path.strokedPath(StrokeStyle(lineWidth: side * 0.105, lineCap: .round, lineJoin: .round))
    }
}
