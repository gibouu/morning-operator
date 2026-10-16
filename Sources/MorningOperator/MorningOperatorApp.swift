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
            if ProcessInfo.processInfo.arguments.contains("--preview-onboarding") {
                MorningWelcomePreview()
            } else if let site = Self.webMorningLaunchSite, showingWebPreview {
                WebMorningView(site: site, minutes: 10, onClose: { showingWebPreview = false })
                    .preferredColorScheme(.light)
            } else if ProcessInfo.processInfo.arguments.contains("--ui-testing")
                        && !ProcessInfo.processInfo.arguments.contains("--ui-testing-real-subscription") {
                MorningRootView(store: store)
            } else {
                MorningSubscriptionEntryView(store: store)
            }
            #else
            MorningSubscriptionEntryView(store: store)
            #endif
            }
            .environment(\.locale, AppLanguage.locale)
            .environment(\.layoutDirection, .leftToRight)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if ProcessInfo.processInfo.arguments.contains("--qa-system-checks"),
                   ["com.gibouu.morningoperator.qa", "com.gibouu.morningoperator.systemqa"].contains(Bundle.main.bundleIdentifier ?? "") {
                    Text(verbatim: "QA")
                        .font(.raleway(.caption2)).padding(4)
                        .accessibilityIdentifier("system.qaIdentity")
                        .accessibilityLabel(Text(verbatim: "\(Bundle.main.bundleIdentifier ?? "missing")|\(Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "missing")"))
                        .allowsHitTesting(false)
                } else if let workspace = Self.testWorkspace,
                          !ProcessInfo.processInfo.arguments.contains("--preview-onboarding") {
                    Text(verbatim: "Test routine")
                        .font(.raleway(.caption2)).padding(4)
                        .dynamicTypeSize(.medium)
                        .accessibilityIdentifier("qa.testWorkspace")
                        .accessibilityValue(workspace)
                        .allowsHitTesting(false)
                }
            }
            #endif
        }
    }

    #if DEBUG
    private static var testWorkspace: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--ui-testing"),
              let argument = args.first(where: { $0.hasPrefix("--ui-testing-workspace=") }),
              let id = UUID(uuidString: String(argument.dropFirst("--ui-testing-workspace=".count))) else { return nil }
        return id.uuidString
    }

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
