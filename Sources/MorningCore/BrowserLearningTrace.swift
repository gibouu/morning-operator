import Foundation

/// A bounded route category associated with actual non-input gestures. No page
/// prose, input contents, identifiers, URLs or tap targets cross this boundary.
public struct BrowserLearningSegment: Codable, Equatable, Sendable {
    public let behavior: WebMorningBehavior
    public let startSeconds: Double
    public let endSeconds: Double
    public let gestures: Int

    public init?(behavior: WebMorningBehavior, startSeconds: Double, endSeconds: Double, gestures: Int) {
        guard startSeconds.isFinite, endSeconds.isFinite, (0...900).contains(startSeconds),
              (startSeconds...900).contains(endSeconds), (1...100_000).contains(gestures) else { return nil }
        self.behavior = behavior; self.startSeconds = startSeconds
        self.endSeconds = endSeconds; self.gestures = gestures
    }

    private enum CodingKeys: String, CodingKey { case behavior, startSeconds, endSeconds, gestures }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let result = try Self(behavior: values.decode(WebMorningBehavior.self, forKey: .behavior),
            startSeconds: values.decode(Double.self, forKey: .startSeconds),
            endSeconds: values.decode(Double.self, forKey: .endSeconds), gestures: values.decode(Int.self, forKey: .gestures)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid browser segment"))
        }
        self = result
    }
}

/// Partial observations made during one explicitly started browser lesson. An
/// interval is between observed gestures, not proof of continuous attention.
/// Likes are deliberately absent: observing a gesture cannot authorize a like.
public struct BrowserLearningTrace: Codable, Equatable, Sendable {
    public static let maximumSegments = 16
    public let site: WebMorningSite
    public let durationSeconds: Double
    public let segments: [BrowserLearningSegment]

    public init?(site: WebMorningSite, durationSeconds: Double, segments: [BrowserLearningSegment]) {
        guard durationSeconds.isFinite, (0...900).contains(durationSeconds), !segments.isEmpty,
              Self.validSegments(segments, site: site, durationSeconds: durationSeconds) else { return nil }
        self.site = site; self.durationSeconds = durationSeconds; self.segments = segments
    }

    static func validSegments(_ segments: [BrowserLearningSegment], site: WebMorningSite, durationSeconds: Double) -> Bool {
        guard segments.count <= maximumSegments else { return false }
        var lastEnd = 0.0
        for segment in segments {
            guard observedBehaviors(for: site).contains(segment.behavior), segment.startSeconds >= lastEnd,
                  segment.endSeconds <= durationSeconds else { return false }
            lastEnd = segment.endSeconds
        }
        return true
    }

    public static func observedBehaviors(for site: WebMorningSite) -> [WebMorningBehavior] {
        // An unread state is not established by a known messaging root route.
        switch site {
        case .gmail, .whatsapp, .slack: []
        case .linkedin: [.browseFeed]
        default: WebMorningBehavior.availableBehaviors(for: site)
        }
    }

    public func segmentText(at index: Int, french: Bool = AppLanguage.isFrench) -> String {
        let segment = segments[index]
        let interval = "\(Self.seconds(segment.startSeconds))–\(Self.seconds(segment.endSeconds))"
        return french
            ? "Séquence observée \(index + 1) — \(site.displayName) : \(Self.activity(segment.behavior, french: true)) ; \(interval) secondes ; \(segment.gestures) gestes."
            : "Observed sequence \(index + 1) — \(site.displayName): \(Self.activity(segment.behavior, french: false)); \(interval) seconds; \(segment.gestures) gestures."
    }

    public func renderedText(french: Bool = AppLanguage.isFrench) -> String {
        let header = french
            ? "Apprentissage explicite dans le navigateur — \(site.displayName) ; \(Self.seconds(durationSeconds)) secondes."
            : "Explicit browser lesson — \(site.displayName); \(Self.seconds(durationSeconds)) seconds."
        let warning = french
            ? "Couverture partielle : catégories de pages connues et gestes hors saisie uniquement. Les intervalles relient des gestes observés, sans prouver une attention continue. Aucun texte de page, champ, destination de clic ou contenu privé conservé. Un geste peut inclure un like observé, mais ne l’identifie ni ne l’autorise. Les prochaines actions restent des propositions à valider."
            : "Partial coverage: known route categories and non-input gestures only. Intervals connect observed gestures, without proving continuous attention. No page text, fields, click targets or private content retained. A gesture may include an observed like, but neither identifies nor authorizes it. Future actions remain proposals for review."
        return ([header] + segments.indices.map { segmentText(at: $0, french: french) } + [warning]).joined(separator: "\n")
    }

    public func proposedTitle(at index: Int, french: Bool = AppLanguage.isFrench) -> String {
        "\(index + 1). \(site.displayName) · \(Self.activity(segments[index].behavior, french: french))"
    }

    /// A candidate for explicit review, never execution permission. The caller
    /// must bind the segment to the exact archived trace before using this.
    public func applying(to step: RoutineStep, segment index: Int) -> RoutineStep {
        var result = RoutineExecutionSuggestion.applying(to: step, bundleIdentifier: nil)
        guard segments.indices.contains(index) else { return result }
        result.target = .inAppWeb(site: site.table.startURL)
        result.webBehavior = segments[index].behavior
        result.webLikesAllowed = false
        return result
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func activity(_ behavior: WebMorningBehavior, french: Bool) -> String {
        switch behavior {
        case .browseFeed: french ? "parcourir le fil" : "browsing the feed"
        case .watchVideos: french ? "parcourir les vidéos" : "browsing videos"
        case .watchStories: french ? "parcourir les stories" : "browsing stories"
        case .readHeadlines: french ? "parcourir les titres" : "browsing headlines"
        case .readUnread: french ? "consulter les non-lus" : "browsing unread information"
        }
    }

    private enum CodingKeys: String, CodingKey { case site, durationSeconds, segments }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        guard let result = try Self(site: values.decode(WebMorningSite.self, forKey: .site),
            durationSeconds: values.decode(Double.self, forKey: .durationSeconds),
            segments: values.decode([BrowserLearningSegment].self, forKey: .segments)) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid browser trace"))
        }
        self = result
    }
}
