#!/usr/bin/env swift
// Regenerate the approved sunrise/day, full-moon/night and monochrome tinted icons.
// DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/make-dotted-app-icon.swift
import Foundation

func generateIcons() throws -> Int32 {
    let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("more-brand-icons-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temporary) }
    let executable = temporary.appendingPathComponent("render-icons")
    let compiler = Process()
    compiler.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
    compiler.arguments = ["swiftc", repository.appendingPathComponent("Sources/MorningCore/MorningBrand.swift").path,
        repository.appendingPathComponent("scripts/BrandIconRenderer.swift").path, "-o", executable.path]
    try compiler.run()
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else { return compiler.terminationStatus }
    let renderer = Process()
    renderer.executableURL = executable
    renderer.arguments = [CommandLine.arguments.dropFirst().first ?? repository.appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset").path]
    try renderer.run()
    renderer.waitUntilExit()
    return renderer.terminationStatus
}
exit(try generateIcons())
