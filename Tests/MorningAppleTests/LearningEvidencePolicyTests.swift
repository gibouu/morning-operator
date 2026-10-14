import Foundation
import Testing
@testable import MorningApple

/// Invented UI content plus public app copy. No captured personal OCR is stored in fixtures.
enum LearningEvidenceFixtures {
    static let setupOnly = """
    [User-selected video: 00:40.3; 3 frames sampled. This is partial visual evidence, not a complete interaction log.]

    [Observed frame at 00:00.0]
    Screen Sharing
    Morning Operator
    Share Screen
    Cancel

    [Observed frame at 00:10.0]
    Less handling. More morning.
    The briefing. The messages. That game of chess. Let's make space for the things you care about.
    Learn my morning

    [Observed frame at 00:20.0]
    App Library
    Suggestions
    Recently Added
    Social
    Entertainment
    """

    // Public interface copy only, not copied from a person's recorded observation.
    static let ownReviewScreen = """
    Learning your morning
    THE LAST SEVEN MORNINGS
    Find your rhythm.
    Average routine
    Routine timing excludes pauses. It doesn’t measure time in other apps or time saved.
    Morning
    Review
    Notes
    """

    static let calendarContent = "Calendar\nToday\n09:00 Team planning meeting\n10:30 Review project milestones"
    static let messageContent = "Messages\nAlex\nPlease bring the printed meeting notes tomorrow."

    // Current public UI wording plus invented visual labels, never personal OCR.
    static let observedOverview = """
    Your observed mornings
    My mornings
    Europe/Paris
    2 days with labeled samples · 3 days with observations
    Cedar
    2 of 2 labeled days
    Lumen
    1 of 2 labeled days
    1 observed day without labels · 4 dates without observations
    A recorded glimpse, not time spent. These samples don't establish app opens, reads or scrolls.
    From your observations
    Sampled screens across days
    """
}

@Suite("Conservative observation evidence")
struct LearningEvidencePolicyTests {
    @Test("Simplified home uses paired visible recording identity before learning")
    func nativeRecordingHomeDoesNotBecomeObservedActivity() {
        for markers in ["morning\nMORE · Recording", "MORNING\nmore • RECORDING",
                        "morning   MORE · Recording", "good morning\nMORE · Recording",
                        "bonjour\nMORE · Recording", "bonjour MORE · Recording",
                        // The badge alone on its line: nothing but MORE's home prints it.
                        "Calendar\nMORE · Recording"] {
            let screen = markers + "\n19 min\n09:00 Team planning meeting"
            #expect(!LearningEvidencePolicy.isEligibleVisualContext(screen))
            #expect(ProposalValidation.step(title: "Review calendar", detail: "", kind: "calendar", durationMinutes: 3,
                evidenceQuote: "09:00 Team planning meeting", source: "09:00 Team planning meeting", sourceContext: screen,
                sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
            }
        }
    }

    @Test("Recording words and external articles remain independent evidence")
    func nativeRecordingMarkerIsNotAGenericMorningFilter() throws {
        for screen in [
            "Calendar\nmorning\nRecording\n09:00 Team planning meeting",
            "Messages\nmorning\nPlease discuss MORE · Recording with the design team.",
            "Calendar\nmorning\n09:00 MORE · Recording planning meeting",
            "Article\nA morning more recording project can help document family stories."
        ] {
            #expect(LearningEvidencePolicy.isEligibleVisualContext(screen))
        }
        let written = "I opened MORE's morning page while MORE · Recording was visible. Then I checked my calendar."
        let units = try LearningEvidencePolicy.prepare(written, as: .writtenReport)
        #expect(units.first?.text == written)
        #expect(units.first?.kind == .userReportedActivity)
    }

    @Test("Native capture home is omitted without changing adjacent external source text")
    func nativeRecordingHomeKeepsAdjacentEvidence() throws {
        let recording = "[Observed frame at 00:00.0]\nmorning\nMORE · Recording\n09:00 Team planning meeting"
            + "\n\n[Observed frame at 00:10.0]\n" + LearningEvidenceFixtures.messageContent
        let units = try LearningEvidencePolicy.prepare(recording, as: .recording)
        try #require(units.count == 1)
        #expect(units[0].text.utf8.elementsEqual(LearningEvidenceFixtures.messageContent.utf8))
    }

    @Test("Glass home paired markers reject its displayed plan, including merged footer columns")
    func glassHomeIsNotNewObservedActivity() {
        for footer in ["Sample morning", "Your rhythm, at your pace", "Hold to arrange",
                       "Sample morning   Hold to arrange", "Your rhythm, at your pace   Hold to arrange",
                       "A new rhythm. Ready to review."] {
            let screen = "Sat, Oct 10\nmorning\n19 min\nplanned\n09:00 Team planning meeting\n" + footer
            #expect(!LearningEvidencePolicy.isEligibleVisualContext(screen))
            #expect(ProposalValidation.step(title: "Review calendar", detail: "", kind: "calendar", durationMinutes: 3,
                evidenceQuote: "09:00 Team planning meeting", source: "09:00 Team planning meeting", sourceContext: screen,
                sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + screen, as: .screenshot)
            }
        }
    }

    @Test("Active glass home needs its footer and paired playback state markers")
    func activeGlassHomeDoesNotRecycleRoutineContent() {
        for footer in ["Sample morning", "Your rhythm, at your pace"] {
            for playback in ["Now\nPause", "Paused\nContinue"] {
                #expect(!LearningEvidencePolicy.isEligibleVisualContext(
                    playback + "\n09:00 Team planning meeting\n" + footer))
            }
            // A footer or a single state word in a genuine external screen is insufficient.
            #expect(LearningEvidencePolicy.isEligibleVisualContext(
                "Calendar\nNow\n09:00 Team planning meeting\n" + footer))
        }
    }

    @Test("New welcome wording is interface copy even without its Learn button")
    func glassWelcomeUsesItsCurrentPublicCopy() {
        let screen = "a little more\nmorning.\nShow us a little of your morning.\nWe’ll find the rhythm together."
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + screen, as: .recording)
        }
        for marker in ["Show us a little of your morning.", "We’ll find the rhythm together."] {
            #expect(LearningEvidencePolicy.isEligibleVisualContext("Messages\n" + marker + "\nPlease bring the printed meeting notes tomorrow."))
        }
    }

    @Test("Home markers alone or inside event content do not block independent evidence")
    func glassHomeRequiresDistinctWholeScreenMarkers() throws {
        for marker in ["morning", "Sample morning", "Your rhythm, at your pace", "Hold to arrange",
                       "A new rhythm. Ready to review."] {
            #expect(LearningEvidencePolicy.isEligibleVisualContext("Calendar\n" + marker + "\n09:00 Team planning meeting"))
        }
        #expect(LearningEvidencePolicy.isEligibleVisualContext("Calendar\nmorning\n09:00 Sample morning planning meeting"))
        #expect(LearningEvidencePolicy.isEligibleVisualContext("Calendar\nMorning planning\nHold to arrange\n09:00 Team planning meeting"))
        let written = "I open MORE's morning page, where it says Your rhythm, at your pace and Hold to arrange. Then I check tomorrow’s calendar."
        let writtenUnits = try LearningEvidencePolicy.prepare(written, as: .writtenReport)
        #expect(writtenUnits.first?.text == written)
        #expect(writtenUnits.first?.kind == .userReportedActivity)
    }

    @Test("Mixed recording keeps external frames byte-exact while rejecting current home and welcome")
    func glassScreensDoNotRemoveAdjacentExternalEvidence() throws {
        let recording = "[Observed frame at 00:00.0]\nmorning\n09:00 Team planning meeting\nYour rhythm, at your pace\nHold to arrange"
            + "\n\n[Observed frame at 00:10.0]\n" + LearningEvidenceFixtures.calendarContent
            + "\n\n[Observed frame at 00:20.0]\nShow us a little of your morning.\nWe’ll find the rhythm together."
            + "\n\n[Observed frame at 00:30.0]\n" + LearningEvidenceFixtures.messageContent
        let original = Data(recording.utf8)
        let units = try LearningEvidencePolicy.prepare(recording, as: .recording)
        try #require(units.count == 2)
        #expect(units[0].text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(LearningEvidenceFixtures.calendarContent.utf8))
        #expect(units[1].text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(LearningEvidenceFixtures.messageContent.utf8))
        #expect(Data(recording.utf8) == original)
    }

    @Test("Observed-first overview cannot feed its derived labels back as new activity")
    func observedOverviewRejectsFeedbackAndKeepsIndependentFrames() throws {
        let overview = LearningEvidenceFixtures.observedOverview
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + overview, as: .screenshot)
        }
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare("[Observed frame at 00:00.0]\n" + overview, as: .recording)
        }
        let quote = "These samples don't establish app opens, reads or scrolls."
        #expect(ProposalValidation.step(title: "Review mornings", detail: "", kind: "custom", durationMinutes: 3,
            evidenceQuote: quote, source: quote, sourceContext: overview,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)

        let recording = "[Observed frame at 00:00.0]\n" + overview
            + "\n\n[Observed frame at 00:12.0]\n" + LearningEvidenceFixtures.calendarContent
            + "\n\n[Observed frame at 00:24.0]\n" + LearningEvidenceFixtures.messageContent
        let original = Data(recording.utf8)
        let retained = try LearningEvidencePolicy.prepare(recording, as: .recording)
        try #require(retained.count == 2)
        #expect(retained[0].text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(LearningEvidenceFixtures.calendarContent.utf8))
        #expect(retained[1].text.trimmingCharacters(in: .whitespacesAndNewlines).utf8.elementsEqual(LearningEvidenceFixtures.messageContent.utf8))
        #expect(Data(recording.utf8) == original)
    }

    @Test("Overview rejection requires paired UI markers and preserves written reports")
    func observedOverviewRequiresIndependentMarkers() throws {
        for marker in ["Your observed mornings", "2 days with labeled samples · 3 days with observations",
                       "A recorded glimpse, not time spent."] {
            #expect(LearningEvidencePolicy.isEligibleVisualContext(
                "Calendar\n\(marker)\n09:00 Team planning meeting"))
        }
        // The heading can remain visible while scrolling hides either the
        // denominator or the footer. Both independently identify this overview.
        for marker in ["1 day with labeled samples · 1 day with observations",
                       "A recorded glimpse, not time spent."] {
            #expect(!LearningEvidencePolicy.isEligibleVisualContext(
                "Your observed mornings\n\(marker)\n09:00 Team planning meeting"))
        }
        let report = "I opened Your observed mornings and reviewed the days with labeled samples. Then I read my calendar."
        let retained = try LearningEvidencePolicy.prepare(report, as: .writtenReport)
        #expect(retained.count == 1)
        #expect(retained.first?.kind == .userReportedActivity)
        #expect(retained.first?.text == report)
    }

    @Test("MORE's compact setup and routine surfaces remain interface content")
    func compactMoreScreensAreNotObservedHabits() {
        let screens = [
            "A little more morning.\nShow MORE a little of your morning.\nWe’ll find the rhythm together.",
            "Good morning.\n19 min planned\n09:00 Team planning meeting\nStart my morning\nUpdate my morning",
            "Good morning.\nYour first draft is ready to review.\nPeople and messages\nReview my morning",
            "A little perspective.\nAverage routine time\nSettings & connections\nRecord, describe or refine",
            "More room for your day.\nAnything you’d like to remember?\nA thought, a dream, a reminder"
        ]
        for screen in screens {
            #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
                try LearningEvidencePolicy.prepare("[User-selected screenshot; one moment, not a confirmed habit]\n" + screen, as: .screenshot)
            }
        }
    }

    @Test("Setup, picker, app marketing and launcher frames abstain without inference")
    func setupOnlyHasNoActivityEvidence() {
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) {
            try LearningEvidencePolicy.prepare(LearningEvidenceFixtures.setupOnly, as: .recording)
        }
    }

    @Test("Our Review screen's public copy is not evidence of a personal activity")
    func ownReviewScreenHasNoActivityEvidence() {
        let screenshot = "[User-selected screenshot; one moment, not a confirmed habit]\n" + LearningEvidenceFixtures.ownReviewScreen
        let video = "[Observed frame at 00:15.0]\n" + LearningEvidenceFixtures.ownReviewScreen
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(screenshot, as: .screenshot) }
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(video, as: .recording) }
        #expect(ProposalValidation.step(title: "Review routine", detail: "", kind: "custom", durationMinutes: 3,
            evidenceQuote: "Routine timing excludes pauses.", source: LearningEvidenceFixtures.ownReviewScreen,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
    }

    @Test("A generic routine label or one Review heading does not exclude real content")
    func ownReviewRequiresMultipleDistinctiveMarkers() throws {
        for heading in ["Average routine", "Learning your morning", "THE LAST SEVEN MORNINGS", "Find your rhythm."] {
            let source = "[User-selected screenshot; one moment, not a confirmed habit]\nCalendar\n\(heading)\n09:00 Team planning meeting"
            let units = try LearningEvidencePolicy.prepare(source, as: .screenshot)
            #expect(units.count == 1)
            #expect(units[0].text.contains("09:00 Team planning meeting"))
        }
    }

    @Test("Bare app icons or names do not establish that the apps were used")
    func appInventoryCannotBecomeActions() {
        let source = "[User-selected screenshot; one moment, not a confirmed habit]\nCalendar\nMessages\nChess\nMail\nPhotos\nSettings"
        #expect(throws: AppleIntelligenceError.insufficientActivityEvidence) { try LearningEvidencePolicy.prepare(source, as: .screenshot) }
    }

    @Test("Useful calendar and message content survive rejected surrounding frames unchanged")
    func mixedRecordingRetainsOnlyEligibleOriginalEvidence() throws {
        let source = LearningEvidenceFixtures.setupOnly
            + "\n\n[Observed frame at 00:22.0]\n" + LearningEvidenceFixtures.ownReviewScreen
            + "\n\n[Observed frame at 00:25.0]\n" + LearningEvidenceFixtures.calendarContent
            + "\n\n[Observed frame at 00:30.0]\n" + LearningEvidenceFixtures.messageContent
        let original = source
        let units = try LearningEvidencePolicy.prepare(source, as: .recording)
        #expect(units.count == 2)
        #expect(units[0].text.trimmingCharacters(in: .whitespacesAndNewlines) == LearningEvidenceFixtures.calendarContent)
        #expect(units[1].text.trimmingCharacters(in: .whitespacesAndNewlines) == LearningEvidenceFixtures.messageContent)
        #expect(units.allSatisfy { $0.kind == .visibleTaskContent })
        #expect(source == original)
    }

    @Test("Personal calendar, Messages and chess descriptions are preserved")
    func writtenActivityRemainsPositive() throws {
        let source = "At 07:30 I review today's calendar. I read Messages, then play chess for ten minutes. Later I join a screen sharing workshop."
        let units = try LearningEvidencePolicy.prepare(source, as: .writtenReport)
        #expect(units.count == 1)
        #expect(units.first?.kind == .userReportedActivity)
        #expect(units.first?.text == source)
        #expect(ProposalValidation.step(title: "Review calendar", detail: "A reported activity.", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "review today's calendar", source: source) != nil)
    }

    @Test("An exact quote from marketing is rejected even when the model claims activity")
    func exactQuoteAloneDoesNotGroundAnAction() {
        let source = "The briefing. The messages. That game of chess. Let's make space for the things you care about."
        #expect(ProposalValidation.step(title: "Read messages", detail: "Read messages each morning.", kind: "messages", durationMinutes: 5,
            evidenceQuote: "The messages. That game of chess.", source: source, sourceContext: source,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Read messages", detail: "", kind: "messages", durationMinutes: 5,
            evidenceQuote: "The messages. That game of chess.", source: source) == nil)
    }

    @Test("Frame context survives chunk boundaries and evidence kinds cannot be relabelled")
    func validatorChecksWholeFrameAndProvenance() {
        let quote = "09:00 Team planning meeting"
        let source = LearningEvidenceFixtures.calendarContent
        let picker = "Screen Sharing\nCancel\n" + source
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: quote, source: source, sourceContext: picker,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: quote, source: source, sourceContext: source,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "userReportedActivity") == nil)
    }

    @Test("Visible task content stays tentative, optional and without automation")
    func visualCalendarAndMessageQuotesRemainEligible() throws {
        let calendar = ProposalValidation.step(title: "Review calendar", detail: "A calendar entry was visible.", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "09:00 Team planning meeting", source: LearningEvidenceFixtures.calendarContent,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent")
        let step = try #require(calendar)
        #expect(step.detail.contains("does not prove an action or repeated habit"))
        #expect(step.automation == nil)
        #expect(!step.isRequired)
        #expect(ProposalValidation.step(title: "Review messages", detail: "A message was visible.", kind: "messages", durationMinutes: 3,
            evidenceQuote: "Please bring the printed meeting notes tomorrow.", source: LearningEvidenceFixtures.messageContent,
            sourceKind: .visibleTaskContent, claimedEvidenceKind: "visibleTaskContent") != nil)
    }

    @Test("Generic labels, metadata and invented quotes are insufficient")
    func labelsAndMetadataAreNotActivityEvidence() {
        let source = LearningEvidenceFixtures.calendarContent
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "Calendar", source: source, sourceKind: .visibleTaskContent,
            claimedEvidenceKind: "visibleTaskContent") == nil)
        #expect(ProposalValidation.step(title: "Calendar", detail: "", kind: "calendar", durationMinutes: 3,
            evidenceQuote: "09:00 Invented appointment", source: source, sourceKind: .visibleTaskContent,
            claimedEvidenceKind: "visibleTaskContent") == nil)
    }

    @Test("Equivalent frames deduplicate and many frames share bounded inference batches")
    func repeatedFramesDoNotCreateOneModelSessionEach() throws {
        let repeated = (0..<24).map { "[Observed frame at 00:\(String(format: "%02d", $0)).0]\n\(LearningEvidenceFixtures.calendarContent)" }.joined(separator: "\n\n")
        let unique = try LearningEvidencePolicy.prepare(repeated, as: .recording)
        #expect(unique.count == 1)
        #expect(LearningEvidencePolicy.inferenceChunks(unique, maximumCharacters: 1_500).count == 1)
        let different = (0..<24).map { "[Observed frame at 00:\(String(format: "%02d", $0)).0]\nCalendar\n09:00 Team planning meeting number \($0)" }.joined(separator: "\n\n")
        let units = try LearningEvidencePolicy.prepare(different, as: .recording)
        let chunks = LearningEvidencePolicy.inferenceChunks(units, maximumCharacters: 1_500)
        #expect(units.count == 24)
        #expect(chunks.count <= ObservationText.chunks(different, maximumCharacters: 1_500).count)
        #expect(chunks.allSatisfy { $0.count <= 1_500 })
    }
}
