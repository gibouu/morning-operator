#!/usr/bin/env swift
// Rebuild all three native iOS app-icon appearances from the repository root on macOS:
// swift -module-cache-path .build/testing-module-cache scripts/make-app-icon.swift
// Optional first argument: a different AppIcon.appiconset output directory.
// Original vector artwork; no font, symbol, downloaded image, or package dependency.

import AppKit
import CoreGraphics
import Foundation

let side = 1024
let scriptURL = URL(fileURLWithPath: #filePath).standardizedFileURL
let repositoryURL = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconDirectory = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? repositoryURL.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { fatalError("Could not create the icon color space.") }

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}

// These normalized coordinates match MorningBrandMark. The two arches form a quiet lowercase m.
// The conversion keeps the design's top-left origin while Core Graphics renders bottom-left.
func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
    CGPoint(x: x * CGFloat(side), y: (1 - y) * CGFloat(side))
}
func monogram() -> CGPath {
    let path = CGMutablePath()
    path.move(to: point(0.18, 0.72))
    path.addLine(to: point(0.18, 0.42))
    path.addCurve(to: point(0.50, 0.42), control1: point(0.18, 0.15), control2: point(0.50, 0.15))
    path.addLine(to: point(0.50, 0.72))
    path.move(to: point(0.50, 0.42))
    path.addCurve(to: point(0.82, 0.42), control1: point(0.50, 0.15), control2: point(0.82, 0.15))
    path.addLine(to: point(0.82, 0.72))
    return path.copy(strokingWithWidth: CGFloat(side) * 0.105, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

struct Appearance {
    let filename: String
    let luminosity: String?
    let backgroundTop: CGColor
    let backgroundBottom: CGColor
    let markTop: CGColor
    let markBottom: CGColor
}
let appearances = [
    Appearance(filename: "AppIcon.png", luminosity: nil,
               backgroundTop: color(247, 249, 250), backgroundBottom: color(226, 232, 237),
               markTop: color(53, 64, 74), markBottom: color(24, 31, 38)),
    Appearance(filename: "AppIcon-Dark.png", luminosity: "dark",
               backgroundTop: color(27, 32, 37), backgroundBottom: color(9, 13, 17),
               markTop: color(235, 241, 246), markBottom: color(165, 181, 194)),
    Appearance(filename: "AppIcon-Tinted.png", luminosity: "tinted",
               backgroundTop: color(23, 23, 23), backgroundBottom: color(8, 8, 8),
               markTop: color(245, 245, 245), markBottom: color(186, 186, 186))
]

func gradient(_ context: CGContext, top: CGColor, bottom: CGColor) {
    guard let gradient = CGGradient(colorsSpace: space, colors: [bottom, top] as CFArray, locations: [0, 1]) else {
        fatalError("Could not create the icon gradient.")
    }
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 0), end: CGPoint(x: 512, y: side), options: [])
}

try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
let mark = monogram()
var images = [[String: Any]]()
for appearance in appearances {
    // Opaque RGB storage: iOS supplies the rounded app-icon mask. No edge mask is baked in.
    guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        fatalError("Could not create the icon canvas.")
    }
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    gradient(context, top: appearance.backgroundTop, bottom: appearance.backgroundBottom)
    context.saveGState()
    context.addPath(mark)
    context.clip()
    gradient(context, top: appearance.markTop, bottom: appearance.markBottom)
    context.restoreGState()

    guard let image = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        fatalError("Could not encode the icon.")
    }
    let imageURL = iconDirectory.appendingPathComponent(appearance.filename)
    try png.write(to: imageURL, options: .atomic)
    var entry: [String: Any] = ["filename": appearance.filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"]
    if let luminosity = appearance.luminosity {
        entry["appearances"] = [["appearance": "luminosity", "value": luminosity]]
    }
    images.append(entry)
    print("Created opaque 1024 × 1024 icon: \(imageURL.path)")
}
let asset: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
try JSONSerialization.data(withJSONObject: asset, options: options)
    .write(to: iconDirectory.appendingPathComponent("Contents.json"), options: .atomic)
let catalogInfo = iconDirectory.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalogInfo.path) {
    try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: options)
        .write(to: catalogInfo, options: .atomic)
}
