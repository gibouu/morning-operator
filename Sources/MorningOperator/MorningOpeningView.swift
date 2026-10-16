import SwiftUI
import MorningApple

/// The short opening of a morning (issue #28): the sentence the composer wrote, then its
/// choices as controls. The view shows the composer's string as it is and decides nothing
/// about freshness, counts or wording. It starts no speech; the store does, once.
struct MorningOpeningView: View {
    let store: MorningStore
    let presentation: MorningOpeningPresentation
    var canOperate: () -> Bool = { true }
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let opening = presentation.opening {
                if presentation.phase == .brief, let brief = presentation.briefText {
                    // The recap being read, word for word.
                    Text(verbatim: brief).font(.raleway(.body)).foregroundStyle(MorningStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("opening.briefText")
                } else {
                    // One string for the screen, VoiceOver and speech.
                    Text(verbatim: opening.displayText).font(.raleway(.body)).foregroundStyle(MorningStyle.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("opening.text")
                        .accessibilityValue(store.openingSpeechObservation)
                }
                choices(opening)
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparing your day…").font(.raleway(.subheadline)).foregroundStyle(MorningStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("opening.preparing")
            }
        }
        // No colour on the whole block: it would override the prominent button's own label.
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(MorningStyle.surface, in: RoundedRectangle(cornerRadius: MorningTheme.Space.radius))
    }

    @ViewBuilder private func choices(_ opening: MorningOpening) -> some View {
        // The recap is not offered while it is being read, or once it could not be read.
        let offered = opening.choices.filter { $0 != .brief || (presentation.phase == .choosing && !presentation.briefWithdrawn) }
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { buttons(offered) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { buttons(offered) }
                    VStack(alignment: .leading, spacing: 10) { buttons(offered) }
                }
            }
        }
        .disabled(store.privacyBlocksWork || store.voiceInputBlocksPlayback)
    }

    @ViewBuilder private func buttons(_ offered: [MorningOpeningChoice]) -> some View {
        ForEach(offered, id: \.self) { choice in
            let button = Button {
                guard choice == .stop || canOperate() else { return }
                store.chooseOpening(choice)
            } label: {
                Label(title(choice), systemImage: symbol(choice))
                    .font(.raleway(.subheadline, .semibold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 28)
            }
            .accessibilityLabel(title(choice))
            .accessibilityIdentifier(identifier(choice))
            .disabled(choice != .stop && !canOperate())
            // The first choice the opening names is the prominent one.
            if choice == offered.first {
                // The ink control carries the matching on-ink text in each appearance.
                button.buttonStyle(PrimaryButtonStyle())
            } else {
                button.buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private func title(_ choice: MorningOpeningChoice) -> String {
        switch choice {
        case .brief: String(localized: "Hear my recap")
        case .ritual: String(localized: "Start my routine")
        case .stop: String(localized: "Stop")
        }
    }

    private func identifier(_ choice: MorningOpeningChoice) -> String {
        switch choice {
        case .brief: "opening.brief"
        case .ritual: "opening.routine"
        case .stop: "opening.stop"
        }
    }

    private func symbol(_ choice: MorningOpeningChoice) -> String {
        switch choice {
        case .brief: "speaker.wave.2"
        case .ritual: "play.fill"
        case .stop: "stop.fill"
        }
    }
}
