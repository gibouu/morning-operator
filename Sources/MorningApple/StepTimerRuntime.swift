import Foundation
import MorningCore
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

/// The running step's timer, kept in its own small file so a +2 min tap can change it
/// while MORE has no screen: the system runs that intent in MORE's process without a
/// scene. Every change is a load, a pure change and a save with no suspension between
/// them, all on the main actor, so two taps arriving together are applied one after the
/// other and the second one sees the first one's end.
@MainActor public enum StepTimerFile {
    public static var url: URL { timerURL(in: LocalDataControl.defaultDirectory) }
    /// A failed retirement blocks this process until a new timer is durably saved.
    private static var blockedURLs: Set<URL> = []
    private static func timerURL(in directory: URL) -> URL { directory.appendingPathComponent("step-timer.json") }
    private static func file(in directory: URL) -> AtomicJSONFile<StepTimer?> {
        AtomicJSONFile(url: timerURL(in: directory), maximumBytes: 8_192)
    }

    public static func load(directory: URL = LocalDataControl.defaultDirectory) -> StepTimer? {
        guard !blockedURLs.contains(timerURL(in: directory)) else { return nil }
        return try? LocalDataControl(directory: directory).withReadyAccess { _ in try file(in: directory).load() }
    }
    public static func save(_ timer: StepTimer, directory: URL = LocalDataControl.defaultDirectory) throws {
        try LocalDataControl(directory: directory).withReadyAccess { _ in try file(in: directory).save(timer) }
        blockedURLs.remove(timerURL(in: directory))
    }

    /// Retire atomically under the same lock as mutation. A null envelope persists
    /// retirement without relying on deletion, so old controls cannot revive a timer.
    @discardableResult
    public static func clear(directory: URL = LocalDataControl.defaultDirectory) -> Bool {
        blockedURLs.insert(timerURL(in: directory))
        do {
            try LocalDataControl(directory: directory).withReadyAccess { _ in try file(in: directory).save(nil) }
            return true
        } catch { return false }
    }

    /// Applies a change to the saved active timer of this step. Retired or unreadable
    /// storage and failed saves return nil without publishing or scheduling effects.
    @discardableResult
    public static func update<Result>(sessionID: UUID?, stepID: UUID?,
                                      directory: URL = LocalDataControl.defaultDirectory,
                                      _ change: (inout StepTimer) -> Result) -> (StepTimer, Result)? {
        guard !blockedURLs.contains(timerURL(in: directory)) else { return nil }
        return try? LocalDataControl(directory: directory).withReadyAccess { _ -> (StepTimer, Result)? in
            guard var timer = try file(in: directory).load() else { return nil }
            if let sessionID, timer.sessionID != sessionID { return nil }
            if let stepID, timer.stepID != stepID { return nil }
            let result = change(&timer)
            try file(in: directory).save(timer)
            return (timer, result)
        }
    }
}

/// +2 min, shared by the Live Activity button, Siri and MORE's own screen.
@MainActor public enum StepTimerExtension {
    public static func addTwoMinutes(sessionID: UUID?, stepID: UUID?, expectedEnd: Date?,
                                     now: Date = Date()) async -> StepTimer.ExtensionResult? {
        guard let (timer, result) = StepTimerFile.update(sessionID: sessionID, stepID: stepID, {
            $0.extend(expectedEnd: expectedEnd, at: now)
        }) else { return nil }
        if case .extended = result {
            await StepTimerActivity.publish(timer: timer, timeIsUp: false)
            await StepTimerAlert.schedule(for: timer, nextLabel: StepTimerActivity.nextLabel(sessionID: timer.sessionID))
            StepTimerSignals.extended(timer)
        }
        return result
    }
}

/// Lets MORE's screen re-arm its own end-of-step check when an intent moves the end.
@MainActor public enum StepTimerSignals {
    public static var onExtended: (@MainActor (StepTimer) -> Void)?
    static func extended(_ timer: StepTimer) { onExtended?(timer) }
}

/// The local notification that rings at the end of a step while MORE is suspended (an
/// app in the background cannot update its Live Activity at an exact instant without a
/// push server). One fixed identifier: a new end replaces the old request, so one step
/// never rings twice.
@MainActor public enum StepTimerAlert {
    public static var identifier: String {
        let directory = LocalDataControl.defaultDirectory.lastPathComponent
        return directory.hasPrefix("MorningOperatorUITests-") ? "more.step-timer.\(directory)" : "more.step-timer"
    }

    private static let queue = StepTimerAlertQueue()
    private static var revision = 0

    public static func schedule(for timer: StepTimer, nextLabel: String?) async {
        guard StepTimerFile.load() == timer else { return }
        revision += 1
        let requestedRevision = revision
        let operation = queue.enqueue {
            await performSchedule(for: timer, nextLabel: nextLabel, revision: requestedRevision)
        }
        await operation.value
    }

    private static func performSchedule(for timer: StepTimer, nextLabel: String?, revision requestedRevision: Int) async {
        #if canImport(UserNotifications)
        guard revision == requestedRevision, StepTimerFile.load() == timer else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        guard timer.pausedAt == nil, revision == requestedRevision, StepTimerFile.load() == timer else { return }
        let interval = timer.endsAt.timeIntervalSinceNow
        guard interval > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Time's up", bundle: .module)
        if let nextLabel { content.body = nextLabel }
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
        guard StepTimerFile.load() == timer else { return }
        try? await center.add(request)
        if revision != requestedRevision || StepTimerFile.load() != timer {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
        }
        #endif
    }

    public static func cancel() {
        revision += 1
        #if canImport(UserNotifications)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        #endif
    }
}

/// Writes a new end (or Time's up) into the running Live Activity directly, keeping the
/// rest of its content. The coordinator's next ordinary update carries the same timer,
/// because MORE builds every snapshot from `StepTimerFile`.
@MainActor public enum StepTimerActivity {
    public static func nextLabel(sessionID: UUID) -> String? {
        #if canImport(ActivityKit) && os(iOS)
        return activity(for: sessionID)?.content.state.stepTimer?.nextLabel
        #else
        return nil
        #endif
    }

    public static func publish(timer: StepTimer, timeIsUp: Bool) async {
        guard !timeIsUp || timer.pausedAt == nil else { return }
        #if canImport(ActivityKit) && os(iOS)
        guard let activity = activity(for: timer.sessionID),
              let current = activity.content.state.stepTimer, current.stepID == timer.stepID else { return }
        let old = activity.content.state
        let stepTimer = MorningActivityStepTimer(stepID: current.stepID, destination: current.destination,
            endsAt: timer.endsAt, nextDestination: current.nextDestination, hasNextStep: current.hasNextStep,
            pausedRemaining: timer.pausedAt == nil ? nil : timer.remaining(at: Date()), startedAt: timer.startedAt)
        guard let state = try? MorningActivityContentState(category: old.category, status: old.status,
            completedSteps: old.completedSteps, totalSteps: old.totalSteps, updatedAt: Date(), stepTimer: stepTimer) else { return }
        let staleDate = timeIsUp ? Date().addingTimeInterval(MorningLiveActivityCoordinator.staleAfter * 15)
            : state.staleDate(staleAfter: MorningLiveActivityCoordinator.staleAfter)
        let alert = timeIsUp ? AlertConfiguration(
            title: LocalizedStringResource(stringLiteral: String(localized: "Time's up", bundle: .module)),
            body: LocalizedStringResource(stringLiteral: stepTimer.nextLabel), sound: .default) : nil
        await Self.update(id: activity.id, content: ActivityContent(state: state, staleDate: staleDate), alert: alert, expectedTimer: timer)
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func activity(for sessionID: UUID) -> Activity<MorningActivityAttributes>? {
        guard let namespace = MorningActivityNamespace.workspace(directory: LocalDataControl.defaultDirectory,
            isUITesting: ProcessInfo.processInfo.arguments.contains("--ui-testing")) else { return nil }
        return Activity<MorningActivityAttributes>.activities.first {
            $0.attributes.namespace == namespace && $0.attributes.sessionID == sessionID &&
                ($0.activityState == .active || $0.activityState == .stale)
        }
    }

    private nonisolated static func update(id: String, content: ActivityContent<MorningActivityContentState>,
                                           alert: AlertConfiguration?, expectedTimer: StepTimer) async {
        guard let timer = await MainActor.run(body: { StepTimerFile.load() }), timer == expectedTimer,
              let activity = Activity<MorningActivityAttributes>.activities.first(where: { $0.id == id }),
              timer.sessionID == activity.attributes.sessionID,
              timer.stepID == content.state.stepTimer?.stepID, timer.endsAt == content.state.stepTimer?.endsAt,
              activity.content.state.stepTimer?.stepID == timer.stepID else { return }
        if let alert { await activity.update(content, alertConfiguration: alert) }
        else { await activity.update(content) }
    }
    #endif
}

/// Includes each operation's suspended add and its cleanup in the same queue slot.
/// A stale add can only remove its own request before the next operation installs one.
@MainActor public final class StepTimerAlertQueue {
    private var tail: Task<Void, Never>?
    public init() {}
    @discardableResult
    public func enqueue(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = tail
        let next = Task {
            await previous?.value
            await operation()
        }
        tail = next
        return next
    }
}
