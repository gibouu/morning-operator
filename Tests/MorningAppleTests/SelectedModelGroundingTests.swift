import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Selected model preserves native grounding", .serialized)
@MainActor
struct SelectedModelGroundingTests {
    private let key = "sk-synthetic-contract-key-never-used-remotely"

    @Test("Local-only composition cannot enable cloud or mutate another configured selection")
    func localOnlyIsIndependentAndClosed() async throws {
        var remoteCalls = 0
        let configured = MoreLanguageModel(storage: GroundingModelStorage(), transport: { _ in
            remoteCalls += 1
            throw MoreLanguageModelError.requestFailed
        })
        try configured.configureOpenAI(apiKey: key, enabled: true)
        let saved = configured.configurationID
        let local = MoreLanguageModel.localOnly()
        #expect(!local.usesOpenAI)
        let localContext = try local.requestContext()
        #expect(localContext.privacyEpoch == nil)
        #expect(throws: MoreLanguageModelError.credentialStorageUnavailable) {
            try local.configureOpenAI(apiKey: key, enabled: true)
        }
        #expect(!local.usesOpenAI && configured.usesOpenAI)
        #expect(configured.configurationID == saved && remoteCalls == 0)
        await #expect(throws: CancellationError.self) {
            try await local.generate(instructions: "Synthetic", prompt: "No generation expected", maximumResponseTokens: 1,
                expectedConfigurationID: UUID())
        }
        #expect(remoteCalls == 0)
    }

    @Test("The selected cloud route receives native IDs and origin and cannot supply a free detail or quote")
    func cloudUsesTheSameAnchorsAndRenderer() async throws {
        var calls = 0
        let model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { request in
            calls += 1
            let requestBody = try #require(request.httpBody)
            let body = try JSONDecoder().decode(ComposioJSONValue.self, from: requestBody)
            let prompt = try #require(body.objectValue?["input"]?.stringValue)
            #expect(prompt.contains("origin=\"synthetic\"") && prompt.contains("[q1]"))
            let schema = try #require(body.objectValue?["text"]?.objectValue?["format"]?.objectValue?["schema"])
            #expect(schema == OpenAIRoutineSchema.make(citationIDs: ["q1"]))
            return try Self.response(citationID: "q1")
        })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let source = try source(), evidence = try LearningEvidencePreparation.prepare(acquisitions: [source])
        let service = AppleIntelligenceService(model: model)
        let proposal = try await service.propose(evidence: evidence, preserving: nil)
        let step = try #require(proposal.routine.steps.first)
        #expect(calls == 1 && proposal.routine.steps.count == 1)
        #expect(!step.detail.contains("West room") && !step.detail.contains("Friday"))
        #expect(step.detail.contains("I review the project agenda after breakfast."))
        #expect(proposal.routine.isSynthetic && !proposal.routine.isApproved)
        #expect(step.automation == nil && step.target == nil && !step.isRequired)
        let archive = try ObservationArchive(entries: [source])
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil))
        #expect(proposal.support[0].citations[0].quote.utf8.elementsEqual(source.originalText.utf8))
        #expect(service.proposalDiagnostics == nil, "Remote generation must not claim Apple SDK invocations.")
    }

    @Test("A selected remote response with an unprovided anchor is still rejected natively")
    func cloudCannotInventAnchors() async throws {
        let model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { _ in try Self.response(citationID: "q999") })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source()])
        let service = AppleIntelligenceService(model: model)
        await #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try await service.propose(evidence: evidence, preserving: nil)
        }
    }

    @Test("A stale route or privacy generation is refused before the transport is entered")
    func staleDispatchDoesNotEnterTransport() async throws {
        var epoch = UUID(), calls = 0
        let model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { _ in
            calls += 1
            return try Self.response(citationID: "q1")
        }, privacyEpoch: { epoch })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let oldPrivacy = try model.requestContext()
        epoch = UUID()
        await #expect(throws: CancellationError.self) {
            try await model.generate(instructions: "Synthetic", prompt: "No dispatch", maximumResponseTokens: 1,
                expectedConfigurationID: oldPrivacy.configurationID, expectedPrivacyGeneration: oldPrivacy.privacyEpoch)
        }
        let oldRoute = try model.requestContext()
        try model.configureOpenAI(apiKey: key + "-replacement", enabled: true)
        await #expect(throws: CancellationError.self) {
            try await model.generate(instructions: "Synthetic", prompt: "No dispatch", maximumResponseTokens: 1,
                expectedConfigurationID: oldRoute.configurationID, expectedPrivacyGeneration: oldRoute.privacyEpoch)
        }
        #expect(calls == 0)
    }

    @Test("An absent captured privacy epoch cannot adopt the first Forget epoch before upload")
    func absentPrivacySnapshotIsPinnedBeforeDispatch() async throws {
        var epoch: UUID?
        var calls = 0
        let model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { _ in
            calls += 1
            return try Self.response(citationID: "q1")
        }, privacyEpoch: { epoch })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let captured = try model.requestContext()
        #expect(captured.privacyEpoch == nil)
        epoch = UUID()
        #expect(model.configurationID == captured.configurationID)
        await #expect(throws: CancellationError.self) {
            try await model.generate(instructions: "Synthetic", prompt: "Old synthetic source must not leave the caller",
                maximumResponseTokens: 1, expectedConfigurationID: captured.configurationID,
                expectedPrivacyGeneration: captured.privacyEpoch)
        }
        #expect(calls == 0, "Reject the old source before entering even the fake transport.")
        // Legacy callers with no pinned context still capture the current epoch
        // at entry; this API does not silently change their dispatch contract.
        _ = try await model.generate(instructions: "Synthetic", prompt: "New synthetic request", maximumResponseTokens: 1)
        #expect(calls == 1)
    }

    @Test("Route replacement while a provider returns cannot publish a grounded proposal")
    func changedRouteCannotPublish() async throws {
        var model: MoreLanguageModel!
        var calls = 0
        model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { _ in
            calls += 1
            try model.useLocal()
            return try Self.response(citationID: "q1")
        })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source()])
        await #expect(throws: CancellationError.self) {
            try await AppleIntelligenceService(model: model).propose(evidence: evidence, preserving: nil)
        }
        #expect(calls == 1 && !model.usesOpenAI)
    }

    @Test("Narration uses its explicitly injected model instead of the host shared selection")
    func narratorUsesInjectedModel() async throws {
        var calls = 0
        let model = MoreLanguageModel(storage: GroundingModelStorage(), transport: { request in
            calls += 1
            let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "role": "assistant",
                "content": [["type": "output_text", "text": "One invented item is available."]]]]])
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        })
        try model.configureOpenAI(apiKey: key, enabled: true)
        let text = try await ConnectedResultNarrator(model: model).summarize(.object(["count": .number(1)]), service: "SYNTHETIC")
        #expect(text == "One invented item is available." && calls == 1)
    }

    @Test("The remote grounded schema excludes free details and quotes while the legacy schema retains its contract")
    func groundedSchemaIsSeparateFromLegacy() throws {
        let properties = try #require(OpenAIRoutineSchema.make(citationIDs: ["q1", "q2"]).objectValue?["properties"]?.objectValue)
        #expect(Set(properties.keys) == ["steps"])
        #expect(properties["steps"]?.objectValue?["minItems"] == .number(0))
        #expect(properties["steps"]?.objectValue?["maxItems"] == .number(4))
        let step = try #require(properties["steps"]?.objectValue?["items"]?.objectValue?["properties"]?.objectValue)
        #expect(Set(step.keys) == ["title", "kind", "durationMinutes", "citationIDs"])
        #expect(step["citationIDs"]?.objectValue?["maxItems"] == .number(1))
        #expect(step["citationIDs"]?.objectValue?["items"]?.objectValue?["enum"] == .array([.string("q1"), .string("q2")]))
        #expect(step["durationMinutes"]?.objectValue?["minimum"] == .number(1))
        #expect(step["durationMinutes"]?.objectValue?["maximum"] == .number(60))
        #expect(step["title"]?.objectValue?["description"] == .string(EvidenceRoutineFieldGuidance.title))
        #expect(step["kind"]?.objectValue?["description"] == .string(EvidenceRoutineFieldGuidance.kind))
        #expect(step["durationMinutes"]?.objectValue?["description"] == .string(EvidenceRoutineFieldGuidance.duration))
        let empty = try #require(OpenAIRoutineSchema.make(citationIDs: []).objectValue?["properties"]?.objectValue)
        #expect(empty["steps"]?.objectValue?["maxItems"] == .number(0))
        #expect(Set(empty.keys) == ["steps"])
        #expect(empty["steps"]?.objectValue?["minItems"] == .number(0))
        let legacyRoot = try #require(OpenAIRoutineSchema.make().objectValue?["properties"]?.objectValue)
        #expect(legacyRoot["outcome"]?.objectValue?["enum"] == .array([.string("insufficientEvidence"), .string("supportedActivities")]))
        let legacy = try #require(OpenAIRoutineSchema.make().objectValue?["properties"]?.objectValue?["steps"]?.objectValue?["items"]?.objectValue?["properties"]?.objectValue)
        #expect(legacy["detail"] != nil && legacy["evidenceQuote"] != nil && legacy["evidenceKind"] != nil)
        #expect(legacy["citationIDs"] == nil)
        #expect(legacy["title"]?.objectValue?["description"] == nil)
        #expect(legacy["durationMinutes"]?.objectValue?["description"] == nil)
    }

    @Test("Both interface languages explicitly constrain generated prose without changing source quotations")
    func generatedLanguageIsExplicitWithoutChangingThePreference() {
        let saved = AppLanguage.code
        let english = AppleIntelligenceService.languageInstruction(french: false)
        let french = AppleIntelligenceService.languageInstruction(french: true)
        #expect(english.contains("in English") && french.contains("in French"))
        for instruction in [english, french] {
            #expect(instruction.contains("Keep evidence quotes exactly as they appear in the source."))
        }
        #expect(AppLanguage.code == saved)
    }

    private func source() throws -> ObservationAcquisition {
        try .init(importedAt: Date(timeIntervalSince1970: 1_792_123_200),
            observedDate: .init(date: Date(timeIntervalSince1970: 1_792_123_200), timeZoneIdentifier: "UTC", provenance: .userAssigned),
            origin: .synthetic, sourceKind: .manual, sourceLabel: "SYNTHETIC model routing contract",
            originalText: "I review the project agenda after breakfast.\n")
    }

    private static func response(citationID: String) throws -> (Data, HTTPURLResponse) {
        let result: [String: Any] = ["steps": [["title": "Review project agenda", "kind": "calendar",
            "durationMinutes": 2, "citationIDs": [citationID], "detail": "Uncited Friday in the West room.", "quote": "Invented quote"]]]
        let text = String(decoding: try JSONSerialization.data(withJSONObject: result), as: UTF8.self)
        let data = try JSONSerialization.data(withJSONObject: ["status": "completed", "output": [["type": "message", "role": "assistant",
            "content": [["type": "output_text", "text": text]]]]])
        return (data, try #require(HTTPURLResponse(url: MoreLanguageModel.endpoint, statusCode: 200, httpVersion: nil, headerFields: nil)))
    }
}

@MainActor
private final class GroundingModelStorage: MoreModelCredentialStorage {
    private var value: Data?
    func load() throws -> Data? { value }
    func save(_ data: Data) throws { value = data }
    func clear() throws { value = nil }
}
