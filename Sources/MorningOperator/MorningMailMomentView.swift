import SwiftUI
import MorningCore
import MorningApple

/// Ordinary foreground mail controls, including a literal editable self-note
/// when the optional local model is unavailable. Draft text stays in memory.
struct MorningMailMomentView: View {
    @Bindable var store: MorningStore
    @State private var replyIntention = ""
    @State private var replyCorrection = ""
    @FocusState private var replyInputFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    private var french: Bool { AppLanguage.isFrench }

    var body: some View {
        let mail = store.mailMorning
        VStack(alignment: .leading, spacing: 12) {
            if GmailAttentionUITestFixture.isRequested {
                if GmailAttentionUITestFixture.isPrivateReplyRequested {
                    Text(french ? "SYNTHETIC — Mails, réponses et envois entièrement simulés. Aucun compte ni réseau réel."
                                : "SYNTHETIC — Mail, replies and sends are entirely simulated. No real account or network.")
                        .font(.caption).accessibilityIdentifier("mail.attention.synthetic")
                    if let proof = GmailAttentionUITestFixture.privateReplyDiagnostic(context: mail.context) {
                        Text(french ? "Transport Gmail simulé" : "Simulated Gmail transport")
                            .font(.caption).accessibilityIdentifier("mail.reply.syntheticReceipt").accessibilityValue(proof)
                    }
                    if mail.lastSendOutcome == .sent {
                        Text(french ? "Envoi simulé confirmé. Aucun vrai mail envoyé." : "Simulated send confirmed. No real email was sent.")
                            .font(.caption).accessibilityIdentifier("mail.reply.simulatedSent")
                    }
                } else {
                    Text("SYNTHETIC — Gmail attention test. No account, network, or sending.")
                        .font(.caption).accessibilityIdentifier("mail.attention.synthetic")
                        .accessibilityValue("HTTP list reads: \(GmailAttentionUITestFixture.inboxReadCount); body reads: \(GmailAttentionUITestFixture.bodyReadCount)")
                }
            }
            if let selection = mail.attentionSelection, !mail.isComposingSelfMessage {
                Text(french ? "Vos mails à examiner" : "Your messages to review").font(.headline)
                Text(selection.explanation(french: french)).font(.caption)
                    .accessibilityIdentifier("mail.attention.explanation")
                if let priorities = selection.prioritiesUsed, !priorities.isEmpty {
                    Text((french ? "Priorités utilisées : " : "Priorities used: ") + priorities).font(.caption)
                        .accessibilityIdentifier("mail.attention.prioritiesUsed")
                }
                ForEach(mail.messageChoices) { choice in
                    VStack(alignment: .leading, spacing: 5) {
                        Text("\(choice.number). \(choice.sender)").font(.subheadline.weight(.medium))
                        Text(verbatim: choice.subject.isEmpty ? (french ? "Sans objet" : "No subject") : choice.subject)
                        if let date = choice.receivedAt { Text(date, format: .dateTime.day().month().hour().minute()).font(.caption) }
                        if let proposed = choice.proposed {
                            Text(verbatim: proposed.summary)
                            Text((selection.mode == .localProposal ? (french ? "Proposition locale : " : "Local proposal: ") : "") + proposed.reason).font(.caption)
                            if let quote = proposed.sourceQuote { Text((french ? "Extrait cité : « " : "Quoted excerpt: “") + quote + (french ? " »" : "”")).font(.caption) }
                            if proposed.sourceWasAbbreviated { Text(french ? "La proposition utilise un contenu abrégé." : "This proposal uses abbreviated source text.").font(.caption) }
                        } else { Text(french ? "Autre mail consulté, hors des trois propositions." : "Another read message, outside the three proposals.").font(.caption) }
                        Button(mail.selectedMessageID == choice.id ? (french ? "Mail choisi" : "Selected message") : (french ? "Choisir ce mail" : "Choose this message")) {
                            store.chooseReadMail(id: choice.id)
                        }.disabled(!mail.canChooseMessage)
                            .accessibilityIdentifier("mail.attention.choose.\(choice.number)")
                    }.padding(.vertical, 6)
                }
                Text(french ? "Choisir un autre mail efface l’ancien brouillon. Son destinataire vient du message réellement lu ; la préparation et l’envoi restent des demandes distinctes."
                    : "Choosing another message clears the previous draft. Its recipient comes from the read message; preparing and sending remain separate requests.").font(.caption)
            }
            if !mail.isComposingSelfMessage {
                if mail.state == .askingToReply {
                    Button(french ? "Répondre à ce mail" : "Reply to this message") { store.beginMailReply() }
                        .accessibilityIdentifier("mail.reply.begin")
                }
                if mail.state == .askingForIntention {
                    TextField(french ? "Votre intention de réponse" : "What you want to reply", text: $replyIntention, axis: .vertical)
                        .lineLimit(2...5).focused($replyInputFocused).accessibilityIdentifier("mail.reply.intention")
                    Button(french ? "Préparer la réponse" : "Prepare reply") {
                        let guidance = replyIntention
                        replyIntention = ""; replyInputFocused = false
                        store.prepareMailReply(guidance: guidance, revising: false)
                    }.disabled(replyIntention.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("mail.reply.prepare")
                }
                if mail.state == .reviewingReply {
                    if let recipient = mail.recipient {
                        Text((french ? "À : " : "To: ") + recipient).textSelection(.enabled)
                            .accessibilityIdentifier("mail.reply.recipient")
                    }
                    Text(verbatim: mail.draftText).textSelection(.enabled).accessibilityIdentifier("mail.reply.body")
                    TextField(french ? "Votre correction" : "Your correction", text: $replyCorrection, axis: .vertical)
                        .lineLimit(2...5).focused($replyInputFocused).accessibilityIdentifier("mail.reply.correction")
                    Button(french ? "Corriger la réponse" : "Revise reply") {
                        let guidance = replyCorrection
                        replyCorrection = ""; replyInputFocused = false
                        store.prepareMailReply(guidance: guidance, revising: true)
                    }.disabled(replyCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("mail.reply.revise")
                    Button(mail.replyWasReviewedOnScreen ? (french ? "Réponse relue" : "Reply reviewed")
                                                       : (french ? "J’ai relu le destinataire et la réponse" : "I reviewed the recipient and reply")) {
                        replyInputFocused = false; store.reviewMailReply()
                    }.disabled(!replyCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("mail.reply.reviewed")
                    Button(french ? "Envoyer cette réponse" : "Send this reply") { store.sendReviewedMailReply() }
                        .disabled(!mail.canSendReply || !replyCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("mail.reply.send")
                    Text(french ? "La relecture n’envoie rien. Une correction exige une nouvelle relecture. L’envoi reste une demande distincte."
                                : "Review sends nothing. A correction needs a new review. Sending is a separate request.").font(.caption)
                }
            }
            if mail.canComposeSelfMessage, !mail.isComposingSelfMessage {
                Button(french ? "Note à moi-même" : "Note to myself") { store.beginSelfMail() }
                    .accessibilityIdentifier("mail.composeSelf")
            }
            if mail.isComposingSelfMessage {
                if let recipient = mail.recipient {
                    Text((french ? "À vous-même : " : "To yourself: ") + recipient)
                        .textSelection(.enabled).accessibilityIdentifier("mail.selfRecipient")
                }
                TextField(french ? "Objet" : "Subject", text: Binding(
                    get: { mail.selfMessageSubject },
                    set: { store.editSelfMail(subject: $0, body: mail.draftText) }))
                    .accessibilityIdentifier("mail.selfSubject")
                    .disabled(mail.lastSendOutcome != nil || mail.state != .reviewingSelfMessage)
                Text(french ? "Texte du message" : "Message body").font(.caption)
                TextEditor(text: Binding(get: { mail.draftText },
                    set: { store.editSelfMail(subject: mail.selfMessageSubject, body: $0) }))
                    .frame(minHeight: 120, maxHeight: 220)
                    .accessibilityIdentifier("mail.selfBody")
                    .disabled(mail.lastSendOutcome != nil || mail.state != .reviewingSelfMessage)
                Button(french ? "Relire ce brouillon" : "Review this draft") { store.reviewSelfMail() }
                    .disabled(mail.selfMessageSubject.isEmpty || mail.draftText.isEmpty || mail.lastSendOutcome != nil)
                    .accessibilityIdentifier("mail.selfReview")
                Button(french ? "Envoyer ce mail" : "Send this email") { store.sendReviewedSelfMail() }
                    .disabled(!mail.canSendSelfMessage)
                    .accessibilityIdentifier("mail.selfSend")
                Text(french ? "Chaque modification demande une nouvelle relecture. Le destinataire vient du compte Gmail connecté."
                            : "Each edit needs a new review. The recipient comes from the connected Gmail account.")
                    .font(.caption)
            }
            if mail.isAwaitingResponse {
                Button(french ? "Continuer mon matin" : "Continue my morning") { store.continueMailMorning() }
                    .accessibilityIdentifier("mail.continue")
            }
        }
        .disabled([.preparing, .preparingReply, .sending].contains(mail.state))
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .onChange(of: mail.context) { _, _ in clearReplyInputs() }
        .onChange(of: mail.selectedMessageID) { _, _ in clearReplyInputs() }
        .onChange(of: store.dataGeneration) { _, _ in clearReplyInputs() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { clearReplyInputs() } }
        .onDisappear { clearReplyInputs() }
    }

    private func clearReplyInputs() { replyIntention = ""; replyCorrection = ""; replyInputFocused = false }
}
