import Foundation

// Worktrees an agent made for a session of its own (FEATURES.md → New agent sessions): Calm
// removes one when its session closes, if the agent is gone and the worktree is still empty,
// since closing a session ends the agent before it can clean up after itself.

public extension ClaudeCodeAdapter {
    /// `claude -w` locks its worktree with `claude session <name> (pid <pid> start <date>)` (seen on
    /// 2.1.292). Claude removes an empty one itself when it exits normally; a session closed in
    /// Calm ends it first, which leaves the worktree behind, locked by a process that's gone.
    func worktreeOwner(lockReason: String) -> Int32? {
        guard lockReason.hasPrefix("claude session "), let open = lockReason.range(of: "(pid ") else { return nil }
        let digits = lockReason[open.upperBound...].prefix { $0.isNumber }
        return Int32(digits)
    }
}

public extension Agents {
    /// The agent process holding a worktree locked with `lockReason`, if an agent made it.
    static func worktreeOwner(lockReason: String) -> Int32? {
        adapters.lazy.compactMap { $0.worktreeOwner(lockReason: lockReason) }.first
    }
}
