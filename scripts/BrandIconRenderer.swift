import AppKit
import Foundation

/// Compiled with MorningBrand.swift by make-dotted-app-icon.swift: one geometry for UI and icon exports.
@main
enum BrandIconRenderer {
    static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (appearance, tinted, filename) in [
            (MorningBrandAppearance.day, false, "AppIcon.png"),
            (.night, false, "AppIcon-Dark.png"),
            (.day, true, "AppIcon-Tinted.png")
        ] {
            try render(appearance: appearance, tinted: tinted)
                .write(to: destination.appendingPathComponent(filename), options: .atomic)
        }
        let images: [[String: Any]] = [
            ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
            ["filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
             "appearances": [["appearance": "luminosity", "value": "dark"]]],
            ["filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
             "appearances": [["appearance": "luminosity", "value": "tinted"]]]
        ]
        try JSONSerialization.data(withJSONObject: ["images": images, "info": ["author": "xcode", "version": 1]],
            options: [.prettyPrinted, .sortedKeys])
            .write(to: destination.appendingPathComponent("Contents.json"), options: .atomic)
        print("Wrote approved MORE day/night icons to \(destination.path)")
    }

    private static func render(appearance: MorningBrandAppearance, tinted: Bool) throws -> Data {
        let side = 1024
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
            bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        let background = tinted ? UInt32(0xE9E4DB)
            : (appearance == .day ? MorningBrandPalette.paper : MorningBrandPalette.night)
        context.setFillColor(color(background))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let scale = (appearance == .day ? 760.0 : 900.0) / 76
        let offsetX = 512 - 56 * scale
        let offsetY = (appearance == .day ? 470 : 495) - (appearance == .day ? 31.25 : 32) * scale
        for dot in MorningBrandArtwork.symbol(appearance: appearance) {
            let radius = dot.radius * scale
            let x = offsetX + dot.x * scale, y = offsetY + dot.y * scale
            context.setFillColor(color(tinted ? 0x272727 : dot.color))
            context.fillEllipse(in: CGRect(x: x - radius, y: 1024 - y - radius, width: radius * 2, height: radius * 2))
        }
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    private static func color(_ hex: UInt32) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}
