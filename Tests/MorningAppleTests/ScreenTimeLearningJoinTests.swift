import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Screen Time joins selected saved observations")
struct ScreenTimeLearningJoinTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Europe/Paris")!; return value
    }
    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func report(id: String = "com.burbn.instagram", seconds: Double = 480, empty: Bool = false) throws -> ScreenTimeObservationEvidence {
        let hours: [ScreenTimeHour] = empty ? [
            .init(interval: .init(start: at(14, 8), duration: 3600), firstPickup: at(14, 8),
                apps: [.init(bundleIdentifier: "com.burbn.instagram", seconds: 1200)])] : [
            .init(interval: .init(start: at(13, 22), duration: 3600), firstPickup: at(13, 22),
                apps: [.init(bundleIdentifier: "com.apple.mobilemail", seconds: 300)]),
            .init(interval: .init(start: at(14, 7), duration: 3600), firstPickup: at(14, 7),
                longestActivity: .init(start: at(14, 7), duration: seconds), apps: [.init(bundleIdentifier: id, seconds: seconds)])]
        return try #require(ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18), now: at(14, 14), calendar: calendar)
            .first { $0.day == at(14, 0) })
    }
    private func day() throws -> ObservationObservedDate {
        try .init(date: at(14, 7), timeZoneIdentifier: "Europe/Paris", provenance: .userAssigned)
    }
    private func following(_ old: ScreenTimeObservationEvidence) throws -> ScreenTimeObservationEvidence {
        try .init(day: old.day.addingTimeInterval(86400), timeZoneIdentifier: old.timeZoneIdentifier,
            requestedWindow: .init(start: old.requestedWindow.start.addingTimeInterval(86400), duration: old.requestedWindow.duration),
            retrievedAt: old.retrievedAt.addingTimeInterval(86400),
            returnedIntervals: old.returnedIntervals.map { .init(start: $0.start.addingTimeInterval(86400), duration: $0.duration) },
            morningWindow: old.morningWindow.map { .init(start: $0.start.addingTimeInterval(86400), duration: $0.duration) }, apps: old.apps)
    }
    private func lesson() throws -> ObservationAcquisition {
        var rhythm = BrowserRhythmAccumulator(site: .instagram)
        let totals = try #require(BrowserRhythmTotals(distance: 200, movingSeconds: 5, scrollBursts: 3, clicks: 2))
        let segments = try [(WebMorningBehavior.browseFeed, 0.0, 10.0), (.watchStories, 20.0, 100.0)].map {
            try #require(BrowserLearningSegment(behavior: $0.0, startSeconds: $0.1, endSeconds: $0.2, gestures: 2))
        }
        let updated = rhythm.update(totals, segments: segments)
        #expect(updated)
        return try .browserLesson(summary: rhythm.summary(durationSeconds: 110), observedDate: day(), importedAt: at(14, 14))
    }
    private func video() throws -> ObservationAcquisition {
        let frame = try ObservationFrameEvidence(requestedTimeSeconds: 0, actualTimeSeconds: 0, outcome: .observed,
            text: "Apple Calendar\nA colleague shared the complete project agenda.")
        let evidence = try ObservationVideoEvidence(durationSeconds: 2, frames: [frame])
        return try .init(importedAt: at(14, 14), observedDate: day(), origin: .human, sourceKind: .video,
            sourceLabel: "Selected video", originalText: evidence.renderedText, videoEvidence: evidence,
            frameReviews: [.init(sampleID: frame.id, label: "Apple Calendar", evidenceQuote: "Apple Calendar", reviewedAt: at(14, 14))])
    }
    private func assemble(_ entries: [ObservationAcquisition], preserving base: RoutineVersion? = nil,
                          preferences: RoutinePreferenceJournal? = nil,
                          selection: ScreenTimeMomentSelection? = nil) throws -> EvidenceRoutineProposal {
        let native = entries.contains { $0.correctedText == nil && $0.screenTimeEvidence != nil }
        let appSelection = try selection ?? (native ? ScreenTimeMomentSelection(referenceDate: at(14, 14)) : nil)
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: entries, screenTimeSelection: appSelection)
        let inputs = evidence.units.filter { $0.sourceLayer == .videoFrame || $0.sourceLayer == .correction }.map {
            EvidenceRoutineStepInput(title: $0.sourceLayer == .correction ? "My correction" : "Calendar first", detail: "A tentative moment",
                kind: .calendar, durationMinutes: 2,
                citations: [.init(unitID: $0.id, quote: $0.sourceLayer == .correction ? $0.text : "A colleague shared the complete project agenda.")])
        }
        return try LearningEvidencePreparation.assemble(evidence: evidence, steps: inputs, preserving: base, preferences: preferences, at: at(14, 14))
    }

    @Test("An explicit native order survives restoration while canonical authority and source selection remain checked")
    func nativeOrderIsRecreatedOnlyByTheExactStandingChoice() throws {
        let hours: [ScreenTimeHour] = [
            .init(interval: .init(start: at(14, 7), duration: 3600), firstPickup: at(14, 7),
                longestActivity: .init(start: at(14, 7), duration: 780), apps: [
                    .init(bundleIdentifier: "com.burbn.instagram", seconds: 480),
                    .init(bundleIdentifier: "com.google.Gmail", seconds: 180),
                    .init(bundleIdentifier: "com.apple.Music", seconds: 120)])]
        let report = try #require(ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18),
            now: at(14, 14), calendar: calendar).first { $0.day == at(14, 0) })
        let source = try ObservationAcquisition.screenTime(report), archive = try ObservationArchive(entries: [source])
        let empty = RoutinePreferenceJournal(), canonical = try assemble([source], preferences: empty)
        #expect(canonical.routine.steps.count == 3)
        var journal = empty
        try journal.rememberOrder(of: Array(canonical.routine.steps.reversed()))
        journal = try JSONDecoder().decode(RoutinePreferenceJournal.self, from: JSONEncoder().encode(journal))
        let proposal = try assemble([source], preferences: journal)
        #expect(proposal.routine.steps.map(\.id) == canonical.routine.steps.reversed().map(\.id))
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: archive, baseRoutine: nil, preferences: journal))
        #expect(restored.support.map(\.citations).allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.sourceLayer == .screenTimeAggregate } })
        #expect(restored.routine.steps.allSatisfy { $0.automation == nil && $0.target == nil })
        func permuted(_ proposal: EvidenceRoutineProposal) throws -> EvidenceRoutineProposal {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
            var routine = try #require(json["routine"] as? [String: Any])
            var steps = try #require(routine["steps"] as? [[String: Any]])
            steps.swapAt(0, 1); routine["steps"] = steps; json["routine"] = routine
            return try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: json))
        }
        #expect(try !permuted(canonical).isCurrent(archive: archive, baseRoutine: nil, preferences: empty), "Without a recorded order, a source permutation remains invalid.")
        #expect(try !permuted(restored).isCurrent(archive: archive, baseRoutine: nil, preferences: journal), "A different permutation cannot borrow the recorded order's authority.")
        var changed = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as? [String: Any])
        var selection = try #require(changed["screenTimeSelection"] as? [String: Any])
        selection["includedBundleIdentifiers"] = [String](); changed["screenTimeSelection"] = selection
        let omitted = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: changed))
        #expect(!omitted.isCurrent(archive: archive, baseRoutine: nil, preferences: journal), "Order does not make removed/unselected source apps current.")
        var kept = canonical.routine.steps[0]; kept.detail = "Owner's exact native ritual."; kept.durationMinutes = 4
        try journal.upsert(.init(target: kept, presence: .keep, durationMinutes: 4))
        try journal.upsert(.init(target: canonical.routine.steps[1], presence: .exclude))
        let personalized = try assemble([source], preferences: journal)
        let reloaded = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(personalized))
        #expect(reloaded.isCurrent(archive: archive, baseRoutine: nil, preferences: journal))
        #expect(reloaded.routine.steps.count == 2 && reloaded.routine.steps.last == kept)
        #expect(reloaded.support.last?.reason == .preservedUserDecision)
        #expect(!reloaded.routine.steps.contains { $0.id == canonical.routine.steps[1].id })
    }

    @Test("Three source types share one proposal; app totals do not rewrite observed gestures or budgets")
    func threeSourceJoin() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), lesson(), video()]
        let proposal = try assemble(entries)
        #expect(proposal.sourceSnapshots.count == 3)
        #expect(proposal.routine.steps.map(\.webBehavior) == [nil, .browseFeed, .watchStories])
        #expect(proposal.routine.steps.map(\.durationMinutes) == [2, 1, 2])
        #expect(proposal.routine.steps[0].automation == .todayCalendar)
        #expect(proposal.support[1].citations.map(\.sourceLayer) == [.original, .screenTimeAggregate])
        #expect(proposal.support[2].citations.count == 1)
        #expect(proposal.routine.steps[1].detail.contains("480"))
        #expect(!proposal.routine.isApproved)
        let archive = try ObservationArchive(entries: entries)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil))
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(restored.isCurrent(archive: try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive)), baseRoutine: nil))
    }

    @Test("App minutes alone propose only a manual baseline and are never sent to a language model")
    func nativeOnlyManual() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source])
        #expect(evidence.hasOnlyStructuredEvidence && !evidence.hasOnlyBrowserLessons && evidence.modelRequestCount == 0)
        let proposal = try assemble([source])
        #expect(proposal.routine.steps.count == 1 && proposal.routine.steps[0].durationMinutes == 8)
        #expect(proposal.routine.steps[0].target == nil && proposal.routine.steps[0].automation == nil && proposal.routine.steps[0].webBehavior == nil)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
        let unit = try #require(evidence.units.first)
        #expect(throws: RoutineEvidenceProposalError.invalidCitation) {
            try LearningEvidencePreparation.assemble(evidence: evidence,
                steps: [.init(title: "Invented stories", detail: "Unobserved gestures", kind: .entertainment, durationMinutes: 5,
                    citations: [.init(unitID: unit.id, quote: unit.text)])], preserving: nil)
        }
    }

    @Test("Eleven brief app openings remain source facts without inflating or aborting a usable morning")
    func manyBriefAppOpeningsDoNotAbortCommonProposal() throws {
        let briefIDs = ["net.whatsapp.WhatsApp", "com.apple.mobilecal", "com.apple.mobilemail", "com.apple.mobilesafari",
            "com.apple.weather", "com.apple.Music", "com.apple.Maps", "com.apple.reminders", "com.google.Gmail",
            "com.chess.iphone", "com.google.ios.youtube"]
        let apps = [ScreenTimeAppHour(bundleIdentifier: "com.burbn.instagram", seconds: 480)]
            + briefIDs.map { ScreenTimeAppHour(bundleIdentifier: $0, seconds: 10) }
        let hours: [ScreenTimeHour] = [
            .init(interval: .init(start: at(13, 22), duration: 3600), firstPickup: at(13, 22),
                apps: [.init(bundleIdentifier: "com.apple.mobilemail", seconds: 300)]),
            .init(interval: .init(start: at(14, 7), duration: 3600), firstPickup: at(14, 7),
                longestActivity: .init(start: at(14, 7), duration: 590), apps: apps)]
        let payload = try #require(ScreenTimeObservationEvidence.make(hours: hours, queryStart: at(13, 18),
            now: at(14, 14), calendar: calendar).first { $0.day == at(14, 0) })
        #expect(payload.hasMorningEvidence && payload.apps.count == 12)
        #expect(payload.apps.allSatisfy { $0.seconds > 0 })
        let source = try ObservationAcquisition.screenTime(payload)
        let archive = try ObservationArchive(entries: [source])
        let selection = try ScreenTimeMomentSelection(referenceDate: at(14, 14))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source], screenTimeSelection: selection)
        #expect(evidence.units.count == 12 && evidence.modelRequestCount == 0)
        let learning = ScreenTimeMorningLearner.learn(hours: hours, queryStart: at(13, 18), now: at(14, 14), calendar: calendar)
        let direct = try #require(ScreenTimeRoutineProposal.make(from: learning, nextMorning: at(15, 7),
            baseRoutineID: nil, calendar: calendar, now: at(14, 14)))
        #expect(direct.steps.count == 1)
        let proposal = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [], preserving: nil)
        #expect(proposal.routine.steps.count == 1 && proposal.routine.steps[0].durationMinutes == direct.steps[0].minutes)
        #expect(proposal.routine.createdAt == selection.referenceDate && proposal.screenTimeSelection == selection)
        let choices = try LearningEvidencePreparation.screenTimeAppChoices(acquisitions: [source], selection: selection)
        #expect(choices.filter(\.isEligible).count == 1 && choices.filter { !$0.isEligible }.count == 11)
        #expect(proposal.isCurrent(archive: archive, baseRoutine: nil))
        let decoded = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
        #expect(decoded.isCurrent(archive: archive, baseRoutine: nil))
        let kept = RoutineStep(title: "My breathing ritual", detail: "My exact personal choice", kind: .wellbeing,
            durationMinutes: 4, isRequired: true)
        let approved = RoutineVersion(sourceLabel: "My approved morning", steps: [kept], isApproved: true)
        let preferences = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        #expect(throws: RoutineEvidenceProposalError.screenTimePersonalChoicesNeedReview) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [], preserving: approved, preferences: preferences)
        }
        let explicit = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: ["com.burbn.instagram"])
        let withKeep = try assemble([source], preserving: approved, preferences: preferences, selection: explicit)
        #expect(withKeep.routine.steps.count == 2 && withKeep.routine.steps.contains(kept))
        #expect(withKeep.isCurrent(archive: archive, baseRoutine: approved, preferences: preferences))
        #expect(archive.entries == [source] && approved.steps == [kept] && approved.isApproved)
    }

    @Test("A selected unknown report stays visible without blocking a usable video or browser lesson")
    func unknownAlongsideOtherEvidence() throws {
        let unknown = try ObservationAcquisition.screenTime(report(empty: true))
        let browser = try lesson()
        let proposal = try assemble([unknown, browser])
        #expect(proposal.sourceSnapshots.count == 2 && proposal.routine.steps.count == 2)
        #expect(proposal.sourceSnapshots.first?.sourceLayer == .screenTimeAggregate)
        #expect(proposal.support.allSatisfy { $0.citations.allSatisfy { $0.acquisitionID == browser.id } })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [unknown, browser]), baseRoutine: nil))
        #expect(throws: RoutineEvidenceProposalError.insufficientEvidence) {
            try LearningEvidencePreparation.prepare(acquisitions: [unknown])
        }
        let withVideo = try assemble([unknown, video()])
        #expect(withVideo.routine.steps.first?.automation == .todayCalendar)
    }

    @Test("A lookalike app name cannot borrow the known app's identity or browser gestures")
    func exactIdentity() throws {
        let source = try ObservationAcquisition.screenTime(report(id: "com.example.Instagram"))
        let browser = try lesson()
        let proposal = try assemble([source, browser])
        #expect(proposal.routine.steps.count == 3)
        let app = try #require(proposal.routine.steps.last)
        #expect(app.title == "Instagram" && app.target == nil && app.webBehavior == nil)
        #expect(proposal.support.prefix(2).allSatisfy { $0.citations.count == 1 })
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [source, browser]), baseRoutine: nil))
    }

    @Test("Refresh updates one dated identity, keeps corrections, and invalidates a proposal even if displayed text is unchanged")
    func refreshRevision() throws {
        let original = try report()
        var archive = ObservationArchive()
        let id = try archive.upsertScreenTime(original)
        let proposal = try assemble(archive.entries)
        let changed = try ScreenTimeObservationEvidence(day: original.day, timeZoneIdentifier: original.timeZoneIdentifier,
            requestedWindow: original.requestedWindow, retrievedAt: original.retrievedAt.addingTimeInterval(1),
            returnedIntervals: original.returnedIntervals, morningWindow: original.morningWindow, apps: original.apps)
        #expect(changed.renderedText() == original.renderedText())
        #expect(try archive.upsertScreenTime(changed) == id)
        #expect(archive.entries.count == 1 && !proposal.isCurrent(archive: archive, baseRoutine: nil))
        try archive.correct(id: id, text: "I prefer stretching before breakfast.")
        let corrected = try assemble(archive.entries)
        #expect(corrected.support.first?.citations.first?.sourceLayer == .correction)
        #expect(corrected.routine.steps.first?.target == nil)
        #expect(try archive.upsertScreenTime(original) == id)
        #expect(archive.entry(id: id)?.correctedText == "I prefer stretching before breakfast.")
        #expect(archive.entry(id: id)?.screenTimeEvidence == original)
        #expect(!corrected.isCurrent(archive: archive, baseRoutine: nil))
        let unchanged = archive
        let unanswered = try ScreenTimeObservationEvidence.make(hours: [], queryStart: at(13, 18), now: at(14, 14), calendar: calendar)
        for report in unanswered { try archive.upsertScreenTime(report) }
        #expect(archive == unchanged)
    }

    @Test("Personal timing and exclusions run after native fusion")
    func preferencesLast() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), lesson()]
        let first = try assemble(entries)
        let preferences = try RoutinePreferenceJournal(entries: [
            RoutinePreference(target: first.routine.steps[0], durationMinutes: 7),
            RoutinePreference(target: first.routine.steps[1], presence: .exclude)], revision: UUID())
        let proposal = try assemble(entries, preferences: preferences)
        #expect(proposal.routine.steps.count == 1 && proposal.routine.steps[0].durationMinutes == 7)
        #expect(proposal.routine.steps[0].webBehavior == .browseFeed)
        #expect(proposal.support[0].reason == .inferredEvidenceWithUserPreference)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: preferences))
    }

    @Test("Restoration recomputes native duration and source allocation rather than trusting a saved proposal")
    func forgedProposal() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let proposal = try assemble([source])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var routine = try #require(object["routine"] as? [String: Any])
        var steps = try #require(routine["steps"] as? [[String: Any]])
        steps[0]["durationMinutes"] = 30; routine["steps"] = steps; object["routine"] = routine
        let restored = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!restored.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
    }

    @Test("Legacy notes remain decodable; deleting or forgetting removes the typed source locally")
    func legacyAndPrivacy() throws {
        let legacy = try ObservationAcquisition(observedDate: day(), origin: .human, sourceKind: .manual,
            sourceLabel: "My old note", originalText: "I stretch before breakfast.")
        let restored = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONEncoder().encode(legacy))
        #expect(restored.screenTimeEvidence == nil && restored == legacy)
        var archive = try ObservationArchive(entries: [legacy, ObservationAcquisition.screenTime(report())])
        let sourceID = archive.entries[1].id
        try archive.delete(id: sourceID)
        #expect(archive.entries == [legacy])
        try archive.upsertScreenTime(report())
        archive.clear()
        #expect(try JSONDecoder().decode(ObservationArchive.self, from: JSONEncoder().encode(archive)).entries.isEmpty)
        #expect(!String(decoding: try JSONEncoder().encode(archive), as: UTF8.self).contains("com.burbn.instagram"))
        let synthetic = try ObservationAcquisition.screenTime(report(), origin: .synthetic)
        #expect(throws: RoutineEvidenceProposalError.incompatibleSources) {
            try LearningEvidencePreparation.prepare(acquisitions: [legacy, synthetic])
        }
    }

    @Test("Saved presentation names are not reinterpreted through the current language or used as app identity")
    func savedNameAndDuplicateReports() throws {
        let original = try report()
        let named = try ScreenTimeObservationEvidence(day: original.day, timeZoneIdentifier: original.timeZoneIdentifier,
            requestedWindow: original.requestedWindow, retrievedAt: original.retrievedAt,
            returnedIntervals: original.returnedIntervals, morningWindow: original.morningWindow,
            apps: [.init(bundleIdentifier: "com.burbn.instagram", displayName: "Nom conservé dans la source", seconds: 480, secondsMeasured: false, firstHourIndex: 0)])
        let source = try ObservationAcquisition.screenTime(named, french: true)
        let decoded = try JSONDecoder().decode(ObservationAcquisition.self, from: JSONEncoder().encode(source))
        #expect(decoded.originalText.contains("Nom conservé dans la source"))
        #expect(decoded.screenTimeEvidence?.apps[0].bundleIdentifier == "com.burbn.instagram")
        #expect(try assemble([decoded, lesson()]).routine.steps.count == 2)
        let duplicate = try ObservationAcquisition.screenTime(named, french: false)
        #expect(throws: ObservationArchiveError.duplicateAcquisition) { try ObservationArchive(entries: [source, duplicate]) }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [source, duplicate])
        }
    }

    @Test("Significant app overflow asks for a useful choice and reserves every kept ritual before optional baselines")
    func significantOverflowAndExplicitChoice() throws {
        let base = try report()
        let ids = (1...12).map { "com.example.MorningApp\($0)" }
        let payload = try ScreenTimeObservationEvidence(day: base.day, timeZoneIdentifier: base.timeZoneIdentifier,
            requestedWindow: base.requestedWindow, retrievedAt: base.retrievedAt, returnedIntervals: base.returnedIntervals,
            morningWindow: .init(start: at(14, 7), duration: 720),
            apps: ids.map { .init(bundleIdentifier: $0, seconds: 60, secondsMeasured: false, firstHourIndex: 0) })
        let source = try ObservationAcquisition.screenTime(payload)
        let all = try ScreenTimeMomentSelection(referenceDate: at(14, 14))
        let evidence = try LearningEvidencePreparation.prepare(acquisitions: [source], screenTimeSelection: all)
        #expect(throws: RoutineEvidenceProposalError.screenTimeSelectionRequired(availableSlots: 8)) {
            try LearningEvidencePreparation.assemble(evidence: evidence, steps: [], preserving: nil)
        }
        let selected = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: Set(ids.prefix(8)))
        let limited = try assemble([source], selection: selected)
        #expect(limited.routine.steps.count == 8 && source.screenTimeEvidence?.apps.count == 12)
        #expect(limited.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
        let kept = (1...6).map { RoutineStep(title: "Personal ritual \($0)", detail: "Exact owner decision", kind: .wellbeing, durationMinutes: 2) }
        let preferences = try RoutinePreferenceJournal(entries: try kept.map { try RoutinePreference(target: $0, presence: .keep) }, revision: UUID())
        #expect(throws: RoutineEvidenceProposalError.screenTimeSelectionRequired(availableSlots: 4)) {
            try assemble([source], preferences: preferences, selection: selected)
        }
        let four = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: Set(ids.prefix(4)))
        let final = try assemble([source], preferences: preferences, selection: four)
        #expect(final.routine.steps.count == 10 && kept.allSatisfy { final.routine.steps.contains($0) })
        #expect(final.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil, preferences: preferences))
        let choices = try LearningEvidencePreparation.screenTimeAppChoices(acquisitions: [source], selection: four)
        #expect(choices.count == 12 && choices.filter(\.isIncluded).count == 4)
        let elevenKept = (1...11).map { RoutineStep(title: "Kept ritual \($0)", detail: "Exact owner decision", kind: .wellbeing, durationMinutes: 2) }
        let impossible = try RoutinePreferenceJournal(entries: try elevenKept.map {
            try RoutinePreference(target: $0, presence: .keep)
        }, revision: UUID())
        let one = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: [ids[0]])
        #expect(throws: RoutineEvidenceProposalError.tooManySteps) {
            try assemble([source], preferences: impossible, selection: one)
        }
    }

    @Test("A brief aggregate can still corroborate an observed sequence without changing its budget or gestures")
    func briefAggregateStillSupportsObservedSequence() throws {
        let original = try report()
        let payload = try ScreenTimeObservationEvidence(day: original.day, timeZoneIdentifier: original.timeZoneIdentifier,
            requestedWindow: original.requestedWindow, retrievedAt: original.retrievedAt,
            returnedIntervals: original.returnedIntervals, morningWindow: .init(start: at(14, 7), duration: 490), apps: [
                .init(bundleIdentifier: "com.apple.mobilesafari", seconds: 480, secondsMeasured: false, firstHourIndex: 0),
                .init(bundleIdentifier: "com.burbn.instagram", seconds: 10, secondsMeasured: false, firstHourIndex: 0)])
        let entries = try [ObservationAcquisition.screenTime(payload), lesson()]
        let proposal = try assemble(entries)
        #expect(proposal.routine.steps.map(\.webBehavior) == [.browseFeed, .watchStories, nil])
        #expect(proposal.routine.steps.map(\.durationMinutes) == [1, 2, 8])
        #expect(proposal.support[0].citations.contains { $0.sourceLayer == .screenTimeAggregate && $0.quote.contains("10") })
        #expect(proposal.support[1].citations.count == 1)
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil))
    }

    @Test("A kept native app restores at its inferred position for the same source and a new day")
    func keptNativeAppRestoresAcrossDays() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let first = try assemble([source])
        var kept = first.routine.steps[0]
        kept.detail = "My exact personal app ritual"; kept.durationMinutes = 7
        let preferences = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        let old = try report()
        let shifted = try following(old)
        for entry in [source, try ObservationAcquisition.screenTime(shifted)] {
            let proposal = try assemble([entry], preferences: preferences,
                selection: .init(referenceDate: at(15, 14)))
            #expect(proposal.routine.steps == [kept])
            #expect(proposal.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: nil, preferences: preferences))
        }
        var legacyKept = kept
        legacyKept.title = " INSTAGRAM  "; legacyKept.isRequired = true
        let legacyBase = RoutineVersion(sourceLabel: "Legacy approved routine", steps: [legacyKept], isApproved: true)
        for entry in [source, try ObservationAcquisition.screenTime(shifted)] {
            let evidence = try LearningEvidencePreparation.prepare(acquisitions: [entry],
                screenTimeSelection: .init(referenceDate: at(15, 14)))
            let legacy = try LearningEvidencePreparation.assemble(evidence: evidence, steps: [], preserving: legacyBase)
            #expect(legacy.routine.steps == [legacyKept])
            #expect(legacy.isCurrent(archive: try ObservationArchive(entries: [entry]), baseRoutine: legacyBase))
        }
        legacyKept.title = "My renamed morning ritual"
        let renamedBase = RoutineVersion(sourceLabel: "Legacy approved routine", steps: [legacyKept], isApproved: true)
        let renamedEvidence = try LearningEvidencePreparation.prepare(acquisitions: [source],
            screenTimeSelection: .init(referenceDate: at(14, 14)))
        let renamed = try LearningEvidencePreparation.assemble(evidence: renamedEvidence, steps: [], preserving: renamedBase)
        #expect(renamed.routine.steps == [legacyKept])
        #expect(renamed.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: renamedBase))
    }

    @Test("A kept video moment stays before the observed browser sequence on restoration")
    func mixedKeepOrderRestores() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), lesson(), video()]
        let first = try assemble(entries)
        let kept = first.routine.steps[0]
        let preferences = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        let proposal = try assemble(entries, preferences: preferences)
        #expect(proposal.routine.steps[0] == kept)
        #expect(proposal.routine.steps.dropFirst().map(\.webBehavior) == [.browseFeed, .watchStories])
        #expect(proposal.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: preferences))
    }

    @Test("Native identity survives a renamed Keep, Exclude or duration choice across source days")
    func renamedNativeChoicesAcrossDays() throws {
        let original = try report()
        let first = try assemble([ObservationAcquisition.screenTime(original)])
        var renamed = first.routine.steps[0]
        renamed.title = "My renamed personal ritual"; renamed.detail = "Owner wording"; renamed.durationMinutes = 7
        let next = try following(original)
        let withOtherApp = try ScreenTimeObservationEvidence(day: next.day, timeZoneIdentifier: next.timeZoneIdentifier,
            requestedWindow: next.requestedWindow, retrievedAt: next.retrievedAt, returnedIntervals: next.returnedIntervals,
            morningWindow: .init(start: at(15, 7), duration: 540), apps: next.apps + [
                .init(bundleIdentifier: "com.apple.mobilesafari", seconds: 60, secondsMeasured: false, firstHourIndex: 0)])
        let source = try ObservationAcquisition.screenTime(withOtherApp)
        let presences: [RoutinePreferencePresence?] = [.keep, .exclude, nil]
        for presence in presences {
            let preference = try RoutinePreference(target: renamed, presence: presence, durationMinutes: presence == nil ? 7 : nil)
            let journal = try RoutinePreferenceJournal(entries: [preference], revision: UUID())
            let proposal = try assemble([source], preferences: journal)
            if presence == .exclude {
                #expect(proposal.routine.steps.count == 1 && !proposal.routine.steps.contains { $0.id == renamed.id })
            } else {
                let retained = try #require(proposal.routine.steps.first { $0.id == renamed.id })
                #expect(proposal.routine.steps.count == 2 && retained.durationMinutes == 7)
                if presence == .keep { #expect(retained == renamed) }
                else { #expect(retained.title != renamed.title && retained.automation == nil && retained.target == nil) }
            }
            #expect(proposal.preferenceSnapshot == journal && !proposal.routine.isApproved)
            let decoded = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
            #expect(decoded.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil, preferences: journal))
        }
    }

    @Test("Unidentified old and manual choices require explicit app review without changing their decisions")
    func unidentifiedChoicesRequireReview() throws {
        let entries = try [ObservationAcquisition.screenTime(report()), video()]
        let old = RoutineStep(title: "My previously renamed app", detail: "Unknown original identity; preserve me", kind: .entertainment, durationMinutes: 7)
        let presences: [RoutinePreferencePresence?] = [.keep, .exclude, nil]
        for presence in presences {
            let choice = try RoutinePreference(target: old, presence: presence, durationMinutes: presence == nil ? 7 : nil)
            let journal = try RoutinePreferenceJournal(entries: [choice], revision: UUID())
            #expect(throws: RoutineEvidenceProposalError.screenTimePersonalChoicesNeedReview) {
                try assemble(entries, preferences: journal)
            }
            let selections: [Set<String>] = [[], ["com.burbn.instagram"]]
            for ids in selections {
                let reviewed = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: ids)
                let proposal = try assemble(entries, preferences: journal, selection: reviewed)
                #expect(proposal.routine.steps.count == 1 + ids.count + (presence == .keep ? 1 : 0))
                #expect(proposal.preferenceSnapshot == journal && journal.entries == [choice])
                #expect(proposal.routine.steps.contains(old) == (presence == .keep))
                #expect(proposal.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: journal))
                if !ids.isEmpty {
                    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
                    var selection = try #require(object["screenTimeSelection"] as? [String: Any])
                    selection.removeValue(forKey: "includedBundleIdentifiers"); object["screenTimeSelection"] = selection
                    let altered = try JSONDecoder().decode(EvidenceRoutineProposal.self,
                        from: JSONSerialization.data(withJSONObject: object))
                    #expect(!altered.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: journal))
                }
            }
        }
        var required = old; required.isRequired = true
        let legacyBase = RoutineVersion(sourceLabel: "Legacy owner routine", steps: [required], isApproved: true)
        #expect(throws: RoutineEvidenceProposalError.screenTimePersonalChoicesNeedReview) {
            try assemble(entries, preserving: legacyBase)
        }
        let reviewed = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: [])
        let legacy = try assemble(entries, preserving: legacyBase, selection: reviewed)
        #expect(legacy.routine.steps.contains(required))
        #expect(legacy.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: legacyBase))
        // Native corroboration of an existing browser sequence adds no app-only
        // candidate, so an unrelated standing choice requires no app review.
        let browserEntries = try [ObservationAcquisition.screenTime(report()), lesson()]
        let excluded = try RoutinePreferenceJournal(entries: [RoutinePreference(target: old, presence: .exclude)], revision: UUID())
        #expect(try assemble(browserEntries, preferences: excluded).routine.steps.count == 2)
        // A kept generative row no longer retains source citations. Review its
        // coexistence with a new native app now, so restoration needs no guess.
        let first = try assemble(entries)
        let videoKeep = first.routine.steps[0]
        for presence in [RoutinePreferencePresence.keep, .exclude] {
            let videoJournal = try RoutinePreferenceJournal(entries: [RoutinePreference(target: videoKeep, presence: presence)], revision: UUID())
            #expect(throws: RoutineEvidenceProposalError.screenTimePersonalChoicesNeedReview) {
                try assemble(entries, preferences: videoJournal)
            }
            let withVideoChoice = try assemble(entries, preferences: videoJournal,
                selection: .init(referenceDate: at(14, 14), includedBundleIdentifiers: ["com.burbn.instagram"]))
            #expect(withVideoChoice.routine.steps.contains(videoKeep) == (presence == .keep))
            #expect(withVideoChoice.isCurrent(archive: try ObservationArchive(entries: entries), baseRoutine: nil, preferences: videoJournal))
        }
        let nativeBrowserEntries = try [ObservationAcquisition.screenTime(report(id: "com.apple.mobilesafari")), lesson()]
        let browser = try assemble(nativeBrowserEntries)
        let excludeFeed = try RoutinePreferenceJournal(entries: [RoutinePreference(target: browser.routine.steps[0], presence: .exclude)], revision: UUID())
        let withExcludedFeed = try assemble(nativeBrowserEntries, preferences: excludeFeed)
        #expect(withExcludedFeed.routine.steps.count == 2 && withExcludedFeed.routine.steps[0].webBehavior == .watchStories)
        #expect(withExcludedFeed.isCurrent(archive: try ObservationArchive(entries: nativeBrowserEntries), baseRoutine: nil, preferences: excludeFeed))
    }

    @Test("Review confirmation expires with source bytes, personal choices or the base routine")
    func confirmationRevision() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let original = try LearningEvidencePreparation.screenTimeSelectionReviewRevision(acquisitions: [source], routine: nil, preferences: .init())
        let changed = try ObservationAcquisition.screenTime(report(seconds: 540), id: source.id)
        #expect(try LearningEvidencePreparation.screenTimeSelectionReviewRevision(acquisitions: [changed], routine: nil, preferences: .init()) != original)
        let kept = RoutineStep(title: "A personal ritual")
        let journal = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
        #expect(try LearningEvidencePreparation.screenTimeSelectionReviewRevision(acquisitions: [source], routine: nil, preferences: journal) != original)
        #expect(try LearningEvidencePreparation.screenTimeSelectionReviewRevision(acquisitions: [source],
            routine: .init(sourceLabel: "A changed routine", steps: [kept]), preferences: .init()) != original)
    }

    @Test("Synthetic native provenance survives renamed Keep, personal evidence, export and legacy base retention")
    func nativeSyntheticProvenance() throws {
        let sample = try ObservationAcquisition.screenTime(report(), origin: .synthetic)
        let initial = try assemble([sample])
        var kept = initial.routine.steps[0]
        #expect(kept.syntheticEvidence == true && initial.routine.isSynthetic)
        kept.title = "My own title"; kept.detail = "Edited owner text with no sample marker"
        for typedFlag in [true, false] {
            if !typedFlag { kept.syntheticEvidence = nil }
            let base = RoutineVersion(sourceLabel: typedFlag ? "Owner text" : "Demo fixture — old sample routine", steps: [kept])
            let journal = try RoutinePreferenceJournal(entries: [RoutinePreference(target: kept, presence: .keep)], revision: UUID())
            let personal = try ObservationAcquisition.screenTime(following(report()))
            let proposal = try assemble([personal], preserving: base, preferences: journal)
            #expect(proposal.sourceSnapshots.allSatisfy { $0.origin == .human })
            #expect(proposal.routine.steps == [kept] && proposal.routine.isSynthetic)
            #expect(proposal.routine.steps.allSatisfy { $0.automation == nil && $0.target == nil })
            let decoded = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONEncoder().encode(proposal))
            #expect(decoded.isCurrent(archive: try ObservationArchive(entries: [personal]), baseRoutine: base, preferences: journal))
            let portable = try PortableRoutineDocument(routine: decoded.routine)
            #expect(portable.sourceIsSynthetic)
            #expect(try PortableRoutineDocument.decode(portable.encoded()).importedDraft(replacing: nil).isSynthetic)
        }
        var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(initial.routine.steps[0])) as? [String: Any])
        legacy.removeValue(forKey: "syntheticEvidence")
        #expect(try JSONDecoder().decode(RoutineStep.self, from: JSONSerialization.data(withJSONObject: legacy)).syntheticEvidence == nil)
    }

    @Test("Selection snapshots reject unavailable identities, malformed versions and legacy native proposals require a new review")
    func selectionSnapshotBoundsAndLegacy() throws {
        let source = try ObservationAcquisition.screenTime(report())
        let absent = try ScreenTimeMomentSelection(referenceDate: at(14, 14), includedBundleIdentifiers: ["com.example.Absent"])
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) {
            try LearningEvidencePreparation.prepare(acquisitions: [source], screenTimeSelection: absent)
        }
        #expect(throws: RoutineEvidenceProposalError.invalidSelection) { try ScreenTimeMomentSelection(referenceDate: .init(timeIntervalSince1970: .nan)) }
        let proposal = try assemble([source])
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        object.removeValue(forKey: "screenTimeSelection")
        let legacy = try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(!legacy.isCurrent(archive: try ObservationArchive(entries: [source]), baseRoutine: nil))
        object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(proposal)) as? [String: Any])
        var selection = try #require(object["screenTimeSelection"] as? [String: Any])
        for version in [1, 99] {
            selection["policyVersion"] = version; object["screenTimeSelection"] = selection
            #expect(throws: (any Error).self) {
                try JSONDecoder().decode(EvidenceRoutineProposal.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
    }
}
