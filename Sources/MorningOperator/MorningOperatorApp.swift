import SwiftUI
import MorningCore
import MorningApple

@main
struct MorningOperatorApp: App {
    @UIApplicationDelegateAdaptor(MorningNotificationDelegate.self) private var notificationDelegate
    @ViewState<MorningStore> private var store = MorningStore()
    #if DEBUG
    @State private var showingWebPreview = true
    #endif

    init() { MorningAppShortcuts.updateAppShortcutParameters() }

    var body: some Scene {
        WindowGroup {
            Group {
            #if DEBUG
            if let site = Self.webMorningLaunchSite, showingWebPreview {
                WebMorningView(site: site, minutes: 10, onClose: { showingWebPreview = false })
            } else {
                MorningRootView(store: store)
            }
            #else
            MorningRootView(store: store)
            #endif
            }
            // MORE's local-time palette owns the day-to-night journey. System
            // appearance must not replace its paper, controls or website chrome.
            .preferredColorScheme(.light)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if ProcessInfo.processInfo.arguments.contains("--qa-system-checks"),
                   ["com.gibouu.morningoperator.qa", "com.gibouu.morningoperator.systemqa"].contains(Bundle.main.bundleIdentifier ?? "") {
                    Text(verbatim: "QA")
                        .font(.caption2).padding(4)
                        .accessibilityIdentifier("system.qaIdentity")
                        .accessibilityLabel(Text(verbatim: "\(Bundle.main.bundleIdentifier ?? "missing")|\(Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "missing")"))
                        .allowsHitTesting(false)
                }
            }
            #endif
        }
    }

    #if DEBUG
    /// `--web-morning --web-morning-site=news` opens the in-app
    /// browser on its own for device checks. All page actions still require a tap.
    private static var webMorningLaunchSite: WebMorningSite? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--web-morning") else { return nil }
        let name = arguments.first { $0.hasPrefix("--web-morning-site=") }?.dropFirst("--web-morning-site=".count)
        return name.flatMap { WebMorningSite(rawValue: String($0)) } ?? .news
    }

    #endif
}
