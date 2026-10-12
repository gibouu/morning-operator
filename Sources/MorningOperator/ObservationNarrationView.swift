import SwiftUI
import MorningCore
import MorningApple

/// Source selection lives in Review. The ordinary Morning page gets no new controls.
struct ObservationNarrationView: View {
    @Bindable var store: MorningStore
    let observationID: UUID
    var requestedNarration: PreparedObservationNarration? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @ViewState<String?> private var selectedID = nil
    @ViewState<UUID?> private var previewID = nil
    @ViewState<Bool> private var added = false
    @ViewState<Bool> private var appliedRequestedSelection = false
    @ViewState<String?> private var message = nil

    private var entry: ObservationAcquisition? { store.observationArchive.entry(id: observationID) }
    private var candidates: [ObservationNarrationCandidate] {
        entry.map { ObservationNarrationComposer.candidates(for: $0) } ?? []
    }
    private var prepared: PreparedObservationNarration? {
        guard let entry, let selectedID, let candidate = candidates.first(where: { $0.id == selectedID }) else { return nil }
        return try? ObservationNarrationComposer.prepare(acquisition: entry, candidate: candidate)
    }
    private var playing: Bool { previewID != nil && previewID == store.speech.playbackID }
    private var blocked: Bool { store.sessionActive || store.busy || !store.storageIsAvailable || store.voiceInputBlocksPlayback }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Keep a thought from a morning you've saved. Choose the words you want to hear again.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let entry { Text(entry.sourceLabel).font(.caption).foregroundStyle(.secondary) }
                }
                if prepared == nil, let message {
                    Section {
                        Text(message).font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("narration.requestUnavailable")
                    }
                }
                if let prepared {
                    Section {
                        Text(prepared.sourceDateLabel).font(.caption).foregroundStyle(.secondary)
                        Text(prepared.spokenText).textSelection(.enabled)
                            .accessibilityIdentifier("narration.text")
                        HStack {
                            Button {
                                message = nil
                                previewID = store.previewObservationNarration(prepared)
                                if previewID == nil { message = String(localized: "The preview isn't ready. Check the source and try again.") }
                            } label: { Label("Hear preview", systemImage: "play.fill") }
                            .disabled(blocked || store.speech.state != .idle)
                            .accessibilityIdentifier("narration.hear")
                            Spacer()
                            if playing {
                                Button("Stop") { stopPreview() }
                                    .accessibilityIdentifier("narration.stop")
                            }
                        }.buttonStyle(.borderless)
                        Text(playing ? store.speech.statusText : (store.speech.lastError ?? String(localized: "Ready when you are")))
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("narration.playback")
                            .accessibilityValue(playing ? store.speech.state.rawValue : "idle")
                        Button(added ? "Added to your draft" : "Add to my morning") {
                            stopPreview()
                            added = store.addObservationNarration(prepared)
                            message = added ? String(localized: "Review and approve your updated morning before running it.") : store.notice
                        }.disabled(blocked || added)
                            .accessibilityIdentifier("narration.add")
                        if let message {
                            Text(message).font(.caption).foregroundStyle(.secondary)
                                .accessibilityIdentifier("narration.message")
                        }
                    } header: { Text("What you'll hear") } footer: {
                        Text("The date is spoken too. This is a saved excerpt, not today's messages. MORE checks its source before every playback.")
                    }
                }
                Section {
                    if candidates.isEmpty {
                        Text("This observation needs a confirmed day, a personal or sample origin, and a short readable line. You can review its date or add a correction in Learn.")
                            .foregroundStyle(.secondary).accessibilityIdentifier("narration.unavailable")
                    } else {
                        ForEach(candidates) { candidate in
                            Button {
                                stopPreview(); selectedID = candidate.id; added = false; message = nil
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(candidate.text).foregroundStyle(.primary).lineLimit(4)
                                    Spacer(minLength: 0)
                                    if selectedID == candidate.id {
                                        Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                                    }
                                }.padding(.vertical, 4)
                            }.disabled(blocked)
                                .accessibilityIdentifier("narration.candidate.\(candidate.id)")
                        }
                    }
                } header: { Text("Choose an excerpt") } footer: {
                    Text("Up to 24 short, complete lines from the saved text. Check extracted words against the recording; screen recognition can make mistakes.")
                }
            }
            .scrollContentBackground(.hidden).background(MorningStyle.background)
            .navigationTitle("A saved moment").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.accessibilityIdentifier("narration.done")
            } }
            .onAppear { applyRequestedSelection() }
            .onChange(of: entry) { _, _ in
                stopPreview(); selectedID = nil; added = false
                if requestedNarration != nil {
                    message = String(localized: "This saved source changed. Choose the excerpt again before adding it.")
                }
            }
            .onChange(of: scenePhase) { _, phase in if phase != .active { stopPreview() } }
            .onDisappear { stopPreview() }
        }.tint(MorningStyle.accent)
    }

    private func applyRequestedSelection() {
        guard !appliedRequestedSelection else { return }
        appliedRequestedSelection = true
        guard let requestedNarration else { return }
        guard requestedNarration.reference.acquisitionID == observationID,
              let current = try? ObservationNarrationComposer.resolve(reference: requestedNarration.reference,
                  archive: store.observationArchive),
              current.spokenText.utf8.elementsEqual(requestedNarration.spokenText.utf8),
              let candidate = candidates.first(where: {
                  $0.frameID == current.reference.frameID &&
                      $0.text.utf8.elementsEqual(current.reference.quote.utf8)
              }) else {
            message = String(localized: "This exact excerpt is no longer available. Return to its source or choose a saved line yourself.")
            return
        }
        selectedID = candidate.id
    }

    private func stopPreview() {
        store.stopObservationPreview(previewID)
        previewID = nil
    }
}
