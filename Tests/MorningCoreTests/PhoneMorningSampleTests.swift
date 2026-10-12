import Foundation
import Testing
@testable import MorningCore

@Suite("Explicit phone morning sample")
struct PhoneMorningSampleTests {
    @Test(arguments: ["en_GB", "fr_FR", "fr_CA"])
    func sampleRequiresApprovalAndCannotDispatchConnectedActions(_ locale: String) throws {
        let sample = PhoneMorningSample.routine(locale: Locale(identifier: locale))
        #expect(sample.isSynthetic)
        #expect(!sample.isApproved)
        #expect(sample.steps.count == 8)
        #expect(sample.totalDurationMinutes == 45)
        #expect(Set(sample.steps.map(\.id)).count == sample.steps.count)
        #expect(sample.steps.allSatisfy {
            $0.durationMinutes > 0 && !$0.isRequired && $0.automation == nil && $0.observationReference == nil
        })
        var session = RoutineSession(routine: sample)
        #expect(throws: SessionError.routineNeedsApproval) { try session.start() }
        #expect(session.events.isEmpty)
        let restored = try JSONDecoder().decode(RoutineVersion.self, from: JSONEncoder().encode(sample.approved()))
        #expect(restored.isSynthetic)
        #expect(restored.steps.allSatisfy { $0.automation == nil && $0.observationReference == nil })
    }

    @Test func messagingAppsStaySeparateFromBriefingAndEntertainment() {
        let sample = PhoneMorningSample.routine(locale: Locale(identifier: "en_GB"))
        #expect(sample.steps.filter { $0.kind == .messages }.map(\.title) == [
            "iMessage", "WhatsApp", "WhatsApp Business", "Messenger", "Mail"
        ])
        #expect(sample.steps.filter { $0.kind == .briefing }.count == 1)
        #expect(sample.steps.filter { $0.kind == .entertainment }.map(\.durationMinutes) == [10])
        #expect(sample.steps.last?.kind == .custom)
    }

    @Test func frenchCopyKeepsProvenanceAndSamePlanWithoutRenamingAppBrands() {
        let french = PhoneMorningSample.routine(locale: Locale(identifier: "fr_CA"))
        let english = PhoneMorningSample.routine(locale: Locale(identifier: "en_GB"))
        #expect(french.steps.first?.title == "Calendrier et météo")
        #expect(french.steps.last?.title == "Une pensée pour plus tard")
        #expect(french.steps[6].title == "Parcourir vos fils")
        #expect(french.steps.map(\.kind) == english.steps.map(\.kind))
        #expect(french.steps.map(\.durationMinutes) == english.steps.map(\.durationMinutes))
        #expect(french.steps.filter { $0.kind == .messages }.map(\.title) == english.steps.filter { $0.kind == .messages }.map(\.title))
        #expect(french.sourceLabel.contains("synthétique"))
        #expect(french.isSynthetic)
        #expect(french.steps[1].detail.contains("n’est pas connecté"))
        #expect(PhoneMorningSample.routine(locale: Locale(identifier: "de_DE")).steps.map(\.title) == english.steps.map(\.title))
    }

    @Test func manufacturedSampleNeverBecomesAnImplicitPersonalHabit() {
        var sample = PhoneMorningSample.routine(locale: Locale(identifier: "fr_FR")).approved()
        // Even an old saved required flag on the sample must not leak into a new
        // personal inference. Explicit journal choices have their own policy.
        sample.steps[0].isRequired = true
        let observed = RoutineStep(title: "My actual morning", kind: .custom, durationMinutes: 2)
        let proposal = RoutineVersion.inferredDraft(
            from: .init(sourceLabel: "Reviewed personal evidence", steps: [observed]), preserving: sample
        )
        #expect(proposal.steps == [observed])
        #expect(!proposal.isApproved)
        #expect(!proposal.isSynthetic)
        #expect(sample.isSynthetic && sample.isApproved)
        #expect(DemoFixtures.candidateRoutine.steps.count == 4)
    }
}
