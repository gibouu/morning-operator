#if DEBUG
import Foundation
import MorningCore
import MorningApple

/// Deliberate, isolated UI-test source only. No movie, OCR or model call occurs here.
/// Even the human-origin branch is manufactured and labeled synthetic: it exercises
/// origin filtering without claiming that any personal observation was acquired.
@MainActor
enum ObservationReviewUITestFixture {
    static let marker = "Synthetic observation review test — no capture or model call"
    static let dayAID = identifier(101)
    static let dayBID = identifier(102)
    static let dayCID = identifier(103)
    static let alternateZoneID = identifier(104)
    static let personalBranchID = identifier(105)

    static func archive(arguments: [String] = ProcessInfo.processInfo.arguments,
                        directory: URL) -> ObservationArchive? {
        guard arguments.contains("--ui-testing"),
              arguments.contains("--ui-testing-observation-review") else { return nil }
        let prefix = "--ui-testing-workspace="
        let workspaces = arguments.filter { $0.hasPrefix(prefix) }
        guard workspaces.count == 1,
              let workspaceID = UUID(uuidString: String(workspaces[0].dropFirst(prefix.count))) else { return nil }
        let temporaryDirectory = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let expectedDirectory = temporaryDirectory
            .appendingPathComponent("MorningOperatorUITests-\(workspaceID.uuidString)", isDirectory: true)
        let resolvedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedDirectory == expectedDirectory.standardizedFileURL.resolvingSymlinksInPath(),
              resolvedDirectory.deletingLastPathComponent() == temporaryDirectory,
              resolvedDirectory.lastPathComponent == expectedDirectory.lastPathComponent else { return nil }

        let now = Date()
        let zone = TimeZone.current
        let alternateZone = TimeZone(identifier: zone.identifier == "Pacific/Honolulu" ? "Asia/Tokyo" : "Pacific/Honolulu")!
        do {
            let a = try acquisition(number: 101, dayOffset: -2, zone: zone, now: now,
                sourceLabel: "Synthetic fixture · day A · Cedar return",
                samples: [
                    .init(requested: 0, actual: 0, context: "Cedar"),
                    .init(requested: 1, actual: 0, context: "Cedar"),
                    .init(requested: 3, actual: 3, context: "Lumen"),
                    .init(requested: 6, actual: 6, context: "Cedar"),
                    .init(requested: 8, actual: 8, context: nil),
                    .init(requested: 10, actual: 10, context: "Cedar")
                ])
            let b = try acquisition(number: 102, dayOffset: -1, zone: zone, now: now,
                sourceLabel: "Synthetic fixture · day B · Cedar",
                samples: [.init(requested: 0, actual: 0, context: "Cedar"),
                          .init(requested: 4, actual: 4, context: "Cedar"),
                          .init(requested: 8, actual: 8, context: "Cedar")])
            let c = try acquisition(number: 103, dayOffset: 0, zone: zone, now: now,
                sourceLabel: "Synthetic fixture · day C · unresolved",
                samples: [.init(requested: 0, actual: 0, context: nil),
                          .init(requested: 4, actual: 4, context: nil),
                          .init(requested: 8, actual: 8, context: nil)])
            let otherZone = try acquisition(number: 104, dayOffset: -1, zone: alternateZone, now: now,
                sourceLabel: "Synthetic fixture · alternate zone",
                samples: [.init(requested: 0, actual: 0, context: "Willow"),
                          .init(requested: 4, actual: 4, context: "Willow")])
            let personalBranch = try acquisition(number: 105, dayOffset: -1, zone: zone, now: now,
                origin: .human, sourceLabel: "Synthetic fixture · personal branch",
                samples: [.init(requested: 0, actual: 0, context: "Harbor"),
                          .init(requested: 4, actual: 4, context: "Harbor")])
            return try ObservationArchive(entries: [a, b, c, otherZone, personalBranch])
        } catch {
            // Invalid fixture data must fail closed rather than bypass source validation.
            return nil
        }
    }

    private struct Sample {
        let requested: Double
        let actual: Double
        let context: String?
    }

    private static func acquisition(number: Int, dayOffset: Int, zone: TimeZone, now: Date,
                                    origin: ObservationAcquisitionOrigin = .synthetic,
                                    sourceLabel: String, samples: [Sample]) throws -> ObservationAcquisition {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)),
              let date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) else {
            throw ObservationArchiveError.invalidDate
        }
        let observedDate = try ObservationObservedDate(date: date, timeZoneIdentifier: zone.identifier,
                                                       provenance: .userAssigned)
        let frames = try samples.enumerated().map { index, sample in
            try ObservationFrameEvidence(id: identifier(number * 100 + index + 1),
                requestedTimeSeconds: sample.requested, actualTimeSeconds: sample.actual,
                outcome: .observed,
                text: "\(sample.context ?? "Undecided scene")\nSynthetic fixture only. No app was opened, movie captured, OCR performed or model called.")
        }
        let evidence = try ObservationVideoEvidence(id: identifier(number + 500), durationSeconds: 12,
            frames: frames, warnings: ["Synthetic UI fixture; capture coverage and actual app use are unknown."])
        let decisions = zip(frames, samples).map { frame, sample in
            let appEvidence: ObservationAppEvidence
            if let context = sample.context {
                appEvidence = .identified(app: .init(key: "visual-context:\(context.lowercased())", displayName: context),
                                          reference: frame.evidenceReference)
            } else {
                appEvidence = .unknown
            }
            return ObservationFrameIdentityDecision(sampleID: frame.id, timeSeconds: frame.timeSeconds,
                timeBasis: frame.timeBasis, evidence: appEvidence, evidenceQuote: sample.context,
                reason: "Synthetic fixture decision; no Apple model call.")
        }
        let hasIdentifiedContext = samples.contains { $0.context != nil }
        // This is a fabricated stored envelope, not a runtime inference result. Completed
        // envelopes require positive batch counts in the public archive schema; the labels
        // below explicitly disclose that those counts are synthetic test values.
        let payload = ClassificationPayload(decisions: decisions,
            status: hasIdentifiedContext ? .completed : .unavailable,
            attemptedBatchCount: hasIdentifiedContext ? 1 : 0,
            respondedBatchCount: hasIdentifiedContext ? 1 : 0,
            failedBatchCount: 0, diagnostics: [],
            modelAvailability: "Synthetic fixture values; no availability check, request or response occurred.",
            modelIdentifier: "Synthetic UI fixture — no model invoked",
            inputSelection: nil)
        let classification = try JSONDecoder().decode(ObservationContextClassification.self,
            from: JSONEncoder().encode(payload))
        let acquisition = try ObservationAcquisition(id: identifier(number), importedAt: now,
            observedDate: observedDate, origin: origin, sourceKind: .video, sourceLabel: sourceLabel,
            originalText: evidence.renderedText, videoEvidence: evidence, classification: classification)
        guard acquisition.classification == classification, acquisition.warnings.isEmpty else {
            throw ObservationArchiveError.invalidClassification
        }
        return acquisition
    }

    private struct ClassificationPayload: Encodable {
        let decisions: [ObservationFrameIdentityDecision]
        let status: ObservationContextInferenceStatus
        let attemptedBatchCount: Int
        let respondedBatchCount: Int
        let failedBatchCount: Int
        let diagnostics: [ObservationContextDiagnostic]
        let modelAvailability: String
        let modelIdentifier: String
        let inputSelection: ObservationContextInputSelection?
    }

    private static func identifier(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", number))!
    }
}
#endif
