import ActivityKit
import Foundation
import MorningCore
import SwiftUI
import WidgetKit

@main
struct MorningActivityWidgetBundle: WidgetBundle {
    var body: some Widget { MorningActivityWidget() }
}

/// Closed category names and timer destinations only. The widget's dot artwork is
/// local vector geometry; actions retain the app-owned intent/deep-link policy.
struct MorningActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MorningActivityAttributes.self) { context in
            MorningActivityLockScreen(state: context.state, isStale: context.isStale,
                                      sessionID: context.attributes.sessionID)
                .environment(\.locale, AppLanguage.locale)
                .environment(\.layoutDirection, .leftToRight)
                .widgetURL(MorningActivityPresentation.destination)
        } dynamicIsland: { context in
            let presentation = MorningActivityPresentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    MorningWidgetLivingMark(fraction: presentation.artworkProgress)
                        .frame(width: 36, height: 26)
                        .foregroundStyle(MorningActivityPalette.islandAccent)
                        .accessibilityHidden(true)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(presentation.status).font(.caption.weight(.medium))
                        .foregroundStyle(.white).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MorningActivityIslandDetail(presentation: presentation,
                                                sessionID: context.attributes.sessionID)
                        .environment(\.locale, AppLanguage.locale)
                        .environment(\.layoutDirection, .leftToRight)
                }
            } compactLeading: {
                HStack(spacing: 0) {
                    MorningWidgetLivingMark(fraction: presentation.artworkProgress).frame(width: 22, height: 22)
                        .foregroundStyle(MorningActivityPalette.islandAccent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.accessibilitySummary)
            } compactTrailing: {
                if context.isStale {
                    Text("!").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .accessibilityLabel(AppLanguage.localized("Update needed. Open MORE."))
                } else if let timer = context.state.stepTimer {
                    StepCountdown(timer: timer, state: context.state)
                        .environment(\.locale, AppLanguage.locale)
                        .environment(\.layoutDirection, .leftToRight)
                        .font(.caption2.monospacedDigit()).foregroundStyle(.white)
                        .frame(maxWidth: 52)
                } else {
                    Text(presentation.shortProgress).font(.caption2.monospacedDigit())
                        .foregroundStyle(.white).accessibilityLabel(presentation.progress)
                }
            } minimal: {
                HStack(spacing: 0) {
                    MorningWidgetLivingMark(fraction: presentation.artworkProgress).frame(width: 22, height: 22)
                        .foregroundStyle(MorningActivityPalette.islandAccent)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.accessibilitySummary)
            }
            .widgetURL(MorningActivityPresentation.destination)
            .keylineTint(MorningActivityPalette.islandAccent)
            .contentMargins(.all, 14, for: .expanded)
        }
    }
}

private struct MorningActivityLockScreen: View {
    let state: MorningActivityContentState
    let isStale: Bool
    let sessionID: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: MorningActivityPresentation { .init(state: state, isStale: isStale) }
    private var ink: Color { MorningActivityPalette.ink }
    private var accent: Color { MorningActivityPalette.rust }
    private var muted: Color { MorningActivityPalette.muted }
    private var background: Color { MorningActivityPalette.paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                MorningWidgetLivingMark(fraction: presentation.artworkProgress).frame(width: 36, height: 28)
                    .foregroundStyle(accent).accessibilityHidden(true)
                Text("MORE").font(.caption.weight(.semibold)).foregroundStyle(ink)
                Spacer(minLength: 8)
                Text(presentation.status).font(.caption.weight(.medium)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let timer = state.stepTimer {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        timerDetails(timer)
                        StepActivityControls(sessionID: sessionID, timer: timer, ink: ink, accent: accent)
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        timerDetails(timer)
                        Spacer(minLength: 4)
                        StepActivityControls(sessionID: sessionID, timer: timer, ink: ink, accent: accent)
                    }
                }
                MorningWidgetBudgetProgress(timer: timer, state: state, tint: accent)
                    .frame(height: 4).padding(.top, 3)
            } else {
                Text(presentation.heading).font(.headline).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isStale ? AppLanguage.localized("Open MORE to update.") : presentation.progress)
                    .font(.caption).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .activityBackgroundTint(background)
        .activitySystemActionForegroundColor(accent)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityHint("Opens MORE's Morning screen.")
    }

    private func timerDetails(_ timer: MorningActivityStepTimer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(timer.destination.displayName).font(.subheadline.weight(.medium)).foregroundStyle(ink)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            StepCountdown(timer: timer, state: state)
                .font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(ink)
                .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).remaining")
        }
    }
}

private struct MorningActivityIslandDetail: View {
    let presentation: MorningActivityPresentation
    let sessionID: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let timer = presentation.state.stepTimer {
                VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(timer.destination.displayName).font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                        StepCountdown(timer: timer, state: presentation.state)
                            .font(.title2.weight(.medium).monospacedDigit()).foregroundStyle(.white)
                            .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).remaining")
                    }
                    Spacer(minLength: 4)
                    StepActivityControls(sessionID: sessionID, timer: timer, ink: .white,
                                         accent: MorningActivityPalette.islandAccent)
                }
                MorningWidgetBudgetProgress(timer: timer, state: presentation.state,
                                            tint: MorningActivityPalette.islandAccent).frame(height: 4)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.heading)
                        .font(dynamicTypeSize.isAccessibilitySize ? .subheadline.weight(.semibold) : .headline)
                        .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Text(presentation.isStale ? AppLanguage.localized("Open MORE to update.") : presentation.progress)
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityHint("Opens MORE's Morning screen.")
    }
}

private struct MorningActivityPresentation {
    let state: MorningActivityContentState
    let isStale: Bool
    static var destination: URL { URL(string: "\(scheme)://morning")! }
    static var scheme: String { Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more" }

    var heading: String { isStale ? AppLanguage.localized("Update needed") : state.category.displayName }
    var status: String { isStale ? AppLanguage.localized("Update needed") : state.status.displayName }
    var artworkProgress: Double? { state.stepTimer?.elapsedFraction(at: state.updatedAt) }
    var shortProgress: String { "\(state.completedSteps)/\(state.totalSteps)" }
    var progress: String { AppLanguage.localized("\(state.completedSteps) of \(state.totalSteps) moments passed") }
    var lastUpdate: String { AppLanguage.localized("Last update \(state.updatedAt.formatted(date: .omitted, time: .shortened))") }
    var accessibilitySummary: String {
        if isStale { return AppLanguage.localized("MORE. Update needed. Last saved progress: \(progress). \(lastUpdate). Open MORE to update.") }
        return AppLanguage.localized("MORE. \(state.category.displayName). \(status). \(progress). \(lastUpdate).")
    }
}

private enum MorningActivityPalette {
    static let ink = Color(red: 0.102, green: 0.184, blue: 0.431)
    static let paper = Color(red: 0.957, green: 0.925, blue: 0.867)
    static let rust = Color(red: 0.608, green: 0.227, blue: 0.071)
    static let muted = Color(red: 0.310, green: 0.333, blue: 0.420)
    static let islandAccent = Color(red: 0.949, green: 0.635, blue: 0.435)
}

private struct StepCountdown: View {
    let timer: MorningActivityStepTimer
    let state: MorningActivityContentState
    var body: some View {
        if state.status == .paused {
            Text(Duration.seconds(timer.pausedRemaining ?? max(0, timer.endsAt.timeIntervalSince(state.updatedAt))), format: .time(pattern: .minuteSecond))
        } else {
            Text(timerInterval: min(state.updatedAt, timer.endsAt)...timer.endsAt, countsDown: true)
        }
    }
}

private struct StepActivityControls: View {
    let sessionID: UUID
    let timer: MorningActivityStepTimer
    let ink: Color
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: AddStepTimeIntent(sessionID: sessionID, stepID: timer.stepID, expectedEnd: timer.endsAt)) {
                VStack(spacing: 3) {
                    MorningWidgetControlGlyph(kind: .extend).frame(width: 23, height: 23)
                        .foregroundStyle(accent)
                    Text("+2 min").font(.caption2.weight(.medium)).foregroundStyle(ink)
                }.frame(minWidth: 50, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel("+2 min")
            .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).extend")
            Link(destination: StepNavigation.nextURL(sessionID: sessionID, stepID: timer.stepID,
                                                     scheme: MorningActivityPresentation.scheme)) {
                VStack(spacing: 3) {
                    MorningWidgetControlGlyph(kind: timer.hasNextStep ? .next : .finish)
                        .frame(width: 23, height: 23).foregroundStyle(accent)
                    if timer.hasNextStep { Text("Next").font(.caption2.weight(.medium)).foregroundStyle(ink) }
                    else { Text("Finish").font(.caption2.weight(.medium)).foregroundStyle(ink) }
                }.frame(minWidth: 50, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(timer.nextLabel)
            .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).next")
        }
        .buttonStyle(.plain)
    }
}

/// The extension repeats the app's small dot silhouette without importing app UI.
/// Each impression is its own circle; no old category logo, emoji or stroked symbol.
private struct MorningWidgetSunrise: Shape {
    func path(in rect: CGRect) -> Path {
        widgetDots(["....x....", ".x..x..x.", "..xxxxx..", ".xxxxxxx.", ".xxxxxxx.",
                    ".xxxxxxx.", "xxxxxxxxx", ".........", "..xxxxx.."], in: rect)
    }
}

private struct MorningWidgetControlGlyph: Shape {
    enum Kind { case extend, next, finish }
    let kind: Kind
    func path(in rect: CGRect) -> Path {
        let rows: [String]
        switch kind {
        case .extend:
            rows = [".........", "....x....", "....x....", "....x....", ".xxxxxxx.", "....x....", "....x....", "....x....", "........."]
        case .next:
            rows = [".........", "....x....", ".....x...", "......x..", ".xxxxxxx.", "......x..", ".....x...", "....x....", "........."]
        case .finish:
            rows = [".........", ".......x.", "......x..", ".....x...", ".x..x....", "..xx.....", "...x.....", ".........", "........."]
        }
        return widgetDots(rows, in: rect)
    }
}

private func widgetDots(_ rows: [String], in rect: CGRect) -> Path {
    let side = min(rect.width, rect.height)
    let cell = side / 10, radius = cell * 0.36
    var path = Path()
    for (row, text) in rows.enumerated() {
        for (column, value) in text.enumerated() where value == "x" {
            let x = rect.midX + (CGFloat(column) - 4) * cell
            let y = rect.midY + (CGFloat(row) - 4) * cell
            path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
        }
    }
    return path
}

/// Two original print concepts. Production uses the rising sun; the quiet crescent
/// remains available to native design previews without claiming a separate capability.
private enum MorningWidgetArtworkConcept { case risingSun, quietMoon }

/// The position changes only with published content, using the real persisted start.
/// Short transitions are allowed; no TimelineView, repeated animation or background loop.
private struct MorningWidgetLivingMark: View {
    let fraction: Double?
    var concept: MorningWidgetArtworkConcept = .risingSun
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var reducedLuminance

    var body: some View {
        GeometryReader { geometry in
            if fraction == nil, concept == .risingSun {
                MorningWidgetSunrise()
            } else {
                let progress = min(1, max(0, fraction ?? 0))
                let side = min(geometry.size.width * 0.72, geometry.size.height * 0.72)
                ZStack {
                    MorningWidgetCelestialDisc(crescent: concept == .quietMoon)
                        .frame(width: side, height: side)
                        .position(x: geometry.size.width / 2,
                                  y: geometry.size.height * (0.74 - 0.34 * progress))
                    MorningWidgetHorizon().frame(height: 3)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.86)
                }
                .clipped()
                .animation(reduceMotion || reducedLuminance ? nil : .easeInOut(duration: 0.35), value: fraction)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MorningWidgetCelestialDisc: Shape {
    var crescent = false
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height), cell = side / 9
        var path = Path()
        for row in 0..<9 {
            for column in 0..<9 {
                let x = (CGFloat(column) + 0.5) / 9, y = (CGFloat(row) + 0.5) / 9
                let distance = hypot(x - 0.5, y - 0.5)
                guard distance < 0.5 else { continue }
                if crescent, hypot(x - 0.72, y - 0.30) < 0.47 { continue }
                let radius = cell * (0.28 + 0.10 * (1 - distance * 2))
                let center = CGPoint(x: rect.midX + (x - 0.5) * side, y: rect.midY + (y - 0.5) * side)
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                          width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}

private struct MorningWidgetHorizon: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = min(1.1, rect.height / 2)
        for index in 0..<7 {
            let x = rect.width * (0.12 + CGFloat(index) * 0.126)
            path.addEllipse(in: CGRect(x: x - radius, y: rect.midY - radius,
                                      width: radius * 2, height: radius * 2))
        }
        return path
    }
}

/// The system updates this date-based progress without asking the app to run.
/// Its mask turns the native linear indicator into separated print impressions.
/// A paused budget uses its frozen snapshot; older payloads simply omit this track.
private struct MorningWidgetBudgetProgress: View {
    let timer: MorningActivityStepTimer
    let state: MorningActivityContentState
    let tint: Color
    var body: some View {
        Group {
            if let start = timer.startedAt, start.timeIntervalSinceReferenceDate.isFinite,
               timer.endsAt.timeIntervalSinceReferenceDate.isFinite, start < timer.endsAt,
               state.status != .paused {
                ProgressView(timerInterval: start...timer.endsAt, countsDown: false)
                    .progressViewStyle(.linear).labelsHidden().tint(tint)
                    .mask(MorningWidgetProgressDots())
            } else if let fraction = timer.elapsedFraction(at: state.updatedAt) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        MorningWidgetProgressDots().fill(tint.opacity(0.2))
                        MorningWidgetProgressDots().fill(tint)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: geometry.size.width * fraction)
                            }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct MorningWidgetProgressDots: Shape {
    func path(in rect: CGRect) -> Path {
        let count = max(2, Int(rect.width / 10))
        let radius = min(1.7, rect.height / 2)
        var path = Path()
        for index in 0..<count {
            let x = radius + (rect.width - radius * 2) * CGFloat(index) / CGFloat(count - 1)
            path.addEllipse(in: CGRect(x: x - radius, y: rect.midY - radius,
                                      width: radius * 2, height: radius * 2))
        }
        return path
    }
}
