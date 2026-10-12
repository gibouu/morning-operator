import Foundation

/// Serial, all-or-nothing collection. The caller only assembles/publishes a proposal
/// after every selected eligible unit has been submitted successfully. No raw source
/// or intermediate model response is persisted by this helper.
@MainActor
enum LearningBatchRunner {
    static func run(
        evidence: PreparedLearningEvidence,
        progress: (@MainActor @Sendable (_ completedRequests: Int, _ totalRequests: Int) -> Void)? = nil,
        generate: @MainActor ([PreparedLearningEvidenceUnit], String) async throws -> [EvidenceRoutineStepInput]
    ) async throws -> [EvidenceRoutineStepInput] {
        guard !evidence.batches.isEmpty,
              evidence.batches.count == evidence.prompts.count,
              evidence.batches.count <= LearningEvidencePreparation.maximumModelCalls,
              evidence.submittedCharacterCount <= LearningEvidencePreparation.maximumSubmittedCharacters else {
            throw RoutineEvidenceProposalError.inputBudgetExceeded
        }
        try Task.checkCancellation()
        progress?(0, evidence.batches.count)
        var results: [EvidenceRoutineStepInput] = []
        for (index, batch) in evidence.batches.enumerated() {
            try Task.checkCancellation()
            let prompt = evidence.prompts[index]
            guard !batch.isEmpty,
                  prompt.count <= LearningEvidencePreparation.maximumBatchCharacters,
                  prompt.utf8.count <= LearningEvidencePreparation.maximumBatchUTF8Bytes else {
                throw RoutineEvidenceProposalError.inputBudgetExceeded
            }
            let next = try await generate(batch, prompt)
            // A non-cooperative provider cannot return a partial or late success
            // after the user has cancelled the operation.
            try Task.checkCancellation()
            try LearningEvidencePreparation.validateBatchResult(next, units: batch)
            results.append(contentsOf: next)
            progress?(index + 1, evidence.batches.count)
        }
        try Task.checkCancellation()
        return results
    }
}

/// Exact Character boundaries plus a UTF-8 workload bound. Separators remain in
/// the chunks, so joining them reproduces the original bytes and citation offsets.
/// Prefer a whole line/word when available; an oversized word may still be split.
/// A single oversized grapheme is rejected explicitly, never silently shortened.
enum LearningTextChunker {
    static func split(_ text: String, maximumCharacters: Int, maximumUTF8Bytes: Int) throws -> [String] {
        guard maximumCharacters > 0, maximumUTF8Bytes > 0 else {
            throw RoutineEvidenceProposalError.inputBudgetExceeded
        }
        var chunks: [String] = []
        var start = text.startIndex
        while start < text.endIndex {
            var end = start
            var count = 0
            var bytes = 0
            var preferredEnd: String.Index?
            var preferredLineEnd: String.Index?
            while end < text.endIndex, count < maximumCharacters {
                let character = text[end]
                let size = String(character).utf8.count
                guard bytes + size <= maximumUTF8Bytes else { break }
                bytes += size
                count += 1
                end = text.index(after: end)
                if character.isWhitespace, count >= maximumCharacters / 2 {
                    preferredEnd = end
                    if character == "\n" || character == "\r\n" || character == "\r" { preferredLineEnd = end }
                }
            }
            guard end > start else { throw RoutineEvidenceProposalError.inputBudgetExceeded }
            if end != text.endIndex, let boundary = preferredLineEnd ?? preferredEnd { end = boundary }
            chunks.append(String(text[start..<end]))
            start = end
        }
        return chunks
    }
}
