import AVFAudio
import AlarmKit
import Foundation
import MorningApple
import MorningCore
import Observation
import Speech
import SwiftUI
import UserNotifications

@MainActor @Observable
final class MorningPermissionSetup {
    var isPresented = false
    private(set) var isRevisiting = false
    private var routineAfterDismiss = false
    private(set) var remaining: [MorningPermission] = []
    private(set) var isRequesting = false
    private enum Outcome { case skipped, allowed, denied, unavailable }
    private enum SaveIssue { case restore, save }
    private var outcome: Outcome?
    private var issue: SaveIssue?
    var lastOutcome: String? {
        switch outcome {
        case .skipped: Self.text("You can enable this access later in iPhone Settings.", "Vous pourrez activer cet accès plus tard dans les réglages de l’iPhone.")
        case .allowed: Self.text("Access is ready. You remain in control of when MORE uses it.", "L’accès est prêt. Vous gardez le contrôle de son utilisation par MORE.")
        case .denied: Self.text("Access wasn't enabled. Your morning can continue, and you can change this later in Settings.", "L’accès n’a pas été activé. Votre matinée peut continuer ; vous pourrez le modifier dans les réglages.")
        case .unavailable: Self.text("This access isn't available right now. Continue and review it later in Settings.", "Cet accès est indisponible pour le moment. Continuez et retrouvez-le plus tard dans les réglages.")
        case nil: nil
        }
    }
    var saveIssue: String? {
        switch issue {
        case .restore: Self.text("Your access choices couldn't be restored. You can still review them; the saved file stays intact.", "Vos choix d’accès n’ont pas pu être relus. Vous pouvez les revoir ; le fichier enregistré reste intact.")
        case .save: Self.text("These access choices couldn't be saved. MORE may ask you to review them next time.", "Ces choix d’accès n’ont pas pu être enregistrés. MORE pourra vous les présenter à la prochaine ouverture.")
        case nil: nil
        }
    }
    private var progress = MorningPermissionProgress()
    private let file: AtomicJSONFile<MorningPermissionProgress>
    private let control: LocalDataControl
    private let isolated: Bool
    private var generation: UUID?
    private var attempt: UUID?
    private var requestTask: Task<Void, Never>?
    @ObservationIgnored private weak var activeVoiceAccess: MorningVoiceAccess?
    private var canSave = true
    var current: MorningPermission? { remaining.first }
    var needsInitialSetup: Bool { !progress.pendingInitial.isEmpty && !isolatedBypass }
    private var isolatedBypass: Bool {
        isolated && !ProcessInfo.processInfo.arguments.contains("--ui-testing-permissions")
    }

    init(directory: URL, isolated: Bool) {
        self.isolated = isolated
        control = LocalDataControl(directory: directory)
        file = AtomicJSONFile(url: directory.appendingPathComponent("permission-setup.json"), maximumBytes: 16 * 1_024)
        do {
            progress = try control.withReadyAccess { state in
                generation = state.generation
                do { return try file.load() }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    // Data(contentsOf:) and bounded FileHandle reads use different
                    // Cocoa codes for a genuinely absent first-launch file.
                    return MorningPermissionProgress()
                }
            }
        } catch {
            canSave = false
            issue = .restore
        }
    }

    var screenTimeUnavailableNote: String? {
        supported.contains(.screenTime) ? nil : Self.text("Screen Time needs a compatible iPhone and app capability. You can review its availability later in Settings.", "Temps d’écran nécessite un iPhone compatible et un accès disponible dans cette version. Retrouvez son état plus tard dans Réglages.")
    }
    var supported: [MorningPermission] {
        var values: [MorningPermission] = [.location, .calendar, .reminders]
        if isolated || Self.screenTimeCapabilityAvailable { values.append(.screenTime) }
        values += [.speech, .notifications, .alarms]
        return values
    }

    func presentIfNeeded() {
        guard needsInitialSetup, !isPresented else { return }
        remaining = [.speech]
        isRevisiting = false; routineAfterDismiss = false
        if !isolated, SFSpeechRecognizer.authorizationStatus() == .authorized,
           AVAudioApplication.shared.recordPermission == .granted {
            resolve(.speech, outcome: .allowed)
            return
        }
        isPresented = true
    }

    func revisit() {
        guard !isRequesting else { return }
        remaining = []; outcome = nil
        isRevisiting = true; routineAfterDismiss = false
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
    }

    func choose(_ permission: MorningPermission) {
        guard isRevisiting, !isRequesting, supported.contains(permission) else { return }
        remaining = [permission]; outcome = nil
    }

    func showOverview() {
        guard isRevisiting, !isRequesting else { return }
        remaining = []; outcome = nil
    }

    func skip() {
        guard let current, !isRequesting else { return }
        resolve(current, outcome: .skipped)
    }

    func allow(store: MorningStore) {
        guard let permission = current, !isRequesting, !store.privacyBlocksWork else { return }
        let id = UUID(); attempt = id; isRequesting = true
        requestTask = Task { @MainActor [weak self, weak store] in
            guard let self, let store else { return }
            let allowed: Bool
            do {
                if isolated {
                    // Explicit isolated fixture: tests exercise explanation/queue/persistence,
                    // never alter the simulator or a person's system authorizations.
                    allowed = !ProcessInfo.processInfo.arguments.contains("--ui-testing-permissions-denied")
                } else {
                    switch permission {
                    case .location:
                        _ = await store.briefing.enableCurrentLocation()
                        allowed = store.briefing.locationAuthorization == .authorized
                    case .calendar:
                        await store.briefing.requestCalendarAccess()
                        allowed = store.briefing.isCalendarAuthorized
                    case .reminders:
                        let reminders = ReminderService()
                        try await reminders.requestReminderAccess()
                        allowed = reminders.hasReminderAccess
                    case .screenTime:
                        try await store.screenTimeSource.requestAccess()
                        store.refreshScreenTimeAccess()
                        allowed = store.screenTimeSource.access == .approved
                    case .speech:
                        activeVoiceAccess = store.voiceAccess
                        let access = try await store.voiceAccess.requestAccess(language: .current)
                        allowed = access.speech == .authorized && access.microphone == .granted
                    case .microphone:
                        allowed = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            let completion: @Sendable (Bool) -> Void = { continuation.resume(returning: $0) }
                            AVAudioApplication.requestRecordPermission(completionHandler: completion)
                        }
                    case .notifications:
                        allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                    case .alarms:
                        allowed = try await AlarmManager.shared.requestAuthorization() == .authorized
                    }
                }
                guard attempt == id, !Task.isCancelled, !store.privacyBlocksWork else { return }
                activeVoiceAccess = nil
                isRequesting = false; requestTask = nil; attempt = nil
                resolve(permission, outcome: allowed ? .allowed : .denied)
            } catch {
                guard attempt == id, !store.privacyBlocksWork else { return }
                activeVoiceAccess = nil
                isRequesting = false; requestTask = nil; attempt = nil
                if !(error is CancellationError) {
                    resolve(permission, outcome: .unavailable)
                }
            }
        }
    }

    func finish(reviewRoutine: Bool = false) {
        guard !isRequesting, remaining.isEmpty else { return }
        routineAfterDismiss = reviewRoutine && !isRevisiting
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }

    func takeRoutineReviewRequest() -> Bool {
        defer { routineAfterDismiss = false }
        return routineAfterDismiss
    }

    func cancelForBackground() {
        activeVoiceAccess?.cancel(); activeVoiceAccess = nil
        attempt = nil; requestTask?.cancel(); requestTask = nil; isRequesting = false
    }

    /// Privacy cleanup cancels publication before the app removes the owned file.
    func cancelForPrivacy() {
        activeVoiceAccess?.cancel(); activeVoiceAccess = nil
        attempt = nil; requestTask?.cancel(); requestTask = nil
        isRequesting = false; isPresented = false; remaining = []; outcome = nil
        routineAfterDismiss = false
    }
    func resetAfterPrivacy() {
        progress = MorningPermissionProgress(); generation = try? control.status().generation
        canSave = true; issue = nil; isRevisiting = false; routineAfterDismiss = false
    }

    private func resolve(_ permission: MorningPermission, outcome: Outcome) {
        guard remaining.first == permission else { return }
        var next = progress; next.resolve(permission)
        if permission == .speech { next.resolve(.microphone) }
        do {
            guard canSave else { throw CocoaError(.fileReadCorruptFile) }
            try control.withReadyAccess { state in
                guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
                try file.save(next)
            }
            progress = next
        } catch {
            issue = .save
            // Keep this launch usable even when persistence is unavailable.
            progress = next
        }
        remaining.removeFirst(); self.outcome = outcome
        if !isRevisiting, remaining.isEmpty { finish(reviewRoutine: true) }
    }

    private static var screenTimeCapabilityAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        guard #available(iOS 26.4, *) else { return false }
        // Personal development profiles disclose the capabilities they grant.
        // When a profile is absent, don't present a permission we can't establish.
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(from: data[start.lowerBound..<end.upperBound], options: [], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return false }
        return entitlements["com.apple.developer.family-controls"] as? Bool == true &&
            entitlements["com.apple.developer.family-controls.app-and-website-usage"] as? Bool == true
        #endif
    }

    nonisolated static func text(_ english: String, _ french: String) -> String { AppLanguage.isFrench ? french : english }
}
