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

    private var testAppearance: ColorScheme? {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-testing") else { return nil }
        if arguments.contains("--light-preview") { return .light }
        if arguments.contains("--dark-preview") { return .dark }
        return nil
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let site = Self.webMorningLaunchSite, showingWebPreview {
                WebMorningView(site: site, minutes: 10, onClose: { showingWebPreview = false })
            } else {
                MorningRootView(store: store)
                    .preferredColorScheme(testAppearance)
            }
            #else
            MorningRootView(store: store)
                .preferredColorScheme(testAppearance)
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
