import Foundation

/// Only operation metadata is saved. Page text, mail and voice input stay in memory.
public struct RoutineExecutionRecord: Codable, Equatable, Sendable, Identifiable {
    public enum Outcome: String, Codable, Sendable {
        case running, completed, budgetFinished, skipped, unavailable, uncertain, interrupted
    }
    public var id: UUID { stepID }
    public let sessionID: UUID
    public let stepID: UUID
    public var outcome: Outcome
    public var observedContents: Int
    public var confirmedLikes: Int
    /// A provider receipt was observed even if presenting its result later failed.
    /// No provider content is retained in the record.
    public var confirmedExternalEffect: Bool?
    /// Opaque browser-content hashes for this exact session/step, never page text.
    public var webContentProgress: WebMorningContentProgress?
    public var updatedAt: Date

    public init(sessionID: UUID, stepID: UUID, outcome: Outcome, observedContents: Int = 0,
                confirmedLikes: Int = 0, confirmedExternalEffect: Bool? = nil,
                webContentProgress: WebMorningContentProgress? = nil, updatedAt: Date = Date()) {
        self.sessionID = sessionID; self.stepID = stepID; self.outcome = outcome
        self.observedContents = max(0, observedContents, webContentProgress?.observedCount ?? 0); self.confirmedLikes = max(0, confirmedLikes)
        self.confirmedExternalEffect = confirmedExternalEffect
        self.webContentProgress = webContentProgress
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case sessionID, stepID, outcome, observedContents, confirmedLikes, confirmedExternalEffect, webContentProgress, updatedAt
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let count = try values.decode(Int.self, forKey: .observedContents)
        let progress: WebMorningContentProgress?
        if values.contains(.webContentProgress) {
            do { progress = try values.decode(WebMorningContentProgress.self, forKey: .webContentProgress) }
            catch { progress = .unavailable(legacyObservedCount: count) }
        } else { progress = nil }
        self.init(sessionID: try values.decode(UUID.self, forKey: .sessionID),
            stepID: try values.decode(UUID.self, forKey: .stepID),
            outcome: try values.decode(Outcome.self, forKey: .outcome), observedContents: count,
            confirmedLikes: try values.decode(Int.self, forKey: .confirmedLikes),
            confirmedExternalEffect: try values.decodeIfPresent(Bool.self, forKey: .confirmedExternalEffect),
            webContentProgress: progress, updatedAt: try values.decode(Date.self, forKey: .updatedAt))
    }
}

/// A read-only recap of each pinned moment. Visiting a moment does not certify an
/// operation, and a provider response is separate from presenting that response.
/// Nothing here is persisted or changes session progression.
public struct RoutineStepExecutionRecap: Identifiable, Equatable, Sendable {
    public enum Progress: Equatable, Sendable { case reached, skipped, notReached }
    public enum Operation: Equatable, Sendable {
        case verified, timedBudgetFinished, budgetFinished, running, paused
        case responseReceivedPresentationUnavailable, responseReceivedPresentationInterrupted
        case unavailable, uncertain, interrupted, notVerified
    }
    public let id: UUID
    public let title: String
    public let progress: Progress
    public let operation: Operation?
    /// Actual metadata for this browser moment; nil means no record was received.
    public let observedContents: Int?
    public let confirmedLikes: Int?

    public static func make(session: RoutineSession, records: [RoutineExecutionRecord]) -> [Self] {
        let started = session.events.contains { $0.kind == .started }
        let skipped = Set(session.skippedStepIDs)
        return session.routine.steps.enumerated().map { index, step in
            let reached = started && index <= session.currentStepIndex
            let progress: Progress = skipped.contains(step.id) ? .skipped : reached ? .reached : .notReached
            let record = reached ? records.last { $0.sessionID == session.id && $0.stepID == step.id } : nil
            let operation: Operation?
            switch record?.outcome {
            case .completed: operation = step.automation == .timedMoment ? .notVerified : .verified
            case .budgetFinished: operation = step.automation == .timedMoment ? .timedBudgetFinished : .budgetFinished
            case .unavailable:
                operation = record?.confirmedExternalEffect == true ? .responseReceivedPresentationUnavailable : .unavailable
            case .uncertain: operation = .uncertain
            case .interrupted:
                operation = record?.confirmedExternalEffect == true ? .responseReceivedPresentationInterrupted : .interrupted
            case .running:
                if index == session.currentStepIndex, session.status == .running { operation = .running }
                else if index == session.currentStepIndex, session.status == .paused { operation = .paused }
                else { operation = .interrupted }
            case .skipped: operation = progress == .skipped ? nil : .notVerified
            case nil: operation = reached && progress != .skipped ? .notVerified : nil
            }
            return Self(id: step.id, title: step.title, progress: progress, operation: operation,
                observedContents: step.webBehavior != nil ? record?.observedContents : nil,
                confirmedLikes: step.webBehavior != nil ? record?.confirmedLikes : nil)
        }
    }

    public func summary(french: Bool) -> String {
        if progress == .notReached { return french ? "Moment non atteint." : "Moment not reached." }
        let result: String
        switch operation {
        case .verified: result = french ? "Opération vérifiée." : "Operation verified."
        case .timedBudgetFinished: result = french ? "Budget chronométré terminé." : "Timed budget finished."
        case .budgetFinished: result = french ? "Temps alloué terminé ; aucune action supplémentaire vérifiée." : "Allocated time finished; no additional action verified."
        case .running: result = french ? "Opération en cours." : "Operation in progress."
        case .paused: result = french ? "Moment en pause." : "Moment paused."
        case .responseReceivedPresentationUnavailable:
            result = french ? "Réponse du service reçue ; restitution indisponible." : "Service response received; presentation unavailable."
        case .responseReceivedPresentationInterrupted:
            result = french ? "Réponse du service reçue ; restitution interrompue." : "Service response received; presentation interrupted."
        case .unavailable: result = french ? "Opération indisponible." : "Operation unavailable."
        case .uncertain: result = french ? "Résultat non confirmé ; à vérifier." : "Result unconfirmed; needs checking."
        case .interrupted: result = french ? "Opération interrompue." : "Operation interrupted."
        case .notVerified: result = french ? "Aucune opération vérifiée enregistrée." : "No verified operation recorded."
        case nil: result = ""
        }
        var text = result
        if progress == .skipped {
            text = (french ? "Moment passé." : "Moment skipped.") + (result.isEmpty ? "" : " " + result)
        }
        if let observedContents, let confirmedLikes {
            text += french ? "\nNavigateur : \(observedContents) contenus observés, \(confirmedLikes) likes confirmés."
                : "\nBrowser: \(observedContents) contents observed, \(confirmedLikes) likes confirmed."
        }
        return text
    }
}

public extension RoutineStep {
    var executionDescription: String {
        let service: String?
        switch target {
        case let .inAppWeb(url): service = WebMorningSite(url: url)?.displayName ?? url.host
        case let .externalApp(app, _): service = app.displayName
        case let .shortcut(name, _): service = "Shortcuts · \(name)"
        case let .connectedAPI(name, _, _, _): service = name.replacingOccurrences(of: "_", with: " ").capitalized
        case .googleCalendarDay(let calendar): service = "Google Calendar · \(calendar.sourceLabel())"
        case .calendlyDay(let account): service = "Calendly · \(account.userName)"
        case .outlookInbox(let account): service = "Outlook · \(account.sourceLabel())"
        case nil: service = automation == .gmailInbox ? "Gmail" : nil
        }
        return service.map { "\($0) · \(operationDescription)" } ?? operationDescription
    }
    private var operationDescription: String {
        let fr = AppLanguage.isFrench
        if case .inAppWeb = target {
            guard let webBehavior else { return fr ? "Ouvrir la page ; navigation manuelle." : "Open the page; browse yourself." }
            let behavior: String
            switch webBehavior {
            case .browseFeed: behavior = fr ? "Parcourir les publications" : "Browse the feed"
            case .watchVideos: behavior = fr ? "Lire les vidéos et passer aux suivantes" : "Play videos and move to the next"
            case .watchStories: behavior = fr ? "Ouvrir et parcourir les stories" : "Open and browse stories"
            case .readHeadlines: behavior = fr ? "Parcourir et lire les titres" : "Browse and read headlines"
            case .readUnread: behavior = fr ? "Lire les conversations non lues" : "Read unread conversations"
            }
            let likes = webLikesAllowed == true
                ? (fr ? ". Aimer jusqu’à 3 contenus affichés." : ". Like up to 3 displayed contents.")
                : (fr ? ". Aucun like." : ". No likes.")
            return behavior + likes
        }
        if case .externalApp = target { return fr ? "Ouvrir l’application ; les gestes restent manuels." : "Open the app; its actions remain manual." }
        if case .shortcut = target { return fr ? "Exécuter le raccourci installé et vérifier son retour." : "Run the installed shortcut and check its return." }
        if case .connectedAPI = target { return fr ? "Effectuer l’action du compte présentée ci-dessous." : "Perform the account action described below." }
        if case .googleCalendarDay = target { return fr ? "Lire les événements d’aujourd’hui, dans le fuseau actuel de cet iPhone. Jusqu’à 25 événements ; toute lecture partielle est signalée." : "Read today’s events in this iPhone’s current time zone. Up to 25 events; partial readings are disclosed." }
        if case .calendlyDay = target { return fr ? "Lire les rendez-vous qui commencent aujourd’hui, dans le fuseau actuel de cet iPhone. Jusqu’à 25 rendez-vous ; toute lecture partielle est signalée." : "Read bookings starting today in this iPhone’s current time zone. Up to 25 bookings; partial readings are disclosed." }
        if case .outlookInbox = target { return fr ? "Présenter jusqu’à trois messages non lus de la boîte de réception, y compris des messages plus anciens. Lire le contenu d’un message à votre demande. Aucun envoi ni changement des messages." : "Present up to three unread Inbox messages, including older mail. Read a message’s content when you ask. No messages are sent or changed." }
        switch automation {
        case .spokenNote: return fr ? "Lire le texte de ce moment." : "Read this moment’s text."
        case .todayCalendar: return fr ? "Lire les événements du jour de vos calendriers choisis." : "Read today’s events from your selected calendars."
        case .morningBriefing: return fr ? "Préparer et lire votre calendrier et la météo disponibles." : "Prepare and read your available calendar and weather."
        case .savedObservation: return fr ? "Lire votre extrait enregistré, sans le présenter comme une information du jour." : "Read your saved excerpt as a past observation."
        case .timedMoment: return fr ? "Vous laisser ce temps, puis passer automatiquement à la suite." : "Give you this time, then continue automatically."
        case .gmailInbox: return fr ? "Lire vos mails non lus, préparer et corriger une réponse. Envoyer seulement à votre demande." : "Read unread mail, prepare and edit a reply. Send only when you ask."
        case nil: return fr ? "Moment personnel. Dites « suivant » lorsque vous avez terminé." : "Your own moment. Say “next” when you finish."
        }
    }
}
