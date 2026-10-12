import Foundation

/// Localized fragments appended to suggested step details. Creation, validation
/// and display all go through these so the markers stay consistent per language.
public enum EvidenceDetailText {
    public static var label: String { String(localized: "Evidence:", bundle: .module) }

    public static func line(_ quote: String) -> String { "\(label) “\(quote)”" }

    /// Separator that begins the evidence lines inside a step detail.
    public static var separator: String { "\n\(label)" }

    public static var tentativeNote: String {
        String(localized: "Tentative suggestion from selected evidence; duration is planned, not measured.", bundle: .module)
    }

    public static var visibleContentNote: String {
        String(localized: "Visible content only; this does not prove an action or repeated habit.", bundle: .module)
    }

    public static var suggestedDurationNote: String {
        String(localized: "Suggested duration; review before approving.", bundle: .module)
    }
}
