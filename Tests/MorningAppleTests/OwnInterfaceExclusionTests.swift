import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// A clock the test moves by hand, standing in for the recorder's monotonic clock.
private final class ManualClock {
    private(set) var seconds: Double
    init(_ seconds: Double) { self.seconds = seconds }
    func advance(_ by: Double) { seconds += by }
}

@Suite("Frames sampled while MORE itself was in front")
struct OwnInterfaceExclusionTests {
    private let instant = Date(timeIntervalSince1970: 1_760_000_000)
    // Synthetic screen text. The first is written so that the text rule accepts it; it
    // stands for a screen of MORE that the wording list does not recognise.
    private let unrecognisedOwnScreen = "Up next\n07:30 Stretching then breakfast outside"
    private let calendar = "Calendar\n09:00 Project planning meeting"
    private let picker = "Screen Sharing\nShare Screen\nCancel"

    @Test("The fixture's own screen is one the text rule accepts, so only time can exclude it")
    func fixturePremise() {
        #expect(LearningEvidencePolicy.isEligibleVisualContext(unrecognisedOwnScreen))
        #expect(LearningEvidencePolicy.isEligibleVisualContext(calendar))
        #expect(!LearningEvidencePolicy.isEligibleVisualContext(picker))
    }

    private func context(_ spans: OwnInterfaceIntervals?) throws -> ObservationRecordingContext {
        try ObservationRecordingContext(startedAt: instant, timeZoneIdentifier: "Europe/Paris",
                                        ownInterfaceIntervals: spans)
    }

    /// One frame per `(movie seconds, text)`. The movie lasts ten seconds past its last frame.
    private func recording(_ frames: [(Double, String)], context: ObservationRecordingContext?) throws -> ObservationAcquisition {
        let evidence = try frames.map {
            try ObservationFrameEvidence(requestedTimeSeconds: $0.0, actualTimeSeconds: $0.0, outcome: .observed, text: $0.1)
        }
        let video = try ObservationVideoEvidence(durationSeconds: (frames.last?.0 ?? 0) + 10, frames: evidence)
        return try ObservationAcquisition(id: context?.id ?? UUID(), importedAt: instant,
            observedDate: ObservationObservedDate(date: instant, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .video, sourceLabel: "Generated fixture",
            originalText: video.renderedText, videoEvidence: video, recordingContext: context)
    }

    private func reasons(_ evidence: PreparedLearningEvidence, in entry: ObservationAcquisition) -> [LearningEvidenceOmissionReason?] {
        (entry.videoEvidence?.frames ?? []).map { frame in
            evidence.omissions.first { $0.sampleID == frame.id }?.reason
        }
    }

    @Test("A native recording that starts and ends in MORE gives evidence only from the other app")
    func startAndEndInMORE() throws {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
        let entry = try recording([(0, unrecognisedOwnScreen), (30, calendar), (64, unrecognisedOwnScreen)],
                                  context: context(spans))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(evidence.units.map(\.sampleID) == [entry.videoEvidence?.frames[1].id])
        #expect(reasons(evidence, in: entry) == [.ownInterfaceInFront, nil, .ownInterfaceInFront])
        #expect(evidence.omissions.count == 2, "Each excluded frame is reported, none is dropped silently.")
    }

    @Test("The same frames from an imported file, or from an older recording, are judged by text alone")
    func noSpansMeansNoTimeRule() throws {
        let frames = [(0.0, unrecognisedOwnScreen), (30.0, calendar), (64.0, unrecognisedOwnScreen)]
        for entry in [try recording(frames, context: nil), try recording(frames, context: context(nil))] {
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
            #expect(evidence.units.count == 3)
            #expect(evidence.omissions.isEmpty)
        }
        // The text rule is unchanged for them: a recognised setup screen is still left out.
        let imported = try recording([(0, picker), (30, calendar)], context: nil)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [imported])
        #expect(reasons(evidence, in: imported) == [.unsupportedVisualContext, nil])
    }

    @Test("The time rule reports its own reason, and the text rule still guards the other frames")
    func reasonsStayDistinct() throws {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4)])
        let entry = try recording([(0, picker), (20, picker), (30, calendar)], context: context(spans))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(reasons(evidence, in: entry) == [.ownInterfaceInFront, .unsupportedVisualContext, nil])
        #expect(LearningEvidenceOmissionReason.ownInterfaceInFront.rawValue
            != LearningEvidenceOmissionReason.unsupportedVisualContext.rawValue)
    }

    @Test("Frames just inside, exactly on and just outside a widened bound")
    func boundaryFrames() throws {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 10, endSeconds: 20)])
        let times = [8.999, 9, 9.001, 20.999, 21, 21.001, 40]
        let entry = try recording(times.map { ($0, calendar) }, context: context(spans))
        let widened = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        #expect(reasons(widened, in: entry) == [nil, .ownInterfaceInFront, .ownInterfaceInFront,
                                                .ownInterfaceInFront, .ownInterfaceInFront, nil, nil])
        let exact = try recording([9.999, 10, 20, 20.001].map { ($0, calendar) }, context: context(spans))
        let unwidened = try LearningEvidencePreparation.prepare(acquisitions: [exact], ownInterfaceMarginSeconds: 0)
        #expect(reasons(unwidened, in: exact) == [nil, .ownInterfaceInFront, .ownInterfaceInFront, nil])
    }

    @Test("A frame the person kept unknown keeps that reason; a recording wholly in MORE supports nothing")
    func reviewAndEmptyResult() throws {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0)])
        let entry = try recording([(0, calendar), (30, calendar)], context: context(spans))
        // The refusal names the cause, so a capture in which MORE never left the front is
        // told apart from a recording that simply shows nothing usable.
        #expect(throws: RoutineEvidenceProposalError.ownInterfaceLeftNoEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [entry])
        }
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [try recording([(0, picker)], context: context(nil))])
        }
        #expect(RoutineEvidenceProposalError.ownInterfaceLeftNoEvidence.errorDescription
            != RoutineEvidenceProposalError.insufficientEvidence.errorDescription)
        let partly = try recording([(0, calendar), (30, calendar)],
                                   context: context(OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4)])))
        var archive = try ObservationArchive(entries: [partly])
        let first = try #require(partly.videoEvidence?.frames.first)
        try archive.reviewFrame(id: partly.id, review: ObservationFrameReview(sampleID: first.id, label: nil, reviewedAt: instant))
        let reviewed = try #require(archive.entry(id: partly.id))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [reviewed])
        #expect(reasons(evidence, in: reviewed) == [.explicitlyReviewedUnknown, nil])
    }

    @Test("The recorder's state turns scene reports and one clock into the session's saved spans")
    func recorderStateWithInjectedClock() throws {
        let clock = ManualClock(1_000)
        var state = ScreenRecordingContextState()
        // The app reports its scene before any capture exists.
        state.ownInterfaceChanged(inFront: true, monotonicSeconds: clock.seconds)
        clock.advance(30)
        let session = UUID()
        state.begin(sessionID: session)
        #expect(state.context == nil, "Opening the picker is not the start of a recording.")
        clock.advance(2)
        state.recordingDidStart(sessionID: session, startedAt: instant, timeZoneIdentifier: "Europe/Paris",
                                monotonicStartSeconds: clock.seconds)
        clock.advance(4)
        state.ownInterfaceChanged(inFront: false, monotonicSeconds: clock.seconds)
        clock.advance(56)
        state.ownInterfaceChanged(inFront: true, monotonicSeconds: clock.seconds)
        clock.advance(6)
        state.captureEnded()
        let saved = try #require(state.context)
        #expect(saved.id == session && saved.startedAt == instant)
        #expect(saved.ownInterfaceIntervals?.intervals == [.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
        // Leaving MORE while the file is still being closed changes nothing that was recorded.
        clock.advance(3)
        state.ownInterfaceChanged(inFront: false, monotonicSeconds: clock.seconds)
        #expect(state.context == saved)

        state.clear()
        #expect(state.context == nil)
        let next = UUID()
        state.begin(sessionID: next)
        clock.advance(1)
        state.recordingDidStart(sessionID: next, startedAt: instant.addingTimeInterval(120), timeZoneIdentifier: "UTC",
                                monotonicStartSeconds: clock.seconds)
        #expect(state.context?.ownInterfaceIntervals == OwnInterfaceIntervals([]),
                "The next recording starts from the latest reported state and inherits no span.")
    }

    @Test("A start that cannot be aligned, or a scene never reported, records no span")
    func unalignedStartRecordsNothing() throws {
        var unaligned = ScreenRecordingContextState()
        unaligned.ownInterfaceChanged(inFront: true, monotonicSeconds: 5)
        let session = UUID()
        unaligned.begin(sessionID: session)
        unaligned.recordingDidStart(sessionID: session, startedAt: instant, timeZoneIdentifier: "UTC")
        let context = try #require(unaligned.context)
        #expect(context.ownInterfaceIntervals == nil)
        let entry = try recording([(0, unrecognisedOwnScreen), (30, calendar)], context: context)
        #expect(try LearningEvidencePreparation.prepare(acquisitions: [entry]).omissions.isEmpty)

        var silent = ScreenRecordingContextState()
        silent.begin(sessionID: session)
        silent.recordingDidStart(sessionID: session, startedAt: instant, timeZoneIdentifier: "UTC", monotonicStartSeconds: 9)
        #expect(silent.context?.ownInterfaceIntervals == nil)
    }

    @Test("The start reading taken in the native callback reaches the session even when finalization runs first")
    func callbackCarriesTheStartReading() throws {
        let session = UUID()
        let output = NSObject()
        let callbacks = ScreenRecordingCallbackProvenance(sessionID: session)
        callbacks.bind(outputID: ObjectIdentifier(output))
        var state = ScreenRecordingContextState()
        state.ownInterfaceChanged(inFront: true, monotonicSeconds: 90)
        state.begin(sessionID: session)
        callbacks.recordingDidStart(outputID: ObjectIdentifier(output), startedAt: instant,
                                    timeZoneIdentifier: "UTC", monotonicStartSeconds: 100)
        // The scene change is handled on the main actor before the start is reconciled there.
        state.ownInterfaceChanged(inFront: false, monotonicSeconds: 107)
        #expect(callbacks.reconcile(into: &state, sessionID: session, outputID: ObjectIdentifier(output), closing: true))
        state.captureEnded()
        #expect(state.context?.ownInterfaceIntervals?.intervals == [.init(startSeconds: 0, endSeconds: 7)])
    }

    @Test("Spans survive the recovery slot across a relaunch, and a sidecar without them loads as before")
    func recoveryRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4), .init(startSeconds: 60)])
        let saved = try context(spans)
        let slot = try PendingScreenRecordingStore(directory: directory).retain(source, recordingContext: saved)
        // A new store value stands for the next launch: only the files on disk remain.
        let relaunched = PendingScreenRecordingStore(directory: directory)
        #expect(try relaunched.recordingContext() == saved)
        #expect(try relaunched.recordingContext()?.ownInterfaceIntervals == spans)
        #expect(try relaunched.retain(slot) == slot)
        #expect(try relaunched.recoveredMetadata()?.recordingContext?.ownInterfaceIntervals == spans)

        // The sidecar of a recording made before spans were recorded.
        let plain = try context(nil)
        let old = #"{"recordingContext":{"id":"\#(plain.id.uuidString)","startedAt":\#(instant.timeIntervalSinceReferenceDate),"timeZoneIdentifier":"Europe/Paris"}}"#
        try Data(old.utf8).write(to: directory.appendingPathComponent("RecordingRecovery/recording-info.json"), options: .atomic)
        #expect(try relaunched.recordingContext() == plain)
    }

    @Test("Spans stay with the saved observation, so a later suggestion still excludes by time")
    func archiveRoundTrip() throws {
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4)])
        let entry = try recording([(0, unrecognisedOwnScreen), (30, calendar)], context: context(spans))
        let archive = try ObservationArchive(entries: [entry])
        let restored = try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive))
        let reloaded = try #require(restored.entry(id: entry.id))
        #expect(reloaded.recordingContext?.ownInterfaceIntervals == spans)
        #expect(reloaded.warnings.isEmpty)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [reloaded])
        #expect(reasons(evidence, in: reloaded) == [.ownInterfaceInFront, nil])
    }

    @Test("Attaching spans to a saved observation stales a suggestion made without them; a bare start does not")
    func spansEnterTheSourceRevision() throws {
        let digest = String(repeating: "ab", count: 32)
        let frames = try [(0.0, unrecognisedOwnScreen), (30.0, calendar)].map {
            try ObservationFrameEvidence(requestedTimeSeconds: $0.0, actualTimeSeconds: $0.0, outcome: .observed, text: $0.1)
        }
        let video = try ObservationVideoEvidence(durationSeconds: 40, frames: frames)
        let entry = try ObservationAcquisition(importedAt: instant, fileSHA256: digest,
            observedDate: ObservationObservedDate(date: instant, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .human, sourceKind: .video, sourceLabel: "Generated fixture",
            originalText: video.renderedText, videoEvidence: video)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let unit = try #require(evidence.units.first { $0.sampleID == frames[0].id })
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            .init(title: "Stretch", detail: "", kind: .custom, durationMinutes: 3,
                  citations: [.init(unitID: unit.id, quote: "07:30 Stretching then breakfast outside")])
        ], preserving: nil)

        var bare = try ObservationArchive(entries: [entry])
        #expect(try bare.attachRecordingContext(context(nil), to: entry.id, matchingFileSHA256: digest))
        #expect(proposal.isCurrent(archive: bare, baseRoutine: nil))

        var marked = try ObservationArchive(entries: [entry])
        let spans = OwnInterfaceIntervals([.init(startSeconds: 0, endSeconds: 4)])
        #expect(try marked.attachRecordingContext(context(spans), to: entry.id, matchingFileSHA256: digest))
        #expect(!proposal.isCurrent(archive: marked, baseRoutine: nil),
                "The cited frame is one a fresh preparation now leaves out.")
    }

    private func syntheticRecording() throws -> URL {
        try FileManager.default.createDirectory(at: ScreenRecordingFiles.directory, withIntermediateDirectories: true)
        let url = ScreenRecordingFiles.directory.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        // These bytes test storage ownership, not video decoding or successful capture.
        try Data("synthetic recording storage test".utf8).write(to: url)
        return url
    }
}
