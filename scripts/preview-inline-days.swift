// Isolated macOS SwiftUI proof. Never opens MorningStore or writes app data.
import AppKit
import SwiftUI
import MorningCore

private struct ProofCase {
    let name: String
    let selectedDay: Int
    var expanded = true
    var largeText = false
    var dark = false
    var french = false
}

private struct ProofView: View {
    let item: ProofCase
    let history: MorningHistory
    let observations: [MorningInlineDayEvidence]
    let now: Date
    @SwiftUI.State var selected: Date
    @SwiftUI.State var expanded: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("MORE · Inline days")
                    .font(.system(.title3, weight: .semibold))
                Text("ISOLATED NATIVE COMPONENT\nSynthetic in-memory evidence. No app data.")
                    .font(.system(.caption)).foregroundStyle(.secondary)
                MorningInlineDayStrip(selectedDate: $selected, isExpanded: $expanded,
                                      history: history, observations: observations,
                                      referenceDate: now)
                Divider()
                Text("Home content continues here.")
                    .font(.system(.subheadline)).foregroundStyle(.secondary)
            }.padding(24)
        }
        .frame(width: 393, height: item.largeText ? 850 : 600)
        .background(item.dark ? Color(white: 0.10) : Color(red: 0.97, green: 0.96, blue: 0.93))
        .foregroundStyle(item.dark ? Color.white : Color(white: 0.15))
        .environment(\.calendar, Self.calendar)
        .environment(\.timeZone, Self.calendar.timeZone)
        .environment(\.locale, Locale(identifier: item.french ? "fr_FR" : "en_GB"))
        .environment(\.dynamicTypeSize, item.largeText ? .accessibility5 : .large)
        .preferredColorScheme(item.dark ? .dark : .light)
    }

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }
}

@main private enum InlineDayProof {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            print("Usage: inline-day-proof OUTPUT_DIRECTORY [--interactive]")
            return
        }
        let output = URL(fileURLWithPath: args[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let calendar = ProofView.calendar
        func date(_ day: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: 12))!
        }
        let now = date(15)
        let routine = RoutineVersion(sourceLabel: "Isolated native fixture", steps: [
            RoutineStep(title: "First moment", durationMinutes: 5),
            RoutineStep(title: "Second moment", durationMinutes: 10)
        ], isApproved: true)
        var finished = RoutineSession(routine: routine)
        try finished.start(at: date(12))
        try finished.advance(at: date(12).addingTimeInterval(60))
        try finished.advance(skipping: true, at: date(12).addingTimeInterval(120))
        var stopped = RoutineSession(routine: routine)
        try stopped.start(at: date(13))
        try stopped.stop(at: date(13).addingTimeInterval(60))
        let history = MorningHistory(runs: [
            try MorningRunRecord(session: finished, timeZoneIdentifier: calendar.timeZone.identifier),
            try MorningRunRecord(session: stopped, timeZoneIdentifier: calendar.timeZone.identifier)
        ])
        let observations = [try MorningInlineDayEvidence(id: UUID(), observedAt: date(14),
            timeZoneIdentifier: calendar.timeZone.identifier, origin: .human)]
        let cases = [
            ProofCase(name: "01-collapsed", selectedDay: 15, expanded: false),
            ProofCase(name: "02-empty-today", selectedDay: 15),
            ProofCase(name: "03-finished-with-skipped", selectedDay: 12),
            ProofCase(name: "04-stopped", selectedDay: 13),
            ProofCase(name: "05-observation-only", selectedDay: 14),
            ProofCase(name: "06-accessibility-size-requested", selectedDay: 15, largeText: true),
            ProofCase(name: "07-dark-french", selectedDay: 12, dark: true, french: true)
        ]
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var windows: [NSWindow] = []
        @MainActor func render(_ index: Int) {
            guard index < cases.count else {
                if !args.contains("--interactive") { app.terminate(nil) }
                return
            }
            let item = cases[index]
            let view = ProofView(item: item, history: history, observations: observations, now: now,
                                 selected: date(item.selectedDay), expanded: item.expanded)
            let host = NSHostingView(rootView: view)
            let size = NSSize(width: 393, height: item.largeText ? 850 : 600)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "MORE · \(item.name) · isolated fixture"
            window.contentView = host
            window.center()
            window.orderFront(nil)
            windows.append(window)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                host.layoutSubtreeIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    fatalError("Native bitmap unavailable")
                }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                do {
                    guard let png = bitmap.representation(using: .png, properties: [:]) else {
                        fatalError("PNG encoding failed")
                    }
                    try png.write(to: output.appendingPathComponent(item.name + ".png"))
                    print("Rendered \(item.name)")
                } catch { fatalError("Proof write failed: \(error)") }
                if !args.contains("--interactive") { window.orderOut(nil) }
                render(index + 1)
            }
        }
        render(0)
        app.run()
    }
}
