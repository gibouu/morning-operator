import Foundation
import Testing
@testable import MorningCore

@Suite("Execution presents actions and live content instead of learning explanations")
struct RoutineExecutionPresentationTests {
    private let history = "Usually 12 min, on 4 of 5 mornings. Estimated from hourly Screen Time."

    @Test func learnedContextNeverBecomesTheContentOfAnAutomatedOrManualMoment() {
        let steps = [
            RoutineStep(title: "Instagram", detail: history, target: .inAppWeb(site: WebMorningSite.instagram.table.startURL), webBehavior: .browseFeed),
            RoutineStep(title: "Calendar", detail: history, automation: .todayCalendar),
            RoutineStep(title: "My morning", detail: history, automation: .morningBriefing),
            RoutineStep(title: "Mail", detail: history, automation: .gmailInbox),
            RoutineStep(title: "Quiet moment", detail: history, automation: .timedMoment),
            RoutineStep(title: "Personal moment", detail: history)
        ]
        for language in ["fr", "en"] {
            for step in steps {
                let text = step.executionPresentationText(locale: Locale(identifier: language))
                #expect(!text.isEmpty)
                #expect(!text.contains(history))
                #expect(!text.contains("Usually"))
            }
        }
    }

    @Test func onlyExplicitReadingOperationsPresentTheApprovedPersonalText() {
        for operation in [RoutineStepAutomation.spokenNote, .savedObservation] {
            let step = RoutineStep(title: "Personal words", detail: history, automation: operation)
            for language in ["fr", "en"] {
                #expect(step.executionPresentationText(locale: Locale(identifier: language)) == history)
            }
        }
    }

    @Test func instructionsFollowTheChosenLanguageWithoutChangingTheStep() {
        let timed = RoutineStep(title: "Quiet moment", detail: history, automation: .timedMoment)
        #expect(timed.executionPresentationText(locale: Locale(identifier: "en")) == "This moment is in progress.")
        #expect(timed.executionPresentationText(locale: Locale(identifier: "fr")) == "Ce moment est en cours.")
        let manual = RoutineStep(title: "Personal moment", detail: history)
        #expect(manual.executionPresentationText(locale: Locale(identifier: "fr")) == "Ce moment demande votre participation. Dites suivant quand vous êtes prêt.")
        let calendar = RoutineStep(title: "Calendar", detail: history, automation: .todayCalendar)
        #expect(calendar.executionPresentationText(locale: Locale(identifier: "fr")) == "Je prépare ce moment…")
        #expect(calendar.detail == history && timed.detail == history && manual.detail == history)
    }
}
