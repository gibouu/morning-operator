import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Stands in for the workspace owner: the saved archive, and a log of which segments the
/// analysis was asked to extract. Extraction itself is faked; no movie is decoded.
private actor FakeWorkspace {
    private(set) var archive = ObservationArchive()
    private(set) var extracted: [Int] = []
    private var failing: Set<Int> = []
    private var cancelWhenReached: Int?
    private var cancelAfterSaving: Int?
    private var missingRawAtSaveTime: [Int] = []

    func fail(_ indexes: Set<Int>) { failing = indexes }
    func cancel(whenReached index: Int?) { cancelWhenReached = index }
    func cancel(afterSaving index: Int?) { cancelAfterSaving = index }
    func rawMissingWhenSaved() -> [Int] { missingRawAtSaveTime }
    func insert(_ acquisition: ObservationAcquisition) throws { try archive.insert(acquisition) }
    func deleteSession(_ id: UUID) throws -> [UUID] { try archive.deleteSession(id) }

    func saved(_ work: RecordingSegmentWork) -> RecordingSegmentDerivation? {
        SegmentedSessionEvidence.savedDerivation(for: work, in: archive, analysedAt: Date(timeIntervalSince1970: 0))
    }

    func analyse(_ work: RecordingSegmentWork) throws -> RecordingSegmentDerivation {
        let index = work.reference.segmentIndex
        extracted.append(index)
        if cancelWhenReached == index {
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
        if failing.contains(index) { throw ObservationFileFingerprintError.unreadableFile }
        let acquisition = try fakeAcquisition(for: work)
        // The raw file must still be there while its text is being saved.
        if !FileManager.default.fileExists(atPath: work.fileURL.path) { missingRawAtSaveTime.append(index) }
        // Describe the entry the archive holds, by the identifier it returned.
        let savedID = try archive.insert(acquisition)
        let saved = try #require(archive.entry(id: savedID))
        if cancelAfterSaving == index { withUnsafeCurrentTask { $0?.cancel() } }
        return SegmentedSessionEvidence.derivation(of: saved, analysedAt: FakeSegmentedSession.start.addingTimeInterval(7_200))
    }
}

/// Synthetic screen text for one segment: two frames, each with ordinary task content.
private func fakeEvidence(segment index: Int, times: [Double] = [60, 180], duration: Double = 300)
    throws -> ObservationVideoEvidence {
    let lines = ["09:15 Standup with the delivery team about release \(index)",
                 "Reply to Camille about the Thursday delivery schedule \(index)",
                 "Review the quarterly budget draft before the call \(index)"]
    return try ObservationVideoEvidence(durationSeconds: duration, frames: times.enumerated().map { offset, time in
        try ObservationFrameEvidence(requestedTimeSeconds: time, actualTimeSeconds: time, outcome: .observed,
                                     text: lines[offset % lines.count] + " (frame \(offset))")
    })
}

private func fakeAcquisition(for work: RecordingSegmentWork, times: [Double] = [60, 180],
                             duration: Double? = nil) throws -> ObservationAcquisition {
    try SegmentedSessionEvidence.acquisition(for: work,
        evidence: fakeEvidence(segment: work.reference.segmentIndex, times: times,
                               duration: duration ?? work.reference.endSeconds - work.reference.startSeconds),
        origin: .synthetic, sourceLabel: "Synthetic segment \(work.reference.segmentIndex)",
        importedAt: FakeSegmentedSession.start.addingTimeInterval(7_000))
}

private func run(_ session: FakeSegmentedSession, _ workspace: FakeWorkspace) async throws -> SegmentedSessionAnalysis.Result {
    try await SegmentedSessionAnalysis.run(sessionID: session.id, store: session.store,
        now: { FakeSegmentedSession.start.addingTimeInterval(7_300) },
        savedDerivation: { await workspace.saved($0) },
        analyse: { try await workspace.analyse($0) })
}

@Suite("Segmented session analysis")
struct SegmentedSessionAnalysisTests {
    @Test("Analysis goes segment by segment and releases each raw file after its text is saved")
    func analysesInOrder() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let workspace = FakeWorkspace()
        let result = try await run(session, workspace)
        #expect(result.analysedSegments == [0, 1, 2])
        #expect(result.failedSegments.isEmpty && result.recoveredSegments.isEmpty && !result.stoppedByCancellation)
        #expect(await workspace.extracted == [0, 1, 2])
        #expect(await workspace.rawMissingWhenSaved().isEmpty, "No raw file was removed before its text was saved.")
        #expect(result.manifest.segments.map(\.state) == [.rawExpired, .rawExpired, .rawExpired])
        #expect(try session.names() == ["session-manifest.json"])
        #expect(try session.store.load(session.id) == result.manifest)
        #expect(result.manifest.usedFrameCount == 6)
        let entries = await workspace.archive.entries(ofSession: session.id)
        #expect(entries.map(\.id) == result.manifest.segments.map(\.id))
        #expect(result.coverage.missing.isEmpty && result.coverage.waiting.isEmpty)

        // Nothing left to do: a second run analyses nothing and counts nothing twice.
        let again = try await run(session, workspace)
        #expect(again.analysedSegments.isEmpty && again.recoveredSegments.isEmpty)
        #expect(await workspace.extracted == [0, 1, 2])
        #expect(await workspace.archive.entries.count == 3)
        #expect(again.manifest == result.manifest)
    }

    @Test("Cancellation mid-analysis leaves a consistent manifest, and the next run resumes")
    func cancellationAndResume() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let workspace = FakeWorkspace()
        await workspace.cancel(whenReached: 1)
        let current = session
        let first = try await Task { try await run(current, workspace) }.value
        #expect(first.stoppedByCancellation)
        #expect(first.analysedSegments == [0])
        #expect(first.failedSegments.isEmpty, "A cancelled segment has not failed.")
        #expect(first.manifest.segments.map(\.state) == [.rawExpired, .sealed, .sealed])
        #expect(try session.store.load(session.id) == first.manifest)
        #expect(!session.fileExists(0) && session.fileExists(1) && session.fileExists(2))
        #expect(await workspace.archive.entries.count == 1)
        #expect(try session.store.reconcile(session.id).manifest.segments.map(\.state) == [.rawExpired, .sealed, .sealed],
                "The manifest and the folder agree after the cancellation.")
        #expect(first.coverage.waiting.map(\.segmentIndex) == [1, 2])

        await workspace.cancel(whenReached: nil)
        let second = try await run(session, workspace)
        #expect(second.analysedSegments == [1, 2])
        #expect(!second.stoppedByCancellation)
        #expect(await workspace.extracted == [0, 1, 1, 2], "Segment 0 was not analysed again.")
        #expect(await workspace.archive.entries.count == 3)
        #expect(second.manifest.usedFrameCount == 6, "Nothing was counted twice.")
    }

    @Test("A cancellation that arrives after a segment's text was saved still records that segment")
    func cancellationAfterSave() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        let workspace = FakeWorkspace()
        await workspace.cancel(afterSaving: 0)
        let current = session
        let result = try await Task { try await run(current, workspace) }.value
        #expect(result.stoppedByCancellation)
        #expect(result.analysedSegments == [0])
        #expect(result.manifest.segments.map(\.state) == [.rawExpired, .sealed])
        #expect(await workspace.archive.entries.count == 1)
        #expect(await workspace.extracted == [0])
    }

    @Test("A segment saved just before an interruption is recorded on resume, not analysed again")
    func resumeAfterSaveWithoutManifestUpdate() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let workspace = FakeWorkspace()
        // The crash: segment 1's observation reached the archive; the manifest still says sealed.
        let work = try SegmentedSessionEvidence.work(forSegment: 1, in: session.manifest, store: session.store)
        try await workspace.insert(fakeAcquisition(for: work))

        let result = try await run(session, workspace)
        #expect(result.recoveredSegments == [1])
        #expect(result.analysedSegments == [0, 2])
        #expect(await workspace.extracted == [0, 2])
        #expect(await workspace.archive.entries.count == 3)
        #expect(result.manifest.segments[1].derivation?.acquisitionID == session.manifest.segments[1].id)
        #expect(result.manifest.usedFrameCount == 6)
    }

    @Test("A failed segment is reported with its time range and does not stop the others")
    func failedSegmentDoesNotPoisonTheSession() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        try session.manifest.end(reason: .stoppedByPerson, atSeconds: 900)
        try session.store.save(session.manifest)
        let workspace = FakeWorkspace()
        await workspace.fail([1])

        let result = try await run(session, workspace)
        #expect(result.analysedSegments == [0, 2])
        #expect(result.failedSegments == [1])
        #expect(result.manifest.segments.map(\.state) == [.rawExpired, .failed, .rawExpired])
        #expect(result.coverage.missing == [
            .init(segmentIndex: 1, range: .init(startSeconds: 300, endSeconds: 600), reason: .analysisFailed, canRetry: true)
        ])
        #expect(result.coverage.analysed.map(\.range) == [
            .init(startSeconds: 0, endSeconds: 300), .init(startSeconds: 600, endSeconds: 900)
        ])
        #expect(!result.coverage.isComplete)
        #expect(session.fileExists(1), "The raw file of a failed segment is kept for another attempt.")
        #expect(!session.fileExists(0) && !session.fileExists(2))

        // Two more failures use up the attempts; after that the segment is left alone.
        _ = try await run(session, workspace)
        let third = try await run(session, workspace)
        #expect(third.manifest.segments[1].failure?.attempts == 3)
        #expect(third.coverage.missing.first?.canRetry == false)
        let fourth = try await run(session, workspace)
        #expect(fourth.failedSegments.isEmpty)
        #expect(await workspace.extracted == [0, 1, 2, 1, 1])
        #expect(session.fileExists(1))
        #expect(await workspace.archive.entries.count == 2)
    }

    @Test("A segment whose bytes changed after sealing is given up, never analysed")
    func changedBytes() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let url = session.store.segmentURL(sessionID: session.id, index: 1)
        var bytes = try Data(contentsOf: url)
        bytes[0] ^= 0xFF
        try bytes.write(to: url)
        try FileManager.default.removeItem(at: session.store.segmentURL(sessionID: session.id, index: 2))
        let workspace = FakeWorkspace()

        let result = try await run(session, workspace)
        #expect(result.analysedSegments == [0])
        #expect(result.discardedSegments == [1, 2])
        #expect(await workspace.extracted == [0])
        #expect(result.manifest.segments.map(\.lossReason) == [nil, .rawMediaChanged, .rawMediaMissing])
        #expect(result.coverage.missing.map(\.reason) == [.rawMediaChanged, .rawMediaMissing])
        #expect(try session.names() == ["session-manifest.json"])
    }

    @Test("A segment whose bytes are already an ordinary observation fails; it is not merged into it")
    func sameBytesAlreadyArchived() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        let workspace = FakeWorkspace()
        // The same file was imported earlier as a plain video: an entry with no session.
        let evidence = try fakeEvidence(segment: 1)
        let imported = try ObservationAcquisition(fileSHA256: session.manifest.segments[1].fingerprint?.sha256,
            sourceKind: .video, sourceLabel: "Imported earlier", originalText: evidence.renderedText, videoEvidence: evidence)
        try await workspace.insert(imported)

        let result = try await run(session, workspace)
        #expect(result.analysedSegments == [0])
        #expect(result.failedSegments == [1])
        #expect(result.recoveredSegments.isEmpty, "An entry without the session's reference is not this segment.")
        #expect(session.fileExists(1), "Its raw file stays: nothing of the session holds its text.")
        #expect(result.coverage.missing.map(\.segmentIndex) == [1])
        #expect(await workspace.archive.entries(ofSession: session.id).map(\.id) == [session.manifest.segments[0].id])
        #expect(await workspace.archive.entry(id: imported.id) == imported)
    }

    @Test("An extraction over the segment's share is refused before it is saved")
    func budgetIsEnforced() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(1)
        let work = try SegmentedSessionEvidence.work(forSegment: 0, in: session.manifest, store: session.store)
        #expect(work.maximumFrames == 12)
        #expect(work.maximumTextCharacters == 10_000)
        #expect(throws: SegmentedSessionEvidenceError.budgetExceeded) {
            try fakeAcquisition(for: work, times: (0..<13).map { Double($0) * 20 })
        }
        // An extraction longer than the segment was not made from this segment's file. Its
        // late frames would escape the spans carried into the segment.
        #expect(work.maximumMediaSeconds == 302)
        #expect(throws: SegmentedSessionEvidenceError.evidenceOutsideSegment) {
            try fakeAcquisition(for: work, times: [60, 400], duration: 600)
        }
        #expect(throws: SegmentedSessionEvidenceError.evidenceOutsideSegment) {
            try fakeAcquisition(for: work, times: [60, 180], duration: 302.5)
        }
        _ = try fakeAcquisition(for: work, times: [60, 301], duration: 302)
        _ = try session.beginSegment(startSeconds: 300)
        #expect(throws: SegmentedSessionEvidenceError.segmentNotAnalysable) {
            try SegmentedSessionEvidence.work(forSegment: 1, in: session.manifest, store: session.store)
        }
    }

    @Test("Forgetting a session removes its observations and files, and no one else's")
    func forgettingTheSession() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        let workspace = FakeWorkspace()
        _ = try await run(session, workspace)
        let unrelated = try ObservationAcquisition(sourceKind: .text, sourceLabel: "Notes",
            originalText: "Stretched for ten minutes, then read the news")
        try await workspace.insert(unrelated)

        let removed = try await workspace.deleteSession(session.id)
        #expect(removed == session.manifest.segments.map(\.id))
        try session.store.forget(session.id)
        #expect(await workspace.archive.entries == [unrelated])
        #expect(!FileManager.default.fileExists(atPath: session.store.sessionDirectory(session.id).path))
        #expect(try await workspace.deleteSession(session.id).isEmpty)
    }
}

@Suite("A segmented session in the archive and the proposal builder")
struct SegmentedSessionEvidenceTests {
    /// Three sealed segments. MORE was in front across the first boundary (298 s to 302 s).
    private func makeManifest() throws -> RecordingSessionManifest {
        var manifest = RecordingSessionManifest(context: try ObservationRecordingContext(
            startedAt: FakeSegmentedSession.start, timeZoneIdentifier: "Europe/Paris",
            ownInterfaceIntervals: OwnInterfaceIntervals([.init(startSeconds: 298, endSeconds: 302)])))
        for index in 0..<3 {
            try manifest.beginSegment(startSeconds: Double(index) * 300)
            try manifest.sealOpenSegment(endSeconds: Double(index + 1) * 300,
                fingerprint: ObservationFileFingerprint(sha256: String(format: "%064x", index + 1), byteCount: 2_000))
        }
        return manifest
    }

    @Test("The existing proposal builder receives a session's segments in order, each frame attributed to its segment")
    func proposalBuilderInput() throws {
        let manifest = try makeManifest()
        let store = RecordingSessionStore(directory: FileManager.default.temporaryDirectory)
        // Frame times are in each file's own media time, as the extractor reports them.
        let frameTimes: [[Double]] = [[100, 299.5], [1.5, 150], [10, 200]]
        var archive = ObservationArchive()
        // Saved out of order on purpose: order comes from the reference, not from insertion.
        for index in [2, 0, 1] {
            let work = try SegmentedSessionEvidence.work(forSegment: index, in: manifest, store: store)
            try archive.insert(fakeAcquisition(for: work, times: frameTimes[index]))
        }
        let entries = archive.entries(ofSession: manifest.id)
        #expect(entries.map(\.id) == manifest.segments.map(\.id))
        #expect(entries.map { $0.sessionSegment?.segmentIndex } == [0, 1, 2])
        #expect(Set(entries.map { $0.observedDate?.dayKey }).count == 1, "One session is one observed day.")
        #expect(entries.map { $0.recordingContext?.startedAt } == [0, 300, 600].map {
            FakeSegmentedSession.start.addingTimeInterval($0)
        })

        let prepared = try LearningEvidencePreparation.prepare(acquisitions: entries)

        // Every unit names its segment's observation and its frame; session time follows.
        var sessionTimes: [Double] = []
        for unit in prepared.units {
            let entry = try #require(entries.first { $0.id == unit.acquisitionID })
            let reference = try #require(entry.sessionSegment)
            let frame = try #require(entry.videoEvidence?.frames.first { $0.id == unit.sampleID })
            #expect(unit.text == frame.text)
            #expect(frame.text.contains("release \(reference.segmentIndex)") || frame.text.contains("schedule \(reference.segmentIndex)"))
            sessionTimes.append(try #require(manifest.sessionSeconds(forSegment: reference.segmentIndex,
                                                                     mediaSeconds: frame.timeSeconds)))
        }
        #expect(sessionTimes == [100, 450, 610, 800], "Ordered on the session's clock, across segments.")
        #expect(prepared.sourceSnapshots.map(\.acquisitionID) == manifest.segments.map(\.id))

        // The span crossing the boundary leaves out the last frame of the first file and the
        // first frame of the second, each under its own observation.
        let omitted = prepared.omissions.filter { $0.reason == .ownInterfaceInFront }
        #expect(omitted.count == 2)
        #expect(omitted.map(\.acquisitionID) == [manifest.segments[0].id, manifest.segments[1].id])
        #expect(omitted[0].sampleID == entries[0].videoEvidence?.frames[1].id)
        #expect(omitted[1].sampleID == entries[1].videoEvidence?.frames[0].id)
        #expect(prepared.omissions.count == 2)
    }

    @Test("One segment is one observation: a second entry for the same segment is refused")
    func oneObservationPerSegment() throws {
        let manifest = try makeManifest()
        let store = RecordingSessionStore(directory: FileManager.default.temporaryDirectory)
        let work = try SegmentedSessionEvidence.work(forSegment: 0, in: manifest, store: store)
        let first = try fakeAcquisition(for: work)
        var archive = ObservationArchive()
        let id = try archive.insert(first)
        // The same file again, as a retry would produce: the existing entry is returned.
        let retry = try ObservationAcquisition(fileSHA256: work.fingerprint.sha256, observedDate: work.observedDate,
            origin: .synthetic, sourceKind: .video, sourceLabel: "Retry", originalText: first.originalText,
            videoEvidence: first.videoEvidence, recordingContext: nil, sessionSegment: work.reference)
        #expect(try archive.insert(retry) == id)
        #expect(archive.entries.count == 1)
        // Different bytes claiming the same place in the session.
        var plain = ObservationArchive()
        try plain.insert(try ObservationAcquisition(fileSHA256: work.fingerprint.sha256, sourceKind: .video,
            sourceLabel: "Imported earlier", originalText: first.originalText, videoEvidence: first.videoEvidence))
        // The same bytes saved earlier as an ordinary video: the segment is refused rather
        // than answered with an entry that has no place in the session.
        #expect(throws: ObservationArchiveError.duplicateDigest) { try plain.insert(first) }
        // The other way round is unchanged: a plain import of a segment's bytes finds it.
        #expect(try archive.insert(try ObservationAcquisition(fileSHA256: work.fingerprint.sha256, sourceKind: .video,
            sourceLabel: "Imported later", originalText: first.originalText, videoEvidence: first.videoEvidence)) == id)
        let impostor = try ObservationAcquisition(fileSHA256: String(repeating: "ab", count: 32),
            observedDate: work.observedDate, origin: .synthetic, sourceKind: .video, sourceLabel: "Other",
            originalText: first.originalText, videoEvidence: first.videoEvidence, sessionSegment: work.reference)
        #expect(throws: ObservationArchiveError.duplicateAcquisition) { try archive.insert(impostor) }
        #expect(throws: ObservationArchiveError.invalidSource) {
            try ObservationAcquisition(sourceKind: .text, sourceLabel: "Notes", originalText: "Read the news",
                                       sessionSegment: work.reference)
        }
        // Edits keep the reference.
        try archive.correct(id: id, text: "I answered Camille and reviewed the budget")
        try archive.assignObservedDate(id: id, value: nil)
        #expect(archive.entry(id: id)?.sessionSegment == work.reference)
    }

    @Test("An archive saved before sessions existed loads unchanged")
    func oldArchivesLoadUnchanged() throws {
        let old = Data("""
        {"entries":[
          {"id":"0B5C0F3E-5E0B-4E63-9A5B-0D5D2F3C7A11","importedAt":781000000,"origin":"human",
           "sourceKind":"text","sourceLabel":"Notes","originalText":"Stretched for ten minutes, then read the news",
           "frameReviews":[],"warnings":[]},
          {"id":"7E1D4C55-0C7F-4B51-8E2C-5F1B8E0A9C22","origin":"unknown","sourceKind":"manual",
           "sourceLabel":"Your written observation","originalText":"Made coffee and checked the calendar"}
        ]}
        """.utf8)
        let archive = try JSONDecoder().decode(ObservationArchive.self, from: old)
        #expect(archive.entries.count == 2)
        #expect(archive.entries.allSatisfy { $0.sessionSegment == nil })
        #expect(archive.entries[0].originalText == "Stretched for ten minutes, then read the news")
        #expect(archive.entries[0].importedAt == Date(timeIntervalSinceReferenceDate: 781_000_000))
        #expect(archive.entries(ofSession: UUID()).isEmpty)
        let encoded = try JSONEncoder().encode(archive)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("sessionSegment"),
                "An observation that is not a segment is written as before.")
        #expect(try JSONDecoder().decode(ObservationArchive.self, from: encoded) == archive)

        // A recording saved by today's single-file path, re-read with the new field absent.
        let evidence = try fakeEvidence(segment: 0)
        let recording = try ObservationAcquisition(fileSHA256: String(repeating: "cd", count: 32),
            sourceKind: .video, sourceLabel: "Screen recording", originalText: evidence.renderedText,
            videoEvidence: evidence, recordingContext: try ObservationRecordingContext(
                startedAt: FakeSegmentedSession.start, timeZoneIdentifier: "Europe/Paris"))
        let single = try JSONEncoder().encode(try ObservationArchive(entries: [recording]))
        #expect(!String(decoding: single, as: UTF8.self).contains("sessionSegment"))
        #expect(try JSONDecoder().decode(ObservationArchive.self, from: single).entries == [recording])
    }

    @Test("A session reference survives saving, and an unreadable one leaves an ordinary observation")
    func referencePersistence() throws {
        let manifest = try makeManifest()
        let store = RecordingSessionStore(directory: FileManager.default.temporaryDirectory)
        let work = try SegmentedSessionEvidence.work(forSegment: 1, in: manifest, store: store)
        let archive = try ObservationArchive(entries: [fakeAcquisition(for: work)])
        let encoded = try JSONEncoder().encode(archive)
        #expect(try JSONDecoder().decode(ObservationArchive.self, from: encoded) == archive)

        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var entries = try #require(object["entries"] as? [[String: Any]])
        var reference = try #require(entries[0]["sessionSegment"] as? [String: Any])
        reference["segmentIndex"] = -4
        entries[0]["sessionSegment"] = reference
        object["entries"] = entries
        let damaged = try JSONDecoder().decode(ObservationArchive.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(damaged.entries[0].sessionSegment == nil)
        #expect(damaged.entries[0].originalText == archive.entries[0].originalText, "The text is not lost with the reference.")
    }
}
