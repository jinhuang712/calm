import Foundation

/// What telling an agent that a folder is trusted did (`AgentAdapter.trust`).
public enum FolderTrust: Sendable, Equatable {
    /// The agent already trusted the folder; nothing was written.
    case alreadyTrusted
    /// Calm added the folder to the ones the agent trusts.
    case added
    /// Nothing was written, and why (the agent isn't set up, its config doesn't read, it was
    /// busy writing it): the agent asks as before, and the next try may do better.
    case unchanged(String)
}
