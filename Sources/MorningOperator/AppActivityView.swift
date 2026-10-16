import SwiftUI
import MorningCore
import MorningApple

struct AppActivityView: View {
    @ViewState<AppTransitionDaySummary?> private var summary = nil
    @ViewState<String?> private var errorMessage = nil
    @ViewState<[ObservedApp]> private var misconfigured: [ObservedApp] = []
    @ViewState<Bool> private var showingSetup = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Coming back to the same apps", systemImage: "arrow.triangle.2.circlepath")
                        .font(.serif(.headline))
                    Spacer()
                    Button { showingSetup = true } label: { Image(systemName: "plus.circle") }
                        .accessibilityLabel("Set up app activity")
                }
                if let summary, summary.hasEvents {
                    Text("Today · \(summary.foregroundEntryCount) recorded entries")
                        .font(.raleway(.subheadline, .medium))
                    ForEach(summary.entryCounts.filter { $0.count > 0 }) { count in
                        HStack { Text(count.app.displayName); Spacer(); Text("\(count.count)").monospacedDigit() }
                            .font(.raleway(.subheadline))
                    }
                    if let returns = summary.observedReturnCount {
                        Text("\(returns) returns after another tracked app")
                            .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.accent)
                    }
                    Text("Today's configured app automations only. These entries are separate from phone pickups; gaps and other apps may be missing.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    if !misconfigured.isEmpty {
                        Label("\(misconfigured.map(\.displayName).joined(separator: ", ")) closes right after opening. In Shortcuts, check that its closing automation has only Is Closed selected; until then recordings can't use its times.",
                              systemImage: "exclamationmark.triangle")
                            .font(.raleway(.caption)).foregroundStyle(MorningStyle.accent)
                            .accessibilityIdentifier("appActivity.misconfigured")
                    }
                } else {
                    Text(errorMessage ?? AppLanguage.localized("Connect the apps you want to understand. Their entries and repeated returns will appear here."))
                        .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    Button("Connect app activity") { showingSetup = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .task { await refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await refresh() } }
        }
        .morningSheet(isPresented: $showingSetup) { AppActivitySetupView(onCleared: refresh) }
    }

    private func refresh() async {
        do {
            summary = try await AppTransitionLogStore.shared.summary(for: Date())
            misconfigured = (try? await AppTransitionLogStore.shared.appsClosingRightAfterOpening()) ?? []
            errorMessage = nil
        } catch {
            summary = nil
            errorMessage = AppLanguage.localized("Your saved app activity couldn't be read. It has been kept intact.")
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
                    PageHeading(eyebrow: String(localized: "A little more context", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), title: String(localized: "Notice the loops.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale),
                                subtitle: String(localized: "Connect any app once with Apple's Shortcuts app, such as WhatsApp, Instagram or Mail. Only app names and times are saved locally.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    instruction("1", String(localized: "Choose one app", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), String(localized: "In Shortcuts, open Automation and create an App automation. Choose any app and Is Opened. Select Run Immediately if you want it to work automatically.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    instruction("2", String(localized: "Add Morning Operator", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), String(localized: "Add the action Log an app transition. Tap App and pick that same app, or type its name; if you leave it empty, iOS asks you every time. Choose Opened or switched to. Leave Event ID empty for ordinary use.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    instruction("3", String(localized: "Track when you leave", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), String(localized: "Create a separate automation for the same app with only Is Closed selected. Choose Closed or switched from in our action. Repeat for any other apps you want to include.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                    Text("Try opening two connected apps and returning to the first, then open Review. Counts appear after those automations actually run. Screen recordings you make in MORE also use these times to name the app on each sampled screen. This setup does not start screen recording or read messages.")
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    #if os(iOS)
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Open Shortcuts", systemImage: "arrow.up.right")
                    }.buttonStyle(PrimaryButtonStyle())
                    #endif

                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your saved app activity").font(.serif(.headline))
                        Text("App names and transition times stay on this device until you clear them. Disable the corresponding automations in Shortcuts to stop adding new entries.")
                            .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                        Button("Clear recorded app activity", role: .destructive) { confirmingClear = true }
                            .disabled(clearing)
                            .accessibilityIdentifier("activity.clear")
                        if clearing { ProgressView("Clearing saved activity…") }
                        if let clearMessage {
                            Text(clearMessage).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
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
            clearMessage = AppLanguage.localized("Recorded app activity cleared.")
        } catch {
            clearMessage = AppLanguage.localized("The saved app activity couldn't be cleared. Try again.")
        }
    }

    private func instruction(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number).font(.serif(.headline)).frame(width: 34, height: 34)
                .background(MorningStyle.selected, in: Circle())
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.serif(.headline))
                Text(detail).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
        }
    }
}
