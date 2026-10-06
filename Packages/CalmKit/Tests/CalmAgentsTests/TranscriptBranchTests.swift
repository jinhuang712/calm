import CalmAgents
import Foundation
import Testing

/// `calm show`'s branch: where a conversation's work lives, by the transcript's own account.
struct TranscriptBranchTests {
    private func fixture(_ name: String, _ folder: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/\(folder)"))
    }

    /// Claude Code stamps every record with its branch; a session that moved into a worktree
    /// ends on the worktree's.
    @Test func `claude code's newest record says the branch`() throws {
        #expect(try ClaudeCodeAdapter().branch(of: fixture("transcript", "claude-code")) == "main")
        #expect(try ClaudeCodeAdapter().branch(of: fixture("transcript-worktree", "claude-code")) == "wt-dark-mode")
    }

    /// Codex's session_meta holds the repository's state at the start (keys as in 0.159's rollouts).
    @Test func `codex's session header says the branch, when it started in a repository`() throws {
        #expect(try CodexAdapter().branch(of: fixture("rollout-git", "codex")) == "fix-auth-race")
        #expect(try CodexAdapter().branch(of: fixture("rollout", "codex")) == nil)
    }

    @Test func `agents not checked, and files that aren't there, say nothing`() {
        #expect(PiAdapter().branch(of: URL(filePath: "/x/session.jsonl")) == nil)
        #expect(ClaudeCodeAdapter().branch(of: URL(filePath: "/nonexistent/t.jsonl")) == nil)
    }
}
