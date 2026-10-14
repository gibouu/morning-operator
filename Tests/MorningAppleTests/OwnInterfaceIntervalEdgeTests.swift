import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Synthetic screen text and manually supplied clocks; no capture or model calls.
@Suite("Own-interface spans with reordered frames, unreliable clocks and damaged saved lists")
struct OwnInterfaceIntervalEdgeTests {
    private let instant = Date(timeIntervalSince1970: 1_791_158_400)
    private let calendar = "Calendar\n09:00 Project planning meeting"

    private func recording(_ times: [(requested: Double, actual: Double?)],
                           spans: OwnInterfaceIntervals) throws -> ObservationAcquisition {
        let frames = try times.map {
            try ObservationFrameEvidence(requestedTimeSeconds: $0.requested,
                actualTimeSeconds: $0.actual, outcome: .observed, text: calendar)
        }
        let end = times.map { max($0.requested, $0.actual ?? 0) }.max() ?? 0
        let video = try ObservationVideoEvidence(durationSeconds: end + 10, frames: frames)
        let context = try ObservationRecordingContext(startedAt: instant,
            timeZoneIdentifier: "UTC", ownInterfaceIntervals: spans)
        return try ObservationAcquisition(id: context.id, importedAt: instant,
            observedDate: .init(date: instant, timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .video, sourceLabel: "Synthetic interval fixture",
            originalText: video.renderedText, videoEvidence: video, recordingContext: context)
    }

    @Test("Actual frame time wins over requested time, including repeated and reordered actual frames")
    func actualTimesAndReplayedFramesSurviveArchiveReload() throws {
        let source = try recording([(0, 10), (10, 8), (20, 10), (30, nil)],
            spans: OwnInterfaceIntervals([.init(startSeconds: 10, endSeconds: 10)]))
        let restored = try JSONDecoder().decode(ObservationArchive.self,
            from: JSONEncoder().encode(ObservationArchive(entries: [source])))
        let entry = try #require(restored.entry(id: source.id))
        let frames = try #require(entry.videoEvidence?.frames)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [entry], ownInterfaceMarginSeconds: 0)
        #expect(prepared.units.map(\.sampleID) == [frames[1].id, frames[3].id])
        #expect(prepared.omissions.map(\.sampleID) == [frames[0].id, frames[2].id])
        #expect(prepared.omissions.allSatisfy { $0.reason == .ownInterfaceInFront })
        #expect(prepared.units.allSatisfy { $0.text.utf8.elementsEqual(calendar.utf8) })
    }

    @Test("Backward scene readings preserve report order and widen the resulting merged interval")
    func backwardsClockDoesNotLoseAnOwnSceneVisit() throws {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: false, at: 90)
        recorder.begin()
        recorder.note(inFront: true, at: 110)
        recorder.note(inFront: false, at: 105)
        recorder.note(inFront: true, at: 108)
        recorder.note(inFront: false, at: 114)
        recorder.end()
        let spans = try #require(recorder.intervals(recordingStartedAt: 100))
        #expect(spans.intervals == [.init(startSeconds: 10, endSeconds: 14)])
        let source = try recording([8, 9, 10, 14, 15, 16].map { ($0, $0) }, spans: spans)
        let frames = try #require(source.videoEvidence?.frames)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source])
        #expect(prepared.units.map(\.sampleID) == [frames[0].id, frames[5].id])
        #expect(prepared.omissions.map(\.sampleID) == Array(frames[1...4]).map(\.id))
        #expect(prepared.omissions.allSatisfy { $0.reason == .ownInterfaceInFront })
    }

    @Test("A non-finite change poisons only that capture, and end freezes it before a fresh attempt")
    func nonFiniteTransitionAndStoppedAttemptCannotContaminateNextRecording() throws {
        var recorder = OwnInterfaceIntervalRecorder()
        recorder.note(inFront: false, at: 90)
        recorder.begin()
        recorder.note(inFront: true, at: .infinity)
        recorder.note(inFront: false, at: 104)
        recorder.end()
        let sealed = try #require(recorder.intervals(recordingStartedAt: 100))
        #expect(sealed.intervals == [.init(startSeconds: 0)])
        recorder.note(inFront: true, at: 120)
        recorder.note(inFront: false, at: 130)
        #expect(recorder.intervals(recordingStartedAt: 100) == sealed)

        recorder.begin()
        #expect(recorder.intervals(recordingStartedAt: 200) == OwnInterfaceIntervals([]))
        recorder.note(inFront: true, at: 210)
        recorder.note(inFront: false, at: 212)
        recorder.end()
        let next = try #require(recorder.intervals(recordingStartedAt: 200))
        #expect(next.intervals == [.init(startSeconds: 10, endSeconds: 12)])
        let source = try recording([(2, 2), (11, 11), (20, 20)], spans: next)
        let frames = try #require(source.videoEvidence?.frames)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source])
        #expect(prepared.units.map(\.sampleID) == [frames[0].id, frames[2].id])
        #expect(prepared.omissions.map(\.sampleID) == [frames[1].id])
    }

    @Test("An oversized unsorted decoded interval list keeps gaps and excludes the overflow tail")
    func hostileDecodedIntervalsAreNormalizedBeforeEvidenceSelection() throws {
        var raw = (0...OwnInterfaceIntervals.maximumIntervals).reversed().map { index in
            ["startSeconds": Double(index) * 6, "endSeconds": Double(index) * 6 + 1]
        }
        raw += [["startSeconds": 0, "endSeconds": 1],
                ["startSeconds": 100, "endSeconds": 99]]
        let spans = try JSONDecoder().decode(OwnInterfaceIntervals.self,
            from: JSONSerialization.data(withJSONObject: ["intervals": raw]))
        #expect(spans.intervals.count == OwnInterfaceIntervals.maximumIntervals)
        #expect(spans.intervals.last == .init(startSeconds: 1_530))
        let source = try recording([(2.001, 2.001), (1_527, 1_527), (1_530, 1_530), (1_590, 1_590)], spans: spans)
        let frames = try #require(source.videoEvidence?.frames)
        let prepared = try LearningEvidencePreparation.prepare(acquisitions: [source])
        #expect(prepared.units.map(\.sampleID) == [frames[0].id, frames[1].id])
        #expect(prepared.omissions.map(\.sampleID) == [frames[2].id, frames[3].id])
        #expect(prepared.omissions.allSatisfy { $0.reason == .ownInterfaceInFront })
    }
}
