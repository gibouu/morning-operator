import Foundation
import MorningCore
#if os(iOS)
import DeviceActivity
import FamilyControls
// `activitySegments` and the rest of the data reading live in the SwiftUI cross-import overlay.
import SwiftUI
#endif

/// Screen Time hours come from the system; unavailable access stays explicit.
@MainActor
protocol ScreenTimeSource {
    var access: ScreenTimeAccess { get }
    /// Shows Apple's one-time Screen Time sheet (Continue + Face ID).
    func requestAccess() async throws
    /// Hourly usage from `start` to `end`. Nothing is written anywhere.
    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour]
}

enum ScreenTimeAccess: Equatable {
    case notAsked, denied, approvedWithoutData, approved, unavailable
}

enum ScreenTimeReadError: Error {
    case unavailable, timedOut
}

@MainActor
enum ScreenTimeSources {
    static func make() -> any ScreenTimeSource {
        #if os(iOS)
        return SystemScreenTimeSource()
        #else
        return UnavailableScreenTimeSource()
        #endif
    }
}

struct UnavailableScreenTimeSource: ScreenTimeSource {
    var access: ScreenTimeAccess { .unavailable }
    func requestAccess() async throws { throw ScreenTimeReadError.unavailable }
    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour] { throw ScreenTimeReadError.unavailable }
}

#if os(iOS)
/// Screen Time with the App and Website Usage data access (iOS 26.4 or later). On iOS 27 it
/// returns hourly segments with real bundle identifiers and seconds per app
/// (docs/SCREEN-TIME-INTEGRATION.md). Only what MORE needs is kept: identifier, seconds, pickups, category.
struct SystemScreenTimeSource: ScreenTimeSource {
    var access: ScreenTimeAccess {
        // App and Website Usage data needs iOS 26.4; asking earlier cannot give it.
        guard #available(iOS 26.4, *) else { return .unavailable }
        let status = AuthorizationCenter.shared.authorizationStatus
        if status == .approvedWithDataAccess { return .approved }
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        case .approved: return .approvedWithoutData
        default: return .notAsked
        }
    }

    func requestAccess() async throws {
        guard #available(iOS 26.4, *) else { throw ScreenTimeReadError.unavailable }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    func hours(from start: Date, to end: Date) async throws -> [ScreenTimeHour] {
        guard #available(iOS 26.4, *) else { throw ScreenTimeReadError.unavailable }
        return try await withThrowingTaskGroup(of: [ScreenTimeHour]?.self) { group in
            group.addTask { try await Self.read(from: start, to: end) }
            // The live stream may stay open for updates; the first complete result is enough.
            group.addTask { try await Task.sleep(for: .seconds(45)); return nil }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let hours = first else { throw ScreenTimeReadError.timedOut }
            return hours
        }
    }

    @available(iOS 26.4, *)
    nonisolated private static func read(from start: Date, to end: Date) async throws -> [ScreenTimeHour] {
        // No device filter: this iPhone only, never another device on the same account.
        let filter = DeviceActivityFilter(segment: .hourly(during: DateInterval(start: start, end: end)))
        var hours: [ScreenTimeHour] = []
        for try await data in DeviceActivityData.activityData(filteredBy: filter, using: .live) {
            for await segment in data.activitySegments {
                var apps: [ScreenTimeAppHour] = []
                for await category in segment.categories {
                    let categoryName = category.category.localizedDisplayName
                    for await activity in category.applications {
                        guard let id = activity.application.bundleIdentifier else { continue }
                        apps.append(ScreenTimeAppHour(bundleIdentifier: id, seconds: activity.totalActivityDuration,
                                                      pickups: activity.numberOfPickups, categoryName: categoryName))
                    }
                }
                hours.append(ScreenTimeHour(interval: segment.dateInterval, firstPickup: segment.firstPickup,
                                            longestActivity: segment.longestActivity, apps: apps))
            }
            break
        }
        return hours
    }
}
#endif
