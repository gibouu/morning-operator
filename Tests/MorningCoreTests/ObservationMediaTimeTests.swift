import Foundation
import Testing
@testable import MorningCore

@Suite("Original rational media timestamps")
struct ObservationMediaTimeTests {
    @Test(arguments: [Int64(23_557), 46_064, 52_542])
    func originalTicksSurviveEncodingWithoutDecimalReconstruction(_ value: Int64) throws {
        let time = try ObservationMediaTime(value: value, timescale: 600, epoch: 7, flags: 3)
        let decoded = try JSONDecoder().decode(ObservationMediaTime.self, from: JSONEncoder().encode(time))
        #expect(decoded == time)
        #expect(decoded.value == value && decoded.timescale == 600)
        #expect(decoded.epoch == 7 && decoded.flags == 3 && decoded.hasBeenRounded)
    }

    @Test func exactInstantComparisonDoesNotUseDoubleOrOverflowingCrossProducts() throws {
        let numerator = Int64.max - 1
        let scaled = try ObservationMediaTime(value: numerator, timescale: 2)
        let reduced = try ObservationMediaTime(value: numerator / 2, timescale: 1, flags: 3)
        #expect(scaled != reduced, "Stored provenance includes the original scale and flags.")
        #expect(scaled.representsSameInstant(as: reduced))
        let adjacent = try ObservationMediaTime(value: Int64.max, timescale: 2)
        #expect(scaled.seconds == adjacent.seconds, "These distinct fractions collide in Double.")
        #expect(!scaled.representsSameInstant(as: adjacent))
        let otherEpoch = try ObservationMediaTime(value: numerator, timescale: 2, epoch: 1)
        #expect(!scaled.representsSameInstant(as: otherEpoch))
        #expect(try ObservationMediaTime(value: 0, timescale: 600)
            .representsSameInstant(as: ObservationMediaTime(value: 0, timescale: 1)))
    }

    @Test func invalidAndNonNumericNativeFieldsAreRejectedByConstructionAndDecode() throws {
        let invalid: [(Int64, Int32, UInt32)] = [(-1, 600, 1), (1, 0, 1), (1, -1, 1),
            (1, 600, 0), (1, 600, 2), (1, 600, 5), (1, 600, 9), (1, 600, 17), (1, 600, 129)]
        for (value, scale, flags) in invalid {
            #expect(throws: ObservationMediaTimeError.invalidTime) {
                try ObservationMediaTime(value: value, timescale: scale, flags: flags)
            }
            let data = try JSONSerialization.data(withJSONObject: ["value": value, "timescale": Int64(scale),
                "epoch": Int64(0), "flags": Int64(flags)])
            #expect(throws: ObservationMediaTimeError.invalidTime) {
                try JSONDecoder().decode(ObservationMediaTime.self, from: data)
            }
        }
    }

    @Test func newFramesRequireTheSameActualTimeAndADecodedImage() throws {
        let time = try ObservationMediaTime(value: 23_557, timescale: 600)
        let frame = try source(time: time)
        #expect(frame.originalPresentationTime == time)
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationFrameEvidence(requestedTimeSeconds: 40, actualTimeSeconds: 39,
                outcome: .observed, text: "Synthetic Cedar", originalPresentationTime: time)
        }
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationFrameEvidence(requestedTimeSeconds: 40,
                outcome: .observed, text: "Synthetic Cedar", originalPresentationTime: time)
        }
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationFrameEvidence(requestedTimeSeconds: 40,
                outcome: .decodeFailed, originalPresentationTime: time)
        }
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try ObservationVideoEvidence(durationSeconds: 30, frames: [frame])
        }
    }

    @Test func legacyAndExplicitNullTimingStayUnknownWithoutChangingSourceEncoding() throws {
        let original = try source(time: nil)
        var object = try object(original)
        #expect(object["originalPresentationTime"] == nil)
        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let legacy = try JSONDecoder().decode(ObservationFrameEvidence.self, from: legacyData)
        #expect(legacy == original && legacy.originalPresentationTime == nil)
        object["originalPresentationTime"] = NSNull()
        let null = try JSONDecoder().decode(ObservationFrameEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(null == original && null.warnings.isEmpty)
        let reencoded = try self.object(null)
        #expect(reencoded["originalPresentationTime"] == nil)
    }

    @Test func corruptedOptionalTimingPreservesExactTextLayoutAndDecimalEvidence() throws {
        let original = try source(time: ObservationMediaTime(value: 23_557, timescale: 600))
        let corruptValues: [Any] = ["wrong type", [1, 2], ["value": 1],
            ["value": 23_557, "timescale": 0, "epoch": 0, "flags": 1],
            ["value": 23_558, "timescale": 600, "epoch": 0, "flags": 1],
            ["value": 23_557, "timescale": 600, "epoch": 0, "flags": 5]]
        for corrupt in corruptValues {
            var object = try object(original)
            object["originalPresentationTime"] = corrupt
            let restored = try JSONDecoder().decode(ObservationFrameEvidence.self,
                from: JSONSerialization.data(withJSONObject: object))
            #expect(restored.originalPresentationTime == nil)
            #expect(restored.id == original.id && restored.text.utf8.elementsEqual(original.text.utf8))
            #expect(restored.ocrLines == original.ocrLines && restored.actualTimeSeconds == original.actualTimeSeconds)
            #expect(restored.requestedTimeSeconds == original.requestedTimeSeconds && restored.outcome == .observed)
            #expect(restored.warnings.count == 1 && restored.warnings[0].contains("timing metadata"))
            let video = try ObservationVideoEvidence(durationSeconds: 45, frames: [restored])
            let originalVideo = try ObservationVideoEvidence(durationSeconds: 45, frames: [original])
            #expect(video.renderedText.utf8.elementsEqual(originalVideo.renderedText.utf8))
        }
    }

    @Test func recoveryWarningsStayBoundedAndDoNotAccumulateAfterResaving() throws {
        let warnings = (1...8).map { "Prior warning \($0)" }
        let original = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0,
            outcome: .observed, text: "Synthetic Cedar", warnings: warnings)
        var object = try object(original)
        object["originalPresentationTime"] = "invalid optional metadata"
        let restored = try JSONDecoder().decode(ObservationFrameEvidence.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.warnings.count == 8)
        #expect(Array(restored.warnings.prefix(7)) == Array(warnings.prefix(7)))
        #expect(restored.warnings.last?.contains("One prior warning was omitted") == true)
        let again = try JSONDecoder().decode(ObservationFrameEvidence.self, from: JSONEncoder().encode(restored))
        #expect(again == restored && again.originalPresentationTime == nil)
    }

    @Test func invalidRequiredSourceCannotBeRescuedByTheTimingRecoveryPath() throws {
        var object = try object(source(time: nil))
        object["text"] = ""
        object["originalPresentationTime"] = "invalid"
        #expect(throws: ObservationVideoEvidenceError.invalidFrame) {
            try JSONDecoder().decode(ObservationFrameEvidence.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func rationalMetadataDoesNotCreateCaptureCoverageOrMeasuredUse() throws {
        let time = try ObservationMediaTime(value: 23_557, timescale: 600)
        let frame = try source(time: time)
        let evidence = try ObservationVideoEvidence(durationSeconds: 45, frames: [frame])
        let trace = try evidence.makeTrace(origin: .synthetic)
        let report = try trace.report(maximumSampleGapSeconds: 5)
        #expect(trace.capturedIntervals == nil)
        #expect(!report.captureIsComplete && report.capturedDurationSeconds == nil)
        #expect(trace.samples.first?.timeSeconds == frame.actualTimeSeconds)
    }

    private func source(time: ObservationMediaTime?) throws -> ObservationFrameEvidence {
        let text = "Café — synthetic Cedar"
        let line = try ObservationOCRLine(text: text, startCharacterOffset: 0, endCharacterOffset: text.count,
            bounds: ObservationNormalizedBounds(x: 0.1, y: 0.5, width: 0.5, height: 0.1), confidence: 0.9)
        return try ObservationFrameEvidence(requestedTimeSeconds: 40, actualTimeSeconds: time?.seconds ?? 39.25,
            outcome: .observed, text: text, ocrLines: [line], originalPresentationTime: time)
    }

    private func object(_ value: ObservationFrameEvidence) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }
}
