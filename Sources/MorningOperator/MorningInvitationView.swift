import SwiftUI
import MorningApple

struct MorningInvitationView: View {
    @Bindable var service: MorningInvitationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @ViewState<Date> private var selectedDate = Self.tomorrowMorning

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Invite me", selection: $selectedDate, in: Date.now...,
                               displayedComponents: [.date, .hourAndMinute])
                        .accessibilityIdentifier("invitation.date")
                    Text("One time · \(TimeZone.current.identifier)")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button {
                        Task { await service.schedule(at: selectedDate) }
                    } label: {
                        HStack {
                            Text("Set invitation")
                            Spacer()
                            if service.isBusy { ProgressView() }
                        }
                    }.disabled(service.isBusy || selectedDate <= .now)
                        .accessibilityIdentifier("invitation.schedule")
                } header: {
                    Text("A little nudge")
                } footer: {
                    Text("Tap the invitation to open MORE and begin your approved morning. This one-time invitation keeps the same instant if you travel to another time zone.")
                }

                Section {
                    Text(service.statusText).accessibilityIdentifier("invitation.status")
                    if let invitation = service.invitation, invitation.disposition == .enabled {
                        Text(scheduledTime(invitation.scheduledAt, zone: invitation.timeZoneIdentifier))
                        Text("Set in \(invitation.timeZoneIdentifier)").font(.footnote).foregroundStyle(.secondary)
                        Button("Cancel invitation", role: .destructive) {
                            Task { await service.cancel() }
                        }.disabled(service.isBusy).accessibilityIdentifier("invitation.cancel")
                    }
                    if let error = service.errorMessage {
                        Text(error).foregroundStyle(.secondary)
                            .accessibilityIdentifier("invitation.error")
                    }
                    if service.needsRecovery {
                        Button("Reset invitation", role: .destructive) {
                            Task { await service.cancel() }
                        }.disabled(service.isBusy).accessibilityIdentifier("invitation.reset")
                        Text("This resets only the invitation. Your routine and observations are kept.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Focus and your notification settings can quiet the invitation. It isn't an alarm and doesn't start screen recording.")
                }

                Section {
                    Button("Notification settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
            .navigationTitle("Your next morning").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                if let invitation = service.invitation, invitation.scheduledAt > .now {
                    selectedDate = invitation.scheduledAt
                }
                #if DEBUG
                let args = ProcessInfo.processInfo.arguments
                if args.contains("--ui-testing"), args.contains("--ui-testing-near-invitation") {
                    selectedDate = .now.addingTimeInterval(45)
                }
                #endif
                await service.reconcile()
            }
        }
        .tint(MorningStyle.accent)
        .presentationDragIndicator(.visible)
    }

    private static var tomorrowMorning: Date {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        return calendar.date(bySettingHour: 7, minute: 30, second: 0, of: tomorrow) ?? tomorrow
    }

    private func scheduledTime(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: zone) ?? .current
        return formatter.string(from: date)
    }
}
