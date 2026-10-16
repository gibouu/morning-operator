import SwiftUI
import MorningApple
import MorningCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum NativeConnectionFocus: Equatable {
    case reminders, shortcuts
}

struct NativeConnectionsView: View {
    @Bindable var store: MorningStore
    @Bindable var service: NativeConnectionsService
    var focus: NativeConnectionFocus? = nil
    @ViewState<Bool> private var showingBriefing = false
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(eyebrow: text("For your morning", "Pour votre matin"),
                    title: pageTitle, subtitle: pageSubtitle)
                if focus == nil { calendarCard }
                if focus != .shortcuts { remindersCard }
                if focus != .reminders { shortcutsSection }
            }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(MorningPaper(showsSun: false))
        .foregroundStyle(MorningStyle.ink)
        .disabled(store.privacyBlocksWork)
        .morningSheet(isPresented: $showingBriefing) { MorningBriefingView(store: store) }
        .task { service.refreshAccess() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { service.refreshAccess() } }
        .onChange(of: store.dataGeneration) { _, _ in showingBriefing = false }
        .id(store.dataGeneration)
    }

    private var pageTitle: String {
        if focus == .reminders { return text("Reminders", "Rappels") }
        if focus == .shortcuts { return text("Your shortcuts", "Vos raccourcis") }
        return text("Your everyday apps.", "Vos apps au quotidien.")
    }

    private var pageSubtitle: String {
        if focus == .reminders {
            return text("Keep the next few days in view, one reminder at a time.",
                        "Retrouvez ce qui vous attend dans les prochains jours.")
        }
        if focus == .shortcuts {
            return text("Messages, Notes and your other apps, with the shortcuts you choose.",
                        "Messages, Notes et vos autres apps, avec les raccourcis que vous choisissez.")
        }
        return text("A few familiar tools to prepare your day.", "Vos outils habituels pour préparer la journée.")
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("Calendar, weather & sleep", "Calendrier, météo et sommeil")).font(MorningTheme.Typography.heading)
            Text(text("Choose calendars, weather and optional recorded sleep for your day recap.",
                      "Choisissez vos calendriers, la météo et le sommeil enregistré facultatif pour votre récapitulatif."))
                .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(text("Choose sources", "Choisir les sources")) { showingBriefing = true }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("native.calendar")
            Button(text("Add a reminder or calendar event", "Ajouter un rappel ou un événement")) { store.openCapture() }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("native.capture")
        }.nativeConnectionCard()
    }

    @ViewBuilder private var shortcutsSection: some View {
        if focus == nil { Text(text("Your shortcuts", "Vos raccourcis")).font(MorningTheme.Typography.title) }
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(text("A little setup, just once", "Une petite préparation, une seule fois"), systemImage: "arrow.triangle.branch")
                    .font(MorningTheme.Typography.heading)
                Text(text("A shortcut is a small set of actions you create in Apple's Shortcuts app. MORE can open it at the right moment in your morning.",
                          "Un raccourci est une petite suite d’actions que vous créez dans l’app Raccourcis d’Apple. MORE peut le lancer au bon moment dans votre matin."))
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Text(text("Choose an example below and follow its guide. Notes is a good first try.",
                          "Choisissez un exemple ci-dessous et suivez son guide. Notes est un bon premier essai."))
                    .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(text("How it works", "Comment ça marche")) {
                    Text(text("MORE opens the shortcut you've prepared. It doesn't install it or inspect its actions. Review those actions in Shortcuts before running it. A returned result confirms the shortcut finished, not that a change in another app was verified.",
                              "MORE ouvre le raccourci que vous avez préparé. Il ne l’installe pas et ne lit pas ses actions. Vérifiez-les dans Raccourcis avant de le lancer. Un retour reçu confirme la fin du raccourci, pas une modification vérifiée dans une autre app."))
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).tint(MorningStyle.accent)
            }
        }
        if let pending = service.pendingShortcut {
            VStack(alignment: .leading, spacing: 12) {
                Text(text("Waiting for \(pending.operation.connectionDisplayName(for: locale))…", "En attente de \(pending.operation.connectionDisplayName(for: locale))…"))
                    .font(.raleway(.headline)).fixedSize(horizontal: false, vertical: true)
                Button(text("Stop waiting", "Arrêter l’attente")) { service.stopWaitingForShortcut() }
                    .buttonStyle(SecondaryButtonStyle())
            }.nativeConnectionCard().accessibilityIdentifier("native.shortcutWaiting")
        }
        if let message = service.shortcutMessage {
            Text(message).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("native.shortcutMessage")
        }
        ForEach(NativeShortcutOperation.configurable) { operation in
            NativeShortcutCard(operation: operation, service: service,
                canAddToRoutine: !store.sessionActive && !store.busy) { name, input in
                let target = RoutineStepTarget.shortcut(name: name, input: input)
                do { try target.validateIntegration() }
                catch { store.notice = error.moreDescription; return false }
                return store.addConnectedStep(RoutineStep(title: name,
                    detail: text("Native action through your shortcut", "Action native avec votre raccourci"),
                    durationMinutes: 1, target: target))
            }
        }
    }

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(text("The next seven days", "Les sept prochains jours")).font(MorningTheme.Typography.heading)
            if !service.hasReminderAccess {
                Text(text("Allow access to Reminders to display them here and mark them complete.",
                          "L’accès à Rappels permet de les afficher ici et de les terminer."))
                    .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(service.hasReminderAccess ? text("Show my reminders", "Afficher mes rappels") : text("Allow & show reminders", "Autoriser et afficher")) {
                service.readUpcomingReminders()
            }.buttonStyle(PrimaryButtonStyle()).disabled(service.remindersBusy)
                .accessibilityIdentifier("native.remindersRead")
            #if canImport(UIKit)
            if service.reminderAuthorization == .denied || service.reminderAuthorization == .restricted,
               let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                Link(text("Open iPhone Settings", "Ouvrir les réglages de l’iPhone"), destination: settingsURL)
                    .buttonStyle(SecondaryButtonStyle())
                    .accessibilityIdentifier("native.remindersSettings")
            }
            #endif
            if service.remindersBusy { ProgressView(text("Reading reminders…", "Lecture des rappels…")) }
            if let readAt = service.remindersReadAt {
                Text(text("Read at \(readAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))", "Lus à \(readAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(AppLanguage.locale)))"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                if service.reminders.isEmpty {
                    Text(text("No dated reminders to finish in the next seven days.",
                              "Aucun rappel daté à terminer dans les sept prochains jours."))
                        .font(.raleway(.subheadline)).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("native.remindersEmpty")
                }
            }
            ForEach(service.reminders) { reminder in
                VStack(alignment: .leading, spacing: 8) {
                    Text(reminder.title).font(.raleway(.headline)).fixedSize(horizontal: false, vertical: true)
                    Text(reminder.listTitle).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if let due = reminder.dueDate { Text(due.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLanguage.locale))).font(.raleway(.caption)) }
                    Button(text("Mark complete", "Marquer comme terminé")) { service.completeReminder(reminder) }
                        .buttonStyle(SecondaryButtonStyle()).disabled(service.remindersBusy)
                        .accessibilityLabel(text("Mark \(reminder.title) complete", "Terminer \(reminder.title)"))
                }.padding(.vertical, 8)
            }
            if let message = service.reminderMessage {
                Text(message).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("native.remindersMessage")
            }
            DisclosureGroup(text("Which reminders appear here?", "Quels rappels sont affichés ?")) {
                Text(text("Up to 50 incomplete reminders dated within the next seven days. Undated and overdue reminders aren't included. This reads the reminders available on your iPhone.",
                          "Jusqu’à 50 rappels incomplets et datés dans les sept prochains jours. Les rappels sans date ou en retard ne sont pas inclus. MORE lit les rappels disponibles sur votre iPhone."))
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).tint(MorningStyle.accent)
        }.nativeConnectionCard()
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}

private struct NativeShortcutCard: View {
    let operation: NativeShortcutOperation
    @Bindable var service: NativeConnectionsService
    let canAddToRoutine: Bool
    let onAddToRoutine: (String, String) -> Bool
    @ViewState<String> private var name = ""
    @ViewState<String> private var input = ""
    @ViewState<String?> private var issue = nil
    @ViewState<Bool> private var showingGuide = false
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL
    private var example: NativeShortcutExample {
        NativeShortcutExample(operation: operation, french: locale.language.languageCode?.identifier == "fr")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(operation == .custom ? text("Other shortcut", "Autre raccourci") : operation.connectionDisplayName(for: locale))
                .font(MorningTheme.Typography.heading)
            Text(example.title).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button(text("Show me the steps", "Me guider pas à pas")) { showingGuide = true }
                .buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("native.\(operation.rawValue).guide")
            Text(text("Exact name in Shortcuts", "Nom exact dans Raccourcis")).font(.raleway(.subheadline, .semibold))
            TextField(text("Paste the shortcut name", "Collez le nom du raccourci"), text: $name)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .nativeConnectionInput().accessibilityIdentifier("native.\(operation.rawValue).name")
            Button(text("Save without running", "Enregistrer sans lancer")) {
                do { try service.setShortcutName(name, for: operation); issue = nil }
                catch { issue = error.moreDescription }
            }.buttonStyle(SecondaryButtonStyle()).disabled(name == (service.shortcutNames[operation] ?? ""))
            DisclosureGroup(text("Send text to the shortcut (optional)", "Transmettre du texte au raccourci (facultatif)")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text("This is text your shortcut can use, such as the contents of a note. Its actions must use the Shortcuts variable “Shortcut Input” to receive it. Leave it empty for the example in this guide.",
                              "C’est du texte que votre raccourci peut utiliser, comme le contenu d’une note. Ses actions doivent utiliser la variable « Entrée du raccourci » pour le recevoir. Laissez ce champ vide pour l’exemple de ce guide."))
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                    TextField(text("Text for your shortcut", "Texte pour votre raccourci"), text: $input, axis: .vertical)
                        .lineLimit(2...5).nativeConnectionInput()
                        .accessibilityIdentifier("native.\(operation.rawValue).input")
                    Text(text("For a note: in Shortcuts, replace the fixed note text with “Shortcut Input”. The text you enter here will then become the note's contents.",
                              "Pour une note : dans Raccourcis, remplacez le texte fixe de la note par « Entrée du raccourci ». Le texte saisi ici deviendra alors le contenu de la note."))
                        .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 8)
            }.tint(MorningStyle.accent)
            Text(text("Testing really runs the actions you prepared in Shortcuts.", "Tester lance réellement les actions que vous avez préparées dans Raccourcis."))
                .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
            Button(text("Test this shortcut", "Tester ce raccourci")) { run() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || service.pendingShortcut != nil)
                .accessibilityIdentifier("native.\(operation.rawValue).run")
            Button(text("Add to my routine", "Ajouter à ma routine")) {
                do {
                    try service.setShortcutName(name, for: operation)
                    if onAddToRoutine(name, input) {
                        issue = text("Added to your draft. Review and approve the routine before starting.",
                                     "Ajouté au brouillon. Vérifiez et approuvez la routine avant de démarrer.")
                    }
                } catch { issue = error.moreDescription }
            }.buttonStyle(SecondaryButtonStyle())
                .disabled(!canAddToRoutine || !ShortcutBridge.isValidName(name) || input.utf8.count > ShortcutBridge.inputByteLimit)
                .accessibilityIdentifier("native.\(operation.rawValue).addToRoutine")
            Text(text("Adding saves this step in your draft. Review and approve your routine before starting it.",
                      "L’ajout enregistre cette étape dans votre brouillon. Relisez et approuvez votre routine avant de la démarrer."))
                .font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).fixedSize(horizontal: false, vertical: true)
            if let outcome = service.shortcutOutcomes[operation] {
                Text(outcome.status == .returned ? text("Shortcut returned", "Retour du raccourci reçu") :
                     outcome.status == .cancelled ? text("Shortcut cancelled", "Raccourci annulé") : text("Shortcut failed", "Échec du raccourci"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if !outcome.text.isEmpty {
                    DisclosureGroup(text("See the returned text", "Voir le texte reçu")) {
                        Text(outcome.text).font(.raleway(.subheadline)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                    }.font(.raleway(.footnote)).tint(MorningStyle.accent)
                } else if outcome.status == .returned {
                    Text(text("No text was returned.", "Aucun texte n’a été renvoyé.")).font(.raleway(.caption))
                }
            } else if service.shortcutNames[operation] != nil {
                Text(text("Name saved · no result received yet", "Nom enregistré · aucun résultat reçu pour le moment"))
                    .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let issue {
                Text(issue).font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup(text("Return a result to MORE", "Renvoyer un résultat à MORE")) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(text("You can finish with a Text action in Shortcuts, such as “Test finished”, to return a short message to MORE. A received message confirms the shortcut returned; check the actual result in the app concerned. Returning text is optional.",
                              "Vous pouvez terminer par une action Texte dans Raccourcis, par exemple « Test terminé », pour renvoyer un court message à MORE. Un message reçu confirme le retour du raccourci ; vérifiez le résultat réel dans l’app concernée. Ce retour de texte est facultatif."))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(text("MORE accepts up to 1,024 bytes of input and 8,192 bytes of returned text.",
                              "MORE accepte jusqu’à 1 024 octets en entrée et 8 192 octets de texte en retour."))
                }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).padding(.top, 8)
            }.tint(MorningStyle.accent)
        }.nativeConnectionCard()
        .onAppear { name = service.shortcutNames[operation] ?? "" }
        .morningSheet(isPresented: $showingGuide) { NativeShortcutGuide(example: example) }
    }

    private func run() {
        do {
            try service.setShortcutName(name, for: operation)
            let url = try service.launchShortcut(name: name, input: input, operation: operation)
            let requestID = service.pendingShortcut?.id
            issue = nil
            openURL(url) { accepted in if !accepted { service.shortcutCouldNotOpen(requestID: requestID) } }
        } catch { issue = error.moreDescription }
    }
    private func text(_ english: String, _ french: String) -> String { locale.language.languageCode?.identifier == "fr" ? french : english }
}

private struct NativeShortcutExample {
    let operation: NativeShortcutOperation
    let french: Bool

    var title: String {
        switch operation {
        case .messages: text("First example: open Messages", "Premier exemple : ouvrir Messages")
        case .mail: text("First example: open Mail", "Premier exemple : ouvrir Mail")
        case .notes: text("First example: create a morning note", "Premier exemple : créer une note du matin")
        case .clock: text("First example: start a 30-second timer", "Premier exemple : lancer un minuteur de 30 secondes")
        case .custom: text("First example: open an app of your choice", "Premier exemple : ouvrir l’app de votre choix")
        }
    }

    var suggestedName: String {
        switch operation {
        case .messages: "MORE Messages"
        case .mail: "MORE Mail"
        case .notes: "MORE Notes"
        case .clock: text("MORE Clock", "MORE Horloge")
        case .custom: text("MORE Personal", "MORE Personnel")
        }
    }

    var actionInstruction: String {
        switch operation {
        case .messages:
            text("Search for “Open App”, add that action, then tap its app field and choose Messages.",
                 "Recherchez « Ouvrir l’app », ajoutez cette action, puis touchez son champ App et choisissez Messages.")
        case .mail:
            text("Search for “Open App”, add that action, then tap its app field and choose Mail.",
                 "Recherchez « Ouvrir l’app », ajoutez cette action, puis touchez son champ App et choisissez Mail.")
        case .notes:
            text("Search for “Create Note” and add the Notes action. Enter “My morning idea” as its text and choose a Notes folder if asked.",
                 "Recherchez « Créer une note » et ajoutez l’action de Notes. Saisissez « Mon idée du matin » comme texte et choisissez un dossier Notes si cela vous est demandé.")
        case .clock:
            text("Search for “timer”, add the Clock action that starts a timer, then set it to 30 seconds.",
                 "Recherchez « minuteur », ajoutez l’action Horloge qui démarre un minuteur, puis réglez-la sur 30 secondes.")
        case .custom:
            text("Search for “Open App”, add that action, then choose an app installed on your iPhone. You can later replace this example with actions you have reviewed in Shortcuts.",
                 "Recherchez « Ouvrir l’app », ajoutez cette action, puis choisissez une app installée sur votre iPhone. Vous pourrez ensuite remplacer cet exemple par des actions que vous avez vérifiées dans Raccourcis.")
        }
    }

    var effect: String {
        switch operation {
        case .messages:
            text("This example only opens Messages. You choose the conversation and write the message yourself; it does not read or send messages.",
                 "Cet exemple ouvre seulement Messages. Vous choisissez la conversation et rédigez le message vous-même ; il ne lit ni n’envoie de messages.")
        case .mail:
            text("This example only opens Mail. You choose the email or compose a message yourself; it does not read or send emails.",
                 "Cet exemple ouvre seulement Mail. Vous choisissez l’e-mail ou rédigez un message vous-même ; il ne lit ni n’envoie d’e-mails.")
        case .notes:
            text("Check Notes for the new note, and confirm any preview you chose to keep. Each run can create another note.",
                 "Vérifiez la nouvelle note dans Notes et validez l’éventuel aperçu que vous avez choisi de garder. Chaque lancement peut créer une autre note.")
        case .clock:
            text("A real timer starts and will ring after 30 seconds. Check it in Clock and stop it there if needed.",
                 "Un vrai minuteur démarre et sonnera après 30 secondes. Vérifiez-le dans Horloge et arrêtez-le dans cette app si nécessaire.")
        case .custom:
            text("The selected app opens. This example does not perform actions inside that app.",
                 "L’app choisie s’ouvre. Cet exemple n’effectue pas d’action à l’intérieur de cette app.")
        }
    }

    private func text(_ english: String, _ french: String) -> String { self.french ? french : english }
}

private struct NativeShortcutGuide: View {
    let example: NativeShortcutExample
    @ViewState<Bool> private var copiedName = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    PageHeading(eyebrow: text("With Apple Shortcuts", "Avec Raccourcis d’Apple"),
                        title: text("Let's prepare it.", "On le prépare ensemble."),
                        subtitle: example.title)
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("1. Create and name it", "1. Créez-le et donnez-lui un nom"))
                                .font(MorningTheme.Typography.heading)
                            guideText(text("Open Shortcuts on your iPhone, tap +, then rename the new shortcut. You can use this exact name:",
                                           "Ouvrez Raccourcis sur votre iPhone, touchez +, puis renommez le nouveau raccourci. Vous pouvez utiliser ce nom exact :"))
                            Text(example.suggestedName).font(.body.monospaced()).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(copiedName ? text("Name copied", "Nom copié") : text("Copy this name", "Copier ce nom")) {
                                copyName()
                            }.buttonStyle(SecondaryButtonStyle()).accessibilityIdentifier("native.guide.copyName")
                            if let url = URL(string: "shortcuts://") {
                                Link(text("Open Shortcuts", "Ouvrir Raccourcis"), destination: url)
                                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("native.guide.openShortcuts")
                            }
                            guideText(text("Already have a shortcut? Keep its name and use that exact name in MORE.",
                                           "Vous avez déjà un raccourci ? Gardez son nom et utilisez ce nom exact dans MORE."))
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("2. Add its action", "2. Ajoutez son action"))
                                .font(MorningTheme.Typography.heading)
                            guideText(example.actionInstruction)
                            guideText(text("Action names can vary with iOS and the apps installed. If the action is unavailable, choose another example.",
                                           "Le nom des actions peut varier selon iOS et les apps installées. Si l’action n’est pas disponible, choisissez un autre exemple."))
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("3. Try it in Shortcuts", "3. Essayez-le dans Raccourcis"))
                                .font(MorningTheme.Typography.heading)
                            guideText(text("Read its actions, then tap the play button. Apple may ask for access or a confirmation: choose what you want to allow.",
                                           "Relisez ses actions, puis touchez le bouton de lecture. Apple peut demander un accès ou une confirmation : choisissez ce que vous souhaitez autoriser."))
                            guideText(example.effect)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(text("4. Return to MORE", "4. Revenez dans MORE"))
                                .font(MorningTheme.Typography.heading)
                            guideText(text("Paste the exact name into this app's card. Save without running remembers only the name; it does not check whether the shortcut exists.",
                                           "Collez le nom exact dans la carte de cette app. Enregistrer sans lancer mémorise uniquement le nom ; cela ne vérifie pas que le raccourci existe."))
                            guideText(text("Leave optional text empty for this example. Test this shortcut runs it again, so its real effect can happen again. Check the result in the app concerned, then return to MORE.",
                                           "Laissez le texte facultatif vide pour cet exemple. Tester ce raccourci le relance : son effet réel peut donc se reproduire. Vérifiez le résultat dans l’app concernée, puis revenez dans MORE."))
                            guideText(text("Add to my routine saves the name and optional text in your draft. It does not run the shortcut immediately. Review and approve the routine, then start it to run this step at the planned moment.",
                                           "Ajouter à ma routine enregistre le nom et le texte facultatif dans votre brouillon. Cela ne lance pas le raccourci immédiatement. Relisez et approuvez la routine, puis démarrez-la pour exécuter cette étape au moment prévu."))
                        }
                    }
                    DisclosureGroup(text("What MORE can confirm", "Ce que MORE peut confirmer")) {
                        VStack(alignment: .leading, spacing: 10) {
                            guideText(text("MORE opens a shortcut by its name. It cannot install it or inspect its actions. Keep any confirmations you need in Shortcuts. A returned message confirms the return to MORE; it does not verify changes in another app.",
                                           "MORE ouvre un raccourci à partir de son nom. Il ne peut ni l’installer ni lire ses actions. Gardez dans Raccourcis les confirmations dont vous avez besoin. Un message reçu confirme le retour à MORE ; il ne vérifie pas les changements dans une autre app."))
                            if let url = URL(string: "https://support.apple.com/fr-fr/guide/shortcuts/apd84c576f8c/ios") {
                                Link(text("Apple's shortcut creation guide", "Le guide de création d’Apple"), destination: url)
                            }
                        }.padding(.top, 8)
                    }.font(.raleway(.footnote)).foregroundStyle(MorningStyle.muted).tint(MorningStyle.accent)
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(MorningPaper(showsSun: false))
            .foregroundStyle(MorningStyle.ink)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(text("Done", "Terminé")) { dismiss() }
                }
            }
        }
    }

    private func guideText(_ value: String) -> some View {
        Text(value).font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func copyName() {
        #if canImport(UIKit)
        UIPasteboard.general.string = example.suggestedName
        copiedName = true
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        copiedName = NSPasteboard.general.setString(example.suggestedName, forType: .string)
        #endif
    }

    private func text(_ english: String, _ french: String) -> String { example.french ? french : english }
}

private extension NativeShortcutOperation {
    func connectionDisplayName(for locale: Locale) -> String {
        if self == .clock, locale.language.languageCode?.identifier == "fr" { return "Horloge" }
        return displayName
    }
}

private extension View {
    func nativeConnectionCard() -> some View {
        Card { self }
    }

    func nativeConnectionInput() -> some View {
        textFieldStyle(.plain).padding(12)
            .background(MorningStyle.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(MorningStyle.line, lineWidth: 1))
    }
}
