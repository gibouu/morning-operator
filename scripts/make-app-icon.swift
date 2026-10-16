#!/usr/bin/env swift
// Rebuild the approved day/night branding in all three native iOS appearances.
// Optional first argument: a different AppIcon.appiconset output directory.
import Foundation

let generator = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("make-dotted-app-icon.swift")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
process.arguments = ["swift", generator.path] + CommandLine.arguments.dropFirst()
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
