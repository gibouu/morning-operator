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
        let learning = UNNotificationCategory(identifier: MorningInvitationService.learningReminderCategoryIdentifier,
            actions: [], intentIdentifiers: [])
        center.setNotificationCategories([category, learning])
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let content = response.notification.request.content
        // A learning reminder is answered by its body only. The saved invitation, not this
        // payload, tells the app it is a reminder, and the app then starts nothing.
        let isInvitation = content.categoryIdentifier == MorningInvitationService.categoryIdentifier &&
            (response.actionIdentifier == UNNotificationDefaultActionIdentifier ||
             response.actionIdentifier == MorningInvitationService.startActionIdentifier)
        let isLearningReminder = content.categoryIdentifier == MorningInvitationService.learningReminderCategoryIdentifier &&
            response.actionIdentifier == UNNotificationDefaultActionIdentifier
        let matches = (isInvitation || isLearningReminder) &&
            response.notification.request.identifier == MorningInvitationService.currentRequestIdentifier
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
