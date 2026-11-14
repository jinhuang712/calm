import Foundation

/// How Calm asks an agent to quit before starting it again. Each was checked against the real
/// agent in a pty (2026-10-07): it exits and turns off every terminal mode it turned on.
public enum AgentQuit: Sendable, Equatable {
    /// A signal the agent handles by tidying up and exiting.
    case signal(Int32)
    /// ⌃C as the keyboard sends it, and again every half second while the agent hasn't quit, up to
    /// `times`: for an agent that tidies up on its own quit key but dies untidily on any signal.
    case controlC(times: Int)
}

public extension AgentQuit {
    /// How long an agent gets to quit. The agents take under a second (Claude Code 0.3 s, Codex
    /// 0.5 s a press): one still there after this isn't quitting, so it is left be.
    static let patience = Duration.seconds(5)
    /// How often the agent's process is looked at while waiting for it to go.
    static let lookEvery = Duration.milliseconds(50)
    /// How long after a ⌃C the next one follows, while the agent is still there: a draft takes a
    /// press of its own.
    static let pressEvery = Duration.milliseconds(500)

    /// Asks the agent running as `processID` to quit, and waits until its process is gone or
    /// `patience` has run out. True when it went.
    ///
    /// Everything that touches the world comes in as a closure and the clock, so a test runs the
    /// whole wait on a clock that moves only when something sleeps.
    @MainActor
    func perform<C: Clock>(
        processID: Int32,
        isRunning: (Int32) -> Bool,
        signal: (Int32, Int32) -> Void,
        pressControlC: () -> Void,
        clock: C,
    ) async -> Bool where C.Duration == Duration {
        var presses = 0
        switch self {
        case let .signal(number):
            signal(processID, number)
        case .controlC:
            pressControlC()
            presses = 1
        }
        let started = clock.now
        var lastPress = started
        while isRunning(processID), clock.now < started.advanced(by: Self.patience) {
            try? await clock.sleep(for: Self.lookEvery)
            // Again while it hasn't quit: a draft takes a press of its own.
            if case let .controlC(times) = self, presses < times, lastPress.duration(to: clock.now) >= Self.pressEvery,
               isRunning(processID) {
                pressControlC()
                presses += 1
                lastPress = clock.now
            }
        }
        return !isRunning(processID)
    }
}
