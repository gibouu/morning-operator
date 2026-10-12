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
        !containsOwnMarketing(normalized(text)) && !meaningfulWords(text).isEmpty
    }

    private static func containsInterfaceOrPromotion(_ text: String) -> Bool {
        let value = normalized(text)
        let lines = Set(text.components(separatedBy: .newlines).map(normalized))
        // These identify a screen's role, not a person's chosen routine. Full-frame rejection
        // is intentionally conservative when a permission/setup overlay covers real content.
        let pickerHeading = ["screen sharing", "share your screen", "partage d ecran", "partager votre ecran"]
        let pickerControls = ["share screen", "share entire screen", "cancel", "microphone", "morning operator", "stop sharing"]
        if pickerHeading.contains(where: lines.contains), pickerControls.contains(where: value.contains) { return true }
        let excludedContexts = [
            "app library", "bibliotheque d apps", "home screen", "ecran d accueil",
            "learn my morning", "show your morning", "make your morning yours", "your rhythm",
            "your routine stays in your hands", "suggest a routine", "stop automatically after",
            "record a little of my morning", "on device learning", "enable screen recording",
            "your first draft is ready to review", "sample morning not your observed activity",
            "your mornings will find their shape", "your approved routine", "a draft for you to review",
            "your morning voice", "more natural voices"
        ]
        if excludedContexts.contains(where: lines.contains) || containsOwnMarketing(value) { return true }
        // Our Review screen describes this app's routine history, not external activity.
        // Require multiple distinctive pieces of its public copy; generic labels such as
        // "Average routine" must not exclude a real calendar entry or personal message.
        let ownReviewHeadings = ["learning your morning", "the last seven mornings", "find your rhythm"]
        let ownReviewMarkerCount = ownReviewHeadings.filter { lines.contains($0) }.count
            + (value.contains("routine timing excludes pauses") ? 1 : 0)
        if ownReviewMarkerCount >= 2 { return true }
        // The observed-first overview displays earlier derived labels. Feeding
        // those labels back as new activity would reinforce our own output.
        // Require its heading plus separate public UI copy, not either alone.
        if lines.contains("your observed mornings"),
           value.contains("with labeled samples") || value.contains("a recorded glimpse not time spent") {
            return true
        }
        // The glass home contains our saved/proposed routine, not new evidence
        // that those activities happened. Match its exact heading and distinctive
        // footer/control copy; neither "morning" nor an event mentioning a sample
        // is enough. Vision may place both footer columns on one recognized line.
        let glassHomeFooters = [
            "sample morning", "your rhythm at your pace", "hold to arrange",
            "sample morning hold to arrange", "your rhythm at your pace hold to arrange"
        ]
        let hasGlassHomeFooter = glassHomeFooters.contains(where: lines.contains)
        let homeHeadings = ["morning", "good morning", "bonjour"]
        if homeHeadings.contains(where: lines.contains),
           hasGlassHomeFooter || lines.contains("a new rhythm ready to review") { return true }
        // The simplified approved home has no permanent explanatory footer.
        // While native capture runs, its visible branded recording control is
        // paired with the exact heading. Neither generic word alone is a guard.
        // Accept only complete control/heading lines (including a merged row),
        // not a message or event that happens to discuss recording a morning.
        // A non-recording import without these markers remains heuristic-limited.
        if (homeHeadings.contains(where: lines.contains) && lines.contains("more recording")) ||
            homeHeadings.contains(where: { lines.contains($0 + " more recording") }) { return true }
        // The active home omits its large heading and the arrange instruction.
        // Require its distinctive footer plus the paired state/playback controls.
        if hasGlassHomeFooter,
           (lines.contains("now") && lines.contains("pause")) ||
           (lines.contains("paused") && lines.contains("continue")) { return true }
        // The V2 shell deliberately removes the persistent brand heading. Use paired,
        // distinctive controls/copy, not generic words such as Morning, planned or MORE.
        let moreScreenPairs = [
            ["start my morning", "update my morning"],
            ["a little perspective", "settings connections"],
            ["more room for your day", "anything you d like to remember"],
            ["show more a little of your morning", "we ll find the rhythm together"],
            ["show us a little of your morning", "we ll find the rhythm together"]
        ]
        if moreScreenPairs.contains(where: { pair in pair.allSatisfy(value.contains) }) { return true }
        let onboardingControls = ["free trial", "subscribe now", "create your account", "sign up to continue", "get started"]
        if onboardingControls.filter({ lines.contains($0) }).count >= 2 { return true }
        // Launcher category grids can remain after a heading is missed by OCR.
        let launcherCategories = ["recently added", "suggestions", "social", "entertainment", "productivity"]
        return launcherCategories.filter { lines.contains($0) }.count >= 3
    }

    private static func containsOwnMarketing(_ text: String) -> Bool {
        ["less handling more morning", "that game of chess let s make space",
         "let s make space for the things you care about"].contains(where: text.contains)
            || (text.contains("the briefing the messages") && text.contains("that game of chess"))
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

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
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
