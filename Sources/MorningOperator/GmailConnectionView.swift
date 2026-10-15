import MorningApple
import SwiftUI

/// Explicit Gmail reads during setup or a morning moment. Count-only access and
/// message-reading permission are separate choices, each usable from a fresh screen.
struct GmailConnectionView: View {
    var allowsReading = true
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
            if let error = controller.errorMessage {
                Text(error).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("gmail.error")
            }
            Text("This Gmail session, messages and local replies clear when you leave this screen or background MORE. Manage Google access in your Google Account.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
        }
        .foregroundStyle(MorningStyle.ink)
        .onChange(of: scenePhase) { _, phase in if phase == .background { controller.clearLocal() } }
        .onChange(of: allowsReading) { _, allowed in if !allowed { controller.clearLocal() } }
        .onDisappear { controller.clearLocal() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                controller.clearIfPrivacyChanged()
            }
        }
    }

    @ViewBuilder private var connectionOverview: some View {
        Text("Choose message reading or an unread count only.")
            .font(.footnote).foregroundStyle(MorningStyle.muted)
        if let configurationError = controller.configurationError {
            Text(configurationError).font(.footnote).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("gmail.configuration")
        } else {
            if let snapshot = controller.snapshot { countSummary(snapshot) }
            if !controller.hasMessageAccess {
                Text("To read messages, Google will ask for read-only access to message text.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            Button {
                controller.readMessages()
            } label: {
                if controller.hasMessageAccess { Label("Refresh unread messages", systemImage: "arrow.clockwise") }
                else { Label("Read messages", systemImage: "envelope.open") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canRead || controller.isBusy)
            .accessibilityIdentifier("gmail.readMessages")
            Button {
                if controller.hasSession { controller.refresh() } else { controller.connect() }
            } label: {
                if controller.hasSession { Text("Refresh unread count") }
                else { Text("Connect Gmail · count only") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(!canRead || controller.isBusy)
            .accessibilityIdentifier("gmail.connect")
            if controller.isBusy {
                ProgressView().accessibilityLabel("Reading Gmail")
            }
            if let snapshot = controller.unreadMessages { inboxMessages(snapshot) }
            if controller.hasSession {
                Button("Clear this Gmail session") { controller.clearLocal() }
                    .font(.footnote).frame(minHeight: 44)
                    .accessibilityIdentifier("gmail.clear")
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
                            Text(verbatim: message.subject.isEmpty ? String(localized: "No subject") : message.subject)
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
