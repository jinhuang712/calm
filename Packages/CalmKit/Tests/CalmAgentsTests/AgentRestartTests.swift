@testable import CalmAgents
import CalmModel
import Darwin
import Foundation
import Testing

/// Restarting an agent on its conversation: the command keeps how it was started and leaves out
/// what would start something else (FEATURES.md → F12).
struct AgentRestartTests {
    private func restart(_ arguments: [String], id: String? = "abc") -> String? {
        ClaudeCodeAdapter().restartCommand(arguments: arguments, agentSessionID: id, transcriptPath: "/x/def.jsonl")
    }

    @Test func `a restarted Claude Code keeps its options and resumes the conversation`() {
        #expect(restart(["claude", "--dangerously-skip-permissions"]) == "claude --dangerously-skip-permissions --resume 'abc'")
        #expect(restart(["claude"]) == "claude --resume 'abc'")
    }

    /// The author's own launches (`ps`, 2026-10-06): a resume by name or id gives way to the id.
    @Test func `the conversation it was resumed with gives way to the one running now`() {
        let named = ["claude", "--dangerously-skip-permissions", "--resume", "animation-performance-optimization"]
        #expect(restart(named) == "claude --dangerously-skip-permissions --resume 'abc'")
        #expect(restart(["claude", "--dangerously-skip-permissions", "-r"]) == "claude --dangerously-skip-permissions --resume 'abc'")
        #expect(restart(["claude", "--resume=old", "--verbose"]) == "claude --verbose --resume 'abc'")
        #expect(restart(["claude", "-c", "--model", "opus"]) == "claude --model opus --resume 'abc'")
        #expect(restart(["claude", "--session-id", "u-1", "--fork-session"]) == "claude --resume 'abc'")
    }

    @Test func `the prompt it was started with is never sent again`() {
        #expect(restart(["claude", "--model", "opus", "fix the login test"]) == "claude --model opus --resume 'abc'")
        #expect(restart(["claude", "fix it", "--verbose"]) == "claude --verbose --resume 'abc'")
        #expect(restart(["claude", "--verbose", "--", "-starts like an option"]) == "claude --verbose --resume 'abc'")
    }

    @Test func `a value is read the way Claude Code reads it`() {
        // Required: the next argument, whatever it looks like.
        #expect(restart(["claude", "--append-system-prompt", "-be brief"]) == "claude --append-system-prompt '-be brief' --resume 'abc'")
        // Optional: the next argument unless it is an option.
        #expect(restart(["claude", "--debug", "--verbose"]) == "claude --debug --verbose --resume 'abc'")
        #expect(restart(["claude", "--debug", "api"]) == "claude --debug api --resume 'abc'")
        // Variadic: every argument up to the next option.
        #expect(restart(["claude", "--add-dir", "/a", "/b", "--verbose"]) == "claude --add-dir /a /b --verbose --resume 'abc'")
    }

    @Test func `a worktree or tmux it was started into isn't made again`() {
        #expect(restart(["claude", "-w", "feat", "--model", "opus"]) == "claude --model opus --resume 'abc'")
        #expect(restart(["claude", "--worktree", "--tmux"]) == "claude --resume 'abc'")
    }

    @Test func `words the shell would change are quoted, and only those`() {
        #expect(restart(["claude", "--settings", #"{"a":1}"#]) == #"claude --settings '{"a":1}' --resume 'abc'"#)
        #expect(restart(["claude", "--model=claude-opus-5-5"]) == "claude --model=claude-opus-5-5 --resume 'abc'")
        #expect(restart(["claude"], id: "it's") == #"claude --resume 'it'\''s'"#)
    }

    @Test func `without an id the transcript's name is the conversation`() {
        #expect(restart(["claude"], id: nil) == "claude --resume 'def'")
    }

    @Test func `only an agent whose way to quit was checked is restarted`() {
        #expect(ClaudeCodeAdapter().quitSignal == SIGTERM)
        for adapter in [CodexAdapter(), OpenCodeAdapter(), PiAdapter()] as [any AgentAdapter] {
            #expect(adapter.quitSignal == nil)
            #expect(adapter.restartCommand(arguments: ["x"], agentSessionID: "a", transcriptPath: "/a") == nil)
        }
    }
}

/// Telling a running agent from the one installed, from files alone (DESIGNS.md → Agents → Updates).
struct AgentUpdateTests {
    @Test func `a path names its version where a component starts with one`() {
        #expect(AgentUpdates.version(in: "/Users/ada/.local/share/claude/versions/2.1.291") == "2.1.291")
        #expect(AgentUpdates
            .version(in: "/Users/ada/.codex/packages/standalone/releases/0.160.1-aarch64-apple-darwin/bin/codex") == "0.160.1")
        #expect(AgentUpdates.version(in: "/opt/homebrew/Cellar/codex/0.160.1/bin/codex") == "0.160.1")
        #expect(AgentUpdates.version(in: "/Users/ada/.opencode/bin/opencode") == nil)
        #expect(AgentUpdates.version(in: "/Users/ada/2024/bin/tool") == nil)
    }

    @Test func `versions compare number by number`() {
        #expect(AgentUpdates.isNewer("2.1.291", than: "2.1.29"))
        #expect(AgentUpdates.isNewer("2.1.291", than: "2.1.285"))
        #expect(AgentUpdates.isNewer("2.2", than: "2.1.999"))
        #expect(!AgentUpdates.isNewer("2.1.285", than: "2.1.291"))
        #expect(!AgentUpdates.isNewer("2.1.291", than: "2.1.291"))
    }

    @Test func `the launcher pointing elsewhere is an update, unless it points back`() {
        let versions = "/Users/ada/.local/share/claude/versions/"
        #expect(AgentUpdates.compare(launcherTarget: versions + "2.1.291", running: versions + "2.1.291") == nil)
        #expect(AgentUpdates.compare(launcherTarget: versions + "2.1.291", running: versions + "2.1.287")
            == AgentUpdate(installed: "2.1.291", running: "2.1.287"))
        #expect(AgentUpdates.compare(launcherTarget: versions + "2.1.280", running: versions + "2.1.287") == nil)
        #expect(AgentUpdates.compare(launcherTarget: "/opt/a/tool", running: "/opt/b/tool") == AgentUpdate(installed: nil, running: nil))
    }

    @Test func `a running file that was deleted is an update`() {
        #expect(AgentUpdates.compare(launcherTarget: "/Users/ada/.local/share/claude/versions/2.1.291", running: nil)
            == AgentUpdate(installed: "2.1.291", running: nil))
        #expect(AgentUpdates.compare(launcherTarget: "/Users/ada/.opencode/bin/opencode", running: nil)
            == AgentUpdate(installed: nil, running: nil))
    }

    /// The real syscalls: a program started through a link, as `claude` is through
    /// `~/.local/bin/claude`, then the link moved to a newer version, then the old one deleted.
    @Test func `a live process is checked through its launcher`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-update-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let versions = root.appending(path: "versions")
        try FileManager.default.createDirectory(at: versions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        let old = versions.appending(path: "1.0.0")
        let new = versions.appending(path: "1.1.0")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: old)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: new)
        let launcher = root.appending(path: "bin/agent")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: old)

        let process = Process()
        process.executableURL = launcher
        process.arguments = ["30"]
        try process.run()
        defer { process.terminate() }
        let snapshot = try #require(ProcessInspector.snapshot(of: process.processIdentifier))
        #expect(snapshot.executablePath == launcher.path)
        #expect(AgentUpdates.check(snapshot) == nil)

        try FileManager.default.removeItem(at: launcher)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: new)
        #expect(AgentUpdates.check(snapshot) == AgentUpdate(installed: "1.1.0", running: "1.0.0"))

        try FileManager.default.removeItem(at: old)
        #expect(AgentUpdates.check(snapshot) == AgentUpdate(installed: "1.1.0", running: nil))

        // Uninstalled rather than updated: nothing to say.
        try FileManager.default.removeItem(at: launcher)
        #expect(AgentUpdates.check(snapshot) == nil)
    }
}
