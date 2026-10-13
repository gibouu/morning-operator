import Foundation
import Testing
@testable import MorningApple

@Suite("City suggestion fragments — fake source only")
@MainActor
struct CitySuggestionLookupTests {
    @Test func failedFragmentIsAskedAgainInsteadOfReusingOlderResults() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let first = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa"] }
        lookup.succeeded()
        try await first.value
        try await lookup.wait(for: "Pa")
        #expect(source.started == ["Pa"], "A completed fragment is reused.")

        let failing = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["Pa", "To"] }
        lookup.failed(URLError(.notConnectedToInternet))
        await #expect(throws: URLError.self) { try await failing.value }
        #expect(source.discards == 1, "A failed source is discarded with its older results.")

        let retry = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["Pa", "To", "To"] }
        lookup.succeeded()
        try await retry.value
    }

    @Test func unansweredFragmentExpiresWithItsCancelledWait() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        // The caller's deadline cancels a wait the source never answered.
        let stalled = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["To"] }
        stalled.cancel()
        await #expect(throws: CancellationError.self) { try await stalled.value }
        #expect(source.discards == 1, "A request nobody waits for is expired, not kept.")

        var returned = false
        let again = Task { try await lookup.wait(for: "To"); returned = true }
        await until { source.started == ["To", "To"] }
        #expect(!returned, "The fragment is sent again and is not complete until the source answers.")
        lookup.succeeded()
        try await again.value
        #expect(returned)
    }

    @Test func newerFragmentSupersedesTheWaitingOneOnTheSameSource() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let older = Task { try await lookup.wait(for: "To") }
        await until { source.started == ["To"] }
        let newer = Task { try await lookup.wait(for: "Tok") }
        await until { source.started == ["To", "Tok"] }
        await #expect(throws: CancellationError.self) { try await older.value }
        #expect(source.discards == 0)
        lookup.succeeded()
        try await newer.value
        try await lookup.wait(for: "Tok")
        #expect(source.started == ["To", "Tok"])
    }

    @Test func resetForgetsTheFragmentAndEndsAPendingWait() async throws {
        let source = SuggestionSourceFixture()
        let lookup = source.lookup()
        let first = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa"] }
        lookup.succeeded()
        try await first.value

        let pending = Task { try await lookup.wait(for: "Par") }
        await until { source.started == ["Pa", "Par"] }
        lookup.reset()
        await #expect(throws: CancellationError.self) { try await pending.value }
        #expect(source.discards == 1)

        let afterReset = Task { try await lookup.wait(for: "Pa") }
        await until { source.started == ["Pa", "Par", "Pa"] }
        lookup.succeeded()
        try await afterReset.value
    }

    /// Waits for main-actor work that is already scheduled.
    private func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        // Bounded by time, not by a yield count: on a busy machine the awaited work can
        // need more turns than any fixed number, and a count then fails for no reason.
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition(), ContinuousClock.now < deadline {
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(1))
        }
        #expect(condition(), sourceLocation: sourceLocation)
    }
}

@MainActor
private final class SuggestionSourceFixture {
    private(set) var started: [String] = []
    private(set) var discards = 0
    func lookup() -> CitySuggestionLookup {
        CitySuggestionLookup(start: { [self] in started.append($0) }, discard: { [self] in discards += 1 })
    }
}
