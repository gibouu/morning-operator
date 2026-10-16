import MorningCore
import Foundation

public enum CaptureDestination: String, Codable, CaseIterable, Sendable {
    case thought, dream, reminder, calendar
}

/// A suggestion for the capture review screen, never an authorization to write to EventKit.
public struct ParsedCaptureRequest: Sendable, Equatable {
    public let originalText: String
    public let content: String
    public let destination: CaptureDestination
    public let suggestedDate: Date?
    public let matchedDatePhrase: String?
    public let dateExplanation: String?
    public let needsDateReview: Bool
}

/// Small, deterministic English/French grammar. Unknown or ambiguous dates stay unresolved.
/// In particular, a dream mentioning a future time does not become a reminder.
public enum CaptureRequestParser {
    public static func parse(
        _ text: String,
        now: Date = Date(),
        calendar: Calendar = .current,
        morningHour: Int = 9
    ) -> ParsedCaptureRequest {
        let original = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let classification = classify(original)
        guard classification.destination == .reminder || classification.destination == .calendar else {
            return ParsedCaptureRequest(originalText: original, content: classification.content,
                destination: classification.destination, suggestedDate: nil, matchedDatePhrase: nil,
                dateExplanation: nil, needsDateReview: false)
        }

        let body = classification.content
        // Only one supported expression at the end of the request is accepted. This avoids
        // stripping times out of quoted narrative or silently choosing between two deadlines.
        let matches = dateMatches(body)
        guard matches.count == 1, let match = matches.first,
              body[match.range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
        else { return unresolved(original, classification: classification) }

        let proposed: Date?
        let explanation: String
        switch match.kind {
        case .morning:
            guard (0...23).contains(morningHour),
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            else { return unresolved(original, classification: classification) }
            proposed = calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: tomorrow,
                matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
            explanation = AppLanguage.localized("Suggested \(String(format: "%02d:00", morningHour)) on the next calendar day in \(calendar.timeZone.identifier). Review the time before saving.", bundle: .module)
        case .relative(let seconds):
            proposed = now.addingTimeInterval(seconds)
            explanation = AppLanguage.localized("Calculated from capture time using \(Int(seconds / 60)) elapsed minutes. Review the date and time before saving.", bundle: .module)
        }
        guard let proposed, proposed.timeIntervalSinceReferenceDate.isFinite else {
            return unresolved(original, classification: classification)
        }
        let content = String(body[..<match.range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
        guard !content.isEmpty else { return unresolved(original, classification: classification) }
        return ParsedCaptureRequest(originalText: original, content: content,
            destination: classification.destination, suggestedDate: proposed,
            matchedDatePhrase: String(body[match.range]), dateExplanation: explanation, needsDateReview: true)
    }

    private struct Classification {
        let destination: CaptureDestination
        let content: String
    }

    private static func classify(_ text: String) -> Classification {
        let prefixes: [(CaptureDestination, String)] = [
            (.dream, #"^(?:dream\s*:|r[êe]ve\s*:)\s*"#),
            (.reminder, #"^(?:remind\s+me\s+to\s+|remind\s+me\s+|reminder\s*:\s*|rappelle[- ]moi\s+de\s+|rappelle[- ]moi\s+|rappel\s*:\s*)"#),
            (.calendar, #"^(?:add\s+to\s+my\s+calendar\s*:?\s*|calendar\s*:\s*|schedule\s+|calendrier\s*:\s*|planifie\s+)"#),
            (.thought, #"^(?:thought\s*:|idea\s*:|pens[ée]e\s*:|id[ée]e\s*:)\s*"#)
        ]
        for (destination, pattern) in prefixes {
            if let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return Classification(destination: destination,
                    content: String(text[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        if text.range(of: #"^(?:I\s+dream(?:ed|t)\b|j['’]ai\s+r[êe]v[ée]\b)"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return Classification(destination: .dream, content: text)
        }
        return Classification(destination: .thought, content: text)
    }

    private enum DateKind { case morning, relative(TimeInterval) }
    private struct DateMatch {
        let range: Range<String.Index>
        let kind: DateKind
    }

    private static func dateMatches(_ text: String) -> [DateMatch] {
        var result: [DateMatch] = []
        let full = NSRange(text.startIndex..<text.endIndex, in: text)
        if let regex = try? NSRegularExpression(pattern: #"\b(?:tomorrow\s+morning|next\s+morning|demain\s+matin)\b"#, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: full) {
                if let range = Range(match.range, in: text) { result.append(DateMatch(range: range, kind: .morning)) }
            }
        }
        let pattern = #"\b(?:in|dans)\s*(\d{1,4}|one|two|three|four|five|six|seven|eight|nine|ten|une?|deux|trois|quatre)\s*(hours?|hrs?|h|minutes?|mins?|heures?)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            for match in regex.matches(in: text, range: full) {
                guard let range = Range(match.range, in: text),
                      let numberRange = Range(match.range(at: 1), in: text),
                      let unitRange = Range(match.range(at: 2), in: text)
                else { continue }
                let words = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
                    "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
                    "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4]
                let value = String(text[numberRange]).lowercased()
                let amount = Int(value) ?? words[value] ?? 0
                let multiplier = text[unitRange].lowercased().hasPrefix("m") ? 60 : 3_600
                let seconds = amount * multiplier
                // Zero, implausibly long intervals and multiple dates require manual review.
                guard seconds > 0, seconds <= 30 * 86_400 else { continue }
                result.append(DateMatch(range: range, kind: .relative(TimeInterval(seconds))))
            }
        }
        return result
    }

    private static func unresolved(_ original: String, classification: Classification) -> ParsedCaptureRequest {
        ParsedCaptureRequest(originalText: original, content: classification.content,
            destination: classification.destination, suggestedDate: nil, matchedDatePhrase: nil,
            dateExplanation: AppLanguage.localized("No single supported date was resolved. Choose a date and time, or save a reminder without a date.", bundle: .module),
            needsDateReview: true)
    }
}
