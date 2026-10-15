import SwiftUI

/// Original fine-grain sunset artwork with its generated alpha preserved.
/// The caller owns position and size, so the existing solar clock can place it.
/// Never tint or mask this image: its cream light and feathered rust edge are baked
/// into the original asset, while the surrounding paper remains transparent.
struct MorningSolarArtwork: View {
    var opacity: Double
    private let image: Image

    /// The image override lets native component previews load the unchanged PNG
    /// without rebuilding an application asset catalog.
    init(opacity: Double = 1, image: Image = Image("SolarSunFineV1")) {
        self.opacity = opacity
        self.image = image
    }

    var body: some View {
        image
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .opacity(min(1, max(0, opacity)))
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
