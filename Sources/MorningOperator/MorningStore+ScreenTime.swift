import Foundation
import MorningCore

/// Learn from Screen Time (docs/SCREEN-TIME-INTEGRATION.md): one approval, then one read of the
/// last week's hourly minutes, turned into a suggestion that waits for review. Its app
/// identifiers, labels, planned minutes and coverage stay in the local workspace; no raw
/// activity stream is logged. Returned daily summaries remain in memory for this launch.
extension MorningStore {
    /// Days asked for. How far back the system really answers is measured on each read.
    static let screenTimeDaysRequested = 7

    func refreshScreenTimeAccess() { screenTimeAccess = screenTimeSource.access }

    func learnFromScreenTime() {
        guard !privacyBlocksWork, storageIsAvailable, !busy, !sessionActive, !voiceInputBlocksPlayback, !screenTimeBusy else { return }
        screenTimeBusy = true
        screenTimeMessage = nil
        let generation = dataGeneration
        let source = screenTimeSource
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if self.dataGeneration == generation { self.screenTimeBusy = false } }
            do {
                guard source.access != .unavailable else {
                    self.screenTimeMessage = String(localized: "Learning from Screen Time needs iOS 26.4 or later.")
                    return
                }
                if source.access != .approved { try await source.requestAccess() }
                guard self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                self.refreshScreenTimeAccess()
                guard self.screenTimeAccess == .approved else {
                    self.screenTimeMessage = self.screenTimeAccessExplanation
                    return
                }
                let calendar = Calendar.current
                let end = Date()
                let queryStart = calendar.date(byAdding: .day, value: -Self.screenTimeDaysRequested, to: calendar.startOfDay(for: end)) ?? end
                let hours = try await source.hours(from: queryStart, to: end)
                guard self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                var own: Set<String> = []
                if let id = Bundle.main.bundleIdentifier { own.insert(id) }
                self.screenTimeDailyUsage = ScreenTimeDailyUsage.summarize(hours: hours, calendar: calendar, ownBundleIdentifiers: own)
                let learning = ScreenTimeMorningLearner.learn(hours: hours, queryStart: queryStart, now: end,
                                                              calendar: calendar, ownBundleIdentifiers: own)
                self.screenTimeLearning = learning
                let nextMorning = calendar.component(.hour, from: end) < 12 ? end
                    : calendar.date(byAdding: .day, value: 1, to: end) ?? end
                // Apps the owner excluded from suggestions stay out; saved durations are the starting minutes.
                guard var proposal = ScreenTimeRoutineProposal.make(from: learning, nextMorning: nextMorning,
                                                                    baseRoutineID: self.routine?.id, calendar: calendar, now: end),
                      proposal.applyPreferences(self.routinePreferences) else {
                    self.screenTimeMessage = learning.earliestData == nil
                        ? String(localized: "Screen Time has no app minutes on this iPhone yet. Try again tomorrow morning.")
                        : String(localized: "Screen Time returned app use, but no complete morning could be identified yet.")
                    return
                }
                if self.savePendingScreenTimeProposal(proposal) {
                    self.screenTimeMessage = nil
                } else if self.notice == nil {
                    self.screenTimeMessage = String(localized: "The suggestion couldn't be saved. Your routine is unchanged.")
                }
            } catch {
                guard self.dataGeneration == generation, !self.privacyBlocksWork else { return }
                self.refreshScreenTimeAccess()
                self.screenTimeMessage = self.screenTimeAccess == .approved
                    ? String(localized: "Screen Time didn't answer this time. Try again in a moment.")
                    : self.screenTimeAccessExplanation
            }
        }
    }

    var screenTimeAccessExplanation: String {
        switch screenTimeAccess {
        case .approved: String(localized: "Screen Time is connected.")
        case .unavailable: String(localized: "Learning from Screen Time needs iOS 26.4 or later.")
        case .approvedWithoutData: String(localized: "Screen Time was approved without app-use data. Check this build’s capabilities and your device’s eligibility.")
        case .denied: String(localized: "Screen Time access wasn't given. You can allow it in Settings → Screen Time, then try again.")
        case .notAsked: String(localized: "Connect Screen Time to read the app-use data available on this iPhone.")
        }
    }
}
