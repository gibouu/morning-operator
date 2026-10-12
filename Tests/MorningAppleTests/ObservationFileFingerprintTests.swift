import Foundation
import Testing
@testable import MorningApple

@Suite("Local streaming observation fingerprint")
struct ObservationFileFingerprintTests {
    @Test("Native SHA-256 matches known vectors independent of file location and chunk boundaries")
    func knownVectorsAndExactByteIdentity() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent("one.mov")
        let copy = directory.appendingPathComponent("renamed.mp4")
        try Data("abc".utf8).write(to: first)
        try Data("abc".utf8).write(to: copy)
        let service = ObservationFileFingerprintService(maximumBytes: 32, chunkByteCount: 2)
        let result = try await service.fingerprint(of: first)
        #expect(result.sha256 == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(result.byteCount == 3)
        #expect(try await service.fingerprint(of: copy) == result)
        try Data("abd".utf8).write(to: copy)
        #expect(try await service.fingerprint(of: copy).sha256 != result.sha256)
        try Data().write(to: copy)
        let empty = try await service.fingerprint(of: copy)
        #expect(empty.sha256 == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(empty.byteCount == 0)
    }

    @Test("Remote URLs, directories, symbolic links and oversized files are not read as accepted media")
    func inputBoundaries() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bytes.mov")
        let link = directory.appendingPathComponent("link.mov")
        try Data("abcde".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        let service = ObservationFileFingerprintService(maximumBytes: 4, chunkByteCount: 2)
        await #expect(throws: ObservationFileFingerprintError.localRegularFileRequired) {
            try await service.fingerprint(of: URL(string: "https://example.invalid/file.mov")!)
        }
        await #expect(throws: ObservationFileFingerprintError.localRegularFileRequired) {
            try await service.fingerprint(of: directory)
        }
        await #expect(throws: ObservationFileFingerprintError.unreadableFile) {
            try await service.fingerprint(of: link)
        }
        await #expect(throws: ObservationFileFingerprintError.fileTooLarge) {
            try await service.fingerprint(of: file)
        }
    }

    @Test("Cancellation after reading a chunk returns no partial digest and permits a later retry")
    func midStreamCancellation() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bytes.mov")
        try Data("abcdef".utf8).write(to: file)
        let service = ObservationFileFingerprintService(maximumBytes: 32, chunkByteCount: 2)
        let gate = FingerprintReadGate()
        let pending = Task {
            try await service.fingerprint(of: file) { count in
                if count == 2 { await gate.pause() }
            }
        }
        await gate.waitUntilPaused()
        pending.cancel()
        await gate.resume()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(try await service.fingerprint(of: file).byteCount == 6)
    }

    @Test("Growing a file during hashing still enforces the byte limit")
    func growthBeyondLimit() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bytes.mov")
        try Data("abcd".utf8).write(to: file)
        let service = ObservationFileFingerprintService(maximumBytes: 4, chunkByteCount: 2)
        let gate = FingerprintReadGate()
        let pending = Task {
            try await service.fingerprint(of: file) { count in
                if count == 2 { await gate.pause() }
            }
        }
        await gate.waitUntilPaused()
        let writer = try FileHandle(forWritingTo: file)
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("efgh".utf8))
        try writer.close()
        await gate.resume()
        await #expect(throws: ObservationFileFingerprintError.fileTooLarge) { try await pending.value }
    }

    @Test("Replacing the pathname mid-stream cannot pair an old digest with a new file for OCR")
    func replacementIsRejected() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bytes.mov")
        let replacement = directory.appendingPathComponent("replacement.mov")
        try Data("abcdef".utf8).write(to: file)
        try Data("uvwxyz".utf8).write(to: replacement)
        let service = ObservationFileFingerprintService(maximumBytes: 32, chunkByteCount: 2)
        let gate = FingerprintReadGate()
        let pending = Task {
            try await service.fingerprint(of: file) { count in
                if count == 2 { await gate.pause() }
            }
        }
        await gate.waitUntilPaused()
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: replacement, to: file)
        await gate.resume()
        await #expect(throws: ObservationFileFingerprintError.fileChanged) { try await pending.value }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private actor FingerprintReadGate {
    private var paused = false
    private var pauseContinuation: CheckedContinuation<Void, Never>?
    private var waitContinuation: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
            paused = true
            waitContinuation?.resume()
            waitContinuation = nil
        }
    }

    func waitUntilPaused() async {
        if paused { return }
        await withCheckedContinuation { waitContinuation = $0 }
    }

    func resume() {
        pauseContinuation?.resume()
        pauseContinuation = nil
    }
}
