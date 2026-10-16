import Foundation
import MorningCore
import Observation

public enum GmailMorningState: String, Sendable, Equatable {
    case idle, preparing, choosingMailAction, askingToReply, askingForIntention, preparingReply, reviewingReply, reviewingSelfMessage, sending, uncertain, completed, unavailable
}

public enum GmailMorningReadOutcome: Sendable, Equatable { case unavailable, read }

public struct GmailMorningMessageChoice: Sendable, Identifiable {
    public let id: String
    public let number: Int
    public let sender: String
    public let subject: String
    public let receivedAt: Date?
    public let proposed: GmailAttentionItem?
}

/// Mail remains in memory. The engine binds every reply to an observed sender;
/// model output proposes observed IDs and reply text; only source headers bind
/// recipients, and attention proposals never authorize sending.
@MainActor @Observable
public final class GmailMorningConversation {
    public private(set) var state: GmailMorningState = .idle
    public private(set) var message = ""
    public private(set) var summary = ""
    public private(set) var attentionSelection: GmailAttentionSelection?
    public var messageChoices: [GmailMorningMessageChoice] {
        messages.enumerated().map { index, mail in
            .init(id: mail.id, number: index + 1, sender: mail.sender, subject: mail.subject, receivedAt: mail.receivedAt,
                  proposed: attentionSelection?.items.first { $0.id == mail.id })
        }
    }
    public var selectedMessageID: String? { messages.indices.contains(selectedIndex) ? messages[selectedIndex].id : nil }
    public var canChooseMessage: Bool {
        !isComposingSelfMessage && lastSendOutcome == nil && [.askingToReply, .askingForIntention, .reviewingReply].contains(state)
    }
    public private(set) var draftText = ""
    public private(set) var lastSendOutcome: GmailSendOutcome?
    public private(set) var readOutcome: GmailMorningReadOutcome = .unavailable
    public private(set) var recipient: String?
    public private(set) var isComposingSelfMessage = false
    public private(set) var selfMessageSubject = ""
    public var canComposeSelfMessage: Bool {
        session?.canReadMessages == true && session?.canSendMessages == true && context != nil &&
            ![.preparing, .preparingReply, .sending, .uncertain, .completed].contains(state) && lastSendOutcome == nil
    }
    public var canSendSelfMessage: Bool { isComposingSelfMessage && state == .reviewingSelfMessage && selfMessageDraft != nil && !sendReviewRevoked }
    public private(set) var context: MorningExecutionID?
    public var isCompleted: Bool { state == .completed }
    public var hasUnfinishedIntention: Bool {
        lastSendOutcome == nil && (isComposingSelfMessage || !draftText.isEmpty || !pendingIntention.isEmpty ||
            [.askingForIntention, .preparingReply].contains(state))
    }
    public var completedExecutionOutcome: RoutineExecutionRecord.Outcome? {
        guard isCompleted else { return nil }
        switch lastSendOutcome {
        case .uncertain, .draftMismatch: return .uncertain
        case .notSent: return .unavailable
        case .sent: return .completed
        case nil: return readOutcome == .read ? .completed : .unavailable
        }
    }
    /// Provider effects outlive narration and navigation. The store saves this
    /// before clearing a dialogue; an ordinary pause keeps its running outcome.
    public var interruptedExecutionOutcome: RoutineExecutionRecord.Outcome? {
        switch lastSendOutcome {
        case .sent: return .completed
        case .notSent: return .unavailable
        case .uncertain, .draftMismatch: return .uncertain
        case nil: return state == .unavailable && readOutcome == .unavailable ? .unavailable : nil
        }
    }
    public var isAwaitingResponse: Bool { [.choosingMailAction, .askingToReply, .askingForIntention, .reviewingReply, .reviewingSelfMessage, .uncertain, .unavailable].contains(state) }
    private let service: GmailConnectionService
    private let drafts: GmailReplyDraftService
    private let selfDrafts: GmailSelfMessageDraftService
    private let attention: GmailAttentionService
    private var selfMessageDraft: GmailPreparedSelfMessage?
    private let speak: @MainActor (String) async throws -> Void
    private let answer: @MainActor (String, String) async throws -> String
    private let privacy: LocalDataControl
    private var session: GmailAccessSession?
    private var messages: [GmailMessage] = []
    private var selectedIndex = 0
    private var inboxNarration: (readCount: Int, hasMore: Bool, failedCount: Int)?
    private var pendingIntention = ""
    private var generation: UUID?
    private var attempt = UUID()
    private var questionID: UUID?
    private var sendReviewRevoked = false

    public init(service: GmailConnectionService = GmailConnectionService(),
                drafts: GmailReplyDraftService = GmailReplyDraftService(),
                selfDrafts: GmailSelfMessageDraftService = GmailSelfMessageDraftService(),
                attention: GmailAttentionService = GmailAttentionService.recentOnly(),
                privacy: LocalDataControl = LocalDataControl(directory: LocalDataControl.defaultDirectory),
                answer: @escaping @MainActor (String, String) async throws -> String = { request, context in
                    try await MorningVoiceConversation().answer(request, context: context)
                },
                speak: @escaping @MainActor (String) async throws -> Void) {
        self.service = service; self.drafts = drafts; self.selfDrafts = selfDrafts; self.attention = attention
        self.privacy = privacy; self.speak = speak; self.answer = answer
    }

    public func begin(context: MorningExecutionID, generation: UUID?) async {
        clear()
        self.context = context; self.generation = generation
        let token = attempt
        state = .preparing
        do {
            try requireCurrent(token)
            guard let access = try await service.restoreConnection(generation: generation) else {
                try await unavailable(String(localized: "Connect Gmail in settings before your next morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
            }
            try requireCurrent(token)
            session = access
            let inbox = try await service.unreadInboxMessages(session: access)
            try requireCurrent(token)
            guard !inbox.messages.isEmpty else {
                if inbox.failedMessageCount > 0 {
                    try await unavailable(String(localized: "Some emails could not be read. I cannot conclude that your inbox is empty.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                } else {
                    readOutcome = .read
                    state = access.canSendMessages ? .choosingMailAction : .completed
                    try await say(access.canSendMessages
                        ? String(localized: "There are no unread emails in your inbox. You can prepare a note to yourself or continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
                        : String(localized: "There are no unread emails in your inbox. I’ll continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                }
                return
            }
            var fetched: [GmailMessage] = []
            var failures = inbox.failedMessageCount
            for item in inbox.messages {
                do {
                    let mail = try await service.message(id: item.id, session: access)
                    try requireCurrent(token)
                    fetched.append(mail)
                } catch {
                    try requireCurrent(token)
                    if let known = error as? GmailConnectionError,
                       [.sessionExpired, .permissionDenied, .connectionChanged].contains(known) { throw known }
                    failures += 1
                }
            }
            try requireCurrent(token)
            guard !fetched.isEmpty else {
                try await unavailable(String(localized: "Your emails could not be read. You can skip this moment or try again later.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
            }
            readOutcome = .read
            let french = AppLanguage.isFrench
            let selection: GmailAttentionSelection
            do {
                let preferences = try GmailAttentionPreferencesStore(directory: privacy.directory).load(generation: generation)
                selection = try await attention.select(messages: fetched, preferences: preferences, french: french)
            } catch {
                try requireCurrent(token)
                if error is CancellationError { throw error }
                selection = attention.recentSelection(fetched, reason: .preferencesUnavailable, french: french)
            }
            // Both the account and the pinned conversation are checked after local
            // analysis. A late ranking cannot revive mail after Pause/Next/Forget.
            try requireCurrent(token)
            let selectedIDs = selection.items.map(\.id)
            guard Set(selectedIDs).count == selectedIDs.count,
                  selectedIDs.allSatisfy({ id in fetched.contains { $0.id == id } }) else { throw GmailAttentionError.invalidProposal }
            messages = selectedIDs.compactMap { id in fetched.first { $0.id == id } } + fetched.filter { !selectedIDs.contains($0.id) }
            attentionSelection = selection
            inboxNarration = (fetched.count, inbox.hasMore, failures)
            summary = inboxSummary()
            selectedIndex = 0; recipient = messages[0].replyAddress
            state = .askingToReply
            try await say(summary + (french ? " Voulez-vous répondre au premier ? Vous pouvez aussi choisir un numéro parmi les mails lus, préparer une note à vous-même ou continuer votre matin."
                : " Would you like to reply to the first? You can also choose a number among the read messages, prepare a note to yourself, or continue your morning."), token: token)
        } catch { await fail(error, token: token) }
    }

    /// Select only a read immutable source; switching mail revokes any old reply.
    public func chooseMessage(id: String, context: MorningExecutionID) async {
        guard self.context == context, canChooseMessage, let index = messages.firstIndex(where: { $0.id == id }) else { return }
        await respond(String(index + 1), context: context)
    }

    private func inboxSummary() -> String {
        guard let facts = inboxNarration, let selection = attentionSelection else { return "" }
        let french = AppLanguage.isFrench
        let chosen = messages.prefix(3).enumerated().map { index, mail in
            let item = selection.items[index]
            let reason = selection.mode == .localProposal
                ? (french ? "Proposition locale : " : "Local proposal: ") + item.reason : item.reason
            let abbreviated = item.sourceWasAbbreviated ? (french ? " Source abrégée." : " Source abbreviated.") : ""
            return "\(index + 1). \(mail.sender.prefix(100)). \(mail.subject.isEmpty ? (french ? "Sans objet" : "No subject") : String(mail.subject.prefix(180)))). \(item.summary) \(reason)\(abbreviated)"
        }.joined(separator: " ")
        var result = (french ? "J’ai consulté \(facts.readCount) mails non lus. " : "I read \(facts.readCount) unread messages. ")
            + selection.explanation(french: french) + " " + chosen
        if facts.hasMore { result += french ? " D’autres mails non lus n’ont pas été consultés." : " Other unread messages were not read." }
        if facts.failedCount > 0 { result += french ? " \(facts.failedCount) messages n’ont pas pu être lus." : " \(facts.failedCount) messages could not be read." }
        return result
    }

    /// Refresh presentation only. Draft bytes, recipient bindings and send journals stay intact.
    public func appLanguageDidChange() {
        questionID = nil
        sendReviewRevoked = true
        summary = inboxSummary()
        switch state {
        case .idle: message = ""
        case .askingToReply where selectedIndex != 0 && messages.indices.contains(selectedIndex):
            message = String(localized: "\(messages[selectedIndex].sender). \(messages[selectedIndex].subject). Would you like to reply?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .askingToReply:
            message = summary + String(localized: " Would you like to reply to the first one? You can also choose a number, prepare a note to yourself, or continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .choosingMailAction:
            message = String(localized: "There are no unread emails in your inbox. You can prepare a note to yourself or continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .askingForIntention:
            message = String(localized: "What would you like to reply?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .reviewingReply:
            message = String(localized: "Reply to \(recipient ?? ""): \(draftText) Your draft is ready. What would you like to do next?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .reviewingSelfMessage:
            message = String(localized: "New email to \(recipient ?? ""). Subject: \(selfMessageSubject). Body: \(draftText) Your draft is ready. What would you like to do next?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .uncertain, .sending:
            message = String(localized: "The send is unconfirmed. I will not send this message again. Say check to review sent mail, or no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .completed:
            message = lastSendOutcome == .sent
                ? String(localized: "Gmail confirms your email was sent to \(recipient ?? ""). I’ll continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
                : String(localized: "All right, I’ll continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .preparingReply:
            message = String(localized: "Preparing your reply…", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .preparing, .unavailable:
            message = String(localized: "Your emails are unavailable right now. You can continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
    }

    /// Called only with an owner's recognized utterance from the current session.
    /// A page or a mail body is never passed here as a command.
    public func respond(_ transcript: String, context: MorningExecutionID) async {
        guard self.context == context, isAwaitingResponse else { return }
        questionID = nil
        let token = attempt
        let normalized = Self.normalized(transcript)
        do {
            try requireCurrent(token)
            if GmailSelfMessageContent.isSelfMessageRequest(transcript) {
                await beginSelfMessage(intention: transcript, context: context)
                return
            }
            if isComposingSelfMessage, state == .reviewingSelfMessage,
               let literal = try GmailSelfMessageContent.literal(in: transcript) {
                selfMessageDraft = nil
                try await bindSelfMessage(literal, token: token)
                return
            }
            if Self.isQuestion(transcript, normalized: normalized) {
                try await answerQuestion(transcript, token: token)
                return
            }
            if ["non", "non merci", "no", "no thanks", "continue", "continuer", "passe les mails"].contains(normalized) {
                state = .completed; draftText = ""; recipient = nil
                try await say(String(localized: "All right, I’ll continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
            }
            if isComposingSelfMessage {
                if state == .uncertain {
                    if Self.isSend(normalized) || ["verifie", "check", "check sent", "verifie les envois"].contains(normalized) {
                        try await sendSelfMessage(token: token)
                    } else { try await say(String(localized: "This send needs checking. No new email will be sent. Say check, or no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token) }
                } else if Self.isSend(normalized) {
                    guard selfMessageDraft != nil else {
                        try await say(String(localized: "Complete and review the subject and body before requesting a send.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
                    }
                    if sendReviewRevoked { try await speakSelfMessage(token: token); return }
                    try await sendSelfMessage(token: token)
                } else if ["oui", "yes", "repete", "relis", "read it", "read again"].contains(normalized) {
                    try await speakSelfMessage(token: token)
                } else {
                    try await prepareSelfMessage(intention: transcript, token: token)
                }
                return
            }
            if let index = Self.messageIndex(normalized), messages.indices.contains(index), canChooseMessage {
                selectedIndex = index; recipient = messages[index].replyAddress; draftText = ""; pendingIntention = ""
                sendReviewRevoked = false
                state = .askingToReply
                try await say(String(localized: "\(messages[index].sender). \(messages[index].subject). Would you like to reply?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
            }
            if state == .unavailable {
                if ["reessaie", "reessaye", "reessayer", "retry", "try again"].contains(normalized) {
                    await begin(context: context, generation: generation)
                } else {
                    try await say(String(localized: "Your emails are not ready. Say retry, no, or next to continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                }
                return
            }
            guard messages.indices.contains(selectedIndex), let session else { return }
            let mail = messages[selectedIndex]
            switch state {
            case .askingToReply:
                let hasReplyIntention = ["oui ", "yes ", "reponds lui ", "repond lui ", "reply ", "tell them "].contains(where: normalized.hasPrefix)
                if ["oui", "yes", "reponds lui", "repondre", "reply"].contains(normalized) || hasReplyIntention {
                    guard !mail.bodyUnavailable, !mail.bodyWasTruncated else {
                        try await say(String(localized: "This message is incomplete. I cannot prepare a reply from partial content. You can choose another message or say no.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
                    }
                    guard recipient != nil else {
                        try await say(String(localized: "The reply address is ambiguous. You can choose another message or say no.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
                    }
                    if hasReplyIntention { try await prepare(mail: mail, guidance: transcript, token: token) }
                    else {
                        state = .askingForIntention
                        try await say(String(localized: "What would you like to reply?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                    }
                } else {
                    try await say(String(localized: "Say yes to reply, no to continue, or a message number.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                }
            case .askingForIntention:
                let guidance = pendingIntention.isEmpty ? transcript : pendingIntention + String(localized: " Correction: ", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale) + transcript
                try await prepare(mail: mail, guidance: guidance, token: token)
            case .reviewingReply:
                if Self.isSend(normalized) {
                    guard session.canSendMessages else {
                        try await say(String(localized: "Sending is not authorized for this account. Enable reading and sending in Gmail settings. Your reply has not been sent.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
                    }
                    if sendReviewRevoked { try await reviewReply(mail: mail, token: token); return }
                    try await send(mail: mail, session: session, token: token)
                } else if ["repete", "relis", "read it", "read again"].contains(normalized) {
                    try await reviewReply(mail: mail, token: token)
                } else if ["oui", "yes"].contains(normalized) {
                    try await say(String(localized: "The reply to \(recipient ?? mail.sender) needs your explicit request to send. You can also revise it.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                } else {
                    try await prepare(mail: mail, guidance: transcript, token: token, revising: true)
                }
            case .uncertain:
                if Self.isSend(normalized) || ["verifie", "check", "check sent", "verifie les envois"].contains(normalized) {
                    try await send(mail: mail, session: session, token: token)
                } else {
                    try await say(String(localized: "The send is uncertain. Say check to look for this reply in sent mail, or no to continue. I will not send it again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
                }
            default: break
            }
        } catch { await fail(error, token: token) }
    }

    public func cancel() {
        attempt = UUID()
        attention.cancel()
        questionID = nil
        // Keep the draft and selected message for a coherent pause/resume. Any
        // unfinished send remains in the durable journal and can only be checked.
        if state == .sending { state = .uncertain }
        else if state == .preparingReply {
            drafts.cancel()
            state = draftText.isEmpty ? .askingForIntention : .reviewingReply
            message = String(localized: "Preparation was interrupted. Your intention is preserved; say your correction or no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        } else if state == .preparing { state = .unavailable }
        if isComposingSelfMessage, state == .askingForIntention || state == .reviewingReply { state = .reviewingSelfMessage }
    }

    /// Another action dialogue takes conversational focus. Keep the exact draft,
    /// but require its complete review again before a later separate Send.
    /// Already claimed sends retain their journal-only reconciliation path.
    public func revokeReviewPreservingDraft(context: MorningExecutionID) {
        guard self.context == context, !draftText.isEmpty, lastSendOutcome == nil,
              state != .sending, state != .uncertain, state != .completed else { return }
        cancel()
        sendReviewRevoked = true
    }

    public func clear() {
        cancel(); context = nil; session = nil; messages = []; selectedIndex = 0; pendingIntention = ""
        draftText = ""; recipient = nil; summary = ""; inboxNarration = nil; message = ""; state = .idle; generation = nil; lastSendOutcome = nil
        attentionSelection = nil
        readOutcome = .unavailable
        isComposingSelfMessage = false; selfMessageSubject = ""; selfMessageDraft = nil
        sendReviewRevoked = false
    }

    /// An ordinary owner action in the active mail moment, not an Inbox fixture.
    /// Initial "send me an email" prepares only; a separate final Send is required.
    public func beginSelfMessage(intention: String = "", context: MorningExecutionID) async {
        guard self.context == context, canComposeSelfMessage else { return }
        attempt = UUID(); questionID = nil
        let token = attempt
        isComposingSelfMessage = true; selfMessageDraft = nil; selfMessageSubject = ""; draftText = ""; recipient = nil
        sendReviewRevoked = true
        state = .preparingReply
        do {
            try requireCurrent(token)
            guard let session else { return }
            let profileRecipient = try await service.selfMessageRecipient(session: session)
            try requireCurrent(token)
            recipient = profileRecipient
            if intention.isEmpty || ["envoie moi un mail", "envoie moi un email", "note a moi meme", "send me an email", "email myself"].contains(Self.normalized(intention)) {
                state = .reviewingSelfMessage
                try await say(String(localized: "Note to yourself: \(recipient ?? ""). Dictate a subject and body, or fill in the fields. Nothing has been sent.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
            } else { try await prepareSelfMessage(intention: intention, token: token) }
        } catch { await fail(error, token: token) }
    }

    public func reviewSelfMessage(subject: String, body: String, context: MorningExecutionID) async {
        guard self.context == context, isComposingSelfMessage, state == .reviewingSelfMessage,
              lastSendOutcome == nil else { return }
        attempt = UUID(); questionID = nil
        let token = attempt
        do { try await bindSelfMessage(.init(subject: subject, body: body), token: token) }
        catch { await fail(error, token: token) }
    }

    public func editSelfMessage(subject: String, body: String, context: MorningExecutionID) {
        guard self.context == context, isComposingSelfMessage, state == .reviewingSelfMessage,
              lastSendOutcome == nil else { return }
        attempt = UUID(); questionID = nil; selfMessageDraft = nil
        selfMessageSubject = subject; draftText = body
        sendReviewRevoked = true
        message = String(localized: "Your changes need a new review before sending.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
    }

    private func prepareSelfMessage(intention: String, token: UUID) async throws {
        state = .preparingReply
        selfMessageDraft = nil
        sendReviewRevoked = true
        let previous = try? GmailSelfMessageContent(subject: selfMessageSubject, body: draftText)
        let proposed = try await selfDrafts.propose(intention: intention, previous: previous)
        try requireCurrent(token)
        try await bindSelfMessage(proposed, token: token)
    }

    private func bindSelfMessage(_ content: GmailSelfMessageContent, token: UUID) async throws {
        try requireCurrent(token)
        guard let session else { throw GmailConnectionError.connectionChanged }
        let prepared = try await service.prepareSelfMessage(subject: content.subject, body: content.body,
            session: session, generation: generation)
        try requireCurrent(token)
        guard prepared.recipient == recipient else { throw GmailConnectionError.connectionChanged }
        selfMessageDraft = prepared; selfMessageSubject = prepared.subject; draftText = prepared.body
        state = .reviewingSelfMessage
        try await speakSelfMessage(token: token)
    }

    private func speakSelfMessage(token: UUID) async throws {
        guard selfMessageDraft != nil else {
            try await say(String(localized: "Fill in the subject and body of your note to yourself, then review the draft. Nothing is sent.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token); return
        }
        sendReviewRevoked = true
        try await say(String(localized: "New email to \(recipient ?? ""). Subject: \(selfMessageSubject). Body: \(draftText) Your draft is ready. What would you like to do next?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        try requireCurrent(token)
        sendReviewRevoked = false
    }

    private func sendSelfMessage(token: UUID) async throws {
        guard let session, let context, let draft = selfMessageDraft else { return }
        state = .sending; lastSendOutcome = .uncertain
        let operation = "self-message." + context.sessionID.uuidString + "." + context.stepID.uuidString
        let result = try await service.sendSelfMessage(draft, operationID: operation, session: session, generation: generation)
        try requireCurrent(token)
        try await finishSending(result, token: token)
    }

    private func prepare(mail: GmailMessage, guidance: String, token: UUID, revising: Bool = false) async throws {
        state = .preparingReply
        sendReviewRevoked = true
        if !revising { pendingIntention = guidance }
        let reply: String
        if revising {
            reply = try await drafts.reviseReply(sender: mail.sender, subject: mail.subject,
                body: mail.plainTextBody, reply: draftText, guidance: guidance)
        } else {
            reply = try await drafts.draftReply(sender: mail.sender, subject: mail.subject,
                body: mail.plainTextBody, guidance: guidance)
        }
        try requireCurrent(token)
        draftText = reply; pendingIntention = ""; state = .reviewingReply
        try await reviewReply(mail: mail, token: token)
    }

    private func reviewReply(mail: GmailMessage, token: UUID) async throws {
        sendReviewRevoked = true
        try await say(String(localized: "Reply to \(recipient ?? mail.sender): \(draftText) Your draft is ready. What would you like to do next?", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        try requireCurrent(token)
        sendReviewRevoked = false
    }

    private func send(mail: GmailMessage, session: GmailAccessSession, token: UUID) async throws {
        guard let context else { return }
        state = .sending; lastSendOutcome = .uncertain
        let operationID = context.sessionID.uuidString + "." + context.stepID.uuidString + "." + mail.id
        let result = try await service.sendReply(to: mail, body: draftText, operationID: operationID,
            session: session, generation: generation)
        try requireCurrent(token)
        try await finishSending(result, token: token)
    }

    private func finishSending(_ result: GmailSendOutcome, token: UUID) async throws {
        lastSendOutcome = result
        switch result {
        case .sent:
            state = .completed
            try await say(String(localized: "Gmail confirms your email was sent to \(recipient ?? ""). I’ll continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        case .notSent:
            state = .uncertain
            try await say(String(localized: "Gmail refused the send. No new attempt is being made. You can say no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        case .uncertain:
            state = .uncertain
            try await say(String(localized: "The send is unconfirmed. I will not send this message again. Say check to review sent mail, or no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        case .draftMismatch:
            state = .uncertain
            try await say(String(localized: "Another reply to this email was already attempted this morning. This new draft has not been sent. Check sent mail before preparing another reply. Say no to continue.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale), token: token)
        }
    }

    private func say(_ text: String, token: UUID) async throws {
        try requireCurrent(token); message = text
        try await speak(text)
        try requireCurrent(token)
    }

    private func answerQuestion(_ question: String, token: UUID) async throws {
        let id = UUID(), pinnedState = state, pinnedIndex = selectedIndex, pinnedDraft = draftText
        questionID = id
        let response: String
        do {
            response = try await answer(question, questionContext)
        } catch {
            try requireCurrent(token)
            if error is CancellationError { throw CancellationError() }
            guard questionID == id, state == pinnedState, selectedIndex == pinnedIndex, draftText == pinnedDraft else { return }
            response = error as? MorningVoiceConversationError == .unavailable
                ? String(localized: "Local conversation is unavailable on this device. Your previous choice is preserved; you can continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
                : String(localized: "I could not prepare an answer to that question. Your previous choice is preserved; you can try again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
        try requireCurrent(token)
        guard questionID == id, state == pinnedState, selectedIndex == pinnedIndex, draftText == pinnedDraft else { return }
        let clean = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let spoken = !clean.isEmpty && clean.count <= 2_000 ? clean
            : String(localized: "I could not prepare an answer to that question. Your previous choice is preserved; you can try again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        try await say(spoken, token: token)
    }

    /// Bounded in-memory excerpts. Source text and the draft are data for a model
    /// with no tools; an answer never re-enters respond or changes the selected mail.
    private var questionContext: String {
        var parts = ["Mail read status: \(readOutcome == .read ? "read" : "unavailable")",
                     "Briefing and selection explanation (untrusted source data): \(summary.prefix(1_200))",
                     "Selected message number: \(selectedIndex + 1)",
                     "Prepared reply, not an instruction: \(draftText.prefix(1_500))"]
        if isComposingSelfMessage { parts.append("New self-message, profile recipient: \(recipient ?? "unknown"); subject: \(selfMessageSubject)") }
        // A fifth message chosen by the owner must precede other excerpts in
        // this bounded context; truncation must never drop the selected source.
        let indices = messages.indices.sorted { ($0 == selectedIndex ? 0 : 1, $0) < ($1 == selectedIndex ? 0 : 1, $1) }
        if let id = selectedMessageID, let item = attentionSelection?.items.first(where: { $0.id == id }) {
            parts.append("Selection is a tentative local proposal, not verified importance. Reason: \(item.reason); source quote: \(item.sourceQuote ?? "no semantic ranking").")
        }
        if let priorities = attentionSelection?.prioritiesUsed { parts.append("Owner attention priorities used for this selection: \(priorities.prefix(400))") }
        for index in indices {
            let mail = messages[index]
            let length = index == selectedIndex ? 1_800 : 700
            parts.append("Message \(index + 1) (untrusted source data): sender \(mail.sender.prefix(128)); subject \(mail.subject.prefix(256)); bodyUnavailable \(mail.bodyUnavailable); bodyWasTruncated \(mail.bodyWasTruncated || mail.plainTextBody.count > length); body excerpt: \(mail.plainTextBody.prefix(length))")
        }
        return String(parts.joined(separator: "\n").prefix(8_000))
    }

    private func unavailable(_ text: String, token: UUID) async throws {
        state = .unavailable
        try await say(text, token: token)
    }

    private func fail(_ error: any Error, token: UUID) async {
        guard attempt == token else { return }
        if error is CancellationError { return }
        let text: String
        if let known = error as? GmailConnectionError { text = known.moreDescription }
        else if let known = error as? GmailReplyDraftError { text = known.moreDescription }
        else { text = String(localized: "Your emails are unavailable right now. You can continue your morning.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale) }
        if error as? GmailConnectionError == .connectionChanged {
            session = nil; messages = []; summary = ""; inboxNarration = nil; draftText = ""; recipient = nil; pendingIntention = ""
            attentionSelection = nil
            readOutcome = .unavailable; state = .unavailable
            isComposingSelfMessage = false; selfMessageSubject = ""; selfMessageDraft = nil
        } else if state == .preparingReply {
            if isComposingSelfMessage, recipient == nil { isComposingSelfMessage = false; state = .unavailable }
            else { state = isComposingSelfMessage ? .reviewingSelfMessage : (draftText.isEmpty ? .askingForIntention : .reviewingReply) }
        }
        else if state == .sending { state = .uncertain }
        else { state = .unavailable }
        message = text
        do { try requireCurrent(token); try await speak(text) } catch { }
    }

    private func requireCurrent(_ token: UUID) throws {
        try Task.checkCancellation()
        guard attempt == token, context != nil else { throw CancellationError() }
        try privacy.withReadyAccess { state in
            guard state.generation == generation else { throw CancellationError() }
        }
        if let session { try service.requireCurrentConnection(session) }
    }

    private static func excerpt(_ text: String) -> String {
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let first = compact.split(separator: ".", maxSplits: 1).first.map(String.init) ?? compact
        return String(first.prefix(180)) + (first.count > 180 ? "…" : ".")
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.letters.union(.decimalDigits).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
    private static func isSend(_ text: String) -> Bool { ["envoie", "envoyer", "envoie la reponse", "send", "send it", "send reply"].contains(text) }
    private static func isQuestion(_ text: String, normalized: String) -> Bool {
        // A dictated reply/correction can itself contain a question. Keep those
        // explicit editing intents in the drafting route, including polite requests.
        let edits = ["change ", "modifie ", "remplace ", "retire ", "ajoute ", "reformule ", "corrige ", "dis ",
                     "reponds ", "repond ", "reply ", "tell them ", "add ", "remove ", "replace ", "rewrite ", "edit "]
        let instruction = ["peux tu ", "pourrais tu ", "can you ", "could you ", "please ", "s il te plait "]
            .first(where: normalized.hasPrefix).map { String(normalized.dropFirst($0.count)) } ?? normalized
        if edits.contains(where: instruction.hasPrefix) || normalized.hasPrefix("oui ") || normalized.hasPrefix("yes ") { return false }
        return text.contains("?") || ["pourquoi", "que dit", "qu est ce", "est ce que", "qui ", "quel", "quand", "comment", "combien",
            "peux tu me dire", "resume ", "lis ", "relis le ", "explique ", "what", "why", "who", "when", "how", "which",
            "can you tell", "could you tell", "read the ", "summarize ", "explain "]
            .contains(where: normalized.hasPrefix)
    }
    private static func messageIndex(_ text: String) -> Int? {
        switch text {
        case "1", "le premier", "premier", "message un", "first", "first message": 0
        case "2", "le deuxieme", "deuxieme", "message deux", "second", "second message": 1
        case "3", "le troisieme", "troisieme", "message trois", "third", "third message": 2
        case "4", "le quatrieme", "quatrieme", "message quatre", "fourth", "fourth message": 3
        case "5", "le cinquieme", "cinquieme", "message cinq", "fifth", "fifth message": 4
        default: nil
        }
    }
}
