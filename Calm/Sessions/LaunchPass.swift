import CalmAgents
import CalmModel
import Foundation

/// The check made at launch of every saved agent run: is that agent still running in its shell,
/// and what does it say about itself (DESIGNS.md → Launch)? Only process and file reads, so it
/// runs off the main thread; the window waits for it no longer than `budget`.
enum LaunchPass {
    /// A saved run to check: which session, which zmx session holds its shell, which agent.
    struct Question: Sendable {
        var id: Session.ID
        var shellName: String
        var kind: AgentKind
    }

    struct Answer: Sendable {
        var outcomes: [Session.ID: AgentAtLaunch]
        /// The shells `zmx list` named, so the first regular probe needn't ask again.
        var shells: [String: pid_t]
        /// Whether zmx answered: only then is a shell missing from `shells` known to be gone.
        var shellsListed = false

        /// The saved session's shell went (the Mac restarted, or its zmx session was ended), as
        /// opposed to the agent in it ending.
        func shellIsGone(_ name: String) -> Bool {
            shellsListed && shells[name] == nil
        }
    }

    /// How long the window waits for the pass before it opens with rows that show as loading.
    /// A `zmx list`, then a few syscalls and one small file read per session: 3 ms for one
    /// session when measured, so the budget is generous.
    static let budgetMilliseconds = 250
    static var budget: DispatchTimeInterval {
        .milliseconds(budgetMilliseconds)
    }

    /// A pass that hasn't answered by then is given up on: every saved run ends, as a launch
    /// always did, and the first regular probe finds the agents again.
    static let deadline = DispatchTimeInterval.seconds(2)

    nonisolated static func run(_ questions: [Question], home: URL) -> Answer {
        #if DEBUG
            // Self-tests: a slow pass, to see the rows load.
            if let delay = ProcessInfo.processInfo.environment["CALM_LAUNCH_PASS_DELAY_MS"].flatMap(Double.init) {
                Thread.sleep(forTimeInterval: delay / 1000)
            }
        #endif
        let listed = PersistentShell.listedShellProcesses()
        let shells = listed ?? [:]
        var outcomes: [Session.ID: AgentAtLaunch] = [:]
        for question in questions {
            let foreground = shells[question.shellName]
                .flatMap { ProcessInspector.foregroundJob(ofShell: $0) }
                .flatMap { ProcessInspector.snapshot(of: $0) }
            outcomes[question.id] = outcome(question.kind, foreground: foreground) { processID in
                Agents.liveStatusReader(for: question.kind)?.liveStatus(processID: processID, home: home)
            }
        }
        return Answer(outcomes: outcomes, shells: shells, shellsListed: listed != nil)
    }

    /// The saved run's agent is still there when the shell's foreground job is that agent.
    nonisolated static func outcome(
        _ kind: AgentKind, foreground: ProcessSnapshot?, status: (Int32) -> AgentLiveStatus?,
    ) -> AgentAtLaunch {
        guard let foreground, Agents.detect(foreground) == kind else { return .gone }
        return .running(kind: kind, processID: foreground.processID, status: status(foreground.processID))
    }
}
