import Foundation
import MorningCore
import Testing
@testable import MorningApple

@Suite("Briefing step execution — injected preparation and speech")
@MainActor
struct MorningAppStepExecutorTests {
    private let now = Date(timeIntervalSince1970: 1_791_619_200)

    @Test func repeatUsesPinnedDocumentEvenAfterAnotherPreviewIsPrepared() async throws {
        let original = try document(title: "Original synthetic calendar")
        let newer = try document(title: "New synthetic calendar")
        var latest = original
        var preparations = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { preparations += 1; return latest },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let context = context(step)
        #expect(try await executor.execute(step: step, context: context) == .completed)
        latest = newer // The Settings preview changed; this session's facts must not.
        #expect(try await executor.execute(step: step, context: context) == .completed)
        #expect(preparations == 1 && utterances == [original.spokenText, original.spokenText])
        #expect(executor.pinnedBriefing?.id == original.id && executor.pinnedExecutionID == context.executionID)
    }

    @Test func newExecutionIdentityPreparesAgainAndChangesThePin() async throws {
        let first = try document(title: "First synthetic event")
        let second = try document(title: "Second synthetic event")
        var count = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { count += 1; return count == 1 ? first : second },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let firstContext = context(step), nextContext = context(step)
        _ = try await executor.execute(step: step, context: firstContext)
        _ = try await executor.execute(step: step, context: nextContext)
        #expect(count == 2 && utterances == [first.spokenText, second.spokenText])
        #expect(executor.pinnedExecutionID == nextContext.executionID && executor.pinnedBriefing?.id == second.id)
    }

    @Test func cancellationDuringPreparationPreventsLateSpeechAndPinning() async throws {
        let gate = ExecutorPreparationGate()
        let prepared = try document(title: "Late synthetic facts")
        var utterances: [String] = []
        var stops = 0
        let executor = MorningAppStepExecutor(prepare: { await gate.pause(); return prepared },
            speak: { utterances.append($0) }, stop: { stops += 1 }, now: { self.now }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let context = context(step)
        let task = Task { try await executor.execute(step: step, context: context) }
        await gate.waitUntilPaused()
        executor.cancel(context: context)
        gate.resume()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(utterances.isEmpty && stops == 1 && executor.pinnedBriefing == nil && executor.pinnedExecutionID == nil)
    }

    @Test func unavailableCalendarDoesNotPinWeatherOnlyDocumentAndRetryCanSucceed() async throws {
        let weatherOnly = try document(title: nil, weather: true)
        let calendarReady = try document(title: "Recovered synthetic calendar", weather: true)
        var count = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { count += 1; return count == 1 ? weatherOnly : calendarReady },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Calendar", automation: .todayCalendar)
        let context = context(step)
        let failed = try await executor.execute(step: step, context: context)
        guard case .unavailable = failed else { Issue.record("Missing Calendar must not report completed."); return }
        #expect(executor.pinnedBriefing == nil && executor.pinnedExecutionID == nil && utterances.isEmpty)
        #expect(try await executor.execute(step: step, context: context) == .completed)
        #expect(count == 2)
        try #require(utterances.count == 1)
        #expect(utterances[0] == MorningAppStepExecutor.text(for: .todayCalendar, in: calendarReady))
        #expect(!utterances[0].contains("Weather in"))
    }

    @Test func stalePreparedDocumentIsRejectedBeforeAnySpeech() async throws {
        let expired = try document(title: "Expired synthetic calendar")
        let later = now.addingTimeInterval(301)
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { expired }, speak: { utterances.append($0) },
            stop: {}, now: { later }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let result = try await executor.execute(step: step, context: context(step))
        guard case .unavailable = result else { Issue.record("Expired facts must be unavailable."); return }
        #expect(utterances.isEmpty && executor.pinnedBriefing == nil)
    }

    @Test func repeatRejectsExpiredPinWithoutSilentlyReplacingItsFacts() async throws {
        let original = try document(title: "Pinned synthetic facts")
        var clock = now
        var count = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { count += 1; return original },
            speak: { utterances.append($0) }, stop: {}, now: { clock }, timeZone: { "UTC" })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let context = context(step)
        #expect(try await executor.execute(step: step, context: context) == .completed)
        clock = try #require(original.validUntil)
        let repeated = try await executor.execute(step: step, context: context)
        guard case .unavailable = repeated else { Issue.record("Repeat cannot speak expired facts."); return }
        #expect(count == 1 && utterances == [original.spokenText])
        #expect(executor.pinnedBriefing?.id == original.id, "An expired pin stays reviewable until an explicit update.")
    }

    @Test(arguments: [true, false])
    func changedConfigurationOrRevokedPermissionBlocksPinnedRepeat(configurationChanged: Bool) async throws {
        let original = try document(title: "Pinned synthetic calendar")
        var configuration = UUID()
        var permissionAllowed = true
        var preparations = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { preparations += 1; return original },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" },
            configurationID: { configuration }, permitsPlayback: { _ in permissionAllowed })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let context = context(step)
        #expect(try await executor.execute(step: step, context: context) == .completed)
        if configurationChanged { configuration = UUID() } else { permissionAllowed = false }

        let repeated = try await executor.execute(step: step, context: context)
        guard case .unavailable = repeated else {
            Issue.record("A changed configuration or revoked permission must block pinned playback.")
            return
        }
        #expect(preparations == 1 && utterances == [original.spokenText])
        #expect(executor.pinnedBriefing?.id == original.id && executor.pinnedExecutionID == context.executionID,
                "Blocked facts stay reviewable; playback must not silently replace them.")
    }

    @Test func configurationChangeDuringPreparationPreventsInitialSpeechAndPinning() async throws {
        let gate = ExecutorPreparationGate()
        let prepared = try document(title: "Late synthetic facts from an old selection")
        var configuration = UUID()
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { await gate.pause(); return prepared },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" },
            configurationID: { configuration })
        let step = RoutineStep(title: "Your day", automation: .morningBriefing)
        let context = context(step)
        let task = Task { try await executor.execute(step: step, context: context) }
        await gate.waitUntilPaused()
        configuration = UUID()
        gate.resume()

        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(utterances.isEmpty && executor.pinnedBriefing == nil && executor.pinnedExecutionID == nil)
    }

    @Test func voiceDisabledAndUserLedMomentsNeverPrepareOrSpeak() async throws {
        var count = 0
        var utterances: [String] = []
        let executor = MorningAppStepExecutor(prepare: { count += 1; return nil },
            speak: { utterances.append($0) }, stop: {}, now: { self.now }, timeZone: { "UTC" })
        executor.spokenEnabled = false
        let spoken = RoutineStep(title: "Your day", automation: .morningBriefing)
        let disabled = try await executor.execute(step: spoken, context: context(spoken))
        guard case .needsUser = disabled else { Issue.record("Disabled speech must stay user-led."); return }
        executor.spokenEnabled = true
        let manual = RoutineStep(title: "Take a walk", automation: nil)
        let ownPace = try await executor.execute(step: manual, context: context(manual))
        guard case .needsUser = ownPace else { Issue.record("A manual moment is not an executed action."); return }
        #expect(count == 0 && utterances.isEmpty)
    }

    private func context(_ step: RoutineStep) -> MorningStepContext {
        .init(executionID: .init(sessionID: UUID(), routineVersionID: UUID(), stepID: step.id))
    }

    private func document(title: String?, weather includeWeather: Bool = false) throws -> PreparedMorningBriefing {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let bounds = calendar.dateInterval(of: .day, for: now)!
        let input: MorningBriefingInput<CalendarSnapshot>
        if let title {
            let choice = CalendarChoice(id: "selected", title: "Synthetic", sourceTitle: "Synthetic local source")
            let event = CalendarEventSummary(id: title, title: title, start: now.addingTimeInterval(600),
                end: now.addingTimeInterval(900), isAllDay: false, calendarTitle: "Synthetic", calendarID: choice.id)
            input = .snapshot(.init(retrievedAt: now, dayStart: bounds.start, dayEnd: bounds.end, events: [event],
                timeZoneIdentifier: "UTC", selectedCalendars: [choice]))
        } else { input = .unavailable }
        let weatherInput: MorningBriefingInput<WeatherObservationSnapshot>
        if includeWeather {
            let attribution = try WeatherAttributionInfo(legalURL: URL(string: "https://example.invalid/legal")!,
                combinedMarkLightURL: URL(string: "https://example.invalid/light.png")!,
                combinedMarkDarkURL: URL(string: "https://example.invalid/dark.png")!, serviceName: "Synthetic Weather")
            weatherInput = .snapshot(try .init(location: WeatherLocation(latitude: 10, longitude: 20, displayName: "Synthetic city"),
                retrievedAt: now, observationAt: now, temperatureCelsius: 20, conditionDescription: "Synthetic sunshine",
                symbolName: "sun.max", attribution: attribution))
        } else { weatherInput = .notConfigured }
        return try MorningBriefingComposer.prepare(calendar: input, weather: weatherInput,
            for: now, at: now, timeZoneIdentifier: "UTC")
    }
}

@MainActor
private final class ExecutorPreparationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var ready: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            ready?.resume(); ready = nil
        }
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { ready = $0 }
    }
    func resume() {
        let pending = continuation; continuation = nil; pending?.resume()
    }
}
