import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Recording recovery storage")
struct PendingScreenRecordingStoreTests {
    @Test func handoffSurvivesReloadAndDoesNotDeleteUntilExplicitRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let context = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_123),
                                                       timeZoneIdentifier: "Europe/Paris")
        let saved = try storage.retain(source, interruptionNote: "The system interrupted this recording.",
                                       recordingContext: context)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: saved) == Data("synthetic recording storage test".utf8))
        // A failed or cancelled worker has no cleanup callback: the same single slot remains.
        let reloaded = PendingScreenRecordingStore(directory: directory)
        #expect(try reloaded.recover() == saved)
        #expect(try reloaded.interruptionNote() == "The system interrupted this recording.")
        #expect(try reloaded.recordingContext() == context)
        #expect(try reloaded.recoveredMetadata() == .init(
            interruptionNote: "The system interrupted this recording.", recordingContext: context))
        #expect(try reloaded.retain(saved) == saved)
        #expect(try reloaded.recordingContext() == context, "A retry without a live recorder retains the saved provenance.")
        try reloaded.remove()
        #expect(try reloaded.recover() == nil)
        #expect(try reloaded.recordingContext() == nil)
        #expect(try reloaded.interruptionNote() == nil)
    }

    @Test("Legacy and orphaned metadata never acquire an invented session date")
    func legacyAndOrphanedMetadata() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try syntheticRecording()
        let next = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(first)
            _ = try? ScreenRecordingFiles.removeIfOwned(next)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(first)
        let metadata = directory.appendingPathComponent("RecordingRecovery/recording-info.json")
        try Data(#"{"interruptionNote":"Legacy interruption"}"#.utf8).write(to: metadata, options: .atomic)
        #expect(try storage.interruptionNote() == "Legacy interruption")
        #expect(try storage.recordingContext() == nil)

        let context = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_123),
                                                       timeZoneIdentifier: "Europe/Paris")
        let encodedContext = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context))
        let orphan = try JSONSerialization.data(withJSONObject: [
            "interruptionNote": "Old session", "recordingContext": encodedContext
        ])
        try orphan.write(to: metadata, options: .atomic)
        try FileManager.default.removeItem(at: saved)
        #expect(try storage.recordingContext() == nil)
        #expect(try storage.interruptionNote() == nil)
        _ = try storage.retain(next)
        #expect(try storage.recordingContext() == nil, "The new recording cannot inherit orphaned metadata.")
        #expect(try storage.interruptionNote() == nil)
    }

    @Test("An occupied recovery slot retains its own metadata when another handoff is rejected")
    func rejectedHandoffDoesNotReplaceContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try syntheticRecording()
        let second = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(first)
            _ = try? ScreenRecordingFiles.removeIfOwned(second)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let firstContext = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_000),
                                                           timeZoneIdentifier: "UTC")
        let nextContext = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_100),
                                                          timeZoneIdentifier: "Europe/Paris")
        _ = try storage.retain(first, recordingContext: firstContext)
        #expect(throws: PendingScreenRecordingError.anotherRecordingPending) {
            try storage.retain(second, recordingContext: nextContext)
        }
        #expect(try storage.recordingContext() == firstContext)
        #expect(FileManager.default.fileExists(atPath: second.path))
    }

    @Test func occupiedSlotPreservesBothFilesAndRejectsUnrelatedImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = try syntheticRecording()
        let second = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(first)
            _ = try? ScreenRecordingFiles.removeIfOwned(second)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(first)
        #expect(throws: PendingScreenRecordingError.anotherRecordingPending) { try storage.retain(second) }
        #expect(FileManager.default.fileExists(atPath: second.path))
        #expect(try storage.recover() == saved)
        let unrelated = directory.appendingPathComponent("user-selected.mp4")
        try Data("user file".utf8).write(to: unrelated)
        #expect(throws: PendingScreenRecordingError.appOwnedRecordingRequired) { try storage.retain(unrelated) }
        try storage.remove()
        #expect(try Data(contentsOf: unrelated) == Data("user file".utf8))
    }

    @Test func strictRemovalClearsOrphanMetadataAndLinksButPreservesTargets() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("RecordingRecovery", isDirectory: true)
        try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true)
        let storage = PendingScreenRecordingStore(directory: directory)
        let metadata = recovery.appendingPathComponent("recording-info.json")
        try Data("malformed orphan metadata".utf8).write(to: metadata)
        try storage.removeAllOwnedData()
        #expect(!FileManager.default.fileExists(atPath: metadata.path))
        let external = directory.appendingPathComponent("external-original")
        try Data("retain original".utf8).write(to: external)
        try FileManager.default.createSymbolicLink(at: storage.recordingURL, withDestinationURL: external)
        try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: directory.appendingPathComponent("missing-target"))
        let unrelated = recovery.appendingPathComponent("unrelated.json")
        try Data("keep".utf8).write(to: unrelated)
        try storage.removeAllOwnedData()
        try storage.removeAllOwnedData()
        #expect(try FileManager.default.contentsOfDirectory(atPath: recovery.path) == ["unrelated.json"])
        #expect(try Data(contentsOf: external) == Data("retain original".utf8))
    }

    @Test func strictRemovalRefusesUnexpectedDirectoryAndCanRetry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recovery = directory.appendingPathComponent("RecordingRecovery", isDirectory: true)
        let metadata = recovery.appendingPathComponent("recording-info.json", isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let child = metadata.appendingPathComponent("preserved")
        try Data("never recurse".utf8).write(to: child)
        let storage = PendingScreenRecordingStore(directory: directory)
        #expect(throws: RecordingCleanupError.unexpectedFileType) { try storage.removeAllOwnedData() }
        #expect(try Data(contentsOf: child) == Data("never recurse".utf8))
        try FileManager.default.removeItem(at: metadata)
        try Data("repaired fixture".utf8).write(to: metadata)
        try storage.removeAllOwnedData()
        #expect(try FileManager.default.contentsOfDirectory(atPath: recovery.path).isEmpty)
    }

    @Test("A missing legacy sidecar is unknown metadata, not an invented recording start")
    func absentLegacySidecarPermitsRetryWithoutProvenance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        #expect(try storage.recoveredMetadata() == nil)
        let saved = try storage.retain(source)
        let metadata = directory.appendingPathComponent("RecordingRecovery/recording-info.json")
        try FileManager.default.removeItem(at: metadata)
        #expect(try storage.recoveredMetadata() == PendingScreenRecordingMetadata())
        #expect(try storage.retain(saved) == saved)
        #expect(!FileManager.default.fileExists(atPath: metadata.path), "Retry must not invent a sidecar or timestamp.")
    }

    @Test("Malformed present metadata blocks retry and preserves both files", arguments: [
        "{not-json",
        #"{"interruptionNote":42}"#,
        #"{"recordingContext":"not-a-context"}"#,
        #"{"recordingContext":{"id":"00000000-0000-4000-8000-000000000001","startedAt":0,"timeZoneIdentifier":"invalid/zone"}}"#
    ])
    func malformedMetadataIsNotSilentlyDiscarded(_ contents: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(source)
        let originalBytes = try Data(contentsOf: saved)
        let metadata = directory.appendingPathComponent("RecordingRecovery/recording-info.json")
        let malformed = Data(contents.utf8)
        try malformed.write(to: metadata, options: .atomic)
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.recoveredMetadata() }
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.retain(saved) }
        #expect(try Data(contentsOf: saved) == originalBytes)
        #expect(try Data(contentsOf: metadata) == malformed)
        try storage.remove()
        #expect(try storage.recover() == nil)
        #expect(!FileManager.default.fileExists(atPath: metadata.path), "Explicit discard remains available without decoding.")
    }

    @Test("One immutable metadata read keeps its note and context together")
    func recoveredMetadataSnapshotDoesNotChangeAfterReplacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let first = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_001),
                                                    timeZoneIdentifier: "Europe/Paris")
        _ = try storage.retain(source, interruptionNote: "First session", recordingContext: first)
        let snapshot = try #require(try storage.recoveredMetadata())
        let next = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_101),
                                                   timeZoneIdentifier: "UTC")
        let replacement = PendingScreenRecordingMetadata(interruptionNote: "Second session", recordingContext: next)
        let metadata = directory.appendingPathComponent("RecordingRecovery/recording-info.json")
        try JSONEncoder().encode(replacement).write(to: metadata, options: .atomic)
        #expect(snapshot.interruptionNote == "First session")
        #expect(snapshot.recordingContext == first)
        #expect(try storage.recoveredMetadata() == replacement)
    }

    @Test("Recovery rejects linked or oversized metadata without following or deleting it")
    func unsafeMetadataRemainsIntactUntilExplicitDiscard() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let source = try syntheticRecording()
        defer {
            try? FileManager.default.removeItem(at: directory)
            _ = try? ScreenRecordingFiles.removeIfOwned(source)
        }
        let storage = PendingScreenRecordingStore(directory: directory)
        let saved = try storage.retain(source)
        let metadata = directory.appendingPathComponent("RecordingRecovery/recording-info.json")
        let external = directory.appendingPathComponent("external-metadata")
        let sentinel = Data(#"{"interruptionNote":"External fixture must stay unchanged"}"#.utf8)
        try sentinel.write(to: external)
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: external)
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.recoveredMetadata() }
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.retain(saved) }
        #expect(try Data(contentsOf: external) == sentinel)
        try FileManager.default.removeItem(at: metadata)
        try FileManager.default.createSymbolicLink(at: metadata, withDestinationURL: directory.appendingPathComponent("missing-target"))
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.recoveredMetadata() }
        try FileManager.default.removeItem(at: metadata)
        let oversized = Data(repeating: 0x20, count: 64 * 1_024 + 1)
        try oversized.write(to: metadata)
        #expect(throws: PendingScreenRecordingError.unreadableMetadata) { try storage.recoveredMetadata() }
        #expect(try Data(contentsOf: metadata) == oversized)
        #expect(try storage.recover() == saved)
        try storage.remove()
        #expect(try Data(contentsOf: external) == sentinel)
    }

    private func syntheticRecording() throws -> URL {
        try FileManager.default.createDirectory(at: ScreenRecordingFiles.directory, withIntermediateDirectories: true)
        let url = ScreenRecordingFiles.directory.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        // These bytes test storage ownership, not video decoding or successful capture.
        try Data("synthetic recording storage test".utf8).write(to: url)
        return url
    }
}
