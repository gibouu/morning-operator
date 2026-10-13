import Foundation
import Testing
@testable import MorningCore

@Suite("Routine boundaries: large plans, decoded sessions and extreme durations")
struct RoutineBoundaryTests {
    @Test("Large plans and extreme targets retain every step and use exact journal identity")
    func largeBudgetDoesNotTrimOrMistakeEquivalentTitlesForIdentity() throws {
        let ordinary = RoutineStep(title: "Cafe\u{301}", durationMinutes: 7)
        let kept = RoutineStep(title: "Reading", durationMinutes: 11)
        let required = RoutineStep(title: "Chess", durationMinutes: 13, isRequired: true)
        let excluded = RoutineStep(title: "Messages", durationMinutes: 17)
        let fillers = (0..<4_096).map { RoutineStep(title: "Moment \($0)", durationMinutes: 1) }
        let routine = RoutineVersion(sourceLabel: "Synthetic boundary routine", steps:
            [ordinary, kept, required, excluded] + fillers, isApproved: true)
        var preferences = RoutinePreferenceJournal()
        // String equality considers these titles equal. The budget contract requires IDs.
        let lookAlike = RoutineStep(title: "Caf\u{e9}", durationMinutes: 7)
        #expect(lookAlike.title == ordinary.title)
        #expect(lookAlike.id != ordinary.id)
        try preferences.upsert(RoutinePreference(target: lookAlike, presence: .keep))
        try preferences.upsert(RoutinePreference(target: kept, presence: .keep))
        try preferences.upsert(RoutinePreference(target: ordinary, durationMinutes: 3))
        try preferences.upsert(RoutinePreference(target: excluded, presence: .exclude))
        let before = routine
        let preferencesBefore = preferences

        let tight = RoutineTimeBudget(routine: routine, targetMinutes: .min, preferences: preferences)
        #expect(tight.targetMinutes == 1)
        #expect(tight.totalMinutes == 4_144)
        #expect(tight.longerPlanMinutes == 4_144)
        #expect(tight.requiredMinutes == 24)
        #expect(tight.requiredStepIDs == [kept.id, required.id])
        #expect(tight.optionalMinutes == 4_120)
        #expect(tight.fit == .requiredAloneOverTarget)
        #expect(tight.minutesOverTarget == 4_143)
        #expect(tight.requiredMinutesOverTarget == 23)

        let loose = RoutineTimeBudget(routine: routine, targetMinutes: .max, preferences: preferences)
        #expect(loose.fit == .withinTarget)
        #expect(loose.minutesOverTarget == 0)
        #expect(loose.requiredMinutesOverTarget == 0)
        #expect(loose.longerPlanMinutes == tight.longerPlanMinutes)
        #expect(routine == before)
        #expect(preferences == preferencesBefore)
    }

    @Test("After relaunch and command replay, a failed replacement save remains not saved")
    func relaunchedReplayAndFailedSaveKeepUnsavedRecapHonest() throws {
        let steps = [
            RoutineStep(title: "First", durationMinutes: 3),
            RoutineStep(title: "Second", durationMinutes: 5),
            RoutineStep(title: "Third", durationMinutes: 7)
        ]
        var session = RoutineSession(routine: RoutineVersion(
            sourceLabel: "Synthetic boundary routine", steps: steps, isApproved: true))
        let commandID = UUID()
        try session.start(at: Date(timeIntervalSince1970: 100))
        try session.advance(commandID: commandID, at: Date(timeIntervalSince1970: 99))
        try session.pause(at: Date(timeIntervalSince1970: 98))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("session.json")
        try AtomicJSONFile<RoutineSession>(url: url).save(session)
        var relaunched = try AtomicJSONFile<RoutineSession>(url: url).load()
        try relaunched.advance(skipping: true, commandID: commandID, at: Date(timeIntervalSince1970: 97))
        #expect(relaunched.status == .paused)
        #expect(relaunched.currentStepIndex == 1)
        #expect(relaunched.events.count == session.events.count)

        // A non-finite timestamp cannot be encoded. A prior successful save must not
        // label this newly stopped, unsaved run as saved.
        try relaunched.stop(at: Date(timeIntervalSince1970: .nan))
        var saved = false
        do {
            try AtomicJSONFile<RoutineSession>(url: url).save(relaunched)
            saved = true
        } catch is EncodingError {
            // Expected failure from the standard encoder's non-finite-number policy.
        }
        #expect(!saved)
        let recap = RoutineSessionRecap(session: relaunched, isPersisted: saved)
        #expect(recap.saveState == .notSaved)
        #expect(recap.ending == .stoppedWhilePaused)
        #expect(recap.completedSteps == [steps[0]])
        #expect(recap.unfinishedSteps == [steps[1], steps[2]])
        #expect(recap.stoppedAtStepID == steps[1].id)
        #expect(recap.plannedMinutesCompleted == 3)
        let stillSaved = try AtomicJSONFile<RoutineSession>(url: url).load()
        #expect(stillSaved == session)
        #expect(RoutineSessionRecap(session: stillSaved, isPersisted: true).ending == .inProgress)
    }

    @Test("A saved stop event naming a step outside the pinned routine is refused when read")
    func decodedForeignStopIDIsRejected() throws {
        let step = RoutineStep(title: "Only pinned step", durationMinutes: 3)
        var session = RoutineSession(routine: RoutineVersion(
            sourceLabel: "Synthetic boundary routine", steps: [step], isApproved: true))
        try session.start()
        try session.stop()
        let foreignID = try #require(UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"))
        let malformed = try rewritingEvents(of: session) { events in
            let stopIndex = try #require(events.firstIndex { $0["kind"] as? String == "stopped" })
            events[stopIndex]["stepID"] = foreignID.uuidString
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineSession.self, from: malformed) }
        // The session as the app wrote it still reads back, and its recap names the pinned step.
        let intact = try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session))
        #expect(intact == session)
        #expect(RoutineSessionRecap(session: intact, isPersisted: true).stoppedAtStepID == step.id)
    }

    @Test("Every session the commands can reach is read back unchanged, alone, in a file and in history")
    func everyReachableSessionRoundTripsThroughFilesAndHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let step = RoutineStep(title: "Synthetic step", durationMinutes: 1_440)
        let regular = RoutineVersion(sourceLabel: "Synthetic", steps: [step, RoutineStep(title: "Second")], isApproved: true)
        // Stopping before any start is allowed for a draft, an empty plan and repeated identities.
        let routines = [regular, regular.revised(steps: regular.steps),
            RoutineVersion(sourceLabel: "Empty", steps: [], isApproved: true),
            RoutineVersion(sourceLabel: "Repeated IDs", steps: [step, step], isApproved: true)]
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let commandID = UUID()
        var reached: [RoutineSession] = []
        // Every sequence of up to six successful commands, including a replayed command ID.
        func explore(_ session: RoutineSession, depth: Int) {
            reached.append(session)
            guard depth > 0 else { return }
            for command in 0..<7 {
                var next = session
                do {
                    switch command {
                    case 0: try next.start(at: now)
                    case 1: try next.pause(at: now.addingTimeInterval(-1))
                    case 2: try next.resume(at: now)
                    case 3: try next.advance(commandID: commandID, at: now)
                    case 4: try next.advance(skipping: true, commandID: commandID, at: now)
                    case 5: try next.advance(skipping: true, at: now)
                    default: try next.stop(at: now)
                    }
                    if next != session { explore(next, depth: depth - 1) }
                } catch { /* The command is not available from this position. */ }
            }
        }
        for routine in routines { explore(RoutineSession(routine: routine), depth: 6) }
        // A step command may carry the ID of an event that is not a step.
        var collision = RoutineSession(routine: regular)
        try collision.start(at: now)
        try collision.advance(commandID: try #require(collision.events.first?.id), at: now)
        try collision.pause(at: now)
        try collision.resume(at: now)
        try collision.advance(commandID: collision.events[2].id, at: now)
        reached.append(collision)
        #expect(reached.contains { $0.status == .completed })
        #expect(reached.contains { $0.status == .paused })
        for (index, value) in reached.enumerated() {
            #expect(try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(value)) == value)
            let url = directory.appendingPathComponent("session.json")
            try AtomicJSONFile<RoutineSession>(url: url).save(value)
            #expect(try AtomicJSONFile<RoutineSession>(url: url).load() == value, "state \(index)")
            if value.status == .completed || value.status == .stopped {
                let record = try MorningRunRecord(session: value, timeZoneIdentifier: "UTC", recordedAt: now, isSynthetic: true)
                #expect(try JSONDecoder().decode(MorningRunRecord.self, from: JSONEncoder().encode(record)) == record)
                let history = MorningHistory(runs: [record])
                let historyURL = directory.appendingPathComponent("history.json")
                try AtomicJSONFile<MorningHistory>(url: historyURL).save(history)
                #expect(try AtomicJSONFile<MorningHistory>(url: historyURL).load() == history)
            }
        }
    }

    @Test("A saved session whose events its commands could not have recorded is refused", arguments: [
        "statusMismatch", "positionMismatch", "negativePosition", "wrongOrder", "eventAfterEnd", "startTwice",
        "startedWithStep", "duplicateCompletion", "completionWithoutSteps", "missingCompletion",
        "completionTimeMismatch", "replayedCommandID", "repeatedStepIDs", "unapprovedStart", "blankTitleStart",
        "emptyStarted", "pausedStepMismatch"
    ])
    func inconsistentDecodedSessionIsRejected(_ damage: String) throws {
        let steps = [RoutineStep(title: "First", durationMinutes: 3), RoutineStep(title: "Second", durationMinutes: 5)]
        var session = RoutineSession(routine: RoutineVersion(
            sourceLabel: "Synthetic boundary routine", steps: steps, isApproved: true))
        try session.start()
        try session.advance()
        // Events: started, first step, then either a pause or the second step and the completion.
        if damage == "pausedStepMismatch" { try session.pause() } else { try session.advance() }
        #expect(try JSONDecoder().decode(RoutineSession.self, from: JSONEncoder().encode(session)) == session)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        var events = try #require(json["events"] as? [[String: Any]])
        var routine = try #require(json["routine"] as? [String: Any])
        var savedSteps = try #require(routine["steps"] as? [[String: Any]])
        switch damage {
        case "statusMismatch": json["status"] = "paused"
        case "positionMismatch": json["currentStepIndex"] = Int.max
        case "negativePosition": json["currentStepIndex"] = -1
        case "wrongOrder": events.swapAt(1, 2)
        case "eventAfterEnd": events.append(events[0])
        case "startTwice": events.insert(events[0], at: 1)
        case "startedWithStep": events[0]["stepID"] = steps[0].id.uuidString
        // The same step completed twice would count as more steps done than the routine holds.
        case "duplicateCompletion": events.insert(events[1], at: 2)
        case "completionWithoutSteps": events.removeAll { ($0["kind"] as? String) == "stepCompleted" }
        case "missingCompletion": events.removeLast(); json["status"] = "running"
        case "completionTimeMismatch": events[3]["occurredAt"] = -1
        case "replayedCommandID": events[2]["id"] = events[1]["id"]
        case "repeatedStepIDs":
            savedSteps[1]["id"] = savedSteps[0]["id"]
            events[2]["stepID"] = events[1]["stepID"]
        case "unapprovedStart": routine["isApproved"] = false
        case "blankTitleStart": savedSteps[0]["title"] = " \n "
        case "emptyStarted": savedSteps = []
        case "pausedStepMismatch": events[2]["stepID"] = steps[0].id.uuidString
        default: Issue.record("Unknown damage \(damage)")
        }
        routine["steps"] = savedSteps
        json["events"] = events; json["routine"] = routine
        let damaged = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineSession.self, from: damaged) }
    }

    /// Before planned minutes were bounded, the first sum below stopped the process
    /// with an arithmetic overflow instead of returning.
    @Test("Planned minutes are bounded where they are set, so no total can overflow")
    func extremeDurationsNeverOverflowATotal() throws {
        let day = RoutineStep.durationMinutesRange.upperBound
        #expect(day == 1_440)
        var edited = RoutineStep(title: "Edited", durationMinutes: 5, isRequired: true)
        edited.durationMinutes = .max
        #expect(edited.durationMinutes == day)
        edited.durationMinutes = .min
        #expect(edited.durationMinutes == 1)
        edited.durationMinutes = .max
        let steps = [RoutineStep(title: "Longest", durationMinutes: .max, isRequired: true), edited,
                     RoutineStep(title: "Shortest", durationMinutes: .min)]
        #expect(steps.map(\.durationMinutes) == [day, day, 1])
        let routine = RoutineVersion(sourceLabel: "Synthetic boundary routine", steps: steps, isApproved: true)
            .proposing(steps: steps, preserving: [RoutineStepPreference(stepID: steps[2].id, durationMinutes: .max)])
        #expect(routine.totalDurationMinutes == 3 * day)
        for target in [Int.min, 1, Int.max] {
            let budget = RoutineTimeBudget(routine: routine, targetMinutes: target)
            #expect(budget.totalMinutes == 3 * day && budget.requiredMinutes == 2 * day)
            #expect(budget.optionalMinutes == day)
            #expect(budget.minutesOverTarget == max(0, 3 * day - max(1, target)))
            #expect(budget.requiredMinutesOverTarget == max(0, 2 * day - max(1, target)))
        }
        var session = RoutineSession(routine: routine.approved())
        try session.start()
        try session.advance(); try session.advance(); try session.advance()
        #expect(RoutineSessionRecap(session: session, isPersisted: false).plannedMinutesCompleted == 3 * day)
        #expect(try MorningRunRecord(session: session, timeZoneIdentifier: "UTC").plannedDurationMinutes == 3 * day)
    }

    @Test("A saved step outside one minute to one day is refused when read", arguments: [
        Int.max, Int.min, 1_441, 0, -1
    ])
    func decodedDurationOutsideTheRangeIsRejected(_ minutes: Int) throws {
        let step = RoutineStep(title: "Saved", durationMinutes: 5)
        func saved(_ value: Int) throws -> Data {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(step)) as? [String: Any])
            json["durationMinutes"] = value
            return try JSONSerialization.data(withJSONObject: json)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineStep.self, from: saved(minutes)) }
        for accepted in [1, 120, 1_440] {
            #expect(try JSONDecoder().decode(RoutineStep.self, from: saved(accepted)).durationMinutes == accepted)
        }
        // The same refusal reaches every saved value that carries a step.
        let routine = RoutineVersion(sourceLabel: "Synthetic boundary routine", steps: [step, step], isApproved: true)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(routine)) as? [String: Any])
        var steps = try #require(json["steps"] as? [[String: Any]])
        steps[0]["durationMinutes"] = minutes; steps[1]["durationMinutes"] = 1
        json["steps"] = steps
        let damaged = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(RoutineVersion.self, from: damaged) }
    }

    /// One day is the longest plan any earlier build could save: its editor stops at 120
    /// minutes, a suggestion at 60 and a kept choice at 1,440. Such files must still open.
    @Test("The longest plan an earlier build could save still opens in a routine, a session and a history")
    func longestSavedDurationStillOpensInEveryFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let routine = RoutineVersion(sourceLabel: "Synthetic saved file",
            steps: [RoutineStep(title: "Synthetic saved plan", durationMinutes: 7)], isApproved: true)
        var session = RoutineSession(routine: routine)
        try session.start(); try session.advance()
        let history = MorningHistory(runs: [try MorningRunRecord(session: session, timeZoneIdentifier: "UTC", isSynthetic: true)])
        func rewritingMinutes(_ data: Data, to minutes: Int) throws -> Data {
            func rewrite(_ value: Any) -> Any {
                if var fields = value as? [String: Any] {
                    for (key, child) in fields { fields[key] = key == "durationMinutes" ? minutes : rewrite(child) }
                    return fields
                }
                if let values = value as? [Any] { return values.map(rewrite) }
                return value
            }
            return try JSONSerialization.data(withJSONObject: rewrite(JSONSerialization.jsonObject(with: data)))
        }
        func check<T: Codable & Sendable>(_ value: T, name: String, minutes: (T) -> [Int]) throws {
            let url = directory.appendingPathComponent(name)
            try AtomicJSONFile<T>(url: url).save(value)
            let saved = try Data(contentsOf: url)
            try rewritingMinutes(saved, to: 1_440).write(to: url)
            #expect(try minutes(AtomicJSONFile<T>(url: url).load()) == [1_440], "\(name)")
            try rewritingMinutes(saved, to: 1_441).write(to: url)
            #expect(throws: DecodingError.self, "\(name)") { _ = try AtomicJSONFile<T>(url: url).load() }
        }
        try check(routine, name: "routine.json") { $0.steps.map(\.durationMinutes) }
        try check(session, name: "session.json") { $0.routine.steps.map(\.durationMinutes) }
        try check(history, name: "history.json") { $0.runs.map(\.plannedDurationMinutes) }
    }

    @Test("Extreme minutes stay bounded through choices, suggestions, budgets, recaps and portable documents")
    func durationPathsRemainBounded() throws {
        for input in [Int.min, 0, 1_441, Int.max] {
            let expected = min(max(1, input), 1_440)
            var step = RoutineStep(title: "Synthetic boundary", durationMinutes: input, isRequired: true)
            #expect(step.durationMinutes == expected)
            step.durationMinutes = input
            #expect(step.durationMinutes == expected)
            #expect(try JSONDecoder().decode(RoutineStep.self, from: JSONEncoder().encode(step)) == step)
            var preference = RoutineStepPreference(stepID: step.id, durationMinutes: input)
            #expect(preference.durationMinutes == max(1, input))
            // A correction is not bounded when read; the step it is applied to is.
            preference.durationMinutes = input
            let decodedPreference = try JSONDecoder().decode(RoutineStepPreference.self, from: JSONEncoder().encode(preference))
            #expect(decodedPreference.durationMinutes == input)
            let base = RoutineVersion(sourceLabel: "Synthetic boundary", steps: [step], isApproved: true)
            let proposed = base.proposing(steps: [step], preserving: [decodedPreference])
            let inferred = RoutineVersion.inferredDraft(from: base, preserving: base, preferences: [decodedPreference])
            let revised = base.revised(steps: [step])
            for routine in [base, proposed, inferred, revised] {
                #expect(routine.totalDurationMinutes == expected)
                for target in [Int.min, Int.max] {
                    let budget = RoutineTimeBudget(routine: routine, targetMinutes: target)
                    #expect(budget.totalMinutes == expected)
                    #expect(budget.requiredMinutes == expected)
                    #expect(budget.optionalMinutes == 0)
                    #expect(budget.minutesOverTarget == (target == Int.min ? expected - 1 : 0))
                    #expect(budget.requiredMinutesOverTarget == budget.minutesOverTarget)
                }
                var session = RoutineSession(routine: routine.approved())
                try session.start(); try session.advance()
                #expect(RoutineSessionRecap(session: session, isPersisted: false).plannedMinutesCompleted == expected)
            }
            let kept = try RoutinePreference(target: step, presence: .keep)
            let keptDecoded = try JSONDecoder().decode(RoutinePreference.self, from: JSONEncoder().encode(kept))
            var journal = RoutinePreferenceJournal()
            try journal.upsert(keptDecoded)
            #expect(try journal.reconcile(steps: []).steps == [step])
            #expect(throws: RoutinePreferenceError.self) { try RoutinePreference(target: step, durationMinutes: input) }
            if expected > 120 {
                #expect(throws: PortableRoutineDocumentError.self) { try PortableRoutineDocument(routine: base) }
            } else {
                let document = try PortableRoutineDocument(routine: base)
                let decoded = try PortableRoutineDocument.decode(document.encoded())
                #expect(try decoded.importedDraft(replacing: base).totalDurationMinutes == expected)
            }
        }
    }

    /// Before the count was made to stop, each of these additions ended the process.
    @Test("A saved version number at the largest integer can still be revised")
    func largestSavedVersionNumberDoesNotOverflow() throws {
        let saved = RoutineVersion(number: Int.max, sourceLabel: "Synthetic", steps: [RoutineStep(title: "One")])
        let decoded = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(saved))
        #expect(decoded.number == Int.max && decoded.nextNumber == Int.max)
        #expect(decoded.revised(steps: decoded.steps).number == Int.max)
        #expect(decoded.proposing(steps: decoded.steps).number == Int.max)
        #expect(RoutineVersion.inferredDraft(from: decoded, preserving: decoded).number == Int.max)
        let first = RoutineVersion(sourceLabel: "Synthetic", steps: [])
        #expect(first.nextNumber == 2 && first.revised(steps: []).number == 2)
        #expect(RoutineVersion.inferredDraft(from: first, preserving: nil).number == 1)
    }

    @Test("A step saved before operations and observation references existed still reads")
    func legacyStepWithoutOptionalFieldsStillDecodes() throws {
        let id = UUID()
        let legacy = Data(#"{"id":"\#(id.uuidString)","title":"Tea","detail":"","kind":"custom","durationMinutes":4,"isRequired":true}"#.utf8)
        let step = try JSONDecoder().decode(RoutineStep.self, from: legacy)
        #expect(step == RoutineStep(id: id, title: "Tea", durationMinutes: 4, isRequired: true))
        #expect(step.automation == nil && step.observationReference == nil)
    }

    @Test("Finite extreme and subnormal instants survive completed and interrupted runs")
    func finiteExtremeInstantsRemainReadable() throws {
        let instants: [Double] = [
            -.greatestFiniteMagnitude, -1e100, -1, -Double.leastNonzeroMagnitude,
            0, Double.leastNonzeroMagnitude, 1, 1e100, .greatestFiniteMagnitude
        ]
        let routine = RoutineVersion(sourceLabel: "Synthetic extreme dates", steps: [
            RoutineStep(title: "First"), RoutineStep(title: "Second")
        ], isApproved: true)
        for instant in instants {
            let date = Date(timeIntervalSinceReferenceDate: instant)
            var run = RoutineSession(routine: routine)
            try run.start(at: date)
            try run.pause(at: Date(timeIntervalSinceReferenceDate: -instant))
            try run.resume(at: date)
            try run.advance(at: date)
            var interrupted = run
            try interrupted.stop(at: Date(timeIntervalSinceReferenceDate: -instant))
            try expectSavedSessionRoundTrip(interrupted)
            try run.advance(at: date)
            try expectSavedSessionRoundTrip(run)
            #expect(run.events.suffix(2).allSatisfy { $0.occurredAt == date })
        }
    }

    @Test("A long completed run retains the approved version after its owner's routine is revised")
    func longRunPinsItsApprovedRoutineAcrossRevision() throws {
        var ownerRoutine = RoutineVersion(number: Int.max, sourceLabel: "Synthetic long routine",
            steps: (0..<4_097).map { RoutineStep(title: "Synthetic \($0)", durationMinutes: 1_440) },
            isApproved: true)
        var run = RoutineSession(routine: ownerRoutine)
        let pinned = run.routine
        try run.start(at: Date(timeIntervalSinceReferenceDate: 0))
        ownerRoutine = ownerRoutine.revised(steps: [RoutineStep(title: "Replacement")])
        #expect(!ownerRoutine.isApproved)
        #expect(ownerRoutine.id != pinned.id)
        for index in pinned.steps.indices {
            try run.advance(skipping: index.isMultiple(of: 3),
                at: Date(timeIntervalSinceReferenceDate: Double(-index)))
        }
        #expect(run.status == .completed)
        #expect(run.currentStepIndex == 4_097)
        #expect(run.progress == 1)
        #expect(run.routine == pinned)
        #expect(run.routine.isApproved)
        #expect(run.events.count == 4_099)
        try expectSavedSessionRoundTrip(run)
    }

    @Test("Invisible nonblank titles keep exactly the same start and decode policy in every ending")
    func unicodeNonblankTitlesRemainReadableAcrossEndings() throws {
        // These scalars resemble whitespace without being removed by the public start rule.
        let titles = ["\u{200D}", "\u{FEFF}", "\u{2060}", "\n\u{0301}\n", "\u{200C}"]
        for title in titles {
            #expect(!title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let routine = RoutineVersion(sourceLabel: "Synthetic Unicode title",
                steps: [RoutineStep(title: title)], isApproved: true)
            var ready = RoutineSession(routine: routine)
            try ready.stop()
            try expectSavedSessionRoundTrip(ready)
            var running = RoutineSession(routine: routine)
            try running.start()
            var stoppedRunning = running
            try stoppedRunning.stop()
            try expectSavedSessionRoundTrip(stoppedRunning)
            var paused = running
            try paused.pause()
            try paused.stop()
            try expectSavedSessionRoundTrip(paused)
            try running.advance()
            try expectSavedSessionRoundTrip(running)
            #expect(throws: SessionError.invalidTransition) { try running.stop() }
        }
    }

    @Test("Unrecordable resume, paused advance and completion payloads are refused")
    func impossibleAdditionalEventTracesAreRefused() throws {
        let steps = [RoutineStep(title: "First"), RoutineStep(title: "Second")]
        let routine = RoutineVersion(sourceLabel: "Synthetic boundary routine", steps: steps, isApproved: true)
        var completed = RoutineSession(routine: routine)
        try completed.start()
        try completed.pause()
        try completed.resume()
        try completed.advance()
        try completed.advance()
        for damage in ["resumeWrongStep", "resumeWithoutPause", "advanceWhilePaused", "completionHasStep", "pauseHasNoStep"] {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(completed)) as? [String: Any])
            var events = try #require(object["events"] as? [[String: Any]])
            switch damage {
            case "resumeWrongStep": events[2]["stepID"] = steps[1].id.uuidString
            case "resumeWithoutPause": events.remove(at: 1)
            case "advanceWhilePaused": events.remove(at: 2)
            case "completionHasStep": events[5]["stepID"] = steps[1].id.uuidString
            case "pauseHasNoStep": events[1].removeValue(forKey: "stepID")
            default: Issue.record("Unknown synthetic damage")
            }
            object["events"] = events
            let data = try JSONSerialization.data(withJSONObject: object)
            #expect(throws: DecodingError.self, "\(damage)") {
                try JSONDecoder().decode(RoutineSession.self, from: data)
            }
        }
    }

    private func expectSavedSessionRoundTrip(_ run: RoutineSession) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutineBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = AtomicJSONFile<RoutineSession>(url: directory.appendingPathComponent("session.json"))
        try file.save(run)
        #expect(try file.load() == run)
    }

    private func rewritingEvents(of session: RoutineSession,
                                 _ change: (inout [[String: Any]]) throws -> Void) throws -> Data {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        var events = try #require(json["events"] as? [[String: Any]])
        try change(&events)
        json["events"] = events
        return try JSONSerialization.data(withJSONObject: json)
    }
}
