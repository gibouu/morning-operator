import Foundation
import MorningCore
import Observation
import UserNotifications

public enum MorningInvitationAuthorization: String, Sendable, Equatable { case notDetermined, denied, authorized, provisional, ephemeral, unknown }

public struct MorningInvitationNotificationSettings: Sendable, Equatable {
    public let authorization: MorningInvitationAuthorization
    public let alertsEnabled: Bool
    public let soundsEnabled: Bool
    public var canPresentInvitation: Bool { authorization == .authorized && alertsEnabled }

    public init(authorization: MorningInvitationAuthorization, alertsEnabled: Bool, soundsEnabled: Bool) {
        self.authorization = authorization
        self.alertsEnabled = alertsEnabled
        self.soundsEnabled = soundsEnabled
    }
}

public struct MorningInvitationPendingRequest: Sendable, Equatable {
    public let payload: MorningInvitationPayload?
    public let scheduledAt: Date?
    public init(payload: MorningInvitationPayload?, scheduledAt: Date?) {
        self.payload = payload; self.scheduledAt = scheduledAt
    }

    public func matches(_ invitation: MorningInvitation) -> Bool {
        guard payload == invitation.payload, let scheduledAt else { return false }
        return abs(scheduledAt.timeIntervalSince(invitation.scheduledAt)) < 1
    }
}

/// All methods concern only MORE's single invitation identifier, never other notifications.
@MainActor
public protocol MorningInvitationNotificationClient {
    func settings() async -> MorningInvitationNotificationSettings
    func requestAuthorization() async throws -> Bool
    func pendingInvitation() async -> MorningInvitationPendingRequest?
    func add(_ invitation: MorningInvitation, sound: Bool) async throws
    func removePendingInvitation() async
    func removeDeliveredInvitation() async
    func hasDeliveredInvitation() async -> Bool
}

public enum MorningInvitationForgetError: LocalizedError, Sendable, Equatable {
    case alreadyForgetting, cleanupUnconfirmed, staleGeneration
    public var errorDescription: String? {
        switch self {
        case .alreadyForgetting: String(localized: "Invitation cleanup is already in progress.", bundle: .module)
        case .cleanupUnconfirmed: String(localized: "The invitation could not be fully removed. Retry forgetting your local data.", bundle: .module)
        case .staleGeneration: String(localized: "Your local data changed. Open Morning again before scheduling an invitation.", bundle: .module)
        }
    }
}

@MainActor
public protocol MorningInvitationStorage {
    func load() throws -> MorningInvitation?
    func save(_ invitation: MorningInvitation?) throws
}

@MainActor
public struct MorningInvitationFileStorage: MorningInvitationStorage {
    private let file: AtomicJSONFile<MorningInvitation?>
    public init(directory: URL) {
        file = AtomicJSONFile(url: directory.appendingPathComponent("morning-invitation.json"))
    }
    public func load() throws -> MorningInvitation? {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return nil }
        return try file.load()
    }
    public func save(_ invitation: MorningInvitation?) throws { try file.save(invitation) }
}

/// Persists desired configuration before requesting OS scheduling. Registration is not
/// evidence of delivery, awakening, recording, or routine execution. One authoritative writer.
@MainActor
@Observable
public final class MorningInvitationService {
    public nonisolated static let requestIdentifier = "more.morning.invitation"
    public nonisolated static let testRequestIdentifier = "more.morning.invitation.ui-testing"
    /// A fixture workspace must never reconcile or remove the person's real invitation.
    public nonisolated static var currentRequestIdentifier: String {
        ProcessInfo.processInfo.arguments.contains("--ui-testing") ? testRequestIdentifier : requestIdentifier
    }
    public nonisolated static let categoryIdentifier = "MORE_MORNING_INVITATION"
    public nonisolated static let startActionIdentifier = "MORE_START_MORNING"

    public private(set) var invitation: MorningInvitation?
    public private(set) var settings: MorningInvitationNotificationSettings?
    public private(set) var isBusy = false
    public private(set) var isScheduled = false
    public private(set) var errorMessage: String?
    public private(set) var statusText = String(localized: "No invitation is scheduled.", bundle: .module)
    public var needsRecovery: Bool { !storageAvailable }

    @ObservationIgnored private let storage: any MorningInvitationStorage
    @ObservationIgnored private let notifications: any MorningInvitationNotificationClient
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let privacy: LocalDataControl?
    @ObservationIgnored private var invitationGeneration: UUID?
    public private(set) var isForgetting = false
    private var storageAvailable = true
    /// Transient evidence of an explicit Schedule tap. Never restored from disk.
    @ObservationIgnored private var pendingPermissionOccurrenceID: UUID?
    @ObservationIgnored private var revision = UUID()
    @ObservationIgnored private var tail: Task<Void, Never>?

    public convenience init(directory: URL) {
        self.init(storage: MorningInvitationFileStorage(directory: directory),
                  notifications: NativeMorningInvitationNotificationClient(),
                  privacy: LocalDataControl(directory: directory))
    }

    public init(storage: any MorningInvitationStorage,
                notifications: any MorningInvitationNotificationClient,
                privacy: LocalDataControl? = nil,
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.storage = storage; self.notifications = notifications; self.privacy = privacy; self.now = now
        reload()
    }

    /// Refreshes settings and repairs only a still-future desired schedule. Never creates
    /// permission intent; it may finish an explicit Schedule request already in flight.
    public func reconcile() async {
        guard !isForgetting else { return }
        reload()
        await enqueueReconciliation().value
    }

    /// Call only from the person's explicit Schedule action. This is the only prompt path.
    /// A denied request remains a saved, unscheduled preference that can be retried later.
    public func schedule(at date: Date, timeZone: TimeZone = .current) async {
        guard storageAvailable, !isForgetting else { return }
        do {
            let desired = try MorningInvitation(scheduledAt: date, timeZoneIdentifier: timeZone.identifier, now: now())
            try withReadyStorage { try storage.save(desired) }
            invitation = desired
            pendingPermissionOccurrenceID = desired.id
            errorMessage = nil
            isScheduled = false
            await enqueueReconciliation().value
        } catch { report(error) }
    }

    /// Explicit cancellation can also replace this feature's corrupt preference with nil.
    /// Routine/workspace data is separate and is never removed here.
    public func cancel() async {
        guard !isForgetting else { return }
        pendingPermissionOccurrenceID = nil
        do {
            var cancelled = invitation
            cancelled?.cancel()
            try withReadyStorage(requireCurrentGeneration: true) { try storage.save(cancelled) }
            invitation = cancelled
            storageAvailable = true
            errorMessage = nil
            isScheduled = false
            await enqueueReconciliation().value
        } catch { report(error) }
    }

    /// Erases this feature's saved metadata as well as its native request. Unlike
    /// cancellation this leaves no occurrence/date tombstone. Allowed during the
    /// app's durable forgetting phase; ordinary scheduling stays blocked throughout.
    public func forget() async throws {
        guard !isForgetting else { throw MorningInvitationForgetError.alreadyForgetting }
        isForgetting = true
        isBusy = true
        pendingPermissionOccurrenceID = nil
        let id = UUID()
        revision = id
        let previous = tail
        var saveFailure: (any Error)?
        do { try saveForgottenPreference(); storageAvailable = true }
        catch { saveFailure = error; storageAvailable = false }
        invitation = nil
        invitationGeneration = nil
        isScheduled = false
        defer {
            if revision == id { tail = nil; isBusy = false }
            isForgetting = false
        }
        // An old add may be inside the OS already. Wait for it before removing it.
        await previous?.value
        await removeNativeInvitation()
        let pending = await notifications.pendingInvitation()
        let delivered = await notifications.hasDeliveredInvitation()
        if let saveFailure { report(saveFailure); throw saveFailure }
        guard pending == nil, !delivered else {
            let error = MorningInvitationForgetError.cleanupUnconfirmed
            report(error)
            throw error
        }
        errorMessage = nil
        statusText = String(localized: "No invitation is scheduled.", bundle: .module)
    }

    /// Consume only after the app's foreground/busy policy says it can accept the entry.
    /// Saves before returning. A crash afterwards may require manual Start; this provides
    /// at-most-once automatic entry, not exactly-once execution across separate stores.
    public func consume(_ payload: MorningInvitationPayload) throws -> MorningInvitation? {
        guard storageAvailable, !isForgetting else { throw MorningInvitationError.invalidRecord }
        guard var current = invitation, current.consume(payload, at: now()) else { return nil }
        do { try withReadyStorage(requireCurrentGeneration: true) { try storage.save(current) } }
        catch { report(error); throw error }
        invitation = current
        pendingPermissionOccurrenceID = nil
        isScheduled = false
        errorMessage = nil
        _ = enqueueReconciliation()
        return current
    }

    public nonisolated static func payload(from userInfo: [AnyHashable: Any]) -> MorningInvitationPayload? {
        MorningInvitationPayload(userInfo: userInfo)
    }

    private func reload() {
        do {
            invitation = try withReadyStorage { try storage.load() }
            if invitation?.id != pendingPermissionOccurrenceID || invitation?.disposition != .enabled {
                pendingPermissionOccurrenceID = nil
            }
            storageAvailable = true
            errorMessage = nil
        } catch {
            invitation = nil
            isScheduled = false
            storageAvailable = false
            pendingPermissionOccurrenceID = nil
            report(error)
        }
    }

    /// Durable desired changes happen synchronously before this queue. Native work is
    /// serialized so a late add/permission callback cannot recreate a cancelled schedule
    /// or remove a newer replacement. Every suspended operation rechecks its revision.
    private func enqueueReconciliation() -> Task<Void, Never> {
        let id = UUID()
        revision = id
        isBusy = true
        let previous = tail
        let generation = invitationGeneration
        let task = Task { @MainActor [self] in
            await previous?.value
            guard revision == id else { return }
            await applyDesiredState(id: id, generation: generation)
            if revision == id { isBusy = false }
        }
        tail = task
        return task
    }

    private func applyDesiredState(id: UUID, generation: UUID?) async {
        do {
            try checkGeneration(generation)
            var latestSettings = await notifications.settings()
            guard revision == id else { return }
            try checkGeneration(generation)
            settings = latestSettings
            guard storageAvailable else {
                await removeNativeInvitation()
                return
            }
            if var current = invitation, current.expire(at: now()) {
                try withReadyStorage(requireCurrentGeneration: true) { try storage.save(current) }
                invitation = current
                pendingPermissionOccurrenceID = nil
            }
            guard let current = invitation, current.disposition == .enabled else {
                await removeNativeInvitation()
                guard revision == id else { return }
                isScheduled = false
                switch invitation?.disposition {
                case .consumed: statusText = String(localized: "Invitation used. Open Morning to continue.", bundle: .module)
                case .expired: statusText = String(localized: "This invitation has expired. Choose another time.", bundle: .module)
                default: statusText = String(localized: "No invitation is scheduled.", bundle: .module)
                }
                return
            }
            if pendingPermissionOccurrenceID == current.id {
                // Claim the explicit request before suspending. A passive refresh can
                // carry it forward while settings loads, but cannot ask a second time.
                pendingPermissionOccurrenceID = nil
                if latestSettings.authorization == .notDetermined || latestSettings.authorization == .provisional {
                    _ = try await notifications.requestAuthorization()
                    guard revision == id else { return }
                    try checkGeneration(generation)
                    latestSettings = await notifications.settings()
                    guard revision == id else { return }
                    try checkGeneration(generation)
                    settings = latestSettings
                }
            }
            guard latestSettings.canPresentInvitation else {
                await removeNativeInvitation()
                guard revision == id else { return }
                isScheduled = false
                switch latestSettings.authorization {
                case .notDetermined: statusText = String(localized: "Allow notifications to schedule this invitation.", bundle: .module)
                case .provisional: statusText = String(localized: "Notifications are quiet. Allow alerts for a morning invitation.", bundle: .module)
                default: statusText = String(localized: "Notifications are off. Your chosen time is saved but is not scheduled.", bundle: .module)
                }
                return
            }
            // A due occurrence may already be in Notification Center. Do not re-add it
            // or remove it until consumed, cancelled or expired.
            guard current.scheduledAt > now() else {
                isScheduled = false
                statusText = String(localized: "The invitation time has passed. Open Morning when you are ready.", bundle: .module)
                return
            }
            let pending = await notifications.pendingInvitation()
            guard revision == id else { return }
            try checkGeneration(generation)
            if pending?.matches(current) != true {
                await notifications.removeDeliveredInvitation()
                guard revision == id else { return }
                try checkGeneration(generation)
                try await notifications.add(current, sound: latestSettings.soundsEnabled)
                guard revision == id else { return }
                try checkGeneration(generation)
            }
            let registered = await notifications.pendingInvitation()
            guard revision == id else { return }
            try checkGeneration(generation)
            isScheduled = registered?.matches(current) == true
            if isScheduled {
                errorMessage = nil
                statusText = String(localized: "One-time invitation scheduled. Delivery follows your notification settings.", bundle: .module)
            } else if current.scheduledAt <= now() {
                statusText = String(localized: "The invitation time has passed. Open Morning when you are ready.", bundle: .module)
            } else {
                errorMessage = String(localized: "The invitation could not be confirmed. Try scheduling it again.", bundle: .module)
                statusText = errorMessage!
            }
        } catch {
            // A replacement waits for this job, so cleanup cannot remove its newer add.
            await removeNativeInvitation()
            guard revision == id else { return }
            report(error)
        }
    }

    private func removeNativeInvitation() async {
        await notifications.removePendingInvitation()
        await notifications.removeDeliveredInvitation()
    }

    private func withReadyStorage<T>(requireCurrentGeneration: Bool = false, _ body: () throws -> T) throws -> T {
        guard let privacy else { return try body() }
        return try privacy.withReadyAccess { state in
            if requireCurrentGeneration, state.generation != invitationGeneration {
                throw MorningInvitationForgetError.staleGeneration
            }
            let value = try body()
            invitationGeneration = state.generation
            return value
        }
    }

    private func saveForgottenPreference() throws {
        guard let privacy else { try storage.save(nil); return }
        let state = try privacy.status()
        if state.forgetPending, let generation = state.generation {
            try privacy.withForgetAccess(expectedGeneration: generation) { try storage.save(nil) }
        } else {
            try privacy.withReadyAccess { _ in try storage.save(nil) }
        }
    }

    private func checkGeneration(_ generation: UUID?) throws {
        guard let privacy else { return }
        try privacy.withReadyAccess { state in
            guard state.generation == generation else { throw MorningInvitationForgetError.staleGeneration }
        }
    }

    private func report(_ error: any Error) {
        isScheduled = false
        errorMessage = error.localizedDescription
        statusText = error.localizedDescription
    }
}

public extension MorningInvitationPayload {
    init?(userInfo: [AnyHashable: Any]) {
        guard let occurrence = userInfo[Self.occurrenceKey] as? String,
              let schema = userInfo[Self.schemaKey] as? String else { return nil }
        self.init(dictionary: [Self.occurrenceKey: occurrence, Self.schemaKey: schema])
    }

    var userInfo: [AnyHashable: Any] { dictionary }
}

@MainActor
private final class NativeMorningInvitationNotificationClient: MorningInvitationNotificationClient {
    private let center = UNUserNotificationCenter.current()
    private let requestIdentifier = MorningInvitationService.currentRequestIdentifier

    func settings() async -> MorningInvitationNotificationSettings {
        let current = await center.notificationSettings()
        let authorization: MorningInvitationAuthorization
        switch current.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .authorized: authorization = .authorized
        case .provisional: authorization = .provisional
        #if os(iOS)
        case .ephemeral: authorization = .ephemeral
        #endif
        @unknown default: authorization = .unknown
        }
        return .init(authorization: authorization, alertsEnabled: current.alertSetting == .enabled,
                     soundsEnabled: current.soundSetting == .enabled)
    }

    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound]) }

    func pendingInvitation() async -> MorningInvitationPendingRequest? {
        let requests = await center.pendingNotificationRequests()
        guard let request = requests.first(where: { $0.identifier == requestIdentifier }) else { return nil }
        return .init(payload: MorningInvitationService.payload(from: request.content.userInfo),
                     scheduledAt: (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
    }

    func add(_ invitation: MorningInvitation, sound: Bool) async throws {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Ready for your morning?", bundle: .module)
        content.body = String(localized: "Tap to begin with MORE.", bundle: .module)
        content.categoryIdentifier = MorningInvitationService.categoryIdentifier
        content.userInfo = invitation.payload.dictionary
        content.interruptionLevel = .active
        content.sound = sound ? .default : nil
        // Pin the absolute instant to UTC; the separately persisted display zone is only a label.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: invitation.scheduledAt)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: trigger)
        try await center.add(request)
    }

    func removePendingInvitation() async {
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        // Queue a read after asynchronous removal before allowing a replacement job.
        _ = await center.pendingNotificationRequests()
    }

    func removeDeliveredInvitation() async {
        center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        _ = await center.deliveredNotifications()
    }

    func hasDeliveredInvitation() async -> Bool {
        await center.deliveredNotifications().contains { $0.request.identifier == requestIdentifier }
    }
}
