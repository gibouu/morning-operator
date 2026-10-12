import SwiftUI
#if os(iOS)
import AVKit
#endif

/// A real system route chooser. It does not select a speaker or detect the user's room.
struct MorningAudioRoutePicker: View {
    var body: some View {
        #if os(iOS)
        MorningSystemRoutePicker()
            .frame(width: 44, height: 44)
            .accessibilityLabel("Choose audio output")
            .accessibilityHint("Select an available speaker or headphones using the system picker.")
            .accessibilityIdentifier("audio.chooseOutput")
        #else
        Label("Choose output in Control Center", systemImage: "airplay.audio")
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("audio.outputInstructions")
        #endif
    }
}

#if os(iOS)
private struct MorningSystemRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView(frame: .zero)
        picker.prioritizesVideoDevices = false
        picker.tintColor = .label
        picker.activeTintColor = .systemBlue
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif
