import AVFAudio
import MorningApple
import SwiftUI

/// The caller keeps this sheet unavailable during an active morning session.
struct VoicePickerView: View {
    @Bindable var speech: SpeechCoordinator
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var search = ""
    @ViewState<Bool> private var showingAllLanguages = false
    @ViewState<[SpeechVoiceDescriptor]> private var voices = []
    @ViewState<UUID?> private var previewID = nil

    var body: some View {
        NavigationStack {
            MorningList {
                Section {
                    voiceRow(name: String(localized: "Automatic"), detail: automaticDetail, identifier: nil)
                        .accessibilityIdentifier("voice.default")
                } footer: {
                    Text("Matches your device’s language and dialect, then prefers a higher-quality installed voice. Your choice applies to spoken morning steps.")
                }

                Section {
                    Button {
                        speech.speak(speech.previewText)
                        previewID = speech.playbackID
                    } label: {
                        Label("Preview selected voice", systemImage: "speaker.wave.2")
                    }
                    .accessibilityIdentifier("voice.preview")

                    if let previewID, speech.playbackID == previewID {
                        if speech.state == .preparing {
                            ProgressView("Preparing audio…")
                        } else if speech.state == .paused {
                            Button("Resume preview") { speech.resume() }
                                .accessibilityIdentifier("voice.resumePreview")
                        }
                        Button {
                            stopPreview()
                        } label: {
                            Label("Stop preview", systemImage: "stop.circle")
                        }
                        .accessibilityIdentifier("voice.stopPreview")
                    }
                    if let error = speech.lastError {
                        Text(error).font(.footnote).foregroundStyle(MorningStyle.muted)
                    }
                } footer: {
                    if let selected = speech.voiceIdentifier, !voices.contains(where: { $0.id == selected }) {
                        Text("Your saved voice is unavailable. Speech uses the automatic choice until you select another.")
                    } else {
                        Text("Listen through your current audio output. These are Apple system speech voices; Siri may use a different voice.")
                    }
                }

                Section {
                    Toggle("Show all languages", isOn: $showingAllLanguages)
                        .accessibilityIdentifier("voice.allLanguages")
                    ForEach(filteredVoices) { voice in
                        voiceRow(name: voice.name,
                            detail: "\(languageName(voice.language)) · \(voice.quality.displayName)", identifier: voice.id)
                            .accessibilityIdentifier("voice.option.\(voice.id)")
                    }
                    if filteredVoices.isEmpty {
                        Text(search.isEmpty ? "No matching installed voices. Try showing all languages." : "No matching voices.")
                            .foregroundStyle(MorningStyle.muted)
                    }
                } header: {
                    Text("Installed voices")
                } footer: {
                    Text("A voice’s language affects pronunciation. Choosing it does not translate your routine.")
                }

                Section("More natural voices") {
                    if !hasHigherQualityVoiceForDeviceLanguage {
                        Text("No Enhanced or Premium voice is available here for your device’s language yet.")
                            .font(.subheadline)
                    }
                    #if os(iOS)
                    Text("In Settings → Accessibility → Read & Speak → Voices, choose your language and download an Enhanced or Premium voice if offered. Return here after the download finishes.")
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                    Link("Apple’s voice settings guide", destination: URL(string: "https://support.apple.com/en-ie/guide/iphone/iph96b214f0/27/ios/27")!)
                    #else
                    Text(String(localized: "More voices can be downloaded through the accessibility voice controls in System Settings. Return here when the download finishes."))
                        .font(.footnote).foregroundStyle(MorningStyle.muted)
                    #endif
                    Button("Refresh installed voices") { voices = speech.availableVoices }
                        .accessibilityIdentifier("voice.refresh")
                }
            }
            .navigationTitle("Your morning voice")
            .searchable(text: $search, prompt: "Search names or languages")
            .tint(MorningStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("voice.done")
                }
            }
            .onAppear { voices = speech.availableVoices }
            .onReceive(NotificationCenter.default.publisher(for: AVSpeechSynthesizer.availableVoicesDidChangeNotification)) { _ in
                voices = speech.availableVoices
            }
            .onDisappear { stopPreview() }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }

    private var filteredVoices: [SpeechVoiceDescriptor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return showingAllLanguages ? voices : voices.filter { speech.matchesPreferredLanguage($0.language) }
        }
        return voices.filter {
            $0.name.localizedStandardContains(query)
                || $0.language.localizedStandardContains(query)
                || languageName($0.language).localizedStandardContains(query)
                || $0.quality.displayName.localizedStandardContains(query)
        }
    }

    private var automaticDetail: String {
        guard let voice = speech.recommendedVoice else { return String(localized: "Follow this device’s language") }
        return "\(voice.name) · \(languageName(voice.language)) · \(voice.quality.displayName)"
    }

    private var hasHigherQualityVoiceForDeviceLanguage: Bool {
        voices.contains { speech.matchesPreferredLanguage($0.language) && $0.quality != .standard }
    }

    private func voiceRow(name: String, detail: String, identifier: String?) -> some View {
        Button {
            stopPreview()
            speech.voiceIdentifier = identifier
        } label: {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(MorningStyle.muted)
                }
                Spacer()
                if speech.voiceIdentifier == identifier {
                    Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("\(name), \(detail)")
        .accessibilityValue(speech.voiceIdentifier == identifier ? "Selected" : "")
    }

    private func languageName(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }

    private func stopPreview() {
        guard let previewID else { return }
        self.previewID = nil
        if speech.playbackID == previewID { speech.stop() }
    }
}
