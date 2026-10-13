import SwiftUI
import MorningCore
#if os(iOS)
import UIKit
#else
import AppKit
#endif

typealias ViewState<Value> = SwiftUI.State<Value>

enum MorningStyle {
    static let ink = Color.primary
    // A warm gray that keeps at least 4.5:1 contrast on the beige background and on
    // cards (system .secondary is about 3.3:1 there in light mode).
    static let muted = adaptive(light: (0.42, 0.38, 0.33), dark: (0.74, 0.70, 0.65))
    static let accent = adaptive(light: (0.48, 0.31, 0.12), dark: (0.93, 0.73, 0.44))
    static let controlTint = Color(red: 0.48, green: 0.31, blue: 0.12)
    static let green = adaptive(light: (0.24, 0.49, 0.39), dark: (0.56, 0.77, 0.65))
    static let line = Color.primary.opacity(0.08)
    static let background = adaptive(light: (0.97, 0.94, 0.87), dark: (0.12, 0.10, 0.11))
    static let surface = adaptive(light: (0.99, 0.965, 0.905), dark: (0.20, 0.16, 0.15))
    static let lavender = adaptive(light: (0.89, 0.86, 0.97), dark: (0.26, 0.23, 0.36))
    static let sage = adaptive(light: (0.85, 0.91, 0.83), dark: (0.21, 0.29, 0.23))
    static let paleOrange = adaptive(light: (0.98, 0.88, 0.76), dark: (0.35, 0.27, 0.20))
    static let blue = adaptive(light: (0.85, 0.90, 0.97), dark: (0.22, 0.27, 0.36))

    static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        #if os(iOS)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #else
        Color(nsColor: NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
        #endif
    }

    static func color(for kind: StepKind) -> Color {
        switch kind {
        case .briefing: paleOrange
        case .messages: lavender
        case .calendar: blue
        case .wellbeing: sage
        case .entertainment: lavender
        case .custom: sage
        }
    }
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
        if seconds < 60 { return "\(Int(seconds)) sec" }
        return "\(Int((seconds / 60).rounded())) min"
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.headline)
            .padding(.horizontal, 22).padding(.vertical, 16)
            .foregroundStyle(.white)
            .background(MorningStyle.controlTint.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}
/// The primary brown fill at the secondary button's compact size, so the two
/// actions sit side by side without the primary one dominating.
struct CompactPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(MorningStyle.controlTint.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.45)
    }
}
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.semibold))
            .padding(.horizontal, 18).padding(.vertical, 14)
            .foregroundStyle(.primary)
            .background(MorningStyle.surface.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(MorningStyle.line, lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(MorningStyle.muted)
    }
}
struct StatusPill: View {
    let text: String
    var color: Color = MorningStyle.green
    var body: some View {
        Label { Text(text) } icon: { Circle().fill(color).frame(width: 5, height: 5) }
            .font(.caption.weight(.semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.09), in: Capsule())
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 26))
    }
}
/// A card that is one button: the whole rounded surface, including its padding
/// and the space between the text and the chevron, responds to a tap.
struct CardButton<Content: View>: View {
    let action: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        Button(action: action) {
            content.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 26))
                .contentShape(RoundedRectangle(cornerRadius: 26))
        }.buttonStyle(.plain)
    }
}
struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
            Text(subtitle).font(.subheadline).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
struct EmptyMoment: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: symbol).scaledFont(30, relativeTo: .title, weight: .light).foregroundStyle(MorningStyle.accent)
                .frame(width: 64, height: 64).background(MorningStyle.lavender, in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.title2.weight(.medium))
            Text(detail).font(.subheadline).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 28))
    }
}

/// Grouped forms and lists on the app's beige background with warm rows that
/// match cards, instead of iOS's grey background and white cells. Rows that set
/// their own background keep it.
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
        scrollContentBackground(.hidden).background(MorningStyle.background.ignoresSafeArea())
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
