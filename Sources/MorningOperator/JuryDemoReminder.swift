#if MORE_JURY_DEMO
import Foundation
import MorningApple
import MorningCore

/// A durable pending reservation prevents an interrupted native save from being
/// repeated. The receipt and reviewed reminder fields permit exact re-reading;
/// microphone audio is never stored.
@MainActor
enum JuryDemoReminder {
    private struct Entry: Codable, Sendable {
        let requestID: String
        let status: String
        let receiptID: String?
        var generation: UUID? = nil
        var title: String? = nil
        var dueDate: Date? = nil
    }

    /// Caller closes the durable privacy gate before removing this owned journal.
    static func forget(directory: URL) throws {
        let url = directory.appendingPathComponent("jury-demo-reminders")
        guard try attributesIfPresent(url) != nil else { return }
        try FileManager.default.removeItem(at: url)
    }

    static func perform(_ action: JuryDemoResponse.Action, service: ReminderService,
                        directory: URL, stillAuthorized: () -> Bool) async -> (status: String, receiptID: String?) {
        guard let requestID = action.requestID, UUID(uuidString: requestID) != nil,
              let rawTitle = action.title, rawTitle.count <= 120,
              action.minutesBefore == 20, action.meetingHour == 15, action.meetingMinute == 0 else {
            return ("unavailable", nil)
        }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, stillAuthorized(), !Task.isCancelled else { return ("unavailable", nil) }
        let control = LocalDataControl(directory: directory)
        let generation: UUID?
        do { generation = try control.withReadyAccess { $0.generation } }
        catch { return ("unavailable", nil) }
        let journalDirectory = directory.appendingPathComponent("jury-demo-reminders")
        let file = AtomicJSONFile<Entry>(url: journalDirectory.appendingPathComponent("\(requestID).json"), maximumBytes: 16_384)
        func access<T>(_ body: () throws -> T) throws -> T {
            try control.withReadyAccess { state in
                guard state.generation == generation, stillAuthorized(), !Task.isCancelled else {
                    throw LocalDataControlError.staleGeneration
                }
                if let attributes = try attributesIfPresent(journalDirectory),
                   attributes[.type] as? FileAttributeType != .typeDirectory {
                    throw LocalDataControlError.unsafePath
                }
                return try body()
            }
        }
        let previous: Entry?
        do { previous = try access { try load(file) } }
        catch { return ("uncertain", nil) }
        if let previous {
            guard previous.requestID == requestID, previous.generation == generation,
                  ["pending", "confirmed"].contains(previous.status), previous.title == title,
                  let receiptID = previous.receiptID, !receiptID.isEmpty, receiptID.count <= 1_024,
                  let due = previous.dueDate, due.timeIntervalSinceReferenceDate.isFinite,
                  await verified(receiptID: receiptID, title: title, due: due, service: service) else {
                return ("uncertain", previous.receiptID)
            }
            do {
                try access { try file.save(Entry(requestID: requestID, status: "confirmed", receiptID: receiptID,
                    generation: generation, title: title, dueDate: due)) }
                return ("confirmed", receiptID)
            } catch { return ("uncertain", receiptID) }
        }
        guard stillAuthorized(), service.hasReminderAccess,
              let meeting = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: Date()),
              let due = Calendar.current.date(byAdding: .minute, value: -20, to: meeting), due > Date() else {
            return ("unavailable", nil)
        }
        var createdReceiptID: String?
        do {
            try access {
                guard try load(file) == nil else { throw LocalDataControlError.staleGeneration }
                try file.save(Entry(requestID: requestID, status: "pending", receiptID: nil,
                    generation: generation, title: title, dueDate: due))
                let receipt = try service.createReminder(from: ReminderDraft(title: title,
                    notes: String(localized: "Product meeting — MORE morning routine.", bundle: AppLanguage.bundle(), locale: AppLanguage.locale), dueDate: due, notifyAtDueTime: true))
                createdReceiptID = receipt.id
                try file.save(Entry(requestID: requestID, status: "pending", receiptID: receipt.id,
                    generation: generation, title: title, dueDate: due))
            }
            guard let receiptID = createdReceiptID,
                  await verified(receiptID: receiptID, title: title, due: due, service: service) else {
                return ("uncertain", createdReceiptID)
            }
            try access { try file.save(Entry(requestID: requestID, status: "confirmed", receiptID: receiptID,
                generation: generation, title: title, dueDate: due)) }
            return ("confirmed", receiptID)
        } catch {
            // EventKit may have saved before returning an error. Keep the pending
            // record and require inspection rather than creating a second item.
            return ("uncertain", createdReceiptID)
        }
    }

    private static func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do { return try FileManager.default.attributesOfItem(atPath: url.path) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile { return nil }
    }

    private static func load(_ file: AtomicJSONFile<Entry>) throws -> Entry? {
        guard let attributes = try attributesIfPresent(file.url) else { return nil }
        guard attributes[.type] as? FileAttributeType == .typeRegular else { throw LocalDataControlError.unsafePath }
        return try file.load()
    }

    private static func verified(receiptID: String, title: String, due: Date, service: ReminderService) async -> Bool {
        guard let items = try? await service.fetchUpcomingReminders(from: due.addingTimeInterval(-60),
            through: due.addingTimeInterval(60), limit: 100) else { return false }
        return items.contains { $0.id == receiptID && $0.title == title &&
            abs(($0.dueDate ?? .distantPast).timeIntervalSince(due)) < 1 }
    }
}
#endif
