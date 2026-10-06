import AppKit
import CalmAgents
import CalmModel

/// ⌘N and ⌘⇧N start an agent (FEATURES.md → New agent sessions): the one chosen in Settings →
/// Agents, with its options, typed into a new session's shell as resume and fork are, so the
/// shell is still there when the agent exits. ⌘T stays a plain shell.
extension MainWindowController {
    /// The agents installed now (their config folder is there). Read each time: four lookups, and
    /// an agent installed while Calm runs shows up at once.
    static var installedAgents: [AgentKind] {
        Agents.installed(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// The agent ⌘N starts, or nil when there is none to start (⌘N then opens a plain shell).
    static func newSessionAgent(settings: CalmSettings) -> AgentKind? {
        Agents.newSessionAgent(settings: settings, installed: installedAgents)
    }

    var newSessionAgent: AgentKind? {
        Self.newSessionAgent(settings: manager.settings)
    }

    /// ⌘N's agent and the others, for the footer, the first-launch rows and the start line.
    var startAgents: StartAgents {
        let installed = Self.installedAgents
        let chosen = Agents.newSessionAgent(settings: manager.settings, installed: installed)
        return StartAgents(chosen: chosen, others: installed.filter { $0 != chosen })
    }

    /// ⌘N: a new session where ⌘T would open one, running `kind`, the chosen agent unless given
    /// (the ⌄ menu and ⌘P start the others).
    func newAgentSession(_ kind: AgentKind? = nil) {
        let session = newSession()
        if let agent = kind ?? newSessionAgent {
            startAgent(agent, in: session)
        }
    }

    /// Types the agent's command into `session`'s new shell. A worktree option is only added in a
    /// git repository: the welcome page's ⌘N starts in the home folder, ⌘⇧N in a scratch folder.
    func startAgent(_ kind: AgentKind, in session: Session) {
        guard let adapter = Agents.adapter(for: kind) else { return }
        let inGit = GitRoot.find(session.workingDirectory) != nil
        runAgentCommand(adapter.launchCommand(settings: manager.settings, inGitRepository: inGit), in: manager.panes[session.id])
    }
}
