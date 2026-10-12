import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Local Shortcuts transition journal")
struct AppTransitionLogStoreTests {
    @Test func disabledCollectionSurvivesReloadAndShortcutCannotEnableIt() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        try await store.setActivityLoggingAllowed(false)
        let blocked = try await store.record(app: .instagram, kind: .entered)
        #expect(!blocked)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("app-transitions.json").path))
        let restored = AppTransitionLogStore(directory: directory)
        #expect(try await !restored.activityLoggingAllowed())
        let retried = try await restored.record(app: .tiktok, kind: .exited)
        #expect(!retried)
        try await restored.setActivityLoggingAllowed(true)
        let explicitNewEvent = try await restored.record(app: .snapchat, kind: .entered)
        #expect(explicitNewEvent)
        #expect(try await restored.events().map(\.app) == [.snapchat])
    }

    @Test func pendingForgetRejectsLateWritesAndDoesNotRecreateADeletedJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        try await store.record(app: .instagram, kind: .entered)
        let privacy = LocalDataControl(directory: directory)
        let reset = try privacy.beginForget()
        let url = directory.appendingPathComponent("app-transitions.json")
        try FileManager.default.removeItem(at: url) // Models the controller's explicit payload sweep.
        await #expect(throws: (any Error).self) {
            try await store.record(app: .tiktok, kind: .entered)
        }
        await #expect(throws: (any Error).self) {
            try await store.setActivityLoggingAllowed(true)
        }
        let restored = AppTransitionLogStore(directory: directory)
        await #expect(throws: (any Error).self) {
            try await restored.record(app: .snapchat, kind: .exited)
        }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try privacy.status().forgetPending)
        let generation = try #require(reset.generation)
        try privacy.finishForget(expectedGeneration: generation)
        let afterReset = try await restored.record(app: .tiktok, kind: .entered)
        #expect(!afterReset, "Finishing a reset does not reenable configured background automations.")
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func corruptPrivacyControlFailsClosedWithoutChangingJournal() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        try await store.record(app: .instagram, kind: .entered)
        let journal = directory.appendingPathComponent("app-transitions.json")
        let before = try Data(contentsOf: journal)
        let control = directory.appendingPathComponent("local-data-control.json")
        let corrupt = Data("unreadable synthetic privacy marker".utf8)
        try corrupt.write(to: control)
        await #expect(throws: (any Error).self) {
            try await store.record(app: .tiktok, kind: .entered)
        }
        #expect(try Data(contentsOf: journal) == before)
        #expect(try Data(contentsOf: control) == corrupt)
    }

    @Test func clearingSurvivesReloadPreservesWorkspaceAndAllowsNewEvents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        let firstID = UUID()
        try await store.record(app: .instagram, kind: .entered, eventID: firstID)
        let workspace = directory.appendingPathComponent("workspace.json")
        let workspaceData = Data("Existing routines and notes".utf8)
        try workspaceData.write(to: workspace)

        try await store.clear()
        try await store.clear() // An already cleared journal is a safe no-op.
        let reloaded = AppTransitionLogStore(directory: directory)
        #expect(try await reloaded.events().isEmpty)
        #expect(try Data(contentsOf: workspace) == workspaceData)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("app-transitions.json").path))

        try await reloaded.record(app: .tiktok, kind: .entered)
        let newEvents = try await reloaded.events()
        #expect(newEvents.count == 1)
        #expect(newEvents.first?.app == .tiktok)
        #expect(!newEvents.contains { $0.id == firstID })

        // The explicit clear action must also recover from a journal that cannot be decoded.
        let journal = directory.appendingPathComponent("app-transitions.json")
        try Data("corrupt journal".utf8).write(to: journal)
        try await reloaded.clear()
        #expect(try await reloaded.events().isEmpty)
        #expect(try Data(contentsOf: workspace) == workspaceData)
    }

    @Test func writeRetryAndReloadPreserveOriginalEventAndSeparateWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(try await store.record(app: .instagram, kind: .entered, observedAt: date,
            eventID: id, timeZoneIdentifier: "UTC"))
        #expect(try await !store.record(app: .instagram, kind: .entered, observedAt: date.addingTimeInterval(20),
            eventID: id, timeZoneIdentifier: "UTC"))
        let restored = AppTransitionLogStore(directory: directory)
        let events = try await restored.events()
        #expect(events.count == 1)
        #expect(events.first?.observedAt == date)
        #expect(events.first?.source == .shortcut)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("workspace.json").path))
        await #expect(throws: AppTransitionError.conflictingEventID) {
            try await store.record(app: .snapchat, kind: .entered, eventID: id)
        }
    }

    @Test func concurrentRequestsAreSerializedAndCorruptLogIsNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppTransitionLogStore(directory: directory)
        let otherWriter = AppTransitionLogStore(directory: directory)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<6 {
                group.addTask {
                    let writer = index.isMultiple(of: 2) ? store : otherWriter
                    _ = try await writer.record(app: .tiktok, kind: .entered,
                        observedAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), timeZoneIdentifier: "UTC")
                }
            }
            try await group.waitForAll()
        }
        #expect(try await store.events().count == 6)
        let url = directory.appendingPathComponent("app-transitions.json")
        let corrupt = Data("not valid JSON".utf8)
        try corrupt.write(to: url)
        await #expect(throws: (any Error).self) {
            try await store.record(app: .instagram, kind: .entered)
        }
        #expect(try Data(contentsOf: url) == corrupt)
    }
}
