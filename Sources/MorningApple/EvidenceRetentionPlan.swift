import Foundation
import MorningCore

/// The only places, besides the archive itself, that a plan ever inspects: every
/// part of the saved workspace that holds a routine step. Thoughts, receipts and
/// recording files hold none and are not inspected.
public enum EvidenceRetentionStore: String, Sendable, Equatable, CaseIterable {
    case currentRoutine, previousRoutine, pendingProposal, preferenceJournal
    /// The saved session pins its own copy of the routine it was made from.
    case session
    /// Each saved run pins the whole routine it ran, with every step's text.
    case runHistory
}

public enum EvidenceDependentKind: String, Sendable, Equatable {
    /// A step that still reads its excerpt from the observation.
    case savedMomentStep
    /// A step that carries a source reference but no longer reads the excerpt.
    case routineStepReference
    /// The pending suggestion was built from the observation, quoted or not.
    case proposalSource
    case proposalCitation
    case keptChoiceSnapshot
    /// A step with no source reference whose text repeats words of the observation:
    /// an accepted suggestion's evidence line, or a saved moment turned into a note.
    case unlinkedStepText
}

public enum EvidenceDependentDisposition: String, Sendable, Equatable {
    /// This quoted copy goes with the observation. It names the quotation and its
    /// source reference only, never the step's title, category, timing or position.
    case removed
    /// Nothing the person wrote is deleted, but what relied on the observation no
    /// longer holds: a suggestion must be recalculated, a source link stops resolving.
    case invalidated
    /// Forgetting this observation leaves the copy in place. It is listed so the
    /// person can see it and remove it where it lives.
    case separatelyRetained
}

/// Why a copy gets its disposition. One reason always gives the same disposition.
public enum EvidenceRetentionReason: String, Sendable, Equatable, CaseIterable {
    case approvedQuotation, keptChoice, markedRequired, savedRun, choicesUnavailable, unlinkedMatchingText
    case unapprovedDraftQuotation, reworkedStep
    case suggestionSource, suggestionCitation, insideDiscardedSuggestion

    public var disposition: EvidenceDependentDisposition {
        switch self {
        case .approvedQuotation, .keptChoice, .markedRequired, .savedRun, .choicesUnavailable, .unlinkedMatchingText: .separatelyRetained
        case .unapprovedDraftQuotation: .removed
        case .reworkedStep, .suggestionSource, .suggestionCitation, .insideDiscardedSuggestion: .invalidated
        }
    }

    public var explanation: String {
        switch self {
        case .approvedQuotation:
            AppLanguage.localized("You approved this quotation as part of a routine. It stays as a separate copy until you remove that step, and it can no longer be replayed from its source.", bundle: .module)
        case .keptChoice:
            AppLanguage.localized("You chose to keep this moment. Its quotation stays with that choice until you clear it in Settings → Saved choices.", bundle: .module)
        case .markedRequired:
            AppLanguage.localized("This moment is marked to stay in your routine, so its quotation is kept. It is listed so you can review or remove it.", bundle: .module)
        case .savedRun:
            AppLanguage.localized("This quotation is part of a saved run of your morning. It stays with that run and is listed so you can see it.", bundle: .module)
        case .choicesUnavailable:
            AppLanguage.localized("Your saved choices could not be read, so this quotation is kept until they can be checked.", bundle: .module)
        case .unlinkedMatchingText:
            AppLanguage.localized("This step holds words that match the observation but no link to it, so it is treated as yours and stays. It is listed so you can review or remove it.", bundle: .module)
        case .unapprovedDraftQuotation:
            AppLanguage.localized("This quotation sits unchanged in a draft you have not approved or kept, so it goes with its observation. The step's name and timing are yours and stay.", bundle: .module)
        case .reworkedStep:
            AppLanguage.localized("This step no longer matches its saved excerpt exactly, so its wording is treated as yours and stays. Only its link to the observation stops working.", bundle: .module)
        case .suggestionSource:
            AppLanguage.localized("This pending suggestion was built from the observation and has to be worked out again.", bundle: .module)
        case .suggestionCitation:
            AppLanguage.localized("This pending suggestion quotes the observation. The suggestion is set aside and has to be worked out again.", bundle: .module)
        case .insideDiscardedSuggestion:
            AppLanguage.localized("This copy sits inside a pending suggestion that has to be worked out again. A choice you kept is listed separately.", bundle: .module)
        }
    }
}

/// One copy of an observation's content held outside the archive.
public struct EvidenceDependentCopy: Sendable, Equatable {
    public let acquisitionID: UUID
    public let store: EvidenceRetentionStore
    public let kind: EvidenceDependentKind
    /// The routine step, suggested step or kept choice holding the copy.
    public let stepID: UUID?
    /// The copied words, when the copy holds any.
    public let quote: String?
    public let reason: EvidenceRetentionReason
    public var disposition: EvidenceDependentDisposition { reason.disposition }
}

/// A derived description of what age-based expiry or forgetting one observation
/// would touch. It deletes nothing and is never persisted; the workspace owner
/// applies it. Raw evidence expires. A quotation outlives its observation only
/// where the person approved it in a routine or kept it as a choice, or in the
/// saved record of a morning that ran, and every such copy that carries a source
/// reference is listed. Each ambiguous case is reported as kept, not removed.
///
/// A copy is found by its source reference, or by exact words of an observation
/// still in the archive: a suggestion's evidence line, or a whole line of a step's
/// detail that is a whole line of the observation. A step's name is not searched:
/// names are short and often equal an app or screen label. Words a person retyped
/// or ran into other text, and copies of an observation that already left the
/// archive without a reference, cannot be found without saved provenance. Copies
/// without a reference are therefore listed as far as exact words allow, not proven
/// complete.
public struct EvidenceRetentionPlan: Sendable, Equatable {
    /// Archive order. Older than `maximumAge` by its import date; an entry exactly
    /// at the limit, or imported after `now`, is not expired.
    public let expiredAcquisitionIDs: [UUID]
    /// No import date was saved. These are reported and never expire by age.
    public let unknownAgeAcquisitionIDs: [UUID]
    /// Every copy those stores hold, for every observation they name.
    public let dependentCopies: [EvidenceDependentCopy]
    /// The shortest quotation a suggestion may cite.
    static let minimumEvidenceCharacters = 8

    /// A maximum age that is negative or not finite, or a clock that is not finite,
    /// expires nothing. Pass nil preferences when the saved choices could not be read:
    /// an empty journal means the person keeps nothing, and nil lists nothing for removal.
    public init(archive: ObservationArchive, currentRoutine: RoutineVersion?, previousRoutine: RoutineVersion?,
                session: RoutineSession?, pendingProposal: EvidenceRoutineProposal?,
                preferences: RoutinePreferenceJournal?, history: MorningHistory, now: Date, maximumAge: TimeInterval) {
        let limit = maximumAge.isFinite && maximumAge >= 0 && now.timeIntervalSince1970.isFinite ? maximumAge : nil
        var expired: [UUID] = []
        var unknown: [UUID] = []
        for entry in archive.entries {
            guard let importedAt = entry.importedAt else { unknown.append(entry.id); continue }
            if let limit, now.timeIntervalSince(importedAt) > limit { expired.append(entry.id) }
        }
        expiredAcquisitionIDs = expired
        unknownAgeAcquisitionIDs = unknown

        // Approval and Keep are the two explicit decisions. A draft made by editing an
        // approved routine is unapproved again, so the quotation is matched by its
        // exact reference in any approved version rather than by the draft's flag. A
        // saved run keeps the approved version it ran after that version has rotated out.
        let runRoutines = history.runs.map(\.session.routine)
        let approved = ([currentRoutine, previousRoutine, session?.routine].compactMap { $0 } + runRoutines).filter(\.isApproved)
            .flatMap { $0.steps.compactMap(\.observationReference) }
        let kept = (preferences?.entries ?? []).filter { $0.presence == .keep }
        func explicitDecision(_ step: RoutineStep, _ reference: RoutineObservationReference) -> EvidenceRetentionReason? {
            if approved.contains(reference) { return .approvedQuotation }
            if kept.contains(where: { $0.targetID == step.id || $0.retainedStep?.observationReference == reference }) {
                return .keptChoice
            }
            // The saved choices are the authority, but a required flag without one can be
            // an older choice not yet carried over or a choice that could not be read.
            return step.isRequired ? .markedRequired : nil
        }
        func kind(_ step: RoutineStep) -> EvidenceDependentKind {
            step.automation == .savedObservation ? .savedMomentStep : .routineStepReference
        }

        // Exact words only, against every text layer the archive still holds. An accepted
        // suggestion writes each quotation on its own evidence line; a saved moment
        // turned into a note keeps its excerpt as a whole line.
        let searchable = archive.entries.map { entry in
            let texts = [entry.originalText] + [entry.correctedText].compactMap { $0 }
                + (entry.videoEvidence?.frames.map(\.text) ?? [])
            return (id: entry.id, texts: texts.map { Data($0.utf8) },
                    lines: Set(texts.flatMap { $0.split(whereSeparator: \.isNewline).map { Data($0.utf8) } }))
        }
        func unlinkedMatches(_ step: RoutineStep) -> [(id: UUID, quote: String)] {
            // An evidence line runs from its opening marker to one of the closing marks
            // after it. Words added after the line, or marks inside the quotation, leave
            // several possible ends; the longest one found in the source is the quotation.
            let bytes = Data(step.detail.utf8)
            func offsets(of marker: String) -> [Range<Int>] {
                let pattern = Data(marker.utf8)
                var result: [Range<Int>] = []
                var from = 0
                while let match = bytes.range(of: pattern, in: from..<bytes.count) {
                    result.append(match); from = match.upperBound
                }
                return result
            }
            let newline = Data([0x0A])
            // A detail keeps the label of the language it was written in.
            let starts = EvidenceDetailText.readableLabels.flatMap { offsets(of: "\($0) “") }.map(\.upperBound).sorted()
            let ends = starts.isEmpty ? [] : offsets(of: "”").map(\.lowerBound)
            // Byte-exact throughout: two spellings of the same letters are two quotations.
            var seenLines = Set<Data>()
            let lines = step.detail.split(whereSeparator: \.isNewline).map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && seenLines.insert(Data($0.utf8)).inserted }
            var found: [(id: UUID, quote: String)] = []
            for source in searchable {
                // A step's own reference already lists its quotation for that observation.
                var seen = Set<Data>()
                if let reference = step.observationReference, reference.acquisitionID == source.id {
                    seen.insert(Data(reference.quote.utf8))
                }
                func holds(_ start: Int, _ end: Int) -> Bool {
                    // A copy, not a slice: searching for a one-byte slice traps in Foundation.
                    let quote = Data(bytes[start..<end])
                    return source.texts.contains { $0.range(of: quote) != nil }
                }
                var covered = 0
                for start in starts {
                    guard var low = ends.firstIndex(where: { $0 > start }) else { continue }
                    // Usual case first, without scanning: the evidence line as written
                    // quotes one whole line of the source.
                    let lineEnd = bytes.range(of: newline, in: start..<bytes.count)?.lowerBound ?? bytes.count
                    if let whole = ends.lastIndex(where: { $0 > start && $0 < lineEnd }),
                       source.lines.contains(Data(bytes[start..<ends[whole]])) {
                        low = whole
                    } else {
                        guard holds(start, ends[low]) else { continue }
                    }
                    // If a longer quotation is in the source, every shorter one is too, so
                    // one failed probe just past the line settles the usual case.
                    var high = ends.count - 1
                    if low < high, !holds(start, ends[low + 1]) { high = low }
                    while low < high {
                        let middle = (low + high + 1) / 2
                        if holds(start, ends[middle]) { low = middle } else { high = middle - 1 }
                    }
                    // A suggestion never writes a quotation shorter than this, and a few
                    // typed letters would match almost every observation.
                    let quote = Data(bytes[start..<ends[low]])
                    let words = String(decoding: quote, as: UTF8.self)
                    guard words.count >= Self.minimumEvidenceCharacters else { continue }
                    // A marker inside a quotation already listed adds nothing unless
                    // its own quotation runs past the end of that one.
                    guard ends[low] > covered else { continue }
                    covered = ends[low]
                    if seen.insert(quote).inserted { found.append((source.id, words)) }
                }
                for line in lines where source.lines.contains(Data(line.utf8)) && seen.insert(Data(line.utf8)).inserted {
                    found.append((source.id, line))
                }
            }
            return found
        }

        var copies: [EvidenceDependentCopy] = []
        func addUnlinked(_ step: RoutineStep, in store: EvidenceRetentionStore) {
            for match in unlinkedMatches(step) {
                copies.append(.init(acquisitionID: match.id, store: store, kind: .unlinkedStepText,
                    stepID: step.id, quote: match.quote, reason: .unlinkedMatchingText))
            }
        }
        for (store, routine) in [(EvidenceRetentionStore.currentRoutine, currentRoutine), (.previousRoutine, previousRoutine),
                                 (.session, session?.routine)] {
            for step in routine?.steps ?? [] {
                addUnlinked(step, in: store)
                guard let reference = step.observationReference else { continue }
                // Removal needs proof that the text is still the untouched saved excerpt:
                // the same byte-for-byte check playback uses against the current source.
                // An edited sentence, or a source that changed or is gone, is kept. The
                // excerpt keeps the language it was composed in, whatever the interface is now.
                let untouched = step.automation == .savedObservation
                    && (try? ObservationNarrationComposer.resolve(reference: reference, archive: archive,
                                                                  approvedText: step.detail)) != nil
                copies.append(.init(acquisitionID: reference.acquisitionID, store: store, kind: kind(step),
                    stepID: step.id, quote: reference.quote,
                    reason: explicitDecision(step, reference) ?? (preferences == nil ? .choicesUnavailable
                        : untouched ? .unapprovedDraftQuotation : .reworkedStep)))
            }
        }

        // A run record is history: its copy is never listed for removal. Approval is
        // required to start a morning, but a session stopped before starting is saved too.
        for routine in runRoutines {
            for step in routine.steps {
                addUnlinked(step, in: .runHistory)
                guard let reference = step.observationReference else { continue }
                copies.append(.init(acquisitionID: reference.acquisitionID, store: .runHistory, kind: kind(step),
                    stepID: step.id, quote: reference.quote, reason: explicitDecision(step, reference) ?? .savedRun))
            }
        }

        if let proposal = pendingProposal {
            // The saved suggestion stops being current as soon as one of its sources
            // leaves the archive, whether or not a step quotes that source.
            var sources: [UUID] = []
            for id in proposal.sourceSnapshots.map(\.acquisitionID) + proposal.omissions.map(\.acquisitionID)
                + proposal.support.flatMap({ $0.citations.map(\.acquisitionID) }) where !sources.contains(id) {
                sources.append(id)
            }
            for id in sources {
                copies.append(.init(acquisitionID: id, store: .pendingProposal, kind: .proposalSource,
                    stepID: nil, quote: nil, reason: .suggestionSource))
            }
            for item in proposal.support {
                for citation in item.citations {
                    copies.append(.init(acquisitionID: citation.acquisitionID, store: .pendingProposal,
                        kind: .proposalCitation, stepID: item.stepID, quote: citation.quote, reason: .suggestionCitation))
                }
            }
            // Kept moments are copied into the suggested routine and its saved choices.
            // They stay with the suggestion unless it is being set aside anyway. Words
            // already listed above as a citation of the same step are not repeated.
            func carried(_ step: RoutineStep, as kind: EvidenceDependentKind) {
                for match in unlinkedMatches(step) where !copies.contains(where: {
                    $0.kind == .proposalCitation && $0.stepID == step.id && $0.acquisitionID == match.id
                        && $0.quote?.utf8.elementsEqual(match.quote.utf8) == true
                }) {
                    copies.append(.init(acquisitionID: match.id, store: .pendingProposal, kind: .unlinkedStepText,
                        stepID: step.id, quote: match.quote,
                        reason: sources.contains(match.id) ? .insideDiscardedSuggestion : .unlinkedMatchingText))
                }
                guard let reference = step.observationReference else { return }
                // A suggestion carries a reference only on a row it preserved as the
                // person's decision, and forgetting some other observation leaves it valid.
                let preserved = kind == .keptChoiceSnapshot
                    || proposal.support.contains { $0.stepID == step.id && $0.reason == .preservedUserDecision }
                let reason = sources.contains(reference.acquisitionID) ? .insideDiscardedSuggestion
                    : explicitDecision(step, reference) ?? (preserved ? .keptChoice : .reworkedStep)
                copies.append(.init(acquisitionID: reference.acquisitionID, store: .pendingProposal, kind: kind,
                    stepID: step.id, quote: reference.quote, reason: reason))
            }
            for step in proposal.routine.steps { carried(step, as: kind(step)) }
            for entry in proposal.preferenceSnapshot?.entries ?? [] {
                if let step = entry.retainedStep { carried(step, as: .keptChoiceSnapshot) }
            }
        }

        for entry in kept {
            guard let step = entry.retainedStep else { continue }
            addUnlinked(step, in: .preferenceJournal)
            guard let reference = step.observationReference else { continue }
            copies.append(.init(acquisitionID: reference.acquisitionID, store: .preferenceJournal,
                kind: .keptChoiceSnapshot, stepID: entry.targetID, quote: reference.quote, reason: .keptChoice))
        }
        dependentCopies = copies
    }

    /// For an expired or user-selected observation. Empty when nothing else holds it.
    public func dependents(of acquisitionID: UUID) -> [EvidenceDependentCopy] {
        dependentCopies.filter { $0.acquisitionID == acquisitionID }
    }

    /// True when the pending suggestion was built from this observation. A kept moment
    /// it merely carries does not make it stale.
    public func invalidatesPendingProposal(forgetting acquisitionID: UUID) -> Bool {
        dependents(of: acquisitionID).contains { $0.kind == .proposalSource }
    }
}
