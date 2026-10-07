import CalmAgents
import Testing

/// Which worktrees an agent made for itself, by the lock it put on them.
struct AgentWorktreeTests {
    @Test func `the lock Claude Code puts on its worktree names the process that holds it`() {
        // As `claude -w` 2.1.292 writes it.
        let reason = "claude session hashed-sparking-starfish (pid 27681 start Wed Oct  7 08:29:37 2026)"
        #expect(Agents.worktreeOwner(lockReason: reason) == 27681)
    }

    @Test func `any other lock, or none, isn't an agent's`() {
        #expect(Agents.worktreeOwner(lockReason: "") == nil)
        #expect(Agents.worktreeOwner(lockReason: "on a removable drive") == nil)
        #expect(Agents.worktreeOwner(lockReason: "claude session x") == nil)
        #expect(Agents.worktreeOwner(lockReason: "my claude session (pid 12)") == nil)
    }
}
