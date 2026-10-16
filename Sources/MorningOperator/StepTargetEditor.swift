import SwiftUI
import MorningCore
import MorningApple

struct StepTargetEditor: View {
    @Binding var target: RoutineStepTarget?
    var reviewedDetail: String? = nil
    private var selectedApp: StepApp? {
        guard case let .externalApp(app, _) = target else { return nil }; return app
    }
    private var detail: String {
        guard case let .externalApp(_, detail) = target else { return "" }; return detail ?? ""
    }
    private var selectedChoice: String {
        switch target?.routineExecutionTarget {
        case let .externalApp(app, _): "app.\(app.rawValue)"
        case let .inAppWeb(url): WebMorningSite(url: url).map { "web.\($0.rawValue)" } ?? "web.saved"
        case .shortcut: "shortcut"
        case .connectedAPI, .googleCalendarDay, .calendlyDay, .outlookInbox: "api.saved"
        case nil: "none"
        }
    }
    private func select(_ choice: String) {
        if choice.hasPrefix("app."), let app = StepApp(rawValue: String(choice.dropFirst(4))) {
            target = .externalApp(app, detail: nil)
        } else if choice.hasPrefix("web."), let site = WebMorningSite(rawValue: String(choice.dropFirst(4))) {
            if case let .inAppWeb(url) = target?.routineExecutionTarget, WebMorningSite(url: url) == site { return }
            target = .inAppWeb(site: site.table.startURL)
        } else if choice == "shortcut" { target = .shortcut(name: "", input: "") }
        else if choice == "none" { target = nil }
    }
    var body: some View {
        Section {
            Picker("Open", selection: Binding(get: { selectedChoice }, set: select)) {
                Text("None").tag("none")
                Section("On this iPhone") {
                    Text("Run an installed Shortcut").tag("shortcut")
                }
                Section("In MORE") {
                    ForEach(WebMorningSite.allCases) { site in Text(site.displayName).tag("web.\(site.rawValue)") }
                    if selectedChoice == "web.saved" { Text("Saved page").tag("web.saved") }
                }
                Section("Another app") {
                    ForEach(StepApp.allCases.filter { $0 != .instagram }, id: \.self) { app in Text(app.displayName).tag("app.\(app.rawValue)") }
                }
                if selectedChoice == "api.saved" {
                    Section("From your accounts") { Text("Saved service action").tag("api.saved") }
                }
            }.accessibilityIdentifier("step.targetApp")
            if let app = selectedApp, app.detailKind != .none {
                TextField(prompt(app.detailKind), text: Binding(get: { detail }, set: { target = .externalApp(app, detail: $0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("step.targetDetail")
            }
            if case let .shortcut(name, input) = target {
                TextField("Installed shortcut name", text: Binding(get: { name }, set: { target = .shortcut(name: $0, input: input) }))
                    .autocorrectionDisabled().accessibilityIdentifier("step.shortcutName")
                TextField("Input (optional)", text: Binding(get: { input }, set: { target = .shortcut(name: name, input: $0) }), axis: .vertical)
                    .lineLimit(2...5)
                Text("Add and authorize the shortcut in Shortcuts first. Its name alone does not verify a connection.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            if case let .connectedAPI(service, _, _, _) = target, let target {
                Text(service.capitalized).font(.subheadline)
                if let details = RoutineConnectedReview.summary(for: target) {
                    if let reviewedDetail, !reviewedDetail.isEmpty, reviewedDetail != details {
                        Text(AppLanguage.isFrench ? "Description et compte enregistrés" : "Saved account and description")
                            .font(.caption).foregroundStyle(MorningStyle.muted)
                        Text(reviewedDetail).font(.subheadline).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(AppLanguage.isFrench ? "Détails que MORE utilisera" : "Details MORE will use")
                        .font(.caption).foregroundStyle(MorningStyle.muted)
                    Text(details).font(.subheadline).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(ConnectedActionReviewError.unreadable.moreDescription)
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                }
            }
            if case let .googleCalendarDay(calendar) = target {
                Text("Google Calendar").font(.subheadline)
                Text(calendar.sourceLabel()).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let target, let details = RoutineConnectedReview.summary(for: target) {
                    Text(details).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Text(AppLanguage.isFrench ? "Pour choisir un autre calendrier, ajoutez un moment depuis Apps et comptes."
                     : "To choose another calendar, add a moment from Apps & accounts.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            if case let .calendlyDay(account) = target {
                Text("Calendly").font(.subheadline)
                Text(account.userName).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let target, let details = RoutineConnectedReview.summary(for: target) {
                    Text(details).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Text(AppLanguage.isFrench ? "Pour choisir un autre compte, ajoutez un moment depuis Apps et comptes."
                     : "To choose another account, add a moment from Apps & accounts.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            if case let .outlookInbox(account) = target {
                Text("Outlook").font(.subheadline)
                Text(account.sourceLabel()).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                if let target, let details = RoutineConnectedReview.summary(for: target) {
                    Text(details).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                }
                Text(AppLanguage.isFrench ? "Pour choisir une autre boîte de réception, ajoutez un moment depuis Apps et comptes."
                     : "To choose another Inbox, add a moment from Apps & accounts.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            if target == nil {
                Text("Choose a website or an app above.")
                    .font(.footnote).foregroundStyle(MorningStyle.muted)
            }
            Text(AppLanguage.isFrench ? "Ce choix s’applique à ce moment. Appuyez sur Enregistrer pour conserver les modifications."
                 : "This choice applies to this moment. Tap Save to keep your changes.")
                .font(.footnote).foregroundStyle(MorningStyle.muted)
        } header: { Text("During this moment") } footer: {
            switch target?.routineExecutionTarget {
            case .inAppWeb:
                Text(AppLanguage.isFrench ? "Choisissez aussi ce que MORE fera dans la page. Si nécessaire, MORE vous demandera de vous connecter à la première ouverture, puis gardera cette session dans son navigateur."
                     : "Also choose what MORE will do in the page. When needed, MORE asks you to sign in the first time it opens, then keeps that session in its browser.")
            case .externalApp:
                Text(AppLanguage.isFrench ? "Cette application peut nécessiter vos gestes."
                     : "This app may still need your actions.")
            default:
                EmptyView()
            }
        }
    }
    private func prompt(_ kind: StepAppDetailKind) -> String {
        switch kind {
        case .none: ""
        case .phoneNumber: AppLanguage.localized("Phone number (optional)")
        case .messageID: AppLanguage.localized("Mail Message-ID (optional)")
        case .username: AppLanguage.localized("Username (optional)")
        case .place: AppLanguage.localized("Place (optional)")
        case .webAddress: AppLanguage.localized("Web address")
        }
    }
}

/// Presentation only: a configured Slack read has one fixed operation. Its
/// saved names describe the owner's choice; execution still verifies IDs and
/// fresh provider identity, then reviews the actual destination before sending.
enum RoutineConnectedReview {
    static func summary(for target: RoutineStepTarget) -> String? {
        if case let .googleCalendarDay(calendar) = target {
            return AppLanguage.isFrench
                ? "Google Calendar : lire « \(calendar.sourceLabel(french: true)) » pour le jour courant, dans le fuseau de cet iPhone. Les dates sont recalculées à chaque matin et à chaque actualisation. Au plus 25 événements ; toute lecture partielle est annoncée. Aucune modification du calendrier."
                : "Google Calendar: read “\(calendar.sourceLabel(french: false))” for today in this iPhone’s time zone. Dates are recalculated each morning and on refresh. Up to 25 events; a partial reading is disclosed. No calendar changes."
        }
        if case let .calendlyDay(account) = target {
            return AppLanguage.isFrench
                ? "Calendly : lire les rendez-vous de « \(account.userName) » qui commencent le jour courant, dans le fuseau de cet iPhone. Les dates sont recalculées à chaque matin et à chaque actualisation. Au plus 25 rendez-vous ; toute lecture partielle est annoncée. Aucun rendez-vous n’est créé ou annulé."
                : "Calendly: read bookings for “\(account.userName)” starting today in this iPhone’s time zone. Dates are recalculated each morning and on refresh. Up to 25 bookings; a partial reading is disclosed. No booking is created or cancelled."
        }
        if case let .outlookInbox(account) = target {
            return AppLanguage.isFrench
                ? "Outlook : présenter jusqu’à trois messages non lus de « \(account.sourceLabel()) », y compris des messages plus anciens. La boîte est vérifiée et relue à chaque matin ou actualisation. Les aperçus sont distincts du contenu du message, lu seulement à votre demande. Aucun message n’est envoyé, modifié ou marqué comme lu."
                : "Outlook: present up to three unread messages from “\(account.sourceLabel())”, including older mail. The Inbox is verified and read each morning or on refresh. Previews are distinct from message content, read only when you ask. No message is sent, changed or marked as read."
        }
        guard case let .connectedAPI(service, _, tool, json) = target else { return nil }
        if service == "slack", tool == "SLACK_FETCH_CONVERSATION_HISTORY",
           let arguments = try? ComposioJSONValue.parseObject(json),
           Set(arguments.keys) == ["channel", "limit"], arguments["limit"] == .number(3),
           let channel = arguments["channel"]?.stringValue,
           (3...80).contains(channel.count), channel.first.map({ "CG".contains($0) }) == true,
           channel.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) {
            return AppLanguage.isFrench
                ? "Slack : lire les trois derniers messages du canal choisi. Le compte et le canal enregistrés seront revérifiés pendant la lecture ; toute réponse demande une relecture et votre instruction d’envoi."
                : "Slack: read the latest three messages in the chosen channel. The saved account and channel will be checked again during reading; any reply requires review and your instruction to send."
        }
        return try? ConnectedActionReview.summary(argumentsJSON: json)
    }
}
