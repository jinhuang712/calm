@testable import CalmAgents
import Foundation
import Testing

/// Time that moves only when something sleeps, so a wait of five seconds takes none.
private final class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private(set) var now = Instant(offset: .zero)
    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        if deadline > now {
            now = deadline
        }
    }
}

/// An agent that quits when it is told to enough times, or never.
@MainActor
private final class StandInAgent {
    var running = true
    var signals: [Int32] = []
    var presses = 0
    /// Quits on the signal, or on this many ⌃C. Nil: never.
    var quitsOnSignal = false
    var quitsAfterPresses: Int?

    func signal(_: Int32, number: Int32) {
        signals.append(number)
        if quitsOnSignal {
            running = false
        }
    }

    func pressControlC() {
        presses += 1
        if let quitsAfterPresses, presses >= quitsAfterPresses {
            running = false
        }
    }
}

/// Asking an agent to quit and waiting for it to go (specs/FEATURES.md → F12, DESIGNS.md → An agent is quit in the way it quits cleanly).
@MainActor
struct AgentQuitTests {
    private let clock = TestClock()
    private let agent = StandInAgent()

    private func quit(_ how: AgentQuit) async -> Bool {
        await how.perform(
            processID: 42,
            isRunning: { _ in agent.running },
            signal: { agent.signal($0, number: $1) },
            pressControlC: { agent.pressControlC() },
            clock: clock,
        )
    }

    @Test func `a signal is sent once, and an agent that quits at once is gone`() async {
        agent.quitsOnSignal = true
        let gone = await quit(.signal(15))
        #expect(gone)
        #expect(agent.signals == [15])
        #expect(agent.presses == 0)
        #expect(clock.now.offset == .zero)
    }

    @Test func `an agent that ignores the signal is left after the patience runs out`() async {
        let gone = await quit(.signal(15))
        #expect(!gone)
        #expect(agent.signals == [15])
        #expect(clock.now.offset >= AgentQuit.patience)
    }

    @Test func `⌃C is pressed again after half a second while the agent is still there`() async {
        agent.quitsAfterPresses = 2
        let gone = await quit(.controlC(times: 4))
        #expect(gone)
        #expect(agent.presses == 2)
        #expect(agent.signals.isEmpty)
        #expect(clock.now.offset >= AgentQuit.pressEvery)
        #expect(clock.now.offset < AgentQuit.pressEvery + AgentQuit.lookEvery * 2)
    }

    @Test func `⌃C stops at the number of presses the agent allows`() async {
        let gone = await quit(.controlC(times: 4))
        #expect(!gone)
        #expect(agent.presses == 4)
        #expect(clock.now.offset >= AgentQuit.patience)
    }

    @Test func `an agent that quits on the first ⌃C is not pressed again`() async {
        agent.quitsAfterPresses = 1
        let gone = await quit(.controlC(times: 4))
        #expect(gone)
        #expect(agent.presses == 1)
    }
}
