import SwiftUI
import MorningCore
import MorningApple

struct AppActivityView: View {
    @ViewState<AppTransitionDaySummary?> private var summary = nil
    @ViewState<String?> private var errorMessage = nil
    @ViewState<Bool> private var showingSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Coming back to the same apps", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                    Spacer()
                    Button { showingSetup = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Set up app activity")
                }
                if let summary, summary.hasEvents {
                    Text("Today · \(summary.foregroundEntryCount) recorded entries")
                        .font(.subheadline.weight(.medium))
                    ForEach(summary.entryCounts.filter { $0.count > 0 }) { count in
                        HStack { Text(count.app.displayName); Spacer(); Text("\(count.count)").monospacedDigit() }
                            .font(.subheadline)
                    }
                    if let returns = summary.observedReturnCount {
                        Text("\(returns) returns after another tracked app")
                            .font(.subheadline).foregroundStyle(MorningStyle.accent)
                    }
                    Text("Today's configured app automations only. These entries are separate from phone pickups; gaps and other apps may be missing.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(errorMessage ?? "Connect the apps you want to understand. Their entries and repeated returns will appear here.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Connect app activity") { showingSetup = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .sheet(isPresented: $showingSetup) { AppActivitySetupView(onCleared: refresh) }
    }

    private func refresh() async {
        do {
            summary = try await AppTransitionLogStore.shared.summary(for: Date())
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = "Your saved app activity couldn't be read. It has been kept intact."
        }
    }
}

private struct AppActivitySetupView: View {
    let onCleared: @MainActor () async -> Void
    @Environment(\.dismiss) private var dismiss
    @ViewState<Bool> private var confirmingClear = false
    @ViewState<Bool> private var clearing = false
    @ViewState<String?> private var clearMessage = nil
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(eyebrow: "A little more context", title: "Notice the loops.",
                                subtitle: "Connect Instagram, TikTok or Snapchat once with Apple's Shortcuts app. Only app names and times are saved locally.")
                    instruction("1", "Choose one app", "In Shortcuts, open Automation and create an App automation. Choose one supported app and Is Opened. Select Run Immediately if you want it to work automatically.")
                    instruction("2", "Add Morning Operator", "Add the action Log an app transition. Choose that same app and Opened or switched to. Leave Event ID empty for ordinary use.")
                    instruction("3", "Track when you leave", "Create a separate Is Closed automation for the same app. Choose Closed or switched from in our action. Repeat for any other supported apps you want to include.")
                    Text("Try opening two connected apps and returning to the first, then open Review. Counts appear after those automations actually run. This setup does not start screen recording or read messages.")
                        .font(.footnote).foregroundStyle(.secondary)
                    #if os(iOS)
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Open Shortcuts", systemImage: "arrow.up.right")
                    }.buttonStyle(PrimaryButtonStyle())
                    #endif

                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your saved app activity").font(.headline)
                        Text("App names and transition times stay on this device until you clear them. Disable the corresponding automations in Shortcuts to stop adding new entries.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Clear recorded app activity", role: .destructive) { confirmingClear = true }
                            .disabled(clearing)
                            .accessibilityIdentifier("activity.clear")
                        if clearing { ProgressView("Clearing saved activity…") }
                        if let clearMessage {
                            Text(clearMessage).font(.footnote).foregroundStyle(.secondary)
                                .accessibilityIdentifier("activity.clearResult")
                        }
                    }
                }.padding(24).frame(maxWidth: 620).frame(maxWidth: .infinity)
            }.background(MorningStyle.background).navigationTitle("App activity")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .confirmationDialog("Clear recorded app activity?", isPresented: $confirmingClear, titleVisibility: .visible) {
                    Button("Clear app names and times", role: .destructive) {
                        Task { await clearActivity() }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove all recorded app names and transition times from Morning Operator on this device. Your routines and notes are kept. Shortcuts automations can still add new entries.")
                }
        }
    }

    @MainActor
    private func clearActivity() async {
        clearing = true
        clearMessage = nil
        defer { clearing = false }
        do {
            try await AppTransitionLogStore.shared.clear()
            await onCleared()
            clearMessage = "Recorded app activity cleared."
        } catch {
            clearMessage = "The saved app activity couldn't be cleared. Try again."
        }
    }

    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.headline).frame(width: 34, height: 34)
                .background(MorningStyle.lavender, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
