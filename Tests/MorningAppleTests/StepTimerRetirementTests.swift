import Foundation
import MorningCore
import MorningApple
import Testing

@Suite("Timer retirement fails closed")
struct StepTimerRetirementTests {
    @MainActor @Test("Retirement replaces legacy storage with a durable null and rejects bound or voice mutation")
    func retiredTimerCannotBeExtended() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let timer = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: Date())
        let url = directory.appendingPathComponent("step-timer.json")
        try AtomicJSONFile<StepTimer>(url: url).save(timer)
        #expect(StepTimerFile.load(directory: directory) == timer)
        #expect(StepTimerFile.clear(directory: directory))
        #expect(try AtomicJSONFile<StepTimer?>(url: url).load() == nil)
        #expect(StepTimerFile.load(directory: directory) == nil)
        for bound in [true, false] {
            let result = StepTimerFile.update(sessionID: bound ? timer.sessionID : nil,
                stepID: bound ? timer.stepID : nil, directory: directory) {
                $0.extend(expectedEnd: bound ? timer.endsAt : nil, at: Date())
            }
            #expect(result == nil)
        }
    }

    @MainActor @Test("A failed retirement stays blocked after privacy reopens until a fresh save succeeds")
    func failedRetirementBlocksProcess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let timer = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 3, at: Date())
        try StepTimerFile.save(timer, directory: directory)
        let control = LocalDataControl(directory: directory)
        let pending = try control.beginForget()
        #expect(!StepTimerFile.clear(directory: directory))
        try control.finishForget(expectedGeneration: #require(pending.generation))
        #expect(StepTimerFile.load(directory: directory) == nil)
        #expect(StepTimerFile.update(sessionID: nil, stepID: nil, directory: directory) {
            $0.extend(expectedEnd: nil, at: Date())
        } == nil)
        let fresh = StepTimer(sessionID: UUID(), stepID: UUID(), minutes: 4, at: Date())
        try StepTimerFile.save(fresh, directory: directory)
        #expect(StepTimerFile.load(directory: directory) == fresh)
    }
}
