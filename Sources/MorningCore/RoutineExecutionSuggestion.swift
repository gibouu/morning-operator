import Foundation

/// Fixed proposals for the next morning. Source recognition does not approve a
/// routine, establish past actions, select an account, or authorize likes.
public enum RoutineExecutionSuggestion {
    public static func applying(to step: RoutineStep, bundleIdentifier: String?) -> RoutineStep {
        var result = manual(step)
        guard let bundleIdentifier else { return result }
        switch bundleIdentifier {
        case "com.google.Gmail": result.automation = .gmailInbox
        case "com.apple.mobilecal": result.automation = .todayCalendar
        default:
            guard let site = browserSite(bundleIdentifier: bundleIdentifier),
                  let behavior = WebMorningBehavior.defaultBehavior(for: site) else { return result }
            result.target = .inAppWeb(site: site.table.startURL)
            result.webBehavior = behavior
            result.webLikesAllowed = false
        }
        return result
    }

    /// These exact labels are human-reviewed visible context, not installed app IDs.
    public static func applyingReviewedLabel(to step: RoutineStep, label: String) -> RoutineStep {
        applying(to: step, bundleIdentifier: bundleIdentifier(forReviewedLabel: label))
    }

    /// Only this fixed identity table can join a reviewed context with an exact
    /// Screen Time identifier. Display-name similarity grants no identity.
    public static func bundleIdentifier(forReviewedLabel label: String) -> String? {
        let bundleIdentifier: String?
        switch label {
        case "Instagram": bundleIdentifier = "com.burbn.instagram"
        case "TikTok": bundleIdentifier = "com.zhiliaoapp.musically"
        case "X", "Twitter": bundleIdentifier = "com.atebits.Tweetie2"
        case "Reddit": bundleIdentifier = "com.reddit.Reddit"
        case "Facebook": bundleIdentifier = "com.facebook.Facebook"
        case "Threads": bundleIdentifier = "com.burbn.barcelona"
        case "LinkedIn": bundleIdentifier = "com.linkedin.LinkedIn"
        case "Slack": bundleIdentifier = "com.tinyspeck.chatlyio"
        case "YouTube", "YouTube Shorts": bundleIdentifier = "com.google.ios.youtube"
        case "Le Monde": bundleIdentifier = "com.lemonde.lmfr"
        case "WhatsApp": bundleIdentifier = "net.whatsapp.WhatsApp"
        case "Gmail": bundleIdentifier = "com.google.Gmail"
        case "Apple Calendar", "Calendrier Apple": bundleIdentifier = "com.apple.mobilecal"
        default: bundleIdentifier = nil
        }
        return bundleIdentifier
    }

    /// Structural decoding gate. Archive-backed callers must separately recompute
    /// the exact proposal from its source; this does not validate source identity.
    public static func isBoundedSuggestion(_ step: RoutineStep) -> Bool {
        guard step.observationReference == nil, step.webLikesAllowed != true else { return false }
        if step.target == nil, step.webBehavior == nil {
            return step.automation == nil || step.automation == .gmailInbox || step.automation == .todayCalendar
        }
        guard step.automation == nil, case let .inAppWeb(url) = step.target,
              let site = WebMorningSite(url: url), url == site.table.startURL,
              site != .gmail, let behavior = step.webBehavior,
              WebMorningBehavior.availableBehaviors(for: site).contains(behavior) else { return false }
        return true
    }

    public static func explanation(bundleIdentifier: String) -> String? {
        guard bundleIdentifier == "com.google.ios.youtube" else { return nil }
        return AppLanguage.isFrench
            ? "Proposition : parcourir YouTube Shorts dans MORE. Screen Time ne précise pas les vidéos que vous regardiez."
            : "Suggested: browse YouTube Shorts in MORE. Screen Time does not identify the videos you watched."
    }

    private static func manual(_ step: RoutineStep) -> RoutineStep {
        var result = step
        result.isRequired = false
        result.automation = nil; result.target = nil; result.observationReference = nil
        result.webBehavior = nil; result.webLikesAllowed = nil
        return result
    }

    private static func browserSite(bundleIdentifier: String) -> WebMorningSite? {
        switch bundleIdentifier {
        case "com.burbn.instagram": .instagram
        case "com.zhiliaoapp.musically": .tiktok
        case "com.atebits.Tweetie2": .twitter
        case "com.reddit.Reddit": .reddit
        case "com.facebook.Facebook": .facebook
        case "com.burbn.barcelona": .threads
        case "com.linkedin.LinkedIn": .linkedin
        case "com.tinyspeck.chatlyio": .slack
        case "com.google.ios.youtube": .youtube
        case "com.lemonde.lmfr", "fr.lemonde.lemonde": .news
        case "net.whatsapp.WhatsApp": .whatsapp
        default: nil
        }
    }
}
