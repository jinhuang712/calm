import CalmAgents
import CalmModel
import Foundation

/// The sidebar's session actions, handled by the window controller.
struct SidebarActions {
    let rename: (Session.ID, String?) -> Void
    let resume: (Session.ID) -> Void
    let fork: (Session.ID, MainWindowController.ForkDestination) -> Void
    let newScratchSession: () -> Void
    /// ⌘N: a session running the chosen agent (nil), or another one from the ⌄ menu.
    let newAgentSession: (AgentKind?) -> Void
    /// Settings → Agents, where ⌘N's agent is chosen.
    let chooseNewSessionAgent: () -> Void
    /// Shows or hides the sidebar's footer (saved in config.toml, applied in every window).
    let showFooter: (Bool) -> Void
    let search: () -> Void
    /// Shows or hides the files column (⌘\): the footer's Files row and the title strip's readout.
    let toggleFiles: () -> Void
    let newSessionIn: (Project) -> Void
    let addProjects: ([URL]) -> Void
    let makeProject: (Project.ID) -> Void
    let removeProject: (Project.ID) -> Void
    let move: (Session.ID, Project.ID) -> Void
    let followFolder: (Session.ID) -> Void
    let keepScratch: (Session.ID) -> Void
    let copy: (Session.ID, SessionCopy) -> Void
    let openFolder: (Session.ID) -> Void
    /// Takes a pane out of its split: the session stays, on its own.
    let takeOut: (Session.ID) -> Void
    /// Restarts the agent on its conversation (now, or after its turn), and takes back a restart
    /// still waiting (FEATURES.md → F12).
    var restart: (Session.ID) -> Void = { _ in }
    var cancelRestart: (Session.ID) -> Void = { _ in }
}
