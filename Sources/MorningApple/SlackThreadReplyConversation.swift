import Foundation
import MorningCore
import Observation

public struct SlackReplyActionCounts: Sendable, Equatable {
    public let confirmed: Int
    public let unconfirmed: Int
}

/// One reply to a selected observed message. Nothing here selects a tool or recipient from model output.
@MainActor @Observable public final class SlackThreadReplyConversation {
    public enum Phase: Sendable, Equatable { case idle, preparing, reviewing, awaitingConfirmation, sending, completed, unavailable, uncertain }
    public private(set) var phase: Phase = .idle
    public private(set) var context: MorningExecutionID?
    public private(set) var source: SlackReplySource?
    public private(set) var destination: SlackReplyDestination?
    public private(set) var body = ""
    public private(set) var message = ""
    public private(set) var operationID = UUID()
    public var isActive: Bool { ![.idle, .completed, .unavailable].contains(phase) }
    public var canConfirm: Bool {
        phase == .awaitingConfirmation && reviewedAttempt == attempt &&
            reviewedAt.map { (0..<300).contains(now().timeIntervalSince($0)) } == true && source?.isCurrent(at: now()) == true
    }
    @ObservationIgnored private let provider: any SlackThreadReplyProviding
    @ObservationIgnored private let drafts: SlackReplyDraftService
    @ObservationIgnored private let control: LocalDataControl
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let speak: @MainActor (String) async throws -> Void
    @ObservationIgnored private var attempt = UUID()
    @ObservationIgnored private var reviewedAttempt: UUID?
    @ObservationIgnored private var reviewedAt: Date?
    @ObservationIgnored private var work: Task<Void, Never>?

    public init(provider: any SlackThreadReplyProviding, drafts: SlackReplyDraftService = SlackReplyDraftService(),
                directory: URL = LocalDataControl.defaultDirectory, now: @escaping @MainActor () -> Date = { Date() },
                speak: @escaping @MainActor (String) async throws -> Void) {
        self.provider = provider; self.drafts = drafts; control = LocalDataControl(directory: directory)
        self.now = now; self.speak = speak
    }

    /// The entire utterance is drafting guidance, even when it also contains the word "send".
    public func prepare(intention: String, source: SlackReplySource, context: MorningExecutionID) async {
        guard phase != .sending, phase != .uncertain else { message = SlackReplyError.uncertain.moreDescription; return }
        clear()
        self.context = context; self.source = source; operationID = UUID(); phase = .preparing
        await run { token in
            do {
                try self.check(token)
                guard source.executionID == context else { throw SlackReplyError.unsupportedSource }
                guard try !self.journal.hasPending(context: context, target: self.target(source), generation: source.origin.privacyGeneration) else { throw SlackReplyError.uncertain }
                let destination = try await self.provider.destination(for: source)
                try self.check(token)
                guard destination.connectionID == source.origin.connectionID, destination.channelID == source.channelID else { throw SlackReplyError.accountChanged }
                self.destination = destination
                let body = try await self.drafts.draft(source: source, intention: intention)
                try self.check(token)
                self.body = body
                await self.presentReview(token)
            } catch { self.fail(error, token: token) }
        }
    }

    public func revise(intention: String) async {
        guard let source, destination != nil, phase != .sending, phase != .uncertain, phase != .completed else { return }
        let previous = body
        reviewedAttempt = nil; reviewedAt = nil; phase = .preparing
        await run { token in
            do {
                try self.check(token)
                let body = try await self.drafts.draft(source: source, intention: intention, previousReply: previous)
                try self.check(token)
                self.body = body; self.operationID = UUID()
                await self.presentReview(token)
            } catch { self.fail(error, token: token) }
        }
    }

    /// A local edit immediately revokes the old spoken review.
    public func edit(body: String) {
        guard source != nil, destination != nil, ![.sending, .uncertain, .completed].contains(phase) else { return }
        cancel()
        self.body = String(body.prefix(4_000)); operationID = UUID(); phase = .reviewing
        message = (try? SlackReplyContract.reply(self.body)) == nil ? SlackReplyError.invalidReply.moreDescription : reviewNeeded
    }

    public func review() async {
        guard ![.sending, .uncertain, .completed].contains(phase) else { return }
        reviewedAttempt = nil; reviewedAt = nil
        await run { token in await self.presentReview(token) }
    }

    /// Touch fallback confirms that the complete visible review was read; it is never a send.
    public func acknowledgeScreenReview() {
        do {
            try check(attempt)
            guard phase == .reviewing, try prepared() != nil else { return }
            // A stopped spoken review must not revoke this newer explicit screen review.
            work?.cancel(); work = nil; attempt = UUID()
            reviewedAttempt = attempt; reviewedAt = now(); phase = .awaitingConfirmation
        } catch { fail(error, token: attempt) }
    }

    @discardableResult public func respond(_ text: String, context: MorningExecutionID) async -> Bool {
        guard self.context == context, phase != .idle else { return false }
        if phase == .completed { return true }
        if phase == .sending || phase == .uncertain { message = SlackReplyError.uncertain.moreDescription; return true }
        let words = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if ["repete", "relis", "repeat", "read it again"].contains(words) { await review(); return true }
        guard ["envoie", "envoyer", "envoie la reponse", "send", "send it", "send reply"].contains(words) else { return false }
        guard canConfirm, let reply = try? prepared() else { message = reviewNeeded; return true }
        let id = operationID, generation = reply.source.origin.privacyGeneration, fingerprint = reply.fingerprint
        reviewedAttempt = nil; reviewedAt = nil
        await run { token in
            do {
                try self.check(token)
                try await self.provider.validate(reply)
                try self.check(token)
                guard try self.journal.claim(id: id, context: context, target: self.target(reply.source), fingerprint: fingerprint, generation: generation) else { throw SlackReplyError.uncertain }
                self.phase = .sending
                let receipt: SlackReplyReceipt
                do { receipt = try await self.provider.send(reply, operationID: id) }
                catch SlackReplyDispatchError.notDispatched(let reason) {
                    try self.journal.releaseNotDispatched(id: id, fingerprint: fingerprint, generation: generation)
                    if self.context == context, self.source == reply.source, self.operationID == id, self.phase == .uncertain {
                        self.phase = .reviewing; self.message = reason.moreDescription
                    }
                    try self.check(token)
                    self.phase = .reviewing; self.message = reason.moreDescription
                    return
                }
                // A known effect is durable before narration and survives a changed UI context.
                try self.journal.confirm(id: id, fingerprint: fingerprint, receipt: receipt, generation: generation)
                try self.check(token, requiresFreshSource: false)
                self.phase = .completed
                self.message = AppLanguage.isFrench
                    ? "Réponse publiée dans le fil de #\(reply.destination.channelName), espace \(reply.destination.teamName), avec \(reply.destination.userName). \(reply.body)"
                    : "Reply posted in the #\(reply.destination.channelName) thread, workspace \(reply.destination.teamName), as \(reply.destination.userName). \(reply.body)"
                do { try await self.speak(self.message) } catch { /* Receipt remains confirmed; speech does not authorize another post. */ }
            } catch { self.fail(error, token: token) }
        }
        return true
    }

    public func cancel() {
        work?.cancel(); work = nil; attempt = UUID(); reviewedAttempt = nil; reviewedAt = nil
        if phase == .sending { phase = .uncertain; message = SlackReplyError.uncertain.moreDescription }
        else if ![.completed, .uncertain, .idle].contains(phase) { phase = .reviewing }
    }

    /// Keeps source, draft and durable effect claims; no provider call or spoken review occurs.
    public func appLanguageDidChange() {
        reviewedAttempt = nil; reviewedAt = nil
        if phase == .uncertain || phase == .sending { message = SlackReplyError.uncertain.moreDescription }
        else if phase != .idle {
            if phase != .completed { phase = .reviewing }
            message = phase == .completed
                ? (AppLanguage.isFrench ? "La réponse a été publiée dans Slack." : "The reply was posted in Slack.")
                : reviewNeeded
        }
    }

    /// Call on advance, background, account changes and privacy reset. The journal remains content-free.
    public func clear() {
        cancel(); context = nil; source = nil; destination = nil; body = ""; message = ""; phase = .idle
    }

    /// Content-free effects outlive the volatile panel and never change the read moment's outcome.
    public func actionCounts(for session: RoutineSession, stepID: UUID? = nil) throws -> SlackReplyActionCounts {
        let generation = try control.status().generation
        return try journal.actionCounts(contexts: session.routine.steps.filter { stepID == nil || $0.id == stepID }.map {
            MorningExecutionID(sessionID: session.id, routineVersionID: session.routine.id, stepID: $0.id)
        }, generation: generation)
    }

    private func run(_ operation: @escaping @MainActor (UUID) async -> Void) async {
        work?.cancel()
        let token = UUID(); attempt = token
        let task = Task { @MainActor in await operation(token) }
        work = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if attempt == token { work = nil }
    }

    private func presentReview(_ token: UUID) async {
        do {
            try check(token)
            guard let reply = try prepared() else { throw SlackReplyError.invalidReply }
            try await provider.validate(reply)
            try check(token)
            phase = .reviewing
            message = AppLanguage.isFrench
                ? "Espace \(reply.destination.teamName), compte \(reply.destination.userName), canal #\(reply.destination.channelName). Réponse dans le fil du message : \(reply.source.text). Voici la réponse proposée : \(reply.body). Dites envoie pour la publier, ou corrigez-la."
                : "Workspace \(reply.destination.teamName), account \(reply.destination.userName), channel #\(reply.destination.channelName). Reply in the thread of this message: \(reply.source.text). Proposed reply: \(reply.body). Say send it to post, or revise it."
            try await speak(message)
            try check(token)
            reviewedAttempt = token; reviewedAt = now(); phase = .awaitingConfirmation
        } catch { fail(error, token: token) }
    }

    private func prepared() throws -> SlackPreparedReply? {
        guard let source, let destination, !body.isEmpty else { return nil }
        return try SlackPreparedReply(source: source, destination: destination, body: body)
    }
    private func check(_ token: UUID, requiresFreshSource: Bool = true) throws {
        try Task.checkCancellation()
        guard attempt == token, let source, context == source.executionID,
              !requiresFreshSource || source.isCurrent(at: now()) else { throw SlackReplyError.staleSource }
        try control.withReadyAccess { state in
            guard state.generation == source.origin.privacyGeneration else { throw LocalDataControlError.staleGeneration }
        }
    }
    private func fail(_ error: any Error, token: UUID) {
        guard token == attempt else { return }
        reviewedAttempt = nil; reviewedAt = nil
        if phase == .sending || error as? SlackReplyError == .uncertain { phase = .uncertain; message = SlackReplyError.uncertain.moreDescription }
        else if !(error is CancellationError) { phase = body.isEmpty ? .unavailable : .reviewing; message = (error as? SlackReplyError)?.moreDescription ?? SlackReplyError.unavailable.moreDescription }
    }
    private var journal: SlackReplyJournal { SlackReplyJournal(control: control) }
    private func target(_ source: SlackReplySource) -> String { SlackReplyContract.digest([source.origin.connectionID, source.channelID, source.threadTS]) }
    private var reviewNeeded: String { AppLanguage.isFrench ? "Relisez la réponse complète avant de dire envoie." : "Review the complete reply before saying send it." }
}

/// Only generated IDs and hashes survive; no provider IDs, source text or draft are saved.
struct SlackReplyJournal {
    struct Entry: Codable { let id: UUID; let context: String; let target: String; let fingerprint: String; var receipt: String? }
    let control: LocalDataControl
    func actionCounts(contexts: [MorningExecutionID], generation: UUID?) throws -> SlackReplyActionCounts {
        let keys = Set(contexts.map(key))
        return try access(generation) { _, entries in
            let selected = entries.filter { keys.contains($0.context) }
            return SlackReplyActionCounts(confirmed: selected.filter { $0.receipt != nil }.count,
                unconfirmed: selected.filter { $0.receipt == nil }.count)
        }
    }
    func hasPending(context: MorningExecutionID, target: String, generation: UUID?) throws -> Bool {
        try access(generation) { _, entries in entries.contains { $0.receipt == nil && ($0.context == key(context) || $0.target == target) } }
    }
    func claim(id: UUID, context: MorningExecutionID, target: String, fingerprint: String, generation: UUID?) throws -> Bool {
        try access(generation) { file, entries in
            guard entries.count < 1_000, !entries.contains(where: { $0.id == id || ($0.receipt == nil && ($0.context == key(context) || $0.target == target)) }) else { return false }
            try file.save(entries + [Entry(id: id, context: key(context), target: target, fingerprint: fingerprint)])
            return true
        }
    }
    func confirm(id: UUID, fingerprint: String, receipt: SlackReplyReceipt, generation: UUID?) throws {
        try access(generation) { file, entries in
            guard let i = entries.firstIndex(where: { $0.id == id && $0.fingerprint == fingerprint && $0.receipt == nil }) else { throw SlackReplyError.journalUnavailable }
            var values = entries; values[i].receipt = SlackReplyContract.digest([receipt.channelID, receipt.messageTS]); try file.save(values)
        }
    }
    func releaseNotDispatched(id: UUID, fingerprint: String, generation: UUID?) throws {
        try access(generation) { file, entries in
            guard entries.contains(where: { $0.id == id && $0.fingerprint == fingerprint && $0.receipt == nil }) else { throw SlackReplyError.journalUnavailable }
            try file.save(entries.filter { $0.id != id })
        }
    }
    private func key(_ c: MorningExecutionID) -> String { SlackReplyContract.digest([c.sessionID.uuidString, c.routineVersionID.uuidString, c.stepID.uuidString]) }
    private func access<T>(_ generation: UUID?, _ body: (AtomicJSONFile<[Entry]>, [Entry]) throws -> T) throws -> T {
        try control.withReadyAccess { state in
            guard state.generation == generation else { throw LocalDataControlError.staleGeneration }
            let url = control.directory.appendingPathComponent("slack-reply-journal.json")
            let file = AtomicJSONFile<[Entry]>(url: url, maximumBytes: 262_144)
            let entries: [Entry]
            if FileManager.default.fileExists(atPath: url.path) {
                let attributes = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true else { throw SlackReplyError.journalUnavailable }
                entries = try file.load()
                guard entries.count <= 1_000, Set(entries.map(\.id)).count == entries.count,
                      entries.allSatisfy({ entry in ([entry.context, entry.target, entry.fingerprint] + [entry.receipt].compactMap { $0 }).allSatisfy { $0.count == 64 && $0.allSatisfy(\.isHexDigit) } }) else { throw SlackReplyError.journalUnavailable }
            } else { entries = [] }
            return try body(file, entries)
        }
    }
}
