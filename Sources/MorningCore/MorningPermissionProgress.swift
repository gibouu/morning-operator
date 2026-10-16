import Foundation

/// Stable permission keys; speech and microphone share one explanation in the UI.
public enum MorningPermission: String, Codable, Sendable, CaseIterable {
    case location, calendar, reminders, screenTime, speech, microphone, notifications, alarms
}

/// Stores only which explanations the person has handled, never private source
/// data or a guessed system authorization. Denial and skipping are valid choices.
public struct MorningPermissionProgress: Codable, Sendable, Equatable {
    public private(set) var completed: Set<MorningPermission>
    public init(completed: Set<MorningPermission> = []) { self.completed = completed }
    /// Other sources are connected only when the person chooses to use them.
    public var pendingInitial: [MorningPermission] { pending(supported: [.speech, .microphone]) }
    public func pending(supported: [MorningPermission]) -> [MorningPermission] {
        var seen = Set<MorningPermission>()
        return supported.filter { !completed.contains($0) && seen.insert($0).inserted }
    }
    public mutating func resolve(_ permission: MorningPermission) { completed.insert(permission) }
}
