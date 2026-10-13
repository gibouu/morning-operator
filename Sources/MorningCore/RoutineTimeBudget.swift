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

    /// The journal's own matching rule (`RoutinePreferenceJournal.reconcile`), read without
    /// changing the journal. Each choice claims the step with its identity or, when no step
    /// has it, the single step with its category and title. A choice that matches several
    /// steps claims none, and a step claimed by two choices is protected by neither: where
    /// the journal refuses to guess about a step, the budget does not protect that step.
    /// The rule is applied choice by choice. A refusal about one activity does not hide a
    /// keep the person made for another step by its identity: the report would then leave
    /// out minutes they did ask to keep.
    private static func keptStepIDs(in steps: [RoutineStep], preferences: RoutinePreferenceJournal) -> Set<UUID> {
        var claims: [UUID: [RoutinePreference]] = [:]
        for entry in preferences.entries {
            if steps.contains(where: { $0.id == entry.targetID }) {
                claims[entry.targetID, default: []].append(entry)
                continue
            }
            let matches = steps.filter {
                $0.kind == entry.targetKind && preferenceTitleKey($0.title) == entry.normalizedTitle
            }
            if matches.count == 1 { claims[matches[0].id, default: []].append(entry) }
        }
        return Set(claims.compactMap { stepID, entries in
            entries.count == 1 && entries[0].presence == .keep ? stepID : nil
        })
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
