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
        func wordsBeforeLineEnd(in frame: Frame, withoutClockTimes: Bool = false) -> [[String]] {
            let shown = wordings.map(Frame.words)
            return (withoutClockTimes ? frame.shownLinesWithoutClockTime : frame.shownLines).compactMap { line in
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

        /// The same, leaving out lines that show an hour ("09:30", « 9h30 »): once split into
        /// words, an hour's two numbers read like a day and a month.
        let shownLinesWithoutClockTime: [[String]]

        init(_ source: String) {
            let recognized = source.components(separatedBy: .newlines)
            lines = Set(recognized.map(LearningEvidencePolicy.normalized))
            text = " \(LearningEvidencePolicy.normalized(source)) "
            shownLines = recognized.map(Self.words).filter { !$0.isEmpty }
            shownLinesWithoutClockTime = recognized
                .filter { $0.range(of: #"\d\s*[:hH]\s*\d"#, options: .regularExpression) == nil }
                .map(Self.words).filter { !$0.isEmpty }
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

    /// These views choose FR/EN literals directly. Their exact live source text is
    /// checked by tests rather than by a String Catalog entry that they do not use.
    private static func sourceLiteral(_ en: String, fr: String) -> Phrase {
        Phrase(catalogKey: nil, isPart: false, [en, fr])
    }

    static let privacyIntroduction = sourceLiteral(
        "Learning stays local by default. If you enable OpenAI, relevant excerpts and context are processed by OpenAI. You control access and saved personal facts.",
        fr: "L’apprentissage reste local par défaut. Si vous activez OpenAI, les extraits et le contexte utiles sont traités par OpenAI. Vous gardez le contrôle des accès et des données mémorisées.")

    // MARK: - Wording

    /// Titles and controls distinctive enough that one complete line identifies the screen.
    static let distinctiveLines: [Phrase] = [
        earlier("Learn my morning", "Apprendre ma matinée"),
        shown("Show your morning", fr: "Montrez votre matinée"),
        shown("Make your morning yours.", fr: "Faites de votre matinée la vôtre."),
        earlier("Your routine stays in your hands", "Votre routine reste entre vos mains"),
        // The Learn button read this until it was shortened to "Record"; it is still its spoken label.
        shown("Record a little of my morning", fr: "Enregistrer un peu de ma matinée"),
        shown("Sample morning, not your observed activity", fr: "Matinée d’exemple, pas votre activité observée"),
        shown("Your mornings will find their shape.", fr: "Vos matinées vont prendre forme."),
        earlier("Your morning voice", "La voix de votre matinée"),
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

    /// An Outlook title or an ordinary email mentioning Outlook is insufficient.
    /// The matching explanation must also be present in that same visible frame.
    static let outlookPairs: [[Phrase]] = [
        [sourceLiteral("Your Outlook Inbox, each morning", fr: "Votre boîte Outlook, chaque matin"),
         sourceLiteral("Choose an account and review its identity. MORE reads up to three previews of unread Inbox messages, including older unread messages.",
               fr: "Choisissez un compte et vérifiez son identité. MORE lit au plus trois aperçus de messages non lus de la boîte de réception, même anciens.")],
        [sourceLiteral("Your Outlook messages", fr: "Vos messages Outlook"),
         sourceLiteral("Up to three unread previews, including older messages. No importance ranking. Choose a message to read its body; attachments and remote resources are not opened.",
               fr: "Au plus trois aperçus de non lus, même anciens. Aucun classement d’importance. Choisissez un message pour lire son corps ; aucune pièce jointe ni ressource distante ne sera ouverte.")]
    ]
    static let screenTimePickerPair: [Phrase] = [
        sourceLiteral("App moments from Screen Time", fr: "Moments d’app depuis Screen Time"),
        sourceLiteral("Choose apps to add as separate moments. Observed sequences and your kept rituals stay in the plan. Up to eight app moments can be added.",
            fr: "Choisissez les apps à ajouter comme moments distincts. Les séquences observées et vos rituels gardés restent dans le plan. Jusqu’à huit moments d’app peuvent être ajoutés.")
    ]

    /// Compact connection rows need all three pieces; provider names alone identify nothing.
    static let compactConnections: [Phrase] = [
        shown("Apps & accounts", fr: "Apps et comptes"),
        sourceLiteral("Messages & your feed", fr: "Messages et fil d’actualité"),
        sourceLiteral("Website · Sign in", fr: "Site web · Se connecter")
    ]
    static let compactConfirmedConnections: [Phrase] = [
        compactConnections[0], compactConnections[1],
        sourceLiteral("Confirmed by you · Open website", fr: "Confirmé par vous · Ouvrir le site")
    ]

    /// Screens without a heading of their own: every piece must be present.
    static let pairs: [[Phrase]] = outlookPairs + [screenTimePickerPair, compactConnections, compactConfirmedConnections] + [
        [shown("Your Calendly appointments, each morning", fr: "Vos rendez-vous Calendly, chaque matin"),
         shown("Choose an account. MORE reads appointments starting today in this iPhone’s time zone.",
               fr: "Choisissez un compte. MORE lit les rendez-vous qui commencent aujourd’hui dans le fuseau de cet iPhone.")],
        [shown("Your calendar, each morning", fr: "Votre calendrier, chaque matin"),
         shown("Choose one calendar. MORE reads the current day in this iPhone’s time zone each morning.",
               fr: "Choisissez un calendrier. MORE lit le jour courant dans le fuseau de cet iPhone à chaque matin.")],
        [shown("Prepare listening", fr: "Préparer l’écoute"),
         shown("This preparation records no audio and does not test the microphone. Reading aloud and continuing your routine remain separate choices.",
               fr: "Cette préparation n’enregistre aucun son et ne teste pas le microphone. La lecture à voix haute et l’enchaînement de votre routine restent des choix distincts.")],
        [shown("Prepare listening", fr: "Préparer l’écoute"),
         shown("Local recognition availability will be checked after your permission. Listening has not started.",
               fr: "La disponibilité de la reconnaissance locale sera vérifiée après votre autorisation. Aucune écoute n’a commencé.")],
        // A Slack heading alone can belong to Slack; MORE's own explanation must accompany it.
        [shown("Slack in your morning", fr: "Slack dans votre matin"),
         shown("Choose a workspace and channel. MORE can read its messages and prepare a reply for your review.",
               fr: "Choisissez un espace et un canal. MORE pourra lire ses messages et préparer une réponse à relire.")],
        [shown("Reply in Slack", fr: "Répondre dans Slack"),
         shown("Choose a message and say what you want to reply. MORE reviews the account, channel, message and reply before your send instruction.",
               fr: "Choisissez un message et dites ce que vous souhaitez répondre. MORE relit le compte, le canal, le message et la réponse avant votre instruction d’envoi.")],
        [earlier("Start my morning"), earlier("Update my morning")],
        [earlier("A little perspective."), shown("Settings & connections", fr: "Réglages et connexions")],
        [earlier("More room for your day."), earlier("Anything you’d like to remember?")],
        [earlier("Show us your morning", "Montrez-nous votre matinée", "Show us a little of your morning", "Montrez-nous un peu de votre matinée", "Show MORE a little of your morning"),
         earlier("Keep what works for you", "Gardez ce qui vous convient", "We’ll find the rhythm together", "Nous trouverons le rythme ensemble")]
    ]

    /// Screens that show text MORE did not write (an earlier observation, a suggestion from
    /// the model) with no sentence of MORE's in view: labels that always sit together, in the
    /// bars that stay while the text scrolls or around the text itself. Every piece of a group
    /// must begin or end a line.
    static let labelGroups: [[Phrase]] = [
        // The inline Home browser may show only saved rows. The date-page heading
        // must accompany a run/observation label; a generic status alone is not MORE.
        [shown("Saved on this day", fr: "Enregistré ce jour-là"), shown("Routine finished", fr: "Routine terminée")],
        [shown("Saved on this day", fr: "Enregistré ce jour-là"), shown("Routine stopped", fr: "Routine arrêtée")],
        [shown("Saved on this day", fr: "Enregistré ce jour-là"), shown("Saved observations", fr: "Observations enregistrées")],
        [shown("Saved on this day", fr: "Enregistré ce jour-là"), shown("App observations", fr: "Observations d’apps")],
        // A scrolled routine can contain the person's own labels. These fixed bars
        // identify the editor without using any of that saved routine as evidence.
        [shown("Routine", fr: "Routine"), shown("Add a moment", fr: "Ajouter un moment")],
        // Compact Settings keeps its explanations folded away. Four fixed destination
        // labels together identify it; an ordinary alarm/calendar label alone does not.
        [shown("Morning alarm", fr: "Réveil du matin"), shown("Shortcuts & timers", fr: "Raccourcis et minuteurs"),
         shown("Your next morning", fr: "Votre prochaine matinée"), shown("Calendar & weather", fr: "Calendrier et météo")],
        [shown("Shortcuts & timers", fr: "Raccourcis et minuteurs"), shown("Lock Screen", fr: "Écran verrouillé"),
         shown("Voice", fr: "Voix"), shown("Audio output", fr: "Sortie audio")],
        // The suggested update, wherever it is scrolled, quotations included: the title and
        // both buttons of the bars that stay. Two of the three are what any updater shows.
        [shown("Suggested update", fr: "Mise à jour suggérée"), shown("Keep current", fr: "Garder l’actuelle"),
         shown("Let MORE take care of this morning", fr: "Confier ce matin à MORE", earlier: "Approve update", "Approuver la mise à jour")],
        [shown("Suggested update", fr: "Mise à jour suggérée"), shown("Discard", fr: "Supprimer"),
         shown("Let MORE take care of this morning", fr: "Confier ce matin à MORE", earlier: "Approve update", "Approuver la mise à jour")],
        // At accessibility sizes only MORE's compact branded approval stays pinned.
        [shown("Suggested update", fr: "Mise à jour suggérée"), shown("Let MORE do it", fr: "Confier à MORE")],
        // The list of saved observations: its title and the button beside it, and the two
        // buttons under it once some are chosen.
        [shown("Observations", fr: "Observations"), shown("Choose mornings", fr: "Choisir des matinées")],
        [shown("Clear selection", fr: "Effacer la sélection"), shown("Suggest an update", fr: "Suggérer une mise à jour")],
        // One saved observation: the two rows above its notes.
        [shown("Read a saved moment", fr: "Lire un moment enregistré"), shown("Edit in Learn", fr: "Modifier dans Apprendre")],
        // One sampled screen: its title read as one line with the button beside it.
        [shown("Sampled moment", fr: "Moment échantillonné"), shown("Done", fr: "Terminé")]
    ]

    /// The retired introduction still occurs in saved recordings; its copy is no longer catalog-bound.
    static let earlierConnections = Screen(name: "Apps and accounts", copy: [
        earlier("Your apps, in one place.", "Vos apps, au même endroit."),
        earlier("Choose what you want to bring into your morning.", "Choisissez ce qui vous accompagne le matin."),
        earlier("Your messages, stories and feed, in MORE.", "Vos messages, vos stories et votre fil, dans MORE."),
        earlier("Read your unread email and prepare replies.", "Lisez vos e-mails non lus et préparez vos réponses."),
        earlier("A little setup. Then you're home.", "Un instant de préparation. Puis à vous de jouer."),
        earlier("Connect Gmail below, or sign in to the websites your morning uses.", "Connectez Gmail ci-dessous ou identifiez-vous sur les sites de votre matin."),
        earlier("Sign in once, here. Your morning uses these same pages.", "Connectez-vous ici une fois. Votre matin utilisera ces mêmes pages.")
    ], controls: [
        shown("Apps & accounts", fr: "Apps et comptes"),
        shown("Calendar & weather", fr: "Calendrier et météo"),
        shown("Your day", fr: "Votre journée"),
        earlier("Your websites", "Vos sites"),
        earlier("Connect my websites", "Connecter mes sites")
    ])

    /// The installed-voice picker was replaced; its older recordings still need exclusion.
    static let earlierVoice = Screen(name: "Voice", copy: [
        earlier("Your choice applies to spoken morning steps", "Votre choix s’applique aux moments lus à voix haute",
                "Votre choix s’applique aux étapes lues à voix haute"),
        earlier("These are Apple system speech voices; Siri may use a different voice",
                "Ce sont les voix système d’Apple ; Siri peut utiliser une voix différente"),
        earlier("Choosing it does not translate your routine", "La choisir ne traduit pas votre routine"),
        earlier("Your own routine text is preserved", "Le texte de vos routines est conservé")
    ], controls: [
        earlier("More natural voices", "Des voix plus naturelles"),
        earlier("Installed voices", "Voix installées"),
        earlier("Preview selected voice", "Écouter la voix choisie"),
        earlier("Refresh installed voices", "Actualiser les voix installées")
    ])

    /// Current and historical screen wording share recognition rules. `shown` and `part`
    /// follow the live catalogs; `earlier` keeps saved observations readable after a redesign.
    /// Shorter current labels remain controls and cannot identify a screen by themselves.
    static let screens: [Screen] = [
        Screen(name: "Inline day browser", copy: [
            earlier("Saved days are unavailable. Try again later.", "Les jours enregistrés sont indisponibles. Réessayez plus tard."),
            earlier("Past days show saved activity", "Les jours passés montrent l’activité enregistrée"),
            earlier("Return to Today to continue your morning", "Revenez à Aujourd’hui pour poursuivre votre matinée"),
            shown("No personal run or confirmed observation is saved for this day.",
                  fr: "Aucune session personnelle ni observation confirmée n’est enregistrée pour ce jour."),
            shown("Samples and unconfirmed sources are not included.",
                  fr: "Les exemples et les sources non confirmées sont exclus."),
            shown("This day could not be displayed in the current time zone.",
                  fr: "Ce jour ne peut pas être affiché dans le fuseau horaire actuel."),
            shown("Shows saved evidence. Does not start the routine.",
                  fr: "Affiche les éléments enregistrés. Ne lance pas la routine.")
        ], controls: [
            shown("Today", fr: "Aujourd’hui"),
            shown("Previous day", fr: "Jour précédent"),
            shown("Next day", fr: "Jour suivant"),
            shown("No saved personal activity", fr: "Aucune activité personnelle enregistrée"),
            shown("Saved on this day", fr: "Enregistré ce jour-là")
        ]),
        Screen(name: "Routine files", copy: [
            part("Open a saved MORE plan and review it before making any changes",
                 fr: "Ouvrez un plan MORE enregistré et relisez-le avant toute modification",
                 of: "Open a saved MORE plan and review it before making any changes. Import saves a draft; approval stays separate."),
            part("Import saves a draft; approval stays separate",
                 fr: "L’import enregistre un brouillon ; l’approbation reste distincte",
                 of: "Open a saved MORE plan and review it before making any changes. Import saves a draft; approval stays separate.")
        ], controls: [
            shown("Routine files", fr: "Fichiers de routine"),
            shown("Export routine", fr: "Exporter la routine"),
            shown("Import routine", fr: "Importer une routine")
        ]),
        Screen(name: "Screen Time", copy: [
            shown("Start with your app use", fr: "Commencez par votre usage des apps"),
            shown("Connect Screen Time, then show MORE a moment of your morning.", fr: "Connectez Temps d’écran, puis montrez un moment de votre matinée à MORE.")
        ], controls: [
            shown("Connect Screen Time", fr: "Connecter Temps d’écran"),
            shown("What Screen Time can show", fr: "Ce que montre Temps d’écran")
        ]),
        Screen(name: "Screen Time review", copy: [
            shown("Your morning, from Screen Time", fr: "Votre matin, d’après Temps d’écran"),
            shown("Your current routine stays ready until you approve. Approving replaces it with the moments you keep here.",
                  fr: "Votre routine actuelle reste prête jusqu’à votre accord. Approuver la remplace par les moments gardés ici.",
                  earlier: "Your current routine stays ready until you approve. Approving replaces it with the apps you keep here.",
                  "Votre routine actuelle reste prête jusqu’à votre accord. Approuver la remplace par les apps gardées ici.")
        ], controls: [
            shown("Let MORE take care of this morning", fr: "Confier ce matin à MORE", earlier: "Approve update", "Approuver la mise à jour"),
            shown("Keep current", fr: "Garder l’actuelle"),
            shown("Minutes measured", fr: "Minutes mesurées"),
            shown("Minutes estimated", fr: "Minutes estimées")
        ]),
        Screen(name: "Gmail connection", copy: [
            shown("Connect once to read Gmail and prepare replies. Google asks for read-only access.", fr: "Connectez-vous une fois pour lire Gmail et préparer des réponses. Google demande un accès en lecture seule."),
            shown("Connection saved securely on this iPhone.", fr: "Connexion enregistrée en sécurité sur cet iPhone."),
            shown("Your connection stays saved. Messages and local replies clear when you leave this screen or background MORE.", fr: "Votre connexion reste enregistrée. Les messages et les réponses locales sont effacés lorsque vous quittez cet écran ou passez MORE en arrière-plan."),
            earlier("Choose message reading or an unread count only.", "Choisissez de lire vos messages ou de consulter seulement leur nombre."),
            earlier("This Gmail session, messages and local replies clear when you leave this screen or background MORE. Manage Google access in your Google Account.", "La session Gmail, les messages et les réponses locales sont effacés lorsque vous quittez cet écran ou passez MORE en arrière-plan. Gérez l’accès Google dans votre compte Google."),
            earlier("Read the number of unread messages in your Gmail inbox. Google asks for read-only metadata access; MORE does not read message bodies.", "Consultez le nombre de messages non lus dans votre boîte Gmail. Google demande l’accès aux métadonnées en lecture seule ; MORE ne lit pas le contenu des messages."),
            earlier("This session and its count clear when you leave this screen or background MORE. Manage the Google account grant in your Google Account.", "La session et son résultat sont effacés en quittant cet écran ou en passant MORE en arrière-plan. Gérez l’autorisation Google dans votre compte Google.")
        ], controls: [
            shown("Connect Gmail", fr: "Connecter Gmail"),
            shown("Disconnect Gmail", fr: "Déconnecter Gmail"),
            earlier("Read messages", "Lire les messages", "Connect Gmail · count only", "Connecter Gmail · nombre uniquement", "Refresh Gmail", "Actualiser Gmail")
        ]),
        Screen(name: "Gmail local reply", copy: [
            shown("Your reply, in a few words", fr: "Votre réponse en quelques mots"),
            shown("Review and edit before copying. Nothing is sent or saved to Gmail.", fr: "Relisez et modifiez avant de copier. Rien n’est envoyé ni enregistré dans Gmail.")
        ], controls: [
            shown("Prepare reply", fr: "Préparer une réponse"),
            shown("Copy reply", fr: "Copier la réponse")
        ]),
        Screen(name: "Browser learning", copy: [
            shown("Learning your scroll and tap rhythm", fr: "Apprentissage du rythme de vos gestes"),
            earlier("Only this page. This estimate does not replay your gestures.", "Cette page seulement. Cette estimation ne reproduit pas vos gestes."),
            part("Only known page categories and gestures here", fr: "Uniquement les catégories de pages connues et vos gestes ici",
                 of: "Only known page categories and gestures here. Review MORE’s proposed actions in Learn before approval."),
            part("Review MORE’s proposed actions in Learn before approval", fr: "Examinez les actions proposées dans Apprendre avant de les valider",
                 of: "Only known page categories and gestures here. Review MORE’s proposed actions in Learn before approval.")
        ], controls: [
            shown("Stop learning", fr: "Arrêter l’apprentissage"),
            shown("Save to Learn", fr: "Garder pour apprendre")
        ]),
        Screen(name: "Learn", copy: [
            shown("Record a moment, or add a file.", fr: "Enregistrez un moment ou ajoutez un fichier."),
            shown("What would make a good morning?", fr: "À quoi ressemble un bon matin pour vous ?"),
            part("Edit what we found", fr: "Corrigez le texte trouvé", of: "Edit what we found. Your original stays saved."),
            part("Your original stays saved", fr: "Votre original reste enregistré", of: "Edit what we found. Your original stays saved."),
            shown("Make your morning yours.", fr: "Faites de votre matinée la vôtre."),
            earlier("You'll review every suggestion.", "Vous validerez chaque suggestion.", "You'll review every suggestion before it becomes your routine", "Vous relirez chaque suggestion avant qu’elle ne devienne votre routine"),
            earlier("Show us your morning", "Montrez-nous votre matinée"),
            earlier("2 · Show your morning", "2 · Montrez votre matin"),
            earlier("Record a short part of your morning, or choose a saved file.", "Enregistrez un court moment de votre matinée ou choisissez un fichier.", "Start an explicitly shared recording or bring one you already made", "Lancez un enregistrement que vous partagez explicitement, ou apportez-en un existant"),
            earlier("Go through a short part of your morning, then review what we can see", "Vivez une courte partie de votre matinée, puis relisez ce que nous voyons"),
            earlier("A screenshot or text file works too", "Une capture ou un fichier texte conviennent aussi", "A screenshot or text file works too", "Une capture d’écran ou un fichier texte fonctionne aussi"),
            earlier("You choose what to share", "Vous choisissez quoi partager", "recording never starts automatically", "l’enregistrement ne démarre jamais automatiquement"),
            earlier("Your routine stays in your hands", "Votre routine reste entre vos mains"),
            earlier("Your current routine stays ready while you review a suggestion", "Votre routine actuelle reste prête pendant que vous relisez une suggestion"),
            shown("About on-device learning", fr: "À propos de l’apprentissage sur l’appareil"),
            earlier("Find earlier observations in Review", "Retrouvez les observations précédentes dans Historique"),
            earlier("Review the current observation here before asking for a suggestion", "Relisez ici l’observation actuelle avant de demander une suggestion"),
            part("Each observation is saved on this device", fr: "Chaque observation est enregistrée sur cet appareil",
                 of: "Each observation is saved on this device, with its original text and your corrections kept separately. Review the current observation here before asking for a suggestion. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it."),
            part("Evidence already attached to a saved routine remains with it",
                 fr: "Les éléments déjà liés à une routine enregistrée restent avec elle",
                 of: "Each observation is saved on this device, with its original text and your corrections kept separately. Review the current observation here before asking for a suggestion. Clear this observation removes its original, corrections, sampled text and screen interpretation. Evidence already attached to a saved routine remains with it."),
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
            earlier("Correct the text below", "Corrigez le texte ci-dessous", "Review the text we found and correct anything we missed", "Relisez le texte trouvé et corrigez ce qui nous a échappé"),
            earlier("The original stays in Saved observations", "L’original reste dans les observations enregistrées", "Visible words don't always mean you performed an activity", "Des mots visibles ne signifient pas toujours que vous avez fait une activité"),
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
            shown("A few words", fr: "Quelques mots"),
            // Advice any app might give; as complete lines they confirm, they do not count as sentences.
            earlier("Add context, if you like", "Ajoutez du contexte, si vous le souhaitez"),
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
            earlier("Import or export your saved routine", "Importer ou exporter votre routine enregistrée"),
            shown("Choose a speaker or HomePod.", fr: "Choisissez une enceinte ou un HomePod."),
            earlier("A few things, your way.", "Quelques réglages, à votre façon."),
            earlier("Choose what to connect and how you'd like your morning to sound.", "Choisissez ce que vous connectez et comment votre matinée doit sonner."),
            earlier("A little context before your morning begins.", "Un peu de contexte avant que votre matinée commence."),
            earlier("Keep your place on the Lock Screen.", "Gardez votre progression sur l’écran verrouillé."),
            earlier("Hear the next step as you move through your routine.", "Entendez l’étape suivante au fil de votre routine."),
            earlier("Saved on this device", "Enregistré sur cet appareil", "What stays here, and what you can remove.", "Ce qui reste ici, et ce que vous pouvez supprimer."),
            earlier("Use the audio output picker to choose an available speaker", "Utilisez le sélecteur de sortie audio pour choisir un haut-parleur disponible"),
            part("Speaker output doesn't connect a HomePod microphone",
                 fr: "La sortie vers un haut-parleur ne connecte pas le micro d’un HomePod",
                 of: "Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet."),
            part("Room-to-room listening isn't available yet", fr: "L’écoute de pièce en pièce n’est pas encore disponible",
                 of: "Speaker output doesn't connect a HomePod microphone. Room-to-room listening isn't available yet."),
            part("You can capture thoughts and dreams, edit a routine, and use spoken guidance",
                 fr: "Vous pouvez noter pensées et rêves, modifier une routine et utiliser le guidage vocal",
                 of: "You can capture thoughts and dreams, edit a routine, and use spoken guidance even while the on-device model is unavailable."),
            earlier("Connecting a phone to a Mac doesn't automatically give this app control of the phone", "Connecter un téléphone à un Mac ne donne pas automatiquement à cette app le contrôle du téléphone"),
            earlier("Messages and email aren't connected here yet", "Les messages et les e-mails ne sont pas encore connectés ici"),
            earlier("Automatic room detection and continuous voice commands also need further work", "La détection automatique de pièce et les commandes vocales continues demandent aussi du travail")
        ], controls: [
            shown("Check again", fr: "Vérifier à nouveau"),
            shown("Routine files", fr: "Fichiers de routine"),
            earlier("Make yourself at home", "Faites comme chez vous"),
            shown("Calendar & weather", fr: "Calendrier et météo"),
            shown("Your next morning", fr: "Votre prochaine matinée"),
            shown("Your day", fr: "Votre journée"),
            earlier("Morning at a glance", "La matinée en un coup d’œil"),
            earlier("A voice to guide you", "Une voix pour vous guider"),
            earlier("Companion voice", "Voix d’accompagnement"),
            shown("Read each step aloud", fr: "Lire chaque étape à voix haute"),
            earlier("Listen where you like", "Écoutez où vous voulez"),
            shown("Privacy & data", fr: "Confidentialité et données"),
            earlier("Try the voice", "Essayer la voix")
        ]),
        Screen(name: "Routine", copy: [
            earlier("min planned · Your own pace", "min prévues · À votre rythme"),
            earlier("min planned · Spoken guidance", "min prévues · Guidage vocal"),
            part("MORE takes care of the actions shown here", fr: "MORE s’occupe des actions présentées ici",
                 of: "MORE takes care of the actions shown here. You can interrupt, extend a moment or stop by voice."),
            part("You can interrupt, extend a moment or stop by voice",
                 fr: "Vous pouvez l’interrompre, prolonger un moment ou arrêter à la voix",
                 of: "MORE takes care of the actions shown here. You can interrupt, extend a moment or stop by voice."),
            earlier("Tap a moment to edit", "Touchez un moment pour le modifier"),
            earlier("Changes save as a draft and need your approval", "Les modifications sont enregistrées en brouillon et doivent être approuvées"),
            shown("Finish or end this morning before editing your routine.",
                  fr: "Terminez ou arrêtez cette matinée avant de modifier votre routine."),
            earlier("Editing creates a new draft; your saved mornings keep their original routine",
                    "Modifier crée un nouveau brouillon ; vos matinées enregistrées gardent leur routine d’origine"),
            earlier("Restoring a routine leaves your saved choices for future suggestions unchanged.",
                    "Restaurer une routine ne modifie pas vos choix enregistrés pour les futures suggestions.")
        ], controls: [
            shown("Routine", fr: "Routine"),
            shown("Your daily routine", fr: "Votre routine de chaque jour"),
            earlier("Your moments", "Vos moments"),
            shown("Let MORE take care of my morning", fr: "Confier mon matin à MORE", earlier: "Approve this routine", "Approuver cette routine"),
            shown("Let MORE do it", fr: "Confier à MORE"),
            shown("Your routine", fr: "Votre routine"),
            earlier("Your approved routine", "Votre routine approuvée"),
            earlier("A draft for you to review", "Un brouillon à relire"),
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
                  fr: "Aucun enregistrement échantillonné n’est lié à cette observation."),
            // Under a sampled moment's label in the list.
            shown("Requested sample time; exact frame time unavailable.",
                  fr: "Heure d’échantillon demandée ; heure exacte de l’image indisponible."),
            shown("Text was limited; identity remains unknown.", fr: "Le texte était limité ; l’identité reste inconnue."),
            part("samples share this time; their order is unknown", fr: "échantillons partagent ce moment ; leur ordre est inconnu",
                 of: "%lld samples share this time; their order is unknown.",
                 earlier: "sample shares this time; its order is unknown", "échantillon à ce moment ; son ordre est inconnu")
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
        // The observed-mornings cards of Review, below their heading (the heading has its own rule).
        Screen(name: "Observed overview", copy: [
            part("A recorded glimpse, not time spent", fr: "Un aperçu enregistré, pas un temps passé",
                 of: "A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls."),
            part("These samples don't establish app opens, reads or scrolls",
                 fr: "Ces échantillons n’établissent ni ouvertures d’apps, ni lectures, ni défilements",
                 of: "A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls."),
            part("days with labeled samples", fr: "jours avec échantillons identifiés",
                 of: "%lld days with labeled samples · %lld days with observations",
                 earlier: "day with labeled samples", "jour avec échantillons identifiés"),
            part("observed days without labels", fr: "jours observés sans libellé",
                 of: "%lld observed days without labels · %lld dates without observations",
                 earlier: "observed day without labels", "jour observé sans libellé"),
            part("All labels and quotations are below", fr: "Tous les libellés et citations sont ci-dessous",
                 of: "Showing 3 of %lld labels. All labels and quotations are below."),
            part("Unresolved samples remain on", fr: "Des échantillons non résolus restent sur",
                 of: "Unresolved samples remain on %lld observed days."),
            part("Your saved sources remain available", fr: "Vos sources enregistrées restent disponibles",
                 of: "No screen labels yet. Your saved sources remain available."),
            part("Open all observations below", fr: "Ouvrez toutes les observations ci-dessous",
                 of: "Showing 3 of %lld separate time-zone and origin groups. Open all observations below.")
        ], controls: [
            shown("Your observed mornings", fr: "Vos matinées observées"),
            shown("From your observations", fr: "D’après vos observations"),
            shown("Sampled screens across days", fr: "Écrans échantillonnés au fil des jours"),
            shown("Samples & tests", fr: "Exemples et tests"),
            shown("My mornings", fr: "Mes matinées"),
            shown("Automated activity", fr: "Activité automatisée"),
            shown("Origin unsure", fr: "Origine incertaine"),
            shown("Your label", fr: "Votre libellé")
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
            part("days with labeled samples", fr: "jours avec échantillons identifiés",
                 of: "Seen on %lld of %lld days with labeled samples",
                 earlier: "day with labeled samples", "jour avec échantillons identifiés"),
            part("observed days also contain unresolved samples", fr: "jours observés contiennent aussi des échantillons non résolus",
                 of: "%lld observed days also contain unresolved samples.",
                 earlier: "observed day also contains unresolved samples", "jour observé contient aussi des échantillons non résolus"),
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
                 of: "You supplied this label. It stays separate from model labels and doesn't establish an action you took."),
            part("Return to observed mornings to see the current patterns",
                 fr: "Revenez aux matinées observées pour voir les tendances actuelles",
                 of: "The sources changed. Return to observed mornings to see the current patterns.")
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
            earlier("After approval, edit your plan in Routine", "Après approbation, modifiez votre plan dans Routine"),
            earlier("You can edit your current routine under Review → Your routine",
                    "Vous pouvez modifier votre routine actuelle dans Historique → Votre routine"),
            part("Adjust this suggestion before delegating it", fr: "Ajustez cette proposition avant de la confier à MORE",
                 of: "Adjust this suggestion before delegating it. Your saved source observations stay unchanged."),
            part("Your saved source observations stay unchanged", fr: "Vos observations sources restent inchangées",
                 of: "Adjust this suggestion before delegating it. Your saved source observations stay unchanged."),
            shown("Sample observations stay separate from your personal habit history.",
                  fr: "Les observations d’exemple restent séparées de votre historique personnel."),
            shown("Finish or end your current morning before approving an update.",
                  fr: "Terminez ou arrêtez votre matinée en cours avant d’approuver une mise à jour."),
            part("The observations or your routine may have changed", fr: "Les observations ou votre routine ont peut-être changé",
                 of: "The observations or your routine may have changed. Choose the mornings again to make a fresh suggestion.")
        ], controls: [
            shown("Suggested update", fr: "Mise à jour suggérée"),
            shown("Adjust this suggestion", fr: "Ajuster cette proposition"),
            shown("Let MORE take care of this morning", fr: "Confier ce matin à MORE", earlier: "Approve update", "Approuver la mise à jour"),
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
            earlier("This step keeps its saved excerpt", "Cette étape garde son extrait enregistré"),
            earlier("To use different words, switch to Read this text aloud and edit the note", "Pour utiliser d’autres mots, passez à « Lire ce texte à voix haute » et modifiez la note"),
            earlier("Choose a different excerpt from its observation in Review. Switching to Read this text aloud makes it an ordinary note.",
                    "Choisissez un autre extrait de son observation dans Historique. Passer à « Lire ce texte à voix haute » en fait une note ordinaire."),
            earlier("Clear these choices later in Review", "Vous pourrez effacer ces choix plus tard dans Historique"),
            earlier("Clear these choices in Settings → Saved choices", "Effacez ces choix dans Réglages → Choix enregistrés"),
            part("You can change the order of your steps back in your routine",
                 fr: "Vous pourrez changer l’ordre des étapes dans votre routine",
                 of: "Keep it simple. You can change the order of your steps back in your routine."),
            part("Choose an action below to decide what Morning Operator does",
                 fr: "Choisissez une action ci-dessous pour décider de ce que fait Morning Operator",
                 of: "The category organizes your routine. Choose an action below to decide what Morning Operator does."),
            part("Keeping a moment preserves its wording, time and action",
                 fr: "Garder un moment conserve son texte, sa durée et son action",
                 of: "Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices in Settings → Saved choices."),
            part("Saving only its duration lets the other details vary",
                 fr: "N’enregistrer que sa durée laisse varier les autres détails",
                 of: "Keeping a moment preserves its wording, time and action. Saving only its duration lets the other details vary. Minutes are planned, not measured. Clear these choices in Settings → Saved choices.")
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
            privacyIntroduction,
            earlier("MORE keeps its learning on this device", "MORE garde son apprentissage sur cet appareil"),
            earlier("You choose when to connect Apple apps and what to keep",
                    "Vous choisissez quand connecter les apps Apple et ce que vous gardez"),
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

    private static let recognitionScreens = screens + [earlierConnections, earlierVoice]

    /// Every phrase above, for the test that compares this table with the String Catalogs.
    static var all: [Phrase] {
        distinctiveLines + marketing + marketingPair + earlierReviewHeadings + [earlierReviewNote]
            + [overviewHeading] + overviewCopy + homeHeadings + homeFooters
            + [homeReviewPrompt, recordingBadge, playbackNow, playbackPause, playbackPaused, playbackContinue]
            + pairs.flatMap { $0 } + labelGroups.flatMap { $0 } + recognitionScreens.flatMap { $0.copy + $0.controls }
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
        let present = frame.sentences(among: recognitionScreens.flatMap(\.copy))
        return recognitionScreens.contains { screen in
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
    /// holds the date, or when it stands alone on its line (at most its dot, read as a zero
    /// or an "o", before it). Nothing else in the product prints these words: not the Live Activity, not a
    /// notification, not the system's recording indicator. A line holding only the badge can
    /// therefore only be MORE's home, whatever the other lines of the frame say. After other
    /// words ("READ MORE · Recording"), or as "more recording" in any other case or place,
    /// it identifies nothing.
    static func showsRecordingBadge(_ frame: Frame) -> Bool {
        let before = recordingBadge.wordsBeforeLineEnd(in: frame, withoutClockTimes: true).map(withoutSymbols)
        if before.contains(where: isHomeDate) { return true }
        // Alone on its line: nothing before it, or only what the badge's own dot is read as.
        // Any other word, even one letter ("A MORE Recording"), makes it ordinary text.
        return recordingBadge.wordsBeforeLineEnd(in: frame).contains { $0.isEmpty || $0 == ["0"] || $0 == ["o"] }
    }

    /// The words of a line without what the two symbols at its end were read as: the badge's
    /// own dot, a zero or an "o", and before it the chevron beside the date, a "v". One of
    /// each at most; any other letter or word is another app's ("Tue, Oct 13 A").
    private static func withoutSymbols(_ words: [String]) -> [String] {
        var words = words
        if let last = words.last, last == "0" || last == "o" { words.removeLast() }
        if words.last == "v" { words.removeLast() }
        return words
    }

    /// The home's date row, as the home prints it: `weekday(.abbreviated).month(.abbreviated).day()`
    /// in the app's language, English or French, with whatever region the phone is set to.
    /// That is exactly three words once punctuation is set aside, since Vision may drop it: a
    /// weekday abbreviation, first or last, and beside it a day with its month, in either
    /// order ("Tue, Oct 13", "Tue 13 Oct", « mar. 13 oct. »). A few regions print the month as
    /// a number ("Tue 13. 10.", « 10-13, mar. »). Nothing else is a date here: not a count
    /// beside short words ("Save 1"), not an hour ("9 AM", "Tue 09:30"), not a duration
    /// (« 5 min »). An hour written with a dot or read without its colon ("Tue 9.05") is the
    /// numeric date some regions print, and still reads as one.
    ///
    /// The words arrive lowercase and without accents. A real date in this form on another
    /// app's line that also ends with the badge's capitals is still read as the home.
    private static func isHomeDate(_ words: [String]) -> Bool {
        guard words.count == 3 else { return false }
        return homeDateNames.contains { language in
            let weekdayFirst = language.weekdays.contains(words[0])
            guard weekdayFirst || language.weekdays.contains(words[2]) else { return false }
            let rest = Array(weekdayFirst ? words[1...] : words[..<2])
            let numbers = rest.map { $0.count <= 2 && $0.allSatisfy { ("0"..."9").contains($0) } ? Int($0) : nil }
            func fits(day: Int?, longest: Int?) -> Bool {
                guard let day, let longest else { return false }
                return (1...longest).contains(day)
            }
            if fits(day: numbers[0], longest: language.months[rest[1]])
                || fits(day: numbers[1], longest: language.months[rest[0]]) { return true }
            // The month as a number, in the two orders printed: after the weekday, the day as
            // written (never "09") then the month; before it, the month then the day.
            guard let month = numbers[weekdayFirst ? 1 : 0], (1...12).contains(month),
                  !(weekdayFirst && rest[0].hasPrefix("0")) else { return false }
            return fits(day: numbers[weekdayFirst ? 0 : 1], longest: monthLengths[month - 1])
        }
    }

    private static let monthLengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

    /// Abbreviations as Foundation prints them for English and French in every region (see the
    /// test that formats each day of a leap year for all of them), with each month's longest
    /// length. « jui » is June or July, depending on the region.
    private static let homeDateNames: [(weekdays: Set<String>, months: [String: Int])] = [
        (["mon", "tue", "wed", "thu", "fri", "sat", "sun"],
         ["jan": 31, "feb": 29, "mar": 31, "apr": 30, "may": 31, "jun": 30, "jul": 31, "aug": 31,
          "sep": 30, "sept": 30, "oct": 31, "nov": 30, "dec": 31]),
        (["lun", "mar", "mer", "jeu", "ven", "sam", "dim"],
         ["janv": 31, "jan": 31, "fevr": 29, "fev": 29, "mars": 31, "mar": 31, "avr": 30, "mai": 31,
          "juin": 30, "jui": 31, "juil": 31, "juill": 31, "aout": 31, "aou": 31, "sept": 30, "sep": 30,
          "oct": 31, "nov": 30, "dec": 31])
    ]

    static func containsMarketing(_ frame: Frame) -> Bool {
        marketing.contains { $0.isWithin(frame) } || marketingPair.allSatisfy { $0.isWithin(frame) }
    }
}
