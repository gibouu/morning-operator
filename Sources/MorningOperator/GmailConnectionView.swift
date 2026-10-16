import MorningApple
import MorningCore
import SwiftUI

/// One saved readonly Gmail connection, restored silently when this reader opens.
/// Only an explicit Connect tap may start Google consent.
struct GmailConnectionView: View {
    var allowsReading = true
    var body: some View {
        if GmailAttentionUITestFixture.isRequested {
            VStack(alignment: .leading, spacing: 16) {
                Text("SYNTHETIC — Gmail attention test. No account, network, or sending.")
                    .font(.caption).accessibilityIdentifier("gmail.attention.synthetic")
                GmailAttentionPreferencesEditor(allowsEditing: allowsReading)
            }
        } else { GmailConnectedReaderView(allowsReading: allowsReading) }
    }
}

private struct GmailConnectedReaderView: View {
    let allowsReading: Bool
    @State private var controller = GmailConnectionController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Gmail", systemImage: "envelope").font(.headline)
            if controller.isShowingMessage {
                GmailMessageView(controller: controller)
            } else {
                connectionOverview
            }
            if let error = controller.errorMessage, error != controller.configurationError {
                Text(error).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("gmail.error")
            }
            GmailAttentionPreferencesEditor(allowsEditing: canRead)
            Text("Your connection stays saved. Messages and local replies clear when you leave this screen or background MORE.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
            DisclosureGroup("Connection details") {
                Text("Disconnect removes this iPhone’s saved login. Manage Google access in your Google Account.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }.font(.caption).foregroundStyle(MorningStyle.muted)
        }
        .foregroundStyle(MorningStyle.ink)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.clearLocal() }
            else if phase == .active && allowsReading { controller.restoreIfNeeded() }
        }
        .onChange(of: allowsReading) { _, allowed in
            if !allowed { controller.clearLocal() }
            else if scenePhase == .active { controller.restoreIfNeeded() }
        }
        .onDisappear { controller.clearLocal() }
        .task {
            if canRead { controller.restoreIfNeeded() }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                controller.clearIfPrivacyChanged()
            }
        }
    }

    @ViewBuilder private var connectionOverview: some View {
        if controller.hasSavedConnection {
            Text("Connection saved securely on this iPhone.")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
        } else {
            Text("Connect once to read Gmail and prepare replies. Google asks for read-only access.")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
        }
        if let configurationError = controller.configurationError {
            Text(configurationError).font(.footnote).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("gmail.configuration")
        } else {
            if let snapshot = controller.snapshot { countSummary(snapshot) }
            if controller.hasSession || controller.hasSavedConnection || controller.canRetryConnection {
                Button { controller.refresh() } label: {
                    if controller.canRetryConnection { Label("Retry Gmail", systemImage: "arrow.clockwise") }
                    else { Label("Refresh Gmail", systemImage: "arrow.clockwise") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canRead || controller.isBusy)
                .accessibilityIdentifier("gmail.refresh")
            } else {
                Button { controller.connect() } label: { Text("Connect Gmail") }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!canRead || controller.isBusy)
                    .accessibilityIdentifier("gmail.connect")
            }
            if controller.isBusy {
                ProgressView().accessibilityLabel("Reading Gmail")
            }
            if let snapshot = controller.unreadMessages { inboxMessages(snapshot) }
            if !controller.hasSendAccess {
                Button {
                    controller.connect(access: .readAndSend)
                } label: {
                    Text(AppLanguage.isFrench ? "Autoriser l’envoi pendant mon matin" : "Enable sending during my morning")
                }
                .disabled(!canRead || controller.isBusy)
                .accessibilityIdentifier("gmail.enableSending")
                Text(AppLanguage.isFrench ? "Google demandera aussi le droit d’envoyer. MORE n’envoie un message préparé et relu qu’après votre demande explicite d’envoi." : "Google will also ask for sending access. MORE sends a prepared, reviewed message only after your explicit request to send it.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
            }
            if controller.hasSession || controller.hasSavedConnection || controller.canRetryConnection {
                Button("Disconnect Gmail") { controller.disconnect() }
                    .font(.footnote).frame(minHeight: 44).disabled(!canRead)
                    .accessibilityIdentifier("gmail.disconnect")
            }
        }
    }

    private var canRead: Bool { allowsReading && scenePhase == .active }

    private func countSummary(_ snapshot: GmailInboxSnapshot) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 4) {
                if snapshot.isCurrent(at: context.date) {
                    Text("Unread messages in Inbox: \(snapshot.unreadMessageCount)")
                        .accessibilityIdentifier("gmail.unread")
                    Text(snapshot.retrievedAt, style: .time).font(.caption).foregroundStyle(MorningStyle.muted)
                } else {
                    Text("This count needs a refresh.").font(.footnote).foregroundStyle(MorningStyle.muted)
                }
            }
        }
    }

    private func inboxMessages(_ snapshot: GmailUnreadMessagesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unread Inbox").font(.headline)
            if snapshot.messages.isEmpty && snapshot.failedMessageCount == 0 {
                Text("No unread messages in Inbox.").font(.subheadline)
            }
            ForEach(snapshot.messages) { message in
                CardButton { controller.openMessage(id: message.id) } content: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: message.sender).font(.caption).foregroundStyle(MorningStyle.muted)
                                .lineLimit(2)
                            Text(verbatim: message.subject.isEmpty ? AppLanguage.localized("No subject") : message.subject)
                                .font(.subheadline.weight(.medium)).lineLimit(2)
                            if let receivedAt = message.receivedAt {
                                Text(receivedAt, style: .date).font(.caption2).foregroundStyle(MorningStyle.muted)
                            }
                        }
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.right").font(.caption).accessibilityHidden(true)
                    }
                }
                .disabled(!canRead || controller.isBusy)
                .accessibilityIdentifier("gmail.message.open")
            }
            if snapshot.failedMessageCount > 0 {
                Text("\(snapshot.failedMessageCount) messages could not be loaded. Try refreshing.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("gmail.messages.partial")
            }
            if snapshot.hasMore {
                Text("Showing up to five unread messages.").font(.caption).foregroundStyle(MorningStyle.muted)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if !snapshot.isCurrent(at: context.date) {
                    Text("This list needs a refresh.").font(.caption).foregroundStyle(MorningStyle.muted)
                }
            }
        }.accessibilityIdentifier("gmail.messages")
    }
}

/// An ordinary local preference editor. Saving never reorders an active reply.
private struct GmailAttentionPreferencesEditor: View {
    let allowsEditing: Bool
    @State private var priorities = ""
    @State private var generation: UUID?
    @State private var loaded = false
    @State private var unreadable = false
    @State private var status = ""
    @Environment(\.scenePhase) private var scenePhase
    private var french: Bool { AppLanguage.isFrench }
    private let control = LocalDataControl(directory: LocalDataControl.defaultDirectory)
    private let preferences = GmailAttentionPreferencesStore()

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text(french ? "Précisez les sujets, demandes ou personnes à privilégier. Le modèle local propose trois mails parmi les cinq lus, avec une raison et un extrait. Cela n’autorise aucun envoi."
                    : "Describe topics, requests or people to prioritize. The local model proposes three of the five read messages, with a reason and an excerpt. This does not authorize sending.")
                    .font(.caption)
                TextField(french ? "Exemple : échéances de mes projets, nouvelles de mes proches" : "Example: project deadlines, news from family", text: $priorities, axis: .vertical)
                    .lineLimit(3...7).accessibilityIdentifier("gmail.attention.priorities")
                    .disabled(!loaded || unreadable || !allowsEditing)
                Text(french ? "400 caractères maximum. Sans modèle disponible, MORE présente les derniers messages consultés sans classement personnalisé. Ces préférences restent sur cet iPhone et seront utilisées à la prochaine lecture."
                    : "Up to 400 characters. Without the local model, MORE presents recently read messages without personalized ranking. These preferences stay on this iPhone and apply to the next reading.")
                    .font(.caption).foregroundStyle(MorningStyle.muted)
                Button(french ? "Enregistrer mes priorités" : "Save my priorities") { save(reset: false) }
                    .disabled(!loaded || unreadable || !allowsEditing || (try? GmailAttentionPreferences(priorities: priorities)) == nil)
                    .accessibilityIdentifier("gmail.attention.save")
                if unreadable {
                    Button(french ? "Effacer uniquement ces préférences illisibles" : "Reset only these unreadable preferences", role: .destructive) { save(reset: true) }
                        .disabled(!allowsEditing).accessibilityIdentifier("gmail.attention.reset")
                }
                if !status.isEmpty { Text(status).font(.caption).accessibilityIdentifier("gmail.attention.status") }
            }.padding(.top, 8)
        }
        label: { Text(french ? "Ce qui mérite votre attention" : "What deserves your attention").accessibilityIdentifier("gmail.attention.settings") }
        .task { load() }
        .onChange(of: allowsEditing) { _, allowed in if allowed { load() } else { clear() } }
        .onChange(of: scenePhase) { _, phase in if phase == .background { clear() } else if phase == .active { load() } }
        .onDisappear { clear() }
    }
    private func load() {
        guard allowsEditing, scenePhase == .active else { return }
        do {
            generation = try control.status().generation
            priorities = try preferences.load(generation: generation).priorities
            unreadable = false; loaded = true; status = ""
        } catch {
            priorities = ""; unreadable = true; loaded = true
            status = french ? "Ces préférences sont indisponibles et n’ont pas été remplacées. Réessayez plus tard ou effacez uniquement ces préférences."
                : "These preferences are unavailable and have not been replaced. Retry later or reset only these preferences."
        }
    }
    private func save(reset: Bool) {
        guard allowsEditing, scenePhase == .active else { return }
        do {
            let next = try GmailAttentionPreferences(priorities: reset ? "" : priorities)
            try preferences.save(next, generation: generation)
            priorities = next.priorities; unreadable = false; loaded = true
            status = french ? "Priorités enregistrées pour la prochaine lecture. Votre mail et sa relecture en cours restent inchangés."
                : "Priorities saved for the next reading. Your current message and reply review are unchanged."
        } catch {
            status = french ? "Les priorités n’ont pas pu être enregistrées. Les préférences précédentes restent conservées."
                : "Priorities could not be saved. Your previous preferences remain saved."
        }
    }
    private func clear() { priorities = ""; generation = nil; loaded = false; unreadable = false; status = "" }
}
