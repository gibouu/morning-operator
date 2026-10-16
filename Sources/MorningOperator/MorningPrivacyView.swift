import SwiftUI
import MorningCore

/// A secondary native screen; privacy controls never compete with the morning.
struct MorningPrivacyView: View {
    @Bindable var store: MorningStore
    @ViewState<Bool> private var confirmingRemoval = false
    @ViewState<Bool> private var removalApproved = false

    private static let removalAnchor = "privacy.removalSection"

    var body: some View {
      ScrollViewReader { proxy in
        MorningList {
            // Pending cleanup is the only action available. Keep its progress or
            // retry message at the top even when hiding the inventory changes the
            // list's height and scroll position.
            if store.privacyBlocksWork { removalSection }
            Section {
                Text("Your mornings stay close.").font(MorningTheme.Typography.title)
                Text("MORE keeps its learning on this device. You choose when to connect Apple apps and what to keep.")
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            }
            Section("Saved in MORE") {
                if store.privacyInventoryIsReadable {
                    LabeledContent("Current routine", value: store.routine == nil ? String(localized: "None", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "1")
                    LabeledContent("Previous routine", value: store.previousRoutine == nil ? String(localized: "None", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "1")
                    LabeledContent("Saved mornings", value: String(store.history.runs.count))
                    countRow(String(localized: "Observations", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: String(store.observationArchive.entries.count), identifier: "privacy.observations")
                    countRow(String(localized: "Saved thoughts & ideas", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: String(store.captures.count), identifier: "privacy.captures")
                    countRow(String(localized: "Saved choices", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), value: store.routinePreferencesIssue == nil ? String(store.routinePreferences.entries.count + (store.routinePreferences.order == nil ? 0 : 1)) : String(localized: "Unavailable", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), identifier: "privacy.choices")
                } else {
                    Text(store.privacyBlocksWork ? String(localized: "Saved data is unavailable while removal needs attention.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Saved data couldn’t be read. You can still choose to remove it.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                }
                Text("This also includes observation text and corrections, retained quotations, suggestions, recording recovery copies, app activity, invitation settings, your chosen calendars and weather city, and local Apple-app save receipts.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
            }
            Section {
                Toggle("Save app activity from Shortcuts", isOn: Binding(
                    get: { store.activityLoggingAllowed },
                    set: { store.setActivityLoggingAllowed($0) }))
                    .disabled(store.privacyBlocksWork)
                    .accessibilityIdentifier("privacy.activityLogging")
            } header: {
                Text("App activity")
            } footer: {
                Text("Only Shortcuts you configure can log app names and entry/exit times. This doesn't record taps or read messages. Removing local data turns this off until you enable it again.")
            }
            Section("Your day") {
                Text("Calendar events and prepared recaps stay in memory. MORE saves only the calendars you select, your chosen weather city and temperature unit.")
                Text("City searches go to Apple Maps. Weather requests send the selected city’s coordinates to Apple Weather. Screen content and learning aren't sent with these requests.")
            }.font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            Section("Connected accounts") {
                Text("Requests to connected accounts and their results pass through our connection service and Composio. Screen recordings and local learning stay on this iPhone.")
                Text("Adding an account action to your routine saves its details. Forgetting local data removes access from this iPhone; service permissions and server receipts are managed separately. To disconnect an account, open its page in Apps & accounts.")
            }.font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            Section("Outside MORE") {
                Text("Originals in Photos or Files, exported copies, and items already saved in Calendar or Reminders stay where they are.")
                Text("Apple permissions, installed voices, Shortcuts and device backups are managed separately. Removing local data doesn't change them or erase copies outside this app.")
            }.font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            #if DEBUG
            if store.privacyTestAnalysisWaiting {
                Section("Synthetic test only") {
                    Button("Release synthetic analysis") { store.releasePrivacyTestAnalysis() }
                        .accessibilityIdentifier("privacy.releaseTestAnalysis")
                }
            }
            #endif
            if !store.privacyBlocksWork { removalSection }
        }
        .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
        // The list keeps its position when the section is added above it, and
        // Forget sits at the bottom: bring the progress or retry message into view.
        .onChange(of: store.privacyBlocksWork) { _, blocked in
            guard blocked else { return }
            Task { @MainActor in proxy.scrollTo(Self.removalAnchor, anchor: .top) }
        }
      }
        .navigationTitle("Privacy").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(store.privacyBlocksWork)
        .interactiveDismissDisabled(store.privacyBlocksWork)
        .sheet(isPresented: $confirmingRemoval, onDismiss: {
            // Start only after the confirmation's native presentation has closed.
            // Fast success/failure must not strand an alert over changing state.
            guard removalApproved else { return }
            removalApproved = false
            Task { await store.forgetLocalData() }
        }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("A fresh start.").font(MorningTheme.Typography.title)
                        Text("Remove routines, observations, thoughts, history, saved choices, app activity and recording copies from MORE on this device.")
                        Text("Original files, exported copies and items in Apple apps stay where they are. This can't be undone.")
                            .foregroundStyle(MorningStyle.muted)
                    }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(MorningStyle.background)
                .navigationTitle("Forget local data?").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { removalApproved = false; confirmingRemoval = false }
                            .accessibilityIdentifier("privacy.cancelForget")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Button("Forget local data", role: .destructive) {
                        removalApproved = true
                        confirmingRemoval = false
                    }
                    .buttonStyle(DestructiveButtonStyle()).controlSize(.large)
                    .accessibilityIdentifier("privacy.confirmForget")
                    .padding(20).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
    }

    private var removalSection: some View {
        Section {
            Group {
                if store.privacyIsForgetting {
                    ProgressView("Removing local data…")
                        .accessibilityIdentifier("privacy.removing")
                } else {
                    Button(store.privacyHasInterruptedRemoval ? String(localized: "Retry removing local data", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : String(localized: "Forget MORE’s local data", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), role: .destructive) {
                        confirmingRemoval = true
                    }.accessibilityIdentifier("privacy.forget")
                }
            }.id(Self.removalAnchor)
            if let status = store.privacyStatus {
                Text(status).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("privacy.status")
            }
        } footer: {
            Text("Removes the saved routine and its learning, stops MORE’s current work and cancels its morning invitation. You can start fresh afterward.")
        }
    }

    private func countRow(_ title: String, value: String, identifier: String) -> some View {
        LabeledContent(title, value: value)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title).accessibilityValue(value)
            .accessibilityIdentifier(identifier)
    }

}
