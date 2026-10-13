import Foundation

/// The wording MORE shows on its own screens, in every language shipped so far, and the
/// rule that tells one of those screens from another app's. A recording of the Learn,
/// Review or Settings screen is not evidence of a morning habit.
///
/// The String Catalogs are the source of the current wording. This table copies the entries
/// recognition depends on, and `OwnInterfaceWordingTests` reads the catalogs to fail when a
/// copied string is reworded, retranslated, removed, or missing a shipped language.
/// When that test fails: add the new wording, and keep the old one as `earlier` wording.
/// Never delete a wording: recordings and saved observations made before the change still
/// contain it. Matching is against screen text only; nothing here is saved or used as a key.
enum OwnInterfaceWording {
    struct Phrase: Sendable {
        /// Source key in a String Catalog while the app still shows this wording; nil once retired.
        let catalogKey: String?
        /// True when the wording is one sentence or clause of a longer catalog string.
        let isPartOfCatalogString: Bool
        /// Every wording to recognize, as shown: source, each translation, then earlier wording.
        let wordings: [String]
        let normalized: [String]

        fileprivate init(catalogKey: String?, isPart: Bool, _ wordings: [String]) {
            self.catalogKey = catalogKey
            isPartOfCatalogString = isPart
            self.wordings = wordings
            normalized = wordings.map(LearningEvidencePolicy.normalized)
        }

        /// One recognized line is exactly this wording.
        func isLine(of frame: Frame) -> Bool { normalized.contains(where: frame.lines.contains) }

        /// The frame contains this wording as whole words, even wrapped over several lines.
        func isWithin(_ frame: Frame) -> Bool { normalized.contains { frame.text.contains(" \($0) ") } }

        /// Where the frame's words read as this wording, in any of its forms.
        func occurrences(in frame: Frame) -> [Range<String.Index>] {
            normalized.flatMap { wording -> [Range<String.Index>] in
                var ranges: [Range<String.Index>] = []
                var start = frame.text.startIndex
                while let match = frame.text.range(of: " \(wording) ", range: start..<frame.text.endIndex) {
                    // Without the spaces around it, so neighbouring sentences do not touch.
                    ranges.append(frame.text.index(after: match.lowerBound)..<frame.text.index(before: match.upperBound))
                    start = frame.text.index(before: match.upperBound)
                }
                return ranges
            }
        }

        /// A line of the frame reads as this wording without being words of a sentence found
        /// in the same frame. `present` is `Frame.sentences(among:)`, worked out once per frame.
        func isLine(of frame: Frame, apartFrom present: [String]) -> Bool {
            normalized.contains { line in
                frame.lines.contains(line) && !present.contains { $0.contains(" \(line) ") }
            }
        }

        /// A line begins or ends with this wording: the title or a button of a bar, read alone
        /// or merged with its neighbour in that bar.
        func isAtLineEdge(of frame: Frame) -> Bool {
            normalized.contains { wording in
                frame.lines.contains { $0 == wording || $0.hasPrefix("\(wording) ") || $0.hasSuffix(" \(wording)") }
            }
        }

        /// For every line that ends with this wording in the letter case MORE shows it, the
        /// words read before it on that line. The mark between its words may be read as any
        /// sign or not at all, so only the words and their case are compared.
        func wordsBeforeLineEnd(in frame: Frame) -> [[String]] {
            let shown = wordings.map(Frame.words)
            return frame.shownLines.compactMap { line in
                shown.first { line.count >= $0.count && Array(line.suffix($0.count)) == $0 }
                    .map { line.dropLast($0.count).map(LearningEvidencePolicy.normalized) }
            }
        }
    }

    /// One screen's recognized text: its complete lines, and all of it as one run of words.
    struct Frame: Sendable {
        let lines: Set<String>
        let text: String
        /// Each line's words as recognized, in their own letter case.
        let shownLines: [[String]]

        init(_ source: String) {
            let recognized = source.components(separatedBy: .newlines)
            lines = Set(recognized.map(LearningEvidencePolicy.normalized))
            text = " \(LearningEvidencePolicy.normalized(source)) "
            shownLines = recognized.map(Self.words).filter { !$0.isEmpty }
        }

        /// Split the way `LearningEvidencePolicy.normalized` splits, keeping case and accents.
        static func words(_ line: String) -> [String] {
            line.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        }

        /// The wordings of `sentences` this frame contains, each between spaces.
        func sentences(among sentences: [Phrase]) -> [String] {
            sentences.flatMap(\.normalized).filter { text.contains(" \($0) ") }.map { " \($0) " }
        }
    }

    /// One MORE screen recognized by several pieces of its wording together.
    struct Screen: Sendable {
        let name: String
        /// Sentences and headings specific to MORE, at least four words in every language.
        let copy: [Phrase]
        /// Short or ordinary labels other apps also show. They only corroborate `copy`.
        let controls: [Phrase]
    }

    /// A whole catalog string the app shows now.
    private static func shown(_ key: String, fr: String, earlier: String...) -> Phrase {
        Phrase(catalogKey: key, isPart: false, [key, fr] + earlier)
    }

    /// One sentence or clause of a longer catalog string the app shows now, with any other
    /// form of it to recognize: a plural's own wording, or wording shown earlier.
    private static func part(_ en: String, fr: String, of key: String, earlier: String...) -> Phrase {
        Phrase(catalogKey: key, isPart: true, [en, fr] + earlier)
    }

    /// Wording the app no longer shows. Earlier recordings and observations still contain it.
    private static func earlier(_ wordings: String...) -> Phrase {
        Phrase(catalogKey: nil, isPart: false, wordings)
    }

    // MARK: - Wording

    /// Titles and controls distinctive enough that one complete line identifies the screen.
    static let distinctiveLines: [Phrase] = [
        shown("Learn my morning", fr: "Apprendre ma matinée"),
        shown("Show your morning", fr: "Montrez votre matinée"),
        shown("Make your morning yours.", fr: "Faites de votre matinée la vôtre."),
        shown("Your routine stays in your hands", fr: "Votre routine reste entre vos mains"),
        // The Learn button read this until it was shortened to "Record"; it is still its spoken label.
        shown("Record a little of my morning", fr: "Enregistrer un peu de ma matinée"),
        shown("Sample morning, not your observed activity", fr: "Matinée d’exemple, pas votre activité observée"),
        shown("Your mornings will find their shape.", fr: "Vos matinées vont prendre forme."),
        shown("Your morning voice", fr: "La voix de votre matinée"),
        // The title that stays above one sampled screen's original text, however far it scrolls.
        shown("Sampled moment", fr: "Moment échantillonné"),
        // These English lines have always identified a screen by themselves, so they still do.
        // Their translations are ordinary French that other apps also show (« Votre rythme »,
        // « Un brouillon à relire »): those only confirm a sentence of their screen, below.
        earlier("Your rhythm"), earlier("Suggest a routine"), earlier("Stop automatically after"),
        earlier("Your approved routine"), earlier("A draft for you to review"), earlier("More natural voices"),
        earlier("On-device learning"),
        earlier("Enable screen recording"),
        earlier("Your first draft is ready to review")
    ]

    /// Launch copy that identifies MORE wherever it appears, including in a written description.
    static let marketing: [Phrase] = [
        earlier("Less handling. More morning."),
        earlier("That game of chess. Let's make space"),
        earlier("Let's make space for the things you care about")
    ]
    static let marketingPair: [Phrase] = [earlier("The briefing. The messages."), earlier("That game of chess")]

    /// The earlier Review screen: any two of its headings and its timing note.
    static let earlierReviewHeadings: [Phrase] = [
        earlier("Learning your morning"), earlier("The last seven mornings"), earlier("Find your rhythm.")
    ]
    static let earlierReviewNote = earlier("Routine timing excludes pauses")

    /// The observed-mornings overview: its heading with either line of its own explanation.
    static let overviewHeading = shown("Your observed mornings", fr: "Vos matinées observées")
    static let overviewCopy: [Phrase] = [
        part("with labeled samples", fr: "avec échantillons identifiés",
             of: "%lld days with labeled samples · %lld days with observations"),
        part("A recorded glimpse, not time spent", fr: "Un aperçu enregistré, pas un temps passé",
             of: "A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls.")
    ]

    /// The home screen. Each of these is an ordinary word or two; only the pairs below count.
    static let homeHeadings: [Phrase] = [
        shown("Morning", fr: "Matinée"), shown("good morning", fr: "bonjour")
    ]
    static let homeFooters: [Phrase] = [
        shown("Sample morning", fr: "Matinée d’exemple"),
        earlier("Your rhythm, at your pace"), earlier("Hold to arrange"),
        // Vision may read both footer columns as one line.
        earlier("Sample morning Hold to arrange"), earlier("Your rhythm, at your pace Hold to arrange")
    ]
    static let homeReviewPrompt = earlier("A new rhythm. Ready to review.")
    /// The red badge beside the date while MORE records. Without its mark it reads "more
    /// recording", words another app can show ("more recording options", "Show more" above
    /// "Recording 12"), so it is not looked for anywhere in the frame: it must end a line in
    /// MORE's own capitals. See `showsRecordingBadge`.
    static let recordingBadge = shown("MORE · Recording", fr: "MORE · Enregistrement")
    static let playbackNow = shown("Now", fr: "Maintenant")
    static let playbackPause = shown("Pause", fr: "Pause")
    static let playbackPaused = shown("Paused", fr: "En pause")
    static let playbackContinue = shown("Continue", fr: "Reprendre")

    /// Screens without a heading of their own: both pieces must be present.
    static let pairs: [[Phrase]] = [
        [earlier("Start my morning"), earlier("Update my morning")],
        [earlier("A little perspective."), shown("Settings & connections", fr: "Réglages et connexions")],
        [earlier("More room for your day."), earlier("Anything you’d like to remember?")],
        [part("Show us a little of your morning", fr: "Montrez-nous un peu de votre matinée",
              of: "Show us a little of your morning.\nWe’ll find the rhythm together.",
              earlier: "Show MORE a little of your morning"),
         part("We’ll find the rhythm together", fr: "Nous trouverons le rythme ensemble",
              of: "Show us a little of your morning.\nWe’ll find the rhythm together.")]
    ]

    /// Screens that show text MORE did not write (an earlier observation, a suggestion from
    /// the model) with no sentence of MORE's in view: labels that always sit together, in the
    /// bars that stay while the text scrolls or around the text itself. Every piece of a group
    /// must begin or end a line.
    static let labelGroups: [[Phrase]] = [
        // The suggested update, wherever it is scrolled, quotations included: the title and
        // both buttons of the bars that stay. Two of the three are what any updater shows.
        [shown("Suggested update", fr: "Mise à jour suggérée"), shown("Keep current", fr: "Garder l’actuelle"),
         shown("Approve update", fr: "Approuver la mise à jour")],
        [shown("Suggested update", fr: "Mise à jour suggérée"), shown("Discard", fr: "Supprimer"),
         shown("Approve update", fr: "Approuver la mise à jour")],
        // The list of saved observations: its title and the button beside it, and the two
        // buttons under it once some are chosen.
        [shown("Observations", fr: "Observations"), shown("Choose mornings", fr: "Choisir des matinées")],
        [shown("Clear selection", fr: "Effacer la sélection"), shown("Suggest an update", fr: "Suggérer une mise à jour")],
        // One saved observation: the two rows above its notes.
        [shown("Read a saved moment", fr: "Lire un moment enregistré"), shown("Edit in Learn", fr: "Modifier dans Apprendre")],
        // One sampled screen: its title read as one line with the button beside it.
        [shown("Sampled moment", fr: "Moment échantillonné"), shown("Done", fr: "Terminé")]
    ]

    /// The Learn, Review, Settings, routine, recording and voice screens as they read today,
    /// then the screens that display an earlier observation or a suggestion.
    static let screens: [Screen] = [
        Screen(name: "Learn", copy: [
            shown("Make your morning yours.", fr: "Faites de votre matinée la vôtre."),
            part("You'll review every suggestion before it becomes your routine",
                 fr: "Vous relirez chaque suggestion avant qu’elle ne devienne votre routine",
                 of: "Start with what you already do. You'll review every suggestion before it becomes your routine."),
            shown("Show us your morning", fr: "Montrez-nous votre matinée"),
            part("Start an explicitly shared recording or bring one you already made",
                 fr: "Lancez un enregistrement que vous partagez explicitement, ou apportez-en un existant",
                 of: "Start an explicitly shared recording or bring one you already made. Go through a short part of your morning, then review what we can see."),
            part("Go through a short part of your morning, then review what we can see",
                 fr: "Vivez une courte partie de votre matinée, puis relisez ce que nous voyons",
                 of: "Start an explicitly shared recording or bring one you already made. Go through a short part of your morning, then review what we can see."),
            part("A screenshot or text file works too", fr: "Une capture d’écran ou un fichier texte fonctionne aussi",
                 of: "A screenshot or text file works too. Only the file you choose is read; recording never starts automatically."),
            part("recording never starts automatically", fr: "l’enregistrement ne démarre jamais automatiquement",
                 of: "A screenshot or text file works too. Only the file you choose is read; recording never starts automatically."),
            shown("Your routine stays in your hands", fr: "Votre routine reste entre vos mains"),
            part("Your current routine stays ready while you review a suggestion",
                 fr: "Votre routine actuelle reste prête pendant que vous relisez une suggestion",
                 of: "Your current routine stays ready while you review a suggestion. Approve it when it fits, or keep the morning you already have."),
            shown("About on-device learning", fr: "À propos de l’apprentissage sur l’appareil"),
            part("Each observation is saved on this device", fr: "Chaque observation est enregistrée sur cet appareil",
                 of: "Each observation is saved on this device, with its original text and your corrections kept separately. Find earlier observations in Review. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it."),
            part("Evidence already attached to a saved routine remains with it",
                 fr: "Les éléments déjà liés à une routine enregistrée restent avec elle",
                 of: "Each observation is saved on this device, with its original text and your corrections kept separately. Find earlier observations in Review. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it."),
            part("A recording is sampled at up to 24 moments", fr: "Un enregistrement est échantillonné sur 24 moments au maximum",
                 of: "A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention."),
            part("it doesn't reveal every tap or intention", fr: "il ne révèle pas chaque toucher ni chaque intention",
                 of: "A recording is sampled at up to 24 moments, so short clips work best and quick actions may be missed. Visible text helps suggest a routine; it doesn't reveal every tap or intention."),
            part("Analysis uses Apple's on-device model when available",
                 fr: "L’analyse utilise le modèle d’Apple sur l’appareil lorsqu’il est disponible",
                 of: "Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you."),
            part("It doesn't run other apps or approve a routine for you",
                 fr: "Elle ne lance pas d’autres apps et n’approuve pas de routine à votre place",
                 of: "Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you."),
            // Under "What we could see": the text of the observation just made, and its sampled screens.
            part("Review the text we found and correct anything we missed",
                 fr: "Relisez le texte trouvé et corrigez ce qui nous a échappé",
                 of: "Review the text we found and correct anything we missed. The original stays in Review → Saved observations. Visible words don't always mean you performed an activity."),
            part("Visible words don't always mean you performed an activity",
                 fr: "Des mots visibles ne signifient pas toujours que vous avez fait une activité",
                 of: "Review the text we found and correct anything we missed. The original stays in Review → Saved observations. Visible words don't always mean you performed an activity."),
            part("These are occasional views of your screen", fr: "Ce sont des aperçus ponctuels de votre écran",
                 of: "These are occasional views of your screen. They can't count every scroll, prove a message was read, or measure complete app use."),
            part("They can't count every scroll, prove a message was read, or measure complete app use",
                 fr: "Ils ne peuvent ni compter chaque défilement, ni prouver qu’un message a été lu, ni mesurer toute l’utilisation des apps",
                 of: "These are occasional views of your screen. They can't count every scroll, prove a message was read, or measure complete app use."),
            part("Order of recognized appearances", fr: "Ordre des apparitions reconnues",
                 of: "Order of recognized appearances. Unknown samples may hide other activity."),
            part("Unknown samples may hide other activity", fr: "Les échantillons inconnus peuvent cacher d’autres activités",
                 of: "Order of recognized appearances. Unknown samples may hide other activity."),
            part("Editing the observation removes its attached frame evidence and screen interpretation",
                 fr: "Modifier l’observation supprime les images liées et l’interprétation de l’écran",
                 of: "Uses Apple Intelligence on this device. Editing the observation removes its attached frame evidence and screen interpretation.")
        ], controls: [
            shown("A glimpse of this recording", fr: "Un aperçu de cet enregistrement"),
            shown("See sampled screens", fr: "Voir les écrans échantillonnés"),
            shown("Recognize sampled screens", fr: "Reconnaître les écrans échantillonnés"),
            shown("Try recognizing screens again", fr: "Relancer la reconnaissance des écrans"),
            shown("Suggest a routine", fr: "Suggérer une routine"),
            shown("Suggest an update", fr: "Suggérer une mise à jour"),
            shown("Check availability again", fr: "Vérifier à nouveau la disponibilité"),
            shown("Record", fr: "Enregistrer"),
            shown("Choose", fr: "Choisir"),
            shown("Your rhythm", fr: "Votre rythme"),
            // Advice any app might give; as complete lines they confirm, they do not count as sentences.
            shown("Add context, if you like", fr: "Ajoutez du contexte, si vous le souhaitez"),
            shown("What we could see", fr: "Ce que nous avons pu voir"),
            shown("Build it myself", fr: "La créer moi-même")
        ]),
        Screen(name: "Review", copy: [
            part("Time in your routine, excluding pauses", fr: "Temps passé dans votre routine, pauses exclues",
                 of: "Time in your routine, excluding pauses. Other app use isn't measured here."),
            part("Other app use isn't measured here", fr: "L’utilisation des autres apps n’est pas mesurée ici",
                 of: "Time in your routine, excluding pauses. Other app use isn't measured here."),
            shown("Original evidence and your corrections", fr: "Éléments d’origine et vos corrections"),
            shown("Learn from a morning", fr: "Apprendre d’une matinée"),
            shown("Record, describe or refine", fr: "Enregistrer, décrire ou affiner"),
            shown("A place for what comes to mind", fr: "Un endroit pour ce qui vous passe par la tête"),
            shown("Today's connected app entries", fr: "Ouvertures d’apps connectées aujourd’hui"),
            shown("Voice, calendar and preferences", fr: "Voix, calendrier et préférences"),
            shown("Sample runs stay out of your personal averages.",
                  fr: "Les sessions d’exemple n’entrent pas dans vos moyennes personnelles."),
            shown("Runs with incomplete timing are excluded from this average.",
                  fr: "Les sessions à la durée incomplète sont exclues de cette moyenne."),
            shown("A morning saved. Time still unknown.", fr: "Une matinée enregistrée. Durée encore inconnue."),
            // The plural form, then the singular's own wording in each language.
            part("saved runs have no complete timing", fr: "sessions enregistrées n’ont pas de durée complète",
                 of: "%lld saved runs have no complete timing. They stay out of the average.",
                 earlier: "saved run has no complete timing", "session enregistrée n’a pas de durée complète"),
            part("Routine time begins with a completed run", fr: "Le temps de routine commence avec une session terminée",
                 of: "Explore the screens you saved below. Routine time begins with a completed run."),
            part("Days without a saved run stay empty", fr: "Les jours sans session enregistrée restent vides",
                 of: "Finish a morning to begin your history. Days without a saved run stay empty.")
        ], controls: [
            shown("A morning, remembered.", fr: "Une matinée, en mémoire."),
            shown("Nothing saved", fr: "Rien d’enregistré"),
            shown("App observations", fr: "Observations d’apps"),
            shown("Average routine time", fr: "Durée moyenne de la routine"),
            shown("Routine-run timing", fr: "Durée des sessions"),
            shown("Observed app time", fr: "Temps d’app observé"),
            shown("Saved observations", fr: "Observations enregistrées"),
            shown("Your routine", fr: "Votre routine"),
            shown("Saved thoughts", fr: "Pensées enregistrées"),
            shown("App activity", fr: "Activité des apps"),
            shown("Settings & connections", fr: "Réglages et connexions")
        ]),
        Screen(name: "Settings", copy: [
            shown("A few things, your way.", fr: "Quelques réglages, à votre façon."),
            shown("Choose what to connect and how you'd like your morning to sound.",
                  fr: "Choisissez ce que vous connectez et comment votre matinée doit sonner."),
            shown("A little context before your morning begins.", fr: "Un peu de contexte avant que votre matinée commence."),
            shown("Keep your place on the Lock Screen.", fr: "Gardez votre progression sur l’écran verrouillé."),
            shown("Hear the next step as you move through your routine.", fr: "Entendez l’étape suivante au fil de votre routine."),
            shown("What stays here, and what you can remove.", fr: "Ce qui reste ici, et ce que vous pouvez supprimer."),
            part("Use the audio output picker to choose an available speaker",
                 fr: "Utilisez le sélecteur de sortie audio pour choisir un haut-parleur disponible",
                 of: "Use the audio output picker to choose an available speaker, including a HomePod on your network."),
            part("Speaker output doesn't connect a HomePod microphone",
                 fr: "La sortie vers un haut-parleur ne connecte pas le micro d’un HomePod",
                 of: "Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet."),
            part("Room-to-room listening isn't available yet", fr: "L’écoute de pièce en pièce n’est pas encore disponible",
                 of: "Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet."),
            part("You can capture thoughts and dreams, edit a routine, and use spoken guidance",
                 fr: "Vous pouvez noter pensées et rêves, modifier une routine et utiliser le guidage vocal",
                 of: "You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable."),
            part("Connecting a phone to a Mac doesn't automatically give this app control of the phone",
                 fr: "Connecter un téléphone à un Mac ne donne pas automatiquement à cette app le contrôle du téléphone",
                 of: "Connecting a phone to a Mac doesn't automatically give this app control of the phone. The separate development test runner is needed for the phone-control experiment."),
            part("Messages and email aren't connected here yet", fr: "Les messages et les e-mails ne sont pas encore connectés ici",
                 of: "Messages and email aren't connected here yet. Automatic room detection and continuous voice commands also need further work."),
            part("Automatic room detection and continuous voice commands also need further work",
                 fr: "La détection automatique de pièce et les commandes vocales continues demandent aussi du travail",
                 of: "Messages and email aren't connected here yet. Automatic room detection and continuous voice commands also need further work.")
        ], controls: [
            shown("Check again", fr: "Vérifier à nouveau"),
            shown("Make yourself at home", fr: "Faites comme chez vous"),
            shown("Your next morning", fr: "Votre prochaine matinée"),
            shown("Your day", fr: "Votre journée"),
            shown("Morning at a glance", fr: "La matinée en un coup d’œil"),
            shown("A voice to guide you", fr: "Une voix pour vous guider"),
            shown("Companion voice", fr: "Voix d’accompagnement"),
            shown("Read each step aloud", fr: "Lire chaque étape à voix haute"),
            shown("Listen where you like", fr: "Écoutez où vous voulez"),
            shown("Privacy & data", fr: "Confidentialité et données"),
            shown("Try the voice", fr: "Essayer la voix")
        ]),
        Screen(name: "Routine", copy: [
            part("min planned · Your own pace", fr: "min prévues · À votre rythme", of: "%lld min planned · Your own pace"),
            part("min planned · Spoken guidance", fr: "min prévues · Guidage vocal", of: "%lld min planned · Spoken guidance"),
            part("Editing creates a new draft; your saved mornings keep their original routine",
                 fr: "Modifier crée un nouveau brouillon ; vos matinées enregistrées gardent leur routine d’origine",
                 of: "Minutes are planned. Editing creates a new draft; your saved mornings keep their original routine."),
            shown("Restoring a routine leaves your saved choices for future suggestions unchanged.",
                  fr: "Restaurer une routine ne modifie pas vos choix enregistrés pour les futures suggestions.")
        ], controls: [
            shown("Your routine", fr: "Votre routine"),
            shown("Your approved routine", fr: "Votre routine approuvée"),
            shown("A draft for you to review", fr: "Un brouillon à relire"),
            shown("Add a moment", fr: "Ajouter un moment"),
            shown("Restore previous routine", fr: "Restaurer la routine précédente"),
            shown("Export routine", fr: "Exporter la routine"),
            shown("Import routine", fr: "Importer une routine"),
            shown("Learn from an observation", fr: "Apprendre d’une observation")
        ]),
        Screen(name: "Recording", copy: [
            part("Confirm Apple's picker, then go through your morning", fr: "Confirmez le sélecteur d’Apple, puis vivez votre matinée",
                 of: "Confirm Apple's picker, then go through your morning. This screen closes when recording begins. We stop at your chosen limit and save the visible text for you to review when you return."),
            part("This screen closes when recording begins", fr: "Cet écran se ferme quand l’enregistrement commence",
                 of: "Confirm Apple's picker, then go through your morning. This screen closes when recording begins. We stop at your chosen limit and save the visible text for you to review when you return."),
            part("This records visible screen content without sound or camera video",
                 fr: "Cela enregistre le contenu visible de l’écran, sans son ni vidéo de la caméra",
                 of: "This records visible screen content without sound or camera video. Keep the part you want to teach short; other personal content on screen may also appear."),
            part("Recording stops at your chosen time limit or its file-size limit",
                 fr: "L’enregistrement s’arrête à la durée choisie ou à sa limite de taille",
                 of: "Recording stops at your chosen time limit or its file-size limit. This is a time limit, not a guess that you stopped using your phone. You can stop earlier using the app or the system controls."),
            part("This is a time limit, not a guess that you stopped using your phone",
                 fr: "C’est une limite de temps, pas une supposition que vous avez cessé d’utiliser votre téléphone",
                 of: "Recording stops at your chosen time limit or its file-size limit. This is a time limit, not a guess that you stopped using your phone. You can stop earlier using the app or the system controls."),
            part("You can stop earlier using the app or the system controls",
                 fr: "Vous pouvez l’arrêter plus tôt depuis l’app ou les commandes du système",
                 of: "Recording stops at your chosen time limit or its file-size limit. This is a time limit, not a guess that you stopped using your phone. You can stop earlier using the app or the system controls."),
            part("When recording finishes, visible text is extracted and saved locally",
                 fr: "À la fin de l’enregistrement, le texte visible est extrait et enregistré localement",
                 of: "When recording finishes, visible text is extracted and saved locally. Review the text, then choose whether to ask Apple Intelligence for a routine suggestion. Your routine changes only after you approve. The video stays on this device until its extracted text is saved, or until you discard it."),
            part("Your routine changes only after you approve", fr: "Votre routine ne change qu’après votre approbation",
                 of: "When recording finishes, visible text is extracted and saved locally. Review the text, then choose whether to ask Apple Intelligence for a routine suggestion. Your routine changes only after you approve. The video stays on this device until its extracted text is saved, or until you discard it.")
        ], controls: [
            shown("Stop automatically after", fr: "Arrêter automatiquement après"),
            shown("Start screen recording", fr: "Lancer l’enregistrement de l’écran"),
            shown("You're in control", fr: "C’est vous qui décidez")
        ]),
        Screen(name: "Voice", copy: [
            part("Your choice applies to spoken morning steps", fr: "Votre choix s’applique aux étapes lues à voix haute",
                 of: "Matches your device’s language and dialect, then prefers a higher-quality installed voice. Your choice applies to spoken morning steps."),
            part("These are Apple system speech voices; Siri may use a different voice",
                 fr: "Ce sont les voix système d’Apple ; Siri peut utiliser une voix différente",
                 of: "Listen through your current audio output. These are Apple system speech voices; Siri may use a different voice."),
            part("Choosing it does not translate your routine", fr: "La choisir ne traduit pas votre routine",
                 of: "A voice’s language affects pronunciation. Choosing it does not translate your routine.")
        ], controls: [
            shown("More natural voices", fr: "Des voix plus naturelles"),
            shown("Installed voices", fr: "Voix installées"),
            shown("Preview selected voice", fr: "Écouter la voix choisie"),
            shown("Refresh installed voices", fr: "Actualiser les voix installées")
        ]),
        // One saved observation: its dates, its notes and original text, its sampled moments.
        Screen(name: "Observation", copy: [
            part("Import time is separate from the day you observed", fr: "L’heure d’import est distincte du jour observé",
                 of: "Import time is separate from the day you observed. These dates don't establish how long you used your phone."),
            part("These dates don't establish how long you used your phone",
                 fr: "Ces dates n’indiquent pas combien de temps vous avez utilisé votre téléphone",
                 of: "Import time is separate from the day you observed. These dates don't establish how long you used your phone."),
            shown("Day recorded by this recording session.", fr: "Jour enregistré par cette session d’enregistrement."),
            part("Changing the observed day keeps this information", fr: "Changer le jour observé conserve cette information",
                 of: "Saved when recording began. Changing the observed day keeps this information. It doesn't measure time spent in apps."),
            part("Corrections change the notes used for suggestions",
                 fr: "Les corrections modifient les notes utilisées pour les suggestions",
                 of: "Corrections change the notes used for suggestions. The original evidence stays available here."),
            part("The original evidence stays available here", fr: "Les éléments d’origine restent disponibles ici",
                 of: "Corrections change the notes used for suggestions. The original evidence stays available here."),
            shown("Activity between these sampled moments is unknown.", fr: "L’activité entre ces moments échantillonnés est inconnue."),
            shown("Original samples in extraction order", fr: "Échantillons d’origine dans l’ordre d’extraction"),
            shown("No return is established by these samples.", fr: "Ces échantillons n’établissent aucun retour."),
            part("Gaps may hide others", fr: "Des trous peuvent en cacher d’autres",
                 of: "At least %lld visible returns in this clip. Gaps may hide others."),
            shown("These samples have not been interpreted.", fr: "Ces échantillons n’ont pas été interprétés."),
            part("Labels come from recognition or your review", fr: "Les libellés viennent de la reconnaissance ou de votre relecture",
                 of: "Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls."),
            part("Samples can miss activity and don't measure time spent, taps, reads or scrolls",
                 fr: "Les échantillons peuvent manquer de l’activité et ne mesurent ni le temps passé, ni les touchers, lectures ou défilements",
                 of: "Labels come from recognition or your review. Samples can miss activity and don't measure time spent, taps, reads or scrolls."),
            shown("No sampled recording is attached to this observation.",
                  fr: "Aucun enregistrement échantillonné n’est lié à cette observation.")
        ], controls: [
            shown("Observation", fr: "Observation"),
            shown("Sampled moments", fr: "Moments échantillonnés"),
            shown("Saved samples", fr: "Échantillons enregistrés"),
            shown("View sampled screens", fr: "Voir les écrans échantillonnés"),
            // What a sampled moment is called when recognition could not name it.
            shown("Unknown screen", fr: "Écran inconnu"),
            shown("Ambiguous screen", fr: "Écran ambigu"),
            shown("Unresolved at this timestamp", fr: "Non résolu à cet instant"),
            shown("Observed day", fr: "Jour observé"),
            shown("Change day or origin", fr: "Changer le jour ou l’origine"),
            shown("Recording details", fr: "Détails de l’enregistrement"),
            shown("Read a saved moment", fr: "Lire un moment enregistré"),
            shown("Edit in Learn", fr: "Modifier dans Apprendre"),
            shown("Current notes", fr: "Notes actuelles"),
            shown("Original extracted text", fr: "Texte extrait d’origine"),
            shown("Recording evidence", fr: "Éléments enregistrés"),
            shown("Delete this observation", fr: "Supprimer cette observation")
        ]),
        // One sampled screen of an observation, with the text read from it at the time.
        Screen(name: "Sampled moment", copy: [
            part("A visual label is a proposal about what's visible", fr: "Un libellé visuel est une proposition sur ce qui est visible",
                 of: "A visual label is a proposal about what's visible. It doesn't establish which app was open or what you did."),
            part("It doesn't establish which app was open or what you did",
                 fr: "Il n’établit ni quelle app était ouverte, ni ce que vous avez fait",
                 of: "A visual label is a proposal about what's visible. It doesn't establish which app was open or what you did."),
            shown("Times are offsets into this recording, rounded to a millisecond.",
                  fr: "Les heures sont des positions dans cet enregistrement, arrondies à la milliseconde."),
            shown("Your description stays separate from the model's interpretation.",
                  fr: "Votre description reste séparée de l’interprétation du modèle."),
            part("It is left out of later activity suggestions", fr: "Il est exclu des prochaines suggestions d’activités",
                 of: "You kept this screen unknown. It is left out of later activity suggestions."),
            shown("The original interpretation supported more than one possible context.",
                  fr: "L’interprétation d’origine permettait plusieurs contextes possibles."),
            shown("No original interpretation quote is attached to this sample.",
                  fr: "Aucune citation d’interprétation d’origine n’est liée à cet échantillon."),
            shown("This text was limited during extraction and cannot support a screen identity.",
                  fr: "Ce texte a été tronqué à l’extraction et ne peut pas appuyer l’identité d’un écran.")
        ], controls: [
            shown("Requested sample", fr: "Échantillon demandé"),
            shown("Actual frame", fr: "Image réelle"),
            shown("Your label", fr: "Votre libellé"),
            shown("Proposed visual label", fr: "Libellé visuel proposé"),
            shown("Original proposed label", fr: "Libellé proposé à l’origine"),
            shown("Exact evidence quote", fr: "Citation exacte de la source"),
            shown("Excerpt you selected", fr: "Extrait que vous avez choisi"),
            shown("Correct label", fr: "Corriger le libellé"),
            shown("Edit your label", fr: "Modifier votre libellé"),
            shown("Original extracted text", fr: "Texte extrait d’origine"),
            shown("Source sample", fr: "Échantillon source"),
            shown("Read this saved moment", fr: "Lire ce moment enregistré")
        ]),
        // Seven days of observations: the screen labels derived from them, and each day's clips.
        Screen(name: "Observed mornings", copy: [
            shown("Screens that appeared across your mornings.", fr: "Les écrans apparus au fil de vos matinées."),
            part("They don't measure time in apps, reads or scrolls",
                 fr: "Ils ne mesurent ni le temps passé dans les apps, ni les lectures, ni les défilements",
                 of: "These labels describe sampled screens. They don't measure time in apps, reads or scrolls. Missing samples stay unknown."),
            part("These labels describe sampled screens", fr: "Ces libellés décrivent des écrans échantillonnés",
                 of: "These labels describe sampled screens. They don't measure time in apps, reads or scrolls. Missing samples stay unknown."),
            part("Missing samples stay unknown", fr: "Les échantillons manquants restent inconnus",
                 of: "These labels describe sampled screens. They don't measure time in apps, reads or scrolls. Missing samples stay unknown."),
            part("Conflicting labels are excluded from this pattern list", fr: "Les libellés contradictoires sont exclus de cette liste",
                 of: "Conflicting labels are excluded from this pattern list. Their original samples remain in each observation."),
            part("Their original samples remain in each observation", fr: "Leurs échantillons d’origine restent dans chaque observation",
                 of: "Conflicting labels are excluded from this pattern list. Their original samples remain in each observation."),
            part("Dates use the time zone saved with each observation",
                 fr: "Les dates utilisent le fuseau horaire enregistré avec chaque observation",
                 of: "Dates use the time zone saved with each observation. Separate clips are never joined into one continuous timeline."),
            part("Separate clips are never joined into one continuous timeline",
                 fr: "Les clips séparés ne sont jamais fusionnés en une chronologie continue",
                 of: "Dates use the time zone saved with each observation. Separate clips are never joined into one continuous timeline."),
            // Under samples, tests and automated activity, in place of the sentence above.
            part("This evidence stays separate from personal mornings", fr: "Ces éléments restent séparés des matinées personnelles",
                 of: "This evidence stays separate from personal mornings. Dates and origins can be reviewed in the source observation."),
            part("Dates and origins can be reviewed in the source observation",
                 fr: "Les dates et origines peuvent être vérifiées dans l’observation source",
                 of: "This evidence stays separate from personal mornings. Dates and origins can be reviewed in the source observation."),
            shown("No screen labels are available yet.", fr: "Aucun libellé d’écran n’est encore disponible."),
            shown("Undated observations are outside this period until you assign their observed day.",
                  fr: "Les observations non datées restent hors de cette période tant que vous ne leur attribuez pas de jour."),
            shown("No dated observations in this period.", fr: "Aucune observation datée sur cette période.")
        ], controls: [
            shown("Observed mornings", fr: "Matinées observées"),
            shown("The seven days", fr: "Les sept jours"),
            shown("No observation", fr: "Aucune observation"),
            shown("Notes only", fr: "Notes uniquement"),
            shown("Your label", fr: "Votre libellé")
        ]),
        // The quotations behind one screen label seen across several mornings.
        Screen(name: "Source moments", copy: [
            part("Open a quote to inspect the original sampled screen",
                 fr: "Ouvrez une citation pour examiner l’écran échantillonné d’origine",
                 of: "Seen on %lld distinct days. Open a quote to inspect the original sampled screen."),
            shown("A proposed visual label doesn't establish an app's identity or an action you took.",
                  fr: "Un libellé visuel proposé n’établit ni l’identité d’une app ni une action de votre part."),
            part("It stays separate from model labels and doesn't establish an action you took",
                 fr: "Il reste séparé des libellés du modèle et n’établit pas une action de votre part",
                 of: "You supplied this label. It stays separate from model labels and doesn't establish an action you took.")
        ], controls: [
            shown("Source moments", fr: "Moments sources"),
            shown("Excerpt selected by you", fr: "Extrait choisi par vous"),
            shown("Pattern updated", fr: "Tendance mise à jour")
        ]),
        // Choosing a line of a saved observation to hear again.
        Screen(name: "Saved moment", copy: [
            part("Keep a thought from a morning you've saved", fr: "Gardez une pensée d’une matinée enregistrée",
                 of: "Keep a thought from a morning you've saved. Choose the words you want to hear again."),
            part("Choose the words you want to hear again", fr: "Choisissez les mots que vous voulez réentendre",
                 of: "Keep a thought from a morning you've saved. Choose the words you want to hear again."),
            part("This is a saved excerpt, not today's messages", fr: "Il s’agit d’un extrait enregistré, pas des messages du jour",
                 of: "The date is spoken too. This is a saved excerpt, not today's messages. MORE checks its source before every playback."),
            part("MORE checks its source before every playback", fr: "MORE vérifie sa source avant chaque lecture",
                 of: "The date is spoken too. This is a saved excerpt, not today's messages. MORE checks its source before every playback."),
            part("Up to 24 short, complete lines from the saved text", fr: "Jusqu’à 24 lignes courtes et complètes du texte enregistré",
                 of: "Up to 24 short, complete lines from the saved text. Check extracted words against the recording; screen recognition can make mistakes."),
            part("Check extracted words against the recording; screen recognition can make mistakes",
                 fr: "Comparez les mots extraits à l’enregistrement ; la reconnaissance d’écran peut se tromper",
                 of: "Up to 24 short, complete lines from the saved text. Check extracted words against the recording; screen recognition can make mistakes.")
        ], controls: [
            shown("A saved moment", fr: "Un moment enregistré"),
            shown("Choose an excerpt", fr: "Choisir un extrait"),
            shown("What you'll hear", fr: "Ce que vous entendrez"),
            shown("Hear preview", fr: "Écouter un aperçu"),
            shown("Add to my morning", fr: "Ajouter à ma matinée")
        ]),
        // Correcting one sampled screen's label, above excerpts of its original text.
        Screen(name: "Screen label", copy: [
            part("Describe the screen, such as Calendar or Messages", fr: "Décrivez l’écran, par exemple Calendrier ou Messages",
                 of: "Describe the screen, such as Calendar or Messages. This changes your review, not the original recording or the model's result."),
            part("This changes your review, not the original recording or the model's result",
                 fr: "Cela modifie votre relecture, pas l’enregistrement d’origine ni le résultat du modèle",
                 of: "Describe the screen, such as Calendar or Messages. This changes your review, not the original recording or the model's result."),
            shown("Unknown screens stay visible in your review and are left out of new activity suggestions.",
                  fr: "Les écrans inconnus restent visibles dans votre relecture et sont exclus des nouvelles suggestions d’activités."),
            shown("Removing your correction restores the original interpretation, if one is available.",
                  fr: "Supprimer votre correction rétablit l’interprétation d’origine, si elle existe."),
            part("No short, complete excerpt is available to anchor a label",
                 fr: "Aucun extrait court et complet n’est disponible pour appuyer un libellé",
                 of: "No short, complete excerpt is available to anchor a label. You can still keep this screen unknown."),
            part("Choose the saved words that help you recognize this screen",
                 fr: "Choisissez les mots enregistrés qui vous aident à reconnaître cet écran",
                 of: "Choose the saved words that help you recognize this screen. Your label is your interpretation; it doesn't prove an app was opened or a message was read."),
            part("it doesn't prove an app was opened or a message was read",
                 fr: "il ne prouve pas qu’une app a été ouverte ou qu’un message a été lu",
                 of: "Choose the saved words that help you recognize this screen. Your label is your interpretation; it doesn't prove an app was opened or a message was read.")
        ], controls: [
            shown("Screen label", fr: "Libellé de l’écran"),
            shown("Your label", fr: "Votre libellé"),
            shown("What was on this screen?", fr: "Qu’y avait-il sur cet écran ?"),
            shown("Keep this screen unknown", fr: "Laisser cet écran inconnu"),
            shown("Remove my correction", fr: "Supprimer ma correction"),
            shown("Original excerpt", fr: "Extrait d’origine")
        ]),
        // The list of saved observations, and choosing some of them for an update.
        Screen(name: "Observations", copy: [
            part("Saved glimpses of your morning", fr: "Des aperçus enregistrés de votre matinée",
                 of: "Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use."),
            part("Observations and routine runs stay separate; sampled screens don't measure complete phone use",
                 fr: "Les observations et les sessions restent séparées ; les écrans échantillonnés ne mesurent pas toute l’utilisation du téléphone",
                 of: "Saved glimpses of your morning. Observations and routine runs stay separate; sampled screens don't measure complete phone use."),
            part("These observations need a day before they can appear in your morning history",
                 fr: "Ces observations doivent avoir un jour avant d’apparaître dans l’historique de vos matinées",
                 of: "These observations need a day before they can appear in your morning history. The day a file was imported doesn't tell us when it was recorded."),
            part("The day a file was imported doesn't tell us when it was recorded",
                 fr: "Le jour d’import d’un fichier n’indique pas quand il a été enregistré",
                 of: "These observations need a day before they can appear in your morning history. The day a file was imported doesn't tell us when it was recorded."),
            shown("Your current routine stays in place until you approve the update.",
                  fr: "Votre routine actuelle reste en place jusqu’à ce que vous approuviez la mise à jour."),
            part("Choose dated observations from your own mornings, or a separate set of samples",
                 fr: "Choisissez des observations datées de vos propres matinées, ou un ensemble d’exemples séparé",
                 of: "Choose dated observations from your own mornings, or a separate set of samples. Nothing is selected automatically."),
            shown("Choose one to five observations.", fr: "Choisissez entre une et cinq observations.")
        ], controls: [
            shown("Observations", fr: "Observations"),
            shown("Date needed", fr: "Date requise"),
            shown("Choose mornings", fr: "Choisir des matinées"),
            shown("Done choosing", fr: "Sélection terminée"),
            shown("Delete all observations", fr: "Supprimer toutes les observations"),
            shown("No saved observations", fr: "Aucune observation enregistrée"),
            shown("Review suggested update", fr: "Relire la mise à jour suggérée"),
            shown("Clear selection", fr: "Effacer la sélection"),
            shown("Suggest an update", fr: "Suggérer une mise à jour")
        ]),
        // A suggestion from the model, with the quotations it rests on.
        Screen(name: "Suggested update", copy: [
            shown("Your current routine stays ready until you approve.", fr: "Votre routine actuelle reste prête jusqu’à votre approbation."),
            shown("Review your moments, then approve when ready.", fr: "Relisez vos moments, puis approuvez quand vous le souhaitez."),
            part("These samples weren't used to suggest activities", fr: "Ces échantillons n’ont pas servi à suggérer des activités",
                 of: "These samples weren't used to suggest activities. Missing or unsuitable evidence stays unknown."),
            part("Missing or unsuitable evidence stays unknown", fr: "Les éléments manquants ou inadaptés restent inconnus",
                 of: "These samples weren't used to suggest activities. Missing or unsuitable evidence stays unknown."),
            shown("Correct a source in Learn to request a new suggestion.",
                  fr: "Corrigez une source dans Apprendre pour demander une nouvelle suggestion."),
            part("Minutes are planned, not measured averages", fr: "Les minutes sont prévues, pas des moyennes mesurées",
                 of: "Minutes are planned, not measured averages. Visible words don't prove an action or a repeated habit."),
            part("Visible words don't prove an action or a repeated habit",
                 fr: "Des mots visibles ne prouvent ni une action ni une habitude répétée",
                 of: "Minutes are planned, not measured averages. Visible words don't prove an action or a repeated habit."),
            part("You can edit your current routine under Review → Your routine",
                 fr: "Vous pouvez modifier votre routine actuelle dans Historique → Votre routine",
                 of: "Done saves this suggestion for later. You can edit your current routine under Review → Your routine."),
            shown("Sample observations stay separate from your personal habit history.",
                  fr: "Les observations d’exemple restent séparées de votre historique personnel."),
            shown("Finish or end your current morning before approving an update.",
                  fr: "Terminez ou arrêtez votre matinée en cours avant d’approuver une mise à jour."),
            part("The observations or your routine may have changed", fr: "Les observations ou votre routine ont peut-être changé",
                 of: "The observations or your routine may have changed. Choose the mornings again to make a fresh suggestion.")
        ], controls: [
            shown("Suggested update", fr: "Mise à jour suggérée"),
            shown("Approve update", fr: "Approuver la mise à jour"),
            shown("Keep current", fr: "Garder l’actuelle"),
            shown("Why this suggestion?", fr: "Pourquoi cette suggestion ?"),
            // Headings a recommendation in any app could carry: they confirm, they do not count.
            shown("Compare with current routine", fr: "Comparer avec la routine actuelle"),
            shown("Kept by your choice", fr: "Gardé selon votre choix"),
            shown("Your saved timing choice", fr: "Votre choix de durée enregistré"),
            shown("Selected observations", fr: "Observations sélectionnées"),
            shown("About this suggestion", fr: "À propos de cette suggestion"),
            shown("Suggestion no longer available", fr: "Suggestion plus disponible"),
            shown("Your next morning", fr: "Votre prochaine matinée")
        ]),
        // The step editor shows a step's own saved wording.
        Screen(name: "Step", copy: [
            part("You can change the order of your steps back in your routine",
                 fr: "Vous pourrez changer l’ordre des étapes dans votre routine",
                 of: "Keep it simple. You can change the order of your steps back in your routine."),
            part("Choose an action below to decide what Morning Operator does",
                 fr: "Choisissez une action ci-dessous pour décider de ce que fait Morning Operator",
                 of: "The category organizes your routine. Choose an action below to decide what Morning Operator does."),
            part("Keeping a moment preserves its wording, time and action",
                 fr: "Garder un moment conserve son texte, sa durée et son action",
                 of: "Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices later in Review."),
            part("Saving only its duration lets the other details vary",
                 fr: "N’enregistrer que sa durée laisse varier les autres détails",
                 of: "Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices later in Review.")
        ], controls: [
            shown("Keep in future suggestions", fr: "Garder dans les futures suggestions"),
            shown("What Morning Operator does", fr: "Ce que fait Morning Operator"),
            shown("Make it yours", fr: "Personnalisez-la"),
            shown("Your moment", fr: "Votre moment"),
            shown("How it fits", fr: "Comment ça s’intègre"),
            shown("Keep this duration", fr: "Garder cette durée"),
            shown("Future mornings", fr: "Prochaines matinées"),
            shown("User-led moment", fr: "Moment mené par vous"),
            shown("Read this text aloud", fr: "Lire ce texte à voix haute"),
            shown("Remove this step", fr: "Retirer cette étape")
        ]),
        Screen(name: "Privacy", copy: [
            shown("Your mornings stay close.", fr: "Vos matinées restent à portée de main."),
            part("MORE keeps its learning on this device", fr: "MORE garde son apprentissage sur cet appareil",
                 of: "MORE keeps its learning on this device. You choose when to connect Apple apps and what to keep."),
            part("You choose when to connect Apple apps and what to keep",
                 fr: "Vous choisissez quand connecter les apps Apple et ce que vous gardez",
                 of: "MORE keeps its learning on this device. You choose when to connect Apple apps and what to keep."),
            part("Only Shortcuts you configure can log app names and entry/exit times",
                 fr: "Seuls les raccourcis que vous configurez peuvent enregistrer les noms d’apps et les heures d’entrée et de sortie",
                 of: "Only Shortcuts you configure can log app names and entry/exit times. This doesn't record taps or read messages. Removing local data turns this off until you enable it again."),
            part("Calendar events and prepared recaps stay in memory", fr: "Les événements et les récaps préparés restent en mémoire",
                 of: "Calendar events and prepared recaps stay in memory. MORE saves only the calendars you select, your chosen weather city and temperature unit."),
            part("Screen content and learning aren't sent with these requests",
                 fr: "Le contenu de l’écran et l’apprentissage ne sont pas envoyés avec ces demandes",
                 of: "City searches go to Apple Maps. Weather requests send the selected city’s coordinates to Apple Weather. Screen content and learning aren't sent with these requests."),
            part("Apple permissions, installed voices, Shortcuts and device backups are managed separately",
                 fr: "Les autorisations Apple, les voix installées, Raccourcis et les sauvegardes de l’appareil sont gérés séparément",
                 of: "Apple permissions, installed voices, Shortcuts and device backups are managed separately. Removing local data doesn't change them or erase copies outside this app."),
            shown("Forget MORE’s local data", fr: "Oublier les données locales de MORE"),
            shown("Save app activity from Shortcuts", fr: "Enregistrer l’activité des apps depuis Raccourcis")
        ], controls: [
            shown("Saved in MORE", fr: "Enregistré dans MORE"),
            shown("Outside MORE", fr: "Hors de MORE"),
            shown("Current routine", fr: "Routine actuelle"),
            shown("Previous routine", fr: "Routine précédente"),
            shown("Saved mornings", fr: "Matinées enregistrées"),
            shown("Saved choices", fr: "Choix enregistrés"),
            shown("App activity", fr: "Activité des apps"),
            shown("Your day", fr: "Votre journée")
        ]),
        // One day of Review: the runs saved for it.
        Screen(name: "Day", copy: [
            shown("No routine saved for this day.", fr: "Aucune routine enregistrée pour ce jour."),
            part("It isn't counted as a zero-minute morning", fr: "Elle n’est pas comptée comme une matinée de zéro minute",
                 of: "A missing run stays unknown. It isn't counted as a zero-minute morning."),
            shown("No observation dated to this day.", fr: "Aucune observation datée de ce jour."),
            shown("Timing is incomplete or unavailable; this run is excluded from time averages.",
                  fr: "La durée est incomplète ou indisponible ; cette session est exclue des moyennes."),
            part("Active time excludes pauses and doesn't measure activity in other apps",
                 fr: "Le temps actif exclut les pauses et ne mesure pas l’activité dans d’autres apps",
                 of: "Saved routine version %lld. Active time excludes pauses and doesn't measure activity in other apps.")
        ], controls: [
            shown("Observed mornings", fr: "Matinées observées"),
            shown("Routine runs", fr: "Sessions de routine"),
            shown("Active routine time", fr: "Temps de routine actif"),
            shown("Planned time", fr: "Durée prévue"),
            shown("Marked complete", fr: "Marqué comme terminé"),
            shown("Skipped", fr: "Passé"),
            shown("Not completed", fr: "Non terminé"),
            shown("App observations", fr: "Observations d’apps")
        ])
    ]

    /// Every phrase above, for the test that compares this table with the String Catalogs.
    static var all: [Phrase] {
        distinctiveLines + marketing + marketingPair + earlierReviewHeadings + [earlierReviewNote]
            + [overviewHeading] + overviewCopy + homeHeadings + homeFooters
            + [homeReviewPrompt, recordingBadge, playbackNow, playbackPause, playbackPaused, playbackContinue]
            + pairs.flatMap { $0 } + labelGroups.flatMap { $0 } + screens.flatMap { $0.copy + $0.controls }
    }

    // MARK: - Recognition

    /// True when the frame is one of MORE's own screens.
    ///
    /// One complete line that is a distinctive MORE title or control is enough, and so is the
    /// recording badge read beside the home's date. Otherwise the frame must hold two different
    /// pieces of the same MORE screen, at least one of them a sentence or heading specific to
    /// MORE. Short ordinary labels such as "Record" or « Enregistrer » never identify a screen
    /// alone or together; they only confirm such a sentence.
    static func identifies(_ frame: Frame) -> Bool {
        if distinctiveLines.contains(where: { $0.isLine(of: frame) }) || containsMarketing(frame) { return true }
        if showsRecordingBadge(frame) { return true }
        // Generic labels such as "Average routine" must not exclude a real calendar entry.
        let reviewMarkers = earlierReviewHeadings.filter { $0.isLine(of: frame) }.count
            + (earlierReviewNote.isWithin(frame) ? 1 : 0)
        if reviewMarkers >= 2 { return true }
        // The overview displays earlier derived labels; feeding them back would reinforce our own output.
        if overviewHeading.isLine(of: frame), overviewCopy.contains(where: { $0.isWithin(frame) }) { return true }
        // The home shows our saved or proposed routine, not new evidence that it happened.
        let hasHeading = homeHeadings.contains { $0.isLine(of: frame) }
        let hasFooter = homeFooters.contains { $0.isLine(of: frame) }
        if hasHeading, hasFooter || homeReviewPrompt.isLine(of: frame) { return true }
        // The earlier forms of the badge rule, kept for recordings read in another letter case:
        // the heading with the badge, on its own line or merged into the heading's row.
        let headingWithBadge = homeHeadings.flatMap(\.normalized).contains { heading in
            recordingBadge.normalized.contains { frame.lines.contains("\(heading) \($0)") }
        }
        if (hasHeading && recordingBadge.isLine(of: frame)) || headingWithBadge { return true }
        // The active home omits its heading: require its footer plus both playback controls.
        if hasFooter,
           (playbackNow.isLine(of: frame) && playbackPause.isLine(of: frame))
            || (playbackPaused.isLine(of: frame) && playbackContinue.isLine(of: frame)) { return true }
        if pairs.contains(where: { pair in pair.allSatisfy { $0.isWithin(frame) } }) { return true }
        if labelGroups.contains(where: { group in group.allSatisfy { $0.isAtLineEdge(of: frame) } }) { return true }
        // Every recognized sentence on this frame, once: a label that is words of one of them
        // is not a second piece, whichever screen the sentence belongs to.
        let present = frame.sentences(among: screens.flatMap(\.copy))
        return screens.contains { screen in
            let found = screen.copy.map { $0.occurrences(in: frame) }.filter { !$0.isEmpty }
            guard !found.isEmpty else { return false }
            // Each sentence needs words of its own: two that share a word are one passage, once.
            // The frame that asked for this was a message reading "Use the audio output picker
            // to choose an available speaker. Output doesn't connect a HomePod microphone.":
            // Settings ends one sentence with "speaker" and begins the next with "Speaker
            // output", so both were found in it through that one word, and it was rejected.
            let twoSentences = found.indices.contains { first in
                found.indices.contains { second in
                    first < second && found[first].contains { one in found[second].contains { !$0.overlaps(one) } }
                }
            }
            // A wrapped sentence can leave a line that reads like a label ("your routine,").
            // That line is the same piece, not a second one.
            return twoSentences || screen.controls.contains { $0.isLine(of: frame, apartFrom: present) }
        }
    }

    /// True when the frame shows the home's recording badge, which MORE shows only while it
    /// records: the most common own frame of a recording is the home with a routine running,
    /// where the step titles are the person's saved routine and read like real activity.
    ///
    /// The badge must end a line in MORE's own capitals, "MORE" then "Recording" or
    /// « Enregistrement ». It sits in the date's row, so it is accepted when that line also
    /// holds the date, or when it stands alone (at most a misread symbol beside it) and the
    /// frame shows something else of the home: the date on a line of its own, a line that
    /// begins with the heading, or a playback label. Alone among another app's lines it is
    /// not enough, and neither is "more recording" in any other case or place.
    static func showsRecordingBadge(_ frame: Frame) -> Bool {
        let before = recordingBadge.wordsBeforeLineEnd(in: frame).map(withoutSymbols)
        if before.contains(where: isHomeDate) { return true }
        guard before.contains(where: \.isEmpty) else { return false }
        let headings = homeHeadings.flatMap(\.normalized)
        return frame.shownLines.contains { isHomeDate(withoutSymbols($0.map(LearningEvidencePolicy.normalized))) }
            || frame.lines.contains { line in headings.contains { line == $0 || line.hasPrefix("\($0) ") } }
            || [playbackNow, playbackPause, playbackPaused, playbackContinue].contains { $0.isLine(of: frame) }
    }

    /// The words of a line without what the symbols at its end were read as: the chevron
    /// beside the date and the badge's own dot, each a single letter or a zero at most.
    private static func withoutSymbols(_ words: [String]) -> [String] {
        var words = words
        while let last = words.last, last == "0" || (last.count == 1 && last.allSatisfy(\.isLetter)) { words.removeLast() }
        return words
    }

    /// The home's date as written with separate words ("Tue, Oct 13", « mar. 13 oct. »): a day
    /// of the month with up to three short words (« ter., 13 de out. »). A date written as one run of signs
    /// ("10月13日") is not recognized here; the badge then needs another piece of the home.
    private static func isHomeDate(_ words: [String]) -> Bool {
        let days = words.filter { Int($0).map { (1...31).contains($0) } ?? false }
        let names = words.filter { $0.allSatisfy(\.isLetter) }
        return days.count == 1 && (1...3).contains(names.count) && days.count + names.count == words.count
            && names.allSatisfy { (2...5).contains($0.count) }
    }

    static func containsMarketing(_ frame: Frame) -> Bool {
        marketing.contains { $0.isWithin(frame) } || marketingPair.allSatisfy { $0.isWithin(frame) }
    }
}
