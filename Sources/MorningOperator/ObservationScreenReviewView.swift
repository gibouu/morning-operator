import SwiftUI
import MorningCore
import MorningApple

/// Holds the source shown when editing began. The store checks it again at Save.
struct ObservationScreenReviewView: View {
    @Bindable var store: MorningStore
    let acquisition: ObservationAcquisition
    let sampleID: UUID
    @Environment(\.dismiss) private var dismiss
    @FocusState private var labelFocused: Bool
    @ViewState<String> private var label = ""
    @ViewState<String?> private var quote = nil
    @ViewState<String?> private var message = nil
    @ViewState<Bool> private var initialized = false

    private var frame: ObservationFrameEvidence? { acquisition.videoEvidence?.frames.first { $0.id == sampleID } }
    private var existing: ObservationFrameReview? { acquisition.frameReviews.first { $0.sampleID == sampleID } }
    private var blocked: Bool { store.busy || store.sessionActive || !store.storageIsAvailable }
    private var quotes: [String] {
        guard let frame, frame.canSupportIdentity else { return [] }
        var seen = Set<Data>()
        let original = acquisition.classification?.decisions.first { $0.sampleID == sampleID }?.evidenceQuote
        let lines = frame.text.split(whereSeparator: \.isNewline).map(String.init)
        return ([existing?.evidenceQuote, original].compactMap { $0 } + lines).compactMap { text in
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 320, value.utf8.count <= 1_280,
                  Data(frame.text.utf8).range(of: Data(value.utf8)) != nil,
                  seen.insert(Data(value.utf8)).inserted else { return nil }
            return value
        }.prefix(24).map { $0 }
    }

    var body: some View {
        NavigationStack {
            MorningForm {
                Section {
                    TextField("What was on this screen?", text: $label)
                        .focused($labelFocused)
                        .disabled(frame?.canSupportIdentity != true)
                        .accessibilityIdentifier("sampleLabel.text")
                    if let message {
                        Text(message).font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                            .accessibilityIdentifier("sampleLabel.message")
                    }
                } header: { Text("Your label") } footer: {
                    Text("Describe the screen, such as Calendar or Messages. This changes your review, not the original recording or the model's result.")
                }
                Section {
                    Button("Keep this screen unknown") { save(unknown: true) }
                        .disabled(blocked).accessibilityIdentifier("sampleLabel.unknown")
                    if existing != nil {
                        Button("Remove my correction", role: .destructive) {
                            labelFocused = false
                            if store.removeFrameReview(sampleID: sampleID, expected: acquisition) { dismiss() }
                            else { message = store.notice ?? AppLanguage.localized("The change could not be saved. Try again.") }
                        }.disabled(blocked).accessibilityIdentifier("sampleLabel.reset")
                    }
                } footer: {
                    Text(existing == nil
                         ? String(localized: "Unknown screens stay visible in your review and are left out of new activity suggestions.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
                         : String(localized: "Removing your correction restores the original interpretation, if one is available.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale))
                }
                Section {
                    if quotes.isEmpty {
                        Text("No short, complete excerpt is available to anchor a label. You can still keep this screen unknown.")
                            .font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                    }
                    ForEach(Array(quotes.enumerated()), id: \.offset) { index, text in
                        Button { quote = text; labelFocused = false } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text(text).foregroundStyle(.primary)
                                Spacer(minLength: 0)
                                if quote.map({ $0.utf8.elementsEqual(text.utf8) }) == true {
                                    Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                                }
                            }
                        }.accessibilityIdentifier("sampleLabel.quote.\(index)")
                    }
                } header: { Text("Original excerpt") } footer: {
                    Text("Choose the saved words that help you recognize this screen. Your label is your interpretation; it doesn't prove an app was opened or a message was read.")
                }
            }
            .scrollContentBackground(.hidden).background(MorningPaper(showsSun: false))
            .navigationTitle("Screen label").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.accessibilityIdentifier("sampleLabel.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save(unknown: false) }
                        .disabled(blocked || quote == nil || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("sampleLabel.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { labelFocused = false }.accessibilityIdentifier("sampleLabel.keyboardDone")
                }
            }
            .onAppear {
                guard !initialized else { return }
                initialized = true
                if let existing { label = existing.label ?? "" }
                else if case .identified(let context, _) = acquisition.classification?.decisions.first(where: { $0.sampleID == sampleID })?.evidence {
                    label = context.displayName
                }
                quote = quotes.first
            }
        }.tint(MorningStyle.accent)
    }

    private func save(unknown: Bool) {
        labelFocused = false
        do {
            let review = try ObservationFrameReview(sampleID: sampleID,
                label: unknown ? nil : label.trimmingCharacters(in: .whitespacesAndNewlines),
                evidenceQuote: unknown ? nil : quote, reviewedAt: Date())
            if store.saveFrameReview(review, expected: acquisition) { dismiss() }
            else { message = store.notice ?? AppLanguage.localized("The change could not be saved. Try again.") }
        } catch { message = error.moreDescription }
    }
}
