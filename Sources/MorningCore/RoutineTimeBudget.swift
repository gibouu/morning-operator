import Foundation

/// The only ways out of a plan that is longer than its target. Both belong to the person;
/// neither is applied here.
public enum RoutineTimeBudgetChoice: String, Codable, CaseIterable, Sendable {
    case editRoutine, acceptLongerPlan
    public var displayName: String {
        switch self {
        case .editRoutine: String(localized: "Edit the routine", bundle: .module)
        case .acceptLongerPlan: String(localized: "Keep the longer plan", bundle: .module)
        }
    }
}

public enum RoutineTimeBudgetFit: String, Codable, Sendable {
    case withinTarget, overTarget
    /// Required and kept rituals alone are longer than the target. Editing optional
    /// steps cannot close the gap; this is reported, never resolved by trimming.
    case requiredAloneOverTarget
}

/// A report comparing planned minutes with a duration target. It deliberately has no
/// trimmed step list: a target never removes, shortens or reorders a step.
/// Planned minutes are the routine's own estimates, not measured phone time.
/// Derived on demand from the stored routine, so it is not decodable: a stored
/// copy could disagree with the routine it describes.
public struct RoutineTimeBudget: Sendable, Equatable {
    public let routineVersionID: UUID
    public let targetMinutes: Int
    public let totalMinutes: Int
    /// Minutes of steps marked required, or kept by an explicit journal choice.
    public let requiredMinutes: Int
    /// In routine order.
    public let requiredStepIDs: [UUID]

    /// A journal keep protects the step the journal itself would apply it to: the step
    /// with that exact identity or, when no step has it, the single step with the same
    /// category and title. Exclusions and timing-only choices do not protect a step.
    public init(routine: RoutineVersion, targetMinutes: Int,
                preferences: RoutinePreferenceJournal = RoutinePreferenceJournal()) {
        let kept = Self.keptStepIDs(in: routine.steps, preferences: preferences)
        let required = routine.steps.filter { $0.isRequired || kept.contains($0.id) }
        routineVersionID = routine.id
        self.targetMinutes = max(1, targetMinutes)
        totalMinutes = routine.totalDurationMinutes
        requiredMinutes = required.reduce(0) { $0 + $1.durationMinutes }
        requiredStepIDs = required.map(\.id)
    }

    /// The journal's own matching rule, read without changing the journal. A choice whose
    /// step is in the routine belongs to that step alone. Otherwise it reaches a step by
    /// category and title only when exactly one step matches it and that step has no choice
    /// of its own; anything ambiguous protects nothing, as the journal refuses to guess.
    private static func keptStepIDs(in steps: [RoutineStep], preferences: RoutinePreferenceJournal) -> Set<UUID> {
        let stepIDs = Set(steps.map(\.id))
        var matchedSteps: [UUID: [UUID]] = [:]
        for step in steps {
            guard let match = try? preferences.matchingPreference(for: step) else { continue }
            if match.targetID == step.id || !stepIDs.contains(match.targetID) {
                matchedSteps[match.id, default: []].append(step.id)
            }
        }
        var kept = Set<UUID>()
        for entry in preferences.entries where entry.presence == .keep {
            if let matched = matchedSteps[entry.id], matched.count == 1 { kept.insert(matched[0]) }
        }
        return kept
    }

    public var minutesOverTarget: Int { max(0, totalMinutes - targetMinutes) }
    public var requiredMinutesOverTarget: Int { max(0, requiredMinutes - targetMinutes) }
    public var optionalMinutes: Int { totalMinutes - requiredMinutes }

    public var fit: RoutineTimeBudgetFit {
        if requiredMinutes > targetMinutes { return .requiredAloneOverTarget }
        return totalMinutes > targetMinutes ? .overTarget : .withinTarget
    }

    /// Empty when the plan fits. Otherwise the person edits, or accepts the full plan.
    public var choices: [RoutineTimeBudgetChoice] {
        fit == .withinTarget ? [] : RoutineTimeBudgetChoice.allCases
    }

    /// The length of the plan if the person accepts it as it is: always every step.
    public var longerPlanMinutes: Int { totalMinutes }
}
