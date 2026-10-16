import Foundation

public enum RoutinePreferencePresence: String, Codable, Sendable {
    case keep, exclude
}

public enum RoutinePreferenceError: Error, LocalizedError, Sendable, Equatable {
    case invalidPreference, tooManyPreferences, preferencesTooLarge, invalidSteps
    case ambiguousMatch(UUID), conflictingMatch(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidPreference: String(localized: "This saved routine preference is invalid. Review or reset it before learning again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .tooManyPreferences: String(localized: "At most 100 routine preferences can be saved. Clear an unused preference first.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .preferencesTooLarge: String(localized: "These saved preferences exceed the local storage limit. Shorten a retained moment or clear an unused preference.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .invalidSteps: String(localized: "The suggested routine has conflicting step identities. Your routine is unchanged.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .ambiguousMatch: String(localized: "More than one suggested moment could match a saved preference. Review the matching activities before trying again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        case .conflictingMatch: String(localized: "Two saved preferences conflict for the same suggested moment. Review those preferences before trying again.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
        }
    }
}

/// An explicit user decision. Only keep retains the full user-owned moment;
/// exclusions and duration-only choices retain an identity and conservative key.
public struct RoutinePreference: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { targetID }
    public let targetID: UUID
    public let targetTitle: String
    public let targetKind: StepKind
    public let presence: RoutinePreferencePresence?
    public let durationMinutes: Int?
    public let retainedStep: RoutineStep?
    public var normalizedTitle: String { preferenceTitleKey(targetTitle) }

    public init(target: RoutineStep, presence: RoutinePreferencePresence? = nil,
                durationMinutes: Int? = nil) throws {
        targetID = target.id
        targetTitle = target.title
        targetKind = target.kind
        self.presence = presence
        self.durationMinutes = durationMinutes
        retainedStep = presence == .keep ? target : nil
        try validate()
    }

    public func validate() throws {
        guard !normalizedTitle.isEmpty, targetTitle.count <= 2_000,
              presence != nil || durationMinutes != nil,
              durationMinutes.map({ (1...120).contains($0) }) ?? true,
              (presence == .keep) == (retainedStep != nil) else {
            throw RoutinePreferenceError.invalidPreference
        }
        if let retainedStep {
            guard retainedStep.id == targetID, retainedStep.kind == targetKind,
                  retainedStep.title.utf8.elementsEqual(targetTitle.utf8),
                  retainedStep.detail.count <= 32_000,
                  RoutineStep.durationMinutesRange.contains(retainedStep.durationMinutes) else {
                throw RoutinePreferenceError.invalidPreference
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case targetID, targetTitle, targetKind, presence, durationMinutes, retainedStep
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        targetID = try values.decode(UUID.self, forKey: .targetID)
        targetTitle = try values.decode(String.self, forKey: .targetTitle)
        targetKind = try values.decode(StepKind.self, forKey: .targetKind)
        presence = try values.decodeIfPresent(RoutinePreferencePresence.self, forKey: .presence)
        durationMinutes = try values.decodeIfPresent(Int.self, forKey: .durationMinutes)
        retainedStep = try values.decodeIfPresent(RoutineStep.self, forKey: .retainedStep)
        try validate()
    }
}

public struct RoutinePreferenceReconciliation: Sendable, Equatable {
    public let steps: [RoutineStep]
    /// Full moments retained from the user's keep snapshots, never model evidence.
    public let retainedStepIDs: Set<UUID>
    /// Explicit overrides are reported even when the incoming number already agrees.
    public let durationOverriddenStepIDs: Set<UUID>
    public let excludedStepIDs: Set<UUID>
    public let appliedPreferenceIDsByStepID: [UUID: [UUID]]
}

/// Persist beside the current routine. Removing a step must not erase its exclusion.
/// An explicitly supplied journal is authoritative: callers sanitize model output
/// without retaining legacy required rows first. If trusted input already includes
/// those rows, exclusions still remove them or reject ambiguous alternatives.
public struct RoutinePreferenceJournal: Codable, Sendable, Equatable {
    public static let maximumEntries = 100
    public static let maximumEncodedBytes = 4 * 1_024 * 1_024
    private static let emptyRevision = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
    /// Records relative order only. It neither keeps absent moments nor grants
    /// action authority; source identity remains separate from this user choice.
    public struct OrderedMoment: Codable, Sendable, Equatable {
        public let targetID: UUID
        public let targetTitle: String
        public let targetKind: StepKind
        fileprivate init(_ step: RoutineStep) {
            targetID = step.id; targetTitle = step.title; targetKind = step.kind
        }
        fileprivate func validate() throws {
            guard !preferenceTitleKey(targetTitle).isEmpty, targetTitle.count <= 2_000,
                  targetTitle.utf8.count <= 8_000,
                  !targetTitle.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw RoutinePreferenceError.invalidPreference
            }
        }
    }

    public private(set) var entries: [RoutinePreference]
    public private(set) var revision: UUID
    public private(set) var order: [OrderedMoment]?

    public init() { entries = []; revision = Self.emptyRevision; order = nil }

    public init(entries: [RoutinePreference], revision: UUID, order: [OrderedMoment]? = nil) throws {
        self.entries = entries
        self.revision = revision
        self.order = order
        try validate()
    }

    /// Call only for an explicit editor reorder, never for model/source order.
    public mutating func rememberOrder(of steps: [RoutineStep]) throws {
        let next = steps.map(OrderedMoment.init)
        if let order, try JSONEncoder().encode(order) == JSONEncoder().encode(next) { return }
        self = try Self(entries: entries, revision: UUID(), order: next)
    }

    public func validate() throws {
        guard entries.count <= Self.maximumEntries else { throw RoutinePreferenceError.tooManyPreferences }
        guard Set(entries.map(\.targetID)).count == entries.count else { throw RoutinePreferenceError.invalidPreference }
        for entry in entries { try entry.validate() }
        if let order {
            guard (1...10).contains(order.count), Set(order.map(\.targetID)).count == order.count else {
                throw RoutinePreferenceError.invalidPreference
            }
            for moment in order { try moment.validate() }
        }
        guard try JSONEncoder().encode(self).count <= Self.maximumEncodedBytes else {
            throw RoutinePreferenceError.preferencesTooLarge
        }
    }

    public func entry(targetID: UUID) -> RoutinePreference? { entries.first { $0.targetID == targetID } }

    /// An exact stable identity wins. Title/category fallback must be unique;
    /// punctuation, synonyms and fuzzy similarity are deliberately not inferred.
    public func matchingPreference(for step: RoutineStep) throws -> RoutinePreference? {
        if let exact = entry(targetID: step.id) { return exact }
        let matching = entries.filter { $0.targetKind == step.kind && $0.normalizedTitle == preferenceTitleKey(step.title) }
        guard matching.count <= 1 else { throw RoutinePreferenceError.ambiguousMatch(step.id) }
        return matching.first
    }

    public mutating func upsert(_ preference: RoutinePreference) throws {
        try preference.validate()
        var next = entries
        if let index = next.firstIndex(where: { $0.targetID == preference.targetID }) {
            // Byte-exact user text changes are real edits, including canonically
            // equivalent Unicode spellings that String equality would collapse.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            if try encoder.encode(next[index]) == encoder.encode(preference) { return }
            next[index] = preference
        } else { next.append(preference) }
        self = try Self(entries: next, revision: UUID(), order: order)
    }

    @discardableResult
    public mutating func remove(targetID: UUID) -> Bool {
        guard entries.contains(where: { $0.targetID == targetID }) else { return false }
        entries.removeAll { $0.targetID == targetID }
        revision = UUID()
        return true
    }

    @discardableResult
    public mutating func clear() -> Bool {
        guard !entries.isEmpty || order != nil else { return false }
        entries.removeAll(); order = nil
        revision = UUID()
        return true
    }

    public func reconcile(steps: [RoutineStep]) throws -> RoutinePreferenceReconciliation {
        try validate()
        guard !entries.isEmpty || order != nil else {
            return .init(steps: steps, retainedStepIDs: [], durationOverriddenStepIDs: [],
                         excludedStepIDs: [], appliedPreferenceIDsByStepID: [:])
        }
        guard Set(steps.map(\.id)).count == steps.count else { throw RoutinePreferenceError.invalidSteps }
        var preferenceByIndex: [Int: RoutinePreference] = [:]
        var missing: [RoutinePreference] = []
        for entry in entries {
            let exact = steps.firstIndex { $0.id == entry.targetID }
            let keyMatches = steps.indices.filter {
                steps[$0].kind == entry.targetKind && preferenceTitleKey(steps[$0].title) == entry.normalizedTitle
            }
            let index: Int?
            if let exact {
                // Legacy required retention may append the old ID after ambiguous
                // model alternatives. Removing only that old row would resurrect the
                // excluded activity under fresh IDs; block instead of guessing.
                if entry.presence == .exclude, keyMatches.contains(where: { $0 != exact }) {
                    throw RoutinePreferenceError.ambiguousMatch(entry.targetID)
                }
                index = exact
            } else {
                guard keyMatches.count <= 1 else { throw RoutinePreferenceError.ambiguousMatch(entry.targetID) }
                index = keyMatches.first
            }
            if let index {
                guard preferenceByIndex[index] == nil else { throw RoutinePreferenceError.conflictingMatch(steps[index].id) }
                preferenceByIndex[index] = entry
            } else { missing.append(entry) }
        }

        var result: [RoutineStep] = []
        var retained: Set<UUID> = []
        var overridden: Set<UUID> = []
        var excluded: Set<UUID> = []
        var applied: [UUID: [UUID]] = [:]
        func apply(_ entry: RoutinePreference, to proposed: RoutineStep?) {
            if entry.presence == .exclude {
                if let proposed { excluded.insert(proposed.id) }
                return
            }
            guard var step = entry.retainedStep ?? proposed else { return }
            if entry.presence == .keep { retained.insert(step.id) }
            if let minutes = entry.durationMinutes {
                step.durationMinutes = minutes
                overridden.insert(step.id)
            }
            applied[step.id] = [entry.id]
            result.append(step)
        }
        for index in steps.indices {
            if let entry = preferenceByIndex[index] { apply(entry, to: steps[index]) }
            else { result.append(steps[index]) }
        }
        // Duration-only and exclude choices never insert an absent activity.
        for entry in missing where entry.presence == .keep { apply(entry, to: nil) }
        guard Set(result.map(\.id)).count == result.count else { throw RoutinePreferenceError.invalidSteps }
        return .init(steps: try applyingOrder(to: result), retainedStepIDs: retained, durationOverriddenStepIDs: overridden,
                     excludedStepIDs: excluded, appliedPreferenceIDsByStepID: applied)
    }

    /// New moments keep their slots and relative order. Only the matched
    /// survivors are exchanged between their current slots in the reviewed order.
    private func applyingOrder(to steps: [RoutineStep]) throws -> [RoutineStep] {
        guard let order else { return steps }
        var matched: [Int] = [], used = Set<Int>()
        for moment in order {
            let index: Int?
            if let exact = steps.firstIndex(where: { $0.id == moment.targetID }) { index = exact }
            else {
                let matches = steps.indices.filter { steps[$0].kind == moment.targetKind &&
                    preferenceTitleKey(steps[$0].title) == preferenceTitleKey(moment.targetTitle) }
                guard matches.count <= 1 else { throw RoutinePreferenceError.ambiguousMatch(moment.targetID) }
                index = matches.first
            }
            if let index {
                guard used.insert(index).inserted else { throw RoutinePreferenceError.conflictingMatch(steps[index].id) }
                matched.append(index)
            }
        }
        var result = steps
        for (slot, source) in zip(matched.sorted(), matched) { result[slot] = steps[source] }
        return result
    }

    private enum CodingKeys: String, CodingKey { case entries, revision, order }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        entries = try values.decode([RoutinePreference].self, forKey: .entries)
        revision = try values.decode(UUID.self, forKey: .revision)
        // Legacy absence means no order preference. Present malformed/null data
        // must remain unreadable rather than silently discard a personal choice.
        order = values.contains(.order) ? try values.decode([OrderedMoment].self, forKey: .order) : nil
        try validate()
    }
}

/// Shared with the time budget, which must match a choice to a step exactly as the journal does.
func preferenceTitleKey(_ title: String) -> String {
    title.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
}
