import Foundation
import Testing
@testable import MorningCore

@Suite("Reviewed portable routine transfer")
struct PortableRoutineDocumentTests {
    private let sourceSecret = "PRIVATE_SOURCE_SENTINEL"
    private let detailSecret = "PRIVATE_DETAIL_SENTINEL"
    private let evidenceSecret = "PRIVATE_QUOTATION_SENTINEL"

    private func routine() -> RoutineVersion {
        RoutineVersion(number: 7, createdAt: Date(timeIntervalSince1970: 1_760_000_000.25),
            sourceLabel: sourceSecret, steps: [
                RoutineStep(title: "A personal title", detail: "\(detailSecret)\nEvidence: “\(evidenceSecret)”",
                    kind: .briefing, durationMinutes: 7, isRequired: true, automation: .spokenNote),
                RoutineStep(title: "Calendar", detail: "Review today's appointments", kind: .calendar,
                    durationMinutes: 3, automation: .todayCalendar)
            ], isApproved: true)
    }

    private func object(_ document: PortableRoutineDocument) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: document.encoded()) as? [String: Any])
    }

    private func data(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    private func expectThrows(_ expected: PortableRoutineDocumentError, _ operation: () throws -> Void) {
        do { try operation(); Issue.record("Expected the portable document operation to fail") }
        catch { #expect(error as? PortableRoutineDocumentError == expected) }
    }

    @Test("Default export projects plan fields without source text, quotations or executable operations")
    func planOnlyExcludesPrivateFieldsStructurally() throws {
        let source = routine()
        let document = try PortableRoutineDocument(routine: source)
        let bytes = try document.encoded()
        let serialized = String(decoding: bytes, as: UTF8.self)
        for sentinel in [sourceSecret, detailSecret, evidenceSecret, "spokenNote", "todayCalendar"] {
            #expect(!serialized.contains(sentinel))
        }
        let json = try object(document)
        #expect(json["sourceLabel"] == nil)
        #expect(json["automation"] == nil)
        let steps = try #require(json["steps"] as? [[String: Any]])
        #expect(steps.allSatisfy { $0["detail"] == nil && $0["automation"] == nil })
        #expect(document.steps.map(\.id) == source.steps.map(\.id))
        #expect(document.steps.map(\.title) == source.steps.map(\.title))
        #expect(document.steps.map(\.kind) == source.steps.map(\.kind))
        #expect(document.steps.map(\.durationMinutes) == [7, 3])
        #expect(document.steps.map(\.isRequired) == [true, false])
        #expect(document.detail == .planOnly)
        #expect(document.sourceLabel == nil)
    }

    @Test("Explicit details preserve exact notes and source, but still cannot transfer actions")
    func includeDetailsRoundTripsMetadataAndExactText() throws {
        let source = routine()
        let document = try PortableRoutineDocument(routine: source, detail: .includeDetails)
        let restored = try PortableRoutineDocument.decode(document.encoded())
        #expect(restored == document)
        #expect(restored.sourceRoutineID == source.id)
        #expect(restored.sourceRoutineVersion == 7)
        #expect(restored.sourceCreatedAt == source.createdAt)
        #expect(restored.approvalAtExport)
        #expect(restored.sourceLabel == source.sourceLabel)
        #expect(restored.steps[0].detail?.utf8.elementsEqual(source.steps[0].detail.utf8) == true)
        let encoded = String(decoding: try document.encoded(), as: UTF8.self)
        #expect(encoded.contains(evidenceSecret))
        #expect(!encoded.contains("automation"))
        #expect(!encoded.contains("spokenNote"))
    }

    @Test("Import creates a new local unapproved manual draft rather than restoring exported authority")
    func importKeepsStepIdentityButCreatesLocalVersion() throws {
        let source = routine()
        let document = try PortableRoutineDocument(routine: source, detail: .includeDetails)
        let current = RoutineVersion(number: 3, sourceLabel: "Local", steps: [], isApproved: true)
        let instant = Date(timeIntervalSince1970: 1_770_000_000)
        let imported = try document.importedDraft(replacing: current, at: instant)
        #expect(imported.id != source.id && imported.id != current.id)
        #expect(imported.number == 4)
        #expect(imported.createdAt == instant)
        #expect(!imported.isApproved)
        #expect(imported.steps.map(\.id) == source.steps.map(\.id))
        #expect(imported.steps.map(\.detail) == source.steps.map(\.detail))
        #expect(imported.steps.allSatisfy { $0.automation == nil })
        #expect(imported.steps[0].isRequired)
        #expect(document.sourceRoutineID == source.id && document.sourceRoutineVersion == 7)
        #expect(document.approvalAtExport)
        let firstDraft = try document.importedDraft(replacing: nil, at: instant)
        #expect(firstDraft.number == 1 && !firstDraft.isApproved)
        let redacted = try PortableRoutineDocument(routine: source).importedDraft(replacing: nil, at: instant)
        #expect(redacted.steps.allSatisfy { $0.detail.isEmpty && $0.automation == nil })
    }

    @Test("Sample provenance survives plan-only export without retaining its source label")
    func syntheticDeclarationDoesNotBecomeHumanHistory() throws {
        let document = try PortableRoutineDocument(routine: DemoFixtures.routine)
        #expect(document.sourceIsSynthetic)
        #expect(document.sourceLabel == nil)
        let restored = try PortableRoutineDocument.decode(document.encoded())
        let imported = try restored.importedDraft(replacing: nil)
        #expect(imported.sourceLabel.localizedCaseInsensitiveContains("demo fixture"))
        #expect(!imported.isApproved)
        #expect(imported.steps.allSatisfy { $0.automation == nil })
    }

    @Test("Wire dates use Unix seconds even under a caller's different date strategy")
    func dateEncodingIsExplicitAndStrategyIndependent() throws {
        let document = try PortableRoutineDocument(routine: routine())
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(document)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(json["sourceCreatedAt"] as? Double == 1_760_000_000.25)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(PortableRoutineDocument.self, from: encoded) == document)
    }

    @Test("Foreign formats, future versions, legacy snapshots and action payloads are rejected")
    func hostileOrUnsupportedFieldsCannotAcquireAuthority() throws {
        let document = try PortableRoutineDocument(routine: routine())
        let original = try object(document)
        var foreign = original
        foreign["format"] = "other-format"
        expectThrows(.invalidFormat) { _ = try PortableRoutineDocument.decode(data(foreign)) }
        var future = original
        future["formatVersion"] = 999
        expectThrows(.unsupportedVersion(999)) { _ = try PortableRoutineDocument.decode(data(future)) }
        var actionAtRoot = original
        actionAtRoot["automation"] = "spokenNote"
        expectThrows(.unexpectedFields) { _ = try PortableRoutineDocument.decode(data(actionAtRoot)) }
        var actionAtStep = original
        var steps = try #require(actionAtStep["steps"] as? [[String: Any]])
        steps[0]["automation"] = "todayCalendar"
        actionAtStep["steps"] = steps
        expectThrows(.unexpectedFields) { _ = try PortableRoutineDocument.decode(data(actionAtStep)) }
        var unknown = original
        unknown["preferences"] = ["keep": true]
        expectThrows(.unexpectedFields) { _ = try PortableRoutineDocument.decode(data(unknown)) }
        expectThrows(.unexpectedFields) { _ = try PortableRoutineDocument.decode(JSONEncoder().encode(routine())) }
    }

    @Test("Plan-only cannot smuggle details, and detailed documents must declare the included text")
    func detailModeAndPayloadMustAgree() throws {
        var json = try object(PortableRoutineDocument(routine: routine()))
        json["sourceLabel"] = sourceSecret
        expectThrows(.invalidDocument) { _ = try PortableRoutineDocument.decode(data(json)) }
        json.removeValue(forKey: "sourceLabel")
        var steps = try #require(json["steps"] as? [[String: Any]])
        steps[0]["detail"] = detailSecret
        json["steps"] = steps
        expectThrows(.invalidDocument) { _ = try PortableRoutineDocument.decode(data(json)) }
        var detailed = try object(PortableRoutineDocument(routine: routine(), detail: .includeDetails))
        detailed.removeValue(forKey: "sourceLabel")
        expectThrows(.invalidDocument) { _ = try PortableRoutineDocument.decode(data(detailed)) }
    }

    @Test("Duplicate step identities, empty or excessive plans and invalid durations are rejected")
    func invalidRowsNeverGetClampedOrDropped() throws {
        let original = try object(PortableRoutineDocument(routine: routine()))
        let originalSteps = try #require(original["steps"] as? [[String: Any]])
        for rows in [[], [originalSteps[0], originalSteps[0]]] {
            var json = original
            json["steps"] = rows
            expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument.decode(data(json)) }
        }
        var tooMany = original
        tooMany["steps"] = (0..<11).map { _ in
            var row = originalSteps[0]; row["id"] = UUID().uuidString; return row
        }
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument.decode(data(tooMany)) }
        for minutes in [-1, 0, 121, Int.max] {
            var json = original
            var rows = originalSteps
            rows[0]["durationMinutes"] = minutes
            json["steps"] = rows
            expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument.decode(data(json)) }
        }
        var source = routine()
        // A step holds one minute to one day, as its initializer always ensured for the
        // lower bound: zero cannot be stored, so there is no zero-minute row to export.
        source.steps[0].durationMinutes = 0
        #expect(source.steps[0].durationMinutes == 1)
        source.steps[0].durationMinutes = 121
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
    }

    @Test("Malformed names, overlong notes and nonfinite source or import dates cannot be exported")
    func invalidSourceTextAndDatesFailWithoutTransformation() throws {
        var source = routine()
        source.steps[0].title = " \n "
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
        source = routine(); source.steps[0].title = String(repeating: "x", count: 2_001)
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
        source = routine(); source.steps[0].detail = String(repeating: "x", count: 32_001)
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
        source = routine(); source.sourceLabel = String(repeating: "x", count: 257)
        expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
        for seconds in [Double.nan, Double.infinity, -Double.infinity] {
            source = routine(); source.createdAt = Date(timeIntervalSince1970: seconds)
            expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: source) }
            let document = try PortableRoutineDocument(routine: routine())
            expectThrows(.invalidDocument) {
                _ = try document.importedDraft(replacing: nil, at: Date(timeIntervalSince1970: seconds))
            }
        }
        var json = try object(PortableRoutineDocument(routine: routine()))
        json["sourceCreatedAt"] = "NaN"
        expectThrows(.invalidDocument) { _ = try PortableRoutineDocument.decode(data(json)) }
    }

    @Test("Local and exported version boundaries cannot overflow or silently become version one")
    func invalidVersionsFailBeforeCreatingDraft() throws {
        let document = try PortableRoutineDocument(routine: routine())
        for number in [-1, 0, Int.max] {
            var current = routine(); current.number = number
            expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument(routine: current) }
            expectThrows(.invalidLocalVersion) { _ = try document.importedDraft(replacing: current) }
            var json = try object(document); json["sourceRoutineVersion"] = number
            expectThrows(.invalidRoutine) { _ = try PortableRoutineDocument.decode(data(json)) }
        }
    }

    @Test("The byte cap covers input whitespace and explicitly included multibyte details")
    func byteBudgetsApplyBeforeDecodeAndBeforeExport() throws {
        let document = try PortableRoutineDocument(routine: routine())
        var padded = try document.encoded()
        padded.append(Data(repeating: 0x20, count: PortableRoutineDocument.maximumEncodedBytes + 1 - padded.count))
        expectThrows(.documentTooLarge) { _ = try PortableRoutineDocument.decode(padded) }
        let large = RoutineVersion(sourceLabel: "Bounded synthetic input", steps: (0..<10).map {
            RoutineStep(title: "Moment \($0)", detail: String(repeating: "🌅", count: 32_000))
        })
        expectThrows(.documentTooLarge) { _ = try PortableRoutineDocument(routine: large, detail: .includeDetails) }
        let planOnly = try PortableRoutineDocument(routine: large)
        #expect(try planOnly.encoded().count < PortableRoutineDocument.maximumEncodedBytes)
    }
}
