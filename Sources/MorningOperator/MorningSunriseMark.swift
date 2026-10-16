import SwiftUI
import MorningCore

/// Existing debug names remain source-compatible. The app now has one dotted mark.
enum MorningSunriseDesign: String, CaseIterable {
    case horizon, halo, radiance, ember

    static var current: Self {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-testing"), arguments.contains("--fixture-mode"),
           let option = arguments.first(where: { $0.hasPrefix("--sunrise-design=") }),
           let design = Self(rawValue: String(option.dropFirst("--sunrise-design=".count))) {
            return design
        }
        #endif
        return .horizon
    }
}

/// The same round impressions as the app icon and navigation family. The enclosing
/// button owns its accessible label and its hit target.
struct MorningSunriseMark: View {
    var design: MorningSunriseDesign = .current

    var body: some View {
        MorningBrandSymbol(appearance: MorningThemeClock.shared.brandAppearance)
            .frame(width: 112, height: 68)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
