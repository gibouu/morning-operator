import MorningApple
import SwiftUI

/// The same API reader is available during setup and a Gmail website moment.
/// The timestamp describes this read, not a continuously monitored mailbox.
struct GmailConnectionView: View {
    var allowsReading = true
    @State private var controller = GmailConnectionController()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gmail", systemImage: "envelope")
                .font(.headline)
            Text(text("Read the number of unread messages in your Gmail inbox. Google asks for read-only metadata access; MORE does not read message bodies.",
                      "Consultez le nombre de messages non lus dans votre boîte Gmail. Google demande l’accès aux métadonnées en lecture seule ; MORE ne lit pas le contenu des messages."))
                .font(.footnote).foregroundStyle(.secondary)
            if let configurationError = controller.configurationError {
                Text(configurationError).font(.footnote).foregroundStyle(.secondary)
                    .accessibilityIdentifier("gmail.configuration")
            } else {
                if let snapshot = controller.snapshot {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if snapshot.isCurrent(at: context.date) {
                            Text(text("Unread messages in Inbox: \(snapshot.unreadMessageCount)",
                                      "Messages non lus dans la boîte de réception : \(snapshot.unreadMessageCount)"))
                                .accessibilityIdentifier("gmail.unread")
                            Text(snapshot.retrievedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(text("This count needs a refresh.", "Ce nombre doit être actualisé."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                if let error = controller.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("gmail.error")
                }
                Button {
                    if controller.hasSession { controller.refresh() } else { controller.connect() }
                } label: {
                    if controller.isBusy { ProgressView() }
                    else { Text(controller.hasSession ? text("Refresh Gmail", "Actualiser Gmail") : text("Connect Gmail", "Connecter Gmail")) }
                }.buttonStyle(.bordered).disabled(!allowsReading || controller.isBusy || scenePhase != .active)
                    .accessibilityIdentifier("gmail.connect")
                if controller.hasSession {
                    Button(text("Clear this Gmail session", "Effacer cette session Gmail")) { controller.clearLocal() }
                        .font(.footnote).accessibilityIdentifier("gmail.clear")
                }
            }
            Text(text("This session and its count clear when you leave this screen or background MORE. Manage the Google account grant in your Google Account.",
                      "La session et son résultat sont effacés en quittant cet écran ou en passant MORE en arrière-plan. Gérez l’autorisation Google dans votre compte Google."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { controller.clearLocal() } }
        .onChange(of: allowsReading) { _, allowed in if !allowed { controller.clearLocal() } }
        .onDisappear { controller.clearLocal() }
    }

    private func text(_ english: String, _ french: String) -> String {
        locale.language.languageCode?.identifier == "fr" ? french : english
    }
}
