import Foundation

/// The person's wake-up alarm choice: on or off, and a time of day.
public struct MorningAlarmSetting: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    public var hour: Int { didSet { hour = min(max(0, hour), 23) } }
    public var minute: Int { didSet { minute = min(max(0, minute), 59) } }
    public init(isEnabled: Bool = false, hour: Int = 7, minute: Int = 0) {
        self.isEnabled = isEnabled
        self.hour = min(max(0, hour), 23); self.minute = min(max(0, minute), 59)
    }
}

/// The alarm MORE last scheduled with the system, as MORE recorded it.
public struct ScheduledMorningAlarm: Codable, Hashable, Sendable {
    public let id: UUID
    public let hour: Int
    public let minute: Int
    public init(id: UUID, hour: Int, minute: Int) { self.id = id; self.hour = hour; self.minute = minute }
}

/// What to do with the system's alarms so that exactly the wanted one exists.
public struct MorningAlarmChange: Equatable, Sendable {
    /// Alarms to cancel first: every alarm of this app that is not the one being kept.
    public var cancel: Set<UUID>
    /// A new daily alarm to schedule after the cancellations, or nil.
    public var schedule: (hour: Int, minute: Int)?
    public var needsAuthorization: Bool

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cancel == rhs.cancel && lhs.needsAuthorization == rhs.needsAuthorization &&
            lhs.schedule?.hour == rhs.schedule?.hour && lhs.schedule?.minute == rhs.schedule?.minute
    }
    public var isNothing: Bool { cancel.isEmpty && schedule == nil && !needsAuthorization }
}

public enum MorningAlarmPlan {
    /// Every alarm this app holds is MORE's morning alarm, so anything other than the
    /// kept one is a leftover (a crash between cancel and record, a reinstall) and is
    /// cancelled: two alarms would ring twice. A recorded alarm the system no longer
    /// holds is scheduled again, so a lost alarm does not silently stay lost.
    public static func change(setting: MorningAlarmSetting, recorded: ScheduledMorningAlarm?,
                              systemAlarmIDs: Set<UUID>, authorized: Bool) -> MorningAlarmChange {
        guard setting.isEnabled else {
            return MorningAlarmChange(cancel: systemAlarmIDs, schedule: nil, needsAuthorization: false)
        }
        guard authorized else {
            return MorningAlarmChange(cancel: [], schedule: nil, needsAuthorization: true)
        }
        if let recorded, recorded.hour == setting.hour, recorded.minute == setting.minute,
           systemAlarmIDs.contains(recorded.id) {
            return MorningAlarmChange(cancel: systemAlarmIDs.subtracting([recorded.id]), schedule: nil, needsAuthorization: false)
        }
        return MorningAlarmChange(cancel: systemAlarmIDs, schedule: (setting.hour, setting.minute), needsAuthorization: false)
    }

    /// One entry identity per alarm per local day. Stopping the alarm and tapping its
    /// second button on the same morning are one morning entry, never two starts.
    public static func entryID(alarmID: UUID, at date: Date, calendar: Calendar = .current) -> UUID {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let stamp = UInt32(clamping: (day.year ?? 0) * 10_000 + (day.month ?? 0) * 100 + (day.day ?? 0))
        var bytes = alarmID.uuid
        withUnsafeMutableBytes(of: &bytes) { raw in
            raw[0] ^= UInt8(truncatingIfNeeded: stamp >> 24); raw[1] ^= UInt8(truncatingIfNeeded: stamp >> 16)
            raw[2] ^= UInt8(truncatingIfNeeded: stamp >> 8); raw[3] ^= UInt8(truncatingIfNeeded: stamp)
        }
        return UUID(uuid: bytes)
    }
}
