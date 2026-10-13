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

        /// This wording also occurs, as whole words, inside `other`.
        func isPart(of other: Phrase) -> Bool {
            normalized.contains { mine in other.normalized.contains { " \($0) ".contains(" \(mine) ") } }
        }
    }

    /// One screen's recognized text: its complete lines, and all of it as one run of words.
    struct Frame: Sendable {
        let lines: Set<String>
        let text: String

        init(_ source: String) {
            lines = Set(source.components(separatedBy: .newlines).map(LearningEvidencePolicy.normalized))
            text = " \(LearningEvidencePolicy.normalized(source)) "
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

    /// The Learn, Review, Settings, routine, recording and voice screens as they read today.
    static let screens: [Screen] = [
        Screen(name: "Learn", copy: [
            shown("Make your morning yours.", fr: "Faites de votre matinée la vôtre."),
            part("Start with what you already do", fr: "Partez de ce que vous faites déjà",
                 of: "Start with what you already do. You'll review every suggestion before it becomes your routine."),
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
            shown("Add context, if you like", fr: "Ajoutez du contexte, si vous le souhaitez"),
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
                 of: "Analysis uses Apple's on-device model when available. It doesn't run other apps or approve a routine for you.")
        ], controls: [
            shown("Suggest a routine", fr: "Suggérer une routine"),
            shown("Suggest an update", fr: "Suggérer une mise à jour"),
            shown("Check availability again", fr: "Vérifier à nouveau la disponibilité"),
            shown("Record", fr: "Enregistrer"),
            shown("Choose", fr: "Choisir"),
            shown("Your rhythm", fr: "Votre rythme"),
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
            // The words every plural form shares, then the singular's own form.
            part("have no complete timing", fr: "pas de durée complète",
                 of: "%lld saved runs have no complete timing. They stay out of the average.",
                 earlier: "has no complete timing"),
            part("out of the average", fr: "pas dans la moyenne",
                 of: "%lld saved runs have no complete timing. They stay out of the average."),
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
                 of: "A voice’s language affects pronunciation. Choosing it does not translate your routine."),
            part("Return here after the download finishes", fr: "Revenez ici une fois le téléchargement terminé",
                 of: "In Settings → Accessibility → Read & Speak → Voices, choose your language and download an Enhanced or Premium voice if offered. Return here after the download finishes.")
        ], controls: [
            shown("More natural voices", fr: "Des voix plus naturelles"),
            shown("Installed voices", fr: "Voix installées"),
            shown("Preview selected voice", fr: "Écouter la voix choisie"),
            shown("Refresh installed voices", fr: "Actualiser les voix installées")
        ])
    ]

    /// Every phrase above, for the test that compares this table with the String Catalogs.
    static var all: [Phrase] {
        distinctiveLines + marketing + marketingPair + earlierReviewHeadings + [earlierReviewNote]
            + [overviewHeading] + overviewCopy + homeHeadings + homeFooters
            + [homeReviewPrompt, recordingBadge, playbackNow, playbackPause, playbackPaused, playbackContinue]
            + pairs.flatMap { $0 } + screens.flatMap { $0.copy + $0.controls }
    }

    // MARK: - Recognition

    /// True when the frame is one of MORE's own screens.
    ///
    /// One complete line that is a distinctive MORE title or control is enough. Otherwise the
    /// frame must hold two different pieces of the same MORE screen, at least one of them a
    /// sentence or heading specific to MORE. Short ordinary labels such as "Record" or
    /// « Enregistrer » never identify a screen alone or together; they only confirm such a sentence.
    static func identifies(_ frame: Frame) -> Bool {
        if distinctiveLines.contains(where: { $0.isLine(of: frame) }) || containsMarketing(frame) { return true }
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
        // While native capture runs, the heading is paired with the branded recording control,
        // on its own line or merged into the heading's row. Neither alone is a guard.
        let headingWithBadge = homeHeadings.flatMap(\.normalized).contains { heading in
            recordingBadge.normalized.contains { frame.lines.contains("\(heading) \($0)") }
        }
        if (hasHeading && recordingBadge.isLine(of: frame)) || headingWithBadge { return true }
        // The active home omits its heading: require its footer plus both playback controls.
        if hasFooter,
           (playbackNow.isLine(of: frame) && playbackPause.isLine(of: frame))
            || (playbackPaused.isLine(of: frame) && playbackContinue.isLine(of: frame)) { return true }
        if pairs.contains(where: { pair in pair.allSatisfy { $0.isWithin(frame) } }) { return true }
        return screens.contains { screen in
            // Each sentence needs words of its own: two that share a word are one passage, once.
            var unclaimed = frame.text
            let sentences = screen.copy.filter { phrase in
                guard let found = phrase.normalized.lazy.compactMap({ unclaimed.range(of: " \($0) ") }).first else { return false }
                unclaimed.replaceSubrange(found, with: " \u{1F} ")
                return true
            }
            guard let sentence = sentences.first else { return false }
            // A wrapped sentence can leave a line that reads like a label ("your routine,").
            // That line is the same piece, not a second one.
            return sentences.count >= 2
                || screen.controls.contains { $0.isLine(of: frame) && !$0.isPart(of: sentence) }
        }
    }

    static func containsMarketing(_ frame: Frame) -> Bool {
        marketing.contains { $0.isWithin(frame) } || marketingPair.allSatisfy { $0.isWithin(frame) }
    }
}
