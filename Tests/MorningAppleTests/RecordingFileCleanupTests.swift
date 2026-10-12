import Foundation
import Testing
@testable import MorningApple

@Suite("Strict app-owned recording cleanup")
struct RecordingFileCleanupTests {
    @Test func recordingNamespaceIsIsolatedAndMalformedTestLaunchFailsClosed() throws {
        let temporary = URL(fileURLWithPath: "/tmp/recording-policy-fixture")
        let workspace = temporary.appendingPathComponent("workspace-\(UUID().uuidString)")
        let valid = ["--ui-testing", "--ui-testing-workspace=\(UUID().uuidString)"]
        try ScreenRecordingFiles.validateTestNamespace(arguments: valid)
        let testDirectory = ScreenRecordingFiles.recordingDirectory(arguments: valid,
            workspaceDirectory: workspace, temporaryDirectory: temporary)
        let ordinary = ScreenRecordingFiles.recordingDirectory(arguments: [],
            workspaceDirectory: workspace, temporaryDirectory: temporary)
        #expect(testDirectory == workspace.appendingPathComponent("MorningOperatorRecordings", isDirectory: true))
        #expect(testDirectory != ordinary)
        #expect(throws: RecordingCleanupError.invalidTestWorkspace) {
            try ScreenRecordingFiles.validateTestNamespace(arguments: ["--ui-testing"])
        }
        #expect(throws: RecordingCleanupError.invalidTestWorkspace) {
            try ScreenRecordingFiles.validateTestNamespace(arguments: ["--ui-testing", "--ui-testing-workspace=ordinary"])
        }
    }

    @Test func sweepOnlyRemovesExactUUIDRecordingNamesAndIsIdempotent() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("first/MorningOperatorRecordings", isDirectory: true)
        let second = root.appendingPathComponent("second/MorningOperatorRecordings", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let ownedName = "morning-\(UUID().uuidString).mp4"
        let owned = first.appendingPathComponent(ownedName)
        let otherWorkspace = second.appendingPathComponent(ownedName)
        try Data("owned synthetic bytes".utf8).write(to: owned)
        try Data("other workspace".utf8).write(to: otherWorkspace)
        let unrelated = ["imported.mp4", "morning-user.mp4", "morning-\(UUID().uuidString).mov", "morning-\(UUID().uuidString).mp4.backup"]
        for name in unrelated { try Data("external original".utf8).write(to: first.appendingPathComponent(name)) }
        let unrelatedDirectory = first.appendingPathComponent("user-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelatedDirectory, withIntermediateDirectories: false)
        try RecordingFileCleanup.removeRecordings(in: first)
        try RecordingFileCleanup.removeRecordings(in: first)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
        #expect(try Data(contentsOf: otherWorkspace) == Data("other workspace".utf8))
        for name in unrelated { #expect(try Data(contentsOf: first.appendingPathComponent(name)) == Data("external original".utf8)) }
        #expect(FileManager.default.fileExists(atPath: unrelatedDirectory.path))
    }

    @Test func ownedSymlinkIsUnlinkedWithoutDeletingItsTarget() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: false)
        let target = root.appendingPathComponent("external-original.mp4")
        try Data("keep this original".utf8).write(to: target)
        let link = recordings.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let dangling = recordings.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: root.appendingPathComponent("absent"))
        try RecordingFileCleanup.removeRecordings(in: recordings)
        #expect(try FileManager.default.contentsOfDirectory(atPath: recordings.path).isEmpty)
        #expect(try Data(contentsOf: target) == Data("keep this original".utf8))
    }

    @Test func linkedDirectoryIsRefusedAndOwnedNameDirectoryRemainsRetryable() throws {
        let root = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let actual = root.appendingPathComponent("actual", isDirectory: true)
        try FileManager.default.createDirectory(at: actual, withIntermediateDirectories: false)
        let owned = actual.appendingPathComponent("morning-\(UUID().uuidString).mp4")
        try Data("must remain".utf8).write(to: owned)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: actual)
        #expect(throws: RecordingCleanupError.unsafeDirectory) { try RecordingFileCleanup.removeRecordings(in: alias) }
        #expect(try Data(contentsOf: owned) == Data("must remain".utf8))
        try FileManager.default.removeItem(at: owned)
        try FileManager.default.createDirectory(at: owned, withIntermediateDirectories: false)
        let child = owned.appendingPathComponent("do-not-traverse")
        try Data("retained".utf8).write(to: child)
        #expect(throws: RecordingCleanupError.unexpectedFileType) { try RecordingFileCleanup.removeRecordings(in: actual) }
        #expect(try Data(contentsOf: child) == Data("retained".utf8))
        // Explicitly repair only this test fixture, then retry the same cleanup policy.
        try FileManager.default.removeItem(at: owned)
        try Data("now a recording file".utf8).write(to: owned)
        try RecordingFileCleanup.removeRecordings(in: actual)
        #expect(!FileManager.default.fileExists(atPath: owned.path))
    }

    private func fixtureDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-cleanup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

@Suite("Recording shutdown wait policy")
@MainActor
struct ScreenRecordingCleanupBarrierTests {
    @Test func waitsForLateStartThenCaptureAndWriterBeforeReportingStopped() async throws {
        let states = [
            ScreenRecordingCleanupStatus(startPending: true, resourcesAttached: true),
            ScreenRecordingCleanupStatus(stopPending: true, resourcesAttached: true, captureMayBeActive: true),
            ScreenRecordingCleanupStatus(resourcesAttached: true),
            ScreenRecordingCleanupStatus()
        ]
        var index = 0
        try await ScreenRecordingCleanupBarrier.wait(status: { states[index] }, pause: { index += 1 })
        #expect(index == 3, "A pending start or writer is not evidence of completed cleanup.")
    }

    @Test func timeoutAndStopFailureNeverReportSuccess() async throws {
        await #expect(throws: RecordingCleanupError.captureStopUnconfirmed) {
            try await ScreenRecordingCleanupBarrier.wait(timeout: .zero,
                status: { .init(startPending: true, resourcesAttached: true) },
                pause: { Issue.record("A zero deadline must not wait.") })
        }
        await #expect(throws: RecordingCleanupError.captureStopUnconfirmed) {
            try await ScreenRecordingCleanupBarrier.wait(
                status: { .init(resourcesAttached: true, needsStopRetry: true) },
                pause: { Issue.record("A native stop failure needs an explicit retry.") })
        }
        try await ScreenRecordingCleanupBarrier.wait(timeout: .zero, status: { .init() })
    }

    @Test func cancelledWaitDoesNotConvertIntoStoppedState() async {
        await #expect(throws: CancellationError.self) {
            try await ScreenRecordingCleanupBarrier.wait(status: { .init(resourcesAttached: true) },
                pause: { throw CancellationError() })
        }
    }
}
