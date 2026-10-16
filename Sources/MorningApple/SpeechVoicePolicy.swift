import MorningCore
import Foundation

public enum SpeechVoiceQuality: Int, Sendable, Equatable {
    case standard = 1, enhanced, premium

    public var displayName: String {
        switch self {
        case .standard: AppLanguage.localized("Standard", bundle: .module)
        case .enhanced: AppLanguage.localized("Enhanced", bundle: .module)
        case .premium: AppLanguage.localized("Premium", bundle: .module)
        }
    }
}

public struct SpeechVoiceDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: SpeechVoiceQuality

    public init(id: String, name: String, language: String, quality: SpeechVoiceQuality = .standard) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
    }
}

/// Ranking does not equate quality with a particular Siri voice or assume a voice is installed.
/// Callers supply only voices that AVSpeechSynthesisVoice reports as available.
enum SpeechVoicePolicy {
    static func recommended(from voices: [SpeechVoiceDescriptor], language: String,
                            systemVoiceID: String? = nil) -> SpeechVoiceDescriptor? {
        let matching = voices.filter { languageMatch($0.language, language) > 0 }
        return matching.sorted { lhs, rhs in
            let leftLanguage = languageMatch(lhs.language, language)
            let rightLanguage = languageMatch(rhs.language, language)
            if leftLanguage != rightLanguage { return leftLanguage > rightLanguage }
            if lhs.quality != rhs.quality { return lhs.quality.rawValue > rhs.quality.rawValue }
            if (lhs.id == systemVoiceID) != (rhs.id == systemVoiceID) { return lhs.id == systemVoiceID }
            return lhs.id < rhs.id
        }.first
    }

    static func languageMatch(_ candidate: String, _ preferred: String) -> Int {
        let left = canonicalLanguage(candidate)
        let right = canonicalLanguage(preferred)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 2 }
        let leftParts = left.components(separatedBy: "-")
        let rightParts = right.components(separatedBy: "-")
        let leftScript = leftParts.dropFirst().first { $0.count == 4 }
        let rightScript = rightParts.dropFirst().first { $0.count == 4 }
        if let leftScript, let rightScript, leftScript != rightScript { return 0 }
        return leftParts.first == rightParts.first ? 1 : 0
    }

    static func previewText(language: String) -> String {
        switch canonicalLanguage(language).split(separator: "-").first {
        case "fr": "Bonjour. Prenons un moment pour commencer votre journée en douceur."
        case "es": "Buenos días. Empecemos el día con un momento de calma."
        case "de": "Guten Morgen. Beginnen wir den Tag mit einem ruhigen Moment."
        case "it": "Buongiorno. Iniziamo la giornata con un momento di calma."
        case "pt": "Bom dia. Vamos começar o dia com um momento de calma."
        case "ja": "おはようございます。落ち着いた気持ちで一日を始めましょう。"
        case "ko": "좋은 아침이에요. 여유롭게 하루를 시작해 볼까요."
        case "zh": "早上好。让我们从容地开始新的一天。"
        default: "Good morning. Let's make a little room for your day."
        }
    }

    private static func canonicalLanguage(_ language: String) -> String {
        language.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}
