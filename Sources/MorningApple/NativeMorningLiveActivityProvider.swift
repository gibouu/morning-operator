import Foundation
import MorningCore
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Local ActivityKit only. No push token, notification, background task, App
/// Intent, or remote lifecycle owner is installed by this adapter.
@MainActor public final class NativeMorningLiveActivityProvider: MorningLiveActivityProviding {
    public let namespace: MorningActivityNamespace
    public init(namespace: MorningActivityNamespace = .production) { self.namespace = namespace }
    #if canImport(ActivityKit) && os(iOS)
    private var retained: [String: Activity<MorningActivityAttributes>] = [:]
    public var isSupported: Bool { true }
    public var authorizationEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }
    private var owned: [Activity<MorningActivityAttributes>] {
        for activity in Activity<MorningActivityAttributes>.activities where activity.attributes.namespace == namespace {
            retained[activity.id] = activity
        }
        return Array(retained.values)
    }
    public var records: [MorningLiveActivityRecord] {
        owned.map { activity in
            let state: MorningLiveActivityRecordState
            switch activity.activityState {
            case .pending: state = .pending
            case .active: state = .active
            case .stale: state = .stale
            case .ended: state = .ended
            case .dismissed: state = .dismissed
            @unknown default: state = .ended
            }
            return .init(id: activity.id, sessionID: activity.attributes.sessionID, state: state)
        }
    }
    public func request(snapshot: MorningActivitySnapshot, staleDate: Date) async throws -> String {
        guard authorizationEnabled else { throw MorningLiveActivityError.requestFailed }
        let activity = try Activity.request(attributes: MorningActivityAttributes(sessionID: snapshot.sessionID, namespace: namespace),
            content: ActivityContent(state: snapshot.state, staleDate: staleDate), pushType: nil)
        retained[activity.id] = activity
        return activity.id
    }
    public func update(id: String, snapshot: MorningActivitySnapshot, staleDate: Date) async throws {
        try await Self.updateNative(id: id, namespace: namespace, snapshot: snapshot, staleDate: staleDate)
    }
    public func end(id: String) async throws {
        try await Self.endNative(id: id, namespace: namespace)
        retained.removeValue(forKey: id)
    }

    // SDK 27's update/end methods are @concurrent, while Activity is not
    // Sendable. Resolve their handles on that executor; only immutable value
    // parameters cross the actor boundary, never a retained UI-isolated handle.
    private nonisolated static func updateNative(id: String, namespace: MorningActivityNamespace,
                                                snapshot: MorningActivitySnapshot, staleDate: Date) async throws {
        guard let activity = Activity<MorningActivityAttributes>.activities.first(where: {
            $0.id == id && $0.attributes.namespace == namespace
        }),
              activity.attributes.sessionID == snapshot.sessionID,
              activity.activityState == .active || activity.activityState == .stale else {
            throw MorningLiveActivityError.updateFailed
        }
        await activity.update(ActivityContent(state: snapshot.state, staleDate: staleDate))
    }
    private nonisolated static func endNative(id: String, namespace: MorningActivityNamespace) async throws {
        guard let activity = Activity<MorningActivityAttributes>.activities.first(where: {
            $0.id == id && $0.attributes.namespace == namespace
        }) else { return }
        guard activity.activityState != .dismissed else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        guard activity.activityState == .dismissed else { throw MorningLiveActivityError.endUnconfirmed }
    }
    #else
    public var isSupported: Bool { false }
    public var authorizationEnabled: Bool { false }
    public var records: [MorningLiveActivityRecord] { [] }
    public func request(snapshot: MorningActivitySnapshot, staleDate: Date) async throws -> String {
        throw MorningLiveActivityError.unavailable
    }
    public func update(id: String, snapshot: MorningActivitySnapshot, staleDate: Date) async throws {
        throw MorningLiveActivityError.unavailable
    }
    public func end(id: String) async throws {}
    #endif
}
