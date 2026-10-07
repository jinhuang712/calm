import CalmModel
import Testing

/// Reading `git worktree list --porcelain` and deciding a worktree is empty, for the cleanup of
/// the worktrees agents make (FEATURES.md → New agent sessions).
struct GitWorktreeTests {
    /// The shape of the author's real listing (2026-10-07): the main checkout, a worktree of this
    /// tooling, and one `claude -w` made and locked.
    private let listing = """
    worktree /Users/me/dev/apps/calm
    HEAD 23267fa8ae439a13b48b00b74beaa27f14bb8b96
    branch refs/heads/main

    worktree /Users/me/dev/apps/calm/.claude/worktrees/ci-green
    HEAD e8a373f340c613fdfbcb64bb44b72e7644709b10
    branch refs/heads/wt-ci-green

    worktree /Users/me/dev/apps/calm/.claude/worktrees/hashed-sparking-starfish
    HEAD 17b90736b1ab33ad0ce0a3c4f0a63d8c25b7d1e2
    branch refs/heads/worktree-hashed-sparking-starfish
    locked claude session hashed-sparking-starfish (pid 27681 start Wed Oct  7 08:29:37 2026)

    worktree /tmp/detached
    HEAD 17b90736b1ab33ad0ce0a3c4f0a63d8c25b7d1e2
    detached
    locked

    """

    @Test func `the listing gives each worktree's path, branch and lock`() {
        let worktrees = GitWorktree.parse(listing)
        #expect(worktrees.count == 4)
        #expect(worktrees[0] == GitWorktree(path: "/Users/me/dev/apps/calm", branch: "main"))
        #expect(worktrees[1].lockReason == nil)
        #expect(worktrees[2].branch == "worktree-hashed-sparking-starfish")
        #expect(worktrees[2].lockReason == "claude session hashed-sparking-starfish (pid 27681 start Wed Oct  7 08:29:37 2026)")
        #expect(worktrees[3] == GitWorktree(path: "/tmp/detached", branch: nil, lockReason: ""))
    }

    @Test func `empty means no change, no untracked file, and its commits on another branch`() {
        let main = ["refs/heads/main", "refs/heads/worktree-x"]
        #expect(GitWorktree.isEmpty(status: "", refsContainingHead: main, branch: "worktree-x"))
        #expect(GitWorktree.isEmpty(
            status: "\n",
            refsContainingHead: ["refs/remotes/origin/main", "refs/heads/worktree-x"],
            branch: "worktree-x",
        ))
        // A change, or a file git doesn't track yet.
        #expect(!GitWorktree.isEmpty(status: " M Sources/App.swift\n", refsContainingHead: main, branch: "worktree-x"))
        #expect(!GitWorktree.isEmpty(status: "?? notes.md\n", refsContainingHead: main, branch: "worktree-x"))
        // A commit only its own branch has.
        #expect(!GitWorktree.isEmpty(status: "", refsContainingHead: ["refs/heads/worktree-x", ""], branch: "worktree-x"))
        // A detached HEAD that some branch holds.
        #expect(GitWorktree.isEmpty(status: "", refsContainingHead: ["refs/heads/main"], branch: nil))
    }
}
