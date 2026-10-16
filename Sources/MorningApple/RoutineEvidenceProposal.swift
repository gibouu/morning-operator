import CryptoKit
import Foundation
import MorningCore

public enum RoutineEvidenceProposalError: Error, LocalizedError, Sendable, Equatable {
    case invalidSelection, dateRequired, incompatibleSources, unsupportedSource, insufficientEvidence
    case inputBudgetExceeded, outputBudgetExceeded, tooManySteps, invalidCitation, invalidProposal
    /// A recording gave no usable evidence and frames of it were left out because MORE's own
    /// scene was in front. Named apart so that a capture during which the scene never left
    /// the front can be told from one that simply shows nothing usable.
    case ownInterfaceLeftNoEvidence
    case screenTimeSelectionRequired(availableSlots: Int)
    case screenTimePersonalChoicesNeedReview
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: String(localized: "Select one to five different saved observations.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .dateRequired: String(localized: "Assign an observed day to every selected observation first.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .incompatibleSources: String(localized: "Select observations in the same time zone and with the same human or synthetic origin.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .unsupportedSource: String(localized: "This source needs a reviewed written correction before it can support a proposal.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .insufficientEvidence: AppLanguage.isFrench
            ? "Les sources choisies ne contiennent pas encore d’activité utilisable. Relisez les notes ou ajoutez une observation. Les périodes inconnues restent inconnues."
            : "The selected sources do not yet contain usable activity evidence. Review the notes or add an observation. Unknown periods remain unknown."
        case .ownInterfaceLeftNoEvidence: String(localized: "A selected recording has no usable activity evidence. Some of its samples were left out because MORE itself was in front when they were taken. Use your other apps while a recording runs, or choose another observation.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .inputBudgetExceeded: String(localized: "These saved observations exceed the bounded local workload or contain a text unit too large to send safely. Your complete saved source is unchanged; nothing was silently shortened.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .outputBudgetExceeded: String(localized: "The combined suggestion contains more distinct supporting text than can fit in one reviewable plan. Your complete observations are still saved; choose a smaller set of observations. Nothing was silently shortened.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .tooManySteps: String(localized: "This proposal exceeds ten moments, including your kept rituals. Select fewer observations or adjust which rituals to keep. No kept ritual was removed automatically.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .screenTimeSelectionRequired(let slots): String(localized: "This plan has room for \(slots) additional Screen Time app moments. Choose which apps to add in the observation selection. Observed sequences and your kept rituals are retained.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .screenTimePersonalChoicesNeedReview: AppLanguage.isFrench
            ? "Certains choix personnels conservés ne peuvent pas être rapprochés des activités choisies. Relisez-les et confirmez les apps Screen Time de cette suggestion. Aucun choix Garder, Exclure ou de durée n’est modifié."
            : "Some saved personal choices cannot be matched to the selected activities. Review them and confirm the Screen Time apps for this suggestion. No Keep, Exclude or duration choice is changed."
        case .invalidCitation: String(localized: "A proposed step could not be tied to the exact supplied evidence. Your current routine is unchanged.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .invalidProposal: String(localized: "This proposal is incomplete or inconsistent with its saved evidence. Create another proposal.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
    }
}

public enum RoutineEvidenceSourceLayer: String, Codable, Sendable {
    case original, correction, videoFrame, screenTimeAggregate
    public var displayName: String {
        switch self {
        case .original: String(localized: "Original observation", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .correction: String(localized: "Your correction", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .videoFrame: String(localized: "Recorded screen text", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .screenTimeAggregate: AppLanguage.isFrench ? "Agrégat Screen Time" : "Screen Time aggregate"
        }
    }
}

public struct LearningSourceSnapshot: Codable, Equatable, Sendable {
    public let acquisitionID: UUID
    public let sourceRevision: String
    public let sourceLabel: String
    public let observedDate: ObservationObservedDate
    public let origin: ObservationAcquisitionOrigin
    public let sourceLayer: RoutineEvidenceSourceLayer
}

public enum LearningEvidenceOmissionReason: String, Codable, Sendable {
    case unavailableOrTruncatedFrame, unsupportedVisualContext, explicitlyReviewedUnknown
    /// The app recorded that its own scene was in front when this frame was sampled. This
    /// comes from the recording's saved spans, not from the frame's text.
    case ownInterfaceInFront
}

/// A disclosed pre-inference rejection, never a claim that no activity occurred.
public struct LearningEvidenceOmission: Codable, Equatable, Sendable {
    public let acquisitionID: UUID
    public let sampleID: UUID
    public let reason: LearningEvidenceOmissionReason
}

public struct RoutineEvidenceCitation: Codable, Equatable, Sendable {
    public let acquisitionID: UUID
    public let sourceRevision: String
    public let sampleID: UUID?
    public let quote: String
    /// Character offsets into frame.text when sampleID is present, otherwise into the
    /// selected original/corrected acquisition text. Bounds are half-open.
    public let startCharacterOffset: Int
    public let endCharacterOffset: Int
    public let sourceLayer: RoutineEvidenceSourceLayer
}

public enum RoutineProposalSupportReason: String, Codable, Sendable {
    case inferredEvidence, inferredEvidenceWithUserPreference, preservedUserDecision
}

public struct RoutineProposalSupport: Codable, Equatable, Sendable {
    public let stepID: UUID
    public let citations: [RoutineEvidenceCitation]
    public let reason: RoutineProposalSupportReason
    /// Journal target IDs, never invented acquisition or source citations.
    public let preferenceIDs: [UUID]

    fileprivate init(stepID: UUID, citations: [RoutineEvidenceCitation],
                     reason: RoutineProposalSupportReason, preferenceIDs: [UUID] = []) {
        self.stepID = stepID; self.citations = citations; self.reason = reason
        self.preferenceIDs = preferenceIDs
    }
    private enum CodingKeys: String, CodingKey { case stepID, citations, reason, preferenceIDs }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        stepID = try values.decode(UUID.self, forKey: .stepID)
        citations = try values.decode([RoutineEvidenceCitation].self, forKey: .citations)
        reason = try values.decode(RoutineProposalSupportReason.self, forKey: .reason)
        preferenceIDs = try values.decodeIfPresent([UUID].self, forKey: .preferenceIDs) ?? []
    }
}

public struct EvidenceRoutineProposal: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let baseRoutineID: UUID?
    public let baseRoutineRevision: String?
    public let preferenceSnapshot: RoutinePreferenceJournal?
    public let preferenceRevision: String?
    public let routine: RoutineVersion
    public let sourceSnapshots: [LearningSourceSnapshot]
    public let support: [RoutineProposalSupport]
    public let omissions: [LearningEvidenceOmission]
    public let screenTimeSelection: ScreenTimeMomentSelection?

    fileprivate init(base: RoutineVersion?, routine: RoutineVersion, sources: [LearningSourceSnapshot],
                     support: [RoutineProposalSupport], omissions: [LearningEvidenceOmission],
                     preferences: RoutinePreferenceJournal?, screenTimeSelection: ScreenTimeMomentSelection?) throws {
        id = UUID()
        baseRoutineID = base?.id
        baseRoutineRevision = try base.map { try EvidenceRevision.hash($0) }
        preferenceSnapshot = preferences
        preferenceRevision = try preferences.map { try EvidenceRevision.hash($0) }
        self.routine = routine
        sourceSnapshots = sources
        self.support = support
        self.omissions = omissions
        self.screenTimeSelection = screenTimeSelection
        try validateStructure()
    }

    /// Adopting a suggestion is an explicit edit, never delegation. Revalidate
    /// the exact saved evidence and choices before handing it to the draft editor.
    public func draftForEditing(archive: ObservationArchive, baseRoutine: RoutineVersion?,
                                preferences: RoutinePreferenceJournal, session: RoutineSession? = nil) throws -> RoutineVersion {
        guard session?.status != .running, session?.status != .paused,
              isCurrent(archive: archive, baseRoutine: baseRoutine, preferences: preferences) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        var draft = routine
        draft.isApproved = false
        return draft
    }

    /// Checks source bytes/metadata, every base field, and the complete preference journal.
    /// Nil means legacy required-step retention; an explicit empty journal is authoritative.
    /// Store must also invalidate immediately on unsaved edits and cancellation; this method
    /// cannot inspect editor state that has not yet reached the supplied archive.
    public func isCurrent(archive: ObservationArchive, baseRoutine: RoutineVersion?,
                          preferences: RoutinePreferenceJournal? = nil) -> Bool {
        do {
            try validateStructure()
            try preferences?.validate()
            guard preferenceRevision == (try preferences.map { try EvidenceRevision.hash($0) }) else { return false }
            let baseNumber = baseRoutine?.number ?? 0
            guard baseNumber >= 0, baseNumber < Int.max,
                  baseRoutine == nil || baseNumber >= 1,
                  routine.number == baseNumber + 1 else { return false }
            guard baseRoutineID == baseRoutine?.id,
                  baseRoutineRevision == (try baseRoutine.map { try EvidenceRevision.hash($0) }) else { return false }
            var sources: [ObservationAcquisition] = []
            for snapshot in sourceSnapshots {
                guard let entry = archive.entry(id: snapshot.acquisitionID),
                      try LearningEvidencePreparation.snapshot(entry) == snapshot else { return false }
                sources.append(entry)
            }
            // Rebuild eligible units and their exact reviewed frame bindings from
            // the archive; stored proposal actions and support reasons grant nothing.
            // Older native proposals predate the shared selection policy. Ask for
            // a new review instead of selecting with a live restoration-time clock.
            guard !sourceSnapshots.contains(where: { $0.sourceLayer == .screenTimeAggregate }) || screenTimeSelection != nil else { return false }
            let restoredEvidence = try LearningEvidencePreparation.prepare(acquisitions: sources, screenTimeSelection: screenTimeSelection)
            // Rebuild user-owned rows independently of the stored support claims. The
            // authoritative journal suppresses legacy retention, including after a cleared keep.
            // Browser lessons are an ordered native observation, not a model's
            // choice of which segments to retain. Rebuild every candidate before
            // preferences, assigning saved IDs only through exact citations.
            var restoredCitations = Dictionary(uniqueKeysWithValues: support.map { ($0.stepID, $0.citations) })
            var restoredCandidates = try LearningEvidencePreparation.restoredBrowserCandidates(
                evidence: restoredEvidence, proposal: self, citations: &restoredCitations)
            let restoredNativeCandidates = try LearningEvidencePreparation.joiningScreenTime(evidence: restoredEvidence,
                steps: &restoredCandidates, citations: &restoredCitations, preserving: baseRoutine, preferences: preferences,
                restoring: true, recordedOrder: routine.steps.map(\.id))
            let restoredNativeIDs = Set(restoredNativeCandidates.keys)
            let candidate = RoutineVersion(createdAt: routine.createdAt, sourceLabel: routine.sourceLabel,
                steps: restoredCandidates)
            var inherited = Self.inferredDraft(from: candidate, preserving: baseRoutine,
                preferences: preferences, at: routine.createdAt)
            let legacyKept = preferences == nil ? Self.keptSteps(in: baseRoutine) : []
            let legacyKeptIDs = Set(legacyKept.map(\.id))
            for index in inherited.steps.indices where !legacyKeptIDs.contains(inherited.steps[index].id) {
                let citations = support.first { $0.stepID == inherited.steps[index].id }?.citations ?? []
                inherited.steps[index] = LearningEvidencePreparation.applyingReviewedSuggestion(to: inherited.steps[index],
                    citations: citations, evidence: restoredEvidence)
            }
            let reconciled = try (preferences ?? RoutinePreferenceJournal()).reconcile(steps: inherited.steps)
            guard try EvidenceRevision.hash(reconciled.steps) == EvidenceRevision.hash(routine.steps) else { return false }
            let keptIDs = Set(legacyKept.map(\.id)).union(reconciled.retainedStepIDs)
            if baseRoutine?.isSynthetic == true,
               baseRoutine?.steps.contains(where: { keptIDs.contains($0.id) }) == true,
               !routine.isSynthetic { return false }
            if screenTimeSelection?.includedBundleIdentifiers == nil,
               reconciled.steps.contains(where: { restoredNativeIDs.contains($0.id) && !keptIDs.contains($0.id) }),
               try LearningEvidencePreparation.hasUnmatchedPersonalChoices(candidates: restoredCandidates,
                    citations: restoredCitations, nativeCandidates: restoredNativeCandidates,
                    evidence: restoredEvidence, base: baseRoutine, preferences: preferences) {
                return false
            }
            for item in support {
                guard let step = routine.steps.first(where: { $0.id == item.stepID }) else { return false }
                let expectedReason: RoutineProposalSupportReason = keptIDs.contains(step.id) ? .preservedUserDecision
                    : reconciled.durationOverriddenStepIDs.contains(step.id) ? .inferredEvidenceWithUserPreference : .inferredEvidence
                let expectedPreferences = (reconciled.appliedPreferenceIDsByStepID[step.id] ?? []).sorted { $0.uuidString < $1.uuidString }
                guard item.reason == expectedReason, item.preferenceIDs == expectedPreferences else { return false }
                if item.reason != .preservedUserDecision,
                   restoredEvidence.units.contains(where: { $0.screenTimeContext != nil }),
                   item.citations != restoredCitations[item.stepID] { return false }
                if item.reason == .inferredEvidenceWithUserPreference {
                    // Model rows receive fresh IDs at assembly. On restore, an invented
                    // collision with a saved target ID cannot transfer its timing to a
                    // different activity; require the same conservative key as fallback.
                    let titleKey = step.title.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                        .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                    let nativeBaseline = restoredNativeIDs.contains(step.id) && !item.citations.isEmpty &&
                        item.citations.allSatisfy { $0.sourceLayer == .screenTimeAggregate }
                    guard expectedPreferences.allSatisfy({ id in
                        guard let preference = preferences?.entry(targetID: id) else { return false }
                        return preference.presence == nil && preference.durationMinutes == step.durationMinutes
                            && ((nativeBaseline && preference.targetID == step.id) ||
                                (preference.targetKind == step.kind && preference.normalizedTitle == titleKey))
                    }) else { return false }
                }
                if item.reason != .preservedUserDecision {
                    guard !step.isRequired, RoutineExecutionSuggestion.isBoundedSuggestion(step),
                          step.observationReference == nil else { return false }
                    for citation in item.citations {
                        guard let entry = archive.entry(id: citation.acquisitionID),
                              let text = Self.citationSource(citation, entry: entry),
                              EvidenceText.matches(citation.quote, in: text,
                                start: citation.startCharacterOffset, end: citation.endCharacterOffset) else { return false }
                    }
                }
            }
            return true
        } catch { return false }
    }

    fileprivate static func keptSteps(in base: RoutineVersion?) -> [RoutineStep] {
        guard let base, !base.isSynthetic else { return [] }
        return base.steps.filter(\.isRequired)
    }

    /// Nil preserves legacy required flags. A supplied journal is authoritative, even
    /// when empty: clearing Keep must not resurrect a stale required flag in the base.
    fileprivate static func inferredDraft(from candidate: RoutineVersion, preserving base: RoutineVersion?,
                                          preferences: RoutinePreferenceJournal?, at date: Date) -> RoutineVersion {
        let inheritanceBase: RoutineVersion?
        if preferences == nil { inheritanceBase = base }
        else { inheritanceBase = base.map { prior in var copy = prior; copy.steps = []; return copy } }
        return RoutineVersion.inferredDraft(from: candidate, preserving: inheritanceBase, at: date)
    }

    private static func citationSource(_ citation: RoutineEvidenceCitation, entry: ObservationAcquisition) -> String? {
        switch citation.sourceLayer {
        case .correction:
            guard citation.sampleID == nil else { return nil }
            return entry.correctedText
        case .original:
            guard citation.sampleID == nil, entry.correctedText == nil else { return nil }
            return entry.originalText
        case .screenTimeAggregate:
            guard citation.sampleID == nil, entry.correctedText == nil, entry.screenTimeEvidence != nil else { return nil }
            return entry.originalText
        case .videoFrame:
            guard entry.correctedText == nil, let id = citation.sampleID,
                  !entry.frameReviews.contains(where: { $0.sampleID == id && $0.label == nil }),
                  let frame = entry.videoEvidence?.frames.first(where: { $0.id == id }), frame.canSupportIdentity else { return nil }
            return frame.text
        }
    }

    private func validateStructure() throws {
        try preferenceSnapshot?.validate()
        try screenTimeSelection?.validate()
        guard screenTimeSelection == nil || (screenTimeSelection?.referenceDate == routine.createdAt &&
            sourceSnapshots.contains(where: { $0.sourceLayer == .screenTimeAggregate })) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        guard (preferenceSnapshot == nil) == (preferenceRevision == nil),
              preferenceRevision.map(EvidenceRevision.isValid) ?? true,
              preferenceRevision == (try preferenceSnapshot.map { try EvidenceRevision.hash($0) }) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        guard (1...5).contains(sourceSnapshots.count), Set(sourceSnapshots.map(\.acquisitionID)).count == sourceSnapshots.count,
              !routine.isApproved, routine.number >= 1, !routine.sourceLabel.isEmpty, routine.sourceLabel.count <= 256,
              !routine.steps.isEmpty, routine.steps.count <= 10,
              routine.createdAt.timeIntervalSince1970.isFinite,
              Set(routine.steps.map(\.id)).count == routine.steps.count,
              support.count == routine.steps.count, Set(support.map(\.stepID)) == Set(routine.steps.map(\.id)),
              (baseRoutineID == nil) == (baseRoutineRevision == nil),
              baseRoutineRevision.map(EvidenceRevision.isValid) ?? true,
              omissions.count <= 120 else { throw RoutineEvidenceProposalError.invalidProposal }
        let first = sourceSnapshots[0]
        guard first.origin == .human || first.origin == .synthetic,
              sourceSnapshots.allSatisfy({ EvidenceRevision.isValid($0.sourceRevision) && !$0.sourceLabel.isEmpty && $0.sourceLabel.count <= 256 &&
                  $0.origin == first.origin && $0.observedDate.timeZoneIdentifier == first.observedDate.timeZoneIdentifier }) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        if (first.origin == .synthetic || routine.isSynthetic)
            && !routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture") {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        guard omissions.allSatisfy({ omission in sourceSnapshots.contains { $0.acquisitionID == omission.acquisitionID && $0.sourceLayer == .videoFrame } }) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        let preferenceIDs = Set(preferenceSnapshot?.entries.map(\.targetID) ?? [])
        for item in support {
            let inferred = item.reason != .preservedUserDecision
            guard let step = routine.steps.first(where: { $0.id == item.stepID }),
                  !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  step.title.count <= (inferred ? 120 : 2_000),
                  step.detail.count <= LearningEvidencePreparation.maximumDetailCharacters,
                  (1...(item.reason == .inferredEvidence
                        ? (item.citations.allSatisfy({ $0.sourceLayer == .screenTimeAggregate }) ? ScreenTimeRoutineSelection.plannedMinutesRange.upperBound : 60)
                        : RoutineStep.durationMinutesRange.upperBound)).contains(step.durationMinutes),
                  !inferred || (!step.isRequired && RoutineExecutionSuggestion.isBoundedSuggestion(step) && step.observationReference == nil),
                  item.citations.count <= LearningEvidencePreparation.maximumCitationsPerStep,
                  item.preferenceIDs.count <= 100,
                  Set(item.preferenceIDs).count == item.preferenceIDs.count,
                  Set(item.preferenceIDs).isSubset(of: preferenceIDs),
                  item.reason != .inferredEvidence || item.preferenceIDs.isEmpty,
                  item.reason != .inferredEvidenceWithUserPreference || !item.preferenceIDs.isEmpty,
                  (item.reason == .preservedUserDecision) == item.citations.isEmpty,
                  // The retained quotations must be the section the app itself wrote at the
                  // end of the detail, never a look-alike inside the model's description.
                  item.citations.isEmpty || EvidenceDetailText.description(of: step.detail,
                      citing: item.citations.map(\.quote)) != nil else {
                throw RoutineEvidenceProposalError.invalidProposal
            }
            for citation in item.citations {
                guard let snapshot = sourceSnapshots.first(where: { $0.acquisitionID == citation.acquisitionID }),
                      snapshot.sourceRevision == citation.sourceRevision, snapshot.sourceLayer == citation.sourceLayer,
                      (citation.sampleID != nil) == (citation.sourceLayer == .videoFrame),
                      (8...240).contains(citation.quote.count), citation.startCharacterOffset >= 0,
                      citation.endCharacterOffset >= citation.startCharacterOffset,
                      citation.endCharacterOffset <= ObservationArchive.maximumOriginalTextCharacters,
                      citation.endCharacterOffset - citation.startCharacterOffset == citation.quote.count else {
                    throw RoutineEvidenceProposalError.invalidProposal
                }
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, baseRoutineID, baseRoutineRevision, preferenceSnapshot, preferenceRevision
        case routine, sourceSnapshots, support, omissions, screenTimeSelection
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        baseRoutineID = try values.decodeIfPresent(UUID.self, forKey: .baseRoutineID)
        baseRoutineRevision = try values.decodeIfPresent(String.self, forKey: .baseRoutineRevision)
        let snapshot = try values.decodeIfPresent(RoutinePreferenceJournal.self, forKey: .preferenceSnapshot)
        let revision = try values.decodeIfPresent(String.self, forKey: .preferenceRevision)
        guard (snapshot == nil) == (revision == nil) else { throw RoutineEvidenceProposalError.invalidProposal }
        preferenceSnapshot = snapshot
        preferenceRevision = revision
        // A step refuses planned minutes outside its range when read; for a saved
        // suggestion that is the same damage as any other value outside its bounds.
        do { routine = try values.decode(RoutineVersion.self, forKey: .routine) }
        catch { throw RoutineEvidenceProposalError.invalidProposal }
        sourceSnapshots = try values.decode([LearningSourceSnapshot].self, forKey: .sourceSnapshots)
        support = try values.decode([RoutineProposalSupport].self, forKey: .support)
        omissions = try values.decodeIfPresent([LearningEvidenceOmission].self, forKey: .omissions) ?? []
        screenTimeSelection = try values.decodeIfPresent(ScreenTimeMomentSelection.self, forKey: .screenTimeSelection)
        try validateStructure()
    }
}

/// A user assertion about visible context, separate from original OCR and from
/// a report that an action occurred. It never becomes a citation source layer.
public struct PreparedLearningReviewedContext: Equatable, Sendable {
    public let label: String
    public let evidenceQuote: String
    public let reviewedAt: Date
}

/// Exact, bounded submitted text. Unit identity is local to one preparation, never guessed
/// from a date, label or matching quote. The full source context is retained only in memory.
public struct PreparedLearningEvidenceUnit: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let acquisitionID: UUID
    public let text: String
    public let sourceLayer: RoutineEvidenceSourceLayer
    public let sampleID: UUID?
    public let startCharacterOffset: Int
    public let reviewedContext: PreparedLearningReviewedContext?
    fileprivate let context: String
    var kind: LearningEvidenceKind { sourceLayer == .videoFrame ? .visibleTaskContent : evidenceKind }
    /// Offer only excerpts that already meet the same policy as final citations.
    /// Noncitable text remains source context; this never grants action authority.
    func supportsCitation(_ quote: String) -> Bool {
        LearningEvidencePolicy.supports(quote: quote, source: text, context: context,
            kind: kind, claimedKind: kind.rawValue)
    }
    fileprivate let evidenceKind: LearningEvidenceKind
    fileprivate let browserContext: PreparedBrowserLearningContext?
    fileprivate var screenTimeContext: PreparedScreenTimeContext? = nil
}

fileprivate struct PreparedScreenTimeContext: Equatable, Sendable {
    let report: ScreenTimeObservationEvidence
    let appIndex: Int
    let french: Bool
    var app: ScreenTimeObservationEvidence.App { report.apps[appIndex] }
}

fileprivate struct PreparedBrowserLearningContext: Equatable, Sendable {
    let trace: BrowserLearningTrace
    let segmentIndex: Int
    let french: Bool
}

fileprivate struct PreparedBrowserLessonGroup {
    var segmentUnits: [[PreparedLearningEvidenceUnit]]
    var acquisitionIDs: Set<UUID> { Set(segmentUnits.flatMap { $0.map(\.acquisitionID) }) }
}

public struct PreparedLearningEvidence: Equatable, Sendable {
    public let sourceSnapshots: [LearningSourceSnapshot]
    public let units: [PreparedLearningEvidenceUnit]
    public let omissions: [LearningEvidenceOmission]
    public let submittedCharacterCount: Int
    public let screenTimeSelection: ScreenTimeMomentSelection?
    public var modelRequestCount: Int { batches.count }
    /// Native categories need no generative interpretation. This can be proposed
    /// locally even when the optional on-device language model is unavailable.
    public var hasOnlyBrowserLessons: Bool { !units.isEmpty && units.allSatisfy { $0.browserContext != nil } }
    public var hasOnlyStructuredEvidence: Bool {
        !units.isEmpty && units.allSatisfy { $0.browserContext != nil || $0.screenTimeContext != nil }
    }
    let batches: [[PreparedLearningEvidenceUnit]]
    let prompts: [String]
}

public struct RoutineEvidenceCitationInput: Equatable, Sendable {
    public let unitID: UUID
    public let quote: String
    public init(unitID: UUID, quote: String) { self.unitID = unitID; self.quote = quote }
}

public struct EvidenceRoutineStepInput: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let kind: StepKind
    public let durationMinutes: Int
    public let citations: [RoutineEvidenceCitationInput]
    public init(title: String, detail: String, kind: StepKind, durationMinutes: Int,
                citations: [RoutineEvidenceCitationInput]) {
        self.title = title; self.detail = detail; self.kind = kind
        self.durationMinutes = durationMinutes; self.citations = citations
    }
}

public enum LearningEvidencePreparation {
    /// A confirmation belongs to these exact source bytes and personal choices.
    /// The view uses this only to discard stale local selection, never as authority.
    public static func screenTimeSelectionReviewRevision(acquisitions: [ObservationAcquisition],
        routine: RoutineVersion?, preferences: RoutinePreferenceJournal) throws -> String {
        var revisions = try acquisitions.map { try $0.id.uuidString + ":" + EvidenceRevision.source($0) }
        revisions.append(try EvidenceRevision.hash(preferences))
        revisions.append(try routine.map { try EvidenceRevision.hash($0) } ?? "no-routine")
        return try EvidenceRevision.hash(revisions)
    }

    // Work is bounded by the existing 1–5 saved acquisitions, not by an 8k
    // whole-morning cutoff. Requests remain small, sequential, and cancellable.
    public static let maximumModelCalls = 768
    public static let maximumBatchCharacters = 1_500
    public static let maximumBatchUTF8Bytes = 6_000
    public static let maximumSubmittedCharacters = maximumModelCalls * maximumBatchCharacters
    public static let maximumCitationsPerStep = 512
    public static let maximumDetailCharacters = 32_000
    private static let maximumUnitCharacters = 1_100
    private static let maximumUnitUTF8Bytes = 3_000

    /// `ownInterfaceMarginSeconds` widens each span in which MORE was in front; see
    /// `OwnInterfaceIntervals`. Only a native recording that saved such spans is affected.
    public static func prepare(acquisitions: [ObservationAcquisition],
                               ownInterfaceMarginSeconds: Double = OwnInterfaceIntervals.defaultMarginSeconds,
                               screenTimeSelection: ScreenTimeMomentSelection? = nil)
        throws -> PreparedLearningEvidence {
        guard (1...5).contains(acquisitions.count), Set(acquisitions.map(\.id)).count == acquisitions.count else {
            throw RoutineEvidenceProposalError.invalidSelection
        }
        let sources = try acquisitions.map(snapshot)
        let first = sources[0]
        guard first.origin == .human || first.origin == .synthetic,
              sources.allSatisfy({ $0.origin == first.origin && $0.observedDate.timeZoneIdentifier == first.observedDate.timeZoneIdentifier }) else {
            throw RoutineEvidenceProposalError.incompatibleSources
        }
        let digests = acquisitions.compactMap(\.fileSHA256)
        guard Set(digests).count == digests.count else { throw RoutineEvidenceProposalError.invalidSelection }
        let reportKeys = acquisitions.compactMap { $0.screenTimeEvidence?.sourceKey }
        guard Set(reportKeys).count == reportKeys.count else { throw RoutineEvidenceProposalError.invalidSelection }
        let hasNativeReport = acquisitions.contains { $0.correctedText == nil && $0.screenTimeEvidence != nil }
        guard hasNativeReport || screenTimeSelection == nil else { throw RoutineEvidenceProposalError.invalidSelection }
        let appSelection = hasNativeReport ? try (screenTimeSelection ?? ScreenTimeMomentSelection(referenceDate: Date())) : nil
        try appSelection?.validate(acquisitions: acquisitions)
        var units: [PreparedLearningEvidenceUnit] = []
        var omissions: [LearningEvidenceOmission] = []
        for entry in acquisitions {
            let previousCount = units.count
            if let correction = entry.correctedText {
                guard LearningEvidencePolicy.isEligibleWrittenContext(correction) else { throw RoutineEvidenceProposalError.insufficientEvidence }
                units += try makeUnits(text: correction, entry: entry, layer: .correction, sampleID: nil, kind: .userReportedActivity)
            } else if let report = entry.screenTimeEvidence {
                let french = entry.originalText.utf8.elementsEqual(report.renderedText(french: true).utf8)
                for index in report.apps.indices {
                    let text = report.appText(at: index, french: french)
                    guard let range = EvidenceText.exactRange(of: text, in: entry.originalText), text.count <= 240 else {
                        throw RoutineEvidenceProposalError.invalidCitation
                    }
                    units.append(.init(id: UUID(), acquisitionID: entry.id, text: text, sourceLayer: .screenTimeAggregate,
                        sampleID: nil, startCharacterOffset: range.lowerBound, reviewedContext: nil,
                        context: entry.originalText, evidenceKind: .aggregateAppUsage, browserContext: nil,
                        screenTimeContext: .init(report: report, appIndex: index, french: french)))
                }
            } else if let trace = entry.browserLearning {
                let french = entry.originalText.utf8.elementsEqual(trace.renderedText(french: true).utf8)
                for index in trace.segments.indices {
                    let text = trace.segmentText(at: index, french: french)
                    guard let range = EvidenceText.exactRange(of: text, in: entry.originalText) else {
                        throw RoutineEvidenceProposalError.invalidCitation
                    }
                    units.append(.init(id: UUID(), acquisitionID: entry.id, text: text, sourceLayer: .original,
                        sampleID: nil, startCharacterOffset: range.lowerBound, reviewedContext: nil,
                        context: entry.originalText, evidenceKind: .userReportedActivity,
                        browserContext: .init(trace: trace, segmentIndex: index, french: french)))
                }
            } else if let video = entry.videoEvidence {
                // Imported files and older recordings carry no spans and are judged by text alone.
                let ownInterface = entry.recordingContext?.ownInterfaceIntervals
                for frame in video.frames {
                    let review = entry.frameReviews.first { $0.sampleID == frame.id }
                    if let review, review.label == nil {
                        omissions.append(.init(acquisitionID: entry.id, sampleID: frame.id, reason: .explicitlyReviewedUnknown)); continue
                    }
                    // Decided before reading the frame: the fact holds whatever its text says.
                    if let ownInterface, ownInterface.contains(mediaSeconds: frame.timeSeconds,
                                                              marginSeconds: ownInterfaceMarginSeconds) {
                        omissions.append(.init(acquisitionID: entry.id, sampleID: frame.id, reason: .ownInterfaceInFront)); continue
                    }
                    guard frame.canSupportIdentity else {
                        omissions.append(.init(acquisitionID: entry.id, sampleID: frame.id, reason: .unavailableOrTruncatedFrame)); continue
                    }
                    guard LearningEvidencePolicy.isEligibleVisualContext(frame.text) else {
                        omissions.append(.init(acquisitionID: entry.id, sampleID: frame.id, reason: .unsupportedVisualContext)); continue
                    }
                    let reviewedContext = review.flatMap { review -> PreparedLearningReviewedContext? in
                        guard let label = review.label, let quote = review.evidenceQuote else { return nil }
                        return .init(label: label, evidenceQuote: quote, reviewedAt: review.reviewedAt)
                    }
                    units += try makeUnits(text: frame.text, entry: entry, layer: .videoFrame, sampleID: frame.id,
                        kind: .visibleTaskContent, reviewedContext: reviewedContext)
                }
            } else {
                let kind: LearningEvidenceKind
                switch entry.sourceKind {
                case .text, .manual: kind = .userReportedActivity
                case .image: kind = .visibleTaskContent
                case .video, .screenTime, .unknown: throw RoutineEvidenceProposalError.unsupportedSource
                }
                var text = entry.originalText
                var sourceOffset = 0
                let screenshotHeader = LearningEvidencePolicy.screenshotHeader
                if entry.sourceKind == .image, text.hasPrefix(screenshotHeader) {
                    text = String(text.dropFirst(screenshotHeader.count))
                    sourceOffset = screenshotHeader.count
                }
                let valid = kind == .userReportedActivity ? LearningEvidencePolicy.isEligibleWrittenContext(text)
                    : LearningEvidencePolicy.isEligibleVisualContext(text)
                guard valid else { throw RoutineEvidenceProposalError.insufficientEvidence }
                units += try makeUnits(text: text, entry: entry, layer: .original, sampleID: nil, kind: kind, startingOffset: sourceOffset)
            }
            guard units.count > previousCount || (entry.correctedText == nil && entry.screenTimeEvidence != nil) else {
                let byTime = omissions.contains { $0.acquisitionID == entry.id && $0.reason == .ownInterfaceInFront }
                throw byTime ? RoutineEvidenceProposalError.ownInterfaceLeftNoEvidence : RoutineEvidenceProposalError.insufficientEvidence
            }
        }
        // No cross-day deduplication. Even identical text keeps independent source IDs.
        // Every eligible source character is retained. Both request limits include identifiers and review metadata.
        var batches: [[PreparedLearningEvidenceUnit]] = []
        var current: [PreparedLearningEvidenceUnit] = []
        guard !units.isEmpty else { throw RoutineEvidenceProposalError.insufficientEvidence }
        for unit in units where unit.screenTimeContext == nil {
            if !fitsRequest(prompt(current + [unit])), !current.isEmpty {
                batches.append(current); current = []
            }
            current.append(unit)
            guard fitsRequest(prompt(current)) else { throw RoutineEvidenceProposalError.inputBudgetExceeded }
        }
        if !current.isEmpty { batches.append(current) }
        let prompts = batches.map(prompt)
        let count = prompts.reduce(0) { $0 + $1.count }
        guard batches.count <= maximumModelCalls, count <= maximumSubmittedCharacters else {
            throw RoutineEvidenceProposalError.inputBudgetExceeded
        }
        return PreparedLearningEvidence(sourceSnapshots: sources, units: units, omissions: omissions,
            submittedCharacterCount: count, screenTimeSelection: appSelection, batches: batches, prompts: prompts)
    }

    /// The same deterministic gate is used for model output and explicitly labeled UI fixtures.
    /// It validates provenance; it does not prove the model's semantic interpretation is true.
    public static func assemble(evidence: PreparedLearningEvidence, steps: [EvidenceRoutineStepInput],
                                preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal? = nil,
                                at date: Date = Date()) throws -> EvidenceRoutineProposal {
        try preferences?.validate()
        guard (!steps.isEmpty || evidence.units.contains(where: { $0.browserContext != nil || $0.screenTimeContext != nil })), steps.count <= maximumModelCalls * 4,
              date.timeIntervalSince1970.isFinite else {
            throw RoutineEvidenceProposalError.insufficientEvidence
        }
        if let base {
            guard base.number >= 1, base.number < Int.max else { throw RoutineEvidenceProposalError.invalidProposal }
        }
        var proposed: [RoutineStep] = []
        var citationsByStep: [UUID: [RoutineEvidenceCitation]] = [:]
        var keyIndexes: [String: Int] = [:]
        let browserGroups = browserLessonGroups(evidence: evidence)
        let browserSources = browserGroups.reduce(into: Set<UUID>()) { $0.formUnion($1.acquisitionIDs) }
        let browserSteps = try browserGroups.map { group in try group.segmentUnits.map { try browserCandidate(units: $0) } }
        var insertedBrowserGroups = Set<Int>()
        func insertBrowserGroup(_ index: Int) throws {
            guard insertedBrowserGroups.insert(index).inserted else { return }
            for (segment, step) in browserSteps[index].enumerated() {
                proposed.append(step)
                citationsByStep[step.id] = try browserGroups[index].segmentUnits[segment].map {
                    try browserCitation(unit: $0, evidence: evidence)
                }
            }
        }
        for input in steps {
            let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = input.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 120, detail.count <= 500, (1...60).contains(input.durationMinutes),
                  (1...24).contains(input.citations.count) else { throw RoutineEvidenceProposalError.invalidProposal }
            var citations: [RoutineEvidenceCitation] = []
            for inputCitation in input.citations {
                guard let unit = evidence.units.first(where: { $0.id == inputCitation.unitID }), unit.screenTimeContext == nil,
                      let snapshot = evidence.sourceSnapshots.first(where: { $0.acquisitionID == unit.acquisitionID }),
                      (8...240).contains(inputCitation.quote.count),
                      let range = EvidenceText.exactRange(of: inputCitation.quote, in: unit.text),
                      LearningEvidencePolicy.supports(quote: inputCitation.quote, source: unit.text, context: unit.context,
                          kind: unit.kind, claimedKind: unit.kind.rawValue) else {
                    throw RoutineEvidenceProposalError.invalidCitation
                }
                let citation = RoutineEvidenceCitation(acquisitionID: unit.acquisitionID, sourceRevision: snapshot.sourceRevision,
                    sampleID: unit.sampleID, quote: inputCitation.quote,
                    startCharacterOffset: unit.startCharacterOffset + range.lowerBound,
                    endCharacterOffset: unit.startCharacterOffset + range.upperBound, sourceLayer: unit.sourceLayer)
                if !citations.contains(citation) { citations.append(citation) }
            }
            let browserAnchors = browserGroups.indices.filter { index in
                citations.contains { browserGroups[index].acquisitionIDs.contains($0.acquisitionID) }
            }
            citations.removeAll { browserSources.contains($0.acquisitionID) }
            // Preserve the model's position among other sources, but put each
            // entire native lesson in its observed order at its first citation.
            if citations.isEmpty {
                for index in browserAnchors { try insertBrowserGroup(index) }
                continue
            }
            let key = input.kind.rawValue + ":" + ObservationText.normalized(title)
            if let index = keyIndexes[key] {
                let id = proposed[index].id
                var existing = citationsByStep[id] ?? []
                for citation in citations where !existing.contains(citation) { existing.append(citation) }
                guard existing.count <= maximumCitationsPerStep else { throw RoutineEvidenceProposalError.outputBudgetExceeded }
                citationsByStep[id] = existing
            } else {
                let step = RoutineStep(title: title,
                    detail: detail + "\n" + EvidenceDetailText.tentativeNote,
                    kind: input.kind, durationMinutes: input.durationMinutes)
                keyIndexes[key] = proposed.count
                proposed.append(step); citationsByStep[step.id] = citations
            }
            for index in browserAnchors { try insertBrowserGroup(index) }
        }
        for index in browserGroups.indices { try insertBrowserGroup(index) }
        let nativeCandidates = try joiningScreenTime(evidence: evidence, steps: &proposed, citations: &citationsByStep,
            preserving: base, preferences: preferences)
        let screenTimeBaselineIDs = Set(nativeCandidates.keys)
        // Pending receipts hold structured provenance. Keep bounded, exact quotations in
        // the routine too, so explicit approval does not erase the established source text.
        for index in proposed.indices {
            if EvidenceDetailText.description(of: proposed[index].detail,
                citing: (citationsByStep[proposed[index].id] ?? []).map(\.quote)) != nil { continue }
            var seenQuotes = Set<Data>()
            let quotes = (citationsByStep[proposed[index].id] ?? []).compactMap { citation -> String? in
                seenQuotes.insert(Data(citation.quote.utf8)).inserted ? citation.quote : nil
            }
            proposed[index].detail += "\n" + quotes.map(EvidenceDetailText.line).joined(separator: "\n")
            guard proposed[index].detail.count <= maximumDetailCharacters else { throw RoutineEvidenceProposalError.outputBudgetExceeded }
        }
        let synthetic = evidence.sourceSnapshots.first?.origin == .synthetic
        let source = synthetic ? "Demo fixture — synthetic saved observations" : String(localized: "Selected saved observations — tentative proposal", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        let proposalDate = evidence.screenTimeSelection?.referenceDate ?? date
        let candidate = RoutineVersion(createdAt: proposalDate, sourceLabel: source, steps: proposed, isApproved: false)
        var routine = EvidenceRoutineProposal.inferredDraft(from: candidate, preserving: base,
            preferences: preferences, at: proposalDate)
        let legacyKept = preferences == nil ? EvidenceRoutineProposal.keptSteps(in: base) : []
        let legacyKeptIDs = Set(legacyKept.map(\.id))
        // Identity comes only from every cited unit's explicit reviewed frame
        // context. Enrich the sanitized draft before applying the person's choices.
        // A retained legacy ritual already belongs to the person, even when its
        // stable native ID also has fresh citations. Do not sanitize it again.
        for index in routine.steps.indices where !legacyKeptIDs.contains(routine.steps[index].id) {
            guard let citations = citationsByStep[routine.steps[index].id] else { continue }
            routine.steps[index] = applyingReviewedSuggestion(to: routine.steps[index], citations: citations, evidence: evidence)
        }
        let reconciled = try (preferences ?? RoutinePreferenceJournal()).reconcile(steps: routine.steps)
        routine.steps = reconciled.steps
        let keptIDs = legacyKeptIDs.union(reconciled.retainedStepIDs)
        // An explicit Keep may reintroduce a synthetic excerpt even when every
        // newly selected source is personal. Preserve that provenance on the
        // whole plan before approval, export or run aggregation can use it.
        let keptFromSyntheticBase = base?.isSynthetic == true && (base?.steps.contains { keptIDs.contains($0.id) } ?? false)
        if (routine.isSynthetic || keptFromSyntheticBase) && !routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture") {
            routine.sourceLabel = String(localized: "Demo fixture — includes a synthetic saved observation", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
        guard !routine.steps.isEmpty else { throw RoutineEvidenceProposalError.insufficientEvidence }
        let optionalAppCount = routine.steps.filter { screenTimeBaselineIDs.contains($0.id) && !keptIDs.contains($0.id) }.count
        let mandatoryCount = routine.steps.count - optionalAppCount
        guard mandatoryCount <= 10 else { throw RoutineEvidenceProposalError.tooManySteps }
        let available = min(ScreenTimeRoutineSelection.maximumSuggestedApps, 10 - mandatoryCount)
        if optionalAppCount > available { throw RoutineEvidenceProposalError.screenTimeSelectionRequired(availableSlots: available) }
        if optionalAppCount > 0, evidence.screenTimeSelection?.includedBundleIdentifiers == nil,
           try hasUnmatchedPersonalChoices(candidates: proposed, citations: citationsByStep,
                nativeCandidates: nativeCandidates, evidence: evidence, base: base, preferences: preferences) {
            throw RoutineEvidenceProposalError.screenTimePersonalChoicesNeedReview
        }
        guard routine.steps.count <= 10 else { throw RoutineEvidenceProposalError.tooManySteps }
        let support = try routine.steps.map { step -> RoutineProposalSupport in
            let preferenceIDs = (reconciled.appliedPreferenceIDsByStepID[step.id] ?? []).sorted { $0.uuidString < $1.uuidString }
            if keptIDs.contains(step.id) {
                return .init(stepID: step.id, citations: [], reason: .preservedUserDecision, preferenceIDs: preferenceIDs)
            }
            guard let citations = citationsByStep[step.id], !citations.isEmpty else { throw RoutineEvidenceProposalError.invalidProposal }
            let reason: RoutineProposalSupportReason = reconciled.durationOverriddenStepIDs.contains(step.id)
                ? .inferredEvidenceWithUserPreference : .inferredEvidence
            return .init(stepID: step.id, citations: citations, reason: reason, preferenceIDs: preferenceIDs)
        }
        return try EvidenceRoutineProposal(base: base, routine: routine, sources: evidence.sourceSnapshots,
            support: support, omissions: evidence.omissions, preferences: preferences, screenTimeSelection: evidence.screenTimeSelection)
    }

    /// Compare with source-backed candidates before Keep reinsertion. A retained
    /// ritual cannot supply its own evidence that an old renamed choice matched.
    fileprivate static func hasUnmatchedPersonalChoices(candidates: [RoutineStep],
        citations: [UUID: [RoutineEvidenceCitation]], nativeCandidates: [UUID: RoutineStep], evidence: PreparedLearningEvidence,
        base: RoutineVersion?, preferences: RoutinePreferenceJournal?) throws -> Bool {
        let legacyKept = preferences == nil ? EvidenceRoutineProposal.keptSteps(in: base) : []
        let candidates = try candidates.filter { step in
            let source = citations[step.id] ?? []
            guard !source.isEmpty else { return false }
            // Native candidates can be reconstructed even after Keep replaces
            // their wording. A model/video row loses its citations on Keep; ask
            // for explicit app review now rather than trusting that row later.
            if source.allSatisfy({ $0.sourceLayer == .screenTimeAggregate || browserUnit(for: $0, evidence: evidence) != nil }) {
                return true
            }
            if let preferences { return try preferences.matchingPreference(for: step)?.presence == nil }
            return !legacyKept.contains { $0.id == step.id || RoutineVersion.matchesActivity($0, step) }
        }
        let sourced = candidates.filter { nativeCandidates[$0.id] == nil } + Array(nativeCandidates.values)
        if let preferences {
            let matched = Set(try sourced.compactMap { try preferences.matchingPreference(for: $0)?.id })
            return preferences.entries.contains { !matched.contains($0.id) }
        }
        return legacyKept.contains { kept in
            if sourced.contains(where: { $0.id == kept.id }) { return false }
            return sourced.filter { RoutineVersion.matchesActivity($0, kept) }.count != 1 ||
                (base?.steps.filter { RoutineVersion.matchesActivity($0, kept) }.count ?? 0) != 1
        }
    }

    fileprivate static func applyingReviewedSuggestion(to step: RoutineStep,
        citations: [RoutineEvidenceCitation], evidence: PreparedLearningEvidence) -> RoutineStep {
        let manual = RoutineExecutionSuggestion.applying(to: step, bundleIdentifier: nil)
        let citations = citations.filter { $0.sourceLayer != .screenTimeAggregate }
        guard !citations.isEmpty else { return manual }
        let browserUnits = citations.compactMap { browserUnit(for: $0, evidence: evidence) }
        if browserUnits.count == citations.count, let context = browserUnits.first?.browserContext,
           browserUnits.allSatisfy({ $0.browserContext == context }) {
            return context.trace.applying(to: manual, segment: context.segmentIndex)
        }
        var exactLabel: String?
        for citation in citations {
            guard citation.sourceLayer == .videoFrame, let sampleID = citation.sampleID,
                  let snapshot = evidence.sourceSnapshots.first(where: { $0.acquisitionID == citation.acquisitionID }),
                  snapshot.sourceRevision == citation.sourceRevision,
                  let unit = evidence.units.first(where: {
                      $0.acquisitionID == citation.acquisitionID && $0.sampleID == sampleID && $0.sourceLayer == .videoFrame &&
                      citation.startCharacterOffset >= $0.startCharacterOffset &&
                      citation.endCharacterOffset <= $0.startCharacterOffset + $0.text.count
                  }),
                  EvidenceText.matches(citation.quote, in: unit.text,
                    start: citation.startCharacterOffset - unit.startCharacterOffset,
                    end: citation.endCharacterOffset - unit.startCharacterOffset),
                  let reviewed = unit.reviewedContext,
                  Data(unit.context.utf8).range(of: Data(reviewed.evidenceQuote.utf8)) != nil else { return manual }
            if let exactLabel {
                guard exactLabel.utf8.elementsEqual(reviewed.label.utf8) else { return manual }
            } else { exactLabel = reviewed.label }
        }
        guard let exactLabel else { return manual }
        return RoutineExecutionSuggestion.applyingReviewedLabel(to: manual, label: exactLabel)
    }

    private static func browserCitation(unit: PreparedLearningEvidenceUnit,
        evidence: PreparedLearningEvidence) throws -> RoutineEvidenceCitation {
        guard unit.browserContext != nil,
              let snapshot = evidence.sourceSnapshots.first(where: { $0.acquisitionID == unit.acquisitionID }) else {
            throw RoutineEvidenceProposalError.invalidCitation
        }
        return .init(acquisitionID: unit.acquisitionID, sourceRevision: snapshot.sourceRevision,
            sampleID: nil, quote: unit.text, startCharacterOffset: unit.startCharacterOffset,
            endCharacterOffset: unit.startCharacterOffset + unit.text.count, sourceLayer: .original)
    }

    private static func browserUnit(for citation: RoutineEvidenceCitation,
        evidence: PreparedLearningEvidence) -> PreparedLearningEvidenceUnit? {
        evidence.units.first { unit in
            unit.browserContext != nil && (try? browserCitation(unit: unit, evidence: evidence)) == citation
        }
    }

    private static func browserCandidate(units: [PreparedLearningEvidenceUnit], id: UUID = UUID()) throws -> RoutineStep {
        guard let unit = units.first, let context = unit.browserContext,
              units.allSatisfy({ $0.browserContext == context && $0.text == unit.text }) else {
            throw RoutineEvidenceProposalError.invalidProposal
        }
        let segment = context.trace.segments[context.segmentIndex]
        let minutes = max(1, Int(((segment.endSeconds - segment.startSeconds) / 60).rounded(.up)))
        let note = context.french
            ? "Couverture partielle de gestes observés, sans contenu de page ni preuve d’attention continue. Durée proposée arrondie à la minute, à ajuster avant validation. Likes désactivés."
            : "Partial coverage of observed gestures, without page content or proof of continuous attention. Suggested duration rounded up to a minute; adjust before approval. Likes disabled."
        let multiple = units.count > 1 ? (context.french
            ? "\nDes observations distinctes soutiennent cette même séquence ; elles ne forment pas une matinée continue."
            : "\nSeparate observations support this same sequence; they are not one continuous morning.") : ""
        return .init(id: id, title: context.trace.proposedTitle(at: context.segmentIndex, french: context.french),
            detail: unit.text + "\n" + note + multiple + "\n" + EvidenceDetailText.savedTentativeNotes[context.french ? 1 : 0]
                + "\n" + EvidenceDetailText.savedLabels[context.french ? 1 : 0] + " “\(unit.text)”",
            kind: context.trace.site == .news ? .briefing : .entertainment, durationMinutes: minutes)
    }

    fileprivate static func restoredBrowserCandidates(evidence: PreparedLearningEvidence,
        proposal: EvidenceRoutineProposal, citations: inout [UUID: [RoutineEvidenceCitation]]) throws -> [RoutineStep] {
        guard evidence.units.contains(where: { $0.browserContext != nil }) else { return proposal.routine.steps }
        let groups = browserLessonGroups(evidence: evidence)
        let browserSources = groups.reduce(into: Set<UUID>()) { $0.formUnion($1.acquisitionIDs) }
        var groupByStepID: [UUID: Int] = [:]
        var browserRows: [[RoutineStep]] = []
        for (index, group) in groups.enumerated() {
            var rows: [RoutineStep] = []
            for units in group.segmentUnits {
                let sourceCitations = try units.map { try browserCitation(unit: $0, evidence: evidence) }
                let matching = proposal.support.filter { $0.citations.filter { $0.sourceLayer != .screenTimeAggregate } == sourceCitations }
                guard matching.count <= 1 else { throw RoutineEvidenceProposalError.invalidProposal }
                let id = matching.first?.stepID ?? UUID()
                citations[id] = sourceCitations + (citations[id] ?? []).filter { $0.sourceLayer == .screenTimeAggregate }
                if matching.first != nil { groupByStepID[id] = index }
                rows.append(try browserCandidate(units: units, id: id))
            }
            browserRows.append(rows)
        }
        // A malformed or mixed citation cannot masquerade as an ordinary model
        // row while a canonical candidate is restored beside it.
        for item in proposal.support where groupByStepID[item.stepID] == nil {
            if item.citations.contains(where: { browserSources.contains($0.acquisitionID) }) {
                throw RoutineEvidenceProposalError.invalidCitation
            }
        }
        if evidence.hasOnlyBrowserLessons { return browserRows.flatMap { $0 } }
        var restored: [RoutineStep] = [], inserted = Set<Int>()
        func insert(_ index: Int) {
            if inserted.insert(index).inserted { restored += browserRows[index] }
        }
        for step in proposal.routine.steps {
            if let group = groupByStepID[step.id] { insert(group) }
            else if proposal.support.first(where: { $0.stepID == step.id })?.reason == .preservedUserDecision {
                let matches = browserRows.indices.filter { index in
                    browserRows[index].contains { $0.kind == step.kind && $0.title == step.title }
                }
                if matches.count == 1, let index = matches.first { insert(index) }
                else { restored.append(step) }
            } else { restored.append(step) }
        }
        for index in groups.indices { insert(index) }
        return restored
    }

    private static func browserLessonGroups(evidence: PreparedLearningEvidence) -> [PreparedBrowserLessonGroup] {
        var seen = Set<UUID>(), groups: [PreparedBrowserLessonGroup] = []
        for unit in evidence.units where unit.browserContext != nil {
            guard seen.insert(unit.acquisitionID).inserted, let context = unit.browserContext else { continue }
            let source = evidence.units.filter { $0.acquisitionID == unit.acquisitionID && $0.browserContext != nil }
                .sorted { $0.browserContext!.segmentIndex < $1.browserContext!.segmentIndex }
            // Only an identical complete observed sequence can be merged across
            // independent mornings. Never concatenate different partial lessons.
            if let index = groups.firstIndex(where: {
                guard let first = $0.segmentUnits.first?.first?.browserContext else { return false }
                return first.trace == context.trace && first.french == context.french && $0.segmentUnits.count == source.count
            }) {
                for segment in source.indices { groups[index].segmentUnits[segment].append(source[segment]) }
            } else { groups.append(.init(segmentUnits: source.map { [$0] })) }
        }
        return groups
    }

    /// The same native join runs on creation and restoration. App-wide aggregates
    /// attach once to an exact identity; they never rewrite an observed sequence,
    /// distribute its minutes among gestures or supply action authority.
    fileprivate static func joiningScreenTime(evidence: PreparedLearningEvidence,
        steps: inout [RoutineStep], citations: inout [UUID: [RoutineEvidenceCitation]],
        preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal?, restoring: Bool = false,
        recordedOrder: [UUID]? = nil) throws -> [UUID: RoutineStep] {
        let units = evidence.units.filter { $0.screenTimeContext != nil }
        guard !units.isEmpty else { return [:] }
        guard let selection = evidence.screenTimeSelection else { throw RoutineEvidenceProposalError.invalidSelection }
        let reports = units.reduce(into: [ScreenTimeObservationEvidence]()) { values, unit in
            let report = unit.screenTimeContext!.report
            if !values.contains(where: { $0.sourceKey == report.sourceKey }) { values.append(report) }
        }
        let policy = try ScreenTimeRoutineSelection.from(reports: reports, referenceDate: selection.referenceDate)
        let ambiguous = ScreenTimeAppMomentChoice.ambiguousIdentifiers(reports: reports)
        let candidates = Dictionary(uniqueKeysWithValues: policy.candidates.map { ($0.bundleIdentifier, $0) })
        var nativeCandidates: [UUID: RoutineStep] = [:]
        var baselinePositions: [Int] = []
        let savedCitations = citations
        // Native-only rows are reconstructed, including their stable identity, from
        // source bytes. A saved proposal cannot relabel them or change their budget.
        let nativeOnlySavedIDs = Set(steps.filter { step in
            let saved = citations[step.id] ?? []
            return !saved.isEmpty && saved.allSatisfy { $0.sourceLayer == .screenTimeAggregate }
        }.map(\.id))
        for id in Array(citations.keys) { citations[id]?.removeAll { $0.sourceLayer == .screenTimeAggregate } }
        var identities: [String] = []
        identities = policy.candidates.map(\.bundleIdentifier) + policy.excludedBundleIdentifiers
        for identity in identities {
            let group = units.filter { $0.screenTimeContext!.app.bundleIdentifier == identity }
            let context = group[0].screenTimeContext!, french = context.french
            let aggregateCitations = try group.map { unit -> RoutineEvidenceCitation in
                guard let snapshot = evidence.sourceSnapshots.first(where: { $0.acquisitionID == unit.acquisitionID }) else {
                    throw RoutineEvidenceProposalError.invalidCitation
                }
                return .init(acquisitionID: unit.acquisitionID, sourceRevision: snapshot.sourceRevision, sampleID: nil,
                    quote: unit.text, startCharacterOffset: unit.startCharacterOffset,
                    endCharacterOffset: unit.startCharacterOffset + unit.text.count, sourceLayer: .screenTimeAggregate)
            }
            let note = french
                ? "Agrégats Screen Time de l’app entière sur \(group.count) fenêtre(s) retenue(s). Ordre estimé, couverture partielle ; aucun contenu ni geste établi. Le total n’est pas réparti entre les séquences observées."
                : "Whole-app Screen Time aggregates across \(group.count) retained window(s). Estimated order, partial coverage; no content or gesture established. The total is not distributed across observed sequences."
            let matching = steps.indices.first { index in
                exactBundleIdentifier(citations: citations[steps[index].id] ?? [], evidence: evidence) == identity
            }
            let index: Int
            if let matching { index = matching }
            else {
                guard let candidate = candidates[identity], !ambiguous.contains(identity),
                      selection.includedBundleIdentifiers?.contains(identity) ?? true else { continue }
                let entry = ScreenTimeAppCatalog.entry(for: identity)
                // A baseline app moment is manual until a separate observed source
                // or explicit user edit establishes a particular activity.
                let id = try screenTimeStepID(identity: identity)
                let synthetic = evidence.sourceSnapshots.first?.origin == .synthetic
                let baseline = RoutineStep(id: id, title: context.app.displayName, detail: french
                    ? "Moment proposé depuis les minutes de l’app ; durée prévue à ajuster. Aucun geste proposé."
                    : "Proposed moment from app minutes; adjust the planned duration. No gesture proposed.",
                    kind: entry.kind.stepKind, durationMinutes: candidate.minutes, syntheticEvidence: synthetic ? true : nil)
                nativeCandidates[id] = baseline
                let preference = try preferences?.matchingPreference(for: baseline)
                // Excluded candidates have no saved position. On restoration they
                // need not displace surviving candidates or missing kept rituals;
                // reconciliation still remains the authority for that exclusion.
                if restoring, preference?.presence == .exclude { continue }
                // A restored Keep is a position placeholder, never a second app
                // candidate. Replace only its matched native baseline and then let
                // the authoritative journal/base restore the person's full row.
                let keptID: UUID?
                if let preference, preference.presence == .keep {
                    keptID = preference.retainedStep?.id ?? preference.targetID
                } else if preferences == nil {
                    let kept = EvidenceRoutineProposal.keptSteps(in: base)
                    let exact = kept.filter { $0.id == id }
                    let matches = exact.isEmpty ? kept.filter { RoutineVersion.matchesActivity($0, baseline) } : exact
                    keptID = matches.count == 1 ? matches[0].id : nil
                } else { keptID = nil }
                if let position = steps.firstIndex(where: { $0.id == id && nativeOnlySavedIDs.contains(id) }) {
                    steps[position] = baseline; index = position
                } else if let keptID, let position = steps.firstIndex(where: { $0.id == keptID }),
                   savedCitations[keptID]?.isEmpty == true {
                    steps[position] = baseline; index = position
                } else {
                    steps.append(baseline); index = steps.count - 1
                }
                citations[id] = []
                baselinePositions.append(index)
            }
            let id = steps[index].id, before = citations[id] ?? []
            var combined = before
            for citation in aggregateCitations where !combined.contains(citation) { combined.append(citation) }
            guard combined.count <= maximumCitationsPerStep else { throw RoutineEvidenceProposalError.outputBudgetExceeded }
            let description = EvidenceDetailText.description(of: steps[index].detail, citing: (savedCitations[id] ?? []).map(\.quote))
                ?? EvidenceDetailText.description(of: steps[index].detail, citing: before.map(\.quote))
                ?? removingTentativeSuffix(steps[index].detail)
            let body = description.hasSuffix(note) ? description : description + "\n" + note
            steps[index].detail = body + "\n" + EvidenceDetailText.savedTentativeNotes[french ? 1 : 0] + "\n"
                + distinctQuotes(combined).map { "\(EvidenceDetailText.savedLabels[french ? 1 : 0]) “\($0)”" }.joined(separator: "\n")
            guard steps[index].detail.count <= maximumDetailCharacters else { throw RoutineEvidenceProposalError.outputBudgetExceeded }
            citations[id] = combined
        }
        if restoring, !zip(baselinePositions, baselinePositions.dropFirst()).allSatisfy({ $0 < $1 }) {
            // Native source order remains canonical. A saved permutation is valid
            // only if the exact current journal recreates the full recorded order
            // from those canonical candidates, including Keep/Exclude decisions.
            guard let preferences, preferences.order != nil, let recordedOrder else {
                throw RoutineEvidenceProposalError.invalidProposal
            }
            var canonical = steps
            for (slot, source) in zip(baselinePositions.sorted(), baselinePositions) { canonical[slot] = steps[source] }
            guard try preferences.reconcile(steps: canonical).steps.map(\.id) == recordedOrder else {
                throw RoutineEvidenceProposalError.invalidProposal
            }
            steps = canonical
        }
        steps.removeAll { nativeOnlySavedIDs.contains($0.id) && nativeCandidates[$0.id] == nil }
        return nativeCandidates
    }

    private static func distinctQuotes(_ citations: [RoutineEvidenceCitation]) -> [String] {
        var seen = Set<Data>()
        return citations.compactMap { seen.insert(Data($0.quote.utf8)).inserted ? $0.quote : nil }
    }

    private static func removingTentativeSuffix(_ text: String) -> String {
        for note in EvidenceDetailText.savedTentativeNotes + [EvidenceDetailText.tentativeNote] {
            let suffix = "\n" + note
            if text.hasSuffix(suffix) { return String(text.dropLast(suffix.count)) }
        }
        return text
    }

    private static func screenTimeStepID(identity: String) throws -> UUID {
        let digest = try EvidenceRevision.hash(["ScreenTime-app-v2", identity])
        let hex = String(digest.prefix(32))
        let sizes = [8, 4, 4, 4, 12]
        var cursor = hex.startIndex, parts: [String] = []
        for size in sizes {
            let end = hex.index(cursor, offsetBy: size); parts.append(String(hex[cursor..<end])); cursor = end
        }
        guard let id = UUID(uuidString: parts.joined(separator: "-")) else { throw RoutineEvidenceProposalError.invalidProposal }
        return id
    }

    private static func exactBundleIdentifier(citations: [RoutineEvidenceCitation], evidence: PreparedLearningEvidence) -> String? {
        let actionCitations = citations.filter { $0.sourceLayer != .screenTimeAggregate }
        guard !actionCitations.isEmpty else { return nil }
        let browser = actionCitations.compactMap { browserUnit(for: $0, evidence: evidence)?.browserContext }
        if browser.count == actionCitations.count, let first = browser.first,
           browser.allSatisfy({ $0.trace.site == first.trace.site }) {
            return RoutineExecutionSuggestion.bundleIdentifier(forReviewedLabel: first.trace.site.displayName)
        }
        var identity: String?
        for citation in actionCitations {
            guard citation.sourceLayer == .videoFrame,
                  let unit = evidence.units.first(where: {
                      $0.acquisitionID == citation.acquisitionID && $0.sampleID == citation.sampleID &&
                      citation.startCharacterOffset >= $0.startCharacterOffset &&
                      citation.endCharacterOffset <= $0.startCharacterOffset + $0.text.count
                  }), let reviewed = unit.reviewedContext,
                  let exact = RoutineExecutionSuggestion.bundleIdentifier(forReviewedLabel: reviewed.label) else { return nil }
            if let identity, identity != exact { return nil }
            identity = exact
        }
        return identity
    }

    fileprivate static func snapshot(_ entry: ObservationAcquisition) throws -> LearningSourceSnapshot {
        // Unreadable user decisions cannot silently fall back to original OCR.
        // Explicit broader notes are a separate user report and may be learned.
        // This shared boundary also prevents restoring an older pending proposal.
        guard entry.correctedText != nil || !entry.warnings.contains(.invalidFrameReviewsRemoved) else {
            throw RoutineEvidenceProposalError.unsupportedSource
        }
        guard let date = entry.observedDate else { throw RoutineEvidenceProposalError.dateRequired }
        return LearningSourceSnapshot(acquisitionID: entry.id, sourceRevision: try EvidenceRevision.source(entry),
            sourceLabel: entry.sourceLabel, observedDate: date, origin: entry.origin,
            sourceLayer: entry.correctedText != nil ? .correction : (entry.screenTimeEvidence != nil ? .screenTimeAggregate : (entry.videoEvidence != nil ? .videoFrame : .original)))
    }

    /// Validate each request before reporting completion or retaining its result.
    /// A later failure still aborts the whole proposal; there is no partial-success draft.
    static func validateBatchResult(_ steps: [EvidenceRoutineStepInput], units: [PreparedLearningEvidenceUnit]) throws {
        guard steps.count <= 4 else { throw RoutineEvidenceProposalError.invalidProposal }
        for step in steps {
            guard !step.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  step.title.count <= 120, step.detail.count <= 500,
                  (1...60).contains(step.durationMinutes), (1...5).contains(step.citations.count) else {
                throw RoutineEvidenceProposalError.invalidProposal
            }
            for citation in step.citations {
                guard let unit = units.first(where: { $0.id == citation.unitID }),
                      (8...240).contains(citation.quote.count),
                      EvidenceText.exactRange(of: citation.quote, in: unit.text) != nil,
                      LearningEvidencePolicy.supports(quote: citation.quote, source: unit.text, context: unit.context,
                        kind: unit.kind, claimedKind: unit.kind.rawValue) else {
                    throw RoutineEvidenceProposalError.invalidCitation
                }
            }
        }
    }

    private static func fitsRequest(_ prompt: String) -> Bool {
        prompt.count <= maximumBatchCharacters && prompt.utf8.count <= maximumBatchUTF8Bytes
    }

    private static func makeUnits(text: String, entry: ObservationAcquisition, layer: RoutineEvidenceSourceLayer,
                                  sampleID: UUID?, kind: LearningEvidenceKind, startingOffset: Int = 0,
                                  reviewedContext: PreparedLearningReviewedContext? = nil) throws -> [PreparedLearningEvidenceUnit] {
        let metadata = reviewPromptMetadata(reviewedContext)
        let chunks = try LearningTextChunker.split(text,
            maximumCharacters: maximumUnitCharacters - metadata.count,
            maximumUTF8Bytes: maximumUnitUTF8Bytes - metadata.utf8.count)
        var offset = startingOffset
        return chunks.map { chunk in
            defer { offset += chunk.count }
            return .init(id: UUID(), acquisitionID: entry.id, text: chunk, sourceLayer: layer,
                sampleID: sampleID, startCharacterOffset: offset, reviewedContext: reviewedContext,
                context: text, evidenceKind: kind, browserContext: nil)
        }
    }

    private static func prompt(_ units: [PreparedLearningEvidenceUnit]) -> String {
        "Suggest only activities supported by these identified units. Empty output is valid. Cite each exact unitID and quote; never infer measured duration, frequency or a completed action.\n" +
        units.map { "<unit id=\"\($0.id.uuidString)\" type=\"\($0.kind.rawValue)\">\n\(reviewPromptMetadata($0.reviewedContext))\($0.text)\n</unit>" }.joined(separator: "\n")
    }

    private static func reviewPromptMetadata(_ context: PreparedLearningReviewedContext?) -> String {
        guard let context else { return "" }
        // Quoted metadata is not part of unit.text. Exact-quote validation cannot
        // borrow it or reinterpret a reviewed label as a completed action.
        return "User-reviewed visible context only (not action evidence): \(String(reflecting: context.label))\n"
    }
}

private enum EvidenceRevision {
    static func hash<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(value)).map { String(format: "%02x", $0) }.joined()
    }
    static func isValid(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func source(_ value: ObservationAcquisition) throws -> String {
        // Hash source, date, correction, origin, extraction and explicit frame reviews.
        // An empty review list stays absent from the payload so legacy no-review
        // proposals keep their existing source revisions.
        // Derived classification/warnings and the recording's start are deliberately excluded:
        // native start metadata is not model input and does not change the assigned day.
        // Adding it to an exact-file retry must not stale an otherwise unchanged proposal.
        // Own-interface spans decide which frames are eligible, so they are hashed when
        // present. Absent spans stay out of the payload and keep existing revisions.
        struct Payload: Encodable {
            let id: UUID; let importedAt: Date?; let fileSHA256: String?
            let observedDate: ObservationObservedDate?; let origin: ObservationAcquisitionOrigin
            let sourceKind: ObservationAcquisitionSourceKind; let sourceLabel: String
            let originalText: String; let correctedText: String?; let videoEvidence: ObservationVideoEvidence?
            let frameReviews: [ObservationFrameReview]?
            let ownInterfaceIntervals: OwnInterfaceIntervals?
            let browserLearning: BrowserLearningTrace?
            let screenTimeEvidence: ScreenTimeObservationEvidence?
        }
        return try hash(Payload(id: value.id, importedAt: value.importedAt, fileSHA256: value.fileSHA256,
            observedDate: value.observedDate, origin: value.origin, sourceKind: value.sourceKind,
            sourceLabel: value.sourceLabel, originalText: value.originalText, correctedText: value.correctedText,
            videoEvidence: value.videoEvidence,
            frameReviews: value.frameReviews.isEmpty ? nil : value.frameReviews.sorted { $0.sampleID.uuidString < $1.sampleID.uuidString },
            ownInterfaceIntervals: value.recordingContext?.ownInterfaceIntervals,
            browserLearning: value.browserLearning, screenTimeEvidence: value.screenTimeEvidence))
    }
}

private enum EvidenceText {
    static func exactRange(of quote: String, in source: String) -> Range<Int>? {
        guard !quote.isEmpty, let bytes = Data(source.utf8).range(of: Data(quote.utf8)) else { return nil }
        var boundaries: [Int: Int] = [0: 0]
        var byteOffset = 0
        for (index, character) in source.enumerated() {
            byteOffset += String(character).utf8.count
            boundaries[byteOffset] = index + 1
        }
        guard let start = boundaries[bytes.lowerBound], let end = boundaries[bytes.upperBound] else { return nil }
        return start..<end
    }
    static func matches(_ quote: String, in source: String, start: Int, end: Int) -> Bool {
        guard start >= 0, end >= start, end <= source.count else { return false }
        let a = source.index(source.startIndex, offsetBy: start)
        let b = source.index(a, offsetBy: end - start)
        return source[a..<b].utf8.elementsEqual(quote.utf8)
    }
}
