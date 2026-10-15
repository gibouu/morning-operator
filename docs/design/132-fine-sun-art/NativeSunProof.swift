import SwiftUI
import AppKit

@main struct NativeSunProof {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        guard let artwork = NSImage(contentsOfFile: CommandLine.arguments[1]) else { fatalError("Missing original artwork") }
        let view = SunProofPlate(sun: Image(nsImage: artwork)).environment(\.colorScheme, .light).frame(width: 1170, height: 590)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Native render failed") }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
        print("Rendered real MorningSolarArtwork on three paper backgrounds at phone scale.")

        if CommandLine.arguments.count > 3 {
            let acceptance = SunAcceptancePlate(sun: Image(nsImage: artwork))
                .environment(\.colorScheme, .light)
            let acceptanceRenderer = ImageRenderer(content: acceptance)
            acceptanceRenderer.scale = 3
            guard let image = acceptanceRenderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
            else { fatalError("Native size/opacity render failed") }
            try png.write(to: URL(fileURLWithPath: CommandLine.arguments[3]))
            print("Rendered 120/240/300 pt sizes and 0/30/100% opacity at 3× scale.")
        }
    }
}

private struct SunAcceptancePlate: View {
    let sun: Image
    private let paper = Color(red: 0.965, green: 0.935, blue: 0.875)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("MORE · sun size and opacity review")
                .font(.system(size: 22, weight: .medium)).padding(24)
            HStack(spacing: 0) {
                ForEach([120, 240, 300], id: \.self) { size in
                    cell(size: CGFloat(size), opacity: 1, label: "\(size) pt canvas · 100% opacity")
                }
            }
            HStack(spacing: 0) {
                ForEach([0, 30, 100], id: \.self) { percent in
                    cell(size: 300, opacity: Double(percent) / 100,
                         label: "300 pt canvas · \(percent)% opacity")
                }
            }
            Text("Native SwiftUI · 3× render · unchanged PNG · component proof only")
                .font(.caption).padding(24)
        }
        .foregroundStyle(Color(red: 0.10, green: 0.18, blue: 0.43))
        .background(paper)
    }

    private func cell(size: CGFloat, opacity: Double, label: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MorningSolarArtwork(opacity: opacity, image: sun)
                .frame(width: size, height: size)
                .frame(width: 300, height: 300)
            Text(label).font(.caption)
        }
        .padding(20)
        .frame(width: 340, height: 360)
    }
}

private struct SunProofPlate: View {
    let sun: Image
    private let papers: [(String, Color)] = [
        ("early light", Color(red: 0.985, green: 0.945, blue: 0.870)),
        ("day cream", Color(red: 0.965, green: 0.935, blue: 0.875)),
        ("warm evening", Color(red: 0.965, green: 0.880, blue: 0.780))
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("MORE · fine sunset sun").font(.system(size: 22, weight: .medium))
                Spacer()
                Text("Native component proof · generated artwork").font(.caption)
            }.padding(24)
            HStack(spacing: 0) {
                ForEach(Array(papers.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 20) {
                        Text(item.0).font(.caption.weight(.medium))
                        MorningSolarArtwork(image: sun).frame(width: 342, height: 342)
                        Text("Original alpha · 342 pt canvas").font(.caption2)
                    }.padding(24).frame(width: 390, height: 470)
                        .background(item.1)
                }
            }
            Text("The bitmap stays unchanged. Fine stochastic grain replaces the large regular dot grid. Position and visibility remain controlled by the app’s existing solar clock.")
                .font(.caption).padding(.horizontal, 24).padding(.top, 16)
        }.foregroundStyle(Color(red: 0.10, green: 0.18, blue: 0.43))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96))
    }
}
