import SwiftUI
import MorningCore

/// Shared chrome sits outside navigation so screen titles and actions keep their space.
struct MorningBrandHeader: View {
    static let height: CGFloat = 32

    var body: some View {
        MorningBrandWordmark(appearance: MorningThemeClock.shared.brandAppearance)
            .frame(width: 112, height: 30)
            .frame(maxWidth: .infinity, minHeight: Self.height)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "MORE"))
            .accessibilityIdentifier("brand.wordmark")
            .accessibilityValue(Text(verbatim: MorningThemeClock.shared.brandAccessibilityValue))
            .allowsHitTesting(false)
    }
}

extension View {
    /// Over the Home landscape the header keeps its space but holds no wordmark:
    /// arriving in MORE shows the landscape alone. Other screens carry the wordmark.
    func morningBrandSurface(overLandscape: Bool = false) -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                if !overLandscape { MorningBrandHeader().transition(.opacity) }
            }
            .frame(maxWidth: .infinity, minHeight: MorningBrandHeader.height)
            .animation(.easeOut(duration: 0.2), value: overLandscape)
            .background(overLandscape ? Color.clear : MorningStyle.background)
        }
        .preferredColorScheme(MorningThemeClock.shared.brandAppearance == .night ? .dark : .light)
    }

    func morningSheet<Sheet: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping () -> Sheet) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content().morningBrandSurface()
        }
    }

    func morningSheet<Item: Identifiable, Sheet: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                      @ViewBuilder content: @escaping (Item) -> Sheet) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item).morningBrandSurface()
        }
    }

    func morningFullScreenCover<Cover: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                            @ViewBuilder content: @escaping () -> Cover) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            content().morningBrandSurface()
        }
    }
}
