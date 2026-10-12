import Foundation
import MorningCore

/// Use the shared actor as the authoritative writer in the application process.
/// Each operation reloads the separate journal; it never replaces workspace.json.
public actor AppTransitionLogStore {
    public static let shared = AppTransitionLogStore()
    private let file: AtomicJSONFile<AppTransitionHistory>
    private let privacy: LocalDataControl

    public init(directory: URL? = nil) {
        let directory = directory ?? LocalDataControl.defaultDirectory
        file = AtomicJSONFile(url: directory.appendingPathComponent("app-transitions.json"))
        privacy = LocalDataControl(directory: directory)
    }

    @discardableResult
    public func record(app: ObservedApp, kind: AppTransitionKind, observedAt: Date = .now,
                       eventID: UUID = UUID(), timeZoneIdentifier: String = TimeZone.current.identifier) throws -> Bool {
        try privacy.withReadyAccess { state in
            guard state.activityLoggingAllowed else { return false }
            let event = try AppTransitionEvent(id: eventID, app: app, kind: kind,
                observedAt: observedAt, timeZoneIdentifier: timeZoneIdentifier)
            var history = try load()
            // A retried action can arrive later or after a time-zone change. Preserve the
            // original observation for its stable ID, and serialize this check with the save.
            if let prior = history.events.first(where: { $0.id == eventID }) {
                guard prior.app == app, prior.kind == kind else { throw AppTransitionError.conflictingEventID }
                return false
            }
            guard try history.append(event) else { return false }
            try file.save(history)
            return true
        }
    }

    public func activityLoggingAllowed() throws -> Bool {
        try privacy.withReadyAccess { $0.activityLoggingAllowed }
    }

    /// An explicit app setting; a Shortcut invocation never enables collection itself.
    public func setActivityLoggingAllowed(_ allowed: Bool) throws {
        try privacy.setActivityLoggingAllowed(allowed)
    }

    public func events() throws -> [AppTransitionEvent] {
        try privacy.withReadyAccess { _ in try load().events }
    }

    public func summary(for date: Date, timeZoneIdentifier: String = TimeZone.current.identifier) throws -> AppTransitionDaySummary {
        try privacy.withReadyAccess { _ in try load().summary(for: date, timeZoneIdentifier: timeZoneIdentifier) }
    }

    /// Removes only this activity journal. Configured Shortcuts can log new events afterward
    /// only while local activity collection is enabled. Full forgetting disables collection.
    /// Clearing does not require decoding the file, so a corrupt journal can also be removed.
    public func clear() throws {
        try privacy.withReadyAccess { _ in
            guard file.url.isFileURL else { throw PersistenceError.fileURLRequired }
            if FileManager.default.fileExists(atPath: file.url.path) {
                try FileManager.default.removeItem(at: file.url)
            }
        }
    }

    private func load() throws -> AppTransitionHistory {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return try AppTransitionHistory() }
        // Corrupt or newer data must fail rather than be silently overwritten.
        return try file.load()
    }
}
