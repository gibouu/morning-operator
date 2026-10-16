import SwiftUI

/// Bundled brand artwork stays legible on both settings appearances.
struct MorningConnectionIcon: View {
    var serviceID: String? = nil
    var fallbackSymbol: String

    var body: some View {
        Group {
            if let assetName {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(.black.opacity(0.65))
            }
        }
        .frame(width: 32, height: 32)
        .background(.white, in: RoundedRectangle(cornerRadius: 7))
        .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(.black.opacity(0.06)) }
        .accessibilityHidden(true)
    }

    private var assetName: String? {
        guard let serviceID else { return nil }
        let id = serviceID.lowercased() == "x" ? "twitter" : serviceID.lowercased()
        guard Self.brandedServices.contains(id) else { return nil }
        return "Connection-\(id)"
    }

    private static let brandedServices: Set<String> = [
        "instagram", "tiktok", "twitter", "whatsapp", "reddit", "facebook", "threads", "youtube",
        "gmail", "outlook", "googlecalendar", "googledrive", "googledocs", "googlesheets",
        "notion", "slack", "calendly", "linkedin", "discord"
    ]
}
