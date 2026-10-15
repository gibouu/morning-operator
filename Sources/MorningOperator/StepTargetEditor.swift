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
    var body: some View {
        Section {
            Picker("Open an app", selection: Binding(get: { selectedApp }, set: { app in
                target = app.map { .externalApp($0, detail: nil) }
            })) {
                Text("None").tag(Optional<StepApp>.none)
                ForEach(StepApp.allCases, id: \.self) { app in Text(app.displayName).tag(Optional(app)) }
            }.accessibilityIdentifier("step.targetApp")
            if let app = selectedApp, app.detailKind != .none {
                TextField(prompt(app.detailKind), text: Binding(get: { detail }, set: { target = .externalApp(app, detail: $0) }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("step.targetDetail")
            }
        } header: { Text("During this moment") } footer: {
            Text("MORE opens this app and keeps your time budget. Choose Next when you're ready.")
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
