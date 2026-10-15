import AppKit
import SwiftUI
import MorningCore

/// Offscreen native SwiftUI component proof. No app install, phone control, data
/// store, routine or navigation is involved. Compiles the real theme and surface.
@main
struct MorningPaperSurfaceProof {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for phase in MorningDayPhase.allCases {
            try render(Sheet(phase: phase), size: CGSize(width: 430, height: 932),
                       to: output.appendingPathComponent("paper-\(phase.rawValue).png"))
        }
        try render(Sheet(phase: .day, old: true), size: CGSize(width: 430, height: 932),
                   to: output.appendingPathComponent("paper-day-before.png"))
        // System accessibility environment values are read-only on macOS. This
        // is an opaque colour reference, not proof of an OS preference toggle.
        try render(Sheet(phase: .day, plain: true),
                   size: CGSize(width: 430, height: 932),
                   to: output.appendingPathComponent("paper-plain-reference.png"))
        try render(Sheet(phase: .day).environment(\.colorScheme, .dark),
                   size: CGSize(width: 430, height: 932),
                   to: output.appendingPathComponent("paper-system-dark.png"))
        try render(HStack(spacing: 0) {
            ForEach(MorningDayPhase.allCases, id: \.self) { phase in
                Sheet(phase: phase, compact: true).frame(width: 220, height: 480)
            }
        }, size: CGSize(width: 1100, height: 480),
                   to: output.appendingPathComponent("paper-day-cycle.png"))
        print("Native SwiftUI component renders saved to \(output.path)")
    }

    @MainActor private static func render<V: View>(_ view: V, size: CGSize, to url: URL) throws {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 3
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}

private struct Sheet: View {
    let phase: MorningDayPhase
    var old = false
    var plain = false
    var compact = false
    private var theme: MorningTheme { MorningTheme(blend: .steady(phase)) }

    var body: some View {
        ZStack {
            if plain {
                theme.paper
            } else if old {
                theme.paper.overlay { MorningHalftone(color: theme.dot, opacity: 0.04) }
            } else {
                MorningPaperSurface(theme: theme)
            }
            VStack(alignment: .leading, spacing: 24) {
                Text("NATIVE COMPONENT PROOF")
                    .font(.caption2.weight(.medium)).foregroundStyle(theme.inkSoft)
                Text(phase.rawValue.capitalized)
                    .font(.largeTitle.weight(.semibold)).foregroundStyle(theme.ink)
                if !compact {
                    Text("Quiet cream paper")
                        .font(.title2.weight(.medium)).foregroundStyle(theme.ink)
                    Text("The page follows the local clock. Fine grain stays behind the words.")
                        .font(.body).foregroundStyle(theme.inkSoft)
                    VStack(alignment: .leading, spacing: 12) {
                        Label("A clear reading surface", systemImage: "text.alignleft")
                        Text("Opaque content keeps the existing palette and text contrast.")
                            .foregroundStyle(theme.inkSoft)
                    }
                    .font(.body).padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }
                Spacer(minLength: 24)
                Text(plain ? "Plain reference · grain omitted" : old ? "Before · regular dot screen" : "After · fine paper grain")
                    .font(.caption).foregroundStyle(theme.inkSoft)
                Text("Surface only · no app behavior verified")
                    .font(.caption2).foregroundStyle(theme.inkSoft)
            }
            .padding(compact ? 20 : 28)
        }
    }
}
