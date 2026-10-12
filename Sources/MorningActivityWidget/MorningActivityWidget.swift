import ActivityKit
import Foundation
import MorningCore
import SwiftUI
import WidgetKit

@main
struct MorningActivityWidgetBundle: WidgetBundle {
    var body: some Widget { MorningActivityWidget() }
}

/// No storage, network, intents or private routine strings enter this extension.
/// Opening the URL only selects the app's Morning screen; the app owns all effects.
struct MorningActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MorningActivityAttributes.self) { context in
            MorningActivityLockScreen(state: context.state, isStale: context.isStale)
                .widgetURL(MorningActivityPresentation.destination)
        } dynamicIsland: { context in
            let presentation = MorningActivityPresentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("MORE").font(.caption.weight(.semibold)).tracking(2)
                        .foregroundStyle(MorningActivityPalette.islandAccent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label(presentation.status, systemImage: presentation.statusSymbol)
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MorningActivityIslandDetail(presentation: presentation)
                }
            } compactLeading: {
                Image(systemName: presentation.leadingSymbol)
                    .foregroundStyle(MorningActivityPalette.islandAccent)
                    .accessibilityLabel(presentation.accessibilitySummary)
            } compactTrailing: {
                if context.isStale {
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(.white).accessibilityLabel("Update needed. Open MORE.")
                } else {
                    Text(presentation.shortProgress).font(.caption2.monospacedDigit())
                        .foregroundStyle(.white).accessibilityLabel(presentation.progress)
                }
            } minimal: {
                Image(systemName: presentation.leadingSymbol)
                    .foregroundStyle(MorningActivityPalette.islandAccent)
                    .accessibilityLabel(presentation.accessibilitySummary)
            }
            .widgetURL(MorningActivityPresentation.destination)
            .keylineTint(MorningActivityPalette.islandAccent)
            .contentMargins(.all, 24, for: .expanded)
        }
    }
}

private struct MorningActivityLockScreen: View {
    let state: MorningActivityContentState
    let isStale: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: MorningActivityPresentation { .init(state: state, isStale: isStale) }
    private var accent: Color { colorScheme == .dark ? MorningActivityPalette.islandAccent : MorningActivityPalette.purple }
    private var background: Color { colorScheme == .dark ? MorningActivityPalette.dark : MorningActivityPalette.cream }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // Two essential facts remain visible without a narrow icon column,
                // time row or progress decoration competing with enlarged text.
                VStack(alignment: .leading, spacing: 5) {
                    Text("MORE").font(.caption2.weight(.semibold)).foregroundStyle(accent)
                    Text(presentation.heading).font(.subheadline.weight(.semibold))
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Text(isStale ? "Open MORE" : "\(presentation.status) · \(presentation.shortProgress)")
                        .font(.caption).lineLimit(2)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("MORE").font(.caption.weight(.semibold)).tracking(2).foregroundStyle(accent)
                        Spacer(minLength: 4)
                        Label(presentation.status, systemImage: presentation.statusSymbol)
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: presentation.leadingSymbol).font(.title3).foregroundStyle(accent)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(presentation.heading).font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(isStale ? "Open MORE to update." : presentation.progress)
                                .font(.subheadline).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(spacing: 4) {
                        Text("Last update")
                        Text(state.updatedAt, style: .time)
                    }.font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .activityBackgroundTint(background)
        .activitySystemActionForegroundColor(accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityHint("Opens MORE's Morning screen.")
        // No timer, implied countdown or explicit animation. Counts change only
        // when the app publishes a real session update, including with Reduce Motion.
    }
}

private struct MorningActivityIslandDetail: View {
    let presentation: MorningActivityPresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(presentation.heading)
                .font(dynamicTypeSize.isAccessibilitySize ? .subheadline.weight(.semibold) : .headline)
                .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
            Text(presentation.isStale ? "Open MORE to update." : presentation.progress)
                .font(.caption).foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.lastUpdate)
                .font(.caption2).foregroundStyle(.white.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityHint("Opens MORE's Morning screen.")
    }
}

private struct MorningActivityPresentation {
    let state: MorningActivityContentState
    let isStale: Bool
    static let destination = URL(string: "more://morning")!

    var heading: String { isStale ? "Update needed" : state.category.displayName }
    var status: String { isStale ? "Update needed" : state.status.displayName }
    var shortProgress: String { "\(state.completedSteps)/\(state.totalSteps)" }
    var progress: String { "\(state.completedSteps) of \(state.totalSteps) moments passed" }
    // A static timestamp remains truthful even when the system defers a stale
    // presentation refresh. No timer implies that the app is still executing.
    var lastUpdate: String { "Last update \(state.updatedAt.formatted(date: .omitted, time: .shortened))" }
    var accessibilitySummary: String {
        if isStale { return "MORE. Update needed. Last saved progress: \(progress). \(lastUpdate). Open MORE to update." }
        return "MORE. \(state.category.displayName). \(status). \(progress). \(lastUpdate)."
    }
    var statusSymbol: String {
        if isStale { return "exclamationmark.circle" }
        return switch state.status {
        case .running: "circle.fill"
        case .paused: "pause.fill"
        case .needsAttention: "hand.tap"
        }
    }
    var leadingSymbol: String {
        if isStale { return "exclamationmark.circle" }
        if state.status == .paused { return "pause.fill" }
        return switch state.category {
        case .briefing: "sun.horizon.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .calendar: "calendar"
        case .wellbeing: "heart.fill"
        case .entertainment: "sparkles.tv"
        case .custom: "leaf.fill"
        }
    }
}

private enum MorningActivityPalette {
    static let purple = Color(red: 0.43, green: 0.34, blue: 0.70)
    static let islandAccent = Color(red: 0.73, green: 0.65, blue: 0.94)
    static let cream = Color(red: 0.98, green: 0.973, blue: 0.952)
    static let dark = Color(red: 0.10, green: 0.11, blue: 0.13)
}
