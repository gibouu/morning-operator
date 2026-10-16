import Foundation

public enum ObservationOCRLineError: Error, LocalizedError, Sendable, Equatable {
    case invalidBounds, invalidConfidence, invalidLine

    public var errorDescription: String? {
        switch self {
        case .invalidBounds: AppLanguage.localized("An OCR line has invalid normalized image bounds.", bundle: .module)
        case .invalidConfidence: AppLanguage.localized("An OCR line has invalid recognition confidence.", bundle: .module)
        case .invalidLine: AppLanguage.localized("An OCR line has an invalid text span.", bundle: .module)
        }
    }
}

/// Approximate Vision-recognized region bounds with a normalized lower-left origin. These
/// describe the oriented image supplied to OCR, not exact glyph outlines, semantic roles,
/// device-screen coordinates or a tappable UI element.
public struct ObservationNormalizedBounds: Codable, Sendable, Equatable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
              x >= 0, y >= 0, width > 0, height > 0,
              x <= 1, y <= 1, width <= 1, height <= 1,
              x + width <= 1, y + height <= 1 else {
            throw ObservationOCRLineError.invalidBounds
        }
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey { case x, y, width, height }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(x: values.decode(Double.self, forKey: .x),
                      y: values.decode(Double.self, forKey: .y),
                      width: values.decode(Double.self, forKey: .width),
                      height: values.decode(Double.self, forKey: .height))
    }
}

/// One retained OCR line. Character offsets refer to its frame's exact text; the end is
/// exclusive. IDs are local extraction identifiers that survive persistence, not hashes
/// or identifiers stable across another OCR pass. Confidence is OCR candidate confidence,
/// not confidence in an app identity, intention, or inferred action.
public struct ObservationOCRLine: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public let text: String
    public let startCharacterOffset: Int
    public let endCharacterOffset: Int
    public let bounds: ObservationNormalizedBounds
    public let confidence: Double

    public init(id: UUID = UUID(), text: String, startCharacterOffset: Int,
                endCharacterOffset: Int, bounds: ObservationNormalizedBounds,
                confidence: Double) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= ObservationVideoEvidence.maximumOCRCharacters,
              text.utf8.count <= ObservationVideoEvidence.maximumOCRBytes,
              startCharacterOffset >= 0, endCharacterOffset > startCharacterOffset,
              endCharacterOffset - startCharacterOffset == text.count else {
            throw ObservationOCRLineError.invalidLine
        }
        guard confidence.isFinite, (0...1).contains(confidence) else {
            throw ObservationOCRLineError.invalidConfidence
        }
        self.id = id
        self.text = text
        self.startCharacterOffset = startCharacterOffset
        self.endCharacterOffset = endCharacterOffset
        self.bounds = bounds
        self.confidence = confidence
    }

    private enum CodingKeys: String, CodingKey {
        case id, text, startCharacterOffset, endCharacterOffset, bounds, confidence
    }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(id: values.decode(UUID.self, forKey: .id),
                      text: values.decode(String.self, forKey: .text),
                      startCharacterOffset: values.decode(Int.self, forKey: .startCharacterOffset),
                      endCharacterOffset: values.decode(Int.self, forKey: .endCharacterOffset),
                      bounds: values.decode(ObservationNormalizedBounds.self, forKey: .bounds),
                      confidence: values.decode(Double.self, forKey: .confidence))
    }
}
