import Foundation
import Testing
@testable import MorningApple

/// The String Catalogs as shipped, read from the repository.
private struct ShippedCatalogs {
    /// One catalog's `strings` dictionary per file.
    var catalogs: [[String: Any]]
    var sourceLanguage: String

    private static var repository: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../..").standardizedFileURL
    }

    static func load() throws -> ShippedCatalogs {
        var catalogs: [[String: Any]] = []
        var source = "en"
        // The app's catalog first, then the shared modules'.
        for path in ["Resources/Localizable.xcstrings", "Sources/MorningCore/Resources/Localizable.xcstrings",
                     "Sources/MorningApple/Resources/Localizable.xcstrings"] {
            let data = try Data(contentsOf: repository.appendingPathComponent(path))
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            catalogs.append(try #require(root["strings"] as? [String: Any]))
            source = root["sourceLanguage"] as? String ?? source
        }
        return ShippedCatalogs(catalogs: catalogs, sourceLanguage: source)
    }

    /// Every language any shipped string is translated into, with the source language.
    var languages: [String] {
        var found: Set<String> = [sourceLanguage]
        for catalog in catalogs {
            for entry in catalog.values {
                found.formUnion(((entry as? [String: Any])?["localizations"] as? [String: Any] ?? [:]).keys)
            }
        }
        return found.sorted()
    }

    /// The values one localization can produce, grouped so that the forms of one plural stay together.
    private static func valueGroups(_ node: [String: Any]) -> [[String]] {
        var groups: [[String]] = []
        if let value = (node["stringUnit"] as? [String: Any])?["value"] as? String { groups.append([value]) }
        for forms in (node["variations"] as? [String: Any] ?? [:]).values {
            let cases = (forms as? [String: Any] ?? [:]).values.compactMap { $0 as? [String: Any] }
            groups.append(cases.flatMap { valueGroups($0).flatMap { $0 } })
        }
        // Only the substitutions the string actually uses reach the screen.
        let used = groups.flatMap { $0 }.joined(separator: " ").replacingOccurrences(of: "%%", with: "")
        for (name, substitution) in node["substitutions"] as? [String: Any] ?? [:] where used.contains("%#@\(name)@") {
            groups += valueGroups(substitution as? [String: Any] ?? [:])
        }
        return groups
    }

    /// What each catalog holding `key` shows for it in `language`; nil when no catalog can.
    func valueGroups(for key: String, in language: String) -> [[[String]]]? {
        var found: [[[String]]] = []
        for catalog in catalogs {
            guard let entry = catalog[key] as? [String: Any] else { continue }
            if let node = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] {
                found.append(Self.valueGroups(node))
            } else if language == sourceLanguage {
                found.append([[key]])
            } else {
                return nil
            }
        }
        return found.isEmpty ? nil : found
    }

    /// The single string shown for `key` in `language`, for building a screen fixture.
    func text(_ key: String, _ language: String) throws -> String {
        let groups = try #require(valueGroups(for: key, in: language), "No \(language) text for “\(key)”")
        return try #require(groups.first?.first?.first)
    }

    /// Everything that would let recognition drift from what the app shows. Empty when in step.
    func drift(of phrases: [OwnInterfaceWording.Phrase]) -> [String] {
        var problems: [String] = []
        for phrase in phrases {
            guard let key = phrase.catalogKey else { continue }
            let entries = catalogs.compactMap { $0[key] as? [String: Any] }
            guard !entries.isEmpty else {
                problems.append("“\(key)” is no longer in a String Catalog. Keep it as earlier wording and add what replaced it.")
                continue
            }
            // The screens are the app's: a copy in a shared module does not stand in for its entry.
            if catalogs.first?[key] == nil {
                problems.append("“\(key)” is no longer in the app's String Catalog. Keep it as earlier wording and add what replaced it.")
                continue
            }
            if entries.contains(where: { $0["extractionState"] as? String == "stale" }) {
                problems.append("“\(key)” is stale: the app no longer shows it. Keep it as earlier wording and add what replaced it.")
            }
            for language in languages {
                guard let perCatalog = valueGroups(for: key, in: language) else {
                    problems.append("“\(key)” has no \(language) text in a catalog that ships it.")
                    continue
                }
                for groups in perCatalog {
                    let values = groups.flatMap { $0 }.map(LearningEvidencePolicy.normalized)
                    let recognized: Bool
                    if phrase.isPartOfCatalogString {
                        // Every form of one plural (or the one plain string) must contain the clause.
                        recognized = groups.contains { group in
                            !group.isEmpty && group.allSatisfy { value in
                                let shown = " \(LearningEvidencePolicy.normalized(value)) "
                                return phrase.normalized.contains { shown.contains(" \($0) ") }
                            }
                        }
                    } else {
                        recognized = !values.isEmpty && values.allSatisfy(phrase.normalized.contains)
                    }
                    if !recognized {
                        problems.append("“\(key)” reads \(groups) in \(language), which the policy does not recognize.")
                    }
                }
            }
        }
        return problems
    }

    /// A copy with one string changed, to prove the guard notices.
    func changing(_ key: String, _ change: (inout [String: Any]) -> Void) throws -> ShippedCatalogs {
        var copy = self
        let index = try #require(copy.catalogs.firstIndex { $0[key] != nil })
        var entry = try #require(copy.catalogs[index][key] as? [String: Any])
        change(&entry)
        copy.catalogs[index][key] = entry
        return copy
    }

    /// The Swift that puts text on screen: everything but the recognition table itself.
    static func appSources() throws -> String {
        let sources = repository.appendingPathComponent("Sources")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let views = files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "OwnInterfaceWording.swift" }
        try #require(views.count > 50)
        // A string that survives only in a comment is not shown.
        return try views.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
            .replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)(?<!:)//.*$"#, with: "", options: .regularExpression)
    }
}

/// MORE's screens as a recording would show them. Text comes from the catalogs by key, in
/// screen order, wrapped the way recognized lines arrive: a paragraph spans several lines.
private enum OwnScreenFixtures {
    static let learn = [
        "Your rhythm", "Make your morning yours.",
        "You'll review every suggestion.",
        "Show us your morning",
        "Record a short part of your morning, or choose a saved file.",
        "Record", "Choose",
        "A screenshot or text file works too. You choose what to share.",
        "Add context, if you like", "Build it myself",
        "Suggest a routine", "About on-device learning",
        "Each observation is saved on this device, with its original text and your corrections kept separately. Find earlier observations in Review. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it.",
        "A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention.",
        "Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you.",
        "Check availability again"
    ]
    static let review = [
        "Average routine time", "Time in your routine, excluding pauses. Other app use isn't measured here.",
        "Saved observations", "Original evidence and your corrections",
        "Your routine", "Build a routine that feels like you",
        "Learn from a morning", "Record, describe or refine",
        "Saved thoughts", "A place for what comes to mind",
        "App activity", "Today's connected app entries",
        "Settings & connections", "Voice, calendar and preferences"
    ]
    static let settings = [
        "Your next morning", "Your day", "Calendar & weather",
        "Morning at a glance", "Keep your place on the Lock Screen.",
        "A voice to guide you", "Companion voice", "Read each step aloud",
        "Try the voice", "Listen where you like",
        "Use the audio output picker to choose an available speaker, including a HomePod on your network.",
        "Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet.",
        "Privacy & data", "Saved on this device", "Apple Intelligence", "Check again",
        "You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable.",
        "Connecting a phone to a Mac doesn't automatically give this app control of the phone. The separate development test runner is needed for the phone-control experiment.",
        "Messages and email aren't connected here yet. Automatic room detection and continuous voice commands also need further work."
    ]
    static let routine = [
        "Your routine", "A draft for you to review",
        "%lld min planned · Your own pace", "%lld min planned · Spoken guidance", "%lld min planned · Your own pace",
        "%lld min planned · Spoken guidance", "%lld min planned · Your own pace", "%lld min planned · Spoken guidance",
        "%lld min planned · Your own pace", "%lld min planned · Spoken guidance", "%lld min planned · Your own pace",
        "%lld min planned · Spoken guidance", "%lld min planned · Your own pace", "%lld min planned · Spoken guidance",
        "Add a moment",
        "Minutes are planned. Editing creates a new draft; your saved mornings keep their original routine.",
        "Restore previous routine", "Export routine", "Learn from an observation",
        "Restoring a routine leaves your saved choices for future suggestions unchanged.", "Approve this routine"
    ]
    static let recording = [
        "Confirm Apple's picker, then go through your morning. This screen closes when recording begins. We stop at your chosen limit and save the visible text for you to review when you return.",
        "Stop automatically after", "Start screen recording", "You're in control",
        "This records visible screen content without sound or camera video. Keep the part you want to teach short; other personal content on screen may also appear.",
        "Recording stops at your chosen time limit or its file-size limit. This is a time limit, not a guess that you stopped using your phone. You can stop earlier using the app or the system controls.",
        "When recording finishes, visible text is extracted and saved locally. Review the text, then choose whether to ask Apple Intelligence for a routine suggestion. Your routine changes only after you approve. The video stays on this device until its extracted text is saved, or until you discard it."
    ]
    static let voice = [
        "Automatic",
        "Matches your device’s language and dialect, then prefers a higher-quality installed voice. Your choice applies to spoken morning steps.",
        "Preview selected voice",
        "Listen through your current audio output. These are Apple system speech voices; Siri may use a different voice.",
        "Installed voices", "A voice’s language affects pronunciation. Choosing it does not translate your routine.",
        "More natural voices",
        "In Settings → Accessibility → Read & Speak → Voices, choose your language and download an Enhanced or Premium voice if offered. Return here after the download finishes.",
        "Refresh installed voices"
    ]
    static let step = [
        "Make it yours", "Your moment", "Keep it simple. You can change the order of your steps back in your routine.",
        "How it fits", "The category organizes your routine. Choose an action below to decide what Morning Operator does.",
        "Keep in future suggestions", "Keep this duration", "Future mornings",
        "Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices later in Review.",
        "User-led moment", "What Morning Operator does", "Remove this step"
    ]
    static let privacy = [
        "Your mornings stay close.",
        "MORE keeps its learning on this device. You choose when to connect Apple apps and what to keep.",
        "Saved in MORE", "Current routine", "Previous routine", "Saved mornings", "Saved choices",
        "Save app activity from Shortcuts", "App activity",
        "Only Shortcuts you configure can log app names and entry/exit times. This doesn't record taps or read messages. Removing local data turns this off until you enable it again.",
        "Your day",
        "Calendar events and prepared recaps stay in memory. MORE saves only the calendars you select, your chosen weather city and temperature unit.",
        "City searches go to Apple Maps. Weather requests send the selected city’s coordinates to Apple Weather. Screen content and learning aren't sent with these requests.",
        "Outside MORE",
        "Originals in Photos or Files, exported copies, and items already saved in Calendar or Reminders stay where they are.",
        "Apple permissions, installed voices, Shortcuts and device backups are managed separately. Removing local data doesn't change them or erase copies outside this app.",
        "Forget MORE’s local data"
    ]
    static let all = [("Learn", learn), ("Review", review), ("Settings", settings),
                      ("Routine", routine), ("Recording", recording), ("Voice", voice),
                      ("Step", step), ("Privacy", privacy)]

    /// Recognized lines for a screen: each string on its own lines, long ones wrapped.
    static func lines(_ keys: [String], _ language: String, from catalogs: ShippedCatalogs, width: Int = 38) throws -> [String] {
        try keys.flatMap { wrapped(try catalogs.text($0, language), width: width) }
    }

    static func wrapped(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        for paragraph in text.components(separatedBy: .newlines) {
            var line = ""
            for word in paragraph.split(separator: " ") {
                if !line.isEmpty, line.count + 1 + word.count > width { lines.append(line); line = "" }
                line += (line.isEmpty ? "" : " ") + word
            }
            lines.append(line)
        }
        return lines
    }

    /// One piece of a screen that also displays text MORE did not write.
    enum Piece {
        /// A catalog string, by key.
        case shown(String)
        /// An earlier observation's text, a derived label, a date or the model's words.
        case other(String, String)
        /// A line of MORE's own with a count in it, written out because its catalog string is a plural.
        case counted(String, String)
    }

    /// A screen whose content is mostly an earlier observation or a suggestion from the model.
    struct ContentScreen {
        let name: String
        /// What stays while the content scrolls: the navigation bar above, any bar below.
        var top: [Piece] = []
        var bottom: [Piece] = []
        let body: [Piece]
        /// Every scroll position is recognized even when neither bar is read.
        var recognizedWithoutBars = true

        func lines(_ pieces: [Piece], _ language: String, from catalogs: ShippedCatalogs, width: Int) throws -> [String] {
            try pieces.flatMap { piece -> [String] in
                switch piece {
                case .shown(let key): return wrapped(try catalogs.text(key, language), width: width)
                case .other(let english, let french), .counted(let english, let french):
                    return wrapped(language == "fr" ? french : english, width: width)
                }
            }
        }
    }

    private static let meeting = Piece.other("09:00 Team planning meeting with the design group",
                                             "09:00 Réunion de planification avec l’équipe de design")
    private static let reply = Piece.other("Reply to Paul about the printed meeting notes before lunch",
                                           "Répondre à Paul au sujet des notes imprimées avant le déjeuner")
    private static let sampleRows: [Piece] = [
        .other("00:00", "00:00"), .other("Calendar", "Calendrier"), .other("00:05", "00:05"), .shown("Unknown screen"),
        .other("00:10", "00:10"), .other("Messages", "Messages"), .other("00:15", "00:15"), .other("Calendar", "Calendrier")
    ]
    private static let observationDates: [Piece] = [
        .shown("Observed day"), .other("Oct 9, 2026", "9 oct. 2026"), .shown("Time zone"), .other("Europe/Paris", "Europe/Paris"),
        .shown("Day recorded by this recording session."), .shown("Origin"), .other("My morning", "Ma matinée"),
        .shown("Imported"), .other("Oct 9, 2026 at 8:12 AM", "9 oct. 2026 à 08:12"), .shown("Change day or origin"),
        .shown("Import time is separate from the day you observed. These dates don't establish how long you used your phone."),
        .shown("Recording details"), .shown("Read a saved moment"), .shown("Edit in Learn"),
        // Both disclosures open: the notes in use, then the text read from the recording.
        .shown("Current notes"), meeting, reply, .shown("Original extracted text"), meeting, reply,
        .shown("Corrections change the notes used for suggestions. The original evidence stays available here."),
        .shown("Recording evidence")
    ]
    /// One saved observation with its sampled moments in order.
    static let observation = ContentScreen(name: "Observation", top: [.shown("Observation")], body: observationDates + [
        .shown("Sampled moments"), .other("3 of 4 sampled moments labeled · 1 unresolved", "3 sur 4 moments échantillonnés identifiés · 1 non résolu"),
        .other("Calendar → Messages → Calendar", "Calendrier → Messages → Calendrier"),
        .shown("No return is established by these samples."), .shown("View sampled screens"),
        .shown("Activity between these sampled moments is unknown.")
    ] + sampleRows + [
        .shown("Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls."),
        .shown("Delete this observation")
    ])
    /// The same observation when its frame times are not in order.
    static let unorderedObservation = ContentScreen(name: "Observation, samples unordered", top: [.shown("Observation")],
                                                    body: observationDates + [
        .shown("Saved samples"), .other("4 source samples · chronology unresolved", "4 échantillons sources · chronologie non résolue"),
        .shown("These samples have not been interpreted."), .shown("View sampled screens"),
        .shown("Original samples in extraction order")
    ] + sampleRows + [
        .shown("Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls."),
        .shown("Delete this observation")
    ])
    /// One sampled screen. Under its original text nothing of MORE is left but the title.
    static let sampledMoment = ContentScreen(name: "Sampled moment", top: [.shown("Sampled moment"), .shown("Done")], body: [
        .shown("A visual label is a proposal about what's visible. It doesn't establish which app was open or what you did."),
        .shown("Times are offsets into this recording, rounded to a millisecond."),
        .shown("Requested sample"), .other("00:05.000", "00:05,000"), .shown("Actual frame"), .other("00:05.012", "00:05,012"),
        .shown("Proposed visual label"), .other("Calendar", "Calendrier"), .shown("Exact evidence quote"), meeting,
        .shown("Read this saved moment"), .shown("Correct label"), .shown("Original extracted text"),
        .other("Friday, October 9", "vendredi 9 octobre"), meeting, reply,
        .other("12:30 Lunch with the product team at the corner café", "12:30 Déjeuner avec l’équipe produit au café du coin"),
        .other("15:00 Review the quarterly budget with finance", "15:00 Revue du budget trimestriel avec la finance"),
        .other("17:30 Pick up the children from football practice", "17:30 Aller chercher les enfants à l’entraînement de football"),
        .shown("Source sample")
    ], recognizedWithoutBars: false)
    /// Learn after a recording: the text just read from it, to correct, and its sampled screens.
    static let learnReview = ContentScreen(name: "Learn, what we could see", top: [.shown("Learn my morning"), .shown("Done")], body: [
        .shown("What we could see"),
        .shown("Correct the text below. The original stays in Saved observations."),
        meeting, reply, .shown("A glimpse of this recording"),
        .other("42 seconds · 9 samples · 7 with complete text", "42 secondes · 9 échantillons · 7 avec texte complet"),
        .shown("See sampled screens"),
        .shown("These are occasional views of your screen. They can't count every scroll, prove a message was read, or measure complete app use."),
        .other("Calendar → Messages", "Calendrier → Messages"),
        .shown("Order of recognized appearances. Unknown samples may hide other activity."),
        .shown("Recognize sampled screens"), .other("00:05", "00:05"), .other("Calendar", "Calendrier"), meeting,
        .shown("Uses Apple Intelligence on this device. Editing the observation removes its attached frame evidence and screen interpretation.")
    ])
    /// Seven days of observations: derived screen labels, then each day's clips.
    static let observedMornings = ContentScreen(name: "Observed mornings", top: [.shown("Observed mornings")], body: [
        .other("2026-10-07 – 2026-10-13", "2026-10-07 – 2026-10-13"), .shown("Screens that appeared across your mornings."),
        .shown("These labels describe sampled screens. They don't measure time in apps, reads or scrolls. Missing samples stay unknown."),
        .other("My mornings · Europe/Paris", "Mes matinées · Europe/Paris"),
        .counted("2 days with labeled samples · 2 days with observations", "2 jours avec échantillons identifiés · 2 jours avec observations"),
        .other("Weekly team planning workshop", "Atelier hebdomadaire de planification de l’équipe"),
        .counted("Seen on 2 of 2 days with labeled samples", "Vu sur 2 des 2 jours avec échantillons identifiés"),
        .shown("Conflicting labels are excluded from this pattern list. Their original samples remain in each observation."),
        .shown("The seven days"), .other("2026-10-09", "2026-10-09"),
        .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov"),
        .other("3 labeled moments · 1 unresolved", "3 moments identifiés · 1 non résolu"),
        .other("2026-10-10", "2026-10-10"), .shown("No observation"),
        .shown("Dates use the time zone saved with each observation. Separate clips are never joined into one continuous timeline.")
    ])
    /// The same review of samples or tests, scrolled to its labels and its other closing sentence.
    static let observedSamples = ContentScreen(name: "Observed mornings, samples", top: [.shown("Observed mornings")], body: [
        .other("Weekly team planning workshop", "Atelier hebdomadaire de planification de l’équipe"),
        .counted("Seen on 2 of 2 days with labeled samples", "Vu sur 2 des 2 jours avec échantillons identifiés"),
        .other("Reply to family messages", "Répondre aux messages de la famille"),
        .counted("Seen on 2 of 2 days with labeled samples", "Vu sur 2 des 2 jours avec échantillons identifiés"),
        .shown("The seven days"),
        .shown("This evidence stays separate from personal mornings. Dates and origins can be reviewed in the source observation.")
    ])
    /// A lower card of Review's observed mornings, its heading scrolled away.
    static let observedOverview = ContentScreen(name: "Observed overview", body: [
        .shown("Samples & tests"), .other("Europe/Paris", "Europe/Paris"),
        .counted("2 days with labeled samples · 2 days with observations", "2 jours avec échantillons identifiés · 2 jours avec observations"),
        .other("Weekly team planning workshop", "Atelier hebdomadaire de planification de l’équipe"), .counted("2 of 2 labeled days", "2 sur 2 jours identifiés"),
        .other("Reply to family messages", "Répondre aux messages de la famille"), .counted("2 of 2 labeled days", "2 sur 2 jours identifiés"),
        .counted("0 observed days without labels · 5 dates without observations", "0 jour observé sans libellé · 5 dates sans observation"),
        .counted("Showing 3 of 4 labels. All labels and quotations are below.", "3 libellés affichés sur 4. Tous les libellés et citations sont ci-dessous."),
        .counted("Unresolved samples remain on 2 observed days.", "Des échantillons non résolus restent sur 2 jours observés."),
        .shown("A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls."),
        .shown("From your observations"), .shown("Sampled screens across days")
    ])
    /// The quotations behind one screen label, as its first screen shows them.
    static let sourceMoments = ContentScreen(name: "Source moments", top: [.shown("Source moments")], body: [
        .other("Calendar", "Calendrier"),
        .counted("Seen on 2 distinct days. Open a quote to inspect the original sampled screen.",
               "Vu sur 2 jours distincts. Ouvrez une citation pour examiner l’écran échantillonné d’origine."),
        .shown("A proposed visual label doesn't establish an app's identity or an action you took."),
        .other("2026-10-09 · Europe/Paris", "2026-10-09 · Europe/Paris"), meeting,
        .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov")
    ])
    /// Choosing a line of a saved observation to hear again.
    static let savedMoment = ContentScreen(name: "Saved moment", top: [.shown("A saved moment"), .shown("Done")], body: [
        .shown("Keep a thought from a morning you've saved. Choose the words you want to hear again."),
        .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov"),
        .shown("What you'll hear"), meeting, .shown("Hear preview"), .shown("Add to my morning"),
        .shown("The date is spoken too. This is a saved excerpt, not today's messages. MORE checks its source before every playback."),
        .shown("Choose an excerpt"), meeting, reply,
        .other("12:30 Lunch with the product team at the corner café", "12:30 Déjeuner avec l’équipe produit au café du coin"),
        .shown("Up to 24 short, complete lines from the saved text. Check extracted words against the recording; screen recognition can make mistakes.")
    ])
    /// Correcting a sampled screen's label: excerpts of its original text to choose from.
    static let screenLabel = ContentScreen(name: "Screen label", top: [.shown("Screen label")], body: [
        .shown("Your label"), .other("Calendar", "Calendrier"),
        .shown("Describe the screen, such as Calendar or Messages. This changes your review, not the original recording or the model's result."),
        .shown("Keep this screen unknown"),
        .shown("Unknown screens stay visible in your review and are left out of new activity suggestions."),
        .shown("Original excerpt"), meeting, reply,
        .other("12:30 Lunch with the product team at the corner café", "12:30 Déjeuner avec l’équipe produit au café du coin"),
        .shown("Choose the saved words that help you recognize this screen. Your label is your interpretation; it doesn't prove an app was opened or a message was read.")
    ])
    private static let historyRows: [Piece] = (9...14).flatMap { day -> [Piece] in
        [.other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov"), .other("Oct \(day), 2026", "\(day) oct. 2026"),
         .other("Europe/Paris", "Europe/Paris")]
    }
    /// The list of saved observations. Its rows are names and dates.
    static let observations = ContentScreen(name: "Observations", top: [.shown("Observations"), .shown("Choose mornings")], body: [
        .shown("Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use.")
    ] + historyRows + [.shown("Delete all observations")], recognizedWithoutBars: false)
    static let choosingObservations = ContentScreen(
        name: "Observations, choosing", top: [.shown("Observations"), .shown("Done choosing")],
        bottom: [.shown("Choose one to five observations."), .shown("Suggest an update")], body: [
            .shown("Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use."),
            .shown("Choose dated observations from your own mornings, or a separate set of samples. Nothing is selected automatically.")
        ] + historyRows, recognizedWithoutBars: false)
    private static func suggestedStep(_ title: (String, String), _ detail: (String, String), quoted: Bool = false) -> [Piece] {
        [.other(title.0, title.1), .other(detail.0, detail.1), .other("5 minutes planned", "5 minutes prévues"), .shown("Why this suggestion?")]
            + (quoted ? [.other("“09:00 Team planning meeting with the design group”", "« 09:00 Réunion de planification avec l’équipe de design »"),
                         .other("Oct 9, 2026 · Original text", "9 oct. 2026 · Texte d’origine"),
                         .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov")] : [])
    }
    /// A suggestion from the model, one "Why this suggestion?" open on its quotation. Between
    /// its first and last lines nothing identifies it but the title above and the buttons below.
    static let suggestedUpdate = ContentScreen(
        name: "Suggested update", top: [.shown("Suggested update"), .shown("Done")],
        bottom: [.shown("Keep current"), .shown("Approve update")], body: [
            .shown("Your next morning"), .other("Selected: 2 observations across 2 dated days", "Sélection : 2 observations sur 2 jours datés"),
            .shown("Your current routine stays ready until you approve."), .shown("Compare with current routine")
        ] + suggestedStep(("Review today’s calendar", "Consulter le calendrier du jour"),
                          ("Look through the meetings planned for this morning and prepare the first one.",
                           "Parcourir les réunions prévues ce matin et préparer la première."), quoted: true)
          + suggestedStep(("Reply to family messages", "Répondre aux messages de la famille"),
                          ("Answer the messages that arrived overnight from the family group.",
                           "Répondre aux messages arrivés pendant la nuit dans le groupe de la famille."))
          + suggestedStep(("Read the morning news", "Lire les nouvelles du matin"),
                          ("Read the headlines and one longer article over breakfast.",
                           "Lire les titres et un article plus long pendant le petit déjeuner."))
          + suggestedStep(("Plan the afternoon", "Préparer l’après-midi"),
                          ("Write down the three tasks that matter most after lunch.",
                           "Noter les trois tâches qui comptent le plus après le déjeuner."))
          + [.shown("Selected observations"), .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov"),
             .other("Oct 9, 2026 · Original text", "9 oct. 2026 · Texte d’origine"),
             .shown("Correct a source in Learn to request a new suggestion."), .shown("About this suggestion")],
        recognizedWithoutBars: false)
    /// Some observations chosen: the sentence under the list gives way to a count.
    static let chosenObservations = ContentScreen(
        name: "Observations, some chosen", top: [.shown("Observations"), .shown("Done choosing")],
        bottom: [.other("2 observations across 2 dated days", "2 observations sur 2 jours datés"),
                 .shown("Clear selection"), .shown("Suggest an update")],
        body: historyRows, recognizedWithoutBars: false)
    /// Scrolled into the quotations of one suggested step: no planned time, no sentence of MORE's.
    static let suggestedUpdateQuotations = ContentScreen(
        name: "Suggested update, quotations", top: [.shown("Suggested update"), .shown("Done")],
        bottom: [.shown("Keep current"), .shown("Approve update")],
        body: (9...12).flatMap { day -> [Piece] in
            [.other("“09:00 Team planning meeting with the design group. Discuss the release schedule.”",
                    "« 09:00 Réunion de planification avec l’équipe de design. Discuter du calendrier de sortie. »"),
             .other("Oct \(day), 2026 · Original text", "\(day) oct. 2026 · Texte d’origine"),
             .other("Team planning workshop video.mov", "Atelier de planification de l’équipe.mov")]
        }, recognizedWithoutBars: false)
    static let contentScreens = [learnReview, observation, unorderedObservation, sampledMoment, observedOverview, observedMornings, observedSamples, sourceMoments, savedMoment, screenLabel, observations, choosingObservations,
                                 chosenObservations, suggestedUpdate, suggestedUpdateQuotations]

    /// The home while MORE records and a saved routine runs: the date and the badge, the heading
    /// read as one line with the invitation time and the planned minutes, then the person's steps.
    static func runningHome(_ language: String, dateRow: [String]? = nil) -> [String] {
        language == "fr"
            ? (dateRow ?? ["mar. 13 oct.", "MORE · Enregistrement"]) + [
                "bonjour 07:30 25 min", "Maintenant", "Lire les messages de ma famille", "Pause",
                "Préparer le petit déjeuner des enfants", "10 min", "Faire une promenade dans le quartier", "10 min"]
            : (dateRow ?? ["Tue, Oct 13", "MORE · Recording"]) + [
                "good morning 7:30 AM 25 min", "Now", "Read messages from my family", "Pause",
                "Prepare breakfast for the children", "10 min", "Walk around the neighbourhood", "10 min"]
    }

    // Written out by hand from the French interface, independent of the table and the catalogs.
    static let frenchLearn = """
    Apprendre ma matinée
    Terminé
    VOTRE RYTHME
    Faites de votre matinée
    la vôtre.
    Partez de ce que vous faites déjà. Vous relirez chaque
    suggestion avant qu’elle ne devienne votre routine.
    Montrez-nous votre matinée
    Lancez un enregistrement que vous partagez
    explicitement, ou apportez-en un existant.
    Enregistrer
    Choisir
    """
    static let frenchReview = """
    7 oct. – 13 oct. 2026
    Durée moyenne de la routine
    Temps passé dans votre routine, pauses exclues.
    L’utilisation des autres apps n’est pas mesurée ici.
    Observations enregistrées
    Éléments d’origine et vos corrections
    Votre routine
    Apprendre d’une matinée
    Enregistrer, décrire ou affiner
    Réglages et connexions
    Voix, calendrier et préférences
    """
    static let frenchSettings = """
    Réglages
    Terminé
    FAITES COMME CHEZ VOUS
    Quelques réglages, à votre
    façon.
    Choisissez ce que vous connectez et comment votre
    matinée doit sonner.
    Votre journée
    Un peu de contexte avant que votre matinée commence.
    La matinée en un coup d'oeil
    Gardez votre progression sur l’écran verrouillé.
    Confidentialité et données
    """
    static let englishLearn = """
    Learn my morning
    Done
    YOUR RHYTHM
    Make your morning
    yours.
    Start with what you already do. You'll review every
    suggestion before it becomes your routine.
    Show us your morning
    Start an explicitly shared recording or bring one
    you already made.
    Record
    Choose
    """
}

@Suite("MORE's own screens are recognized from the wording the app shows")
struct OwnInterfaceWordingTests {
    private func isOwnInterface(_ screen: String) -> Bool { !LearningEvidencePolicy.isEligibleVisualContext(screen) }

    // MARK: The table follows the String Catalogs

    @Test("Every recognized string still reads the same in the catalogs, in each shipped language")
    func recognizedWordingMatchesTheCatalogs() throws {
        let catalogs = try ShippedCatalogs.load()
        #expect(catalogs.languages == ["en", "fr"], "A new language needs its wording in OwnInterfaceWording.")
        #expect(catalogs.drift(of: OwnInterfaceWording.all) == [])
        // The comparison is not empty: every screen is recognized through wording the catalogs
        // still hold, sentences and labels both, and so are the badge and each pair of labels.
        let linked = OwnInterfaceWording.all.filter { $0.catalogKey != nil }
        for screen in OwnInterfaceWording.screens {
            #expect(screen.copy.contains { $0.catalogKey != nil }, "\(screen.name) has no sentence tied to a catalog.")
            #expect(screen.controls.contains { $0.catalogKey != nil }, "\(screen.name) has no label tied to a catalog.")
        }
        #expect(OwnInterfaceWording.recordingBadge.catalogKey == "MORE · Recording")
        // The badge is matched in the letter case the app shows, so its case must not drift either.
        #expect(try catalogs.languages.map { try catalogs.text("MORE · Recording", $0) } == OwnInterfaceWording.recordingBadge.wordings)
        #expect(OwnInterfaceWording.labelGroups.allSatisfy { group in group.count >= 2 && group.allSatisfy { $0.catalogKey != nil } })
        #expect(linked.allSatisfy { $0.wordings.count >= catalogs.languages.count })
        let record = try #require(OwnInterfaceWording.screens.first { $0.name == "Learn" }?
            .controls.first { $0.catalogKey == "Record" })
        #expect(record.wordings == ["Record", "Enregistrer"])
    }

    @Test("Rewording, retranslating, removing or half-translating a recognized string fails the comparison")
    func catalogChangesAreNoticed() throws {
        let catalogs = try ShippedCatalogs.load()
        let phrases = OwnInterfaceWording.all
        func french(_ value: String) -> (inout [String: Any]) -> Void {
            { entry in entry["localizations"] = ["fr": ["stringUnit": ["state": "translated", "value": value]]] }
        }
        // A new translation of the Learn button.
        #expect(try catalogs.changing("Record", french("Capturer")).drift(of: phrases).count == 1)
        // The view shows a new English string, so the old key leaves the catalog or goes stale.
        var removed = catalogs
        for index in removed.catalogs.indices { removed.catalogs[index]["Record"] = nil }
        #expect(removed.drift(of: phrases).count == 1)
        #expect(try catalogs.changing("Record") { $0["extractionState"] = "stale" }.drift(of: phrases).count == 1)
        var appOnly = catalogs
        appOnly.catalogs[0]["Paused"] = nil
        #expect(appOnly.drift(of: phrases).count == 1)
        // A translation is dropped, or a third language ships without its wording.
        #expect(try catalogs.changing("Record") { $0["localizations"] = [String: Any]() }.drift(of: phrases).count == 1)
        let german = try catalogs.changing("Choose") { entry in
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            localizations["de"] = ["stringUnit": ["state": "translated", "value": "Auswählen"]]
            entry["localizations"] = localizations
        }
        #expect(german.drift(of: phrases).count >= phrases.filter { $0.catalogKey != nil }.count)
        // A sentence the policy matches by one clause is rewritten.
        let sentence = "A screenshot or text file works too. You choose what to share."
        #expect(try catalogs.changing(sentence, french("Une image ou un fichier texte convient aussi."))
            .drift(of: phrases).count == 2)
        // One plural form of a counted line loses the recognized words.
        let counted = "%lld days with labeled samples · %lld days with observations"
        let plural = try catalogs.changing(counted) { entry in
            var text = String(decoding: try! JSONSerialization.data(withJSONObject: entry), as: UTF8.self)
            text = text.replacingOccurrences(of: "%arg jours avec échantillons identifiés", with: "%arg jours identifiés")
            entry = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        }
        // Reported once for each phrase that rests on those words: the overview's rule and its cards.
        #expect(plural.drift(of: phrases).count == 2)
        // The counted line stops using the part that holds the recognized words.
        let unused = try catalogs.changing(counted) { entry in
            var text = String(decoding: try! JSONSerialization.data(withJSONObject: entry), as: UTF8.self)
            text = text.replacingOccurrences(of: "%#@a@ · %#@b@", with: "%#@b@")
            entry = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        }
        #expect(unused.drift(of: phrases).count == 4)
    }

    @Test("Every recognized catalog string is one the app's source still shows")
    func recognizedWordingIsShownByTheApp() throws {
        let sources = try ShippedCatalogs.appSources()
        func literal(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        for phrase in OwnInterfaceWording.all {
            guard let key = phrase.catalogKey else { continue }
            let expected = phrase.isPartOfCatalogString ? literal(phrase.wordings[0]) : "\"\(literal(key))\""
            #expect(sources.contains(expected), "No view shows \(expected) any more.")
        }
        // The Learn button itself, not only some string with the same text.
        #expect(sources.contains(#"Label("Record", systemImage: "record.circle")"#))
        // The table's own literals are not counted as the app showing them.
        #expect(!sources.contains("enum OwnInterfaceWording"))
    }

    @Test("Sentences are specific enough to count; short labels are kept as controls")
    func copyIsLongEnoughToBeDistinctive() {
        for screen in OwnInterfaceWording.screens {
            #expect(screen.copy.count >= 2)
            // Two sentences count as two pieces, so neither may be found inside the other.
            let wordings = screen.copy.map(\.normalized)
            for (index, sentence) in wordings.enumerated() {
                #expect(!wordings.indices.contains { other in
                    other != index && sentence.contains { mine in wordings[other].contains { " \($0) ".contains(" \(mine) ") } }
                })
            }
            for wording in screen.copy.flatMap(\.normalized) {
                #expect(wording.split(separator: " ").count >= 4, "“\(wording)” is too short to identify \(screen.name).")
            }
        }
        for phrase in OwnInterfaceWording.all {
            #expect(phrase.normalized.allSatisfy { !$0.isEmpty })
        }
    }

    // MARK: MORE's screens are rejected, in English and in French

    @Test("Learn, Review and Settings as the catalogs word them are not evidence", arguments: ["en", "fr"])
    func ownScreensFromTheCatalogsAreRejected(language: String) throws {
        let catalogs = try ShippedCatalogs.load()
        for (name, keys) in OwnScreenFixtures.all {
            let lines = try OwnScreenFixtures.lines(keys, language, from: catalogs)
            let screen = lines.joined(separator: "\n")
            #expect(isOwnInterface(screen), "\(name) in \(language) passed as evidence.")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
            }
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + screen, as: .screenshot)
            }
            // Scrolled anywhere: any fourteen consecutive lines (a phone shows more) still show
            // enough of the screen, without its navigation title and whatever the wrapping width.
            for width in [34, 42, 52] {
                let wrapped = try OwnScreenFixtures.lines(keys, language, from: catalogs, width: width)
                for start in 0...max(0, wrapped.count - 14) {
                    let visible = wrapped[start..<min(wrapped.count, start + 14)].joined(separator: "\n")
                    #expect(isOwnInterface(visible), "\(name) in \(language), from line \(start) at width \(width):\n\(visible)")
                }
            }
        }
    }

    @Test("Hand-written English and French screens are rejected, and their text cannot ground a step")
    func writtenOutScreensAreRejected() {
        for screen in [OwnScreenFixtures.englishLearn, OwnScreenFixtures.frenchLearn,
                       OwnScreenFixtures.frenchReview, OwnScreenFixtures.frenchSettings] {
            #expect(isOwnInterface(screen))
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
            }
        }
        let quote = "Lancez un enregistrement que vous partagez"
        #expect(ProposalValidation.step(title: "Enregistrer", detail: "", kind: "custom", durationMinutes: 3,
            evidenceQuote: quote, source: OwnScreenFixtures.frenchLearn, sourceContext: OwnScreenFixtures.frenchLearn,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
    }

    @Test("The shortened Learn button is recognized with the text around it, and the earlier button still is")
    func learnButtonWordingOldAndNew() {
        // Heading scrolled away and the navigation title unread: the button and one paragraph.
        for screen in ["Start an explicitly shared recording or bring\none you already made. Go through a short part\nRecord\nChoose",
                       "Lancez un enregistrement que vous partagez\nexplicitement, ou apportez-en un existant. Vivez\nEnregistrer\nChoisir",
                       "Record\nChoose\nA screenshot or text file works too. Only the\nfile you choose is read",
                       "ENREGISTRER\nCHOISIR\nUne capture d'écran ou un fichier texte fonctionne\naussi. Seul le fichier choisi est lu"] {
            #expect(isOwnInterface(screen), "Passed as evidence:\n\(screen)")
        }
        // A label is judged against the wording actually on screen, not its other translation.
        #expect(isOwnInterface("Time in your routine, excluding pauses.\nVotre routine"))
        // A line of a wrapped sentence from another screen is not this screen's label.
        #expect(!isOwnInterface("A recording is sampled at up to 24 moments\nRecord,\ndescribe or refine"))
        // A sentence shown twice still leaves its second reading free to pair with another.
        #expect(isOwnInterface("Use the audio output picker to choose an available speaker. Output doesn't connect a HomePod microphone.\nUse the audio output picker to choose an available speaker."))
        // Recordings made before the button was shortened, and its French form.
        for button in ["Record a little of my morning", "Enregistrer un peu de ma matinée"] {
            #expect(isOwnInterface("Calendar\n\(button)\n09:00 Team planning meeting"))
        }
    }

    @Test("The French home, welcome, overview and recording screens are rejected like the English ones")
    func frenchFormsOfEarlierRulesAreRecognized() {
        let planned = "09:00 Réunion de planification de l’équipe"
        for screen in [
            "bonjour\n19 min\n\(planned)\nMatinée d’exemple",
            "Matinée\n\(planned)\nMatinée d'exemple",
            "bonjour\nMORE · Enregistrement\n\(planned)",
            "bonjour MORE · Enregistrement\n\(planned)",
            "Maintenant\nPause\n\(planned)\nMatinée d’exemple",
            "En pause\nReprendre\n\(planned)\nMatinée d’exemple",
            "Votre matinée\nMontrez-nous un peu de votre matinée.\nNous trouverons le rythme ensemble.",
            "Vos matinées observées\n2 jours avec échantillons identifiés · 3 jours avec observations\n\(planned)",
            "Vos matinées observées\nUn aperçu enregistré, pas un temps passé. Ces échantillons\nn’établissent ni ouvertures d’apps\n\(planned)",
            "Montrez votre matinée\nArrêter automatiquement après\n\(planned)",
            "La voix de votre matinée\nDes voix plus naturelles\n\(planned)",
            "Vos matinées vont prendre forme.\n\(planned)",
            // A saved routine's steps under its French heading, with the footer scrolled away.
            "Votre routine\nTerminé\nVotre routine approuvée\nLire les messages de ma famille\n5 min prévues · À votre rythme\nPréparer le petit déjeuner des enfants\n10 min prévues · À votre rythme",
            "Un brouillon à relire\nÉcouter les nouvelles du matin\n5 min prévues · Guidage vocal",
            // Review with runs whose timing is incomplete, before its links scroll into view.
            "Vendredi\n9 oct.\nRien d’enregistré\nUne matinée enregistrée. Durée encore inconnue.\n2 sessions enregistrées n’ont pas de durée complète.\nElles n’entrent pas dans la moyenne.",
            "Friday\nOct 9\nNothing saved\nA morning saved. Time still unknown.\n2 saved runs have no complete timing.\nThey stay out of the average.",
            // Scrolled past the heading: the sheet's title and rows that all read the same.
            "Votre routine\nModifier\nTerminé\nLire les messages de ma famille\n5 min prévues · À votre rythme\nFaire une promenade dans le quartier\n10 min prévues · À votre rythme",
            "Your routine\nEdit\nDone\nRead messages from my family\n5 min planned · Your own pace\nWalk around the neighbourhood\n10 min planned · Your own pace"
        ] {
            #expect(isOwnInterface(screen), "Passed as evidence:\n\(screen)")
        }
    }

    // MARK: The home while MORE records

    @Test("The home with a routine running is rejected by its recording badge", arguments: ["en", "fr"])
    func runningHomeIsRejectedByItsBadge(language: String) throws {
        let badge = language == "fr" ? "MORE · Enregistrement" : "MORE · Recording"
        let date = language == "fr" ? "mar. 13 oct." : "Tue, Oct 13"
        let home = OwnScreenFixtures.runningHome(language)
        // Without the badge this frame is what a recording of another app looks like: nothing
        // else on it is recognized, and the saved step titles read as real activity.
        #expect(!isOwnInterface(home.filter { $0 != badge }.joined(separator: "\n")))
        let dateRows: [[String]] = [
            [date, badge],                          // read as two lines
            ["\(date) \(badge)"],                   // read as one line
            ["\(date) v \(badge)"],                 // with the chevron beside the date
            ["\(date) v O \(badge)"], ["\(date) v", "O \(badge)"],   // and the badge's symbol
            ["\(date) v 0 \(badge)"], [date, "0 \(badge)"],
            [date, "O \(badge)"], [date, badge.replacingOccurrences(of: "·", with: "•")],
            [date, badge.replacingOccurrences(of: " ·", with: "")], ["\(date) \(badge.replacingOccurrences(of: " ·", with: ""))"],
            [badge],                                // the date not read: the heading and the playback labels remain
            [badge, date]
        ]
        for row in dateRows {
            let screen = OwnScreenFixtures.runningHome(language, dateRow: row).joined(separator: "\n")
            #expect(isOwnInterface(screen), "Passed as evidence:\n\(screen)")
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
            }
        }
        // The badge alone on its line is enough, whatever else the frame shows: only MORE's
        // home prints it. Its dot may be read as a zero or an "o".
        let step = home[4]
        for line in [badge, "0 \(badge)", "O \(badge)"] {
            #expect(isOwnInterface("\(line)\n\(step)"), "Passed as evidence with “\(line)”.")
            #expect(isOwnInterface("Calendar\n\(line)\n09:00 Team planning meeting"))
        }
        // The saved step cannot come back as the evidence for a suggested step.
        let screen = home.joined(separator: "\n")
        #expect(ProposalValidation.step(title: step, detail: "", kind: "messages", durationMinutes: 5,
            evidenceQuote: step, source: screen, sourceContext: screen,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
        // The frame after it, in another app, is still read.
        let next = "Calendar\n09:00 Team planning meeting"
        let units = try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n\(screen)\n\n[Observed frame at 00:10.0]\n\(next)", as: .recording)
        #expect(units.map(\.text) == [next])
    }

    @Test("Another app's “more” and “recording” are not the badge")
    func otherAppsRecordingWordsAreKept() throws {
        let screens = [
            // The two words apart, on one line or on neighbouring lines.
            "Voice Memos\nShow more\nRecording 12\n09:00 Team planning meeting",
            "Voice Memos\nTue, Oct 13\nMore\nRecording\n09:00 Team planning meeting",
            "Recorder\nRecording saved. Tap for more.\n09:00 Team planning meeting",
            "Dictaphone\nVoir plus\nEnregistrement 12\n09:00 Réunion de planification de l’équipe",
            "Dictaphone\nmar. 13 oct.\nPlus\nEnregistrement\n09:00 Réunion de planification de l’équipe",
            // The words together, as other apps write them.
            "Recorder\nTue, Oct 13\nmore recording options\nNow\nPause\n09:00 Team planning meeting",
            "Recorder\nTue, Oct 13\nMore recording options\n09:00 Team planning meeting",
            "Recorder\nTue, Oct 13\nMore Recording\nNow\nPause\n09:00 Team planning meeting",
            "Recorder\nTue, Oct 13\nNo more recording\nPause\n09:00 Team planning meeting",
            "Recorder\nOct 13 more recording\nPause\n09:00 Team planning meeting",
            "Recorder\nTue, Oct 13\nADD 1 MORE RECORDING\nPause\n09:00 Team planning meeting",
            "Recorder\nTue, Oct 13\nYou can save 1 more recording\nPause\n09:00 Team planning meeting",
            "Dictaphone\nmar. 13 oct.\nPlus d’enregistrement\nPause\n09:00 Réunion de planification de l’équipe",
            "Dictaphone\nmar. 13 oct.\nmore enregistrement\nMaintenant\n09:00 Réunion de planification de l’équipe",
            // The badge's own form after other words, or before them.
            "News\nTue, Oct 13\nREAD MORE · Recording\nNow\n09:00 Team planning meeting",
            "News\nTue, Oct 13\nMORE · Recording the album took two years\nNow\n09:00 Team planning meeting",
            "Calendar\nTue, Oct 13\n09:00 MORE · Recording\nNow\n10:00 Team planning meeting",
            // One word before the badge, even a single letter, makes it ordinary text.
            "Notes\nA MORE Recording\n09:00 Team planning meeting",
            "Notes\nA MORE Enregistrement\n09:00 Réunion de planification de l’équipe",
            "Recorder\n1 MORE Recording\n09:00 Team planning meeting",
            // The badge's words inside a sentence are ordinary text.
            "Messages\nPlease discuss MORE · Recording with the design team before 09:00 tomorrow."
        ]
        for screen in screens {
            #expect(!isOwnInterface(screen), "Wrongly rejected:\n\(screen)")
            #expect(try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording).count == 1)
        }
    }

    @Test("Every date the home can print beside its badge is recognized, in English and French with every region",
          arguments: ["en", "fr"])
    func everyPrintedHomeDateIsRecognized(language: String) throws {
        // The home's own format for each day of a leap year, in the app's language with each
        // region a phone can be set to: every weekday, month, day, order and numeric month.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let start = try #require(calendar.date(from: DateComponents(year: 2028, month: 1, day: 1)))
        let days = try (0..<366).map { try #require(calendar.date(byAdding: .day, value: $0, to: start)) }
        var printed = Set<String>()
        for region in Locale.Region.isoRegions {
            var style = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
            style.locale = Locale(identifier: "\(language)_\(region.identifier)")
            style.timeZone = calendar.timeZone
            printed.formUnion(days.map { $0.formatted(style) })
        }
        #expect(printed.count >= 366 * 2)
        let badge = language == "fr" ? "MORE · Enregistrement" : "MORE · Recording"
        for date in printed {
            let unpunctuated = String(date.map { $0.isLetter || $0.isNumber ? $0 : " " })
            // With its punctuation, without it, in capitals, and with the chevron and the dot.
            for row in [date, unpunctuated, date.uppercased(), "\(date) v O"] {
                #expect(isOwnInterface("Recorder\n\(row) \(badge)\n09:00 Team planning meeting"),
                        "Not read as the home's date: \(row)")
            }
        }
    }

    @Test("A number beside short words is not the home's date, so another app's line ending in the badge's words is kept",
          arguments: [
        "Save 1 MORE Recording", "9 AM MORE Recording", "Track 12 MORE Recording", "5 min MORE Enregistrement",
        "Save MORE Recording", "Save 32 MORE Recording", "Take 2 of 5 MORE Recording", "Oct 13 MORE Recording",
        "13 MORE Recording", "Tue MORE Recording", "Tue, Oct MORE Recording", "Tue, Oct 32 MORE Recording",
        "Tue, Feb 30 MORE Recording", "Tue, Oct 0 MORE Recording", "Tue, Oct 013 MORE Recording",
        "Tue, Oct 13 A B C D MORE Recording", "Tue, Oct 13 0 0 0 MORE Recording", "Tue, Oct 13 v v MORE Recording",
        "Tue 13 13 MORE Recording", "Tue 31 4 MORE Recording", "Tue 0 5 MORE Recording", "13 Tue Oct MORE Recording",
        "Tue 09:30 MORE Recording", "Tue 9:05 MORE Recording", "09:30 Tue MORE Recording", "Tue 09 30 MORE Recording",
        "mar. 9h05 MORE Enregistrement", "Tue 4 31 MORE Recording", "31 4 Tue MORE Recording", "Tue, Oct 13 2026 MORE Recording",
        "Tue, Oct 13 at 9 MORE Recording", "Tue, mars 13 MORE Recording", "mar. 13 Feb MORE Enregistrement",
        "mar. 13 Oct 9 MORE Enregistrement", "lun. 31 avr. MORE Enregistrement", "Day 13 Oct MORE Recording",
        "Tue Tue 13 MORE Recording", "Set 1 Tue MORE Recording", "Mon 3 Jan 4 MORE Recording"
    ])
    func numberedLinesAreNotTheHomeDate(line: String) throws {
        let screen = "Recorder\n\(line)\n09:00 Team planning meeting"
        #expect(!OwnInterfaceWording.identifies(.init(screen)))
        #expect(!isOwnInterface(screen), "Wrongly rejected:\n\(screen)")
        let units = try LearningEvidencePolicy.prepare(frames: [screen])
        #expect(units.map(\.text) == [screen])
        #expect(units.first?.kind == .visibleTaskContent)
    }

    // MARK: Screens that display an earlier observation or a suggestion

    @Test("Screens that display an earlier observation or a suggestion are not evidence, wherever they are scrolled",
          arguments: ["en", "fr"])
    func screensShowingEarlierTextAreRejected(language: String) throws {
        let catalogs = try ShippedCatalogs.load()
        for screen in OwnScreenFixtures.contentScreens {
            for width in [34, 42, 52] {
                let top = try screen.lines(screen.top, language, from: catalogs, width: width)
                let bottom = try screen.lines(screen.bottom, language, from: catalogs, width: width)
                let body = try screen.lines(screen.body, language, from: catalogs, width: width)
                let whole = (top + body + bottom).joined(separator: "\n")
                #expect(isOwnInterface(whole), "\(screen.name) in \(language) passed as evidence.")
                // The fixture holds text that would be learned from if the screen were not recognized.
                #expect(!isOwnInterface(try screen.lines(screen.body.filter { if case .other = $0 { true } else { false } },
                                                         language, from: catalogs, width: width).joined(separator: "\n")),
                        "\(screen.name) in \(language) has no text of its own to protect.")
                // Any fourteen consecutive lines of the content, between the bars that stay.
                for start in 0...max(0, body.count - 14) {
                    let visible = Array(body[start..<min(body.count, start + 14)])
                    let framed = (top + visible + bottom).joined(separator: "\n")
                    #expect(isOwnInterface(framed), "\(screen.name) in \(language), from line \(start) at width \(width):\n\(framed)")
                    if screen.recognizedWithoutBars {
                        let bare = visible.joined(separator: "\n")
                        #expect(isOwnInterface(bare), "\(screen.name) in \(language) without its bars, from line \(start) at width \(width):\n\(bare)")
                    }
                }
            }
        }
    }

    @Test("Labels that sit together are recognized together, read alone or as one line; without one of them they are not")
    func labelGroupsNeedEveryPiece() {
        let content = "09:00 Team planning meeting"
        for group in OwnInterfaceWording.labelGroups {
            for language in [0, 1] {
                let pieces = group.map { $0.wordings[language] }
                #expect(isOwnInterface((pieces.dropLast() + [content] + pieces.suffix(1)).joined(separator: "\n")))
                // The last two labels of one bar read as one line.
                let merged = pieces.dropLast(2) + ["\(pieces[pieces.count - 2]) \(pieces[pieces.count - 1])", content]
                #expect(isOwnInterface(merged.joined(separator: "\n")))
                for missing in pieces.indices where group.count > 2 || (pieces[1 - missing] != "Sampled moment" && pieces[1 - missing] != "Moment échantillonné") {
                    var rest = pieces
                    rest.remove(at: missing)
                    #expect(!isOwnInterface((rest + [content]).joined(separator: "\n")), "\(rest) without “\(pieces[missing])” rejected a screen.")
                }
                // Inside a longer line they are ordinary words.
                #expect(!isOwnInterface(pieces.map { "Please see the \($0) today" }.joined(separator: "\n") + "\n\(content)"))
            }
        }
        // The title of one sampled screen stays above its original text and identifies it alone.
        for title in ["Sampled moment", "Moment échantillonné"] {
            #expect(isOwnInterface("\(title)\n\(content)\n12:30 Lunch with the product team"))
        }
        // The same title read as one line with the button beside it.
        for title in ["Sampled moment Done", "Moment échantillonné Terminé"] {
            #expect(isOwnInterface("\(title)\nFriday, October 9\n\(content)\n12:30 Lunch with the product team"))
        }
    }

    @Test("One day of Review is rejected in English and French")
    func dayDetailIsRejected() {
        for screen in [
            "Friday, October 9\nObserved mornings\nNo observation dated to this day.\nRoutine runs\nNo routine saved for this day.\nA missing run stays unknown. It isn't counted as a\nzero-minute morning.",
            "vendredi 9 octobre\nMatinées observées\nAucune observation datée de ce jour.\nSessions de routine\nAucune routine enregistrée pour ce jour.\nUne session manquante reste inconnue. Elle n’est pas\ncomptée comme une matinée de zéro minute.",
            "Active routine time\n18 min\nPlanned time\n25 min\nRead messages from my family\nMarked complete\n5 min planned\nSaved routine version 3. Active time excludes pauses and\ndoesn't measure activity in other apps.",
            "Routine run 1 · completed\nRead messages from my family\nSkipped\nPrepare breakfast for the children\nSkipped\nSaved routine version 3. Active time excludes pauses and doesn't measure activity in other apps.",
            "Temps de routine actif\n18 min\nDurée prévue\n25 min\nLire les messages de ma famille\nMarqué comme terminé\n5 min prévues\nVersion 3 de la routine enregistrée. Le temps actif exclut les\npauses et ne mesure pas l’activité dans d’autres apps."
        ] {
            #expect(isOwnInterface(screen), "Passed as evidence:\n\(screen)")
        }
    }

    // MARK: Other apps' screens are kept

    @Test("A screen that only shares ordinary words with MORE stays evidence")
    func ordinaryWordsDoNotRejectOtherApps() throws {
        let screens = [
            "Voice Memos\nAll Recordings\nRecord\n09:00 Team planning meeting",
            "Dictaphone\nTous les enregistrements\nEnregistrer\n09:00 Réunion de planification de l’équipe",
            "Camera\nRecord\nChoose\nBuild it myself\n09:00 Team planning meeting",
            "Appareil photo\nEnregistrer\nChoisir\nVotre rythme\n09:00 Réunion de planification de l’équipe",
            "Notes\nEnregistrer\nPensez à enregistrer la réunion de planification avec toute l’équipe",
            "Réglages\nConfidentialité et données\nVotre journée\nÉcoutez où vous voulez\n09:00 Réunion de planification de l’équipe",
            "Settings\nPrivacy & data\nYour day\nRead each step aloud\nListen where you like\n09:00 Team planning meeting",
            "Santé\nVotre routine\nActivité des apps\nDurée des sessions\n09:00 Réunion de planification de l’équipe",
            "Forme\nVotre routine\nÉtirements du matin avec toute la famille\n10 min prévues · à mon rythme",
            "Fitness\nYour routine\nApp activity\nAverage routine time\n09:00 Team planning meeting",
            "Matinée\nMaintenant\nPause\n09:00 Réunion de planification de l’équipe",
            // A French title that is ordinary wording elsewhere does not reject by itself.
            "Notes\nUn brouillon à relire\nBonjour Paul, voici les documents pour notre réunion.",
            "Minuteur\nArrêter automatiquement après\n09:00 Réunion de planification de l’équipe",
            "Sport\nSuggérer une routine\nVotre routine approuvée\n09:00 Réunion de planification de l’équipe",
            "Notes\nDes voix plus naturelles\nComparer les voix françaises pour enregistrer le livre audio.",
            // Ordinary remarks about timing and averages are not Review's summary.
            "Notes\nWe have no complete timing data for the warm-up laps, so leave them out of the average.",
            "Messages\nNous n’avons pas de durée complète pour ces tours. Ne les compte pas dans la moyenne.",
            // Advice any app might give, even when two such remarks meet.
            "Messages\nSend the error report before our 09:00 meeting. A screenshot or text file works too. Add context, if you like.",
            "Notes\nInstalled voices\nDownload the new French narrator pack. Return here after the download finishes.",
            // Two recognized sentences that share a word are one passage, counted once.
            "Messages\nUse the audio output picker to choose an available\nspeaker. Output doesn't connect a HomePod microphone.\nPlease test the kitchen speaker at 09:00 tomorrow.",
            // A wrapped sentence is one piece, even when one of its lines reads like a label.
            "Fitness\nTime in\nyour routine,\nexcluding pauses.\n07:30 Mobility strength session",
            "Forme\nTemps passé dans\nvotre routine,\npauses exclues.\n07:30 Séance de mobilité et de force",
            // One sentence of MORE's copy quoted in a conversation is not MORE's screen.
            "Messages\nMontrez-nous votre matinée\nPlease bring the printed meeting notes tomorrow.",
            "Messages\nA place for what comes to mind\nPlease bring the printed meeting notes tomorrow.",
            "Messages\nGardez votre progression sur l’écran verrouillé.\nPlease bring the printed meeting notes tomorrow.",
            // A control from one MORE screen does not confirm a sentence from another.
            "Messages\nA few things, your way.\nRecord\nPlease bring the printed meeting notes tomorrow.",
            // Words of the observation, sampled-moment and suggestion screens, as other apps show them.
            "Scanner\nOriginal extracted text\nSaved samples\nInvoice 2026-114 for the team planning workshop",
            "Scanner\nTexte extrait d’origine\nÉchantillons enregistrés\nFacture 2026-114 pour l’atelier de planification",
            "Audio\nSampled moments\nSaved samples\nView sampled screens\nRecording details\n09:00 Team planning meeting",
            "Nature\nObservations\nSélection terminée\nEffacer la sélection\n09:00 Sortie d’observation des oiseaux du parc",
            "Nature\nObservations\nObserved day\nCurrent notes\nTwo herons seen near the northern pond at sunrise",
            "Updates\nSuggested update\nKeep current\nVersion 4.2 improves the calendar and fixes meeting reminders",
            "Mises à jour\nMise à jour suggérée\nGarder l’actuelle\nLa version 4.2 améliore le calendrier et les rappels",
            "Updates\nApprove update\nKeep current\n09:00 Team planning meeting",
            "Updates\nSuggested update\nVersion 4.2 improves the calendar and fixes meeting reminders\nApprove update",
            "Mises à jour\nMise à jour suggérée\nLa version 4.2 améliore le calendrier et les rappels\nApprouver la mise à jour",
            "Messages\nPourquoi cette suggestion ?\nElle dépasse les 30 minutes prévues.\n09:00 Réunion de planification de l’équipe",
            "Messages\nWhy this suggestion? The meeting already runs over its 30 minutes planned\n09:00 Team planning meeting",
            "Scanner\nCurrent notes\nCheck the invoice before the planning meeting\nOriginal extracted text\nInvoice 2026-114",
            "Scanner\nNotes actuelles\nVérifier la facture avant la réunion de planification\nTexte extrait d’origine\nFacture 2026-114",
            "Photos\nClear selection\nDone\nObservations\n09:00 Team planning meeting",
            "Fitness\nWhy this suggestion?\n45 minutes planned\n09:00 Mobility and strength session with the group",
            "Forme\nPourquoi cette suggestion ?\n45 minutes prévues\n09:00 Séance de mobilité et de renforcement avec le groupe",
            "Music\nWhy this suggestion?\nBecause you listened to the morning jazz playlist four times",
            "Musique\nPourquoi cette suggestion ?\nParce que vous avez écouté la playlist jazz du matin",
            "Fitness\n45 minutes planned\nMorning mobility and strength session with the group",
            "Notes\nSuggested update to tomorrow's agenda\n09:00 Team planning meeting\n30 minutes planned",
            "Notes\nMise à jour suggérée pour demain\n09:00 Réunion de planification de l’équipe\n30 minutes prévues",
            "Updates\nApprove update\n5 minutes planned\n09:00 Team planning meeting",
            "Messages\nGaps may hide others\nPlease bring the printed meeting notes tomorrow.",
            "Nature\nObservation\nA saved moment\nChoose an excerpt\nTwo herons seen near the northern pond at sunrise",
            "Fitness\nCompare with current routine\nWhy this suggestion?\n45 minutes planned\n09:00 Mobility and strength session with the group",
            "Forme\nComparer avec la routine actuelle\nPourquoi cette suggestion ?\n45 minutes prévues\n09:00 Séance de mobilité et de renforcement avec le groupe",
            "Notes\nKept by your choice\nYour saved timing choice\nPlease bring the printed meeting notes tomorrow.",
            // A label of one of these screens beside a sentence of another is not either screen.
            "Messages\nYour current routine stays ready until you approve.\nObservations\nPlease bring the printed meeting notes tomorrow.",
            "Messages\nNo return is established by these samples.\nYour label\nPlease bring the printed meeting notes tomorrow.",
            // The words inside a longer line are not the control.
            "Calendar\nRecord the team planning meeting notes\nA screenshot or text file works too\n09:00 Team planning meeting"
        ]
        for screen in screens {
            #expect(!isOwnInterface(screen), "Wrongly rejected:\n\(screen)")
            let units = try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
            #expect(units.count == 1)
        }
        let written = "Chaque matin j’ouvre Dictaphone, je touche Enregistrer et je dicte mes notes. Then I tap Record again."
        #expect(try LearningEvidencePolicy.prepare(written, as: .writtenReport).first?.kind == .userReportedActivity)
    }

    @Test("Per screen and language: controls alone never reject, one sentence alone never rejects, two pieces do",
          arguments: OwnInterfaceWording.screens.map(\.name), [0, 1])
    func pairRuleHoldsForEveryRecognizedPiece(screenName: String, language: Int) throws {
        let screen = try #require(OwnInterfaceWording.screens.first { $0.name == screenName })
        let content = "09:00 Team planning meeting"
        // A few titles identify a screen by one complete line; leave those to their own tests.
        // Two labels that sit together identify their screen; that has its own tests too.
        let titles = Set((OwnInterfaceWording.distinctiveLines + OwnInterfaceWording.labelGroups.flatMap { $0 }).flatMap(\.normalized))
        func isTitle(_ wording: String) -> Bool { titles.contains(LearningEvidencePolicy.normalized(wording)) }
        let controls = screen.controls.map { $0.wordings[language] }.filter { !isTitle($0) }
        let copy = screen.copy.map { $0.wordings[language] }
        #expect(controls.count >= 2)
        #expect(!isOwnInterface((["Calendar"] + controls + [content]).joined(separator: "\n")),
                "\(screenName)'s controls alone rejected a screen.")
        for (index, sentence) in copy.enumerated() {
            if !isTitle(sentence) {
                #expect(!isOwnInterface("Messages\n\(sentence)\n\(content)"), "“\(sentence)” alone rejected a screen.")
            }
            for control in controls {
                // A label whose words also occur in the sentence cannot confirm that sentence.
                let independent = !" \(LearningEvidencePolicy.normalized(sentence)) "
                    .contains(" \(LearningEvidencePolicy.normalized(control)) ")
                #expect(isOwnInterface("\(sentence)\n\(control)\n\(content)") == independent,
                        "“\(sentence)” with “\(control)”: expected own interface \(independent).")
            }
            let other = copy[(index + 1) % copy.count]
            #expect(isOwnInterface("\(sentence)\n\(other)\n\(content)"), "“\(sentence)” with “\(other)” passed.")
        }
    }
}
