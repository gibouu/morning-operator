import UIKit
import UserNotifications
import MorningCore
import MorningApple

/// Delivery only displays an invitation. Only a person choosing the notification
/// body or its foreground action can enqueue entry into the morning.
@MainActor
final class MorningNotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let start = UNNotificationAction(identifier: MorningInvitationService.startActionIdentifier,
            title: String(localized: "Start morning"), options: [.foreground, .authenticationRequired])
        let category = UNNotificationCategory(identifier: MorningInvitationService.categoryIdentifier,
            actions: [start], intentIdentifiers: [])
        center.setNotificationCategories([category])
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let content = response.notification.request.content
        let matches = content.categoryIdentifier == MorningInvitationService.categoryIdentifier &&
            response.notification.request.identifier == MorningInvitationService.currentRequestIdentifier &&
            (response.actionIdentifier == UNNotificationDefaultActionIdentifier ||
             response.actionIdentifier == MorningInvitationService.startActionIdentifier)
        let payload = matches ? MorningInvitationPayload(userInfo: content.userInfo) : nil
        // Complete on the main actor explicitly. The SDK's async delegate bridge
        // completed on a cooperative worker in the real simulator tap trial, which
        // reached UIKit state restoration off its required main thread.
        Task { @MainActor in
            if let payload { MorningIntentRouter.shared.requestStart(invitation: payload) }
            completionHandler()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler([.banner, .sound, .list]) }
    }
}
