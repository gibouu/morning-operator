import Foundation
import HealthKit
import MorningApple

// NEVER RUN AGAINST REAL DATA. This reader compiles for the package's platforms and its
// value mapping is tested, but no authorization prompt, no query and no real sample has
// ever passed through it: that needs the HealthKit entitlement, a usage description and
// a device, which are not in this repository yet. Treat every line that touches
// `HKHealthStore` as unverified until a device check says otherwise.
//
// The app does not link this module. Nothing here can run in the app until the owner adds
// the `MorningHealth` product to the app target together with the entitlement.

/// Reads sleep-analysis samples, read-only. It asks for one type and writes nothing.
@MainActor
public final class HealthKitSleepReader: SleepObservationProviding {
    /// The Info.plist key HealthKit requires before a read prompt. Asking without it
    /// stops the process, so the prompt is refused here first.
    public nonisolated static let usageDescriptionKey = "NSHealthShareUsageDescription"

    private let usageDescription: @Sendable () -> String?
    private var store: HKHealthStore?

    public init(usageDescription: @escaping @Sendable () -> String? = {
        Bundle.main.object(forInfoDictionaryKey: HealthKitSleepReader.usageDescriptionKey) as? String
    }) {
        self.usageDescription = usageDescription
    }

    /// False on a device without a health data store. No store is created to answer this.
    public var isAvailableOnDevice: Bool { HKHealthStore.isHealthDataAvailable() }

    /// Shows Apple's read prompt for sleep analysis, once. Returning normally means the
    /// prompt was handled, not that reading was allowed: HealthKit does not report a read
    /// decision, and a refused read later returns no samples and no error.
    public func requestReadAccess() async throws {
        guard isAvailableOnDevice else { throw SleepObservationError.unavailableOnDevice }
        guard let text = usageDescription(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SleepObservationError.missingUsageDescription
        }
        try await healthStore().requestAuthorization(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
    }

    public func sleepSamples(in interval: DateInterval) async throws -> SleepReadOutcome {
        guard isAvailableOnDevice else { return .unavailableOnDevice }
        let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
        let query = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await query.result(for: healthStore())
        return .samples(samples.compactMap { sample in
            Self.sample(value: sample.value, start: sample.startDate, end: sample.endDate,
                        bundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                        productType: sample.sourceRevision.productType,
                        wasUserEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false)
        })
    }

    private func healthStore() -> HKHealthStore {
        if let store { return store }
        let created = HKHealthStore()
        store = created
        return created
    }

    /// The fields of one sample that are kept. A value HealthKit adds later, which this
    /// build does not know, is dropped rather than counted as sleep.
    nonisolated static func sample(value: Int, start: Date, end: Date, bundleIdentifier: String,
                                   productType: String?, wasUserEntered: Bool) -> SleepSample? {
        guard let stage = stage(value) else { return nil }
        return SleepSample(stage: stage, start: start, end: end, sourceID: bundleIdentifier,
            sourceKind: .classify(bundleIdentifier: bundleIdentifier, productType: productType,
                                  wasUserEntered: wasUserEntered))
    }

    nonisolated static func stage(_ value: Int) -> SleepStage? {
        guard let native = HKCategoryValueSleepAnalysis(rawValue: value) else { return nil }
        switch native {
        case .inBed: return .inBed
        case .awake: return .awake
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        @unknown default: return nil
        }
    }
}
