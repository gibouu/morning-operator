import SwiftUI

/// Quiet glass for discovery and access setup, with solid accessibility surfaces.
struct MorningEntryBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: [MorningStyle.surface, MorningStyle.background],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(.white.opacity(scheme == .dark ? 0.035 : 0.35))
                    .frame(width: 320, height: 320).blur(radius: 100).offset(x: 140, y: -140)
            }
            .ignoresSafeArea().accessibilityHidden(true)
    }
}

struct MorningEntrySurface: ViewModifier {
    var prefersOpaque = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content
            .background {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                if prefersOpaque || reduceTransparency || contrast == .increased {
                    shape.fill(MorningStyle.surface)
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(MorningStyle.line.opacity(contrast == .increased ? 1 : 0.45),
                                  lineWidth: contrast == .increased ? 1 : 0.5)
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
    }
}

struct MorningEntryPrimaryStyle: ViewModifier {
    var prefersOpaque = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if prefersOpaque || reduceTransparency || contrast == .increased {
            content.buttonStyle(PrimaryButtonStyle())
        } else {
            content.buttonStyle(.glassProminent).buttonBorderShape(.capsule)
                .controlSize(.large).tint(MorningStyle.controlTint)
                .foregroundStyle(MorningStyle.onControl)
        }
    }
}
