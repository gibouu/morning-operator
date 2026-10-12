import Foundation

public enum ObservationMediaTimeError: Error, LocalizedError, Sendable, Equatable {
    case invalidTime
    public var errorDescription: String? { String(localized: "The original media timestamp is invalid or unsupported.", bundle: .module) }
}

/// The original finite, nonnegative CMTime fields returned for a decoded image. Retaining
/// a rational value does not establish a presentation span, capture coverage or actual use.
/// Rounded and nonzero-epoch times remain source metadata; later span analysis must decide
/// whether it supports them. Decimal seconds are a display projection, not a lookup key.
public struct ObservationMediaTime: Codable, Equatable, Sendable {
    public let value: Int64
    public let timescale: Int32
    public let epoch: Int64
    public let flags: UInt32

    public var seconds: Double { Double(value) / Double(timescale) }
    public var hasBeenRounded: Bool { flags & 2 != 0 }

    public init(value: Int64, timescale: Int32, epoch: Int64 = 0, flags: UInt32 = 1) throws {
        // CoreMedia numeric values require valid(1), optionally hasBeenRounded(2).
        // Infinity, indefinite, invalid and unknown flag bits cannot support this field.
        guard value >= 0, timescale > 0, flags == 1 || flags == 3 else {
            throw ObservationMediaTimeError.invalidTime
        }
        self.value = value
        self.timescale = timescale
        self.epoch = epoch
        self.flags = flags
    }

    /// Numeric equivalence is separate from Equatable's exact field/provenance equality.
    /// Reduction avoids overflowing Int64 cross multiplication or losing precision to Double.
    /// Rounded flags are retained but do not change the represented numeric instant.
    public func representsSameInstant(as other: Self) -> Bool {
        guard epoch == other.epoch else { return false }
        let left = reducedFraction
        let right = other.reducedFraction
        return left.numerator == right.numerator && left.denominator == right.denominator
    }

    private var reducedFraction: (numerator: Int64, denominator: Int64) {
        var a = value
        var b = Int64(timescale)
        while b != 0 { (a, b) = (b, a % b) }
        return (value / a, Int64(timescale) / a)
    }

    private enum CodingKeys: String, CodingKey { case value, timescale, epoch, flags }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(value: values.decode(Int64.self, forKey: .value),
                      timescale: values.decode(Int32.self, forKey: .timescale),
                      epoch: values.decode(Int64.self, forKey: .epoch),
                      flags: values.decode(UInt32.self, forKey: .flags))
    }
}
