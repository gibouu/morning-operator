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
    private var isIsolatedTest: Bool { ProcessInfo.processInfo.arguments.contains("--ui-testing") }
    private let file = AtomicJSONFile<MorningAlarmFile>(url: LocalDataControl.defaultDirectory.appendingPathComponent("morning-alarm.json"))
    private init() {
        guard let saved = try? LocalDataControl(directory: LocalDataControl.defaultDirectory).withReadyAccess({ _ in try file.load() }) else { return }
        setting = saved.setting; recorded = saved.recorded
        status = setting.isEnabled ? String(localized: "Check your scheduled alarm") : String(localized: "Off")
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
            status = desired.isEnabled ? String(localized: "Scheduled every day") : String(localized: "Off")
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
