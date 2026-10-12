import Foundation

/// An optional manufactured plan for an explicit Try a sample action.
/// This factory never reads observations, migrates saved routines or connects apps.
/// DemoFixtures remains the separate, stable four-step test baseline.
public enum PhoneMorningSample {
    public static func routine(locale: Locale = .current) -> RoutineVersion {
        let french = locale.language.languageCode?.identifier == "fr"
        func text(_ english: String, _ frenchText: String) -> String {
            french ? frenchText : english
        }
        func manual(_ title: String, _ detail: String, _ kind: StepKind, _ minutes: Int) -> RoutineStep {
            RoutineStep(title: title, detail: detail, kind: kind, durationMinutes: minutes)
        }

        return RoutineVersion(
            // Retain the existing machine-recognized provenance marker in both languages.
            sourceLabel: text(
                "Demo fixture — synthetic phone morning, not observed personal data",
                "Demo fixture — exemple synthétique sur téléphone, aucune activité personnelle observée"
            ),
            steps: [
                manual(text("Calendar & weather", "Calendrier et météo"),
                    text("Check your calendar and the weather yourself. This sample has no live events or forecast. Configure your day briefing separately to add supported connected information.",
                         "Consultez votre calendrier et la météo. Cet exemple ne contient ni événements réels ni prévisions. Configurez séparément votre récap de la journée pour ajouter les informations connectées disponibles."),
                    .briefing, 5),
                manual("iMessage",
                    text("Open Messages and choose the conversations you want to catch up on. MORE is not connected to this inbox and does not read or reply for you.",
                         "Ouvrez Messages et choisissez les conversations que vous souhaitez retrouver. MORE n’est pas connecté à cette messagerie et ne lit ni ne répond à votre place."),
                    .messages, 5),
                manual("WhatsApp",
                    text("Open WhatsApp and check the conversations you choose. This is a manual moment; MORE has no access to your WhatsApp messages or unread count.",
                         "Ouvrez WhatsApp et consultez les conversations de votre choix. Ce moment est manuel : MORE n’a accès ni à vos messages WhatsApp ni à leur nombre de non-lus."),
                    .messages, 6),
                manual("WhatsApp Business",
                    text("Open WhatsApp Business if you use it, and choose which work conversations need your attention. This app is separate from WhatsApp and is not connected to MORE.",
                         "Ouvrez WhatsApp Business si vous l’utilisez et choisissez les échanges professionnels à consulter. Cette application est distincte de WhatsApp et n’est pas connectée à MORE."),
                    .messages, 5),
                manual("Messenger",
                    text("Open Messenger and catch up with the people you choose. MORE is not connected to Messenger; reading or replying remains your choice in that app.",
                         "Ouvrez Messenger et retrouvez les personnes de votre choix. MORE n’est pas connecté à Messenger : vous choisissez de lire ou de répondre dans cette application."),
                    .messages, 4),
                manual("Mail",
                    text("Open your mail app and review the messages you choose. MORE is not connected to your mailbox and cannot supply an unread count, summary or replies for this sample.",
                         "Ouvrez votre application de courrier et parcourez les messages de votre choix. MORE n’est pas connecté à votre boîte mail et ne fournit ici ni nombre de non-lus, ni résumé, ni réponses."),
                    .messages, 7),
                manual(text("Scroll a little", "Parcourir vos fils"),
                    text("Enjoy a feed you choose. Ten minutes is an editable suggestion, not a measured habit or an enforced limit. You decide when to move on.",
                         "Profitez d’un fil de votre choix. Ces dix minutes sont une proposition modifiable, pas une habitude mesurée ni une limite imposée. Vous choisissez quand passer à la suite."),
                    .entertainment, 10),
                manual(text("A thought for later", "Une pensée pour plus tard"),
                    text("If something comes to mind, keep a thought for later. You can write or speak it in the completion review and choose whether to save it. No reminder is created automatically.",
                         "Si une idée vous vient, gardez une pensée pour plus tard. Vous pourrez l’écrire ou la dicter dans le récap de fin et choisir de l’enregistrer. Aucun rappel n’est créé automatiquement."),
                    .custom, 3)
            ]
        )
    }
}
