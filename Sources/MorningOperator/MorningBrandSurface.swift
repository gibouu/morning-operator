import SwiftUI
import MorningCore

/// Shared chrome sits outside navigation so screen titles and actions keep their space.
struct MorningBrandHeader: View {
    var body: some View {
        MorningBrandWordmark(appearance: MorningThemeClock.shared.brandAppearance)
            .frame(width: 112, height: 30)
            .frame(maxWidth: .infinity, minHeight: 32)
            .padding(.horizontal, 20)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "MORE"))
            .accessibilityIdentifier("brand.wordmark")
            .accessibilityValue(MorningThemeClock.shared.brandAppearance.rawValue)
            .allowsHitTesting(false)
    }
}

extension View {
    func morningBrandSurface() -> some View {
        safeAreaInset(edge: .top, spacing: 0) {
            MorningBrandHeader().background(MorningStyle.background)
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
