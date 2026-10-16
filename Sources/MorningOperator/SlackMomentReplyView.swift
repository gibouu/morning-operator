import MorningApple
import MorningCore
import SwiftUI

/// The same source-bound conversation is used by speech and this touch fallback.
struct SlackMomentReplyView: View {
    @Bindable var store: MorningStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var intention = ""
    @FocusState private var focused: Bool
    private var reply: SlackThreadReplyConversation { store.slackReply }
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(french ? "Répondre dans Slack" : "Reply in Slack").font(MorningTheme.Typography.heading)
            if store.usesSyntheticSlack {
                Text("SYNTHETIC local fixture · no Slack message is posted")
                    .font(.raleway(.caption)).accessibilityIdentifier("slackMoment.synthetic")
            }
            if SlackSetupUITestFixture.integratedJourneyRequested {
                Text("SYNTHETIC — isolated transport and draft. No account, network or real post; one simulated dispatch loses its response.")
                    .font(.caption).accessibilityIdentifier("slackMoment.integratedSynthetic")
                    .accessibilityValue(integratedDiagnostic)
            }
            Text(french ? "Choisissez un message et dites ce que vous souhaitez répondre. MORE relit le compte, le canal, le message et la réponse avant votre instruction d’envoi."
                 : "Choose a message and say what you want to reply. MORE reviews the account, channel, message and reply before your send instruction.")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
            if reply.context == nil {
                let sources = store.slackReplySources
                ForEach(Array(sources.enumerated()), id: \.element.messageTS) { index, source in
                    Button { store.selectedSlackMessageTS = source.messageTS } label: {
                        HStack(alignment: .top) {
                            Image(systemName: store.selectedSlackMessageTS == source.messageTS ? "checkmark.circle.fill" : "circle")
                            Text("\(index + 1). \(source.text)").fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("slackMoment.message.\(index)")
                }
                if sources.isEmpty {
                    Text(french ? "La lecture est absente, périmée ou contient des messages non pris en charge. Actualisez-la pour retrouver les messages disponibles."
                         : "The reading is absent, expired or contains unsupported messages. Refresh it to find available messages.")
                        .font(.raleway(.subheadline)).accessibilityIdentifier("slackMoment.empty")
                }
                TextField(french ? "Ce que vous souhaitez répondre" : "What you want to reply", text: $intention, axis: .vertical)
                    .textFieldStyle(.roundedBorder).focused($focused).accessibilityIdentifier("slackMoment.intention")
                Button(french ? "Préparer la réponse" : "Prepare reply") {
                    focused = false
                    let selected = sources.first { $0.messageTS == store.selectedSlackMessageTS } ?? (sources.count == 1 ? sources.first : nil)
                    if let selected { store.prepareSlackReply(to: selected, intention: intention); intention = "" }
                }.buttonStyle(SecondaryButtonStyle())
                    .disabled(intention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        (sources.count != 1 && !sources.contains { $0.messageTS == store.selectedSlackMessageTS }))
                    .accessibilityIdentifier("slackMoment.prepare")
                Button(french ? "Actualiser les messages" : "Refresh messages") { focused = false; store.refreshSlackMessages() }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("slackMoment.refresh")
            }
            if let destination = reply.destination {
                Text("\(destination.teamName) · \(destination.userName) · #\(destination.channelName)")
                    .font(.raleway(.subheadline, .medium)).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("slackMoment.destination")
                if let source = reply.source { Text(source.text).font(.raleway(.subheadline)).textSelection(.enabled).accessibilityIdentifier("slackMoment.source") }
                if ![.sending, .uncertain, .completed].contains(reply.phase) {
                    TextField(french ? "Réponse proposée" : "Proposed reply", text: Binding(get: { reply.body }, set: {
                        store.speech.stop(); reply.edit(body: $0)
                    }), axis: .vertical).textFieldStyle(.roundedBorder).focused($focused).accessibilityIdentifier("slackMoment.body")
                    Button(french ? "Relire la réponse" : "Review reply") {
                        focused = false; store.performSlackReply { reply, _ in await reply.review() }
                    }.buttonStyle(SecondaryButtonStyle()).disabled(reply.body.isEmpty).accessibilityIdentifier("slackMoment.review")
                    if reply.phase == .reviewing {
                        Button(french ? "J’ai lu tous ces détails" : "I reviewed all these details") {
                            focused = false; store.speech.stop(); reply.acknowledgeScreenReview()
                        }.buttonStyle(SecondaryButtonStyle()).disabled(reply.body.isEmpty).accessibilityIdentifier("slackMoment.reviewed")
                    }
                    Button(french ? "Envoyer cette réponse" : "Send this reply") {
                        focused = false; store.performSlackReply { reply, context in _ = await reply.respond("send", context: context) }
                    }.buttonStyle(PrimaryButtonStyle()).disabled(!reply.canConfirm).accessibilityIdentifier("slackMoment.send")
                }
            }
            if !reply.message.isEmpty {
                Text(reply.message).font(.raleway(.subheadline)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("slackMoment.status")
            }
            if reply.phase == .preparing || reply.phase == .sending { ProgressView() }
            if reply.context != nil {
                Text(french ? "Votre matin est en pause. Dites reprends après avoir fermé cette demande."
                     : "Your morning is paused. Say resume after closing this request.")
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                Button(french ? "Fermer cette demande" : "Close this request") { focused = false; store.clearSlackReply() }
                    .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("slackMoment.cancel")
            }
        }.accessibilityElement(children: .contain)
            .accessibilityIdentifier("slackMoment.panel")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focused {
                        Spacer()
                        Button(french ? "Terminé" : "Done") { focused = false }
                            .accessibilityIdentifier("slackMoment.keyboardDone")
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { intention = ""; focused = false } }
            .onChange(of: store.dataGeneration) { _, _ in intention = ""; focused = false }
            .onChange(of: store.currentSlackContext) { _, _ in intention = ""; focused = false }
            .onDisappear { intention = ""; focused = false }
    }

    private var integratedDiagnostic: String {
        let counts = store.session.flatMap { store.slackActionCounts(for: $0) }
        return SlackSetupUITestFixture.integratedDiagnostic + "; confirmed replies: " +
            (counts.map { String($0.confirmed) } ?? "unknown") + "; unconfirmed replies: " +
            (counts.map { String($0.unconfirmed) } ?? "unknown")
    }
}
