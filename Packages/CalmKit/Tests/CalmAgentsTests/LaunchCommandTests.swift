@testable import CalmAgents
import CalmModel
import Foundation
import Testing

/// What ⌘N types for each agent (FEATURES.md → New agent sessions), and which agent it starts.
struct LaunchCommandTests {
    private func command(_ kind: AgentKind, _ config: String = "", inGit: Bool = true) throws -> String {
        let adapter = try #require(Agents.adapter(for: kind))
        return adapter.launchCommand(settings: CalmSettings(text: config), inGitRepository: inGit)
    }

    @Test func `with nothing chosen, each agent starts by its own name`() throws {
        #expect(try command(.claudeCode) == "claude")
        #expect(try command(.codex) == "codex")
        #expect(try command(.openCode) == "opencode")
        #expect(try command(.pi) == "pi")
    }

    @Test func `the options for Claude Code are its own flags, the worktree last`() throws {
        let both = "[agents.claude-code]\nworktree = true\nskip-permissions = true\n"
        #expect(try command(.claudeCode, both) == "claude --dangerously-skip-permissions -w")
    }

    @Test func `a new worktree only in a git repository`() throws {
        let both = "[agents.claude-code]\nskip-permissions = true\nworktree = true\n\n[agents.codex]\nworktree = true\n"
        #expect(try command(.claudeCode, both, inGit: false) == "claude --dangerously-skip-permissions")
        #expect(try command(.codex, both, inGit: false) == "codex")
        #expect(try command(.codex, both, inGit: true) == "codex --worktree")
    }

    @Test func `skipping the questions for Codex and OpenCode uses their own flags`() throws {
        let skip = "[agents.codex]\nskip-permissions = true\n\n[agents.opencode]\nskip-permissions = true\n"
        #expect(try command(.codex, skip) == "codex --dangerously-bypass-approvals-and-sandbox")
        #expect(try command(.openCode, skip) == "opencode --auto")
    }

    @Test func `flags from config.toml come before the options, as written`() throws {
        let config = "[agents.claude-code]\nflags = \"--model opus\"\nworktree = true\n\n[agents.pi]\nflags = \"--provider anthropic\"\n"
        #expect(try command(.claudeCode, config) == "claude --model opus -w")
        #expect(try command(.pi, config) == "pi --provider anthropic")
    }

    @Test func `the whole command is typed as written, in place of the flags and options`() throws {
        let config = "[agents.claude-code]\ncommand = \"claude -w\"\nflags = \"--model opus\"\nskip-permissions = true\n"
        // As written even outside a git repository: Calm doesn't read flags out of it.
        #expect(try command(.claudeCode, config, inGit: false) == "claude -w")
        #expect(try command(.claudeCode, config, inGit: true) == "claude -w")
        #expect(try command(.codex, config) == "codex")
    }

    @Test func `⌘N starts the agent config.toml names, else the first installed`() {
        let codex = CalmSettings(text: "[agents]\nnew-session = \"codex\"\n")
        #expect(Agents.newSessionAgent(settings: codex, installed: [.claudeCode]) == .codex)
        #expect(Agents.newSessionAgent(settings: CalmSettings(), installed: [.claudeCode, .pi]) == .claudeCode)
        #expect(Agents.newSessionAgent(settings: CalmSettings(), installed: [.codex, .pi]) == .codex)
        #expect(Agents.newSessionAgent(settings: CalmSettings(), installed: []) == nil)
    }

    @Test func `installed agents are the ones whose folder is there, in Calm's order`() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        for kind in [AgentKind.pi, .codex] {
            let folder = try #require(Agents.adapter(for: kind)?.configFolder)
            try FileManager.default.createDirectory(at: home.appending(path: folder), withIntermediateDirectories: true)
        }
        #expect(Agents.installed(home: home) == [.codex, .pi])
    }

    @Test func `calm config knows each agent's options as true-or-false keys`() throws {
        let worktree = try #require(Agents.settingsKey(named: "agents.claude-code.worktree"))
        #expect(worktree.kind == .bool)
        #expect(worktree.defaultValue == "false")
        #expect(Agents.settingsKey(named: "agents.opencode.skip-permissions") != nil)
        #expect(Agents.settingsKey(named: "agents.pi.skip-permissions") == nil)
        #expect(Agents.settingsKey(named: "motion") != nil)
        let names = Agents.settingsKeys.map(\.name)
        #expect(Set(names).count == names.count)
    }
}
