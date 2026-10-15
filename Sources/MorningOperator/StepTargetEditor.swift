import SwiftUI
import MorningCore

struct StepTargetEditor: View {
    @Binding var target: RoutineStepTarget?
    private var selectedApp: StepApp? {
        guard case let .externalApp(app, _) = target else { return nil }; return app
    }
    private var detail: String {
        guard case let .externalApp(_, detail) = target else { return "" }; return detail ?? ""
    }
    private var selectedChoice: String {
        switch target {
        case let .externalApp(app, _): "app.\(app.rawValue)"
        case let .inAppWeb(url): WebMorningSite(url: url).map { "web.\($0.rawValue)" } ?? "web.saved"
        case nil: "none"
        }
    }
    private func select(_ choice: String) {
        if choice.hasPrefix("app."), let app = StepApp(rawValue: String(choice.dropFirst(4))) {
            target = .externalApp(app, detail: nil)
        } else if choice.hasPrefix("web."), let site = WebMorningSite(rawValue: String(choice.dropFirst(4))) {
            target = .inAppWeb(site: site.table.startURL)
        } else if choice == "none" { target = nil }
    }
    var body: some View {
        Section {
            Picker("Open", selection: Binding(get: { selectedChoice }, set: select)) {
                Text("None").tag("none")
                Section("In MORE") {
                    ForEach(WebMorningSite.allCases) { site in Text(site.displayName).tag("web.\(site.rawValue)") }
                    if selectedChoice == "web.saved" { Text("Saved page").tag("web.saved") }
                }
                Section("Another app") {
                    ForEach(StepApp.allCases, id: \.self) { app in Text(app.displayName).tag("app.\(app.rawValue)") }
                }
            }.accessibilityIdentifier("step.targetApp")
            if let app = selectedApp, app.detailKind != .none {
                TextField(prompt(app.detailKind), text: Binding(get: { detail }, set: { target = .externalApp(app, detail: $0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("step.targetDetail")
            }
        } header: { Text("During this moment") } footer: {
            Text("One timer, in MORE or another app. Choose Next when you're ready.")
        }
    }
    private func prompt(_ kind: StepAppDetailKind) -> String {
        switch kind {
        case .none: ""
        case .phoneNumber: String(localized: "Phone number (optional)")
        case .messageID: String(localized: "Mail Message-ID (optional)")
        case .username: String(localized: "Username (optional)")
        case .place: String(localized: "Place (optional)")
        case .webAddress: String(localized: "Web address")
        }
    }
}
