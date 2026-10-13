import Foundation
import Testing
@testable import MorningCore

@Suite("Adversarial saved budgets, feedback and journal keep matching")
struct RoutineBudgetAndFeedbackAdversarialTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    private func routine(_ steps: [RoutineStep], id: UUID = UUID()) -> RoutineVersion {
        RoutineVersion(id: id, createdAt: instant, sourceLabel: "Adversarial test fixture",
                       steps: steps, isApproved: true)
    }

    private func decoded(_ json: String) throws -> RoutineBudgetAndFeedback {
        try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: Data(json.utf8))
    }

    private func acceptanceJSON(versionID: UUID = UUID(), target: String = "10",
                                total: String = "20") -> String {
        #"{"routineVersionID":"\#(versionID)","targetMinutes":\#(target),"totalMinutes":\#(total)}"#
    }

    private func feedbackJSON(id: UUID = UUID(), sessionID: UUID = UUID(), versionID: UUID = UUID(),
                              useful: String = "null", enjoyable: String = "null",
                              recordedAt: String = "0") -> String {
        #"{"id":"\#(id)","sessionID":"\#(sessionID)","routineVersionID":"\#(versionID)","wasUseful":\#(useful),"wasEnjoyable":\#(enjoyable),"recordedAt":\#(recordedAt)}"#
    }

    private func assertStable(_ state: RoutineBudgetAndFeedback) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let first = try encoder.encode(state)
        let copy = try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: first)
        #expect(copy == state)
        #expect(try encoder.encode(copy) == first)
    }

    private func journal(_ entries: [RoutinePreference]) throws -> RoutinePreferenceJournal {
        try RoutinePreferenceJournal(entries: entries, revision: UUID())
    }

    @Test("Extreme targets, acceptances and feedback leave all routine and journal bytes intact")
    func budgetOperationsNeverEditStepsOrJournal() throws {
        let required = RoutineStep(title: "Required", detail: "Keep every word", durationMinutes: 9,
                                   isRequired: true, automation: .spokenNote)
        let kept = RoutineStep(title: "Kept", durationMinutes: 17)
        let excluded = RoutineStep(title: "Excluded", durationMinutes: 6)
        let timed = RoutineStep(title: "Timed", durationMinutes: 8)
        let version = routine([timed, kept, required, excluded])
        let preferences = try journal([
            RoutinePreference(target: kept, presence: .keep, durationMinutes: 2),
            RoutinePreference(target: excluded, presence: .exclude),
            RoutinePreference(target: timed, durationMinutes: 1)
        ])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let originalRoutine = try encoder.encode(version)
        let originalJournal = try encoder.encode(preferences)
        var session = RoutineSession(routine: version)
        try session.start(at: instant)
        try session.advance(skipping: true, at: instant)
        try session.stop(at: instant)
        let originalSession = session
        var state = RoutineBudgetAndFeedback()
        for target: Int? in [nil, Int.min, -1, 0, 5, 7, 10, 240, Int.max, nil] {
            state.setTarget(target)
            if let report = state.report(for: version, preferences: preferences) {
                #expect(report.totalMinutes == 40)
                #expect(report.longerPlanMinutes == 40)
                #expect(report.requiredStepIDs == [kept.id, required.id])
                #expect(report.requiredMinutes == 26)
                #expect(report.optionalMinutes == 14)
                let accepted = state.acceptLongerPlan(report)
                #expect(accepted == (report.fit != .withinTarget))
            }
            state.setFeedback(for: session, wasUseful: .no, wasEnjoyable: .somewhat, at: instant)
            state.setFeedback(for: session, wasUseful: nil, wasEnjoyable: nil, at: instant)
            #expect(try encoder.encode(version) == originalRoutine)
            #expect(try encoder.encode(preferences) == originalJournal)
            #expect(session == originalSession)
            #expect(RoutineSessionRecap(session: session, isPersisted: true).skippedSteps == [timed])
        }
    }

    @Test("Absent targets cannot be inferred from a routine, feedback or an attempted acceptance")
    func optionalTargetIsNeverInferred() throws {
        let version = routine([RoutineStep(title: "Long", durationMinutes: 120)])
        let session = RoutineSession(routine: version)
        var state = RoutineBudgetAndFeedback()
        state.setFeedback(for: session, wasUseful: .yes, wasEnjoyable: nil, at: instant)
        #expect(state.report(for: version) == nil)
        let accepted = state.acceptLongerPlan(RoutineTimeBudget(routine: version, targetMinutes: 5))
        #expect(!accepted)
        #expect(state.targetMinutes == nil)
        #expect(state.acceptedLongerPlan == nil)
        state.setTarget(5)
        #expect(state.report(for: nil) == nil)
        state.setTarget(nil)
        try assertStable(state)
    }

    @Test("Suggested targets safely round at both integer extremes and every offered boundary")
    func suggestedTargetsAreBoundedWithoutOverflow() {
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: Int.min) == 5)
        #expect(RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: Int.max) == 240)
        for planned in -5...245 {
            let suggested = RoutineBudgetAndFeedback.suggestedTargetMinutes(forPlannedMinutes: planned)
            #expect((5...240).contains(suggested))
            #expect(suggested.isMultiple(of: 5))
            if (5...240).contains(planned) {
                #expect(suggested >= planned)
                #expect(suggested - planned < 5)
            }
        }
    }

    @Test("Every revision invalidates acceptance, including metadata, equal totals and a restored plan")
    func everyRoutineRevisionRequiresFreshAcceptance() throws {
        let first = RoutineStep(title: "First", detail: "Original", durationMinutes: 12)
        let second = RoutineStep(title: "Second", durationMinutes: 8)
        let version = routine([first, second])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(5)
        let accepted = state.acceptLongerPlan(try #require(state.report(for: version)))
        #expect(accepted)
        var title = first; title.title = "Renamed"
        var detail = first; detail.detail = "Edited"
        var kind = first; kind.kind = .wellbeing
        var required = first; required.isRequired = true
        var automation = first; automation.automation = .spokenNote
        var shorter = first; shorter.durationMinutes = 11
        var longer = second; longer.durationMinutes = 9
        let revisions = [
            version.revised(steps: version.steps),
            version.revised(steps: version.steps, sourceLabel: "Changed label", at: instant),
            version.revised(steps: [title, second]), version.revised(steps: [detail, second]),
            version.revised(steps: [kind, second]), version.revised(steps: [required, second]),
            version.revised(steps: [automation, second]), version.revised(steps: [second, first]),
            version.revised(steps: [shorter, longer]), version.revised(steps: [first]),
            version.revised(steps: []), version.proposing(steps: version.steps)
        ]
        for revised in revisions {
            #expect(revised.id != version.id)
            #expect(!state.hasAccepted(try #require(state.report(for: revised))))
            let restored = revised.revised(steps: version.steps).approved()
            #expect(!state.hasAccepted(try #require(state.report(for: restored))))
        }
        #expect(state.hasAccepted(try #require(state.report(for: version.approved()))))
    }

    @Test("Acceptance covers exactly its version, target and total")
    func acceptanceDoesNotLeakAcrossAnyPartOfItsKey() throws {
        let step = RoutineStep(title: "Plan", durationMinutes: 20)
        let version = routine([step])
        let report = RoutineTimeBudget(routine: version, targetMinutes: 5)
        let acceptance = try #require(RoutineTimeBudgetAcceptance(budget: report))
        #expect(acceptance.covers(report))
        var changed = step; changed.durationMinutes = 21
        let reports = [
            RoutineTimeBudget(routine: routine([step]), targetMinutes: 5),
            RoutineTimeBudget(routine: routine([changed], id: version.id), targetMinutes: 5),
            RoutineTimeBudget(routine: version, targetMinutes: 6),
            RoutineTimeBudget(routine: version, targetMinutes: 20),
            RoutineTimeBudget(routine: version, targetMinutes: Int.max)
        ]
        for other in reports { #expect(!acceptance.covers(other)) }
    }

    @Test("Changing or removing a target permanently drops acceptance, including across persistence")
    func targetChangesAndChangesBackCannotResurrectAcceptance() throws {
        let version = routine([RoutineStep(title: "Plan", durationMinutes: 30)])
        for replacement: Int? in [nil, Int.min, 5, 11, 240, Int.max] {
            var state = RoutineBudgetAndFeedback()
            state.setTarget(10)
            let original = try #require(state.report(for: version))
            let accepted = state.acceptLongerPlan(original)
            #expect(accepted)
            state.setTarget(replacement)
            #expect(state.acceptedLongerPlan == nil)
            state = try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: JSONEncoder().encode(state))
            state.setTarget(10)
            #expect(!state.hasAccepted(original))
            #expect(state.acceptedLongerPlan == nil)
        }
    }

    @Test("Persisting a revision or missing routine drops acceptance even if the exact old version returns")
    func droppingAcceptancePreventsRestoringAnOldDecision() throws {
        let version = routine([RoutineStep(title: "Plan", durationMinutes: 20)])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        let report = try #require(state.report(for: version))
        let accepted = state.acceptLongerPlan(report)
        #expect(accepted)
        state.setFeedback(for: RoutineSession(routine: version), wasUseful: .yes,
                          wasEnjoyable: nil, at: instant)
        #expect(state.droppingAcceptance(unlessFor: version.approved()) == state)
        for replacement: RoutineVersion? in [nil, version.revised(steps: version.steps)] {
            let dropped = state.droppingAcceptance(unlessFor: replacement)
            #expect(dropped.acceptedLongerPlan == nil)
            #expect(dropped.targetMinutes == state.targetMinutes)
            #expect(dropped.feedback == state.feedback)
            let restored = dropped.droppingAcceptance(unlessFor: version)
            #expect(!restored.hasAccepted(report))
            try assertStable(restored)
        }
        #expect(state.hasAccepted(report))
    }

    @Test("Setting the same effective target does not erase the person's acceptance")
    func unchangedEffectiveTargetPreservesAcceptance() throws {
        let version = routine([RoutineStep(title: "Plan", durationMinutes: 300)])
        for (target, equivalent) in [(5, Int.min), (10, 10), (240, Int.max)] {
            var state = RoutineBudgetAndFeedback()
            state.setTarget(target)
            let report = try #require(state.report(for: version))
            let accepted = state.acceptLongerPlan(report)
            #expect(accepted)
            state.setTarget(equivalent)
            #expect(state.hasAccepted(report))
            try assertStable(state)
        }
    }

    @Test("Empty, exactly fitting and shorter plans can never be accepted")
    func fittingPlansAreNeverAccepted() throws {
        for target in [5, 10, 240] {
            for steps in [[], [RoutineStep(title: "Short", durationMinutes: 1)],
                          [RoutineStep(title: "Exact", durationMinutes: target, isRequired: true)]] {
                var state = RoutineBudgetAndFeedback()
                state.setTarget(target)
                let report = try #require(state.report(for: routine(steps)))
                #expect(report.fit == .withinTarget)
                #expect(report.choices.isEmpty)
                #expect(RoutineTimeBudgetAcceptance(budget: report) == nil)
                let accepted = state.acceptLongerPlan(report)
                #expect(!accepted)
                #expect(state.acceptedLongerPlan == nil)
            }
        }
    }

    @Test("Rejected acceptances leave an existing valid acceptance and feedback untouched")
    func rejectedAcceptanceIsAnExactNoOp() throws {
        let version = routine([RoutineStep(title: "Long", durationMinutes: 20)])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        let accepted = state.acceptLongerPlan(try #require(state.report(for: version)))
        #expect(accepted)
        state.setFeedback(for: RoutineSession(routine: version), wasUseful: .no, wasEnjoyable: nil, at: instant)
        let before = state
        let otherTarget = state.acceptLongerPlan(RoutineTimeBudget(routine: version, targetMinutes: 5))
        #expect(!otherTarget)
        #expect(state == before)
        let fitting = state.acceptLongerPlan(RoutineTimeBudget(routine: routine([]), targetMinutes: 10))
        #expect(!fitting)
        #expect(state == before)
    }

    @Test("Declining feedback stores nothing at any session lifecycle stage")
    func unansweredFeedbackNeverCreatesARecord() throws {
        var session = RoutineSession(routine: routine([RoutineStep(title: "One")]))
        var sessions = [session]
        try session.start(at: instant); sessions.append(session)
        try session.pause(at: instant); sessions.append(session)
        try session.resume(at: instant)
        try session.advance(at: instant); sessions.append(session)
        var stopped = RoutineSession(routine: session.routine)
        try stopped.stop(at: instant); sessions.append(stopped)
        var state = RoutineBudgetAndFeedback()
        for snapshot in sessions {
            #expect(RoutineSessionFeedback(session: snapshot) == nil)
            state.setFeedback(for: snapshot, wasUseful: nil, wasEnjoyable: nil, at: instant)
            #expect(state.feedback.isEmpty)
        }
    }

    @Test("Every optional answer combination stores exactly those answers or removes the old record")
    func feedbackAnswerMatrixNeverInventsAnswers() throws {
        let session = RoutineSession(routine: routine([RoutineStep(title: "One")]))
        let answers: [RoutineFeedbackAnswer?] = [nil, .yes, .somewhat, .no]
        for useful in answers {
            for enjoyable in answers {
                var state = RoutineBudgetAndFeedback()
                state.setFeedback(for: session, wasUseful: .yes, wasEnjoyable: .yes, at: instant)
                let oldID = try #require(state.feedback.first).id
                state.setFeedback(for: session, wasUseful: useful, wasEnjoyable: enjoyable, at: instant)
                if useful == nil && enjoyable == nil {
                    #expect(state.feedback.isEmpty)
                } else {
                    let record = try #require(state.feedback(forSessionID: session.id))
                    #expect(state.feedback.count == 1)
                    #expect(record.id == oldID)
                    #expect(record.wasUseful == useful)
                    #expect(record.wasEnjoyable == enjoyable)
                    #expect(record.routineVersionID == session.routine.id)
                }
                try assertStable(state)
            }
        }
    }

    @Test("Updating and clearing one session never merges separate runs of the same routine")
    func feedbackIsUniqueBySessionAndClearingIsLocal() throws {
        let version = routine([RoutineStep(title: "One")])
        let sessions = (0..<3).map { _ in RoutineSession(routine: version) }
        var state = RoutineBudgetAndFeedback()
        for session in sessions {
            state.setFeedback(for: session, wasUseful: .no, wasEnjoyable: nil, at: instant)
        }
        let initial = state.feedback
        for _ in 0..<20 {
            state.setFeedback(for: sessions[1], wasUseful: nil, wasEnjoyable: .yes,
                              at: instant.addingTimeInterval(1))
        }
        #expect(state.feedback.count == 3)
        #expect(state.feedback.map(\.sessionID) == sessions.map(\.id))
        #expect(state.feedback.map(\.id) == initial.map(\.id))
        state.setFeedback(for: sessions[1], wasUseful: nil, wasEnjoyable: nil, at: instant)
        #expect(state.feedback == [initial[0], initial[2]])
        #expect(state.feedback(forSessionID: sessions[1].id) == nil)
        state.setFeedback(for: sessions[1], wasUseful: nil, wasEnjoyable: nil, at: instant)
        #expect(state.feedback == [initial[0], initial[2]])
        try assertStable(state)
    }

    @Test("The session identity remains the uniqueness key even when a caller supplies a new snapshot")
    func feedbackReplacementUsesSessionIdentity() throws {
        let original = RoutineSession(routine: routine([RoutineStep(title: "One")]))
        let replacement = RoutineSession(id: original.id, routine: original.routine.revised(steps: []))
        var state = RoutineBudgetAndFeedback()
        state.setFeedback(for: original, wasUseful: .yes, wasEnjoyable: nil, at: instant)
        let id = try #require(state.feedback.first).id
        state.setFeedback(for: replacement, wasUseful: nil, wasEnjoyable: .no, at: instant)
        #expect(state.feedback.count == 1)
        #expect(state.feedback.first?.id == id)
        #expect(state.feedback.first?.routineVersionID == replacement.routine.id)
        #expect(state.feedback.first?.wasUseful == nil)
    }

    @Test("Every JSON value kind, including huge numeric scalars, can be decoded without inventing state")
    func arbitraryTopLevelJSONValuesNeverThrow() throws {
        let values = ["null", "true", "false", "0", "-1", "1.5", "1e400", "-1e400",
                      "99999999999999999999999999999999999999999999999999999999",
                      #""yes""#, #""""#, "[]", "[null,true,1e400,{},[]]", "{}",
                      #"{"unknown":{"targetMinutes":10,"wasUseful":"yes"}}"#]
        for json in values {
            let state = try decoded(json)
            #expect(state == RoutineBudgetAndFeedback(), "Unexpected state for \(json)")
            try assertStable(state)
        }
    }

    @Test("Wrong target types and out-of-range numbers are discarded while valid feedback survives")
    func invalidTargetsAreNeverClampedOrCoercedDuringDecoding() throws {
        let record = feedbackJSON(useful: #""yes""#)
        let invalid = ["null", "true", "false", #""10""#, #""soon""#, "[]", "{}",
                       "-1", "0", "4", "241", "10.5", String(Int.min), String(Int.max),
                       "1e400", "-1e400", "999999999999999999999999999999999999999999"]
        for value in invalid {
            let state = try decoded(#"{"targetMinutes":\#(value),"acceptedLongerPlan":\#(acceptanceJSON()),"feedback":[\#(record)]}"#)
            #expect(state.targetMinutes == nil, "Unexpected target for \(value)")
            #expect(state.acceptedLongerPlan == nil)
            #expect(state.feedback.count == 1)
            #expect(state.feedback.first?.wasUseful == .yes)
            #expect(state.feedback.first?.wasEnjoyable == nil)
            try assertStable(state)
        }
    }

    @Test("Saved targets retain their exact in-range integer instead of being rounded to editor increments")
    func validDecodedTargetsKeepTheirExactValue() throws {
        for target in [5, 6, 9, 10, 239, 240] {
            let state = try decoded(#"{"targetMinutes":\#(target)}"#)
            #expect(state.targetMinutes == target)
            #expect(state.acceptedLongerPlan == nil)
            #expect(state.feedback.isEmpty)
            try assertStable(state)
        }
    }

    @Test("Malformed, missing-target and mismatched-target acceptances cannot be restored")
    func malformedOrOrphanedAcceptancesAreDiscarded() throws {
        let version = UUID()
        let malformed = ["null", "true", "0", "1e400", #""accepted""#, "[]", "{}",
                         #"{"routineVersionID":"invalid","targetMinutes":10,"totalMinutes":20}"#,
                         #"{"routineVersionID":"\#(version)","targetMinutes":10}"#,
                         acceptanceJSON(target: #""10""#), acceptanceJSON(target: "null"),
                         acceptanceJSON(total: "true"), acceptanceJSON(total: "1e400"),
                         acceptanceJSON(total: "20.5"), acceptanceJSON(target: "15")]
        for acceptance in malformed {
            let state = try decoded(#"{"targetMinutes":10,"acceptedLongerPlan":\#(acceptance)}"#)
            #expect(state.targetMinutes == 10)
            #expect(state.acceptedLongerPlan == nil, "Unexpected acceptance for \(acceptance)")
            try assertStable(state)
        }
        for targetPart in ["", #""targetMinutes":null,"#, #""targetMinutes":true,"#,
                           #""targetMinutes":4,"#] {
            let state = try decoded("{\(targetPart)\"acceptedLongerPlan\":\(acceptanceJSON())}")
            #expect(state.targetMinutes == nil)
            #expect(state.acceptedLongerPlan == nil)
        }
    }

    @Test("Decoding cannot create an acceptance for a fitting or negative-length plan")
    func decodedAcceptanceCannotRepresentAFittingPlan() throws {
        for total in [Int.min, -1, 0, 1, 9, 10] {
            let state = try decoded(#"{"targetMinutes":10,"acceptedLongerPlan":\#(acceptanceJSON(total: String(total)))}"#)
            #expect(state.targetMinutes == 10)
            #expect(state.acceptedLongerPlan == nil, "A total of \(total) cannot be accepted against target 10")
        }
    }

    @Test("Unknown keys are ignored without suppressing legitimate saved data")
    func unknownKeysNeitherInventNorDestroyState() throws {
        let version = routine([RoutineStep(title: "Long", durationMinutes: 20)])
        let record = feedbackJSON(versionID: version.id, enjoyable: #""somewhat""#)
        let state = try decoded(#"{"targetMinutes":10,"acceptedLongerPlan":\#(acceptanceJSON(versionID: version.id)),"feedback":[\#(record)],"future":{"targetMinutes":99,"answer":"yes","huge":1e400},"wasUseful":"yes"}"#)
        #expect(state.targetMinutes == 10)
        #expect(state.hasAccepted(RoutineTimeBudget(routine: version, targetMinutes: 10)))
        #expect(state.feedback.count == 1)
        #expect(state.feedback.first?.wasUseful == nil)
        #expect(state.feedback.first?.wasEnjoyable == .somewhat)
        try assertStable(state)
    }

    @Test("All malformed feedback fields are isolated and cannot consume the following valid record")
    func malformedFeedbackRecordsDoNotPoisonTheirNeighbors() throws {
        let baseline = feedbackJSON(useful: #""yes""#)
        let baselineObject = try #require(JSONSerialization.jsonObject(with: Data(baseline.utf8)) as? [String: Any])
        let expected = try decoded(#"{"feedback":[\#(baseline)]}"#).feedback
        let invalidValues: [Any] = [NSNull(), true, [], [:], "not-a-valid-value"]
        for key in ["id", "sessionID", "routineVersionID", "recordedAt"] {
            for value in invalidValues {
                var object = baselineObject
                object[key] = value
                let broken = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
                let state = try decoded(#"{"targetMinutes":10,"feedback":[\#(broken),\#(baseline),\#(broken)]}"#)
                #expect(state.targetMinutes == 10)
                #expect(state.feedback.count == 1, "Invalid \(key) must not become a record")
                #expect(state.feedback == expected)
                #expect(state.feedback.first?.wasUseful == .yes)
                try assertStable(state)
            }
            var missing = baselineObject
            missing.removeValue(forKey: key)
            let broken = String(decoding: try JSONSerialization.data(withJSONObject: missing), as: UTF8.self)
            #expect(try decoded(#"{"feedback":[\#(broken)]}"#).feedback.isEmpty)
        }
    }

    @Test("Null, wrong-type and unknown feedback answers never become a person's answer")
    func invalidOrMissingAnswersNeverBecomeFeedback() throws {
        for value in ["null", "true", "false", "0", "1e400", "[]", "{}", #""YES""#,
                      #"" yes ""#, #""maybe""#, #""""#] {
            for (useful, enjoyable) in [(value, "null"), ("null", value)] {
                let record = feedbackJSON(useful: useful, enjoyable: enjoyable)
                let state = try decoded(#"{"feedback":[\#(record)]}"#)
                #expect(state.feedback.isEmpty, "Unexpected answer for \(value)")
            }
        }
        let missing = #"{"id":"\#(UUID())","sessionID":"\#(UUID())","routineVersionID":"\#(UUID())","recordedAt":0,"answer":"yes"}"#
        #expect(try decoded(#"{"feedback":[\#(missing)]}"#).feedback.isEmpty)
    }

    @Test("Damaged duplicate sessions do not hide a later valid record or merge contradictory answers")
    func duplicateSessionsKeepOnlyTheFirstValidWholeRecord() throws {
        let firstSession = UUID(), secondSession = UUID(), firstID = UUID()
        let unanswered = feedbackJSON(sessionID: firstSession)
        let first = feedbackJSON(id: firstID, sessionID: firstSession, useful: #""yes""#)
        let duplicate = feedbackJSON(sessionID: firstSession, enjoyable: #""no""#)
        let second = feedbackJSON(sessionID: secondSession, useful: #""somewhat""#)
        let state = try decoded(#"{"feedback":[null,1e400,[],{},\#(unanswered),\#(first),false,\#(duplicate),\#(second),\#(first)]}"#)
        #expect(state.feedback.map(\.sessionID) == [firstSession, secondSession])
        #expect(state.feedback.first?.id == firstID)
        #expect(state.feedback.first?.wasUseful == .yes)
        #expect(state.feedback.first?.wasEnjoyable == nil)
        #expect(state.feedback.last?.wasUseful == .somewhat)
        try assertStable(state)
    }

    @Test("Clearing a recovered duplicate session removes the sole retained record")
    func recoveredDuplicateCanBeClearedWithoutLeavingAGhost() throws {
        let session = RoutineSession(routine: routine([RoutineStep(title: "One")]))
        let record = feedbackJSON(sessionID: session.id, versionID: session.routine.id, useful: #""yes""#)
        var state = try decoded(#"{"feedback":[\#(record),\#(record),\#(record)]}"#)
        #expect(state.feedback.count == 1)
        state.setFeedback(for: session, wasUseful: nil, wasEnjoyable: nil, at: instant)
        #expect(state.feedback.isEmpty)
        #expect(state.feedback(forSessionID: session.id) == nil)
        try assertStable(state)
    }

    @Test("Wrong feedback containers and overflowing record timestamps never make decoding fail")
    func malformedFeedbackContainersAndHugeNumbersAreRecoverable() throws {
        for value in ["null", "true", "false", "1e400", #""yes""#, "{}"] {
            let state = try decoded(#"{"targetMinutes":10,"acceptedLongerPlan":\#(acceptanceJSON()),"feedback":\#(value)}"#)
            #expect(state.targetMinutes == 10)
            #expect(state.acceptedLongerPlan != nil)
            #expect(state.feedback.isEmpty)
            try assertStable(state)
        }
        for huge in ["1e400", "-1e400"] {
            let record = feedbackJSON(useful: #""yes""#, recordedAt: huge)
            let state = try decoded(#"{"feedback":[\#(record)]}"#)
            #expect(state.feedback.isEmpty)
            try assertStable(state)
        }
    }

    @Test("Full and partially answered saved states retain stable bytes over repeated round trips")
    func populatedStatesRoundTripWithoutDrift() throws {
        let version = routine([RoutineStep(title: "Plan", durationMinutes: 25)])
        var state = RoutineBudgetAndFeedback()
        state.setTarget(10)
        let accepted = state.acceptLongerPlan(try #require(state.report(for: version)))
        #expect(accepted)
        for answer in RoutineFeedbackAnswer.allCases {
            state.setFeedback(for: RoutineSession(routine: version), wasUseful: answer,
                              wasEnjoyable: nil, at: instant)
            state.setFeedback(for: RoutineSession(routine: version), wasUseful: nil,
                              wasEnjoyable: answer, at: instant.addingTimeInterval(0.125))
        }
        for _ in 0..<5 {
            try assertStable(state)
            state = try JSONDecoder().decode(RoutineBudgetAndFeedback.self, from: JSONEncoder().encode(state))
        }
        #expect(state.feedback.count == 6)
        #expect(state.hasAccepted(try #require(state.report(for: version))))
    }

    @Test("Budget keeps agree with successful reconciliation across exact, fresh and absent identities")
    func keptSetMatchesReconciliationAcrossChoiceAndIdentityMatrix() throws {
        let saved = [RoutineStep(title: "Alpha", durationMinutes: 7),
                     RoutineStep(title: "Beta", durationMinutes: 11)]
        let fresh = [RoutineStep(title: " alpha ", durationMinutes: 13),
                     RoutineStep(title: "BETA", durationMinutes: 17)]
        let choices: [(RoutinePreferencePresence?, Int?)] = [(nil, nil), (.keep, nil),
                                                            (.exclude, nil), (nil, 2), (.keep, 3)]
        for firstChoice in choices {
            for secondChoice in choices {
                var entries: [RoutinePreference] = []
                for (index, choice) in [firstChoice, secondChoice].enumerated() {
                    if choice.0 != nil || choice.1 != nil {
                        entries.append(try RoutinePreference(target: saved[index], presence: choice.0,
                                                             durationMinutes: choice.1))
                    }
                }
                let preferences = try journal(entries)
                for firstIdentity in 0...2 {
                    for secondIdentity in 0...2 {
                        // 0 = original identity, 1 = relearned identity, 2 = absent.
                        var steps: [RoutineStep] = []
                        var savedIDByInputID: [UUID: UUID] = [:]
                        for (index, identity) in [firstIdentity, secondIdentity].enumerated() where identity != 2 {
                            let step = identity == 0 ? saved[index] : fresh[index]
                            steps.append(step)
                            savedIDByInputID[step.id] = saved[index].id
                        }
                        let reconciled = try preferences.reconcile(steps: steps)
                        // Reconciliation restores the saved ID for fallback keeps. Translate its
                        // retained identities back to their known input slots, not by intersection.
                        let expected = steps.filter {
                            savedIDByInputID[$0.id].map { reconciled.retainedStepIDs.contains($0) } == true
                        }
                        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5,
                                                       preferences: preferences)
                        #expect(budget.requiredStepIDs == expected.map(\.id))
                        #expect(budget.requiredMinutes == expected.reduce(0) { $0 + $1.durationMinutes })
                        #expect(budget.totalMinutes == steps.reduce(0) { $0 + $1.durationMinutes })
                        #expect(preferences.entries == entries)
                    }
                }
            }
        }
    }

    @Test("Exact identity wins after title and category edits and never protects its namesake as well")
    func exactKeepIdentityWinsEvenAfterItsFieldsChange() throws {
        let saved = RoutineStep(title: "Tea", kind: .wellbeing, durationMinutes: 9)
        var edited = saved; edited.title = "Coffee"; edited.kind = .custom; edited.durationMinutes = 4
        let namesake = RoutineStep(title: "Tea", kind: .wellbeing, durationMinutes: 7)
        let preferences = try journal([RoutinePreference(target: saved, presence: .keep)])
        let steps = [namesake, edited]
        let reconciled = try preferences.reconcile(steps: steps)
        #expect(reconciled.retainedStepIDs == [saved.id])
        #expect(reconciled.steps == [namesake, saved])
        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: preferences)
        #expect(budget.requiredStepIDs == [edited.id])
        #expect(budget.requiredMinutes == 4)
    }

    @Test("Required and kept identities are counted once and remain in routine order")
    func requiredAndKeptUnionPreservesRoutineOrder() throws {
        let first = RoutineStep(title: "Same", durationMinutes: 7, isRequired: true)
        let second = RoutineStep(title: "Same", durationMinutes: 11)
        let third = RoutineStep(title: "Third", durationMinutes: 13, isRequired: true)
        let preferences = try journal([RoutinePreference(target: second, presence: .keep),
                                       RoutinePreference(target: first, presence: .keep)])
        let steps = [third, first, second]
        let reconciled = try preferences.reconcile(steps: steps)
        #expect(reconciled.retainedStepIDs == [first.id, second.id])
        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: preferences)
        #expect(budget.requiredStepIDs == steps.map(\.id))
        #expect(budget.requiredMinutes == 31)
        #expect(budget.optionalMinutes == 0)
    }

    @Test("Title fallback uses the journal's exact case and whitespace normalization")
    func titleMatchingAgreesWithJournalCaseAndWhitespaceKey() throws {
        let pairs = [("Morning Tea", " \tMORNING\n\rTEA  "), ("Morning Tea", "morning\u{00A0}tea"),
                     ("Café", "CAFE\u{301}"), ("Tea", "tEa")]
        for (original, candidate) in pairs {
            let saved = RoutineStep(title: original, kind: .wellbeing, durationMinutes: 9)
            let fresh = RoutineStep(title: candidate, kind: .wellbeing, durationMinutes: 4)
            let preferences = try journal([RoutinePreference(target: saved, presence: .keep)])
            #expect(try preferences.matchingPreference(for: fresh)?.targetID == saved.id)
            let reconciled = try preferences.reconcile(steps: [fresh])
            #expect(reconciled.retainedStepIDs == [saved.id])
            #expect(reconciled.steps == [saved])
            let budget = RoutineTimeBudget(routine: routine([fresh]), targetMinutes: 5, preferences: preferences)
            #expect(budget.requiredStepIDs == [fresh.id])
            #expect(budget.requiredMinutes == 4)
        }
    }

    @Test("Punctuation, diacritics, invisible non-whitespace, synonyms and categories are not fuzzy matches")
    func titleMatchingDoesNotInferAnythingFuzzierThanTheJournalKey() throws {
        let pairs = [("Tea-time", "Tea time"), ("Café", "Cafe"), ("Tea", "Tea time"),
                     ("Morning Tea", "Morning\u{2060}Tea"), ("Tea", "Coffee"),
                     ("Today's tea", "Today’s tea"), ("Tea", "Téa")]
        for (original, candidate) in pairs {
            let saved = RoutineStep(title: original, kind: .wellbeing)
            let fresh = RoutineStep(title: candidate, kind: .wellbeing)
            let preferences = try journal([RoutinePreference(target: saved, presence: .keep)])
            #expect(try preferences.matchingPreference(for: fresh) == nil, "Unexpected match: \(original) / \(candidate)")
            #expect(try preferences.reconcile(steps: [fresh]).steps == [fresh, saved])
            #expect(RoutineTimeBudget(routine: routine([fresh]), targetMinutes: 5,
                                      preferences: preferences).requiredStepIDs.isEmpty)
        }
        let saved = RoutineStep(title: "Tea", kind: .wellbeing)
        let differentKind = RoutineStep(title: "Tea", kind: .custom)
        let preferences = try journal([RoutinePreference(target: saved, presence: .keep)])
        #expect(try preferences.matchingPreference(for: differentKind) == nil)
        #expect(RoutineTimeBudget(routine: routine([differentKind]), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs.isEmpty)
    }

    @Test("Less familiar Unicode spellings use exactly the journal key, including its whitespace set")
    func unicodeTitleMatchingUsesTheJournalKeyAsItsOracle() throws {
        // CharacterSet whitespace and case folding are Foundation behavior. In particular,
        // do not assume a zero-width scalar is necessarily outside the journal's key.
        let pairs = [("Morning Tea", "Morning\u{200B}Tea"), ("Straße", "STRASSE"),
                     ("σ", "ς"), ("I", "ı"), ("İ", "i"), ("Tea", "Ｔｅａ"),
                     ("Tea", "Tea\u{200D}"), ("Café", "Cafe\u{301}")]
        for (original, candidate) in pairs {
            let saved = RoutineStep(title: original)
            let fresh = RoutineStep(title: candidate)
            let keep = try RoutinePreference(target: saved, presence: .keep)
            let candidateKey = try RoutinePreference(target: fresh, presence: .keep).normalizedTitle
            let matchesKey = keep.normalizedTitle == candidateKey
            let preferences = try journal([keep])
            let match = try preferences.matchingPreference(for: fresh)
            #expect((match != nil) == matchesKey)
            let reconciled = try preferences.reconcile(steps: [fresh])
            #expect(reconciled.steps == (matchesKey ? [saved] : [fresh, saved]))
            let budget = RoutineTimeBudget(routine: routine([fresh]), targetMinutes: 5,
                                           preferences: preferences)
            #expect(budget.requiredStepIDs == (matchesKey ? [fresh.id] : []))
        }
    }

    @Test("Exclusions and timing-only entries never add budget protection for exact or fresh steps")
    func exclusionsAndDurationOnlyChoicesNeverProtect() throws {
        for presence: RoutinePreferencePresence? in [nil, .exclude] {
            let saved = RoutineStep(title: "Tea", durationMinutes: 9)
            let fresh = RoutineStep(title: " tea ", durationMinutes: 13)
            let preferences = try journal([RoutinePreference(target: saved, presence: presence,
                                                              durationMinutes: 2)])
            for steps in [[saved], [fresh], []] {
                #expect(try preferences.reconcile(steps: steps).retainedStepIDs.isEmpty)
                let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: preferences)
                #expect(budget.requiredStepIDs.isEmpty)
                #expect(budget.requiredMinutes == 0)
                #expect(budget.totalMinutes == steps.reduce(0) { $0 + $1.durationMinutes })
            }
        }
    }

    @Test("A keep with two possible input steps protects neither")
    func ambiguousFallbackProtectsNothing() throws {
        let saved = RoutineStep(title: "Tea")
        let steps = [RoutineStep(title: "tea"), RoutineStep(title: " Tea ")]
        let preferences = try journal([RoutinePreference(target: saved, presence: .keep)])
        #expect(throws: RoutinePreferenceError.ambiguousMatch(saved.id)) {
            try preferences.reconcile(steps: steps)
        }
        #expect(RoutineTimeBudget(routine: routine(steps), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs.isEmpty)
    }

    @Test("Two fallback journal keeps that collide on one step protect nothing")
    func conflictingFallbackKeepsProtectNothing() throws {
        let first = RoutineStep(title: "Tea"), second = RoutineStep(title: " tea ")
        let candidate = RoutineStep(title: "TEA")
        let preferences = try journal([RoutinePreference(target: first, presence: .keep),
                                       RoutinePreference(target: second, presence: .keep)])
        #expect(throws: RoutinePreferenceError.conflictingMatch(candidate.id)) {
            try preferences.reconcile(steps: [candidate])
        }
        #expect(RoutineTimeBudget(routine: routine([candidate]), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs.isEmpty)
    }

    @Test("An exact keep cannot hide a conflicting fallback keep, exclusion or timing choice")
    func exactKeepCannotSurviveConflictingMatch() throws {
        let exact = RoutineStep(title: "Tea", durationMinutes: 9)
        let missing = RoutineStep(title: " tea ")
        let alternatives = [try RoutinePreference(target: missing, presence: .keep),
                            try RoutinePreference(target: missing, presence: .exclude),
                            try RoutinePreference(target: missing, durationMinutes: 3)]
        for alternative in alternatives {
            let keep = try RoutinePreference(target: exact, presence: .keep)
            for entries in [[keep, alternative], [alternative, keep]] {
                let preferences = try journal(entries)
                #expect(throws: RoutinePreferenceError.conflictingMatch(exact.id)) {
                    try preferences.reconcile(steps: [exact])
                }
                #expect(RoutineTimeBudget(routine: routine([exact]), targetMinutes: 5,
                                          preferences: preferences).requiredStepIDs.isEmpty)
            }
        }
    }

    @Test("An exact timing choice cannot resolve two candidates for a missing keep")
    func exactTimingChoiceDoesNotResolveAmbiguousFallback() throws {
        let saved = RoutineStep(title: "Tea")
        let first = RoutineStep(title: "Tea", durationMinutes: 7)
        let second = RoutineStep(title: " tea ", durationMinutes: 11)
        let preferences = try journal([RoutinePreference(target: saved, presence: .keep),
                                       RoutinePreference(target: first, durationMinutes: 3)])
        #expect(throws: RoutinePreferenceError.ambiguousMatch(saved.id)) {
            try preferences.reconcile(steps: [first, second])
        }
        #expect(RoutineTimeBudget(routine: routine([first, second]), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs.isEmpty)
    }

    @Test("A renamed exact exclusion or timing choice cannot conceal an ambiguous keep candidate")
    func renamedExactChoiceCannotHideAmbiguousKeepCandidate() throws {
        let savedKeep = RoutineStep(title: "Tea")
        let savedOther = RoutineStep(title: "Coffee", durationMinutes: 7)
        var renamed = savedOther; renamed.title = "Tea"
        let fresh = RoutineStep(title: " tea ", durationMinutes: 11)
        let alternatives = [try RoutinePreference(target: savedOther, durationMinutes: 3),
                            try RoutinePreference(target: savedOther, presence: .exclude)]
        for alternative in alternatives {
            let preferences = try journal([RoutinePreference(target: savedKeep, presence: .keep), alternative])
            #expect(throws: RoutinePreferenceError.ambiguousMatch(savedKeep.id)) {
                try preferences.reconcile(steps: [renamed, fresh])
            }
            #expect(RoutineTimeBudget(routine: routine([renamed, fresh]), targetMinutes: 5,
                                      preferences: preferences).requiredStepIDs.isEmpty)
        }
    }

    @Test("A keep by identity stays protected beside an exclusion of a namesake; the exclusion protects nothing")
    func keepByIdentityStaysProtectedBesideAnAmbiguousExclusion() throws {
        let kept = RoutineStep(title: "Tea", durationMinutes: 9)
        let excluded = RoutineStep(title: "Tea", durationMinutes: 7)
        let preferences = try journal([RoutinePreference(target: kept, presence: .keep),
                                       RoutinePreference(target: excluded, presence: .exclude)])
        #expect(throws: RoutinePreferenceError.ambiguousMatch(excluded.id)) {
            try preferences.reconcile(steps: [kept, excluded])
        }
        // The journal refuses to reconcile a suggestion here. The budget reads the current
        // routine choice by choice: the step kept by its identity is still kept.
        #expect(RoutineTimeBudget(routine: routine([kept, excluded]), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs == [kept.id])
    }

    @Test("An ambiguous keep protects none of its namesakes and does not hide an unrelated keep by identity")
    func ambiguousKeepProtectsNoNamesakeAndLeavesOtherKeepsAlone() throws {
        let kept = RoutineStep(title: "Coffee", durationMinutes: 9)
        let required = RoutineStep(title: "Required", durationMinutes: 3, isRequired: true)
        let absent = RoutineStep(title: "Tea")
        let steps = [required, kept, RoutineStep(title: "Tea"), RoutineStep(title: "tea")]
        let preferences = try journal([RoutinePreference(target: kept, presence: .keep),
                                       RoutinePreference(target: absent, presence: .keep)])
        #expect(throws: RoutinePreferenceError.ambiguousMatch(absent.id)) {
            try preferences.reconcile(steps: steps)
        }
        let budget = RoutineTimeBudget(routine: routine(steps), targetMinutes: 5, preferences: preferences)
        #expect(budget.requiredStepIDs == [required.id, kept.id])
    }

    @Test("A step claimed by two choices is not protected; an unrelated keep by identity still is")
    func conflictingChoicesProtectOnlyTheUnrelatedKeep() throws {
        let kept = RoutineStep(title: "Coffee", durationMinutes: 9)
        let firstSaved = RoutineStep(title: "Tea")
        let secondSaved = RoutineStep(title: "Tea")
        let fresh = RoutineStep(title: "Tea")
        let preferences = try journal([RoutinePreference(target: kept, presence: .keep),
                                       RoutinePreference(target: firstSaved, presence: .keep),
                                       RoutinePreference(target: secondSaved, presence: .exclude)])
        #expect(throws: RoutinePreferenceError.conflictingMatch(fresh.id)) {
            try preferences.reconcile(steps: [kept, fresh])
        }
        #expect(RoutineTimeBudget(routine: routine([kept, fresh]), targetMinutes: 5,
                                  preferences: preferences).requiredStepIDs == [kept.id])
    }

    @Test("A historical title on an exact keep cannot shadow another uniquely reconciled keep")
    func renamedExactKeepDoesNotShadowUniqueFallback() throws {
        let original = RoutineStep(title: "Tea", durationMinutes: 9)
        let otherSaved = RoutineStep(title: "Tea", durationMinutes: 7)
        var renamed = original; renamed.title = "Coffee"
        let fresh = RoutineStep(title: "Tea", durationMinutes: 11)
        let preferences = try journal([RoutinePreference(target: original, presence: .keep),
                                       RoutinePreference(target: otherSaved, presence: .keep)])
        let reconciled = try preferences.reconcile(steps: [renamed, fresh])
        #expect(reconciled.steps == [original, otherSaved])
        #expect(reconciled.retainedStepIDs == [original.id, otherSaved.id])
        let budget = RoutineTimeBudget(routine: routine([renamed, fresh]), targetMinutes: 5,
                                       preferences: preferences)
        #expect(budget.requiredStepIDs == [renamed.id, fresh.id])
    }

    @Test("A historical category on an exact timing choice cannot shadow a uniquely reconciled keep")
    func recategorizedTimingChoiceDoesNotShadowUniqueFallback() throws {
        let original = RoutineStep(title: "Tea", kind: .wellbeing, durationMinutes: 9)
        let otherSaved = RoutineStep(title: "Tea", kind: .wellbeing, durationMinutes: 7)
        var changed = original; changed.kind = .custom
        let fresh = RoutineStep(title: "Tea", kind: .wellbeing, durationMinutes: 11)
        let preferences = try journal([RoutinePreference(target: original, durationMinutes: 3),
                                       RoutinePreference(target: otherSaved, presence: .keep)])
        let reconciled = try preferences.reconcile(steps: [changed, fresh])
        #expect(reconciled.retainedStepIDs == [otherSaved.id])
        #expect(reconciled.steps.last == otherSaved)
        let budget = RoutineTimeBudget(routine: routine([changed, fresh]), targetMinutes: 5,
                                       preferences: preferences)
        #expect(budget.requiredStepIDs == [fresh.id])
    }
}
