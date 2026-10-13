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
        for substitution in (node["substitutions"] as? [String: Any] ?? [:]).values {
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
        return try views.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}

/// MORE's screens as a recording would show them. Text comes from the catalogs by key, in
/// screen order, wrapped the way recognized lines arrive: a paragraph spans several lines.
private enum OwnScreenFixtures {
    static let learn = [
        "Your rhythm", "Make your morning yours.",
        "Start with what you already do. You'll review every suggestion before it becomes your routine.",
        "Show us your morning",
        "Start an explicitly shared recording or bring one you already made. Go through a short part of your morning, then review what we can see.",
        "Record", "Choose",
        "A screenshot or text file works too. Only the file you choose is read; recording never starts automatically.",
        "Add context, if you like", "Build it myself", "Your routine stays in your hands",
        "Your current routine stays ready while you review a suggestion. Approve it when it fits, or keep the morning you already have.",
        "About on-device learning"
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
        "Make yourself at home", "A few things, your way.",
        "Choose what to connect and how you'd like your morning to sound.",
        "Your next morning", "Your day", "A little context before your morning begins.",
        "Morning at a glance", "Keep your place on the Lock Screen.",
        "A voice to guide you", "Companion voice", "Read each step aloud",
        "Hear the next step as you move through your routine.", "Listen where you like",
        "Privacy & data", "What stays here, and what you can remove.", "Try the voice"
    ]
    static let all = [("Learn", learn), ("Review", review), ("Settings", settings)]

    /// Recognized lines for a screen: each string on its own lines, long ones wrapped.
    static func lines(_ keys: [String], _ language: String, from catalogs: ShippedCatalogs, width: Int = 38) throws -> [String] {
        try keys.flatMap { key -> [String] in
            var lines: [String] = []
            for paragraph in try catalogs.text(key, language).components(separatedBy: .newlines) {
                var line = ""
                for word in paragraph.split(separator: " ") {
                    if !line.isEmpty, line.count + 1 + word.count > width { lines.append(line); line = "" }
                    line += (line.isEmpty ? "" : " ") + word
                }
                lines.append(line)
            }
            return lines
        }
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
        // The comparison is not empty: most recognition depends on current catalog strings.
        let linked = OwnInterfaceWording.all.filter { $0.catalogKey != nil }
        #expect(linked.count >= 70)
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
        // A translation is dropped, or a third language ships without its wording.
        #expect(try catalogs.changing("Record") { $0["localizations"] = [String: Any]() }.drift(of: phrases).count == 1)
        let german = try catalogs.changing("Choose") { entry in
            var localizations = entry["localizations"] as? [String: Any] ?? [:]
            localizations["de"] = ["stringUnit": ["state": "translated", "value": "Auswählen"]]
            entry["localizations"] = localizations
        }
        #expect(german.drift(of: phrases).count >= phrases.filter { $0.catalogKey != nil }.count)
        // A sentence the policy matches by one clause is rewritten.
        let sentence = "A screenshot or text file works too. Only the file you choose is read; recording never starts automatically."
        #expect(try catalogs.changing(sentence, french("Une image ou un fichier texte convient aussi."))
            .drift(of: phrases).count == 2)
        // One plural form of a counted line loses the recognized words.
        let counted = "%lld days with labeled samples · %lld days with observations"
        let plural = try catalogs.changing(counted) { entry in
            var text = String(decoding: try! JSONSerialization.data(withJSONObject: entry), as: UTF8.self)
            text = text.replacingOccurrences(of: "%arg jours avec échantillons identifiés", with: "%arg jours identifiés")
            entry = try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
        }
        #expect(plural.drift(of: phrases).count == 1)
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
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen)
            }
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + screen)
            }
            // Scrolled anywhere: any ten consecutive lines still show enough of the screen,
            // without its navigation title and whatever the wrapping width.
            for width in [30, 38, 52] {
                let wrapped = try OwnScreenFixtures.lines(keys, language, from: catalogs, width: width)
                for start in 0...max(0, wrapped.count - 10) {
                    let visible = wrapped[start..<min(wrapped.count, start + 10)].joined(separator: "\n")
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
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen)
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
            "Votre routine approuvée\n\(planned)", "Un brouillon à relire\n\(planned)", "Suggérer une routine\n\(planned)"
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
            "Fitness\nYour routine\nApp activity\nAverage routine time\n09:00 Team planning meeting",
            "Matinée\nMaintenant\nPause\n09:00 Réunion de planification de l’équipe",
            // One sentence of MORE's copy quoted in a conversation is not MORE's screen.
            "Messages\nMontrez-nous votre matinée\nPlease bring the printed meeting notes tomorrow.",
            "Messages\nA place for what comes to mind\nPlease bring the printed meeting notes tomorrow.",
            "Messages\nGardez votre progression sur l’écran verrouillé.\nPlease bring the printed meeting notes tomorrow.",
            // A control from one MORE screen does not confirm a sentence from another.
            "Messages\nA few things, your way.\nRecord\nPlease bring the printed meeting notes tomorrow.",
            // The words inside a longer line are not the control.
            "Calendar\nRecord the team planning meeting notes\nA screenshot or text file works too\n09:00 Team planning meeting"
        ]
        for screen in screens {
            #expect(!isOwnInterface(screen), "Wrongly rejected:\n\(screen)")
            let units = try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen)
            #expect(units.count == 1)
        }
        let written = "Chaque matin j’ouvre Dictaphone, je touche Enregistrer et je dicte mes notes. Then I tap Record again."
        #expect(try LearningEvidencePolicy.prepare(written).first?.kind == .userReportedActivity)
    }

    @Test("Per screen and language: controls alone never reject, one sentence alone never rejects, two pieces do",
          arguments: OwnInterfaceWording.screens.map(\.name), [0, 1])
    func pairRuleHoldsForEveryRecognizedPiece(screenName: String, language: Int) throws {
        let screen = try #require(OwnInterfaceWording.screens.first { $0.name == screenName })
        let content = "09:00 Team planning meeting"
        // A few titles identify a screen by one complete line; leave those to their own tests.
        let titles = Set(OwnInterfaceWording.distinctiveLines.flatMap(\.normalized))
        func isTitle(_ wording: String) -> Bool { titles.contains(LearningEvidencePolicy.normalized(wording)) }
        let controls = screen.controls.map { $0.wordings[language] }.filter { !isTitle($0) }
        let copy = screen.copy.map { $0.wordings[language] }
        #expect(controls.count >= 3)
        #expect(!isOwnInterface((["Calendar"] + controls + [content]).joined(separator: "\n")),
                "\(screenName)'s controls alone rejected a screen.")
        for (index, sentence) in copy.enumerated() {
            if !isTitle(sentence) {
                #expect(!isOwnInterface("Messages\n\(sentence)\n\(content)"), "“\(sentence)” alone rejected a screen.")
            }
            for control in controls {
                #expect(isOwnInterface("\(sentence)\n\(control)\n\(content)"), "“\(sentence)” with “\(control)” passed.")
            }
            let other = copy[(index + 1) % copy.count]
            #expect(isOwnInterface("\(sentence)\n\(other)\n\(content)"), "“\(sentence)” with “\(other)” passed.")
        }
    }
}
