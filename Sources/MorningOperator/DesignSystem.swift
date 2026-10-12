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
    static let muted = Color.secondary
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
        Text(text.uppercased()).font(.caption2.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
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
struct PageHeading: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: eyebrow)
            Text(title).font(.system(.largeTitle, design: .serif, weight: .medium))
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
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
            Image(systemName: symbol).font(.system(size: 30, weight: .light)).foregroundStyle(MorningStyle.accent)
                .frame(width: 64, height: 64).background(MorningStyle.lavender, in: RoundedRectangle(cornerRadius: 22))
            Text(title).font(.title2.weight(.medium))
            Text(detail).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(26)
            .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: 28))
    }
}
