import Foundation

/// Stable permission keys; speech and microphone share one explanation in the UI.
public enum MorningPermission: String, Codable, Sendable, CaseIterable {
    case location, calendar, reminders, screenTime, speech, microphone, notifications, alarms
}

/// Stores only which explanations the person has handled, never private source
/// data or a guessed system authorization. Denial and skipping are valid choices.
public struct MorningPermissionProgress: Codable, Sendable, Equatable {
    public private(set) var completed: Set<MorningPermission>
    public private(set) var initialSetupCompleted: Bool
    public init(completed: Set<MorningPermission> = [], initialSetupCompleted: Bool = false) {
        self.completed = completed
        self.initialSetupCompleted = initialSetupCompleted
    }
    private enum CodingKeys: String, CodingKey { case completed, initialSetupCompleted }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        completed = try values.decode(Set<MorningPermission>.self, forKey: .completed)
        initialSetupCompleted = try values.decodeIfPresent(Bool.self, forKey: .initialSetupCompleted)
            ?? (completed.contains(.speech) && completed.contains(.microphone))
    }
    /// Missing voice grants, grouped into one choice by the setup interface.
    public var pendingInitial: [MorningPermission] { pending(supported: [.speech, .microphone]) }
    public func pending(supported: [MorningPermission]) -> [MorningPermission] {
        var seen = Set<MorningPermission>()
        return supported.filter { !completed.contains($0) && seen.insert($0).inserted }
    }
    public mutating func resolve(_ permission: MorningPermission) { completed.insert(permission) }
    public mutating func completeInitialSetup() { initialSetupCompleted = true }
}
