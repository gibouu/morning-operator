import AppKit
import SwiftUI
import MorningCore

/// Native component composition, not a phone screenshot or routine acceptance test.
/// Uses the actual MorningPaper wrapper and its default asset-catalog lookup.
@main
struct MorningVisualFoundationProof {
    @MainActor static func main() throws {
        guard CommandLine.arguments.count == 2 else { throw CocoaError(.fileReadInvalidFileName) }
        guard NSImage(named: "SolarSunFineV1") != nil else { throw CocoaError(.fileNoSuchFile) }
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for phase in MorningDayPhase.allCases {
            MorningThemeClock.shared.pinnedPhase = phase
            let view = FoundationSheet(phase: phase).frame(width: 430, height: 932)
            let renderer = ImageRenderer(content: view)
            renderer.proposedSize = ProposedViewSize(width: 430, height: 932)
            renderer.scale = 3
            guard let image = renderer.cgImage,
                  let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try data.write(to: output.appendingPathComponent("foundation-\(phase.rawValue).png"))
        }
        MorningThemeClock.shared.pinnedPhase = nil
        print("Actual paper, celestial scene, system type and default asset lookup rendered across five phases.")
    }
}

private struct FoundationSheet: View {
    let phase: MorningDayPhase
    var body: some View {
        ZStack {
            MorningPaper()
            VStack(alignment: .leading, spacing: 20) {
                Text("Thu, Oct 15").font(MorningTheme.Typography.label)
                Text("Sun · paper · type").font(MorningTheme.Typography.title)
                Text("Native composition proof · \(phase.rawValue)")
                    .font(MorningTheme.Typography.note)
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("One clear voice").font(MorningTheme.Typography.heading)
                    Text("The date, title and reading text use the same native font family.")
                        .font(MorningTheme.Typography.body)
                    Text("Component appearance only. This does not verify an iPhone routine.")
                        .font(MorningTheme.Typography.label)
                }
                .padding(22)
                .background(MorningTheme.current.surface, in: RoundedRectangle(cornerRadius: 10))
            }
            .padding(28)
            .foregroundStyle(MorningTheme.current.ink)
        }
        .environment(\.colorScheme, .light)
    }
}
