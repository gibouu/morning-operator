#!/usr/bin/env swift
// Original, app-owned dotted sunrise. Regenerate on macOS from the repository root:
// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/make-dotted-app-icon.swift
// The earlier non-dotted generator remains at scripts/make-app-icon.swift.
import AppKit
import CoreGraphics
import Foundation

let side: CGFloat = 1024
let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let destination = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? repository.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
func color(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func render(paper: UInt32, ink: UInt32, sun: UInt32, name: String) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
        bytesPerRow: 4096, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.setFillColor(color(paper)); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
    func dot(_ x: CGFloat, _ y: CGFloat, radius: CGFloat, ink value: UInt32) {
        context.setFillColor(color(value))
        // Drawing coordinates are top-down, like the native SwiftUI mark.
        context.fillEllipse(in: CGRect(x: x - radius, y: side - y - radius, width: radius * 2, height: radius * 2))
    }
    let center = CGPoint(x: 512, y: 596), radius: CGFloat = 246, cell: CGFloat = 42
    for row in 0...6 {
        let y = center.y - radius + CGFloat(row) * cell
        for column in 0...12 {
            let x = center.x - radius + CGFloat(column) * cell
            let distance = hypot(x - center.x, y - center.y) / radius
            if distance <= 1 { dot(x, y, radius: 12 + 5.5 * (1 - distance * distance), ink: sun) }
        }
    }
    for degree in [25.0, 55, 90, 125, 155] {
        let angle = degree * .pi / 180
        for reach in [326.0, 378.0] {
            dot(center.x + cos(angle) * reach, center.y - sin(angle) * reach, radius: 15.5, ink: ink)
        }
    }
    for column in 0...14 { dot(CGFloat(190 + column * 46), 648, radius: 16, ink: ink) }
    for column in 0...7 { dot(CGFloat(350 + column * 46), 728, radius: 10.5, ink: ink) }
    let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
    let data = bitmap.representation(using: .png, properties: [:])!
    try data.write(to: destination.appendingPathComponent(name), options: .atomic)
}
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
try render(paper: 0xF4ECDD, ink: 0x1A2F6E, sun: 0xB54C25, name: "AppIcon.png")
try render(paper: 0x0B1226, ink: 0xE6D4B4, sun: 0xE48B55, name: "AppIcon-Dark.png")
try render(paper: 0xE9E4DB, ink: 0x272727, sun: 0x272727, name: "AppIcon-Tinted.png")
let asset: [String: Any] = [
    "images": [
        ["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"],
        ["filename": "AppIcon-Dark.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
         "appearances": [["appearance": "luminosity", "value": "dark"]]],
        ["filename": "AppIcon-Tinted.png", "idiom": "universal", "platform": "ios", "size": "1024x1024",
         "appearances": [["appearance": "luminosity", "value": "tinted"]]]
    ], "info": ["author": "xcode", "version": 1]
]
try JSONSerialization.data(withJSONObject: asset, options: [.prettyPrinted, .sortedKeys])
    .write(to: destination.appendingPathComponent("Contents.json"), options: .atomic)
print("Wrote original dotted sunrise app icons to \(destination.path)")
