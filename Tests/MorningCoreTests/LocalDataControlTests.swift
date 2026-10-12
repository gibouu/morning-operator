import Foundation
import Testing
@testable import MorningCore

@Suite("Local privacy lifecycle")
struct LocalDataControlTests {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("morning-privacy-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func expectError(_ expected: LocalDataControlError, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected a privacy-control error") }
        catch { #expect(error as? LocalDataControlError == expected) }
    }

    @Test("An untouched workspace has no generation or personal marker contents")
    func initialStatusAndPrivateLock() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory)
        let state = try control.status()
        #expect(state.generation == nil)
        #expect(!state.forgetPending)
        #expect(state.activityLoggingAllowed)
        #expect(try control.withReadyAccess { $0 } == state)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [".morning-privacy-lock"])
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(".morning-privacy-lock").path)
        #expect((mode[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("A pending removal blocks ready access, retains its epoch and disables activity")
    func pendingForgetSurvivesRestartAndRejectsWrites() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory)
        let pending = try control.beginForget()
        #expect(pending.generation != nil)
        #expect(pending.forgetPending && !pending.activityLoggingAllowed)
        let restored = LocalDataControl(directory: directory)
        #expect(try restored.status() == pending)
        #expect(try restored.beginForget() == pending)
        var executed = false
        expectError(.forgetInProgress) { try restored.withReadyAccess { _ in executed = true } }
        expectError(.forgetInProgress) { try restored.setActivityLoggingAllowed(true) }
        #expect(!executed)
        #expect(try restored.status() == pending)
    }

    @Test("Only the matching pending generation may perform or finish cleanup")
    func staleGenerationCannotCleanOrFinish() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory)
        let pending = try control.beginForget()
        let generation = try #require(pending.generation)
        var executed = false
        expectError(.staleGeneration) { try control.withForgetAccess(expectedGeneration: UUID()) { executed = true } }
        expectError(.staleGeneration) { try control.finishForget(expectedGeneration: UUID()) }
        #expect(!executed)
        #expect(try control.status() == pending)
        let result = try control.withForgetAccess(expectedGeneration: generation) { "only this cleanup" }
        #expect(result == "only this cleanup")
        try control.finishForget(expectedGeneration: generation)
        expectError(.forgetNotPending) { try control.finishForget(expectedGeneration: generation) }
        let next = try control.beginForget()
        #expect(next.generation != generation)
        expectError(.staleGeneration) { try control.finishForget(expectedGeneration: generation) }
        #expect(try control.status() == next)
    }

    @Test("Finishing keeps activity off until separately enabled, across control instances")
    func finishedRemovalAndExplicitActivityChoicePersist() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = LocalDataControl(directory: directory)
        let generation = try #require(control.beginForget().generation)
        try control.finishForget(expectedGeneration: generation)
        let restored = LocalDataControl(directory: directory)
        let ready = try restored.withReadyAccess { $0 }
        #expect(ready.generation == generation && !ready.forgetPending && !ready.activityLoggingAllowed)
        try restored.setActivityLoggingAllowed(true)
        #expect(try control.status().activityLoggingAllowed)
        #expect(try control.status().generation == generation)
        try control.setActivityLoggingAllowed(false)
        #expect(try restored.status().activityLoggingAllowed == false)
        let mode = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("local-data-control.json").path)
        #expect((mode[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("Normal access preserves a corrupt marker; explicit forgetting can replace it")
    func corruptMarkerFailsClosedUntilExplicitForget() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("local-data-control.json")
        let malformed = Data("{not-json".utf8)
        try malformed.write(to: marker)
        let control = LocalDataControl(directory: directory)
        expectError(.invalidControl) { _ = try control.status() }
        expectError(.invalidControl) { _ = try control.withReadyAccess { _ in Issue.record("Corrupt control allowed access") } }
        expectError(.invalidControl) { try control.setActivityLoggingAllowed(true) }
        #expect(try Data(contentsOf: marker) == malformed)
        let pending = try control.beginForget()
        #expect(pending.forgetPending && !pending.activityLoggingAllowed)
        #expect(try LocalDataControl(directory: directory).status() == pending)
    }

    @Test("Future formats fail closed but the explicit forget action can reset them")
    func futureMarkerNeedsExplicitForget() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("local-data-control.json")
        let future = Data(#"{"schemaVersion":999,"value":{"unknown":"future"}}"#.utf8)
        try future.write(to: marker)
        let control = LocalDataControl(directory: directory)
        expectError(.unsupportedSchema(999)) { _ = try control.status() }
        expectError(.unsupportedSchema(999)) { try control.setActivityLoggingAllowed(false) }
        #expect(try Data(contentsOf: marker) == future)
        #expect(try control.beginForget().forgetPending)
    }

    @Test("A semantically invalid pending marker never opens the ordinary access gate")
    func invalidPendingStateFailsClosed() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let marker = directory.appendingPathComponent("local-data-control.json")
        try Data(#"{"schemaVersion":1,"value":{"forgetPending":true,"activityLoggingAllowed":true}}"#.utf8).write(to: marker)
        let control = LocalDataControl(directory: directory)
        expectError(.invalidControl) { _ = try control.status() }
        #expect(try control.beginForget().activityLoggingAllowed == false)
    }

    @Test("A final directory symlink is rejected instead of resolving to another workspace")
    func directorySymlinkDoesNotTouchItsTarget() throws {
        let root = location()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original", isDirectory: true)
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        let alias = root.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        let control = LocalDataControl(directory: alias)
        expectError(.unsafePath) { _ = try control.status() }
        expectError(.unsafePath) { _ = try control.beginForget() }
        #expect(try FileManager.default.contentsOfDirectory(atPath: original.path).isEmpty)
        #expect(try LocalDataControl(directory: original).status().generation == nil)
    }

    @Test("Lock and control symlinks cannot redirect access, including explicit forgetting")
    func controlAndLockSymlinksAreRejected() throws {
        for name in [".morning-privacy-lock", "local-data-control.json"] {
            let directory = location()
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("unrelated-original.txt")
            let bytes = Data("Synthetic original must remain unchanged".utf8)
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(name), withDestinationURL: target)
            let control = LocalDataControl(directory: directory)
            expectError(.unsafePath) { _ = try control.status() }
            expectError(.unsafePath) { _ = try control.beginForget() }
            #expect(try Data(contentsOf: target) == bytes)
        }
    }

    @Test("A dangling marker link is unsafe, not a missing initial marker")
    func danglingControlLinkIsNotAnInitialWorkspace() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let target = directory.appendingPathComponent("absent.json")
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("local-data-control.json"), withDestinationURL: target)
        let control = LocalDataControl(directory: directory)
        expectError(.unsafePath) { _ = try control.status() }
        expectError(.unsafePath) { _ = try control.beginForget() }
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Nonregular control paths are preserved and caller errors release the lock")
    func unsafeMarkerAndThrowingCaller() throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let marker = directory.appendingPathComponent("local-data-control.json", isDirectory: true)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        let control = LocalDataControl(directory: directory)
        expectError(.unsafePath) { _ = try control.beginForget() }
        try FileManager.default.removeItem(at: marker)
        expectError(.staleGeneration) { try control.withReadyAccess { _ in throw LocalDataControlError.staleGeneration } }
        #expect(try control.status().generation == nil)
        #expect(try control.beginForget().forgetPending)
        let nonfile = LocalDataControl(directory: URL(string: "https://example.invalid/workspace")!)
        expectError(.fileURLRequired) { _ = try nonfile.status() }
    }

    @Test("Independent owners serialize their full read and replacement under the same file lock")
    func independentOwnersCannotLoseConcurrentUpdates() async throws {
        let directory = location()
        defer { try? FileManager.default.removeItem(at: directory) }
        let counter = AtomicJSONFile<Int>(url: directory.appendingPathComponent("synthetic-counter.json"))
        try LocalDataControl(directory: directory).withReadyAccess { _ in try counter.save(0) }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<24 {
                group.addTask {
                    try LocalDataControl(directory: directory).withReadyAccess { state in
                        #expect(!state.forgetPending)
                        let value = try counter.load()
                        try counter.save(value + 1)
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(try counter.load() == 24)
    }

    @Test("Simultaneous first use creates one workspace and lock without losing writes")
    func concurrentFirstUseWithoutPrecreatedDirectory() async throws {
        // Repeat distinct first-use races. No status call, empty counter save or
        // directory preparation is allowed before the concurrent owners begin.
        for _ in 0..<8 {
            let directory = location()
            defer { try? FileManager.default.removeItem(at: directory) }
            #expect(!FileManager.default.fileExists(atPath: directory.path))
            let counter = AtomicJSONFile<Int>(url: directory.appendingPathComponent("synthetic-counter.json"))
            try await withThrowingTaskGroup(of: Void.self) { group in
                for _ in 0..<16 {
                    group.addTask {
                        try LocalDataControl(directory: directory).withReadyAccess { state in
                            #expect(state.generation == nil && !state.forgetPending)
                            let value = FileManager.default.fileExists(atPath: counter.url.path)
                                ? try counter.load() : 0
                            try counter.save(value + 1)
                        }
                    }
                }
                try await group.waitForAll()
            }
            #expect(try counter.load() == 16)
            #expect(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
                == [".morning-privacy-lock", "synthetic-counter.json"])
        }
    }
}
