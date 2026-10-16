import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Closed vocabulary only: nothing from titles, notes, calendar facts or OCR.
public enum MorningActivityCategory: String, Codable, Hashable, Sendable, CaseIterable {
    case briefing, messages, calendar, wellbeing, entertainment, custom
    public var displayName: String { displayName(locale: AppLanguage.locale) }
    public func displayName(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        return switch self {
        case .briefing: String(localized: "Briefing", bundle: bundle, locale: locale)
        case .messages: String(localized: "Messages", bundle: bundle, locale: locale)
        case .calendar: String(localized: "Calendar", bundle: bundle, locale: locale)
        case .wellbeing: String(localized: "Wellbeing", bundle: bundle, locale: locale)
        case .entertainment: String(localized: "Time to enjoy", bundle: bundle, locale: locale)
        case .custom: String(localized: "Your moment", bundle: bundle, locale: locale)
        }
    }
}

public enum MorningActivityStatus: String, Codable, Hashable, Sendable, CaseIterable {
    case running, paused, needsAttention
    public var displayName: String { displayName(locale: AppLanguage.locale) }
    public func displayName(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        return switch self {
        case .running: String(localized: "In progress", bundle: bundle, locale: locale)
        case .paused: String(localized: "Paused", bundle: bundle, locale: locale)
        case .needsAttention: String(localized: "Your turn", bundle: bundle, locale: locale)
        }
    }
}

/// Tests use a distinct namespace even when running the same installed bundle.
public enum MorningActivityNamespace: Codable, Hashable, Sendable {
    case production
    case testing(workspaceID: UUID)

    /// One namespace for both app publications and background timer intents.
    /// A malformed test directory cannot fall through to production activities.
    public static func workspace(directory: URL, isUITesting: Bool) -> Self? {
        guard isUITesting else { return .production }
        let prefix = "MorningOperatorUITests-"
        let name = directory.lastPathComponent
        guard name.hasPrefix(prefix), let id = UUID(uuidString: String(name.dropFirst(prefix.count))) else { return nil }
        return .testing(workspaceID: id)
    }
}

public enum MorningActivityValidationError: Error, Sendable, Equatable {
    case invalidProgress, invalidTimestamp
}

/// The running step's timer as the Lock Screen shows it: where the step went, when its
/// time ends, and where Next goes. Names come from the closed `StepDestination` list.
public struct MorningActivityStepTimer: Codable, Hashable, Sendable {
    public let stepID: UUID
    public let destination: StepDestination
    public let endsAt: Date
    /// Actual persisted step start. Nil for older payloads; artwork must not invent it.
    public let startedAt: Date?
    /// Nil when the next step stays in MORE or there is no next step.
    public let nextDestination: StepDestination?
    public let hasNextStep: Bool
    public let pausedRemaining: TimeInterval?
    public init(stepID: UUID, destination: StepDestination, endsAt: Date,
                nextDestination: StepDestination?, hasNextStep: Bool, pausedRemaining: TimeInterval? = nil,
                startedAt: Date? = nil) {
        self.stepID = stepID; self.destination = destination; self.endsAt = endsAt
        self.nextDestination = nextDestination; self.hasNextStep = hasNextStep
        self.pausedRemaining = pausedRemaining
        self.startedAt = startedAt
    }

    /// A snapshot fraction of the current time budget, not a background animation.
    /// Unknown starts stay unknown; paused payloads use their frozen remaining time.
    public func elapsedFraction(at date: Date) -> Double? {
        guard let startedAt, startedAt.timeIntervalSinceReferenceDate.isFinite,
              endsAt.timeIntervalSinceReferenceDate.isFinite else { return nil }
        let duration = endsAt.timeIntervalSince(startedAt)
        guard duration > 0 else { return nil }
        let remaining = pausedRemaining ?? endsAt.timeIntervalSince(date)
        guard remaining.isFinite else { return nil }
        return min(1, max(0, 1 - max(0, remaining) / duration))
    }

    /// "Next: Instagram", "Next: MORE" or "Finish".
    public var nextLabel: String { nextLabel(locale: AppLanguage.locale) }
    public func nextLabel(locale: Locale) -> String {
        let bundle = AppLanguage.bundle(for: .module, languageCode: locale.language.languageCode?.identifier)
        guard hasNextStep else { return String(localized: "Finish", bundle: bundle, locale: locale) }
        let name = nextDestination?.displayName(locale: locale) ?? "MORE"
        return String(localized: "Next: \(name)", bundle: bundle, locale: locale)
    }
}

public struct MorningActivityContentState: Codable, Hashable, Sendable {
    public let category: MorningActivityCategory
    public let status: MorningActivityStatus
    /// Number of moments passed, including explicitly skipped moments; not a
    /// claim that a real-world action was performed or a message was read.
    public let completedSteps: Int
    public let totalSteps: Int
    public let updatedAt: Date
    /// Present only while the current step has a target and its timer.
    public let stepTimer: MorningActivityStepTimer?
    /// The app's selected language, carried across the widget process boundary.
    /// Nil in older activities, whose interface falls back to the current app language.
    public let languageIdentifier: String?
    /// Solar timing only; no location coordinates cross into the extension.
    /// Missing in older activities, which use the same reference day as Home.
    public let brandClock: MorningActivityBrandClock?
    public var locale: Locale { Locale(identifier: languageIdentifier ?? AppLanguage.localeIdentifier) }
    public var currentStepNumber: Int { completedSteps + 1 }

    public init(category: MorningActivityCategory, status: MorningActivityStatus,
                completedSteps: Int, totalSteps: Int, updatedAt: Date,
                stepTimer: MorningActivityStepTimer? = nil, languageIdentifier: String? = nil,
                brandClock: MorningActivityBrandClock? = nil) throws {
        guard (1...100).contains(totalSteps), completedSteps >= 0, completedSteps < totalSteps else {
            throw MorningActivityValidationError.invalidProgress
        }
        guard updatedAt.timeIntervalSinceReferenceDate.isFinite else {
            throw MorningActivityValidationError.invalidTimestamp
        }
        self.category = category; self.status = status
        self.completedSteps = completedSteps; self.totalSteps = totalSteps; self.updatedAt = updatedAt
        self.stepTimer = stepTimer
        self.languageIdentifier = languageIdentifier.flatMap { ["fr", "en"].contains($0) ? $0 : nil }
        self.brandClock = brandClock
    }
    private enum CodingKeys: CodingKey { case category, status, completedSteps, totalSteps, updatedAt, stepTimer, languageIdentifier, brandClock }
    public init(from decoder: any Decoder) throws {
        let value = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(category: value.decode(MorningActivityCategory.self, forKey: .category),
            status: value.decode(MorningActivityStatus.self, forKey: .status),
            completedSteps: value.decode(Int.self, forKey: .completedSteps),
            totalSteps: value.decode(Int.self, forKey: .totalSteps),
            updatedAt: value.decode(Date.self, forKey: .updatedAt),
            stepTimer: value.decodeIfPresent(MorningActivityStepTimer.self, forKey: .stepTimer),
            languageIdentifier: value.decodeIfPresent(String.self, forKey: .languageIdentifier),
            brandClock: value.decodeIfPresent(MorningActivityBrandClock.self, forKey: .brandClock))
    }
    public func hasSameProgress(as other: Self) -> Bool {
        category == other.category && status == other.status &&
        completedSteps == other.completedSteps && totalSteps == other.totalSteps && stepTimer == other.stepTimer &&
        languageIdentifier == other.languageIdentifier && brandClock == other.brandClock
    }

    /// The logo follows wall-clock light, independently of progress or pause.
    public func brandAppearance(at date: Date) -> MorningBrandAppearance {
        (brandClock ?? MorningActivityBrandClock(solar: .fixed)).appearance(at: date)
    }

    /// When this content stops being trustworthy. A running step timer is exact until
    /// its end, so the content goes stale at that end (the widget then shows Time's up);
    /// everything else goes stale `staleAfter` seconds after it was published.
    public func staleDate(staleAfter: TimeInterval) -> Date {
        let ordinary = updatedAt.addingTimeInterval(staleAfter)
        guard let stepTimer, status != .paused else { return ordinary }
        return stepTimer.endsAt > updatedAt ? stepTimer.endsAt : ordinary
    }
}

public struct MorningActivitySnapshot: Codable, Hashable, Sendable {
    public let sessionID: UUID
    public let state: MorningActivityContentState
    public init(sessionID: UUID, state: MorningActivityContentState) {
        self.sessionID = sessionID; self.state = state
    }
}

public enum MorningActivityProjection {
    /// Ready and terminal sessions have no Live Activity. Paused is explicit;
    /// a running session may instead need attention for an unavailable operation.
    public static func snapshot(session: RoutineSession?, needsAttention: Bool = false,
                                timer: StepTimer? = nil, at date: Date = Date(),
                                brandClock: MorningActivityBrandClock? = nil) -> MorningActivitySnapshot? {
        guard let session, session.status == .running || session.status == .paused,
              session.routine.isApproved, let step = session.currentStep,
              let category = MorningActivityCategory(rawValue: step.kind.rawValue) else { return nil }
        let status: MorningActivityStatus = session.status == .paused ? .paused :
            (needsAttention ? .needsAttention : .running)
        var stepTimer: MorningActivityStepTimer?
        if let timer, timer.belongs(to: session.id, stepID: step.id), let target = step.target {
            let next = StepNavigation.nextStep(in: session)
            stepTimer = MorningActivityStepTimer(stepID: step.id, destination: target.destination, endsAt: timer.endsAt,
                nextDestination: next?.target?.destination, hasNextStep: next != nil,
                pausedRemaining: timer.pausedAt == nil ? nil : timer.remaining(at: date), startedAt: timer.startedAt)
        }
        guard let state = try? MorningActivityContentState(category: category, status: status,
            completedSteps: session.currentStepIndex, totalSteps: session.routine.steps.count, updatedAt: date,
            stepTimer: stepTimer, languageIdentifier: AppLanguage.code, brandClock: brandClock) else { return nil }
        return .init(sessionID: session.id, state: state)
    }
}

#if canImport(ActivityKit) && os(iOS)
public struct MorningActivityAttributes: ActivityAttributes {
    public typealias ContentState = MorningActivityContentState
    public let sessionID: UUID
    public let namespace: MorningActivityNamespace
    public init(sessionID: UUID, namespace: MorningActivityNamespace = .production) {
        self.sessionID = sessionID; self.namespace = namespace
    }
}
#endif
