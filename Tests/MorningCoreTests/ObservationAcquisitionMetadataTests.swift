import Foundation
import Testing
@testable import MorningCore

@Suite("Local observation acquisition metadata")
struct ObservationAcquisitionMetadataTests {
    @Test("Recording context retains the actual instant, session identity and original time zone")
    func contextRoundTrip() throws {
        let context = try ObservationRecordingContext(startedAt: Date(timeIntervalSince1970: 1_728_000_123.5),
                                                       timeZoneIdentifier: "Europe/Paris")
        let decoded = try JSONDecoder().decode(ObservationRecordingContext.self,
                                               from: JSONEncoder().encode(context))
        #expect(decoded == context)
        #expect(decoded.timeZoneIdentifier == "Europe/Paris")
        #expect(decoded.startedAt.timeIntervalSince1970 == 1_728_000_123.5)
    }

    @Test("Invalid persisted recording metadata cannot become an observed date")
    func contextValidation() throws {
        #expect(throws: ObservationRecordingContextError.invalidStartDate) {
            try ObservationRecordingContext(startedAt: Date(timeIntervalSinceReferenceDate: .infinity),
                                            timeZoneIdentifier: "UTC")
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "id": UUID().uuidString, "startedAt": 0, "timeZoneIdentifier": "No/SuchZone"
        ])
        #expect(throws: ObservationRecordingContextError.invalidTimeZone) {
            try JSONDecoder().decode(ObservationRecordingContext.self, from: data)
        }
    }

    @Test("Fingerprints validate SHA-256 representation and retain no file locator")
    func fingerprintRoundTripAndValidation() throws {
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let fingerprint = try ObservationFileFingerprint(sha256: expected.uppercased(), byteCount: 3)
        #expect(fingerprint.sha256 == expected)
        let encoded = try JSONEncoder().encode(fingerprint)
        #expect(try JSONDecoder().decode(ObservationFileFingerprint.self, from: encoded) == fingerprint)
        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == ["sha256", "byteCount"])
        #expect(throws: ObservationFileFingerprintValidationError.invalidDigest) {
            try ObservationFileFingerprint(sha256: String(repeating: "g", count: 64), byteCount: 3)
        }
        #expect(throws: ObservationFileFingerprintValidationError.invalidByteCount) {
            try ObservationFileFingerprint(sha256: expected, byteCount: -1)
        }
        let malformed = try JSONSerialization.data(withJSONObject: ["sha256": "short", "byteCount": 3])
        #expect(throws: ObservationFileFingerprintValidationError.invalidDigest) {
            try JSONDecoder().decode(ObservationFileFingerprint.self, from: malformed)
        }
    }
}
