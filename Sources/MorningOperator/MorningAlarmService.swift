import AlarmKit
import AppIntents
import Foundation
import MorningCore
import Observation
import SwiftUI

private struct MorningAlarmMetadata: AlarmMetadata {}
private struct MorningAlarmFile: Codable {
    var setting = MorningAlarmSetting()
    var recorded: ScheduledMorningAlarm?
}

@MainActor @Observable
final class MorningAlarmService {
    static let shared = MorningAlarmService()
    private(set) var setting = MorningAlarmSetting()
    private(set) var status = String(localized: "Off")
    private(set) var busy = false
    private var recorded: ScheduledMorningAlarm?
    @ObservationIgnored private var systemObservers: [Task<Void, Never>] = []
    #if DEBUG
    /// Scalar diagnostics only: no alarm identities or account data enter test evidence.
    var nativeDiagnostic: String {
        let auth: String
        switch AlarmManager.shared.authorizationState {
        case .authorized: auth = "authorized"
        case .denied: auth = "denied"
        case .notDetermined: auth = "notDetermined"
        @unknown default: auth = "unknown"
        }
        guard let alarms = try? AlarmManager.shared.alarms else { return "auth:\(auth)|scheduled:unknown" }
        let owned = recorded.map { record in alarms.filter { $0.id == record.id }.count } ?? 0
        return "auth:\(auth)|scheduled:\(alarms.count)|recorded:\(recorded == nil ? 0 : 1)|owned:\(owned)"
    }
    #endif
    private var isIsolatedTest: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.gibouu.morningoperator.qa",
           arguments.contains("--qa-system-checks") { return false }
        #endif
        return arguments.contains("--ui-testing")
    }
    private let file = AtomicJSONFile<MorningAlarmFile>(url: LocalDataControl.defaultDirectory.appendingPathComponent("morning-alarm.json"))
    private init() {
        if let saved = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess({ _ in try file.load() }) {
            setting = saved.setting; recorded = saved.recorded
            status = setting.isEnabled ? String(localized: "Check your scheduled alarm") : String(localized: "Off")
        }
        guard !isIsolatedTest else { return }
        refreshSystemStatus()
        // AlarmKit owns the schedule and permission outside this process. These
        // observations only reconcile the displayed status; they never reschedule
        // an alarm or request permission without the person's Save action.
        systemObservers = [
            Task { [weak self] in
                for await _ in AlarmManager.shared.alarmUpdates {
                    guard !Task.isCancelled, let self else { return }
                    if !self.busy { self.refreshSystemStatus() }
                }
            },
            Task { [weak self] in
                for await _ in AlarmManager.shared.authorizationUpdates {
                    guard !Task.isCancelled, let self else { return }
                    if !self.busy { self.refreshSystemStatus() }
                }
            }
        ]
    }

    private func refreshSystemStatus() {
        guard !isIsolatedTest,
              let privacy = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).status(),
              !privacy.forgetPending else { return }
        guard setting.isEnabled else { status = String(localized: "Off"); return }
        guard AlarmManager.shared.authorizationState == .authorized else {
            status = String(localized: "Allow alarms for MORE in Settings, then save again."); return
        }
        guard let alarms = try? AlarmManager.shared.alarms else {
            status = String(localized: "The scheduled alarm couldn't be checked. Try saving again."); return
        }
        guard let recorded, alarms.contains(where: { $0.id == recorded.id }),
              recorded.hour == setting.hour, recorded.minute == setting.minute else {
            status = String(localized: "Your morning alarm is missing. Save again to schedule it."); return
        }
        status = String(localized: "Scheduled every day")
    }

    /// Permission is requested only from this explicit Save action.
    func save(_ desired: MorningAlarmSetting) async {
        guard !isIsolatedTest else {
            status = String(localized: "System alarms are unavailable in an isolated test workspace."); return
        }
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let control = LocalDataControl(directory: LocalDataControl.defaultDirectory)
            let generation = try control.withReadyAccess { $0.generation }
            func requireGeneration(_ state: LocalDataControlState) throws {
                guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
            }
            if desired.isEnabled, AlarmManager.shared.authorizationState == .notDetermined {
                _ = try await AlarmManager.shared.requestAuthorization()
            }
            try control.withReadyAccess { try requireGeneration($0) }
            let alarms = try AlarmManager.shared.alarms
            let change = MorningAlarmPlan.change(setting: desired, recorded: recorded,
                systemAlarmIDs: Set(alarms.map(\.id)), authorized: AlarmManager.shared.authorizationState == .authorized)
            guard !change.needsAuthorization else {
                status = String(localized: "Allow alarms for MORE in Settings, then save again."); return
            }
            for id in change.cancel { try AlarmManager.shared.cancel(id: id) }
            let newRecord: ScheduledMorningAlarm?
            if let time = change.schedule {
                let id = UUID()
                newRecord = .init(id: id, hour: time.hour, minute: time.minute)
                // Record the identity before scheduling. If the process ends after
                // schedule, the next Save reconciles this same system alarm.
                try control.withReadyAccess { state in
                    try requireGeneration(state)
                    try file.save(MorningAlarmFile(setting: desired, recorded: newRecord))
                }
                let alert = AlarmPresentation.Alert(title: "Good morning", stopButton:
                    AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"),
                    secondaryButton: AlarmButton(text: "Start MORE", textColor: .white, systemImageName: "sun.horizon"),
                    secondaryButtonBehavior: .custom)
                let attributes = AlarmAttributes(presentation: AlarmPresentation(alert: alert),
                    metadata: MorningAlarmMetadata(), tintColor: .orange)
                let intent = StartFromMorningAlarmIntent(alarmID: id)
                let configuration = AlarmManager.AlarmConfiguration.alarm(
                    schedule: .relative(.init(time: .init(hour: time.hour, minute: time.minute),
                        repeats: .weekly([.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]))),
                    attributes: attributes, stopIntent: intent, secondaryIntent: intent)
                _ = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
                // A forget may have begun while the system scheduled the alarm.
                do { try control.withReadyAccess { try requireGeneration($0) } }
                catch { try? AlarmManager.shared.cancel(id: id); throw error }
            } else { newRecord = desired.isEnabled ? recorded : nil }
            try control.withReadyAccess { state in
                    try requireGeneration(state)
                    try file.save(MorningAlarmFile(setting: desired, recorded: newRecord))
                }
            recorded = newRecord; setting = desired
            refreshSystemStatus()
        } catch { status = String(localized: "The alarm couldn't be saved. Check it and try again. \(error.localizedDescription)") }
    }

    /// Errors must keep the app's forget marker pending so cleanup can be retried.
    func forget() throws {
        if !isIsolatedTest {
            for alarm in try AlarmManager.shared.alarms { try AlarmManager.shared.cancel(id: alarm.id) }
        }
        if FileManager.default.fileExists(atPath: file.url.path) { try FileManager.default.removeItem(at: file.url) }
        recorded = nil; setting = MorningAlarmSetting(); status = String(localized: "Off")
    }
}

struct StartFromMorningAlarmIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Start morning from alarm"
    static let supportedModes: IntentModes = .foreground(.immediate)
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication
    @Parameter(title: "Alarm") var alarm: String
    init() { alarm = "" }
    init(alarmID: UUID) { alarm = alarmID.uuidString }
    @MainActor func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: alarm) else { return .result() }
        try? AlarmManager.shared.stop(id: id)
        MorningIntentRouter.shared.requestStart(entryID: MorningAlarmPlan.entryID(alarmID: id, at: Date()))
        return .result()
    }
}
