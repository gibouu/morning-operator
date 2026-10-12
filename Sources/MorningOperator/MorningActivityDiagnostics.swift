#if DEBUG
import ActivityKit
import MorningCore

/// A native ActivityKit read in an explicitly isolated UI-test workspace. This
/// is not the coordinator's optimistic state, a fixture provider or a renderer.
@MainActor
enum MorningActivityDiagnostics {
    static func summary(namespace: MorningActivityNamespace) -> String {
        let activities = Activity<MorningActivityAttributes>.activities.filter {
            $0.attributes.namespace == namespace && ($0.activityState == .active || $0.activityState == .stale)
        }
        guard activities.count == 1, let activity = activities.first else { return "count:\(activities.count)" }
        let state = activity.content.state
        return "count:1|status:\(state.status.rawValue)|complete:\(state.completedSteps)|total:\(state.totalSteps)|category:\(state.category.rawValue)"
    }
}
#endif
