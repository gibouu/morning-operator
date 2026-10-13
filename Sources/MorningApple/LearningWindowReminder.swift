import Foundation
import MorningCore

/// Why a morning's reminder is not registered with the system. Each is reported as it is:
/// a reminder is never described as scheduled unless the system holds it.
public enum LearningWindowReminderObstacle: String, Sendable, Equatable {
    case notificationsDenied
    /// Delivered quietly or without alerts: the person would not see it in time.
    case notificationsQuiet
    /// Permission was never asked, and this refresh was not the person's own request.
    case permissionNotRequested
    /// The person's own one-time invitation holds the single slot. It is never replaced.
    case personalInvitationPending
    case storageUnavailable
    /// The system did not confirm the request.
    case notConfirmed
}

public enum LearningWindowReminderOutcome: Sendable, Equatable {
    /// The system holds one reminder, for this morning.
    case scheduled(dayKey: String, at: Date)
    /// This morning's reminder time has passed and it has not been used or expired. Whether
    /// the system showed it is not known here. Nothing replaces it until then.
    case reminderTimePassed(dayKey: String, at: Date)
    /// Pause, Stop or the last morning should have removed the reminder and the removal
    /// did not go through: it may still be shown.
    case removalFailed(dayKey: String, at: Date)
    case notScheduled(dayKey: String, at: Date, obstacle: LearningWindowReminderObstacle)
    /// The window is not running (not started, paused, stopped or completed), or has no
    /// morning left to announce. Any reminder it had is removed.
    case nothingToSchedule
}

/// Keeps at most one reminder for a learning window: the next morning's, at the window's
/// start. The OS makes the person start each recording, so the reminder is an invitation
/// to do that and nothing else.
///
/// It goes through `MorningInvitationService` and so inherits its rules: one occurrence,
/// permission asked only on the person's own request, a denied or quiet setting leaves the
/// reminder unscheduled and says so. The service has one slot. A reminder therefore never
/// replaces the person's own pending invitation, and two reminders can never be pending.
///
/// The next reminder is registered when `refresh` runs after the previous one was used,
/// expired unanswered (two hours after the window's start) or was overtaken by a recording.
/// Nothing runs while the app is closed: after an unanswered reminder, the following one is
/// registered the next time the app is opened.
@MainActor
public struct LearningWindowReminderPlanner {
    private let invitations: MorningInvitationService
    private let now: @MainActor () -> Date

    public init(invitations: MorningInvitationService, now: @escaping @MainActor () -> Date = { Date() }) {
        self.invitations = invitations
        self.now = now
    }

    /// - Parameters:
    ///   - observedDayKeys: mornings that already have a recording; they need no reminder.
    ///   - personRequested: true only when the person has just pressed Start on the window.
    ///     It is the one case that may ask for notification permission.
    @discardableResult
    public func refresh(for window: LearningWindow, observedDayKeys: Set<String> = [],
                        personRequested: Bool = false) async -> LearningWindowReminderOutcome {
        await invitations.reconcile()
        let moment = now()
        let current = invitations.invitation.flatMap { $0.disposition == .enabled ? $0 : nil }
        let ownReminder = current.flatMap { $0.learningTarget?.windowID == window.id ? $0 : nil }
        let upcoming = window.state == .active
            ? window.schedule(asOf: moment).countedMornings.filter { !observedDayKeys.contains($0.dayKey) } : []

        // A reminder whose time has come stays until it is used or expires.
        if let ownReminder, let target = ownReminder.learningTarget, ownReminder.scheduledAt <= moment,
           upcoming.contains(where: { $0.dayKey == target.dayKey }) {
            // With notifications off there is nothing on screen to answer.
            guard invitations.settings?.canPresentInvitation == true else {
                return .notScheduled(dayKey: target.dayKey, at: ownReminder.scheduledAt, obstacle: obstacle)
            }
            return .reminderTimePassed(dayKey: target.dayKey, at: ownReminder.scheduledAt)
        }
        guard let next = upcoming.first(where: { $0.expectedStart > moment }) else {
            // Stop, Pause and the last morning all end here: the pending reminder goes.
            if let ownReminder, let target = ownReminder.learningTarget {
                await invitations.cancel()
                if invitations.invitation?.disposition == .enabled {
                    return .removalFailed(dayKey: target.dayKey, at: ownReminder.scheduledAt)
                }
            }
            return .nothingToSchedule
        }
        if let current, current.learningTarget == nil {
            return .notScheduled(dayKey: next.dayKey, at: next.expectedStart, obstacle: .personalInvitationPending)
        }
        let target = MorningInvitationLearningTarget(windowID: window.id, dayKey: next.dayKey)
        if ownReminder?.learningTarget != target || ownReminder?.scheduledAt != next.expectedStart {
            guard let zone = TimeZone(identifier: window.timeZoneIdentifier) else {
                return .notScheduled(dayKey: next.dayKey, at: next.expectedStart, obstacle: .notConfirmed)
            }
            await invitations.schedule(at: next.expectedStart, timeZone: zone, learningTarget: target,
                                       mayRequestPermission: personRequested)
        }
        let saved = invitations.invitation
        if invitations.isScheduled, saved?.disposition == .enabled, saved?.learningTarget == target {
            return .scheduled(dayKey: next.dayKey, at: next.expectedStart)
        }
        return .notScheduled(dayKey: next.dayKey, at: next.expectedStart, obstacle: obstacle)
    }

    private var obstacle: LearningWindowReminderObstacle {
        if invitations.needsRecovery { return .storageUnavailable }
        guard let settings = invitations.settings else { return .notConfirmed }
        switch settings.authorization {
        case .denied: return .notificationsDenied
        case .notDetermined: return .permissionNotRequested
        case .provisional, .ephemeral: return .notificationsQuiet
        case .authorized: return settings.alertsEnabled ? .notConfirmed : .notificationsQuiet
        case .unknown: return .notConfirmed
        }
    }
}
