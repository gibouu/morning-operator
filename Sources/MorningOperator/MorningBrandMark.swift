import MorningCore
import SwiftUI

/// App-owned wordmark: every surface reads the same solar decision.
struct MorningBrandMark: View {
    var body: some View {
        MorningBrandWordmark(appearance: MorningThemeClock.shared.brandAppearance)
            .accessibilityIdentifier("brand.wordmark")
            .accessibilityValue(Text(verbatim: MorningThemeClock.shared.brandAccessibilityValue))
            .allowsHitTesting(false)
    }
}
