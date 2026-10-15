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
            Form {
                Toggle("Morning alarm", isOn: $enabled)
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .disabled(!enabled)
                Text(service.status).font(.footnote).accessibilityIdentifier("alarm.status")
                Text("The alarm opens your approved morning after you stop it. Unlock your phone if asked.").font(.footnote)
                Button("Save") {
                    let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                    Task { await service.save(.init(isEnabled: enabled, hour: components.hour ?? 7, minute: components.minute ?? 0)) }
                }.disabled(service.busy).accessibilityIdentifier("alarm.save")
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
        List {
            Section("Step timers") {
                Button("Allow time's up alerts") {
                    Task {
                        do {
                            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            alertStatus = allowed ? String(localized: "Alerts allowed") : String(localized: "Allow notifications for MORE in iPhone Settings.")
                        } catch { alertStatus = String(localized: "Notification permission couldn't be checked.") }
                    }
                }
                if !alertStatus.isEmpty { Text(alertStatus).font(.footnote) }
                Text("Your step timer keeps time when MORE is in the background. A notification can tell you when time is up.").font(.footnote)
            }
            Section("Shortcuts") {
                if ShortcutTemplate.visible().isEmpty {
                    Text("Shared shortcut templates will appear here when they're ready.").font(.footnote)
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
