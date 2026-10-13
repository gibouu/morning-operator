import Foundation

enum LearningEvidenceKind: String, Equatable, Sendable {
    case userReportedActivity
    case visibleTaskContent
}

struct LearningEvidenceUnit: Sendable {
    let text: String
    let kind: LearningEvidenceKind
}

/// Conservative provenance checks before inference and after generation. An exact OCR quote
/// proves text was visible; it does not establish that a person performed the described action.
/// These checks deliberately prefer abstention over turning setup or marketing into a routine.
/// This is a narrow heuristic, not comprehensive scene classification or proof of user actions.
enum LearningEvidencePolicy {
    static func prepare(_ input: String) throws -> [LearningEvidenceUnit] {
        let units: [LearningEvidenceUnit]
        if input.contains("[Observed frame at ") || input.contains("[User-selected video:") {
            // Filter whole frames before chunking: splitting first can detach marketing copy
            // from its identifying UI context and make an invalid quote appear legitimate.
            var frames: [String] = []
            var current: [String] = []
            var inFrame = false
            for line in input.components(separatedBy: .newlines) {
                if line.hasPrefix("[Observed frame at ") {
                    if inFrame { frames.append(current.joined(separator: "\n")) }
                    current = []
                    inFrame = true
                } else if inFrame, !line.hasPrefix("[Recording coverage:") {
                    current.append(line)
                }
            }
            if inFrame { frames.append(current.joined(separator: "\n")) }
            units = frames.filter(isEligibleVisualContext).map {
                LearningEvidenceUnit(text: $0, kind: .visibleTaskContent)
            }
        } else if input.contains("[User-selected screenshot;") {
            let body = input.components(separatedBy: .newlines)
                .filter { !$0.hasPrefix("[User-selected screenshot;") && !$0.hasPrefix("[Recording coverage:") }
                .joined(separator: "\n")
            units = isEligibleVisualContext(body) ? [.init(text: body, kind: .visibleTaskContent)] : []
        } else {
            // Written descriptions remain a separate positive path. Pasted onboarding copy
            // and bare interface inventories still do not become reports of personal actions.
            units = isEligibleWrittenContext(input) ? [.init(text: input, kind: .userReportedActivity)] : []
        }
        var seen = Set<String>()
        let unique = units.filter { seen.insert("\($0.kind.rawValue):\(ObservationText.normalized($0.text))").inserted }
        guard !unique.isEmpty else { throw AppleIntelligenceError.insufficientActivityEvidence }
        return unique
    }

    static func inferenceChunks(_ units: [LearningEvidenceUnit], maximumCharacters: Int) -> [String] {
        // Coalesce eligible frames into the same character-bounded batches used for notes.
        // A 24-frame recording must not create 24 independent model sessions.
        ObservationText.chunks(units.map(\.text).joined(separator: "\n\n"), maximumCharacters: maximumCharacters)
    }

    static func supports(quote: String, source: String, context: String,
                         kind: LearningEvidenceKind, claimedKind: String) -> Bool {
        guard claimedKind == kind.rawValue, !quote.isEmpty, Data(source.utf8).range(of: Data(quote.utf8)) != nil, quote.count >= 8,
              !meaningfulWords(quote).isEmpty else { return false }
        switch kind {
        case .userReportedActivity:
            return isEligibleWrittenContext(context)
        case .visibleTaskContent:
            return isEligibleVisualContext(context) && containsTaskContent(quote)
        }
    }

    static func isEligibleVisualContext(_ text: String) -> Bool {
        !containsInterfaceOrPromotion(text) && containsTaskContent(text)
    }

    static func isEligibleWrittenContext(_ text: String) -> Bool {
        // A person's own description may legitimately mention setup, screen sharing,
        // Messages or chess. Do not apply visual-screen classification to that description.
        !OwnInterfaceWording.containsMarketing(.init(text)) && !meaningfulWords(text).isEmpty
    }

    private static func containsInterfaceOrPromotion(_ text: String) -> Bool {
        let value = normalized(text)
        let lines = Set(text.components(separatedBy: .newlines).map(normalized))
        // These identify a screen's role, not a person's chosen routine. Full-frame rejection
        // is intentionally conservative when a permission/setup overlay covers real content.
        let pickerHeading = ["screen sharing", "share your screen", "partage d ecran", "partager votre ecran"]
        let pickerControls = ["share screen", "share entire screen", "cancel", "microphone", "morning operator", "stop sharing"]
        if pickerHeading.contains(where: lines.contains), pickerControls.contains(where: value.contains) { return true }
        // The system launcher. MORE's own screens are recognized from `OwnInterfaceWording`,
        // which follows the String Catalogs in every shipped language.
        let launcherHeadings = ["app library", "bibliotheque d apps", "home screen", "ecran d accueil"]
        if launcherHeadings.contains(where: lines.contains) || OwnInterfaceWording.identifies(.init(text)) { return true }
        let onboardingControls = ["free trial", "subscribe now", "create your account", "sign up to continue", "get started"]
        if onboardingControls.filter({ lines.contains($0) }).count >= 2 { return true }
        // Launcher category grids can remain after a heading is missed by OCR.
        let launcherCategories = ["recently added", "suggestions", "social", "entertainment", "productivity"]
        return launcherCategories.filter { lines.contains($0) }.count >= 3
    }

    private static func containsTaskContent(_ text: String) -> Bool {
        let value = normalized(text)
        if ["white to move", "black to move", "checkmate"].contains(where: value.contains) { return true }
        for line in text.components(separatedBy: .newlines) {
            let words = meaningfulWords(line)
            // A visible event time plus its content, not the status-bar clock or app name.
            let hasTime = line.range(of: #"\b\d{1,2}[:h]\d{2}\b"#, options: .regularExpression) != nil
            if hasTime && words.count >= 2 { return true }
            if words.count >= 4 && line.count >= 20 { return true }
        }
        return false
    }

    private static func meaningfulWords(_ text: String) -> [String] {
        normalized(text).split(separator: " ").map(String.init).filter {
            $0.count > 1 && $0.contains(where: \.isLetter) && !interfaceWords.contains($0)
        }
    }

    /// Lowercase words without accents or punctuation, so a recognized line compares equal
    /// to interface wording however Vision rendered its case, apostrophes or ligatures.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "æ", with: "ae")
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    private static let interfaceWords: Set<String> = [
        "calendar", "calendars", "calendrier", "chess", "messages", "message", "mail", "email",
        "photos", "camera", "settings", "reglages", "safari", "phone", "contacts", "facetime",
        "maps", "music", "wallet", "weather", "clock", "notes", "reminders", "health",
        "app", "apps", "library", "home", "search", "cancel", "done", "back", "next", "continue",
        "allow", "deny", "share", "screen", "recording", "start", "stop", "on", "off",
        "today", "tomorrow", "yesterday", "month", "year", "day", "week", "all", "edit",
        "mon", "tue", "wed", "thu", "fri", "sat", "sun", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec", "am", "pm", "the", "and", "of", "to", "for"
    ]
}
