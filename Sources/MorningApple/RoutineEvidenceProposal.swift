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
    public var errorDescription: String? {
        switch self {
        case .invalidSelection: String(localized: "Select one to five different saved observations.", bundle: .module)
        case .dateRequired: String(localized: "Assign an observed day to every selected observation first.", bundle: .module)
        case .incompatibleSources: String(localized: "Select observations in the same time zone and with the same human or synthetic origin.", bundle: .module)
        case .unsupportedSource: String(localized: "This source needs a reviewed written correction before it can support a proposal.", bundle: .module)
        case .insufficientEvidence: String(localized: "Each selected observation needs usable activity evidence. Review its notes or choose another observation.", bundle: .module)
        case .ownInterfaceLeftNoEvidence: String(localized: "A selected recording has no usable activity evidence. Some of its samples were left out because MORE itself was in front when they were taken. Use your other apps while a recording runs, or choose another observation.", bundle: .module)
        case .inputBudgetExceeded: String(localized: "These saved observations exceed the bounded local workload or contain a text unit too large to send safely. Your complete saved source is unchanged; nothing was silently shortened.", bundle: .module)
        case .outputBudgetExceeded: String(localized: "The combined suggestion contains more distinct supporting text than can fit in one reviewable plan. Your complete observations are still saved; choose a smaller set of observations. Nothing was silently shortened.", bundle: .module)
        case .tooManySteps: String(localized: "This proposal needs more than ten moments, including your kept rituals. Select fewer observations; no kept ritual was removed.", bundle: .module)
        case .invalidCitation: String(localized: "A proposed step could not be tied to the exact supplied evidence. Your current routine is unchanged.", bundle: .module)
        case .invalidProposal: String(localized: "This proposal is incomplete or inconsistent with its saved evidence. Create another proposal.", bundle: .module)
        }
    }
}

public enum RoutineEvidenceSourceLayer: String, Codable, Sendable {
    case original, correction, videoFrame
    public var displayName: String {
        switch self {
        case .original: String(localized: "Original observation", bundle: .module)
        case .correction: String(localized: "Your correction", bundle: .module)
        case .videoFrame: String(localized: "Recorded screen text", bundle: .module)
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

    fileprivate init(base: RoutineVersion?, routine: RoutineVersion, sources: [LearningSourceSnapshot],
                     support: [RoutineProposalSupport], omissions: [LearningEvidenceOmission],
                     preferences: RoutinePreferenceJournal?) throws {
        id = UUID()
        baseRoutineID = base?.id
        baseRoutineRevision = try base.map { try EvidenceRevision.hash($0) }
        preferenceSnapshot = preferences
        preferenceRevision = try preferences.map { try EvidenceRevision.hash($0) }
        self.routine = routine
        sourceSnapshots = sources
        self.support = support
        self.omissions = omissions
        try validateStructure()
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
            for snapshot in sourceSnapshots {
                guard let entry = archive.entry(id: snapshot.acquisitionID),
                      try LearningEvidencePreparation.snapshot(entry) == snapshot else { return false }
            }
            // Rebuild user-owned rows independently of the stored support claims. The
            // authoritative journal suppresses legacy retention, including after a cleared keep.
            let candidate = RoutineVersion(createdAt: routine.createdAt, sourceLabel: routine.sourceLabel,
                steps: routine.steps)
            let inherited = Self.inferredDraft(from: candidate, preserving: baseRoutine,
                preferences: preferences, at: routine.createdAt)
            let reconciled = try (preferences ?? RoutinePreferenceJournal()).reconcile(steps: inherited.steps)
            guard try EvidenceRevision.hash(reconciled.steps) == EvidenceRevision.hash(routine.steps) else { return false }
            let legacyKept = preferences == nil ? Self.keptSteps(in: baseRoutine) : []
            let keptIDs = Set(legacyKept.map(\.id)).union(reconciled.retainedStepIDs)
            for item in support {
                guard let step = routine.steps.first(where: { $0.id == item.stepID }) else { return false }
                let expectedReason: RoutineProposalSupportReason = keptIDs.contains(step.id) ? .preservedUserDecision
                    : reconciled.durationOverriddenStepIDs.contains(step.id) ? .inferredEvidenceWithUserPreference : .inferredEvidence
                let expectedPreferences = (reconciled.appliedPreferenceIDsByStepID[step.id] ?? []).sorted { $0.uuidString < $1.uuidString }
                guard item.reason == expectedReason, item.preferenceIDs == expectedPreferences else { return false }
                if item.reason == .inferredEvidenceWithUserPreference {
                    // Model rows receive fresh IDs at assembly. On restore, an invented
                    // collision with a saved target ID cannot transfer its timing to a
                    // different activity; require the same conservative key as fallback.
                    let titleKey = step.title.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                        .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
                    guard expectedPreferences.allSatisfy({ id in
                        guard let preference = preferences?.entry(targetID: id) else { return false }
                        return preference.presence == nil && preference.durationMinutes == step.durationMinutes
                            && preference.targetKind == step.kind && preference.normalizedTitle == titleKey
                    }) else { return false }
                }
                if item.reason != .preservedUserDecision {
                    guard !step.isRequired, step.automation == nil,
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
        case .videoFrame:
            guard entry.correctedText == nil, let id = citation.sampleID,
                  !entry.frameReviews.contains(where: { $0.sampleID == id && $0.label == nil }),
                  let frame = entry.videoEvidence?.frames.first(where: { $0.id == id }), frame.canSupportIdentity else { return nil }
            return frame.text
        }
    }

    private func validateStructure() throws {
        try preferenceSnapshot?.validate()
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
                  (1...(item.reason == .inferredEvidence ? 60 : 1_440)).contains(step.durationMinutes),
                  !inferred || (!step.isRequired && step.automation == nil && step.observationReference == nil),
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
        case routine, sourceSnapshots, support, omissions
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
        routine = try values.decode(RoutineVersion.self, forKey: .routine)
        sourceSnapshots = try values.decode([LearningSourceSnapshot].self, forKey: .sourceSnapshots)
        support = try values.decode([RoutineProposalSupport].self, forKey: .support)
        omissions = try values.decodeIfPresent([LearningEvidenceOmission].self, forKey: .omissions) ?? []
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
    fileprivate let evidenceKind: LearningEvidenceKind
}

public struct PreparedLearningEvidence: Equatable, Sendable {
    public let sourceSnapshots: [LearningSourceSnapshot]
    public let units: [PreparedLearningEvidenceUnit]
    public let omissions: [LearningEvidenceOmission]
    public let submittedCharacterCount: Int
    public var modelRequestCount: Int { batches.count }
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
                               ownInterfaceMarginSeconds: Double = OwnInterfaceIntervals.defaultMarginSeconds)
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
        var units: [PreparedLearningEvidenceUnit] = []
        var omissions: [LearningEvidenceOmission] = []
        for entry in acquisitions {
            let previousCount = units.count
            if let correction = entry.correctedText {
                guard LearningEvidencePolicy.isEligibleWrittenContext(correction) else { throw RoutineEvidenceProposalError.insufficientEvidence }
                units += try makeUnits(text: correction, entry: entry, layer: .correction, sampleID: nil, kind: .userReportedActivity)
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
                case .video, .unknown: throw RoutineEvidenceProposalError.unsupportedSource
                }
                var text = entry.originalText
                var sourceOffset = 0
                let screenshotHeader = "[User-selected screenshot; one moment, not a confirmed habit]\n"
                if entry.sourceKind == .image, text.hasPrefix(screenshotHeader) {
                    text = String(text.dropFirst(screenshotHeader.count))
                    sourceOffset = screenshotHeader.count
                }
                let valid = kind == .userReportedActivity ? LearningEvidencePolicy.isEligibleWrittenContext(text)
                    : LearningEvidencePolicy.isEligibleVisualContext(text)
                guard valid else { throw RoutineEvidenceProposalError.insufficientEvidence }
                units += try makeUnits(text: text, entry: entry, layer: .original, sampleID: nil, kind: kind, startingOffset: sourceOffset)
            }
            guard units.count > previousCount else {
                let byTime = omissions.contains { $0.acquisitionID == entry.id && $0.reason == .ownInterfaceInFront }
                throw byTime ? RoutineEvidenceProposalError.ownInterfaceLeftNoEvidence : RoutineEvidenceProposalError.insufficientEvidence
            }
        }
        // No cross-day deduplication. Even identical text keeps independent source IDs.
        // Every eligible source character is retained. Both request limits include identifiers and review metadata.
        var batches: [[PreparedLearningEvidenceUnit]] = []
        var current: [PreparedLearningEvidenceUnit] = []
        for unit in units {
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
            submittedCharacterCount: count, batches: batches, prompts: prompts)
    }

    /// The same deterministic gate is used for model output and explicitly labeled UI fixtures.
    /// It validates provenance; it does not prove the model's semantic interpretation is true.
    public static func assemble(evidence: PreparedLearningEvidence, steps: [EvidenceRoutineStepInput],
                                preserving base: RoutineVersion?, preferences: RoutinePreferenceJournal? = nil,
                                at date: Date = Date()) throws -> EvidenceRoutineProposal {
        try preferences?.validate()
        guard !steps.isEmpty, steps.count <= maximumModelCalls * 4, date.timeIntervalSince1970.isFinite else {
            throw RoutineEvidenceProposalError.insufficientEvidence
        }
        if let base {
            guard base.number >= 1, base.number < Int.max else { throw RoutineEvidenceProposalError.invalidProposal }
        }
        var proposed: [RoutineStep] = []
        var citationsByStep: [UUID: [RoutineEvidenceCitation]] = [:]
        var keyIndexes: [String: Int] = [:]
        for input in steps {
            let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = input.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title.count <= 120, detail.count <= 500, (1...60).contains(input.durationMinutes),
                  (1...24).contains(input.citations.count) else { throw RoutineEvidenceProposalError.invalidProposal }
            var citations: [RoutineEvidenceCitation] = []
            for inputCitation in input.citations {
                guard let unit = evidence.units.first(where: { $0.id == inputCitation.unitID }),
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
        }
        // Pending receipts hold structured provenance. Keep bounded, exact quotations in
        // the routine too, so explicit approval does not erase the established source text.
        for index in proposed.indices {
            var seenQuotes = Set<Data>()
            let quotes = (citationsByStep[proposed[index].id] ?? []).compactMap { citation -> String? in
                seenQuotes.insert(Data(citation.quote.utf8)).inserted ? citation.quote : nil
            }
            proposed[index].detail += "\n" + quotes.map(EvidenceDetailText.line).joined(separator: "\n")
            guard proposed[index].detail.count <= maximumDetailCharacters else { throw RoutineEvidenceProposalError.outputBudgetExceeded }
        }
        let synthetic = evidence.sourceSnapshots.first?.origin == .synthetic
        let source = synthetic ? "Demo fixture — synthetic saved observations" : String(localized: "Selected saved observations — tentative proposal", bundle: .module)
        let candidate = RoutineVersion(createdAt: date, sourceLabel: source, steps: proposed, isApproved: false)
        var routine = EvidenceRoutineProposal.inferredDraft(from: candidate, preserving: base,
            preferences: preferences, at: date)
        let reconciled = try (preferences ?? RoutinePreferenceJournal()).reconcile(steps: routine.steps)
        routine.steps = reconciled.steps
        // An explicit Keep may reintroduce a synthetic excerpt even when every
        // newly selected source is personal. Preserve that provenance on the
        // whole plan before approval, export or run aggregation can use it.
        if routine.isSynthetic && !routine.sourceLabel.localizedCaseInsensitiveContains("demo fixture") {
            routine.sourceLabel = "Demo fixture — includes a synthetic saved observation"
        }
        guard !routine.steps.isEmpty else { throw RoutineEvidenceProposalError.insufficientEvidence }
        guard routine.steps.count <= 10 else { throw RoutineEvidenceProposalError.tooManySteps }
        let legacyKept = preferences == nil ? EvidenceRoutineProposal.keptSteps(in: base) : []
        let keptIDs = Set(legacyKept.map(\.id)).union(reconciled.retainedStepIDs)
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
            support: support, omissions: evidence.omissions, preferences: preferences)
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
            sourceLayer: entry.correctedText != nil ? .correction : (entry.videoEvidence != nil ? .videoFrame : .original))
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
                context: text, evidenceKind: kind)
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
        }
        return try hash(Payload(id: value.id, importedAt: value.importedAt, fileSHA256: value.fileSHA256,
            observedDate: value.observedDate, origin: value.origin, sourceKind: value.sourceKind,
            sourceLabel: value.sourceLabel, originalText: value.originalText, correctedText: value.correctedText,
            videoEvidence: value.videoEvidence,
            frameReviews: value.frameReviews.isEmpty ? nil : value.frameReviews.sorted { $0.sampleID.uuidString < $1.sampleID.uuidString },
            ownInterfaceIntervals: value.recordingContext?.ownInterfaceIntervals))
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
