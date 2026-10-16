import AppKit
import Foundation

// Compile alongside MorningCore/MorningBrand.swift; never redraw an approximate logo.
@main
enum ExportDemoBrand {
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bounds = MorningBrandArtwork.wordmarkBounds
        let width = 1440
        let scale = Double(width) / bounds.width
        let height = Int(ceil(bounds.height * scale))
        for appearance in MorningBrandAppearance.allCases {
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            for dot in MorningBrandArtwork.wordmark(appearance: appearance) {
                let hex = dot.color
                context.setFillColor(CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                    green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1))
                let radius = dot.radius * scale
                let x = (dot.x - bounds.x) * scale
                let y = (dot.y - bounds.y) * scale
                context.fillEllipse(in: CGRect(x: x - radius, y: Double(height) - y - radius,
                    width: radius * 2, height: radius * 2))
            }
            let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
            let png = bitmap.representation(using: .png, properties: [:])!
            try png.write(to: destination.appendingPathComponent("wordmark-\(appearance.rawValue).png"))
        }
    }
}
