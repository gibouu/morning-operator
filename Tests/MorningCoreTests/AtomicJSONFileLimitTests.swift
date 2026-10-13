import Foundation
import Testing
@testable import MorningCore

@Suite("A size-limited local file never writes what it would refuse to read")
struct AtomicJSONFileLimitTests {
    @Test("The limit counts the bytes written, and a refused save leaves the file as it was")
    func saveAppliesTheReadLimitToItsEncodedBytes() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicJSONFileLimitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("value.json")
        try AtomicJSONFile<String>(url: url).save("")
        let overhead = try Data(contentsOf: url).count
        let limit = overhead + 64
        let file = AtomicJSONFile<String>(url: url, maximumBytes: limit)

        // A quote is one byte in the value and two in the file: the limit follows the file.
        let fits = String(repeating: "\"", count: 32)
        try file.save(fits)
        #expect(try Data(contentsOf: url).count == limit)
        #expect(try file.load() == fits)
        let saved = try Data(contentsOf: url)

        let over = String(repeating: "\"", count: 32) + "x"
        #expect(throws: PersistenceError.fileTooLarge(byteCount: limit + 1, limit: limit)) { try file.save(over) }
        #expect(try Data(contentsOf: url) == saved)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["value.json"])
        #expect(try file.load() == fits)

        // A file that grew outside the app is refused by the same limit, and read no further.
        try AtomicJSONFile<String>(url: url).save(over)
        #expect(throws: PersistenceError.fileTooLarge(byteCount: limit + 1, limit: limit)) { _ = try file.load() }
        #expect(try AtomicJSONFile<String>(url: url).load() == over)
    }

    @Test("Escaped and multi-byte text is measured as written, at the exact limit and one byte under")
    func escapedTextIsMeasuredAsWritten() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicJSONFileLimitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("value.json")
        for token in ["\"", "\\", "/", "\u{2028}", "\u{2029}", "\u{007F}", "😀", "e\u{0301}", "a\u{0301}\u{0301}"] {
            let value = Set((0..<10).map { "\($0):" + String(repeating: token, count: 512) })
            try AtomicJSONFile<Set<String>>(url: url).save(value)
            let size = try Data(contentsOf: url).count
            #expect(try AtomicJSONFile<Set<String>>(url: url, maximumBytes: size).load() == value)
            try AtomicJSONFile<Set<String>>(url: url, maximumBytes: size).save(value)
            #expect(try AtomicJSONFile<Set<String>>(url: url, maximumBytes: size).load() == value)
            #expect(throws: PersistenceError.fileTooLarge(byteCount: size, limit: size - 1)) {
                try AtomicJSONFile<Set<String>>(url: url, maximumBytes: size - 1).save(value)
            }
            #expect(throws: PersistenceError.fileTooLarge(byteCount: size, limit: size - 1)) {
                _ = try AtomicJSONFile<Set<String>>(url: url, maximumBytes: size - 1).load()
            }
        }
        // The limit is on bytes, so a compact file under it can hold a value whose indented
        // form is over it. Saving that value is refused and the compact file stays.
        let compact = Data(#"{"schemaVersion":1,"value":"x"}"#.utf8)
        try compact.write(to: url)
        let tight = AtomicJSONFile<String>(url: url, maximumBytes: compact.count)
        #expect(try tight.load() == "x")
        #expect(throws: PersistenceError.self) { try tight.save("x") }
        #expect(try Data(contentsOf: url) == compact)
    }

    /// Reading one byte past a limit of the largest integer used to overflow and end the process.
    @Test("The largest and the smallest limits neither overflow nor admit a file")
    func extremeLimitsAreSafe() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AtomicJSONFileLimitTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("value.json")
        let widest = AtomicJSONFile<String>(url: url, maximumBytes: .max)
        try widest.save("synthetic")
        #expect(try widest.load() == "synthetic")
        for limit in [Int.min, -1, 0] {
            let closed = AtomicJSONFile<String>(url: url, maximumBytes: limit)
            #expect(throws: PersistenceError.self) { try closed.save("synthetic") }
            #expect(throws: PersistenceError.self) { _ = try closed.load() }
        }
        #expect(try widest.load() == "synthetic")
    }
}
