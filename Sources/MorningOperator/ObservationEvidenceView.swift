import SwiftUI
import MorningCore
import MorningApple

/// Evidence belongs in review, away from the quiet everyday Morning screen.
struct ObservationEvidenceView: View {
    let evidence: ObservationVideoEvidence
    let classification: ObservationContextClassification?
    let isBusy: Bool
    let canAnalyze: Bool
    let analyze: () -> Void

    private var readableCount: Int { evidence.frames.filter(\.canSupportIdentity).count }
    private var report: ObservationTraceReport? {
        guard let classification else { return nil }
        return try? evidence.makeTrace(decisions: classification.decisions).report(maximumSampleGapSeconds: 5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("A glimpse of this recording", systemImage: "film.stack")
                .font(.raleway(.subheadline, .semibold))
            Text("\(Int(evidence.durationSeconds.rounded())) seconds · \(evidence.frames.count) samples · \(readableCount) with complete text")
                .font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                .accessibilityIdentifier("learn.videoEvidence")
            DisclosureGroup("See sampled screens") {
                VStack(alignment: .leading, spacing: 14) {
                    Text("These are occasional views of your screen. They can't count every scroll, prove a message was read, or measure complete app use.")
                    if let report, !report.visits.isEmpty {
                        Text(report.visits.map { $0.app.displayName }.joined(separator: " → "))
                            .fontWeight(.medium).foregroundStyle(MorningStyle.ink)
                            .accessibilityIdentifier("learn.visibleContexts")
                        Text("Order of recognized appearances. Unknown samples may hide other activity.")
                    }
                    if let classification {
                        Text(classificationStatus(classification))
                            .accessibilityIdentifier("learn.contextStatus")
                    }
                    Button(classification == nil ? "Recognize sampled screens" : "Try recognizing screens again", action: analyze)
                        .buttonStyle(.borderless).foregroundStyle(MorningStyle.accent)
                        .disabled(isBusy || !canAnalyze || readableCount == 0)
                        .accessibilityIdentifier("learn.recognizeScreens")
                    ForEach(evidence.frames) { frame in
                        HStack(alignment: .top, spacing: 12) {
                            Text(timestamp(frame.timeSeconds)).monospacedDigit()
                                .frame(width: 48, alignment: .leading)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(frameLabel(frame)).foregroundStyle(MorningStyle.ink)
                                if frame.textWasTruncated { Text("Text limit reached; identity left unknown.") }
                                if frame.timeBasis == .requestedSamplingTime { Text("Requested time; exact frame time unavailable.") }
                            }
                        }
                    }
                    ForEach(Array(evidence.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(warning)
                    }
                    Text("Uses Apple Intelligence on this device. Editing the observation removes its attached frame evidence and screen interpretation.")
                }.font(.raleway(.caption)).foregroundStyle(MorningStyle.muted)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            }.font(.raleway(.subheadline)).tint(MorningStyle.accent)
        }
    }

    private func classificationStatus(_ value: ObservationContextClassification) -> String {
        switch value.status {
        case .noEligibleFrames: AppLanguage.localized("No samples have enough usable text to recognize a screen.")
        case .unavailable: AppLanguage.localized("On-device screen recognition is unavailable. The saved samples are still here.")
        case .completed: AppLanguage.localized("On-device recognition finished. Unclear screens remain unknown.")
        case .partialFailure: AppLanguage.localized("Some screens could not be analyzed. Those samples remain unknown.")
        case .failed: AppLanguage.localized("Screen recognition did not finish. Samples remain unknown; you can retry.")
        }
    }

    private func frameLabel(_ frame: ObservationFrameEvidence) -> String {
        if let decision = classification?.decisions.first(where: { $0.sampleID == frame.id }) {
            switch decision.evidence {
            case .identified(let app, _): return app.displayName
            case .ambiguous: return AppLanguage.localized("Unclear screen")
            case .unknown: break
            }
        }
        switch frame.outcome {
        case .observed: return classification == nil ? AppLanguage.localized("Text found · screen not yet recognized") : AppLanguage.localized("Unknown screen")
        case .blank: return AppLanguage.localized("No readable text")
        case .decodeFailed: return AppLanguage.localized("Frame unavailable")
        case .ocrFailed: return AppLanguage.localized("Text extraction failed")
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}
