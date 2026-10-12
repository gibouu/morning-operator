import Foundation
import MorningCore

/// Shared by the actual extraction loop and deterministic failure/budget tests. It does not
/// decode a second time or deduplicate frames; clipping is explicit and prevents classification.
struct VideoObservationBuilder {
    let durationSeconds: Double
    private(set) var frames: [ObservationFrameEvidence] = []
    private var remainingCharacters = ObservationVideoEvidence.maximumOCRCharacters
    private var remainingBytes = ObservationVideoEvidence.maximumOCRBytes

    init(durationSeconds: Double) throws {
        guard durationSeconds.isFinite, durationSeconds > 0,
              durationSeconds <= ObservationVideoEvidence.maximumDurationSeconds else {
            throw ObservationVideoEvidenceError.invalidDuration
        }
        self.durationSeconds = durationSeconds
    }

    mutating func append(id: UUID, requestedTimeSeconds: Double, actualTimeSeconds: Double?,
                         outcome: ObservationSampleOutcome, text: String = "",
                         ocrLines: [ObservationOCRLine]? = nil, ocrWarnings: [String] = [],
                         originalPresentationTime: ObservationMediaTime? = nil) throws {
        guard frames.count < ObservationVideoEvidence.maximumFrames else { throw ObservationVideoEvidenceError.evidenceTooLarge }
        var warnings = ocrWarnings
        let actual = actualTimeSeconds.flatMap { $0.isFinite && $0 >= 0 && $0 <= durationSeconds ? $0 : nil }
        // Decimal fallback and native metadata are one admission decision. Keep neither
        // native time nor a manufactured replacement when the source time is out of range.
        let original = outcome != .decodeFailed && actual == nil ? nil : originalPresentationTime
        if outcome != .decodeFailed, actual == nil {
            warnings.append("Actual presentation time was unavailable; the requested sample time is retained as a fallback.")
        }
        if outcome == .decodeFailed { warnings.append("This requested frame could not be decoded.") }
        if outcome == .ocrFailed { warnings.append("This decoded frame could not be analyzed for text.") }
        let bounded = Self.prefix(text, maximumCharacters: remainingCharacters, maximumBytes: remainingBytes)
        let truncated = bounded != text
        if truncated { warnings.append("OCR text was truncated or omitted to stay within the extraction budget.") }
        let boundedCharacterCount = bounded.count
        let completeLines = ocrLines.map { $0.filter { $0.endCharacterOffset <= boundedCharacterCount } }
        let retainedLines = completeLines.map { Array($0.prefix(ObservationFrameEvidence.maximumOCRLines)) }
        if let ocrLines, let completeLines, completeLines.count != ocrLines.count {
            warnings.append("Some OCR layout regions were omitted because their complete text did not survive the extraction limits.")
        }
        if let completeLines, let retainedLines, retainedLines.count != completeLines.count {
            warnings.append("Some OCR layout regions were omitted at the line limit; their text was preserved.")
        }
        let evidence = try ObservationFrameEvidence(id: id, requestedTimeSeconds: requestedTimeSeconds,
            actualTimeSeconds: actual, outcome: outcome, text: bounded,
            textWasTruncated: truncated, warnings: warnings, ocrLines: retainedLines,
            originalPresentationTime: original)
        frames.append(evidence)
        remainingCharacters -= bounded.count
        remainingBytes -= bounded.utf8.count
    }

    func finish() throws -> ObservationVideoEvidence {
        var warnings = [
            "Sparse sampling may miss fast transitions and does not reveal exact taps or the user's intent.",
            "File duration and sample times do not establish wall-clock recording start or continuous capture coverage."
        ]
        let failed = frames.filter { $0.outcome == .decodeFailed || $0.outcome == .ocrFailed }.count
        if failed > 0 { warnings.append("\(failed) of \(frames.count) requested frames could not be analyzed.") }
        let truncated = frames.filter(\.textWasTruncated).count
        if truncated > 0 { warnings.append("\(truncated) frames contain truncated or omitted OCR and cannot support app identification.") }
        return try ObservationVideoEvidence(durationSeconds: durationSeconds, frames: frames, warnings: warnings)
    }

    private static func prefix(_ text: String, maximumCharacters: Int, maximumBytes: Int) -> String {
        if text.count <= maximumCharacters, text.utf8.count <= maximumBytes { return text }
        var result = ""
        var characters = 0
        var bytes = 0
        for character in text {
            let fragment = String(character)
            guard characters < maximumCharacters, bytes + fragment.utf8.count <= maximumBytes else { break }
            result.append(character)
            characters += 1
            bytes += fragment.utf8.count
        }
        return result
    }
}
