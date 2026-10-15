import Foundation
import MorningCore
import MorningApple
import Testing

@Suite("Step timer notification serialization")
struct StepTimerAlertQueueTests {
    @MainActor @Test("A suspended stale add finishes cleanup before a new timer can install its alert")
    func staleAddCannotRemoveNewAlert() async {
        let queue = StepTimerAlertQueue()
        var events: [String] = []
        var installed: String?
        var release: CheckedContinuation<Void, Never>?
        let first = queue.enqueue {
            events.append("old-start")
            await withCheckedContinuation { release = $0 }
            installed = "old"
            events.append("old-add")
            installed = nil
            events.append("old-cleanup")
        }
        let second = queue.enqueue {
            installed = "new"
            events.append("new-add")
        }
        while release == nil { await Task.yield() }
        #expect(events == ["old-start"])
        release?.resume()
        await first.value; await second.value
        #expect(events == ["old-start", "old-add", "old-cleanup", "new-add"])
        #expect(installed == "new")
    }
}
