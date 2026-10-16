import Foundation
import Testing
@testable import MorningCore

@Suite("Step targets: app schemes")
struct StepAppSchemeTests {
    @Test("Each app opens its home screen without a detail")
    func homeScreens() {
        #expect(StepApp.messages.url()?.absoluteString == "sms:")
        #expect(StepApp.mail.url()?.absoluteString == "message://")
        #expect(StepApp.whatsapp.url()?.absoluteString == "whatsapp://")
        #expect(StepApp.instagram.url()?.absoluteString == "instagram://app")
        #expect(StepApp.calendar.url()?.absoluteString == "calshow://")
        #expect(StepApp.maps.url()?.absoluteString == "maps://")
        #expect(StepApp.safari.url() == nil)
    }

    @Test("A valid detail opens the right screen")
    func deepLinks() {
        #expect(StepApp.messages.url(detail: "+33 6 12 34 56 78")?.absoluteString == "sms:+33612345678")
        #expect(StepApp.messages.url(detail: "sou@example.com")?.absoluteString == "sms:sou@example.com")
        #expect(StepApp.whatsapp.url(detail: "+33 (6) 12-34")?.absoluteString == "whatsapp://send?phone=3361234")
        #expect(StepApp.instagram.url(detail: "@nasa")?.absoluteString == "instagram://user?username=nasa")
        #expect(StepApp.mail.url(detail: "<abc.123@mail.example.com>")?.absoluteString == "message://%3Cabc.123@mail.example.com%3E")
        #expect(StepApp.maps.url(detail: "Gare de Lyon & co")?.absoluteString == "maps://?q=Gare%20de%20Lyon%20%26%20co")
        #expect(StepApp.safari.url(detail: "lemonde.fr")?.absoluteString == "https://lemonde.fr")
        #expect(StepApp.safari.url(detail: "http://example.com/a?b=1")?.absoluteString == "http://example.com/a?b=1")
    }

    @Test("Hostile details fall back to the home screen, never into the URL")
    func hostileDetails() {
        #expect(StepApp.messages.url(detail: "123;rm -rf")?.absoluteString == "sms:")
        #expect(StepApp.messages.url(detail: "12")?.absoluteString == "sms:")
        #expect(StepApp.whatsapp.url(detail: "abc")?.absoluteString == "whatsapp://")
        #expect(StepApp.instagram.url(detail: "a/b?c")?.absoluteString == "instagram://app")
        #expect(StepApp.mail.url(detail: "no at sign")?.absoluteString == "message://")
        #expect(StepApp.safari.url(detail: "javascript:alert(1)") == nil)
        #expect(StepApp.safari.url(detail: "file:///etc/passwd") == nil)
        #expect(StepApp.safari.url(detail: "https://user:pw@example.com") == nil)
        #expect(StepApp.safari.url(detail: "not a url") == nil)
    }

    @Test("project.yml declares every queried scheme")
    func querySchemesDeclared() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let plist = try String(contentsOf: root.appendingPathComponent("Configuration/iOS-Info.plist"), encoding: .utf8)
        guard let start = plist.range(of: "<key>LSApplicationQueriesSchemes</key>") else {
            Issue.record("LSApplicationQueriesSchemes is missing"); return
        }
        let tail = plist[start.upperBound...]
        let block = tail[..<(tail.range(of: "</array>")?.upperBound ?? tail.endIndex)]
        for scheme in StepApp.querySchemes { #expect(block.contains("<string>\(scheme)</string>"), "\(scheme)") }
    }
}

@Suite("Step targets: model")
struct RoutineStepTargetTests {
    @Test("Targets round-trip, and a step without one still decodes")
    func codable() throws {
        let targets: [RoutineStepTarget] = [.externalApp(.instagram, detail: "nasa"), .externalApp(.calendar, detail: nil),
                                            .inAppWeb(site: URL(string: "https://www.instagram.com")!)]
        for target in targets {
            let step = RoutineStep(title: "T", durationMinutes: 10, target: target)
            let decoded = try JSONDecoder().decode(RoutineStep.self, from: JSONEncoder().encode(step))
            #expect(decoded.target == target)
        }
        let old = #"{"id":"\#(UUID().uuidString)","title":"Old","detail":"","kind":"custom","durationMinutes":5,"isRequired":false}"#
        #expect(try JSONDecoder().decode(RoutineStep.self, from: Data(old.utf8)).target == nil)
    }

    @Test("A page in MORE must be http(s), and unknown kinds are refused")
    func refusesDamage() {
        let bad = #"{"kind":"inAppWeb","site":"javascript:alert(1)"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineStepTarget.self, from: Data(bad.utf8)) }
        let unknown = #"{"kind":"teleport"}"#
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineStepTarget.self, from: Data(unknown.utf8)) }
    }

    @Test("The Lock Screen names only closed destinations")
    func destinations() {
        #expect(RoutineStepTarget.externalApp(.messages, detail: "+33612345678").destination == .app(.messages))
        #expect(RoutineStepTarget.inAppWeb(site: URL(string: "https://www.instagram.com/x")!).destination == .inMORE(.instagram))
        #expect(RoutineStepTarget.inAppWeb(site: URL(string: "https://secret-diary.example")!).destination == .inMORE(nil))
        #expect(!StepDestination.inMORE(nil).displayName.contains("secret"))
    }

    @Test("A model draft cannot assign a target")
    func draftsDropTargets() {
        let candidate = RoutineVersion(sourceLabel: "Model", steps: [
            RoutineStep(title: "Scroll", durationMinutes: 10, target: .externalApp(.instagram, detail: nil))])
        #expect(RoutineVersion.inferredDraft(from: candidate, preserving: nil).steps[0].target == nil)
    }
}

@Suite("Step timer")
struct StepTimerTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func timer(minutes: Int = 10) -> StepTimer { StepTimer(sessionID: UUID(), stepID: UUID(), minutes: minutes, at: t0) }

    @Test("Remaining time comes from absolute instants, so a suspension cannot drift it")
    func noDrift() {
        let timer = timer()
        #expect(timer.remaining(at: t0) == 600)
        // An hour suspended, then a read: the end is where it was.
        #expect(timer.remaining(at: t0.addingTimeInterval(599)) == 1)
        #expect(timer.remaining(at: t0.addingTimeInterval(3_600)) == 0)
        #expect(timer.isExpired(at: t0.addingTimeInterval(600)))
    }

    @Test("+2 min tapped twice against the same end adds two minutes once")
    func doubleTap() {
        var timer = timer()
        let seen = timer.endsAt
        let r1 = timer.extend(expectedEnd: seen, at: t0)
        #expect(r1 == .extended(seen.addingTimeInterval(120)))
        let r2 = timer.extend(expectedEnd: seen, at: t0)
        #expect(r2 == .duplicate)
        #expect(timer.endsAt == seen.addingTimeInterval(120))
        // A second, deliberate tap is made against the new end and applies.
        let r3 = timer.extend(expectedEnd: timer.endsAt, at: t0)
        #expect(r3 == .extended(seen.addingTimeInterval(240)))
    }

    @Test("A voice +2 min always applies; an expired step gets two minutes from now")
    func voiceAndExpired() {
        var timer = timer(minutes: 1)
        let late = t0.addingTimeInterval(300)
        let r4 = timer.extend(expectedEnd: nil, at: late)
        #expect(r4 == .extended(late.addingTimeInterval(120)))
    }

    @Test("Extensions stop at one hour")
    func limit() {
        var timer = timer()
        for _ in 0..<StepTimer.maximumExtensions { _ = timer.extend(expectedEnd: nil, at: t0) }
        let r5 = timer.extend(expectedEnd: nil, at: t0)
        #expect(r5 == .limitReached)
    }

    @Test("Time's up rings once per end, again after +2 min")
    func alertOnce() {
        var timer = timer(minutes: 1)
        let before = timer.claimAlert(at: t0)
        #expect(!before)
        let end = t0.addingTimeInterval(60)
        let first = timer.claimAlert(at: end)
        #expect(first)
        let again = timer.claimAlert(at: end.addingTimeInterval(5))
        #expect(!again)
        _ = timer.extend(expectedEnd: nil, at: end)
        let early = timer.claimAlert(at: end.addingTimeInterval(60))
        #expect(!early)
        let rang = timer.claimAlert(at: end.addingTimeInterval(120))
        #expect(rang)
    }

    @Test("Pause freezes the budget, resume shifts its end, and a saved timer keeps its opened mark")
    func pauseResumeRelaunch() throws {
        var timer = timer()
        timer.markOpened(at: t0)
        timer.pause(at: t0.addingTimeInterval(30))
        #expect(timer.remaining(at: t0.addingTimeInterval(3_600)) == 570)
        let data = try JSONEncoder().encode(timer)
        var restored = try JSONDecoder().decode(StepTimer.self, from: data)
        #expect(restored.openedAt == t0)
        restored.resume(at: t0.addingTimeInterval(3_600))
        #expect(restored.remaining(at: t0.addingTimeInterval(3_600)) == 570)
        #expect(restored.endsAt == t0.addingTimeInterval(4_170))
        restored.resume(at: t0.addingTimeInterval(3_601))
        #expect(restored.endsAt == t0.addingTimeInterval(4_170))
    }

    @Test("+2 min while paused adds two minutes to the frozen budget")
    func extendPaused() {
        var timer = timer()
        timer.pause(at: t0.addingTimeInterval(30))
        _ = timer.extend(expectedEnd: timer.endsAt, at: t0.addingTimeInterval(3_600))
        #expect(timer.remaining(at: t0.addingTimeInterval(3_600)) == 690)
        timer.resume(at: t0.addingTimeInterval(3_600))
        #expect(timer.remaining(at: t0.addingTimeInterval(3_600)) == 690)
    }

    @Test("Opened is recorded once")
    func openedOnce() {
        var timer = timer()
        timer.markOpened(at: t0)
        timer.markOpened(at: t0.addingTimeInterval(9))
        #expect(timer.openedAt == t0)
    }
}

@Suite("Next step")
struct StepNavigationTests {
    private let insta = RoutineStep(title: "Insta", durationMinutes: 5, target: .externalApp(.instagram, detail: nil))
    private let mail = RoutineStep(title: "Mail", durationMinutes: 5, target: .externalApp(.mail, detail: nil))
    private let tea = RoutineStep(title: "Tea", durationMinutes: 5)

    private func running(_ steps: [RoutineStep]) throws -> RoutineSession {
        var session = RoutineSession(routine: RoutineVersion(sourceLabel: "T", steps: steps, isApproved: true))
        try session.start()
        return session
    }

    @Test("Next from the current step opens the next step's app")
    func opensNext() throws {
        let session = try running([insta, mail, tea])
        #expect(StepNavigation.decide(session: session, sessionID: session.id, stepID: insta.id)
            == .advance(resumeFirst: false, then: .externalApp(.mail, detail: nil)))
    }

    @Test("A repeated Next from a step already left does nothing")
    func staleNext() throws {
        var session = try running([insta, mail, tea])
        try session.advance()
        #expect(StepNavigation.decide(session: session, sessionID: session.id, stepID: insta.id) == .stale)
        #expect(StepNavigation.decide(session: session, sessionID: UUID(), stepID: mail.id) == .stale)
    }

    @Test("Next to a step without a target opens nothing; a paused run resumes first")
    func noTargetAndPaused() throws {
        var session = try running([mail, tea])
        try session.pause()
        #expect(StepNavigation.decide(session: session, sessionID: session.id, stepID: mail.id)
            == .advance(resumeFirst: true, then: nil))
    }

    @Test("Without a morning, Next is unavailable")
    func unavailable() throws {
        #expect(StepNavigation.decide(session: nil, sessionID: nil, stepID: nil) == .unavailable)
        var session = try running([tea])
        try session.advance()
        #expect(StepNavigation.decide(session: session, sessionID: session.id, stepID: tea.id) == .unavailable)
    }

    @Test("Next links round-trip and nothing else parses")
    func links() {
        let session = UUID(), step = UUID()
        let parsed = StepNavigation.parseNext(StepNavigation.nextURL(sessionID: session, stepID: step))
        #expect(parsed?.sessionID == session && parsed?.stepID == step)
        #expect(StepNavigation.parseNext(URL(string: "more://morning")!) == nil)
        #expect(StepNavigation.parseNext(URL(string: "more://next?session=x&step=y")!) == nil)
        #expect(StepNavigation.parseNext(URL(string: "evil://next?session=\(session)&step=\(step)")!) == nil)
    }

    @Test("QA Next links stay in their own app scheme")
    func separateAppScheme() {
        let session = UUID(), step = UUID()
        let qa = StepNavigation.nextURL(sessionID: session, stepID: step, scheme: "moreqa")
        #expect(qa.scheme == "moreqa")
        let parsed = StepNavigation.parseNext(qa, scheme: "moreqa")
        #expect(parsed?.sessionID == session && parsed?.stepID == step)
        #expect(StepNavigation.parseNext(qa) == nil)
        #expect(StepNavigation.parseNext(StepNavigation.nextURL(sessionID: session, stepID: step), scheme: "moreqa") == nil)
    }

    @Test("Timer intents resolve the same isolated Activity namespace as the app")
    func activityWorkspace() {
        let id = UUID()
        let directory = URL(fileURLWithPath: "/tmp/MorningOperatorUITests-\(id.uuidString)")
        #expect(MorningActivityNamespace.workspace(directory: directory, isUITesting: true) == .testing(workspaceID: id))
        #expect(MorningActivityNamespace.workspace(directory: directory, isUITesting: false) == .production)
        #expect(MorningActivityNamespace.workspace(directory: URL(fileURLWithPath: "/tmp/unknown"), isUITesting: true) == nil)
    }

    @Test("The Lock Screen timer appears only for the current step's own timer")
    func activityTimer() throws {
        let session = try running([insta, tea])
        let own = StepTimer(sessionID: session.id, stepID: insta.id, minutes: 5, at: Date())
        let snapshot = MorningActivityProjection.snapshot(session: session, timer: own)
        #expect(snapshot?.state.stepTimer?.destination == .inMORE(.instagram))
        #expect(snapshot?.state.stepTimer?.hasNextStep == true)
        #expect(snapshot?.state.stepTimer?.nextDestination == nil)
        let foreign = StepTimer(sessionID: session.id, stepID: tea.id, minutes: 5, at: Date())
        #expect(MorningActivityProjection.snapshot(session: session, timer: foreign)?.state.stepTimer == nil)
    }

    @Test("A running timer keeps the activity fresh until its end, then it goes stale")
    func staleAtEnd() throws {
        let now = Date()
        let timer = MorningActivityStepTimer(stepID: UUID(), destination: .app(.maps), endsAt: now.addingTimeInterval(600),
                                             nextDestination: nil, hasNextStep: false)
        let state = try MorningActivityContentState(category: .custom, status: .running, completedSteps: 0, totalSteps: 1,
                                                    updatedAt: now, stepTimer: timer)
        #expect(state.staleDate(staleAfter: 60) == now.addingTimeInterval(600))
        let plain = try MorningActivityContentState(category: .custom, status: .running, completedSteps: 0, totalSteps: 1, updatedAt: now)
        #expect(plain.staleDate(staleAfter: 60) == now.addingTimeInterval(60))
    }
}

@Suite("Morning alarm plan")
struct MorningAlarmPlanTests {
    private let id = UUID()

    @Test("Off cancels every alarm MORE holds")
    func off() {
        let other = UUID()
        let change = MorningAlarmPlan.change(setting: .init(isEnabled: false), recorded: .init(id: id, hour: 7, minute: 0),
                                             systemAlarmIDs: [id, other], authorized: true)
        #expect(change.cancel == [id, other] && change.schedule == nil)
    }

    @Test("An unchanged, present alarm is kept and a leftover duplicate is cancelled")
    func keep() {
        let leftover = UUID()
        let change = MorningAlarmPlan.change(setting: .init(isEnabled: true, hour: 7, minute: 0),
            recorded: .init(id: id, hour: 7, minute: 0), systemAlarmIDs: [id, leftover], authorized: true)
        #expect(change.cancel == [leftover] && change.schedule == nil)
        let steady = MorningAlarmPlan.change(setting: .init(isEnabled: true, hour: 7, minute: 0),
            recorded: .init(id: id, hour: 7, minute: 0), systemAlarmIDs: [id], authorized: true)
        #expect(steady.isNothing)
    }

    @Test("A new time replaces the old alarm, never adds a second")
    func replace() {
        let change = MorningAlarmPlan.change(setting: .init(isEnabled: true, hour: 6, minute: 45),
            recorded: .init(id: id, hour: 7, minute: 0), systemAlarmIDs: [id], authorized: true)
        #expect(change.cancel == [id] && change.schedule?.hour == 6 && change.schedule?.minute == 45)
    }

    @Test("An alarm the system lost is scheduled again")
    func lost() {
        let change = MorningAlarmPlan.change(setting: .init(isEnabled: true, hour: 7, minute: 0),
            recorded: .init(id: id, hour: 7, minute: 0), systemAlarmIDs: [], authorized: true)
        #expect(change.schedule != nil)
    }

    @Test("Without permission nothing is scheduled and permission is asked for")
    func unauthorized() {
        let change = MorningAlarmPlan.change(setting: .init(isEnabled: true), recorded: nil, systemAlarmIDs: [], authorized: false)
        #expect(change.needsAuthorization && change.schedule == nil)
    }

    @Test("One morning entry per alarm per day")
    func entryPerDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let morning = Date(timeIntervalSince1970: 1_791_000_000)
        let a = MorningAlarmPlan.entryID(alarmID: id, at: morning, calendar: calendar)
        #expect(a == MorningAlarmPlan.entryID(alarmID: id, at: morning.addingTimeInterval(120), calendar: calendar))
        #expect(a != MorningAlarmPlan.entryID(alarmID: id, at: morning.addingTimeInterval(86_400), calendar: calendar))
        #expect(a != id)
    }

    @Test("Times are kept in range")
    func clamps() {
        let setting = MorningAlarmSetting(isEnabled: true, hour: 31, minute: -4)
        #expect(setting.hour == 23 && setting.minute == 0)
    }
}

@Suite("Shortcut templates")
struct ShortcutTemplateTests {
    @Test("Cards stay hidden until their link is a real iCloud shortcut")
    func hiddenUntilLinked() {
        #expect(ShortcutTemplate.all.count == 6)
        let templates = [ShortcutTemplate(id: "text", symbol: "message", link: ""),
                         ShortcutTemplate(id: "email", symbol: "envelope", link: "https://evil.example/shortcuts/x"),
                         ShortcutTemplate(id: "water", symbol: "drop", link: "https://www.icloud.com/shortcuts/abc123"),
                         ShortcutTemplate(id: "focus", symbol: "moon", link: "https://www.icloud.com/shortcuts/")]
        #expect(ShortcutTemplate.visible(templates).map(\.id) == ["water"])
    }
}
