import Foundation
import Testing
import MorningCore
@testable import MorningApple

@Suite("Selected routine file reading")
struct RoutineDocumentReaderTests {
    @Test func readsActualPortableFileWithoutChangingTheOriginal() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let routine = RoutineVersion(sourceLabel: "Synthetic file reader source", steps: [
            RoutineStep(title: "Tea", detail: "Private synthetic note", durationMinutes: 4)
        ], isApproved: true)
        let document = try PortableRoutineDocument(routine: routine)
        let bytes = try document.encoded()
        let url = folder.appendingPathComponent("routine.json")
        try bytes.write(to: url)
        let loaded = try await RoutineDocumentReader().read(url)
        #expect(loaded.sourceRoutineID == routine.id)
        #expect(loaded.steps.first?.id == routine.steps.first?.id)
        #expect(loaded.steps.first?.detail == nil)
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func refusesOversizedFileWithoutRemovingIt() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let bytes = Data(repeating: 32, count: PortableRoutineDocument.maximumEncodedBytes + 1)
        try bytes.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: RoutineDocumentReadError.self) {
            try await RoutineDocumentReader().read(url)
        }
        #expect(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == bytes.count)
    }

    @Test func refusesDirectoriesAndNetworkLocations() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        await #expect(throws: RoutineDocumentReadError.self) {
            try await RoutineDocumentReader().read(directory)
        }
        await #expect(throws: RoutineDocumentReadError.self) {
            try await RoutineDocumentReader().read(URL(string: "https://example.invalid/routine.json")!)
        }
    }
}
