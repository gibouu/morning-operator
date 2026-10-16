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
                .environment(\.locale, context.state.locale)
                .environment(\.layoutDirection, .leftToRight)
                .widgetURL(MorningActivityPresentation.destination)
        } dynamicIsland: { context in
            let presentation = MorningActivityPresentation(state: context.state, isStale: context.isStale)
            return DynamicIsland {
                // Keep all text below the camera. Side regions are too narrow
                // for localized status labels and meet the island's curved edge.
                DynamicIslandExpandedRegion(.bottom) {
                    MorningActivityIslandDetail(presentation: presentation,
                                                sessionID: context.attributes.sessionID)
                        .environment(\.locale, context.state.locale)
                        .environment(\.layoutDirection, .leftToRight)
                }
            } compactLeading: {
                HStack(spacing: 0) {
                    MorningBrandSymbol(appearance: presentation.appearance, contrasting: true)
                        .frame(width: 24, height: 22).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.accessibilitySummary)
            } compactTrailing: {
                if context.isStale {
                    Text("!").font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .accessibilityLabel(activityText("Update needed. Open MORE.", locale: context.state.locale))
                } else if let timer = context.state.stepTimer {
                    MorningActivityCompactTimer(timer: timer, state: context.state)
                        .environment(\.locale, context.state.locale)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    Text(presentation.shortProgress).font(.caption2.monospacedDigit())
                        .dynamicTypeSize(...DynamicTypeSize.large)
                        .lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 52)
                        .foregroundStyle(.white).accessibilityLabel(presentation.progress)
                }
            } minimal: {
                HStack(spacing: 0) {
                    MorningBrandSymbol(appearance: presentation.appearance, contrasting: true)
                        .frame(width: 24, height: 22).accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.accessibilitySummary)
            }
            .widgetURL(MorningActivityPresentation.destination)
            .keylineTint(MorningActivityPalette.islandAccent)
            .contentMargins(.horizontal, 18, for: .expanded)
            .contentMargins(.bottom, 14, for: .expanded)
        }
    }
}

private struct MorningActivityLockScreen: View {
    let state: MorningActivityContentState
    let isStale: Bool
    let sessionID: UUID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var presentation: MorningActivityPresentation { .init(state: state, isStale: isStale) }
    private var isNight: Bool { presentation.appearance == .night }
    private var ink: Color { isNight ? MorningActivityPalette.moon : MorningActivityPalette.ink }
    private var accent: Color { isNight ? MorningActivityPalette.moon : MorningActivityPalette.rust }
    private var muted: Color { isNight ? MorningActivityPalette.moon.opacity(0.8) : MorningActivityPalette.muted }
    private var background: Color { isNight ? MorningActivityPalette.night : MorningActivityPalette.paper }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                MorningBrandWordmark(appearance: presentation.appearance)
                    .frame(width: 100, height: 27).accessibilityHidden(true)
                Spacer(minLength: 8)
                Text(presentation.status).font(.caption.weight(.medium)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            #if MORE_JURY_DEMO
            JuryDemoIslandControls(sessionID: sessionID, paused: state.status == .paused)
            #endif
            if let timer = state.stepTimer {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        timerDetails(timer)
                        StepActivityControls(sessionID: sessionID, timer: timer, ink: ink, accent: accent, locale: state.locale)
                    }
                } else {
                    HStack(alignment: .center, spacing: 16) {
                        timerDetails(timer)
                        Spacer(minLength: 4)
                        StepActivityControls(sessionID: sessionID, timer: timer, ink: ink, accent: accent, locale: state.locale)
                    }
                }
                MorningWidgetBudgetProgress(timer: timer, state: state, tint: accent)
                    .frame(height: 4).padding(.top, 3)
            } else {
                Text(presentation.heading).font(.headline).foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(isStale ? activityText("Open MORE to update.", locale: state.locale) : presentation.progress)
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
        .accessibilityHint(activityText("Opens MORE's Morning screen.", locale: state.locale))
    }

    private func timerDetails(_ timer: MorningActivityStepTimer) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(timer.destination.displayName(locale: state.locale)).font(.subheadline.weight(.medium)).foregroundStyle(ink)
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                MorningBrandWordmark(appearance: presentation.appearance, contrasting: true)
                    .frame(width: 76, height: 20).accessibilityHidden(true)
                Text(presentation.status).font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let timer = presentation.state.stepTimer {
                Text(timer.destination.displayName(locale: presentation.state.locale))
                    .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                timerRow(timer)
                MorningWidgetBudgetProgress(timer: timer, state: presentation.state,
                                            tint: MorningActivityPalette.islandAccent).frame(height: 4)
            } else {
                Text(presentation.heading)
                    .font(dynamicTypeSize.isAccessibilitySize ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Text(presentation.isStale ? activityText("Open MORE to update.", locale: presentation.state.locale) : presentation.progress)
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        #if MORE_JURY_DEMO
        .safeAreaInset(edge: .bottom, spacing: 10) {
            JuryDemoIslandControls(sessionID: sessionID, paused: presentation.state.status == .paused)
        }
        #endif
        // Expanded activities have a fixed system height. Keep visual type within
        // that budget; VoiceOver still receives the complete state and labels.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilitySummary)
        .accessibilityHint(activityText("Opens MORE's Morning screen.", locale: presentation.state.locale))
    }

    private func timerRow(_ timer: MorningActivityStepTimer) -> some View {
        HStack(alignment: .center, spacing: 12) {
            StepCountdown(timer: timer, state: presentation.state)
                .font(.title3.weight(.medium).monospacedDigit()).foregroundStyle(.white)
                // A native date text has an unbounded ideal width. Do not ask
                // WidgetKit to archive it at its fixed size or measure it in
                // ViewThatFits; give this label a finite adaptive slot instead.
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 110, alignment: .leading)
                .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).remaining")
            Spacer(minLength: 4)
            controls(timer)
        }
    }

    private func controls(_ timer: MorningActivityStepTimer) -> some View {
        StepActivityControls(sessionID: sessionID, timer: timer, ink: .white,
                             accent: MorningActivityPalette.islandAccent, locale: presentation.state.locale)
            .fixedSize()
    }
}

/// Landscape on iOS 27 can offer only a 28-point circle. Use the timer's
/// graphical progress there; the full countdown remains in the expanded view
/// and in the accessibility representation.
private struct MorningActivityCompactTimer: View {
    let timer: MorningActivityStepTimer
    let state: MorningActivityContentState

    var body: some View {
        #if os(iOS)
        if #available(iOS 27.0, *) {
            LimitedWidthTimer(timer: timer, state: state)
        } else {
            countdown
        }
        #else
        countdown
        #endif
    }

    private var countdown: some View {
        StepCountdown(timer: timer, state: state)
            .font(.caption2.monospacedDigit()).foregroundStyle(.white)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(maxWidth: 52)
    }

    #if os(iOS)
    @available(iOS 27.0, *)
    private struct LimitedWidthTimer: View {
        let timer: MorningActivityStepTimer
        let state: MorningActivityContentState
        @Environment(\.isDynamicIslandLimitedInWidth) private var limitedWidth

        var body: some View {
            if limitedWidth {
                Group {
                    if state.status == .paused {
                        Image(systemName: "pause.fill")
                    } else if let start = timer.startedAt,
                              start.timeIntervalSinceReferenceDate.isFinite,
                              timer.endsAt.timeIntervalSinceReferenceDate.isFinite,
                              start < timer.endsAt {
                        ProgressView(timerInterval: start...timer.endsAt, countsDown: true)
                            .progressViewStyle(.circular).labelsHidden()
                    } else {
                        // Legacy snapshots have no budget origin. Keep the time
                        // accessible without inventing an elapsed fraction.
                        Image(systemName: "timer")
                    }
                }
                .font(.caption2).tint(MorningActivityPalette.islandAccent)
                .dynamicTypeSize(...DynamicTypeSize.large)
                .foregroundStyle(.white).frame(width: 22, height: 22)
                .accessibilityRepresentation {
                    Text(state.status.displayName(locale: state.locale))
                    StepCountdown(timer: timer, state: state)
                }
            } else {
                MorningActivityCompactTimer(timer: timer, state: state).countdown
            }
        }
    }
    #endif
}

private struct MorningActivityPresentation {
    let state: MorningActivityContentState
    let isStale: Bool
    static var destination: URL { URL(string: "\(scheme)://morning")! }
    static var scheme: String { Bundle.main.object(forInfoDictionaryKey: "MorningURLScheme") as? String ?? "more" }

    var heading: String { isStale ? activityText("Update needed", locale: state.locale) : state.category.displayName(locale: state.locale) }
    var status: String { isStale ? activityText("Update needed", locale: state.locale) : state.status.displayName(locale: state.locale) }
    // ActivityKit invokes this view on content/system updates; it does not offer
    // a widget timeline to guarantee a solar switch while the app is suspended.
    var appearance: MorningBrandAppearance { state.brandAppearance(at: Date()) }
    var shortProgress: String { "\(state.completedSteps)/\(state.totalSteps)" }
    var progress: String { activityText("\(state.completedSteps) of \(state.totalSteps) moments passed", locale: state.locale) }
    var lastUpdate: String { activityText("Last update \(state.updatedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(state.locale)))", locale: state.locale) }
    var accessibilitySummary: String {
        if isStale { return activityText("MORE. Update needed. Last saved progress: \(progress). \(lastUpdate). Open MORE to update.", locale: state.locale) }
        return activityText("MORE. \(state.category.displayName(locale: state.locale)). \(status). \(progress). \(lastUpdate).", locale: state.locale)
    }
}

private enum MorningActivityPalette {
    static let ink = color(MorningBrandPalette.ink)
    static let paper = color(MorningBrandPalette.paper)
    static let night = color(MorningBrandPalette.night)
    static let moon = color(MorningBrandPalette.moon)
    static let rust = color(MorningBrandPalette.rust)
    static let muted = Color(red: 0.310, green: 0.333, blue: 0.420)
    static let islandAccent = Color(red: 0.949, green: 0.635, blue: 0.435)

    private static func color(_ value: UInt32) -> Color {
        Color(.sRGB, red: Double((value >> 16) & 255) / 255,
              green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
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
    let locale: Locale

    var body: some View {
        HStack(spacing: 12) {
            Button(intent: AddStepTimeIntent(sessionID: sessionID, stepID: timer.stepID, expectedEnd: timer.endsAt)) {
                VStack(spacing: 3) {
                    MorningWidgetControlGlyph(kind: .extend).frame(width: 23, height: 23)
                        .foregroundStyle(accent)
                    Text(activityText("+2 min", locale: locale)).font(.caption2.weight(.medium)).foregroundStyle(ink).fixedSize()
                }.frame(minWidth: 50, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(activityText("+2 min", locale: locale))
            .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).extend")
            Link(destination: StepNavigation.nextURL(sessionID: sessionID, stepID: timer.stepID,
                                                     scheme: MorningActivityPresentation.scheme)) {
                VStack(spacing: 3) {
                    MorningWidgetControlGlyph(kind: timer.hasNextStep ? .next : .finish)
                        .frame(width: 23, height: 23).foregroundStyle(accent)
                    if timer.hasNextStep { Text(activityText("Next", locale: locale)).font(.caption2.weight(.medium)).foregroundStyle(ink).fixedSize() }
                    else { Text(activityText("Finish", locale: locale)).font(.caption2.weight(.medium)).foregroundStyle(ink).fixedSize() }
                }.frame(minWidth: 50, minHeight: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(timer.nextLabel(locale: locale))
            .accessibilityIdentifier("stepActivity.\(MorningActivityPresentation.scheme).next")
        }
        .buttonStyle(.plain)
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
        // ActivityKit can ask a mask for its path during an unconstrained layout
        // pass. Wait for finite geometry before converting the dot count to Int.
        guard !rect.isEmpty, !rect.isInfinite, rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.maxX.isFinite, rect.maxY.isFinite else { return Path() }
        let count = Int(min(256, max(2, rect.width / 10)))
        let radius = min(1.7, rect.height / 2)
        var path = Path()
        for index in 0..<count {
            let fraction = CGFloat(index) / CGFloat(count - 1)
            let x = radius + (rect.width - radius * 2) * fraction
            path.addEllipse(in: CGRect(x: x - radius, y: rect.midY - radius,
                                      width: radius * 2, height: radius * 2))
        }
        return path
    }
}

/// Widget text follows the language pinned to its activity snapshot; ordinary
/// app language changes publish a new snapshot through the existing coordinator.
private func activityText(_ value: String.LocalizationValue, locale: Locale) -> String {
    AppLanguage.localized(value, bundle: AppLanguage.bundle(for: .main,
        languageCode: locale.language.languageCode?.identifier), locale: locale)
}

#if MORE_JURY_DEMO
private struct JuryDemoIslandControls: View {
    let sessionID: UUID
    let paused: Bool
    var body: some View {
        HStack(spacing: 24) {
            if paused {
                // iOS needs the foreground to reacquire a released microphone.
                Link(destination: URL(string: "more-demo://resume?session=\(sessionID.uuidString)")!) {
                    Image(systemName: "play.fill")
                }.accessibilityLabel("Reprendre dans MORE")
                    .accessibilityIdentifier("jury.demo.island.resume")
            } else {
                Button(intent: JuryDemoPlaybackIntent(sessionID: sessionID, command: "pause")) {
                    Image(systemName: "pause.fill")
                }.accessibilityLabel("Pause")
                    .accessibilityIdentifier("jury.demo.island.pause")
            }
            Button(intent: JuryDemoPlaybackIntent(sessionID: sessionID, command: "next")) {
                Image(systemName: "forward.end.fill")
            }.accessibilityLabel("Suivant")
                .accessibilityIdentifier("jury.demo.island.next")
            Button(intent: JuryDemoPlaybackIntent(sessionID: sessionID, command: "stop")) {
                Image(systemName: "stop.fill")
            }.accessibilityLabel("Arrêter")
                .accessibilityIdentifier("jury.demo.island.stop")
        }
        .buttonStyle(.plain).font(.title3).frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
#endif
