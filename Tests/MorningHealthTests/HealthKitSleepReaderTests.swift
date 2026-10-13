import Foundation
import HealthKit
import Testing
import MorningApple
@testable import MorningHealth

/// These tests cover the value mapping and the refusals that need no health store.
/// They do not read health data and prove nothing about a real device.
@Suite("HealthKit sleep reader — mapping only, no health data read")
@MainActor
struct HealthKitSleepReaderTests {
    @Test func everySleepAnalysisValueMapsToItsOwnStageAndOnlyAsleepStagesCount() {
        let expected: [(HKCategoryValueSleepAnalysis, SleepStage, Bool)] = [
            (.inBed, .inBed, false), (.awake, .awake, false), (.asleepUnspecified, .asleepUnspecified, true),
            (.asleepCore, .asleepCore, true), (.asleepDeep, .asleepDeep, true), (.asleepREM, .asleepREM, true)
        ]
        for (native, stage, asleep) in expected {
            #expect(HealthKitSleepReader.stage(native.rawValue) == stage)
            #expect(stage.isAsleep == asleep)
            #expect(HKCategoryValueSleepAnalysis.allAsleepValues.contains(native) == asleep,
                    "The asleep stages must be the ones HealthKit itself calls asleep.")
        }
        #expect(HealthKitSleepReader.stage(999) == nil, "An unknown value is dropped, never counted as sleep.")
    }

    @Test func sampleKeepsTheRecordedSpanAndWorksOutTheSourceKind() throws {
        let start = Date(timeIntervalSince1970: 1_791_590_400), end = start.addingTimeInterval(3_600)
        let sample = try #require(HealthKitSleepReader.sample(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            start: start, end: end, bundleIdentifier: "com.apple.health.SYNTHETIC", productType: "Watch7,1",
            wasUserEntered: false))
        #expect(sample == SleepSample(stage: .asleepCore, start: start, end: end,
                                      sourceID: "com.apple.health.SYNTHETIC", sourceKind: .watch))
        #expect(HealthKitSleepReader.sample(value: 999, start: start, end: end, bundleIdentifier: "x",
                                            productType: nil, wasUserEntered: false) == nil)
    }

    @Test func promptIsRefusedWithoutAUsageDescriptionOrAHealthStore() async {
        let reader = HealthKitSleepReader(usageDescription: { nil })
        // Either refusal happens before any HealthKit call that could prompt or stop the process.
        let expected: SleepObservationError = reader.isAvailableOnDevice ? .missingUsageDescription : .unavailableOnDevice
        await #expect(throws: expected) { try await reader.requestReadAccess() }
    }

    @Test(.enabled(if: !HKHealthStore.isHealthDataAvailable(), "This machine has a health data store; the test host has no entitlement to query it."))
    func aMachineWithoutAHealthStoreAnswersUnavailableWithoutQuerying() async throws {
        let now = Date(timeIntervalSince1970: 1_791_619_200)
        let outcome = try await HealthKitSleepReader().sleepSamples(in: DateInterval(start: now.addingTimeInterval(-3_600), end: now))
        #expect(outcome == .unavailableOnDevice)
    }
}
