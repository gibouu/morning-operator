import Foundation

public enum StepKind: String, Codable, CaseIterable, Sendable {
    case briefing, messages, calendar, wellbeing, entertainment, custom
    public var displayName: String {
        switch self {
        case .briefing: String(localized: "Briefing", bundle: .module)
        case .messages: String(localized: "Messages", bundle: .module)
        case .calendar: String(localized: "Calendar", bundle: .module)
        case .wellbeing: String(localized: "Wellbeing", bundle: .module)
        case .entertainment: String(localized: "Entertainment", bundle: .module)
        case .custom: String(localized: "Custom", bundle: .module)
        }
    }
}

/// A concrete app-owned operation, separate from an inferred activity category.
/// A nil operation remains manual, including routines decoded from older files.
public enum RoutineStepAutomation: String, Codable, CaseIterable, Sendable {
    case spokenNote, todayCalendar, morningBriefing, savedObservation
    public var displayName: String {
        switch self {
        case .spokenNote: String(localized: "Read this note aloud", bundle: .module)
        case .todayCalendar: String(localized: "Read today's calendar", bundle: .module)
        case .morningBriefing: String(localized: "Read today's briefing", bundle: .module)
        case .savedObservation: String(localized: "Read reviewed observation text", bundle: .module)
        }
    }
}

public struct RoutineStep: Codable, Sendable, Identifiable, Equatable {
    /// One minute to one day: the widest planned time a saved choice or suggestion may carry.
    /// A step holds no other value, so adding the minutes of any list of steps cannot overflow.
    public static let durationMinutesRange = 1...1_440

    public let id: UUID
    public var title: String
    public var detail: String
    public var kind: StepKind
    /// Planned minutes. A value set outside `durationMinutesRange` becomes its nearest bound.
    public var durationMinutes: Int { didSet { durationMinutes = Self.bounded(durationMinutes) } }
    public var isRequired: Bool
    public var automation: RoutineStepAutomation?
    public var observationReference: RoutineObservationReference?
    public init(id: UUID = UUID(), title: String, detail: String = "", kind: StepKind = .custom,
                durationMinutes: Int = 5, isRequired: Bool = false, automation: RoutineStepAutomation? = nil,
                observationReference: RoutineObservationReference? = nil) {
        self.id = id; self.title = title; self.detail = detail; self.kind = kind
        self.durationMinutes = Self.bounded(durationMinutes); self.isRequired = isRequired
        self.automation = automation; self.observationReference = observationReference
    }

    private static func bounded(_ minutes: Int) -> Int {
        min(max(durationMinutesRange.lowerBound, minutes), durationMinutesRange.upperBound)
    }

    /// The app never writes minutes outside the range, so a saved value outside it is damage.
    /// It is refused, not adjusted: a changed number would be presented as the person's own.
    /// An absent operation or observation reference is an older file, and stays readable.
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        detail = try values.decode(String.self, forKey: .detail)
        kind = try values.decode(StepKind.self, forKey: .kind)
        let minutes = try values.decode(Int.self, forKey: .durationMinutes)
        guard Self.durationMinutesRange.contains(minutes) else {
            throw DecodingError.dataCorruptedError(forKey: .durationMinutes, in: values,
                debugDescription: "Planned minutes must be between 1 and 1,440.")
        }
        durationMinutes = minutes
        isRequired = try values.decode(Bool.self, forKey: .isRequired)
        automation = try values.decodeIfPresent(RoutineStepAutomation.self, forKey: .automation)
        observationReference = try values.decodeIfPresent(RoutineObservationReference.self, forKey: .observationReference)
    }
}

/// A user correction kept separately from inferred preferences.
public struct RoutineStepPreference: Codable, Sendable, Equatable {
    public let stepID: UUID
    public var isRequired: Bool?
    public var durationMinutes: Int?
    public init(stepID: UUID, isRequired: Bool? = nil, durationMinutes: Int? = nil) {
        self.stepID = stepID; self.isRequired = isRequired
        self.durationMinutes = durationMinutes.map { max(1, $0) }
    }
}

public struct RoutineVersion: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public var number: Int
    public var createdAt: Date
    public var sourceLabel: String
    public var steps: [RoutineStep]
    public var isApproved: Bool
    public init(id: UUID = UUID(), number: Int = 1, createdAt: Date = Date(), sourceLabel: String,
                steps: [RoutineStep], isApproved: Bool = false) {
        self.id = id; self.number = max(1, number); self.createdAt = createdAt
        self.sourceLabel = sourceLabel; self.steps = steps; self.isApproved = isApproved
    }
    /// Kept source bindings retain sample provenance even after a new proposal
    /// changes the routine label. A legacy sample marker remains conservative.
    public var isSynthetic: Bool {
        sourceLabel.localizedCaseInsensitiveContains("demo fixture") ||
            steps.contains { $0.observationReference?.isSynthetic == true }
    }
    public var totalDurationMinutes: Int { steps.reduce(0) { $0 + $1.durationMinutes } }
    /// The number of the version that follows this one. A saved number is not bounded when
    /// read, so the count stops at the largest integer instead of overflowing.
    public var nextNumber: Int { number < Int.max ? number + 1 : Int.max }
    public func approved() -> RoutineVersion { var copy = self; copy.isApproved = true; return copy }
    /// Explicit edits create a new version needing approval, leaving active sessions unchanged.
    public func revised(steps: [RoutineStep], sourceLabel: String? = nil, at date: Date = Date()) -> RoutineVersion {
        RoutineVersion(number: nextNumber, createdAt: date, sourceLabel: sourceLabel ?? self.sourceLabel,
                       steps: steps, isApproved: false)
    }
    /// Proposals retain complete required rituals and steps named by explicit preferences.
    /// Trusted callers may supply automation; use inferredDraft for untrusted model output.
    /// Explicit removal remains available through revised(steps:).
    public func proposing(steps proposedSteps: [RoutineStep], preserving preferences: [RoutineStepPreference] = [],
                          sourceLabel: String? = nil, at date: Date = Date()) -> RoutineVersion {
        revised(steps: Self.reconcile(proposedSteps, previous: steps, preferences: preferences),
            sourceLabel: sourceLabel, at: date)
    }

    /// A model can suggest content but cannot mark a ritual required, assign an operation,
    /// or approve its own proposal. Prior required steps (and explicitly supplied preference
    /// targets) retain all user-owned fields. Other corrections/removals need a separate
    /// persisted preference journal; this method does not infer that missing history.
    public static func inferredDraft(from candidate: RoutineVersion, preserving previous: RoutineVersion?,
                                     preferences: [RoutineStepPreference] = [], at date: Date = Date()) -> RoutineVersion {
        let proposed = candidate.steps.map { step in
            var manual = step
            manual.isRequired = false
            manual.automation = nil
            manual.observationReference = nil
            return manual
        }
        // The sample's required ritual demonstrates the control; it is not a personal
        // preference. Keep its existing synthetic provenance out of a learned morning.
        let personalSteps = previous?.isSynthetic == true
            ? [] : previous?.steps ?? []
        return RoutineVersion(number: previous?.nextNumber ?? 1, createdAt: date,
            sourceLabel: candidate.sourceLabel,
            steps: reconcile(proposed, previous: personalSteps, preferences: preferences),
            isApproved: false)
    }

    private static func reconcile(_ proposed: [RoutineStep], previous: [RoutineStep],
                                  preferences: [RoutineStepPreference]) -> [RoutineStep] {
        var result = proposed
        let preferenceIDs = Set(preferences.map(\.stepID))
        let oldKeys = Dictionary(grouping: previous, by: RoutineStepMatchKey.init)
        let proposedKeys = Dictionary(grouping: proposed.indices, by: { RoutineStepMatchKey(proposed[$0]) })
        var replacedIndexes = Set<Int>()
        for kept in previous where kept.isRequired || preferenceIDs.contains(kept.id) {
            let idMatches = proposed.indices.filter { proposed[$0].id == kept.id }
            let key = RoutineStepMatchKey(kept)
            let index: Int?
            if idMatches.count == 1 {
                index = idMatches[0]
            } else if idMatches.isEmpty, !key.title.isEmpty,
                      oldKeys[key]?.count == 1, proposedKeys[key]?.count == 1 {
                index = proposedKeys[key]?.first
            } else {
                index = nil
            }
            if let index, replacedIndexes.insert(index).inserted {
                // Keep the entire prior value, not just the required flag. A fresh model ID
                // and suggested duration/detail cannot erase this explicit user decision.
                result[index] = kept
            } else {
                // Ambiguous semantic alternatives remain separate draft rows for review.
                // Never guess which row may replace the person's kept ritual.
                result.append(kept)
            }
        }
        for preference in preferences {
            guard let index = result.firstIndex(where: { $0.id == preference.stepID }) else { continue }
            if let required = preference.isRequired { result[index].isRequired = required }
            if let minutes = preference.durationMinutes { result[index].durationMinutes = max(1, minutes) }
        }
        return result
    }
}

/// Deliberately no fuzzy/synonym/punctuation matching: similarity is not user approval.
private struct RoutineStepMatchKey: Hashable {
    let kind: String
    let title: String
    init(_ step: RoutineStep) {
        kind = step.kind.rawValue
        title = step.title.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
public enum DemoFixtures {
    /// Synthetic demonstration data, never a recorded personal morning.
    public static var candidateRoutine: RoutineVersion {
        RoutineVersion(sourceLabel: "Demo fixture — synthetic morning, not observed personal data", steps: [
            RoutineStep(title: String(localized: "Your morning", bundle: .module), detail: String(localized: "Good morning. Let’s see what’s ahead.", bundle: .module), kind: .briefing, durationMinutes: 3, automation: .spokenNote),
            RoutineStep(title: String(localized: "People and messages", bundle: .module), detail: String(localized: "Check in with the people who matter.", bundle: .module), kind: .messages, durationMinutes: 5),
            RoutineStep(title: String(localized: "Make room for the day", bundle: .module), detail: String(localized: "Read today’s events from your connected calendar.", bundle: .module), kind: .calendar, durationMinutes: 3, automation: .todayCalendar),
            RoutineStep(title: String(localized: "A little time to play", bundle: .module), detail: String(localized: "A little chess. A little joy. Keep this time for yourself.", bundle: .module), kind: .entertainment, durationMinutes: 8, isRequired: true)
        ])
    }
    public static var routine: RoutineVersion { candidateRoutine.approved() }
}
