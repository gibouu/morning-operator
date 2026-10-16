import MorningCore
import SwiftUI

/// Shared by the app and its Live Activity, without fonts or bitmap scaling.
struct MorningBrandWordmark: View {
    let appearance: MorningBrandAppearance
    var contrasting = false

    var body: some View {
        MorningBrandCanvas(dots: MorningBrandArtwork.wordmark(appearance: appearance, contrasting: contrasting),
            bounds: MorningBrandArtwork.wordmarkBounds)
            .accessibilityIdentifier("more.brand.wordmark")
    }
}

struct MorningBrandSymbol: View {
    let appearance: MorningBrandAppearance
    var contrasting = false

    var body: some View {
        MorningBrandCanvas(dots: MorningBrandArtwork.symbol(appearance: appearance, contrasting: contrasting),
            bounds: MorningBrandArtwork.symbolBounds)
            .accessibilityIdentifier("more.brand.symbol")
    }
}

private struct MorningBrandCanvas: View {
    let dots: [MorningBrandDot]
    let bounds: MorningBrandBounds

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let offsetX = (size.width - bounds.width * scale) / 2 - bounds.x * scale
            let offsetY = (size.height - bounds.height * scale) / 2 - bounds.y * scale
            for dot in dots {
                let diameter = dot.radius * scale * 2
                let rect = CGRect(x: offsetX + (dot.x - dot.radius) * scale,
                    y: offsetY + (dot.y - dot.radius) * scale, width: diameter, height: diameter)
                context.fill(Path(ellipseIn: rect), with: .color(Color(
                    .sRGB, red: Double((dot.color >> 16) & 255) / 255,
                    green: Double((dot.color >> 8) & 255) / 255,
                    blue: Double(dot.color & 255) / 255, opacity: 1)))
            }
        }
        .aspectRatio(bounds.width / bounds.height, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "MORE"))
    }
}
