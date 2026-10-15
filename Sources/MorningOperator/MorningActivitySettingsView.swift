import SwiftUI

struct MorningActivitySettingsView: View {
    @Bindable var store: MorningStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    Toggle("Show on Lock Screen", isOn: Binding(
                        get: { store.showMorningOnLockScreen },
                        set: { store.setMorningOnLockScreen($0) }))
                    .disabled(!store.storageIsAvailable)
                    .accessibilityIdentifier("activity.enabled")
                } header: {
                    Text("Your morning, at a glance")
                } footer: {
                    Text("See your place in the morning on the Lock Screen and Dynamic Island. Anyone who can see your screen may see the category and progress.")
                }
                Section {
                    Label(store.morningActivityStatusText, systemImage: "sun.horizon")
                        .accessibilityIdentifier("activity.status")
                    #if DEBUG
                    if let namespace = store.morningActivityTestNamespace {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(MorningActivityDiagnostics.summary(namespace: namespace))
                                .font(.caption2)
                                .accessibilityIdentifier("activity.nativeDiagnostic")
                        }
                    }
                    #endif
                } footer: {
                    Text("Your messages, calendar details and personal step names stay inside MORE.")
                }
                Section {
                    Text("Tap the activity to return to your morning.")
                    Text("Timed app steps keep running outside MORE. Other steps pause until you return.")
                } footer: {
                    Text("This shows a morning you've chosen to start. It doesn't start recording or listen in the background.")
                }
            }
            .tint(MorningStyle.accent)
            .navigationTitle("Lock Screen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { store.synchronizeMorningActivity() }
        }
    }
}
