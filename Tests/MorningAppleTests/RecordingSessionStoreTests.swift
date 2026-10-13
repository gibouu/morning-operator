import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// A session on disk made of fake segment files. No movie is encoded or recorded here:
/// each "segment" is a few bytes of text, enough to have a size and a fingerprint.
struct FakeSegmentedSession {
    let root: URL
    let store: RecordingSessionStore
    var manifest: RecordingSessionManifest
    var id: UUID { manifest.id }

    static let start = Date(timeIntervalSince1970: 1_791_000_000)

    init(policy: SegmentedRecordingPolicy = .provisional, intervals: OwnInterfaceIntervals? = nil) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("more-sessions-\(UUID().uuidString)")
        store = RecordingSessionStore(directory: root)
        manifest = RecordingSessionManifest(context: try ObservationRecordingContext(startedAt: Self.start,
            timeZoneIdentifier: "Europe/Paris", ownInterfaceIntervals: intervals), policy: policy)
        try store.create(manifest)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    static func bytes(_ index: Int) -> Data { Data("fake segment \(index), not a movie".utf8) }

    /// Begins a segment and leaves the writer's partial file on disk.
    mutating func beginSegment(startSeconds: Double) throws -> Int {
        let segment = try manifest.beginSegment(startSeconds: startSeconds)
        try store.save(manifest)
        try Self.bytes(segment.index).write(to: store.writingURL(sessionID: id, index: segment.index))
        return segment.index
    }

    /// One whole segment the way capture will do it: manifest first, file, rename, seal.
    mutating func recordSegment(from start: Double, to end: Double) async throws {
        let index = try beginSegment(startSeconds: start)
        try store.completeWrittenSegment(sessionID: id, index: index)
        let fingerprint = try await ObservationFileFingerprintService()
            .fingerprint(of: store.segmentURL(sessionID: id, index: index))
        try manifest.sealOpenSegment(endSeconds: end, fingerprint: fingerprint)
        try store.save(manifest)
    }

    mutating func recordSegments(_ count: Int) async throws {
        for index in 0..<count { try await recordSegment(from: Double(index) * 300, to: Double(index + 1) * 300) }
    }

    func fileExists(_ index: Int) -> Bool {
        FileManager.default.fileExists(atPath: store.segmentURL(sessionID: id, index: index).path)
    }

    func names() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: store.sessionDirectory(id).path).sorted()
    }
}

func fakeDerivation(_ acquisition: UUID? = UUID(), at date: Date = FakeSegmentedSession.start.addingTimeInterval(7_200))
    -> RecordingSegmentDerivation {
    .init(acquisitionID: acquisition, sampledFrameCount: 4, textCharacterCount: 200, analysedAt: date)
}

@Suite("Recording session storage")
struct RecordingSessionStoreTests {
    @Test("The manifest is saved before any segment and reloads unchanged")
    func createAndReload() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        #expect(try session.store.load(session.id) == session.manifest)
        #expect(try session.names() == ["session-manifest.json"])
        try await session.recordSegments(2)
        let reloaded = try RecordingSessionStore(directory: session.root).load(session.id)
        #expect(reloaded == session.manifest)
        #expect(reloaded.segments.map(\.state) == [.sealed, .sealed])
        #expect(reloaded.segments.map(\.byteCount) == [0, 1].map { Int64(FakeSegmentedSession.bytes($0).count) })
        #expect(try session.names() == ["segment-0000.mp4", "segment-0001.mp4", "session-manifest.json"])
        #expect(try session.store.sessionIDs() == [session.id])
        let permissions = try FileManager.default.attributesOfItem(atPath: session.store.manifestURL(session.id).path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        #expect(throws: RecordingSessionStoreError.sessionExists) { try session.store.create(session.manifest) }
        #expect(RecordingSessionManifest.maximumSegmentFileBytes == ObservationFileFingerprintService.maximumFileBytes,
                "The manifest's bound on a segment file is the fingerprint service's.")
    }

    @Test("A crash mid-segment loses that open segment only; sealed ones remain analysable")
    func crashMidSegment() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        _ = try session.beginSegment(startSeconds: 600)
        #expect(try session.names().contains("segment-0002.writing.mp4"))

        // Relaunch: a new store value, nothing in memory.
        let store = RecordingSessionStore(directory: session.root)
        let recovery = try store.reconcile(session.id)
        #expect(recovery.findings == [.sessionInterrupted, .lostOpenSegment(index: 2)])
        #expect(recovery.manifest.segments.map(\.state) == [.sealed, .sealed, .discarded])
        #expect(recovery.manifest.segments[2].lossReason == .interruptedWhileWriting)
        #expect(recovery.manifest.endReason == .interrupted)
        #expect(recovery.manifest.segmentsAwaitingAnalysis.map(\.index) == [0, 1])
        #expect(try session.names() == ["segment-0000.mp4", "segment-0001.mp4", "session-manifest.json"])
        #expect(try store.load(session.id) == recovery.manifest, "What recovery decided is what is saved.")
        // The lost tail is reported with an unknown end, not as a recovered or empty range.
        #expect(recovery.manifest.coverage.missing == [
            .init(segmentIndex: 2, range: .init(startSeconds: 600, endSeconds: nil),
                  reason: .interruptedWhileWriting, canRetry: false)
        ])
        // Running recovery again changes nothing.
        let again = try store.reconcile(session.id)
        #expect(again.findings.isEmpty)
        #expect(again.manifest == recovery.manifest)
    }

    @Test("A file completed just before the crash is kept for sealing, not thrown away")
    func completedButUnsealed() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(1)
        let index = try session.beginSegment(startSeconds: 300)
        try session.store.completeWrittenSegment(sessionID: session.id, index: index)

        let recovery = try session.store.reconcile(session.id)
        let size = Int64(FakeSegmentedSession.bytes(1).count)
        #expect(recovery.findings == [.sessionInterrupted, .completedButUnsealedSegment(index: 1, byteCount: size)])
        #expect(recovery.manifest.segments[1].state == .writing)
        #expect(session.fileExists(1))

        // The caller measures the file, then seals it: nothing of it was lost.
        var manifest = recovery.manifest
        let fingerprint = try await ObservationFileFingerprintService()
            .fingerprint(of: session.store.segmentURL(sessionID: session.id, index: 1))
        try manifest.sealOpenSegment(endSeconds: 540, fingerprint: fingerprint)
        try session.store.save(manifest)
        #expect(try session.store.reconcile(session.id).findings.isEmpty)
        #expect(try session.store.load(session.id).segmentsAwaitingAnalysis.map(\.index) == [0, 1])
    }

    @Test("An entry without its file: a sealed range is lost, an analysed one keeps its text")
    func entryWithoutFile() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let kept = fakeDerivation()
        try session.manifest.markAnalysed(index: 1, derivation: kept)
        try session.manifest.end(reason: .stoppedByPerson, atSeconds: 900)
        try session.store.save(session.manifest)
        try FileManager.default.removeItem(at: session.store.segmentURL(sessionID: session.id, index: 0))
        try FileManager.default.removeItem(at: session.store.segmentURL(sessionID: session.id, index: 1))

        let recovery = try session.store.reconcile(session.id)
        #expect(recovery.findings == [.rawMediaMissing(index: 0), .rawAlreadyReleased(index: 1)])
        #expect(recovery.manifest.segments.map(\.state) == [.discarded, .rawExpired, .sealed])
        #expect(recovery.manifest.segments[1].derivation == kept)
        #expect(recovery.manifest.coverage.missing == [
            .init(segmentIndex: 0, range: .init(startSeconds: 0, endSeconds: 300), reason: .rawMediaMissing, canRetry: false)
        ])
        #expect(session.fileExists(2))
    }

    @Test("A file without an entry is removed when it carries this store's names, else left alone")
    func fileWithoutEntry() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(1)
        try session.manifest.end(reason: .stoppedByPerson, atSeconds: 300)
        try session.store.save(session.manifest)
        let directory = session.store.sessionDirectory(session.id)
        // The last three only look like this store's names.
        for name in ["segment-0007.mp4", "segment-0003.writing.mp4", ".morning-save-AbCdEf",
                     "notes.txt", "segment-7.mp4", ".morning-save-notes.txt"] {
            try Data("stray".utf8).write(to: directory.appendingPathComponent(name))
        }
        let recovery = try session.store.reconcile(session.id)
        #expect(recovery.findings.filter { $0 == .removedUnlistedFile }.count == 3)
        #expect(recovery.findings.contains(.unexpectedItems(count: 3)))
        #expect(try session.names() == [".morning-save-notes.txt", "notes.txt", "segment-0000.mp4", "segment-7.mp4",
                                        "session-manifest.json"])
        // Forgetting leaves the same look-alikes in place.
        try session.store.forget(session.id)
        #expect(try session.names() == [".morning-save-notes.txt", "notes.txt", "segment-7.mp4"])
        #expect(recovery.manifest == session.manifest, "Unlisted files change nothing in the manifest.")
    }

    @Test("A sealed file that changed size, and a link in its place, are never analysed")
    func changedOrLinkedFile() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        try session.manifest.end(reason: .stoppedByPerson, atSeconds: 600)
        try session.store.save(session.manifest)
        let outside = session.root.appendingPathComponent("outside.mp4")
        try Data("someone else's file".utf8).write(to: outside)
        try Data("shorter".utf8).write(to: session.store.segmentURL(sessionID: session.id, index: 0))
        let linked = session.store.segmentURL(sessionID: session.id, index: 1)
        try FileManager.default.removeItem(at: linked)
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: outside)

        let recovery = try session.store.reconcile(session.id)
        #expect(recovery.findings == [.rawMediaChanged(index: 0), .rawMediaChanged(index: 1)])
        #expect(recovery.manifest.segments.map(\.state) == [.discarded, .discarded])
        #expect(recovery.manifest.segments.map(\.lossReason) == [.rawMediaChanged, .rawMediaChanged])
        #expect(try session.names() == ["session-manifest.json"])
        #expect(try Data(contentsOf: outside) == Data("someone else's file".utf8), "The link was removed, not its target.")
    }

    @Test("Raw media is released only for an analysed segment, manifest first")
    func rawRelease() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        #expect(throws: RecordingSessionManifestError.invalidTransition(index: 0, from: .sealed)) {
            try session.store.releaseRaw(sessionID: session.id, index: 0)
        }
        #expect(session.fileExists(0), "A sealed segment's text is not saved yet: its file stays.")

        let kept = fakeDerivation()
        try session.manifest.markAnalysed(index: 0, derivation: kept)
        try session.store.save(session.manifest)
        let released = try session.store.releaseRaw(sessionID: session.id, index: 0)
        #expect(!session.fileExists(0))
        #expect(session.fileExists(1))
        #expect(released.segments[0].state == .rawExpired)
        #expect(released.segments[0].derivation == kept)
        #expect(try session.store.load(session.id) == released)

        // A crash after the manifest was saved and before the file was removed: the file is
        // a leftover the manifest no longer wants, and recovery finishes the removal.
        try FakeSegmentedSession.bytes(0).write(to: session.store.segmentURL(sessionID: session.id, index: 0))
        let recovery = try session.store.reconcile(session.id)
        #expect(recovery.findings.contains(.removedLeftoverRaw(index: 0)))
        #expect(!session.fileExists(0))
        #expect(recovery.manifest.segments[0].derivation == kept)
    }

    @Test("Raw media expires by the policy's retention, on an injected clock")
    func rawExpiryByClock() async throws {
        let policy = try SegmentedRecordingPolicy(identifier: "retention-test", maximumSegmentDurationSeconds: 300,
            maximumSegmentBytes: 64 * 1_048_576, segmentByteOvershootAllowance: 0, maximumSessionDurationSeconds: 5_400,
            segmentTimingToleranceSeconds: 2, framesPerSegment: 12, maximumSessionFrames: 216, maximumSessionTextCharacters: 180_000,
            maximumUnreleasedRawSegments: 18, minimumFreeBytesReserve: 0, analysedRawRetentionSeconds: 3_600,
            maximumAnalysisAttempts: 3)
        var session = try FakeSegmentedSession(policy: policy)
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        let analysedAt = FakeSegmentedSession.start.addingTimeInterval(7_200)
        try session.manifest.markAnalysed(index: 0, derivation: fakeDerivation(at: analysedAt))
        try session.store.save(session.manifest)

        let early = try session.store.releaseExpiredRaw(sessionID: session.id, now: analysedAt.addingTimeInterval(3_599))
        #expect(early.segments[0].state == .analysed)
        #expect(session.fileExists(0))
        let due = try session.store.releaseExpiredRaw(sessionID: session.id, now: analysedAt.addingTimeInterval(3_600))
        #expect(due.segments.map(\.state) == [.rawExpired, .sealed])
        #expect(!session.fileExists(0))
        #expect(session.fileExists(1), "A segment still waiting for analysis never expires by time.")
        #expect(due.segments[0].derivation?.textCharacterCount == 200)
    }

    @Test("Forgetting a session removes what it lists and nothing else")
    func forgetting() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        _ = try session.beginSegment(startSeconds: 600)
        // A second session in the same store, a stray file, a link, and a file outside.
        var other = RecordingSessionManifest(context: try ObservationRecordingContext(
            startedAt: FakeSegmentedSession.start.addingTimeInterval(86_400), timeZoneIdentifier: "Europe/Paris"))
        try session.store.create(other)
        try other.beginSegment(startSeconds: 0)
        try session.store.save(other)
        try Data("other".utf8).write(to: session.store.segmentURL(sessionID: other.id, index: 0))
        let directory = session.store.sessionDirectory(session.id)
        try Data("keep".utf8).write(to: directory.appendingPathComponent("notes.txt"))
        let outside = session.root.appendingPathComponent("outside.mp4")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("segment-0009.mp4"),
                                                   withDestinationURL: outside)

        try session.store.forget(session.id)
        #expect(try session.names() == ["notes.txt"], "An item this store never wrote keeps the folder in place.")
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
        #expect(try session.store.load(other.id) == other)
        #expect(FileManager.default.fileExists(atPath: session.store.segmentURL(sessionID: other.id, index: 0).path))
        #expect(throws: RecordingSessionStoreError.unreadableManifest) { try session.store.load(session.id) }
        try session.store.forget(session.id)

        // With nothing unexpected inside, the folder goes too.
        try session.store.forget(other.id)
        #expect(!FileManager.default.fileExists(atPath: session.store.sessionDirectory(other.id).path))
        #expect(try session.store.sessionIDs() == [session.id], "Only the folder holding the stray note remains.")
        try session.store.forgetAll()
        try session.store.forget(UUID())
    }

    @Test("A session whose manifest cannot be read can still be forgotten")
    func forgettingWithUnreadableManifest() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(2)
        try Data("{ not json".utf8).write(to: session.store.manifestURL(session.id))
        #expect(throws: RecordingSessionStoreError.unreadableManifest) { try session.store.reconcile(session.id) }
        #expect(session.fileExists(0) && session.fileExists(1), "A manifest that cannot be read changes nothing.")
        try session.store.forget(session.id)
        #expect(!FileManager.default.fileExists(atPath: session.store.sessionDirectory(session.id).path))
    }

    @Test("A manifest that breaks a rule, names another session, or is a link is refused")
    func loadFailsClosed() async throws {
        var session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        try await session.recordSegments(3)
        let url = session.store.manifestURL(session.id)
        let saved = try Data(contentsOf: url)
        func rewrite(_ edit: (inout [String: Any]) -> Void) throws {
            var envelope = try #require(JSONSerialization.jsonObject(with: saved) as? [String: Any])
            var value = try #require(envelope["value"] as? [String: Any])
            edit(&value)
            envelope["value"] = value
            try JSONSerialization.data(withJSONObject: envelope).write(to: url)
        }
        try rewrite { $0["formatVersion"] = 2 }
        #expect(throws: RecordingSessionStoreError.manifestRejected(.unsupportedVersion(2))) { try session.store.load(session.id) }
        try rewrite { value in
            var segments = value["segments"] as! [[String: Any]]
            segments.remove(at: 1)
            value["segments"] = segments
        }
        #expect(throws: RecordingSessionStoreError.manifestRejected(.segmentIndexGap(expected: 1, found: 2))) {
            try session.store.load(session.id)
        }
        try rewrite { value in
            var segments = value["segments"] as! [[String: Any]]
            segments[2]["startSeconds"] = 450
            value["segments"] = segments
        }
        #expect(throws: RecordingSessionStoreError.manifestRejected(.overlappingTimeRanges(2))) {
            try session.store.reconcile(session.id)
        }
        #expect(session.fileExists(0) && session.fileExists(1) && session.fileExists(2))

        // A valid manifest of another session placed in this folder cannot address it.
        let other = RecordingSessionManifest(context: try ObservationRecordingContext(
            startedAt: FakeSegmentedSession.start, timeZoneIdentifier: "Europe/Paris"))
        try session.store.create(other)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.copyItem(at: session.store.manifestURL(other.id), to: url)
        #expect(throws: RecordingSessionStoreError.sessionMismatch) { try session.store.load(session.id) }

        // A link at the manifest's name is neither read nor written through.
        let target = session.root.appendingPathComponent("elsewhere.json")
        try saved.write(to: target)
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
        #expect(throws: RecordingSessionStoreError.unreadableManifest) { try session.store.load(session.id) }
        #expect(throws: RecordingSessionStoreError.unreadableManifest) { try session.store.save(session.manifest) }
        #expect(try Data(contentsOf: target) == saved)
    }

    @Test("A linked session folder is never followed")
    func linkedSessionFolder() throws {
        let session = try FakeSegmentedSession()
        defer { session.cleanUp() }
        let elsewhere = session.root.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try Data("victim".utf8).write(to: elsewhere.appendingPathComponent("segment-0000.mp4"))
        let linkedID = UUID()
        try FileManager.default.createSymbolicLink(at: session.store.sessionDirectory(linkedID), withDestinationURL: elsewhere)
        #expect(throws: RecordingSessionStoreError.unsafeLocation) { try session.store.load(linkedID) }
        #expect(throws: RecordingSessionStoreError.unsafeLocation) { try session.store.reconcile(linkedID) }
        #expect(throws: RecordingSessionStoreError.unsafeLocation) { try session.store.forget(linkedID) }
        #expect(try session.store.sessionIDs() == [session.id])
        #expect(FileManager.default.fileExists(atPath: elsewhere.appendingPathComponent("segment-0000.mp4").path))
    }

    @Test("Only names this store writes are treated as its segment files")
    func ownedNames() {
        #expect(RecordingSessionStore.segmentFileName(7) == "segment-0007.mp4")
        #expect(RecordingSessionStore.writingFileName(255) == "segment-0255.writing.mp4")
        #expect(RecordingSessionStore.segmentIndex(inFileName: "segment-0007.mp4") == 7)
        #expect(RecordingSessionStore.segmentIndex(inFileName: "segment-0007.writing.mp4") == 7)
        #expect(RecordingSessionStore.isStagingFileName(".morning-save-a1B2c3"))
        for name in [".morning-save-notes.txt", ".morning-save-", ".morning-save-abcde", ".morning-save-abcdefg",
                     ".morning-save-abc/ef", "morning-save-abcdef"] {
            #expect(!RecordingSessionStore.isStagingFileName(name), "\(name)")
        }
        for name in ["segment-7.mp4", "segment-0256.mp4", "segment-00a7.mp4", "segment-0007.mov", "../segment-0007.mp4",
                     "segment-0007.mp4/", "session-manifest.json", "segment--001.mp4"] {
            #expect(RecordingSessionStore.segmentIndex(inFileName: name) == nil, "\(name)")
        }
    }
}
