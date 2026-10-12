import AVFoundation
import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Native media time preservation")
struct RationalMediaTimingTests {
    @Test(arguments: [Int64(23_557), 46_064, 52_542])
    func nativeFieldsCanBeRestoredWithoutASecondsInitializer(_ value: Int64) throws {
        let native = CMTime(value: value, timescale: 600, flags: [.valid, .hasBeenRounded], epoch: 5)
        let timing = DecodedFrameTiming(native)
        let original = try #require(timing.original)
        #expect(original.value == native.value && original.timescale == native.timescale)
        #expect(original.epoch == native.epoch && original.flags == native.flags.rawValue)
        #expect(timing.seconds == native.seconds && original.seconds == native.seconds)
        #expect(timing.warnings.isEmpty)
        let restored = CMTime(value: original.value, timescale: original.timescale,
            flags: CMTimeFlags(rawValue: original.flags), epoch: original.epoch)
        #expect(restored.value == value && restored.timescale == 600 && restored.epoch == 5)
        #expect(restored.flags == native.flags && CMTimeCompare(restored, native) == 0)
    }

    @Test func blankOCRFailureAndTextBudgetClippingKeepTheOriginalTime() throws {
        let nativeTimes = [CMTime(value: 0, timescale: 600), CMTime(value: 23_557, timescale: 600),
                           CMTime(value: 46_064, timescale: 600), CMTime(value: 52_542, timescale: 600)]
        let timing = nativeTimes.map(DecodedFrameTiming.init)
        let outcomes: [ObservationSampleOutcome] = [.observed, .ocrFailed, .blank, .observed]
        let requested = [0.0, 40, 80, 90]
        let text = [String(repeating: "x", count: ObservationVideoEvidence.maximumOCRCharacters + 1), "", "", "Later synthetic text"]
        var builder = try VideoObservationBuilder(durationSeconds: 100)
        for index in nativeTimes.indices {
            try builder.append(id: UUID(), requestedTimeSeconds: requested[index], actualTimeSeconds: timing[index].seconds,
                outcome: outcomes[index], text: text[index], ocrWarnings: timing[index].warnings,
                originalPresentationTime: timing[index].original)
        }
        let result = try builder.finish()
        #expect(result.frames.map(\.originalPresentationTime) == timing.map(\.original))
        #expect(result.frames.map(\.outcome) == outcomes)
        #expect(result.frames.first?.textWasTruncated == true && result.frames.last?.textWasTruncated == true)
        #expect(result.frames.last?.text.isEmpty == true && result.decodedFrameCount == 4)
    }

    @Test func unsupportedNativeMetadataDoesNotRelabelDecodedImagesAsFailures() throws {
        let invalidTimes = [CMTime.invalid, CMTime.indefinite,
            CMTime(value: 1, timescale: 600, flags: CMTimeFlags(rawValue: 129), epoch: 0)]
        for native in invalidTimes {
            let timing = DecodedFrameTiming(native)
            #expect(timing.original == nil && timing.warnings.count == 1)
            var builder = try VideoObservationBuilder(durationSeconds: 1)
            try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: timing.seconds,
                outcome: .observed, text: "Synthetic Cedar", ocrWarnings: timing.warnings,
                originalPresentationTime: timing.original)
            let result = try builder.finish()
            let frame = try #require(result.frames.first)
            #expect(frame.outcome == .observed && frame.text == "Synthetic Cedar" && result.decodedFrameCount == 1)
            #expect(frame.originalPresentationTime == nil)
            #expect(frame.warnings.contains { $0.contains("Original media timing could not be preserved") })
        }
    }

    @Test func outOfMovieRangeFallsBackWithoutKeepingADanglingNativeTime() throws {
        let timing = DecodedFrameTiming(CMTime(value: 20, timescale: 1))
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        try builder.append(id: UUID(), requestedTimeSeconds: 1, actualTimeSeconds: timing.seconds,
            outcome: .blank, originalPresentationTime: timing.original)
        let frame = try #require(builder.finish().frames.first)
        #expect(frame.originalPresentationTime == nil && frame.actualTimeSeconds == nil)
        #expect(frame.outcome == .blank && frame.timeBasis == .requestedSamplingTime)
        #expect(frame.warnings.contains { $0.contains("fallback") })
    }

    @Test func inconsistentNewMetadataCannotEnterTheAssembler() throws {
        var builder = try VideoObservationBuilder(durationSeconds: 10)
        let original = try ObservationMediaTime(value: 1, timescale: 1)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try builder.append(id: UUID(), requestedTimeSeconds: 0, actualTimeSeconds: 2,
                outcome: .observed, text: "Synthetic Cedar", originalPresentationTime: original)
        }
        #expect(builder.frames.isEmpty)
    }

    @Test func archiveRestorationKeepsSourceAndCitedClassificationWhenOptionalTimingIsCorrupt() throws {
        let nativeTime = try ObservationMediaTime(value: 0, timescale: 600)
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0,
            outcome: .observed, text: "Cedar\nSynthetic archive restoration fixture", originalPresentationTime: nativeTime)
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: [frame])
        let decision = ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: 0, timeBasis: .mediaPresentation,
            evidence: .identified(app: .init(key: "visual-context:cedar", displayName: "Cedar"), reference: frame.evidenceReference),
            evidenceQuote: "Cedar", reason: "Synthetic fixture; no model called.")
        let classification = ObservationContextClassification(decisions: [decision], status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0, diagnostics: [],
            modelAvailability: "Synthetic fixture envelope; no model called.")
        let entry = try ObservationAcquisition(origin: .synthetic, sourceKind: .video, sourceLabel: "Synthetic timing restoration",
            originalText: evidence.renderedText, videoEvidence: evidence, classification: classification)
        let archive = try ObservationArchive(entries: [entry])
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var entries = try #require(payload["entries"] as? [[String: Any]])
        try #require(entries.count == 1)
        var video = try #require(entries[0]["videoEvidence"] as? [String: Any])
        var frames = try #require(video["frames"] as? [[String: Any]])
        try #require(frames.count == 1)
        frames[0]["originalPresentationTime"] = ["value": "corrupt", "timescale": 600]
        video["frames"] = frames; entries[0]["videoEvidence"] = video; payload["entries"] = entries
        let restored = try JSONDecoder().decode(ObservationArchive.self,
            from: JSONSerialization.data(withJSONObject: payload))
        let restoredEntry = try #require(restored.entry(id: entry.id))
        let restoredFrame = try #require(restoredEntry.videoEvidence?.frames.first)
        #expect(restoredEntry.originalText.utf8.elementsEqual(entry.originalText.utf8))
        #expect(restoredEntry.videoEvidence?.renderedText == evidence.renderedText)
        #expect(restoredEntry.classification == classification && restoredEntry.warnings.isEmpty)
        #expect(restoredFrame.originalPresentationTime == nil && restoredFrame.id == frame.id)
        #expect(restoredFrame.text == frame.text && restoredFrame.actualTimeSeconds == frame.actualTimeSeconds)
        #expect(restoredFrame.warnings.contains { $0.contains("timing metadata") })
    }
}
