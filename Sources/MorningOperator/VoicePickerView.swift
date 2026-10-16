import MorningApple
import MorningCore
import SwiftUI

/// The caller keeps this sheet unavailable during an active morning session.
struct VoicePickerView: View {
    @Bindable var store: MorningStore
    private var speech: SpeechCoordinator { store.speech }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var previewTask: Task<Void, Never>?
    @State private var previewAttempt: UUID?
    #if DEBUG
    @State private var previewReceipt: MorningVoicePreviewReceipt?
    #endif

    var body: some View {
        NavigationStack {
            MorningList {
                voiceRow(.male)
                voiceRow(.female)
                Section {
                    Button {
                        stopPreview()
                        let attempt = UUID()
                        previewAttempt = attempt
                        previewTask = Task { @MainActor in
                            #if DEBUG
                            await store.previewNaturalVoice { receipt in
                                guard previewAttempt == attempt, !store.privacyBlocksWork else { return }
                                previewReceipt = receipt
                            }
                            #else
                            await store.previewNaturalVoice()
                            #endif
                            guard previewAttempt == attempt else { return }
                            previewAttempt = nil; previewTask = nil
                        }
                    } label: {
                        Label("Listen", systemImage: "speaker.wave.2")
                    }
                    .disabled(previewTask != nil || store.privacyBlocksWork || store.sessionActive)
                    .accessibilityIdentifier("voice.preview")
                    .accessibilityValue(speech.statusText)
                    if previewTask != nil {
                        Button("Stop") { stopPreview() }
                            .accessibilityIdentifier("voice.stopPreview")
                    }
                    if let message = store.voiceFallbackMessage {
                        Text(message).font(.footnote).foregroundStyle(MorningStyle.muted)
                    }
                    #if DEBUG
                    if let previewReceipt, !store.privacyBlocksWork {
                        Text(AppLanguage.isFrench ? "Diagnostic de l’exemple vocal" : "Voice sample diagnostic").font(.caption)
                            .accessibilityIdentifier("voice.preview.receipt")
                            .accessibilityValue(previewReceipt.diagnostic)
                    }
                    #endif
                }
            }
            .navigationTitle("Voice")
            .navigationBarTitleDisplayMode(.inline)
            .tint(MorningStyle.accent)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("voice.done")
                }
            }
            .onDisappear { stopPreview() }
            .onChange(of: AppLanguage.code) { _, _ in stopPreview() }
            .onChange(of: store.dataGeneration) { _, _ in stopPreview() }
            .onChange(of: store.privacyBlocksWork) { _, blocked in if blocked { stopPreview() } }
            .onChange(of: store.sessionActive) { _, active in if active { stopPreview() } }
            .onChange(of: scenePhase) { _, phase in if phase == .background { stopPreview() } }
        }
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 220)
        #endif
    }

    private func voiceRow(_ gender: MorningVoiceGender) -> some View {
        let name = gender == .male
            ? String(localized: "Male", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
            : String(localized: "Female", bundle: AppLanguage.bundle(), locale: AppLanguage.locale)
        return Button {
            stopPreview()
            speech.voiceGender = gender
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if speech.voiceGender == gender {
                    Image(systemName: "checkmark").foregroundStyle(MorningStyle.accent)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(gender == .male ? "voice.gender.male" : "voice.gender.female")
        .accessibilityLabel(name)
        .accessibilityValue(speech.voiceGender == gender
            ? String(localized: "Selected", bundle: AppLanguage.bundle(), locale: AppLanguage.locale) : "")
        .accessibilityAddTraits(speech.voiceGender == gender ? .isSelected : [])
    }

    private func stopPreview() {
        #if DEBUG
        previewReceipt = nil
        #endif
        previewAttempt = nil
        previewTask?.cancel(); previewTask = nil
    }
}
