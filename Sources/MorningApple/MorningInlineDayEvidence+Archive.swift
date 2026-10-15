import MorningCore

extension ObservationArchive {
    /// The explicit saved observation day is the only day assignment. Import time,
    /// file metadata and recording context are never substituted for an absent day.
    public var inlineDayEvidence: [MorningInlineDayEvidence] {
        get throws {
            try entries.map { entry in
                let origin: MorningInlineDayEvidenceOrigin
                switch entry.origin {
                case .human: origin = .human
                case .synthetic: origin = .synthetic
                case .automated: origin = .automated
                case .unknown: origin = .unknown
                }
                return try MorningInlineDayEvidence(id: entry.id, observedAt: entry.observedDate?.date,
                    timeZoneIdentifier: entry.observedDate?.timeZoneIdentifier, origin: origin)
            }
        }
    }
}
