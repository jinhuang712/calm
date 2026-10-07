import CalmAgents
import CalmModel
import Darwin
import Foundation

/// Removes the git worktree an agent made for a session (`claude -w`) once the session closes, if
/// nothing in it would be lost (FEATURES.md → New agent sessions; DESIGNS.md → Session actions).
///
/// Claude Code removes an empty worktree of its own when it exits, but closing a session in Calm
/// ends the agent first, so it never gets to: ⌘N with New worktree on left four empty ones behind
/// in two minutes (2026-10-07), each still locked by a process that was gone.
///
/// Only a worktree its agent locked as its own (`AgentAdapter.worktreeOwner`), whose agent has
/// exited, that no open session is in, with no change, no untracked file and no commit another
/// branch doesn't have. git's own safe commands do the removing (`worktree remove` without force,
/// `branch -d`), so git refuses as well if anything is left.
enum WorktreeCleanup {
    enum Outcome: Equatable {
        case removed
        /// Not a worktree an agent made for itself: never touched.
        case notAnAgents
        /// Its agent was still running when the wait ran out.
        case agentRunning
        case notEmpty
        case failed(String)
    }

    /// After `session` closed: the worktree its agent was in, looked at off the main thread.
    /// `open` are the sessions still open; one of them in the worktree keeps it.
    static func afterClose(_ session: Session, open: [Session]) {
        let directory = session.activeDirectory
        guard GitRoot.worktreeName(directory) != nil, let root = GitRoot.find(directory) else { return }
        let inUse = open.contains { other in
            other.id != session.id && [other.activeDirectory, other.workingDirectory].contains { isInside($0, root) }
        }
        let id = Trace.id(session.id)
        guard !inUse else {
            Trace.note("worktree \(id): kept, another session is in it")
            return
        }
        DispatchQueue.global(qos: .utility).async {
            let outcome = removeIfEmpty(root)
            if outcome != .notAnAgents {
                Trace.note("worktree \(id): \(outcome)")
            }
        }
    }

    /// Removes `root` if an agent made it, that agent has exited (waiting up to `wait`, since
    /// closing the session has only just ended it), and nothing in it would be lost. Blocking.
    static func removeIfEmpty(_ root: String, wait: TimeInterval = 5) -> Outcome {
        guard let listing = GitCommand.run(["worktree", "list", "--porcelain"], in: root) else { return .failed("no listing") }
        let worktrees = GitWorktree.parse(listing)
        // The first entry is the main checkout, where the removing is done from.
        guard let main = worktrees.first?.path,
              let entry = worktrees.dropFirst().first(where: { resolved($0.path) == resolved(root) }),
              let reason = entry.lockReason, let owner = Agents.worktreeOwner(lockReason: reason)
        else { return .notAnAgents }
        let deadline = Date().addingTimeInterval(wait)
        while isRunning(owner) {
            guard Date() < deadline else { return .agentRunning }
            Thread.sleep(forTimeInterval: 0.25)
        }
        guard let status = GitCommand.run(["status", "--porcelain", "--untracked-files=all"], in: root),
              let refs = GitCommand.run(["branch", "-a", "--contains", "HEAD", "--format=%(refname)"], in: root),
              GitWorktree.isEmpty(status: status, refsContainingHead: refs.components(separatedBy: "\n"), branch: entry.branch)
        else { return .notEmpty }
        _ = GitCommand.run(["worktree", "unlock", entry.path], in: main)
        guard GitCommand.run(["worktree", "remove", entry.path], in: main) != nil else {
            return .failed("git worktree remove refused")
        }
        if let branch = entry.branch {
            // `-d`, not `-D`: git keeps a branch it doesn't consider merged.
            _ = GitCommand.run(["branch", "-d", branch], in: main)
        }
        return .removed
    }

    private static func isRunning(_ pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    private static func isInside(_ path: String, _ root: String) -> Bool {
        let path = resolved(path)
        let root = resolved(root)
        return path == root || path.hasPrefix(root + "/")
    }

    /// `/var` is `/private/var`, and git prints the resolved form.
    private static func resolved(_ path: String) -> String {
        (path as NSString).resolvingSymlinksInPath
    }
}
