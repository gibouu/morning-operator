import CryptoKit
import Foundation
import MorningCore
import Observation

/// Only an explicit minute-resolution UI edit uses this boundary. Loading a
/// prepared draft or editing its title must retain the original Date exactly.
public enum NativeMomentDateInput {
    public static func editedMinute(_ date: Date, calendar: Calendar = .current) -> Date {
        guard date.timeIntervalSinceReferenceDate.isFinite else { return date }
        return calendar.dateInterval(of: .minute, for: date)?.start ?? date
    }
}

/// Exact local account/list identity. Titles are presentation; identifiers pin the destination.
public struct NativeMomentDestination: Codable, Sendable, Equatable {
    public let id: String
    public let sourceID: String
    public let title: String
    public let sourceTitle: String
    public let kind: CaptureDestination
    public init(id: String, sourceID: String, title: String, sourceTitle: String, kind: CaptureDestination) {
        self.id = id; self.sourceID = sourceID; self.title = title; self.sourceTitle = sourceTitle; self.kind = kind
    }
}

@MainActor public protocol NativeMomentProviding: AnyObject {
    func destination(for kind: CaptureDestination) throws -> NativeMomentDestination
    func validateDestination(_ destination: NativeMomentDestination) throws
    func upcomingReminders() async throws -> [ReminderSummary]
    func perform(_ action: NativeMomentAction) throws -> String
}

public enum NativeMomentAction: Sendable, Equatable {
    case reminder(ReminderDraft, NativeMomentDestination)
    case event(CalendarEventDraft, NativeMomentDestination)
    case complete(ReminderSummary)

    public var title: String {
        switch self { case .reminder(let draft, _): draft.title; case .event(let draft, _): draft.title; case .complete(let item): item.title }
    }
    public var date: Date? {
        switch self { case .reminder(let draft, _): draft.dueDate; case .event(let draft, _): draft.startDate; case .complete(let item): item.dueDate }
    }
    public var durationMinutes: Int {
        if case .event(let draft, _) = self { return Int(draft.endDate.timeIntervalSince(draft.startDate) / 60) }
        return 30
    }
    public var isCompletion: Bool { if case .complete = self { return true }; return false }
    public var destination: NativeMomentDestination? {
        switch self { case .reminder(_, let destination), .event(_, let destination): destination; case .complete: nil }
    }
}

public enum NativeMomentError: LocalizedError, Sendable {
    case destinationChanged, staleSource, unavailableJournal
    public var errorDescription: String? {
        switch self {
        case .destinationChanged: AppLanguage.isFrench ? "La liste ou le calendrier a changé. Préparez et relisez l’ajout à nouveau." : "The list or calendar changed. Prepare and review the addition again."
        case .staleSource: AppLanguage.isFrench ? "Ce rappel n’est plus dans la lecture actuelle. Dites lis mes rappels pour le retrouver." : "This reminder is no longer in the current reading. Say read my reminders to find it again."
        case .unavailableJournal: AppLanguage.isFrench ? "La protection contre les doublons est indisponible. Aucun nouvel ajout n’est lancé." : "Duplicate protection is unavailable. No new addition is being started."
        }
    }
}

/// A content-free projection of durable claims, separate from routine completion.
public struct NativeMomentActionCounts: Sendable, Equatable {
    public let confirmed: Int
    public let unconfirmed: Int
}

/// One native draft at a time, scoped to the current moment. Provider IDs never come from a model.
@MainActor @Observable public final class NativeMomentConversation {
    public enum Phase: Sendable, Equatable { case idle, preparing, choosingReminder, needsDetails, reviewing, awaitingConfirmation, writing, completed, unavailable, uncertain }
    public private(set) var phase: Phase = .idle
    public private(set) var message = ""
    public private(set) var action: NativeMomentAction?
    public private(set) var observedReminders: [ReminderSummary] = []
    public private(set) var context: MorningExecutionID?
    public private(set) var reviewID = UUID()
    public var isActive: Bool { ![.idle, .completed, .unavailable].contains(phase) }
    public var canConfirm: Bool { phase == .awaitingConfirmation && reviewedID == reviewID && reviewedAt.map { (0..<300).contains(now().timeIntervalSince($0)) } == true }
    public var draftKind: CaptureDestination? { pendingInput?.kind }
    public var draftTitle: String? { pendingInput?.title }
    public var draftDate: Date? { pendingInput?.date }
    public var draftDurationMinutes: Int { pendingInput?.duration ?? 30 }

    /// Editing on screen revokes the spoken review immediately, before the next button or utterance.
    public func stageEdit(title: String, date: Date?, durationMinutes: Int) {
        guard let input = pendingInput, phase != .writing, phase != .uncertain,
              title != input.title || date != input.date || (input.kind == .calendar && durationMinutes != input.duration) else { return }
        pendingInput = (input.kind, title, date, date == nil, durationMinutes)
        action = nil; reviewedID = nil; attempt = UUID(); phase = .needsDetails
        message = Self.localized("Ces modifications doivent être relues avant confirmation.", "Review these changes before confirming.")
    }
    @ObservationIgnored private let provider: any NativeMomentProviding
    @ObservationIgnored private let control: LocalDataControl
    @ObservationIgnored private let speak: @MainActor (String) async throws -> Void
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private var generation: UUID?
    @ObservationIgnored private var privacyBound = false
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var operationID = UUID()
    @ObservationIgnored private var reviewedID: UUID?
    @ObservationIgnored private var reviewedAt: Date?
    @ObservationIgnored private var observedAt: Date?
    @ObservationIgnored private var pendingInput: (kind: CaptureDestination, title: String, date: Date?, noDate: Bool, duration: Int?)?
    @ObservationIgnored private var calendar = Calendar.current

    public init(provider: any NativeMomentProviding, directory: URL = LocalDataControl.defaultDirectory,
                now: @escaping @MainActor () -> Date = { Date() }, calendar: Calendar = .current,
                speak: @escaping @MainActor (String) async throws -> Void) {
        self.provider = provider; control = LocalDataControl(directory: directory); self.now = now; self.speak = speak; self.calendar = calendar
    }

    public func accepts(_ text: String, context: MorningExecutionID) -> Bool {
        let words = Self.words(text)
        return Self.creationKind(words) != nil || ["lis mes rappels", "lire mes rappels", "read my reminders"].contains(words) ||
            words.hasPrefix("termine ") || words.hasPrefix("marque ") || words.hasPrefix("complete ") || words.hasPrefix("finish ") || (self.context == context && isActive)
    }

    /// A final owner utterance only. Creating/revising a draft can never confirm it in that same turn.
    @discardableResult public func respond(_ text: String, context: MorningExecutionID) async -> Bool {
        let words = Self.words(text)
        guard !Task.isCancelled, !words.isEmpty, text.count <= 4_000 else { return false }
        let newKind = Self.creationKind(words)
        let read = ["lis mes rappels", "lire mes rappels", "read my reminders"].contains(words)
        let completion = words.hasPrefix("termine ") || words.hasPrefix("marque ") || words.hasPrefix("complete ") || words.hasPrefix("finish ")
        guard newKind != nil || read || completion || (self.context == context && isActive) else { return false }
        if self.context != context { clear() }
        self.context = context
        let turn = UUID(); attempt = turn
        do {
            try checkPrivacy()
            if ["annule", "annuler", "cancel", "non", "no"].contains(words), phase != .writing {
                clear(); message = Self.localized("Demande fermée. Dites reprends pour continuer votre matin.", "Request closed. Say resume to continue your morning."); await say(); return true
            }
            if phase == .writing || phase == .uncertain {
                message = Self.uncertainMessage; await say(); return true
            }
            if ["repete", "repeat", "relis", "read it again"].contains(words) {
                if action != nil { await review(); return true }
                if pendingInput != nil { try prepareInput(); await presentPrepared(); return true }
            }
            let addWords = ["ajoute", "ajouter", "confirme l ajout", "add it", "confirm addition"]
            let completeWords = ["confirme la completion", "confirme termine", "marque termine", "mark complete"]
            if addWords.contains(words) || completeWords.contains(words) {
                guard action?.isCompletion == completeWords.contains(words) else {
                    message = Self.localized("Cette confirmation ne correspond pas à la demande préparée. Dites ajoute pour créer, ou marque terminé pour terminer un rappel relu.", "That confirmation does not match the prepared request. Say add it to create, or mark complete to complete a reviewed reminder.")
                    await say(); return true
                }
                await confirm(context: context); return true
            }
            if ["oui", "yes", "envoie", "send", "confirme", "confirm"].contains(words), action != nil {
                message = Self.localized("Relisez les détails, puis dites ajoute pour créer, ou marque terminé pour terminer ce rappel.", "Review the details, then say add it to create, or mark complete to complete this reminder."); await say(); return true
            }
            if read {
                let token = turn; phase = .preparing; action = nil; pendingInput = nil
                let values = try await provider.upcomingReminders()
                guard isCurrent(token, context: context) else { return true }
                guard values.count <= 50, Set(values.map(\.id)).count == values.count,
                      values.allSatisfy({ !$0.id.isEmpty && !$0.listID.isEmpty && !$0.sourceID.isEmpty }) else { throw NativeMomentError.staleSource }
                observedReminders = Array(values.prefix(5)); observedAt = now(); phase = .choosingReminder
                message = observedReminders.isEmpty ? Self.localized("Aucun rappel incomplet et daté dans les sept prochains jours n’a été trouvé dans cette lecture locale.", "No incomplete dated reminders in the next seven days were found in this local reading.") :
                    Self.localized("Voici les cinq premiers rappels au maximum, datés dans les sept prochains jours. ", "Here are up to the first five reminders dated in the next seven days. ") + observedReminders.enumerated().map { "\($0.offset + 1). \($0.element.title), \($0.element.listTitle)." }.joined(separator: " ") + Self.localized(" Dites termine le premier rappel, ou précisez son numéro.", " Say complete the first reminder, or specify its number.")
                await say(); return true
            }
            if completion {
                guard let item = selectedReminder(words) else {
                    phase = .choosingReminder; message = Self.localized("Quel rappel de la dernière lecture ? Dites son numéro, ou lis mes rappels.", "Which reminder from the last reading? Say its number, or read my reminders."); await say(); return true
                }
                try validateObserved(item)
                operationID = UUID(); action = .complete(item); pendingInput = nil; await review(); return true
            }
            if let kind = newKind {
                operationID = UUID(); action = nil; reviewedID = nil
                let parsed = Self.parse(text, kind: kind, now: now(), calendar: calendar)
                pendingInput = (kind, parsed.title, parsed.date, parsed.noDate, parsed.duration)
                try prepareInput(); await presentPrepared(); return true
            }
            if var input = pendingInput {
                // Corrections are owner text; no source or account identity can be changed here.
                if let changed = Self.changedTitle(text) { input.title = changed }
                else {
                    let parsed = Self.parse(text, kind: input.kind, now: now(), calendar: calendar)
                    if let date = parsed.date { input.date = date; input.noDate = false }
                    else if parsed.noDate { input.date = nil; input.noDate = true }
                    if let duration = parsed.duration { input.duration = duration }
                    let newTitle = action == nil && input.title.isEmpty && !parsed.title.isEmpty
                    if newTitle { input.title = parsed.title }
                    guard parsed.date != nil || parsed.noDate || parsed.duration != nil || newTitle else {
                        reviewedID = nil; reviewedAt = nil; phase = .needsDetails
                        message = Self.localized("Je n’ai pas compris cette modification. Rien n’a changé. Dites répète pour relire les détails actuels, ou modifiez-les à l’écran avant de les relire.", "I didn’t understand that change. Nothing changed. Say repeat to review the current details, or edit them on screen before reviewing.")
                        await say(); return true
                    }
                }
                pendingInput = input; action = nil; reviewedID = nil
                try prepareInput(); await presentPrepared(); return true
            }
            message = Self.localized("Dites lis mes rappels, ou annule pour revenir à votre matin.", "Say read my reminders, or cancel to return to your morning."); await say(); return true
        } catch {
            guard attempt == turn, self.context == context, (try? checkPrivacy()) != nil, !Task.isCancelled else { return true }
            phase = .unavailable; action = nil; reviewedID = nil
            message = error.moreDescription; await say(); return true
        }
    }

    public func edit(title: String, date: Date?, durationMinutes: Int, context: MorningExecutionID) async {
        guard !Task.isCancelled, self.context == context, action?.isCompletion != true, phase != .writing, phase != .uncertain,
              let input = pendingInput else { return }
        attempt = UUID()
        pendingInput = (input.kind, title, date, date == nil, durationMinutes)
        action = nil; reviewedID = nil
        do { try checkPrivacy(); try prepareInput(); await presentPrepared() }
        catch { phase = .unavailable; message = error.moreDescription }
    }

    public func selectReminder(id: String, context: MorningExecutionID) async {
        guard !Task.isCancelled, self.context == context, let item = observedReminders.first(where: { $0.id == id }), phase != .writing, phase != .uncertain else { return }
        attempt = UUID()
        do { try checkPrivacy(); try validateObserved(item); operationID = UUID(); action = .complete(item); pendingInput = nil; await review() }
        catch { phase = .unavailable; message = error.moreDescription; await say() }
    }

    public func review() async {
        guard !Task.isCancelled, let action, let context, phase != .writing, phase != .uncertain else { return }
        let token = UUID(); attempt = token; reviewID = UUID(); let revision = reviewID; reviewedID = nil; phase = .reviewing
        do {
            try checkPrivacy()
            if let destination = action.destination { try provider.validateDestination(destination) }
            if case .complete(let item) = action { try validateObserved(item) }
        } catch {
            guard self.context == context else { return }
            reviewedID = nil; phase = .unavailable; message = error.moreDescription; await say(); return
        }
        message = reviewText(action)
        do {
            try await speak(message)
            guard isCurrent(token, context: context), reviewID == revision else { return }
            reviewedID = revision; reviewedAt = now(); phase = .awaitingConfirmation
        } catch {
            guard isCurrent(token, context: context), reviewID == revision else { return }
            phase = .reviewing
            message += Self.localized(" La lecture a été interrompue. Dites répète avant de confirmer.", " The reading was interrupted. Say repeat before confirming.")
        }
    }

    /// Explicit screen review is a touch fallback; it does not itself commit an action.
    public func acknowledgeScreenReview() {
        guard action != nil, phase == .reviewing else { return }
        attempt = UUID(); reviewedID = reviewID; reviewedAt = now(); phase = .awaitingConfirmation
    }

    public func confirmedActionCount(for session: RoutineSession) throws -> Int {
        try actionCounts(for: session).confirmed
    }

    public func actionCounts(for session: RoutineSession) throws -> NativeMomentActionCounts {
        let current = try control.status()
        return try NativeMomentJournal(control: control).counts(contexts: session.routine.steps.map {
            MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: $0.id)
        }, generation: current.generation)
    }

    /// Language changes revoke review, never an action or its reconciliation state.
    public func appLanguageDidChange() {
        reviewID = UUID(); reviewedID = nil
        if phase == .uncertain || phase == .writing { message = Self.uncertainMessage }
        else if let action { message = reviewText(action); phase = .reviewing }
        else if phase != .idle {
            message = Self.localized("Votre demande est conservée. Relisez ses détails avant de continuer.", "Your request is preserved. Review its details before continuing.")
        }
    }

    public func clear() {
        attempt = UUID(); reviewedID = nil; reviewedAt = nil; action = nil; pendingInput = nil; observedReminders = []; observedAt = nil
        context = nil; generation = nil; privacyBound = false; phase = .idle; message = ""
    }

    private func checkPrivacy() throws {
        do {
            try control.withReadyAccess { state in
                if privacyBound, generation != state.generation { throw LocalDataControlError.staleGeneration }
                generation = state.generation; privacyBound = true
            }
        } catch { clear(); throw error }
    }
    private func isCurrent(_ token: UUID, context: MorningExecutionID) -> Bool {
        guard attempt == token, self.context == context, !Task.isCancelled else { return false }
        return (try? checkPrivacy()) != nil
    }
    private func validateObserved(_ item: ReminderSummary) throws {
        guard observedReminders.contains(item), let observedAt, (0..<300).contains(now().timeIntervalSince(observedAt)),
              !item.listID.isEmpty, !item.sourceID.isEmpty else { throw NativeMomentError.staleSource }
    }
    private func selectedReminder(_ words: String) -> ReminderSummary? {
        let ordinals = [["1", "1st", "premier", "premiere", "first"], ["2", "2nd", "deuxieme", "second"], ["3", "3rd", "troisieme", "third"], ["4", "4th", "quatrieme", "fourth"], ["5", "5th", "cinquieme", "fifth"]]
        let tokens = Set(words.split(separator: " ").map(String.init))
        let knownOrdinals = Set(ordinals.flatMap { $0 })
        if tokens.contains(where: { !knownOrdinals.contains($0) && ($0.hasSuffix("ieme") || $0.first?.isNumber == true || ["sixth", "seventh", "eighth", "ninth", "tenth", "last", "dernier", "derniere"].contains($0)) }) { return nil }
        let matches = ordinals.enumerated().filter { !$0.element.filter(tokens.contains).isEmpty }
        if matches.count == 1, observedReminders.indices.contains(matches[0].offset) {
            return observedReminders[matches[0].offset]
        }
        // A missing or out-of-range explicit ordinal never falls back to the sole result.
        if !matches.isEmpty || tokens.contains(where: { $0.hasSuffix("ieme") || $0.first?.isNumber == true || ["sixth", "seventh", "eighth", "ninth", "tenth", "last", "dernier", "derniere"].contains($0) }) { return nil }
        let single = ["termine ce rappel", "termine le rappel", "complete this reminder", "complete the reminder", "finish this reminder", "finish the reminder", "marque ce rappel comme termine"]
        return observedReminders.count == 1 && single.contains(words) ? observedReminders[0] : nil
    }
    private func prepareInput() throws {
        guard let input = pendingInput else { return }
        guard !input.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { phase = .needsDetails; message = Self.localized("Quel titre souhaitez-vous ?", "What title would you like?"); return }
        if input.kind == .calendar && input.date == nil || input.kind == .reminder && input.date == nil && !input.noDate {
            phase = .needsDetails; message = Self.localized("Quand ? Vous pouvez dire demain matin, dans deux heures, ou sans date pour un rappel. Les autres dates se règlent dans les détails affichés.", "When? You can say tomorrow morning, in two hours, or no date for a reminder. Set other dates in the visible details."); return
        }
        if input.kind == .calendar && input.duration == nil { phase = .needsDetails; message = Self.localized("Quelle durée en minutes pour cet événement ?", "How many minutes should this event last?"); return }
        let destination = try provider.destination(for: input.kind)
        if input.kind == .reminder {
            let draft = ReminderDraft(title: input.title, dueDate: input.date, timeZoneIdentifier: calendar.timeZone.identifier, notifyAtDueTime: input.date != nil)
            try draft.validate(); action = .reminder(draft, destination)
        } else if let date = input.date, let duration = input.duration, (1...1_440).contains(duration) {
            let draft = CalendarEventDraft(title: input.title, startDate: date, endDate: date.addingTimeInterval(Double(duration) * 60), timeZoneIdentifier: calendar.timeZone.identifier)
            try draft.validate(); action = .event(draft, destination)
        } else { throw ReminderServiceError.invalidDate }
    }
    private func presentPrepared() async { if action != nil { await review() } else { await say() } }
    private func confirm(context: MorningExecutionID) async {
        guard !Task.isCancelled, canConfirm, self.context == context, let action else {
            message = Self.localized("Préparez et relisez d’abord les détails. Rien n’a été ajouté.", "Prepare and review the details first. Nothing was added."); await say(); return
        }
        do {
            try checkPrivacy()
            if let destination = action.destination { try provider.validateDestination(destination) }
            if case .complete(let item) = action { try validateObserved(item) }
            let fingerprint = try actionFingerprint(action)
            let journal = NativeMomentJournal(control: control)
            let claimed = try journal.claim(id: operationID, context: context, fingerprint: fingerprint, generation: generation)
            guard claimed else { phase = .uncertain; message = Self.uncertainMessage; await say(); return }
            attempt = UUID(); phase = .writing
            // No await between durable reservation, effect, and durable receipt.
            let receipt = try provider.perform(action)
            try journal.confirm(id: operationID, fingerprint: fingerprint, receipt: receipt, generation: generation)
            if action.isCompletion {
                // Retiring the entire reading preserves the ordinal meanings the owner heard.
                observedReminders = []; observedAt = nil
            }
            phase = .completed
            message = confirmedText(action)
            self.action = nil; pendingInput = nil; reviewedID = nil; await say()
        } catch {
            if phase == .writing { phase = .uncertain; message = Self.uncertainMessage }
            else { phase = .unavailable; message = error.moreDescription; reviewedID = nil }
            await say()
        }
    }
    private func say() async {
        let cue = phase == .completed ? Self.localized(" Votre matin est en pause. Dites reprends pour continuer.", " Your morning is paused. Say resume to continue.") : ""
        try? await speak(message + cue)
    }
    private func reviewText(_ action: NativeMomentAction) -> String {
        let format = Date.FormatStyle(date: .complete, time: .shortened, locale: AppLanguage.locale, calendar: calendar, timeZone: calendar.timeZone)
        switch action {
        case .reminder(let draft, let destination):
            return Self.localized("Ajouter le rappel « \(draft.title) » dans \(destination.title), compte \(destination.sourceTitle). ", "Add reminder “\(draft.title)” to \(destination.title), account \(destination.sourceTitle). ") +
                (draft.dueDate.map { Self.localized("Échéance \($0.formatted(format)), fuseau \(draft.timeZoneIdentifier), avec alerte. ", "Due \($0.formatted(format)), time zone \(draft.timeZoneIdentifier), with alert. ") } ?? Self.localized("Sans date et sans alerte. ", "No date or alert. ")) + Self.localized("Dites ajoute pour confirmer, ou change le titre suivi du nouveau titre.", "Say add it to confirm, or change the title followed by the new title.")
        case .event(let draft, let destination):
            return Self.localized("Ajouter « \(draft.title) » dans \(destination.title), compte \(destination.sourceTitle), le \(draft.startDate.formatted(format)) jusqu’au \(draft.endDate.formatted(format)), fuseau \(draft.timeZoneIdentifier). Aucun invité, aucune récurrence ni alerte. Dites ajoute pour confirmer.", "Add “\(draft.title)” to \(destination.title), account \(destination.sourceTitle), from \(draft.startDate.formatted(format)) until \(draft.endDate.formatted(format)), time zone \(draft.timeZoneIdentifier). No attendees, recurrence, or alert. Say add it to confirm.")
        case .complete(let item):
            return Self.localized("Marquer « \(item.title) » comme terminé dans \(item.listTitle), compte \(item.sourceTitle). Dites marque terminé pour confirmer.", "Mark “\(item.title)” complete in \(item.listTitle), account \(item.sourceTitle). Say mark complete to confirm.")
        }
    }
    private func confirmedText(_ action: NativeMomentAction) -> String {
        let format = Date.FormatStyle(date: .complete, time: .shortened, locale: AppLanguage.locale, calendar: calendar, timeZone: calendar.timeZone)
        switch action {
        case .reminder(let draft, let target):
            return Self.localized("Le rappel « \(draft.title) » a été ajouté dans Rappels Apple, liste \(target.title), compte \(target.sourceTitle). ", "Reminder “\(draft.title)” was added to Apple Reminders, list \(target.title), account \(target.sourceTitle). ") +
                (draft.dueDate.map { Self.localized("Échéance : \($0.formatted(format)), fuseau \(draft.timeZoneIdentifier), avec alerte.", "Due: \($0.formatted(format)), time zone \(draft.timeZoneIdentifier), with alert.") } ?? Self.localized("Sans date et sans alerte.", "No date or alert."))
        case .event(let draft, let target):
            return Self.localized("L’événement « \(draft.title) » a été ajouté dans Calendrier Apple, calendrier \(target.title), compte \(target.sourceTitle), du \(draft.startDate.formatted(format)) au \(draft.endDate.formatted(format)), fuseau \(draft.timeZoneIdentifier). Aucun invité, aucune récurrence ni alerte.", "Event “\(draft.title)” was added to Apple Calendar, calendar \(target.title), account \(target.sourceTitle), from \(draft.startDate.formatted(format)) until \(draft.endDate.formatted(format)), time zone \(draft.timeZoneIdentifier). No attendees, recurrence, or alert.")
        case .complete(let item):
            return Self.localized("Le rappel « \(item.title) » a été marqué comme terminé dans Rappels Apple, liste \(item.listTitle), compte \(item.sourceTitle).", "Reminder “\(item.title)” was marked complete in Apple Reminders, list \(item.listTitle), account \(item.sourceTitle).")
        }
    }

    private func actionFingerprint(_ action: NativeMomentAction) throws -> String {
        var fields = [String]()
        switch action {
        case .reminder(let draft, let target): fields = ["reminder", target.id, target.sourceID, draft.title, draft.notes, draft.dueDate?.ISO8601Format() ?? "no-date", draft.timeZoneIdentifier, String(draft.notifyAtDueTime)]
        case .event(let draft, let target): fields = ["event", target.id, target.sourceID, draft.title, draft.notes, draft.startDate.ISO8601Format(), draft.endDate.ISO8601Format(), draft.timeZoneIdentifier]
        case .complete(let item): fields = ["complete", item.id, item.listID, item.sourceID, item.title, item.notes, item.dueDate?.ISO8601Format() ?? "no-date"]
        }
        return NativeMomentJournal.digest(try JSONEncoder().encode(fields))
    }
    static func words(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR")).replacingOccurrences(of: "’", with: " ").replacingOccurrences(of: "'", with: " ").split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ") }
    private static func creationKind(_ words: String) -> CaptureDestination? {
        if ["rappelle moi", "rappel ", "remind me", "reminder "].contains(where: words.hasPrefix) { return .reminder }
        if ["ajoute un evenement", "ajouter un evenement", "add an event", "calendar ", "calendrier ", "planifie ", "schedule "].contains(where: words.hasPrefix) { return .calendar }
        return nil
    }
    private static func changedTitle(_ text: String) -> String? {
        let pattern = #"^(?:change (?:le titre|the title)(?: en| to)?|titre|title)\s*:?\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
    private static func parse(_ text: String, kind: CaptureDestination, now: Date, calendar: Calendar) -> (title: String, date: Date?, noDate: Bool, duration: Int?) {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = kind == .reminder ? #"^(?:rappelle[- ]moi(?: de)?|rappel\s*:|remind me(?: to)?|reminder\s*:)\s*"# : #"^(?:ajoute[rz]? un [ée]v[ée]nement|add an event|calendrier\s*:|calendar\s*:|planifie|schedule)\s*"#
        body = body.replacingOccurrences(of: prefix, with: "", options: [.regularExpression, .caseInsensitive])
        var duration: Int?
        if let regex = try? NSRegularExpression(pattern: #"(?:\s+(?:pendant|pour|for))?\s*(\d{1,4})\s*(?:minutes?|min)\s*$"#, options: .caseInsensitive), let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)), let numberRange = Range(match.range(at: 1), in: body), let range = Range(match.range, in: body), let value = Int(body[numberRange]), (1...1_440).contains(value), kind == .calendar {
            duration = value; body.removeSubrange(range)
        }
        let noDate = words(body).hasSuffix("sans date") || words(body).hasSuffix("no date")
        if noDate { body = body.replacingOccurrences(of: #"\s*(?:sans date|no date)\s*$"#, with: "", options: [.regularExpression, .caseInsensitive]) }
        let parsed = CaptureRequestParser.parse((kind == .reminder ? "Reminder: " : "Calendar: ") + body, now: now, calendar: calendar)
        return (parsed.content.trimmingCharacters(in: .whitespacesAndNewlines), parsed.suggestedDate, noDate, duration)
    }
    private static func localized(_ french: String, _ english: String) -> String { AppLanguage.isFrench ? french : english }
    private static var uncertainMessage: String { localized("Le résultat d’une écriture Apple n’est pas confirmé. Vérifiez Rappels ou Calendrier avant une autre tentative. MORE ne relance pas cette demande.", "An Apple write has an unconfirmed outcome. Check Reminders or Calendar before another attempt. MORE will not repeat this request.") }
}

/// Content-free claims survive relaunch; no title, note, date, account ID, or provider content is stored.
struct NativeMomentJournal {
    struct Entry: Codable { let id: UUID; let context: String; let fingerprint: String; var receipt: String? }
    let control: LocalDataControl
    static func digest(_ value: Data) -> String { SHA256.hash(data: value).map { String(format: "%02x", $0) }.joined() }
    func claim(id: UUID, context: MorningExecutionID, fingerprint: String, generation: UUID?) throws -> Bool {
        try access(generation) { file, entries in
            let key = Self.contextKey(context)
            guard !entries.contains(where: { $0.id == id || ($0.receipt == nil && ($0.context == key || $0.fingerprint == fingerprint)) }), entries.count < 1_000 else { return false }
            try file.save(entries + [Entry(id: id, context: key, fingerprint: fingerprint)])
            return true
        }
    }
    func confirmedCount(contexts: [MorningExecutionID], generation: UUID?) throws -> Int {
        try counts(contexts: contexts, generation: generation).confirmed
    }
    func counts(contexts: [MorningExecutionID], generation: UUID?) throws -> NativeMomentActionCounts {
        let keys = Set(contexts.map { Self.contextKey($0) })
        return try access(generation) { _, entries in
            let matching = entries.filter { keys.contains($0.context) }
            return NativeMomentActionCounts(confirmed: matching.filter { $0.receipt != nil }.count,
                unconfirmed: matching.filter { $0.receipt == nil }.count)
        }
    }
    private static func contextKey(_ context: MorningExecutionID) -> String {
        Self.digest(Data("\(context.sessionID):\(context.routineVersionID):\(context.stepID)".utf8))
    }
    func confirm(id: UUID, fingerprint: String, receipt: String, generation: UUID?) throws {
        try access(generation) { file, entries in
            guard let index = entries.firstIndex(where: { $0.id == id && $0.fingerprint == fingerprint && $0.receipt == nil }), !receipt.isEmpty else { throw NativeMomentError.unavailableJournal }
            var updated = entries; updated[index].receipt = Self.digest(Data(receipt.utf8)); try file.save(updated)
        }
    }
    private func access<T>(_ generation: UUID?, body: (AtomicJSONFile<[Entry]>, [Entry]) throws -> T) throws -> T {
        try control.withReadyAccess { state in
            guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
            let url = control.directory.appendingPathComponent("native-moment-journal.json")
            let file = AtomicJSONFile<[Entry]>(url: url, maximumBytes: 262_144)
            let entries: [Entry]
            if FileManager.default.fileExists(atPath: url.path) {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw NativeMomentError.unavailableJournal }
                entries = try file.load()
                guard entries.count <= 1_000, Set(entries.map(\.id)).count == entries.count,
                      entries.allSatisfy({ [$0.context, $0.fingerprint] .allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } && ($0.receipt.map { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } ?? true) }) else { throw NativeMomentError.unavailableJournal }
            } else { entries = [] }
            return try body(file, entries)
        }
    }
}
