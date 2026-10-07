import Foundation

/// One entry of `git worktree list --porcelain`: what Calm needs to clean up a worktree an agent
/// made for a session and left empty (FEATURES.md → New agent sessions).
public struct GitWorktree: Equatable, Sendable {
    public var path: String
    /// The branch's short name; nil for a detached HEAD.
    public var branch: String?
    /// Why it's locked: what the locker wrote, empty for a lock without a reason; nil when unlocked.
    public var lockReason: String?

    public init(path: String, branch: String? = nil, lockReason: String? = nil) {
        self.path = path
        self.branch = branch
        self.lockReason = lockReason
    }

    /// Reads the porcelain listing: blocks separated by blank lines, a `worktree <path>` line first,
    /// then `branch refs/heads/<name>` and `locked [<reason>]` among others.
    public static func parse(_ porcelain: String) -> [GitWorktree] {
        var entries: [GitWorktree] = []
        var current: GitWorktree?
        for line in porcelain.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("worktree ") {
                current.map { entries.append($0) }
                current = GitWorktree(path: String(line.dropFirst("worktree ".count)))
            } else if line.hasPrefix("branch ") {
                let ref = String(line.dropFirst("branch ".count))
                current?.branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
            } else if line == "locked" {
                current?.lockReason = ""
            } else if line.hasPrefix("locked ") {
                current?.lockReason = String(line.dropFirst("locked ".count))
            }
        }
        current.map { entries.append($0) }
        return entries
    }

    /// Nothing would be lost by removing it: `status` (`git status --porcelain --untracked-files=all`)
    /// is empty, so no change and no untracked file; and a ref other than the worktree's own branch
    /// holds its HEAD (`git branch -a --contains HEAD --format=%(refname)`), so every commit on the
    /// branch is on another one too. Ignored files don't count, as for Claude Code's own cleanup.
    public static func isEmpty(status: String, refsContainingHead: [String], branch: String?) -> Bool {
        guard status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let own = branch.map { "refs/heads/\($0)" }
        return refsContainingHead.contains { ref in
            let ref = ref.trimmingCharacters(in: .whitespaces)
            return !ref.isEmpty && ref != own
        }
    }
}
