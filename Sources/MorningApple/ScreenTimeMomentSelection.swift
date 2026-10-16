import Foundation
import MorningCore

/// A review choice about optional app-only moments, separate from retained facts.
/// Its clock is captured once and also dates the resulting proposal.
public struct ScreenTimeMomentSelection: Codable, Equatable, Sendable {
    public let policyVersion: Int
    public let referenceDate: Date
    /// Nil uses all eligible candidates; an explicit empty list adds no baseline.
    public let includedBundleIdentifiers: [String]?
    public init(referenceDate: Date, includedBundleIdentifiers: Set<String>? = nil) throws {
        policyVersion = 2
        self.referenceDate = referenceDate
        self.includedBundleIdentifiers = includedBundleIdentifiers.map { $0.sorted() }
        try validate()
    }
    public func validate() throws {
        guard policyVersion == 2, referenceDate.timeIntervalSince1970.isFinite,
              referenceDate.timeIntervalSince1970 >= -62_135_596_800,
              referenceDate.timeIntervalSince1970 < 253_402_300_800,
              includedBundleIdentifiers.map({ ids in
                  ids.count <= 640 && ids == Array(Set(ids)).sorted() && ids.allSatisfy {
                      !$0.isEmpty && $0.count <= 255 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || ".-_".contains($0)) }
                  }
              }) ?? true else { throw RoutineEvidenceProposalError.invalidSelection }
    }
    func validate(acquisitions: [ObservationAcquisition]) throws {
        try validate()
        let available = Set(acquisitions.filter { $0.correctedText == nil }.flatMap { $0.screenTimeEvidence?.apps.map(\.bundleIdentifier) ?? [] })
        let ambiguous = ScreenTimeAppMomentChoice.ambiguousIdentifiers(reports: acquisitions.filter { $0.correctedText == nil }.compactMap(\.screenTimeEvidence))
        guard includedBundleIdentifiers.map({ Set($0).isSubset(of: available) && Set($0).isDisjoint(with: ambiguous) }) ?? true else {
            throw RoutineEvidenceProposalError.invalidSelection
        }
    }
    private enum CodingKeys: String, CodingKey { case policyVersion, referenceDate, includedBundleIdentifiers }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        policyVersion = try values.decode(Int.self, forKey: .policyVersion)
        referenceDate = try values.decode(Date.self, forKey: .referenceDate)
        includedBundleIdentifiers = try values.decodeIfPresent([String].self, forKey: .includedBundleIdentifiers)
        try validate()
    }
}

public struct ScreenTimeAppMomentChoice: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let plannedMinutes: Int?
    public let isIncluded: Bool
    public let isAmbiguous: Bool
    public var isEligible: Bool { plannedMinutes != nil }
    public static var policyExplanation: String {
        String(localized: "Shared rule: use of at least 30 seconds, presence in at least half the retained comparable windows, median rounded to a minute and planned duration between 1 and 240 minutes. Order stays estimated and missing use unknown. All aggregates remain in the sources.", bundle: AppLanguage.bundle(for: .module), locale: AppLanguage.locale)
    }
    static func ambiguousIdentifiers(reports: [ScreenTimeObservationEvidence]) -> Set<String> {
        let names = reports.flatMap(\.apps).reduce(into: [String: String]()) { values, app in
            if values[app.bundleIdentifier] == nil { values[app.bundleIdentifier] = app.displayName }
        }
        let groups = Dictionary(grouping: names.keys) { id in
            names[id]!.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Set(groups.values.filter { $0.count > 1 }.flatMap { $0 })
    }
}

extension LearningEvidencePreparation {
    public static func screenTimeAppChoices(acquisitions: [ObservationAcquisition], selection: ScreenTimeMomentSelection) throws -> [ScreenTimeAppMomentChoice] {
        try selection.validate(acquisitions: acquisitions)
        let reports = acquisitions.filter { $0.correctedText == nil }.compactMap(\.screenTimeEvidence)
        let policy = try ScreenTimeRoutineSelection.from(reports: reports, referenceDate: selection.referenceDate)
        let ambiguous = ScreenTimeAppMomentChoice.ambiguousIdentifiers(reports: reports)
        let names = reports.flatMap(\.apps).reduce(into: [String: String]()) { names, app in
            if names[app.bundleIdentifier] == nil { names[app.bundleIdentifier] = app.displayName }
        }
        let eligible = policy.candidates.map { candidate in
            ScreenTimeAppMomentChoice(id: candidate.bundleIdentifier, name: names[candidate.bundleIdentifier]!,
                plannedMinutes: candidate.minutes,
                isIncluded: !ambiguous.contains(candidate.bundleIdentifier) && (selection.includedBundleIdentifiers?.contains(candidate.bundleIdentifier) ?? true),
                isAmbiguous: ambiguous.contains(candidate.bundleIdentifier))
        }
        return eligible + policy.excludedBundleIdentifiers.map {
            ScreenTimeAppMomentChoice(id: $0, name: names[$0]!, plannedMinutes: nil, isIncluded: false, isAmbiguous: ambiguous.contains($0))
        }
    }
}
