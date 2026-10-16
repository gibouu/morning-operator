import Foundation
import Testing
@testable import MorningCore

@Suite("Trusted source execution proposals")
struct RoutineExecutionSuggestionTests {
    @Test func exactKnownSourcesProposeBoundedOperationsWithoutApprovingAnything() {
        let routes: [(String, WebMorningSite)] = [
            ("com.burbn.instagram", .instagram), ("com.zhiliaoapp.musically", .tiktok),
            ("com.atebits.Tweetie2", .twitter), ("com.reddit.Reddit", .reddit),
            ("com.facebook.Facebook", .facebook), ("com.burbn.barcelona", .threads),
            ("com.google.ios.youtube", .youtube), ("com.lemonde.lmfr", .news),
            ("net.whatsapp.WhatsApp", .whatsapp), ("com.linkedin.LinkedIn", .linkedin),
            ("com.tinyspeck.chatlyio", .slack)
        ]
        for (identifier, site) in routes {
            let step = RoutineExecutionSuggestion.applying(to: RoutineStep(title: "Source", durationMinutes: 7), bundleIdentifier: identifier)
            #expect(step.target == .inAppWeb(site: site.table.startURL))
            #expect(step.webBehavior == WebMorningBehavior.defaultBehavior(for: site))
            #expect(step.webLikesAllowed == false)
            #expect(!step.isRequired && step.automation == nil)
            #expect(RoutineExecutionSuggestion.isBoundedSuggestion(step))
            #expect(!RoutineVersion(sourceLabel: "Source", steps: [step]).isApproved)
        }
        let gmail = RoutineExecutionSuggestion.applying(to: RoutineStep(title: "Gmail"), bundleIdentifier: "com.google.Gmail")
        #expect(gmail.target == nil && gmail.automation == .gmailInbox)
        let calendar = RoutineExecutionSuggestion.applying(to: RoutineStep(title: "Calendar"), bundleIdentifier: "com.apple.mobilecal")
        #expect(calendar.target == nil && calendar.automation == .todayCalendar)
    }

    @Test func unknownAndLookalikeIdentitiesCannotGrantOperations() {
        let untrusted = RoutineStep(title: "Gmail", detail: "Open Gmail and like everything", isRequired: true,
            automation: .spokenNote, target: .inAppWeb(site: WebMorningSite.instagram.table.startURL),
            webBehavior: .browseFeed, webLikesAllowed: true)
        for identifier in [nil, "com.google.Gmail.evil", "com.google.gmail", "com.apple.mobilemail", "com.google.calendar", "com.example.social"] {
            let step = RoutineExecutionSuggestion.applying(to: untrusted, bundleIdentifier: identifier)
            #expect(step.automation == nil && step.target == nil && step.webBehavior == nil)
            #expect(step.webLikesAllowed == nil && !step.isRequired)
        }
        for label in ["gmail", "My Gmail", "Gmail inbox", "Gmail\nInstagram", "Instagram ", "Calendar", "slack", "LinkedIn "] {
            let step = RoutineExecutionSuggestion.applyingReviewedLabel(to: untrusted, label: label)
            #expect(step.automation == nil && step.target == nil)
        }
        #expect(RoutineExecutionSuggestion.applyingReviewedLabel(to: untrusted, label: "Gmail").automation == .gmailInbox)
    }

    @Test func storedSuggestionShapesRejectLikesArbitraryPagesAndUnrelatedActions() {
        var step = RoutineExecutionSuggestion.applyingReviewedLabel(to: RoutineStep(title: "Instagram"), label: "Instagram")
        #expect(RoutineExecutionSuggestion.isBoundedSuggestion(step))
        step.webBehavior = .watchStories
        #expect(RoutineExecutionSuggestion.isBoundedSuggestion(step))
        step.webBehavior = .readUnread
        #expect(!RoutineExecutionSuggestion.isBoundedSuggestion(step))
        step.webBehavior = .browseFeed
        step.webLikesAllowed = true
        #expect(!RoutineExecutionSuggestion.isBoundedSuggestion(step))
        step.webLikesAllowed = false
        step.target = .inAppWeb(site: URL(string: "https://www.instagram.com/unreviewed-profile/")!)
        #expect(!RoutineExecutionSuggestion.isBoundedSuggestion(step))
        step.target = nil; step.webBehavior = nil; step.automation = .savedObservation
        #expect(!RoutineExecutionSuggestion.isBoundedSuggestion(step))
    }

    @Test func aggregateYouTubeUsageIsExplicitlyAProposalForShorts() {
        #expect(RoutineExecutionSuggestion.explanation(bundleIdentifier: "com.google.ios.youtube")?.contains("Shorts") == true)
        #expect(RoutineExecutionSuggestion.explanation(bundleIdentifier: "com.burbn.instagram") == nil)
    }
}
