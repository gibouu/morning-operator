import Foundation
import MorningCore
import Testing
@testable import MorningApple

/// Explicit opt-in only. Uses harmless synthetic input, a private temporary
/// workspace and an in-memory credential store; never reads accounts or recordings.
@Suite("Real OpenAI routine understanding and personal correction", .serialized)
@MainActor
struct MoreIntelligenceLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["MORE_OPENAI_LIVE_KEY_FILE"] != nil))
    func understandsRoutineAndRemembersCorrectionAcrossRelaunch() async throws {
        let keyPath = try #require(ProcessInfo.processInfo.environment["MORE_OPENAI_LIVE_KEY_FILE"])
        let key = try String(contentsOfFile: keyPath, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        let model = MoreLanguageModel(storage: LiveCredentialStore(), transport: MoreLanguageModel.send)
        try model.configureOpenAI(apiKey: key, enabled: true)
        defer { try? model.forget() }

        let text = "Every morning I review my calendar, then read my email inbox."
        let acquisition = try ObservationAcquisition(importedAt: .now,
            observedDate: ObservationObservedDate(date: .now, timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .text, sourceLabel: "Synthetic live verification", originalText: text)
        let archive = try ObservationArchive(entries: [acquisition])
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [acquisition])
        let proposal = try await AppleIntelligenceService(model: model).propose(evidence: evidence,
            preserving: nil, preferences: RoutinePreferenceJournal())
        #expect(!proposal.routine.isApproved)
        #expect(proposal.routine.steps.contains { $0.kind == .calendar })
        #expect(proposal.routine.steps.contains { $0.kind == .messages })
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil, preferences: RoutinePreferenceJournal()))
        #expect(proposal.support.allSatisfy { !$0.citations.isEmpty })

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        func memory() -> MorePersonalMemory {
            MorePersonalMemory(directory: directory, extractor: { prompt in
                let result = try await model.generate(instructions: MorePersonalMemory.extractionInstructions,
                    prompt: prompt, maximumResponseTokens: 500, schema: MorePersonalMemory.extractionSchema)
                print("Synthetic memory extraction: \(result)")
                return result
            })
        }
        let first = memory()
        await first.remember(fromOwnerUtterance: "J’ai une trottinette électrique.")
        try #require(first.facts.contains { $0.key == .electricScooter && $0.value == "yes" })
        await first.remember(fromOwnerUtterance: "Je n’ai pas de trottinette, je prends les transports.")
        await first.remember(fromOwnerUtterance: "Je ne bois pas de café.")
        await first.remember(fromOwnerUtterance: "Je bois un café le matin.")
        let restored = memory()
        try #require(restored.facts.filter { $0.key.rawValue == "coffeePreference" }.count == 1)
        try #require(restored.facts.contains { $0.key.rawValue == "coffeePreference" && $0.value.contains("Je bois un café le matin") })
        try #require(restored.facts.contains { $0.key == .electricScooter && $0.value == "no" })
        try #require(restored.facts.contains { $0.key == .usualTransport && $0.value == "publicTransport" })
        let conversation = MorningVoiceConversation(generator: { prompt in
            try await model.generate(instructions: MorningVoiceConversation.instructions,
                prompt: prompt, maximumResponseTokens: 350)
        }, memory: restored)
        let advice = try await conversation.morningAdvice(context: "Météo actuelle vérifiée : pluie, 7 °C. Aucune prévision quotidienne disponible.")
        #expect(!advice.isEmpty)
        #expect(!advice.lowercased().contains("trottinette"))
        #expect(!advice.lowercased().contains("scooter"))
        // Safe to display: synthetic weather and transport facts only.
        print("MORE live verification: cited routine proposed; correction retained after reload. Advice: \(advice)")
        try restored.forgetAll()
        #expect(memory().facts.isEmpty)
    }
}

@MainActor
private final class LiveCredentialStore: MoreModelCredentialStorage {
    private var data: Data?
    func load() throws -> Data? { data }
    func save(_ data: Data) throws { self.data = data }
    func clear() throws { data = nil }
}
