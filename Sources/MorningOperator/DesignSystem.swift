import SwiftUI
import MorningCore

typealias ViewState<Value> = SwiftUI.State<Value>

/// The short names every view uses. Each one reads the clock's theme, so a view that
/// asks for `MorningStyle.ink` follows the time of day on its own.
@MainActor
enum MorningStyle {
    static var ink: Color { MorningTheme.current.ink }
    static var muted: Color { MorningTheme.current.inkSoft }
    /// The accent for small text and icons.
    static var accent: Color { MorningTheme.current.accentText }
    /// The accent as a fill: marks, the sun, the current moment's dot.
    static var mark: Color { MorningTheme.current.accent }
    /// The fill of the primary control.
    static var controlTint: Color { MorningTheme.current.ink }
    static var onControl: Color { MorningTheme.current.onInk }
    static var green: Color { MorningTheme.current.positive }
    static var line: Color { MorningTheme.current.line }
    static var background: Color { MorningTheme.current.paper }
    static var surface: Color { MorningTheme.current.surface }
    /// A tinted surface for a selected chip.
    static var selected: Color { MorningTheme.current.selected }

    static func symbol(for kind: StepKind) -> String {
        switch kind {
        case .briefing: "sun.horizon.fill"
        case .messages: "bubble.left.and.bubble.right.fill"
        case .calendar: "calendar"
        case .wellbeing: "heart.fill"
        case .entertainment: "sparkles.tv"
        case .custom: "leaf.fill"
        }
    }
    static func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        if seconds < 60 { return String(localized: "\(Int(seconds)) sec") }
        return String(localized: "\(Int((seconds / 60).rounded())) min")
    }
}

/// A small, letter-spaced kicker: the print's small label.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(MorningTheme.Typography.label).tracking(1.4).foregroundStyle(MorningStyle.muted)
    }
}
struct StatusPill: View {
    let text: String
    var color: Color = MorningStyle.green
    var body: some View {
        Label { Text(text) } icon: { Circle().fill(color).frame(width: 6, height: 6) }
            .font(MorningTheme.Typography.label).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(MorningStyle.surface, in: Capsule())
            .overlay(MorningDottedFrame(cornerRadius: 100, spacing: 6).fill(color.opacity(0.65)))
    }
}
/// Opaque reading paper with sparse dotted frame accents.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(MorningTheme.Space.card).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            .overlay(MorningCardFrame())
    }
}
/// A card that is one button: the whole surface responds to a tap.
struct CardButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content.padding(MorningTheme.Space.card).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
                .overlay(MorningCardFrame())
                .contentShape(RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
        }.buttonStyle(.plain)
    }
}
/// A row inside a card that opens something: title, one line of detail, a chevron.
struct LinkRow: View {
    let title: String
    let detail: String
    var symbol: String? = nil
    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                MorningDottedIcon(systemName: symbol).foregroundStyle(MorningStyle.accent).frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(MorningTheme.Typography.heading)
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            MorningDottedIcon(systemName: "chevron.right").foregroundStyle(MorningStyle.muted).frame(width: 18, height: 18)
        }.frame(minHeight: 44).foregroundStyle(MorningStyle.ink)
    }
}
struct PageHeading: View {
    let eyebrow: String
    let title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: eyebrow)
            Text(title).font(MorningTheme.Typography.display).foregroundStyle(MorningStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !subtitle.isEmpty {
                Text(subtitle).font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
struct EmptyMoment: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            MorningDottedIcon(systemName: symbol).frame(width: 30, height: 30).foregroundStyle(MorningStyle.accent)
            Text(title).font(MorningTheme.Typography.title)
            Text(detail).font(MorningTheme.Typography.note).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(MorningTheme.Space.card + 4)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
            .overlay(MorningCardFrame())
    }
}

/// Decorative only. Higher contrast makes the same separated dots more visible.
private struct MorningCardFrame: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        MorningDottedFrame(cornerRadius: MorningTheme.Space.radius,
                           dotRadius: contrast == .increased ? 1.05 : 0.85)
            .fill(MorningStyle.ink.opacity(contrast == .increased ? 0.75 : 0.28))
            .accessibilityHidden(true).allowsHitTesting(false)
    }
}

/// Grouped forms and lists on the paper with surface rows, instead of iOS's grey
/// background and white cells. Rows that set their own background keep it.
struct MorningForm<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { Form { Group { content }.morningRows() }.morningListBackground() }
}
struct MorningList<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { List { Group { content }.morningRows() }.morningListBackground() }
}
extension View {
    func morningListBackground() -> some View {
        scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
    }
    func morningRows() -> some View {
        listRowBackground(MorningStyle.surface).listRowSeparatorTint(MorningStyle.line)
    }
}

/// A fixed design size that still follows the person's text size (Dynamic Type),
/// as the Human Interface Guidelines ask for every piece of text and symbol.
private struct ScaledSystemFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, design: Font.Design) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight; self.design = design
    }

    func body(content: Content) -> some View { content.font(.system(size: size, weight: weight, design: design)) }
}

extension View {
    func scaledFont(_ size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight = .regular,
                    design: Font.Design = .default) -> some View {
        modifier(ScaledSystemFont(size: size, relativeTo: style, weight: weight, design: design))
    }
}
