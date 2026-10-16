import Foundation
import Testing
@testable import MorningCore

@Suite("Attributed execution recap — visits are not effects")
struct RoutineStepExecutionRecapTests {
    @Test func mixedReadUnpresentedResponseAndTimerRemainDistinctAfterRestore() throws {
        let mail = RoutineStep(title: "SYNTHETIC mail", automation: .gmailInbox)
        let slack = RoutineStep(title: "SYNTHETIC team")
        let timed = RoutineStep(title: "SYNTHETIC quiet finish", automation: .timedMoment)
        var session = RoutineSession(routine: .init(sourceLabel: "SYNTHETIC", steps: [mail, slack, timed], isApproved: true))
        try session.start()
        for _ in 0..<3 { try session.advance() }
        let records = [
            RoutineExecutionRecord(sessionID: session.id, stepID: mail.id, outcome: .completed),
            RoutineExecutionRecord(sessionID: session.id, stepID: slack.id, outcome: .unavailable, confirmedExternalEffect: true),
            RoutineExecutionRecord(sessionID: session.id, stepID: timed.id, outcome: .budgetFinished),
            RoutineExecutionRecord(sessionID: UUID(), stepID: slack.id, outcome: .completed),
            RoutineExecutionRecord(sessionID: session.id, stepID: UUID(), outcome: .completed)
        ]
        let rows = RoutineStepExecutionRecap.make(session: session, records: records)
        #expect(rows.map(\.title) == [mail.title, slack.title, timed.title])
        #expect(rows.map(\.operation) == [.verified, .responseReceivedPresentationUnavailable, .timedBudgetFinished])
        #expect(rows.allSatisfy { $0.progress == .reached })
        #expect(rows[1].summary(french: false) == "Service response received; presentation unavailable.")
        #expect(rows[1].summary(french: true) == "Réponse du service reçue ; restitution indisponible.")
        let restoredSession = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        let restoredRecords = try JSONDecoder().decode([RoutineExecutionRecord].self, from: JSONEncoder().encode(records))
        #expect(RoutineStepExecutionRecap.make(session: restoredSession, records: restoredRecords) == rows)
    }

    @Test func skipStoppedCurrentAndUnreachedFutureAreNotMergedIntoSuccess() throws {
        let steps = (0..<4).map { RoutineStep(title: "Moment \($0)") }
        var session = RoutineSession(routine: .init(sourceLabel: "SYNTHETIC", steps: steps, isApproved: true))
        try session.start(); try session.advance(); try session.advance(skipping: true); try session.stop()
        let records = [
            RoutineExecutionRecord(sessionID: session.id, stepID: steps[0].id, outcome: .completed),
            RoutineExecutionRecord(sessionID: session.id, stepID: steps[1].id, outcome: .skipped),
            RoutineExecutionRecord(sessionID: session.id, stepID: steps[2].id, outcome: .running),
            // A stray record must not claim that the pinned session visited a future step.
            RoutineExecutionRecord(sessionID: session.id, stepID: steps[3].id, outcome: .completed)
        ]
        let rows = RoutineStepExecutionRecap.make(session: session, records: records)
        #expect(rows.map(\.progress) == [.reached, .skipped, .reached, .notReached])
        #expect(rows.map(\.operation) == [.verified, nil, .interrupted, nil])
        #expect(rows[1].summary(french: false) == "Moment skipped.")
        #expect(rows[1].summary(french: true) == "Moment passé.")
        #expect(rows[3].summary(french: false) == "Moment not reached.")
        #expect(rows[3].summary(french: true) == "Moment non atteint.")
    }

    @Test func advancementAndAContentBudgetDoNotCertifyAnOperation() throws {
        let manual = RoutineStep(title: "Manual")
        let content = RoutineStep(title: "Content")
        var session = RoutineSession(routine: .init(sourceLabel: "SYNTHETIC", steps: [manual, content], isApproved: true))
        let before = RoutineStepExecutionRecap.make(session: session, records: [])
        #expect(before.allSatisfy { $0.progress == .notReached && $0.operation == nil })
        try session.start(); try session.advance(); try session.advance()
        #expect(RoutineStepExecutionRecap.make(session: session, records: []).allSatisfy { $0.operation == .notVerified })
        let rows = RoutineStepExecutionRecap.make(session: session, records: [
            .init(sessionID: session.id, stepID: manual.id, outcome: .skipped),
            .init(sessionID: session.id, stepID: content.id, outcome: .budgetFinished)
        ])
        #expect(rows[0].operation == .notVerified)
        #expect(rows[1].operation == .budgetFinished)
        #expect(rows[1].summary(french: false) == "Allocated time finished; no additional action verified.")
        #expect(rows[1].summary(french: true) == "Temps alloué terminé ; aucune action supplémentaire vérifiée.")
    }

    @Test func browserObservationsAndConfirmedLikesStayWithExactMomentAfterRestore() throws {
        let feed = RoutineStep(title: "Same browser title", webBehavior: .browseFeed)
        let stories = RoutineStep(title: "Same browser title", webBehavior: .watchStories)
        var session = RoutineSession(routine: .init(sourceLabel: "SYNTHETIC", steps: [feed, stories], isApproved: true))
        try session.start(); try session.advance(); try session.advance()
        let records = [
            RoutineExecutionRecord(sessionID: session.id, stepID: feed.id, outcome: .budgetFinished, observedContents: 4, confirmedLikes: 1),
            RoutineExecutionRecord(sessionID: session.id, stepID: stories.id, outcome: .interrupted, observedContents: 2, confirmedLikes: 0),
            RoutineExecutionRecord(sessionID: UUID(), stepID: feed.id, outcome: .completed, observedContents: 99, confirmedLikes: 99)
        ]
        let rows = RoutineStepExecutionRecap.make(session: session, records: records)
        #expect(rows.map(\.observedContents) == [4, 2])
        #expect(rows.map(\.confirmedLikes) == [1, 0])
        #expect(rows[0].summary(french: false).contains("Browser: 4 contents observed, 1 likes confirmed."))
        #expect(rows[1].summary(french: true).contains("Navigateur : 2 contenus observés, 0 likes confirmés."))
        let restoredSession = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        let restoredRecords = try JSONDecoder().decode([RoutineExecutionRecord].self, from: JSONEncoder().encode(records))
        #expect(RoutineStepExecutionRecap.make(session: restoredSession, records: restoredRecords) == rows)
        let unknown = RoutineStepExecutionRecap.make(session: session, records: []).first
        #expect(unknown?.observedContents == nil && unknown?.confirmedLikes == nil)
    }
}
