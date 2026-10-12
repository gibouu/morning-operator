import Foundation

public enum ObservationFileFingerprintValidationError: Error, LocalizedError, Sendable, Equatable {
    case invalidDigest, invalidByteCount

    public var errorDescription: String? {
        switch self {
        case .invalidDigest: "The local file fingerprint is invalid."
        case .invalidByteCount: "The local file size is invalid."
        }
    }
}

/// SHA-256 of the complete local file bytes. Useful for exact-byte deduplication only;
/// transcoding or editing changes this digest. It does not establish capture date, app
/// identity, semantic equivalence, or authenticity. No source path or filename is retained.
public struct ObservationFileFingerprint: Codable, Equatable, Sendable {
    public let sha256: String
    public let byteCount: Int64

    public init(sha256: String, byteCount: Int64) throws {
        let canonical = sha256.lowercased()
        guard canonical.utf8.count == 64,
              canonical.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ObservationFileFingerprintValidationError.invalidDigest
        }
        guard byteCount >= 0 else { throw ObservationFileFingerprintValidationError.invalidByteCount }
        self.sha256 = canonical
        self.byteCount = byteCount
    }

    private enum CodingKeys: String, CodingKey { case sha256, byteCount }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sha256: values.decode(String.self, forKey: .sha256),
                      byteCount: values.decode(Int64.self, forKey: .byteCount))
    }
}
