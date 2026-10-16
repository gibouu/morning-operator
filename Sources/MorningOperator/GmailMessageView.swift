import MorningCore
import MorningApple
import SwiftUI

/// Message bodies render as plain text only. The reply is an editable local value;
/// no send, Gmail draft write or compose-permission path exists here.
struct GmailMessageView: View {
    @Bindable var controller: GmailConnectionController
    @State private var showsFullMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button { controller.closeMessage() } label: {
                Label("Back to Inbox", systemImage: "chevron.left").frame(minHeight: 44)
            }.buttonStyle(.plain).accessibilityIdentifier("gmail.message.close")
            if let message = controller.selectedMessage {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: message.subject.isEmpty ? AppLanguage.localized("No subject") : message.subject)
                        .font(.headline).textSelection(.enabled)
                    Text(verbatim: message.sender).font(.subheadline).foregroundStyle(MorningStyle.muted)
                        .textSelection(.enabled)
                    if let receivedAt = message.receivedAt {
                        Text(receivedAt, style: .date).font(.caption).foregroundStyle(MorningStyle.muted)
                    }
                }
                if message.bodyUnavailable {
                    Text("This message has no readable plain-text body here. You can write a reply below.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                } else {
                    Card {
                        Text(verbatim: message.plainTextBody).font(.body).textSelection(.enabled)
                            .lineLimit(showsFullMessage ? nil : 5)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("gmail.message.body")
                    }
                    Button {
                        showsFullMessage.toggle()
                    } label: {
                        if showsFullMessage { Text("Show less") }
                        else { Text("Read full message") }
                    }.buttonStyle(.plain).font(.footnote).frame(minHeight: 44)
                        .accessibilityIdentifier("gmail.message.expand")
                }
                if message.bodyWasTruncated {
                    Text("Only part of this message is available. You can write a reply below.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                        .accessibilityIdentifier("gmail.message.truncated")
                }
                replyComposer(message)
            } else if controller.isBusy {
                ProgressView("Reading message…").accessibilityIdentifier("gmail.message.loading")
            }
        }
        .onChange(of: controller.selectedMessageID) { _, _ in showsFullMessage = false }
    }

    private func replyComposer(_ message: GmailMessage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your reply").font(.headline)
            Text("Your reply, in a few words").font(.subheadline)
            TextField("Optional", text: Binding(get: { controller.replyGuidance }, set: { controller.editGuidance($0) }), axis: .vertical)
                .font(.body).lineLimit(2...4).padding(12)
                .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                .disabled(controller.isBusy)
                .accessibilityLabel("Your reply, in a few words")
                .accessibilityIdentifier("gmail.reply.guidance")
            if let reason = controller.replyUnavailabilityReason {
                Text(reason).font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            Button { controller.prepareReply() } label: {
                HStack(spacing: 8) {
                    if controller.isPreparingReply { ProgressView() }
                    Text("Prepare reply")
                }
            }.buttonStyle(SecondaryButtonStyle())
                .disabled(controller.isBusy || message.bodyUnavailable || message.bodyWasTruncated || controller.replyUnavailabilityReason != nil)
                .accessibilityIdentifier("gmail.reply.prepare")
            TextEditor(text: Binding(get: { controller.replyText }, set: { controller.editReply($0) }))
                .font(.body).frame(minHeight: 160).padding(8)
                .scrollContentBackground(.hidden)
                .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 10))
                .disabled(controller.isBusy)
                .accessibilityLabel("Editable reply")
                .accessibilityIdentifier("gmail.reply.editor")
            Button { controller.copyReply() } label: {
                Label("Copy reply", systemImage: "doc.on.doc")
            }.buttonStyle(SecondaryButtonStyle())
                .disabled(controller.isBusy || controller.replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("gmail.reply.copy")
            if let notice = controller.replyNotice {
                Text(notice).font(.footnote).foregroundStyle(MorningStyle.muted)
                    .accessibilityIdentifier("gmail.reply.notice")
            }
            Text("Review and edit before copying. Nothing is sent or saved to Gmail.")
                .font(.caption).foregroundStyle(MorningStyle.muted)
        }
    }
}
