#!/usr/bin/env swift
// Rebuild from the repository root on macOS:
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

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGColor {
    CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
}
let cream = color(247, 241, 231)
let peach = color(232, 157, 116)
let ink = color(56, 49, 66)
let lavender = color(184, 170, 198)

// Opaque RGB storage: the platform supplies its own rounded app-icon mask.
guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
          bytesPerRow: side * 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("Could not create the icon canvas.") }
context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.setFillColor(cream)
context.fill(CGRect(x: 0, y: 0, width: side, height: side))

// A broad rising sun, cut precisely by its horizon. Coordinates use a lower-left origin.
context.saveGState()
context.clip(to: CGRect(x: 0, y: 434, width: side, height: side - 434))
context.setFillColor(peach)
context.fillEllipse(in: CGRect(x: 294, y: 216, width: 436, height: 436))
context.restoreGState()

func stroke(from start: CGPoint, to end: CGPoint, width: CGFloat, color: CGColor) {
    context.setStrokeColor(color)
    context.setLineWidth(width)
    context.setLineCap(.round)
    context.move(to: start)
    context.addLine(to: end)
    context.strokePath()
}

// Three short rays keep the silhouette clear at small icon sizes.
stroke(from: CGPoint(x: 512, y: 754), to: CGPoint(x: 512, y: 812), width: 36, color: ink)
stroke(from: CGPoint(x: 287, y: 664), to: CGPoint(x: 249, y: 702), width: 36, color: ink)
stroke(from: CGPoint(x: 737, y: 664), to: CGPoint(x: 775, y: 702), width: 36, color: ink)

// A single quiet horizon and its small reflection anchor the dawn.
stroke(from: CGPoint(x: 222, y: 434), to: CGPoint(x: 802, y: 434), width: 48, color: ink)
stroke(from: CGPoint(x: 408, y: 320), to: CGPoint(x: 616, y: 320), width: 36, color: lavender)

guard let image = context.makeImage() else { fatalError("Could not render the icon.") }
let bitmap = NSBitmapImageRep(cgImage: image)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Could not encode the icon.")
}
try FileManager.default.createDirectory(at: iconDirectory, withIntermediateDirectories: true)
let imageURL = iconDirectory.appendingPathComponent("AppIcon.png")
try png.write(to: imageURL, options: .atomic)
let asset: [String: Any] = [
    "images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1]
]
let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys]
try JSONSerialization.data(withJSONObject: asset, options: options)
    .write(to: iconDirectory.appendingPathComponent("Contents.json"), options: .atomic)
let catalogInfo = iconDirectory.deletingLastPathComponent().appendingPathComponent("Contents.json")
if !FileManager.default.fileExists(atPath: catalogInfo.path) {
    try JSONSerialization.data(withJSONObject: ["info": ["author": "xcode", "version": 1]], options: options)
        .write(to: catalogInfo, options: .atomic)
}
print("Created opaque 1024 × 1024 icon: \(imageURL.path)")
