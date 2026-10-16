import Foundation
import Testing
@testable import MorningCore

@Suite("Instagram stays in the routine browser")
struct InstagramRoutineRoutingTests {
    private let home = WebMorningSite.instagram.table.startURL

    @Test func legacyAppChoicesResolveToTheBrowserAndKeepValidProfiles() {
        for detail in [nil, "", " \n", "a/b?c", "name&username=other", String(repeating: "a", count: 31), "éloïse"] as [String?] {
            let target = RoutineStepTarget.externalApp(.instagram, detail: detail)
            #expect(target.routineExecutionTarget == .inAppWeb(site: home))
            #expect(target.externalURL == nil)
            #expect(target.destination == .inMORE(.instagram))
            #expect(target.integrationRoute == .browser)
        }
        for detail in ["nasa", "@nasa", " @nasa \n", "person.name_12"] {
            let target = RoutineStepTarget.externalApp(.instagram, detail: detail)
            let name = detail.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
            #expect(target.routineExecutionTarget == .inAppWeb(site: URL(string: "https://www.instagram.com/\(name)/")!))
            #expect(target.externalURL == nil)
            #expect(target.routineExecutionTarget.routineExecutionTarget == target.routineExecutionTarget)
        }
        // The low-level native scheme remains available outside routine execution.
        #expect(StepApp.instagram.url(detail: "@nasa")?.absoluteString == "instagram://user?username=nasa")
    }

    @Test func savedSafariInstagramPagesKeepTheirPathInsideMORE() {
        for (detail, expected) in [
            ("https://www.instagram.com/reels/?next=%2Fperson%2F#clip", "https://www.instagram.com/reels/?next=%2Fperson%2F#clip"),
            ("instagram.com/person/", "https://instagram.com/person/"),
            ("http://instagram.com:80/p/example/?img_index=2", "https://instagram.com/p/example/?img_index=2")
        ] {
            let target = RoutineStepTarget.externalApp(.safari, detail: detail)
            #expect(target.routineExecutionTarget == .inAppWeb(site: URL(string: expected)!))
            #expect(target.externalURL == nil)
            #expect(target.destination == .inMORE(.instagram))
            #expect(target.integrationRoute == .browser)
        }
        for detail in ["https://instagram.com.evil.example/person/", "https://evil.example/?next=https://instagram.com/",
                       "https://user:secret@instagram.com/", "https://instagram.com:8443/", "not a URL"] {
            let target = RoutineStepTarget.externalApp(.safari, detail: detail)
            #expect(target.routineExecutionTarget == target)
        }
    }

    @Test func aSavedRoutineStartsAndAdvancesToInstagramWithoutAnExternalURL() throws {
        let first = RoutineStep(title: "Instagram", target: .externalApp(.instagram, detail: nil))
        let mail = RoutineStep(title: "Mail", target: .externalApp(.mail, detail: nil))
        let profile = RoutineStep(title: "Profile", target: .externalApp(.instagram, detail: "@nasa"))
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "Saved personal routine",
            steps: [first, mail, profile], isApproved: true))
        try session.start()
        session = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        #expect(session.currentStep?.target == first.target)
        #expect(session.currentStep?.target?.routineExecutionTarget == .inAppWeb(site: home))
        #expect(session.currentStep?.target?.externalURL == nil)
        try session.advance()
        #expect(session.currentStep?.target?.externalURL?.absoluteString == "message://")
        let next = try #require(StepNavigation.nextStep(in: session))
        #expect(next.id == profile.id)
        #expect(next.target?.routineExecutionTarget == .inAppWeb(site: URL(string: "https://www.instagram.com/nasa/")!))
        #expect(next.target?.externalURL == nil)
        try session.pause()
        if case let .advance(resumeFirst, target) = StepNavigation.decide(session: session,
            sessionID: session.id, stepID: mail.id) {
            #expect(resumeFirst)
            #expect(target?.routineExecutionTarget == next.target?.routineExecutionTarget)
        } else { Issue.record("A paused routine must retain its next Instagram route.") }
        try session.resume()
        try session.advance()
        #expect(session.currentStep?.id == profile.id)
        #expect(session.currentStep?.target?.externalURL == nil)
    }

    @Test func resolutionPreservesSavedIdentityApprovalLabelsAndManualAuthority() throws {
        let target = RoutineStepTarget.externalApp(.instagram, detail: "@nasa")
        let label = try #require(RoutineStepSourceLabel(target: target, label: "My saved profile"))
        let step = RoutineStep(title: "Instagram", durationMinutes: 7, target: target, sourceLabel: label)
        let routine = RoutineVersion(sourceLabel: "Personal choice", steps: [step], isApproved: true)
        let restored = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(routine))
        #expect(restored == routine)
        #expect(restored.isApproved)
        let saved = try #require(restored.steps.first)
        #expect(saved.target == target)
        #expect(saved.reviewedSourceLabel == "My saved profile")
        #expect(saved.webBehavior == nil)
        #expect(saved.webLikesAllowed == nil)
        #expect(saved.target?.routineExecutionTarget != target)
        #expect(label.text(for: .externalApp(.instagram, detail: "other")) == nil)
        #expect(try JSONDecoder().decode(RoutineStepTarget.self, from: JSONEncoder().encode(target)) == target)
    }

    @Test func theBrowserDestinationUsesTheChosenLanguage() {
        let target = RoutineStepTarget.externalApp(.instagram, detail: "private_person")
        #expect(target.destination.displayName(locale: Locale(identifier: "en")) == "Instagram in MORE")
        #expect(target.destination.displayName(locale: Locale(identifier: "fr")) == "Instagram dans MORE")
        #expect(!target.destination.displayName(locale: Locale(identifier: "fr")).contains("private_person"))
    }

    @Test func legacyRoutingDescribesManualBrowsingEvenWithStaleBrowserFlags() {
        let legacy = RoutineStep(title: "Instagram", target: .externalApp(.instagram, detail: nil),
            webBehavior: .watchStories, webLikesAllowed: true)
        let manual = RoutineStep(title: "Instagram", target: .inAppWeb(site: home))
        #expect(legacy.executionDescription == manual.executionDescription)
        // Resolution must not turn stale browser fields into a reviewed web target.
        if case .inAppWeb = legacy.target { Issue.record("A legacy app choice must retain its original authority.") }
    }

    @Test func otherNativeBrowserAndConnectedRoutesDoNotChange() {
        let targets: [RoutineStepTarget] = [
            .externalApp(.messages, detail: "+33612345678"), .externalApp(.mail, detail: nil),
            .externalApp(.whatsapp, detail: "+33612345678"), .externalApp(.calendar, detail: nil),
            .externalApp(.maps, detail: "Paris"), .externalApp(.safari, detail: "https://example.com/"),
            .inAppWeb(site: URL(string: "https://www.instagram.com/accounts/login/")!),
            .inAppWeb(site: WebMorningSite.gmail.table.startURL),
            .shortcut(name: "Read Messages", input: "today"),
            .connectedAPI(service: "gmail", connectionID: "account", tool: "GMAIL_FETCH_EMAILS", argumentsJSON: "{}")
        ]
        for target in targets { #expect(target.routineExecutionTarget == target) }
        #expect(RoutineStepTarget.externalApp(.whatsapp, detail: nil).externalURL?.absoluteString == "whatsapp://")
        #expect(RoutineStepTarget.externalApp(.messages, detail: nil).integrationRoute == .nativeIOS)
        #expect(RoutineStepTarget.shortcut(name: "Test", input: "").integrationRoute == .nativeIOS)
        #expect(RoutineStepTarget.connectedAPI(service: "gmail", connectionID: "account", tool: "READ", argumentsJSON: "{}").integrationRoute == .api)
    }
}
