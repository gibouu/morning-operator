import SwiftUI
import MorningApple
import MorningCore

/// Touch fallback for the same prepared native action used by hands-free speech.
struct NativeMomentReviewView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: MorningStore
    var initiallyExpanded = false
    @ViewState<String> private var request = ""
    @ViewState<String> private var title = ""
    @ViewState<Date> private var date = Date().addingTimeInterval(3_600)
    @ViewState<Bool> private var hasDate = false
    @ViewState<Int> private var duration = 30
    @ViewState<Bool> private var expanded = false
    @FocusState private var focusedInput: Input?
    private enum Input: Hashable { case request, title }
    private var native: NativeMomentConversation { store.nativeMoment }
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing-native-actions") {
                    Text("SYNTHETIC local fixture · no Apple data is changed")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("nativeMoment.synthetic")
                }
                #endif
                #if DEBUG
                if let proof = store.exactReminderUITestDiagnostic {
                    Text("SYNTHETIC reminder transport · no EventKit write")
                        .font(.raleway(.caption)).accessibilityIdentifier("nativeMoment.exactProof")
                        .accessibilityValue(proof)
                }
                #endif
                Text(french ? "Dites « rappelle-moi de… », « ajoute un événement… » ou « lis mes rappels ». Vous pouvez aussi préparer la demande ici." : "Say “remind me to…”, “add an event…” or “read my reminders”. You can also prepare the request here.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                TextField(french ? "Votre demande" : "Your request", text: $request, axis: .vertical)
                    .textFieldStyle(.roundedBorder).focused($focusedInput, equals: .request).accessibilityIdentifier("nativeMoment.request")
                Button(french ? "Préparer la demande" : "Prepare request") {
                    focusedInput = nil
                    let text = request; request = ""
                    store.performNativeMoment { _, _ in _ = await store.handleNativeMomentUtterance(text) }
                }.buttonStyle(SecondaryButtonStyle()).disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || native.phase == .writing)
                    .accessibilityIdentifier("nativeMoment.prepare")
                if !native.message.isEmpty {
                    Text(native.message).font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                        .accessibilityIdentifier("nativeMoment.status")
                }
                if native.phase == .completed {
                    Text(french ? "Votre matin est en pause. Dites reprends pour continuer." : "Your morning is paused. Say resume to continue.")
                        .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                }
                if native.draftKind != nil {
                        TextField(french ? "Titre" : "Title", text: Binding(get: { title }, set: { title = $0; stageEdits() }), axis: .vertical)
                            .textFieldStyle(.roundedBorder).focused($focusedInput, equals: .title).accessibilityIdentifier("nativeMoment.title")
                        Toggle(french ? "Date et heure" : "Date and time", isOn: Binding(get: { hasDate }, set: {
                            hasDate = $0
                            if hasDate { date = NativeMomentDateInput.editedMinute(date) }
                            stageEdits()
                        })).accessibilityIdentifier("nativeMoment.hasDate")
                        if hasDate {
                            DatePicker(french ? "Quand" : "When", selection: Binding(get: { date }, set: {
                                date = NativeMomentDateInput.editedMinute($0); stageEdits()
                            }), displayedComponents: [.date, .hourAndMinute]).accessibilityIdentifier("nativeMoment.date")
                        }
                        if native.draftKind == .calendar {
                            Stepper(french ? "Durée : \(duration) min" : "Duration: \(duration) min", value: Binding(get: { duration }, set: { duration = $0; stageEdits() }), in: 1...1_440)
                                .accessibilityIdentifier("nativeMoment.duration")
                        }
                        Button(french ? "Relire ces modifications" : "Review these changes") {
                            focusedInput = nil
                            let editedTitle = title, editedDate = hasDate ? date : nil, editedDuration = duration
                            store.performNativeMoment { native, context in await native.edit(title: editedTitle, date: editedDate, durationMinutes: editedDuration, context: context) }
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("nativeMoment.editReview")
                }
                if let action = native.action {
                    if native.phase == .reviewing {
                        Button(french ? "J’ai lu ces détails" : "I reviewed these details") { focusedInput = nil; native.acknowledgeScreenReview(); store.speech.stop() }
                            .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("nativeMoment.reviewed")
                    }
                    Button(action.isCompletion ? (french ? "Confirmer : marquer terminé" : "Confirm: mark complete") : (french ? "Confirmer l’ajout" : "Confirm addition")) {
                        focusedInput = nil
                        store.performNativeMoment { native, context in _ = await native.respond(action.isCompletion ? "mark complete" : "add it", context: context) }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!native.canConfirm || hasUnreviewedEdits(action))
                        .accessibilityIdentifier("nativeMoment.confirm")
                }
                if !native.observedReminders.isEmpty, native.action == nil, native.phase == .choosingReminder {
                    ForEach(Array(native.observedReminders.enumerated()), id: \.element.id) { index, item in
                        Button("\(index + 1). \(item.title)") {
                            store.performNativeMoment { native, context in await native.selectReminder(id: item.id, context: context) }
                        }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("nativeMoment.reminder.\(index)")
                    }
                }
                if native.context != nil {
                    Button(french ? "Fermer cette demande" : "Close this request") { store.clearNativeMoment() }
                        .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("nativeMoment.cancel")
                }
            }.padding(.top, 12)
        } label: {
            Label(french ? "Rappels et calendrier" : "Reminders and Calendar", systemImage: "calendar.badge.plus")
                .font(.raleway(.subheadline)).accessibilityIdentifier("nativeMoment.open")
        }.tint(MorningStyle.accent)
            .onChange(of: native.reviewID) { _, _ in loadDraft(); expanded = true }
            .onChange(of: native.phase) { _, phase in
                if phase == .idle { resetInputs() } else { expanded = true; loadDraft() }
            }
            .onChange(of: native.context) { _, context in if context == nil { resetInputs() } }
            .onChange(of: scenePhase) { _, phase in if phase != .active { resetInputs() } }
            .onChange(of: store.dataGeneration) { _, _ in resetInputs() }
            .onChange(of: store.currentStep?.id) { _, _ in resetInputs() }
            .onAppear { loadDraft(); expanded = initiallyExpanded || native.context != nil }
            .onDisappear { resetInputs() }
    }

    private func resetInputs() {
        request = ""; title = ""; date = Date().addingTimeInterval(3_600)
        hasDate = false; duration = 30; expanded = false; focusedInput = nil
    }
    private func loadDraft() {
        guard let selectedTitle = native.draftTitle else { return }
        title = selectedTitle; hasDate = native.draftDate != nil
        if let selected = native.draftDate { date = selected }
        duration = native.draftDurationMinutes
    }
    private func stageEdits() {
        native.stageEdit(title: title, date: hasDate ? date : nil, durationMinutes: duration)
    }
    private func hasUnreviewedEdits(_ action: NativeMomentAction) -> Bool {
        guard !action.isCompletion else { return false }
        return title != action.title || (hasDate ? date : nil) != action.date || (action.destination?.kind == .calendar && duration != action.durationMinutes)
    }
}
