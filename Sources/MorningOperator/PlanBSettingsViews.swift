import MorningCore
import MorningApple
import SwiftUI
import UserNotifications

struct MorningAlarmView: View {
    @State private var service = MorningAlarmService.shared
    @State private var enabled = false
    @State private var time = Date()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            MorningForm {
                Toggle("Morning alarm", isOn: $enabled)
                    .accessibilityIdentifier("alarm.enabled")
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .accessibilityIdentifier("alarm.time")
                    .disabled(!enabled)
                Text(service.status).font(MorningTheme.Typography.note).accessibilityIdentifier("alarm.status")
                    #if DEBUG
                    .accessibilityValue(service.nativeDiagnostic)
                    #endif
                Text("Stop the alarm to open your morning. Unlock if asked.")
                    .font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                Button("Save") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    Task { await service.save(.init(isEnabled: enabled, hour: components.hour ?? 7, minute: components.minute ?? 0)) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(service.busy).accessibilityIdentifier("alarm.save")
            }
            .navigationTitle("Morning alarm")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .onAppear {
                enabled = service.setting.isEnabled
                time = Calendar.current.date(bySettingHour: service.setting.hour, minute: service.setting.minute, second: 0, of: Date()) ?? Date()
            }
        }
    }
}

struct ShortcutTemplatesView: View {
    @State private var alertStatus = ""
    @Environment(\.openURL) private var openURL
    var body: some View {
        MorningList {
            Section("Step timers") {
                Button("Allow time's up alerts") {
                    Task {
                        do {
                            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            alertStatus = allowed ? AppLanguage.localized("Alerts allowed") : AppLanguage.localized("Allow notifications for MORE in iPhone Settings.")
                        } catch { alertStatus = AppLanguage.localized("Notification permission couldn't be checked.") }
                    }
                }
                if !alertStatus.isEmpty { Text(alertStatus).font(.raleway(.footnote)) }
                Text("Your timer keeps time outside MORE.").font(MorningTheme.Typography.note)
            }
            Section("Shortcuts") {
                if ShortcutTemplate.visible().isEmpty {
                    Text("More shortcuts soon.").font(MorningTheme.Typography.note)
                }
                ForEach(ShortcutTemplate.visible()) { template in
                    if let url = template.url {
                        HStack {
                            Label(template.title, systemImage: template.symbol)
                            Spacer()
                            Button("Add") { openURL(url) }
                        }
                    }
                }
            }
        }.navigationTitle("Shortcuts & timers")
    }
}
