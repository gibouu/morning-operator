import Foundation

/// Localized fragments appended to suggested step details. Creation writes the
/// current language; validation and display read every language ever saved.
public enum EvidenceDetailText {
    public static var label: String { String(localized: "Evidence:", bundle: .module) }

    public static func line(_ quote: String) -> String { line(quote, label: label) }

    public static var tentativeNote: String {
        String(localized: "Tentative suggestion from selected evidence; duration is planned, not measured.", bundle: .module)
    }

    // A step detail is saved with the fragments of the language it was written in, and
    // is later validated and displayed under any interface language. Reading therefore
    // recognizes every fragment ever shipped, never only the current translation.
    // Append when a translation is added or reworded; never edit or remove an entry.

    /// Every evidence label a saved step detail may carry.
    public static let savedLabels = ["Evidence:", "Source :"]

    /// Every tentative note a saved step detail may carry.
    public static let savedTentativeNotes = [
        "Tentative suggestion from selected evidence; duration is planned, not measured.",
        "Suggestion provisoire tirée des éléments choisis ; la durée est prévue, pas mesurée."
    ]

    /// Whether a saved detail retains this exact quotation as an evidence line,
    /// whichever language wrote it.
    public static func detail(_ detail: String, retains quote: String) -> Bool {
        let bytes = Data(detail.utf8)
        return readableLabels.contains { bytes.range(of: Data(line(quote, label: $0).utf8)) != nil }
    }

    /// The description that precedes the generated note and evidence lines of a saved detail.
    public static func description(of detail: String) -> String {
        let markers = readableLabels.map { "\n\($0)" }
            + (savedTentativeNotes + [tentativeNote]).map { "\n\($0)" }
        let end = markers.compactMap { detail.range(of: $0)?.lowerBound }.min() ?? detail.endIndex
        return String(detail[..<end])
    }

    // The current label is included so a reworded translation cannot reject its own new proposals.
    private static var readableLabels: [String] { savedLabels.contains(label) ? savedLabels : savedLabels + [label] }

    private static func line(_ quote: String, label: String) -> String { "\(label) “\(quote)”" }

    public static var visibleContentNote: String {
        String(localized: "Visible content only; this does not prove an action or repeated habit.", bundle: .module)
    }

    public static var suggestedDurationNote: String {
        String(localized: "Suggested duration; review before approving.", bundle: .module)
    }
}
