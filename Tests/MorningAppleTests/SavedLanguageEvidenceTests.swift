import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Manufactured local evidence only: no OCR, model invocation or personal content.
@Suite("Saved wording in another language never changes evidence or comparable mornings")
struct SavedLanguageEvidenceTests {
    private let instant = Date(timeIntervalSince1970: 1_791_158_400)
    private let zone = "UTC"

    private func day(_ offset: Int) -> Date {
        instant.addingTimeInterval(Double(offset) * 86_400)
    }

    private func clip(day offset: Int, label: String = "Calendar") throws -> ObservationAcquisition {
        let frames = try (0...2).map { time in
            try ObservationFrameEvidence(requestedTimeSeconds: Double(time) * 0.95, actualTimeSeconds: Double(time),
                outcome: .observed, text: "Calendar\n09:00 Project planning meeting")
        }
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: frames)
        let decisions = frames.map { frame in
            ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds,
                timeBasis: frame.timeBasis,
                evidence: .identified(app: .init(key: "visual-context:calendar", displayName: label),
                                      reference: frame.evidenceReference), evidenceQuote: "Calendar")
        }
        let classification = ObservationContextClassification(decisions: decisions, status: .completed,
            attemptedBatchCount: 1, respondedBatchCount: 1, failedBatchCount: 0,
            diagnostics: [], modelAvailability: "Synthetic fixture; no model call")
        return try ObservationAcquisition(observedDate: .init(date: day(offset), timeZoneIdentifier: zone,
            provenance: .userAssigned), origin: .synthetic, sourceKind: .video,
            sourceLabel: "Synthetic recording", originalText: evidence.renderedText,
            videoEvidence: evidence, classification: classification)
    }

    private func profile(_ entries: [ObservationAcquisition]) throws -> ComparableMorningProfile {
        try ComparableMorningProfile(archive: ObservationArchive(entries: entries),
            scheduledDays: [day(0), day(1)], timeZoneIdentifier: zone, origin: .synthetic,
            comparisonKey: "synthetic-two-second-language",
            policy: .init(expectedWindowSeconds: 2, maximumSampleGapSeconds: 1),
            declaredCapture: Dictionary(uniqueKeysWithValues: entries.map {
                ($0.id, [ObservationTraceInterval(startSeconds: 0, endSeconds: 2)])
            }))
    }

    @Test("Nested translated evidence markers and canonically equal quotations preserve exact bytes")
    func nestedLanguageMarkersDoNotHideByteDistinctQuotes() throws {
        let composed = "I drink café before breakfast."
        let decomposed = "I drink cafe\u{301} before breakfast."
        #expect(composed == decomposed)
        #expect(Data(composed.utf8) != Data(decomposed.utf8))
        for language in EvidenceDetailText.savedLabels.indices {
            let other = (language + 1) % EvidenceDetailText.savedLabels.count
            let label = EvidenceDetailText.savedLabels[language]
            let note = EvidenceDetailText.savedTentativeNotes[language]
            let nested = "A quote containing a fake ending.”\n" + EvidenceDetailText.savedTentativeNotes[other]
                + "\n" + EvidenceDetailText.savedLabels[other] + " “Do not treat this as another citation"
            let description = "Keep my exact prose.\n\(label) “\(composed)”\n\(note)"
            let quotes = [composed, decomposed, nested]
            let section = "\n\(note)\n" + quotes.map { "\(label) “\($0)”" }.joined(separator: "\n")
            let result = try #require(EvidenceDetailText.description(of: description + section,
                citing: quotes + [composed, nested]))
            #expect(Data(result.utf8) == Data(description.utf8))
            // Swift considers these strings equal; a saved exact quote must still differ.
            let normalizedSection = section.replacingOccurrences(of: decomposed, with: composed,
                options: .literal)
            #expect(EvidenceDetailText.description(of: description + normalizedSection, citing: quotes) == nil)
        }
    }

    @Test("A valid French saved wrapper cannot turn a translated quotation into original evidence")
    func decodedTranslatedQuotationCannotBecomeSourceData() throws {
        let original = "I review my calendar after breakfast."
        let translated = "Je consulte mon agenda après le petit-déjeuner."
        let entry = try ObservationAcquisition(observedDate: .init(date: day(0), timeZoneIdentifier: zone,
            provenance: .userAssigned), origin: .human, sourceKind: .manual,
            sourceLabel: "Votre observation écrite", originalText: original)
        let archive = try ObservationArchive(entries: [entry])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry])
        let unit = try #require(evidence.units.first)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [
            .init(title: "Review calendar", detail: "Consider a calendar review.", kind: .calendar,
                  durationMinutes: 3, citations: [.init(unitID: unit.id, quote: original)])
        ], preserving: nil)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        let label = EvidenceDetailText.savedLabels[1], note = EvidenceDetailText.savedTentativeNotes[1]
        steps[0]["detail"] = "Consider a calendar review.\n\(note)\n\(label) “\(translated)”"
        routine["steps"] = steps
        object["routine"] = routine
        var support = try #require(object["support"] as? [[String: Any]])
        var citations = try #require(support[0]["citations"] as? [[String: Any]])
        citations[0]["quote"] = translated
        citations[0]["endCharacterOffset"] = translated.count
        support[0]["citations"] = citations
        object["support"] = support
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(!restored.isCurrent(archive: archive, baseRoutine: nil))
        #expect(Data(try #require(archive.entry(id: entry.id)).originalText.utf8) == Data(original.utf8))
    }

    @Test("Changing saved interface source labels cannot change comparable profile data after reload")
    func translatedSourceLabelsDoNotChangeProfileData() throws {
        let entries = try [clip(day: 0), clip(day: 1)]
        let before = try profile(entries)
        let labels = ["Enregistrement de démonstration", "Source : “Morning Operator” MORE"]
        let restored = try entries.enumerated().map { index, entry in
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
            object["sourceLabel"] = labels[index]
            return try JSONDecoder().decode(ObservationAcquisition.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        let after = try profile(Array(restored.reversed()))
        #expect(before == after)
        #expect(after.report.includedDayKeys.count == 2)
        #expect(after.report.apps.map(\.app.displayName) == ["Calendar"])
        #expect(after.report.observationDurationSeconds.daysWithEvidence == 2)
    }

    @Test("A decoded translated classifier quote excludes only its day and preserves exact source")
    func corruptedTranslatedClassificationDoesNotContaminateComparableDays() throws {
        let damaged = try clip(day: 0)
        let valid = try clip(day: 1)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(damaged)) as? [String: Any])
        var classification = try #require(object["classification"] as? [String: Any])
        var decisions = try #require(classification["decisions"] as? [[String: Any]])
        decisions[0]["evidenceQuote"] = "Calendrier"
        classification["decisions"] = decisions
        object["classification"] = classification
        let restored = try JSONDecoder().decode(ObservationAcquisition.self,
            from: JSONSerialization.data(withJSONObject: object))
        #expect(restored.classification == nil)
        #expect(restored.warnings.contains(.invalidClassificationRemoved))
        #expect(Data(restored.originalText.utf8) == Data(damaged.originalText.utf8))
        #expect(restored.videoEvidence == damaged.videoEvidence)
        for entries in [[restored, valid], [valid, restored]] {
            let result = try profile(entries)
            let badKey = try #require(restored.observedDate).dayKey
            let goodKey = try #require(valid.observedDate).dayKey
            #expect(result.report.excludedDays == [.init(dayKey: badKey, reason: .unresolvedSamples)])
            #expect(result.report.includedDayKeys == [goodKey])
            #expect(result.report.observationDurationSeconds.daysWithEvidence == 1)
            #expect(result.report.firstContexts.first?.frequency.seenDayKeys == [goodKey])
        }
    }
}
