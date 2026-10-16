import Foundation
import Testing
@testable import MorningApple

@Suite("Local proposal diagnostics describe structure without retaining model content")
struct RoutineProposalDiagnosticsTests {
    @Test func emptyCausesAndAcceptedStructureRemainDistinguishable() throws {
        var diagnostics = RoutineProposalDiagnostics()
        diagnostics.prepare([(2, 0), (3, 5), (4, 3)])
        for (index, result) in [("insufficientEvidence", 0), ("supportedActivities", 0), ("supportedActivities", 1)].enumerated() {
            diagnostics.started(index); diagnostics.returned(index)
            diagnostics.decoded(index, outcome: result.0, stepCount: result.1)
            diagnostics.resolved(index, stepCount: result.1); diagnostics.validated(index)
        }
        diagnostics.phase = .assembling
        #expect(diagnostics.respondInvocations == 3 && diagnostics.responseReturns == 3 && diagnostics.validatedBatchCount == 3)
        #expect(diagnostics.resolvedStepCount == 1 && diagnostics.phase == .assembling)
        #expect(diagnostics.batches[0].anchorCount == 0 && diagnostics.batches[0].outcome == .insufficientEvidence)
        #expect(diagnostics.batches[1].anchorCount == 5 && diagnostics.batches[1].outcome == .supportedActivities && diagnostics.batches[1].stepCount == 0)
        #expect(diagnostics.batches[2].stepCount == 1 && diagnostics.batches.allSatisfy { $0.phase == .validated })
        #expect(try JSONDecoder().decode(RoutineProposalDiagnostics.self, from: JSONEncoder().encode(diagnostics)) == diagnostics)
    }

    @Test func failureCheckpointsAndUnknownOutcomesRetainNoRawResponse() throws {
        var diagnostics = RoutineProposalDiagnostics()
        diagnostics.prepare([(2, 4), (2, 3)])
        diagnostics.started(0); diagnostics.returned(0)
        diagnostics.decoded(0, outcome: "PRIVATE_MODEL_RESPONSE_CANARY", stepCount: 2)
        // Resolution failed: a returned response is not a validated batch.
        #expect(diagnostics.batches[0].phase == .decoded && diagnostics.batches[0].outcome == .unrecognized)
        #expect(diagnostics.responseReturns == 1 && diagnostics.validatedBatchCount == 0 && diagnostics.resolvedStepCount == 0)
        diagnostics.started(1) // SDK throws before returning.
        #expect(diagnostics.respondInvocations == 2 && diagnostics.responseReturns == 1)
        #expect(diagnostics.batches[1].phase == .started && diagnostics.batches[1].outcome == nil)
        let saved = String(decoding: try JSONEncoder().encode(diagnostics), as: UTF8.self)
        #expect(!saved.contains("PRIVATE_MODEL_RESPONSE_CANARY"))
        let object = try JSONSerialization.jsonObject(with: Data(saved.utf8))
        let keys = try #require(object as? [String: Any])
        #expect(Set(keys.keys) == ["phase", "plannedBatchCount", "respondInvocations", "responseReturns", "validatedBatchCount", "resolvedStepCount", "batches"])
    }

    @Test func boundedRowsDoNotChangeOrMisreportALargerNativeWorkload() {
        var diagnostics = RoutineProposalDiagnostics()
        diagnostics.prepare(Array(repeating: (1, Optional(2)), count: 30))
        for index in 0..<30 {
            diagnostics.started(index); diagnostics.returned(index)
            diagnostics.decoded(index, outcome: "supportedActivities", stepCount: 1)
            diagnostics.resolved(index, stepCount: 1); diagnostics.validated(index)
        }
        #expect(diagnostics.plannedBatchCount == 30 && diagnostics.batches.count == 24)
        #expect(diagnostics.respondInvocations == 30 && diagnostics.responseReturns == 30 && diagnostics.validatedBatchCount == 30)
        #expect(diagnostics.resolvedStepCount == 30)
    }
}
