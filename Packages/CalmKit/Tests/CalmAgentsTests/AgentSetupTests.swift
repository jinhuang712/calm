@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct AgentSetupTests {
    private func temporaryHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func `each agent says how it connects, through the protocol`() throws {
        let setups = Dictionary(uniqueKeysWithValues: Agents.adapters.map { ($0.kind, $0.setup) })
        #expect(setups[.claudeCode] == .automatic)
        #expect(setups[.codex] == .notifications)
        guard case .hint = try #require(setups[.openCode]) else { Issue.record("OpenCode should be a hint"); return }
        guard case let .files(files) = try #require(setups[.pi]) else { Issue.record("pi should install a file"); return }
        #expect(files.keys.sorted() == [".pi/agent/extensions/calm.ts"])
        #expect(Agents.adapters.allSatisfy { $0.configFolder != nil })
    }

    /// OpenCode 2.0.18's own `cli.json` on the author's machine (2026-09-29), trimmed to the
    /// sections that matter here.
    private let openCodeCLIJSON = """
    {
      "$schema": "https://opencode.ai/v2/cli.json",
      "animations": true,
      "session": { "sidebar": "hide", "permissions": "autoaccept" },
      "attention": { "notifications": true, "sound": true, "volume": 0.20000000000000004 },
      "diffs": { "view": "unified" }
    }
    """

    private func writeOpenCodeCLI(_ text: String?, in home: URL) throws {
        let folder = home.appending(path: ".config/opencode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        if let text {
            try text.write(to: folder.appending(path: "cli.json"), atomically: true, encoding: .utf8)
        }
    }

    @Test func `opencode points at cli json until its notifications are on`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let opencode = OpenCodeAdapter()
        guard case let .hint(text) = opencode.setup else { Issue.record("OpenCode's static setup is a hint"); return }
        #expect(text.contains("cli.json"))
        #expect(!text.contains("tui.json"))

        // No settings file: notifications are off by default (checked in 2.0.18's code).
        try writeOpenCodeCLI(nil, in: home)
        #expect(opencode.currentSetup(home: home) == opencode.setup)

        try writeOpenCodeCLI(openCodeCLIJSON, in: home)
        #expect(opencode.currentSetup(home: home) == .notifications)
    }

    @Test func `opencode's notifications count as on only when they are true`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cases: [(String, Bool)] = [
            (#"{ "attention": { "notifications": false, "sound": true } }"#, false),
            (#"{ "attention": { "sound": true } }"#, false),
            (#"{ "animations": true }"#, false),
            (#"{ "attention": { "notifications": "yes" } }"#, false),
            ("not json at all", false),
            // Comments and a trailing comma, as OpenCode's own parser allows.
            ("{\n  // loud\n  \"attention\": { \"notifications\": true, },\n}", true),
        ]
        for (text, expected) in cases {
            try writeOpenCodeCLI(text, in: home)
            #expect(OpenCodeAdapter.attentionNotificationsOn(home: home) == expected, "\(text)")
        }
    }

    @Test func `agents without their own switch keep their static setup`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for adapter in Agents.adapters where adapter.kind != .openCode {
            #expect(adapter.currentSetup(home: home) == adapter.setup, "\(adapter.kind)")
        }
    }

    @Test func `the pi extension is safe outside Calm and never waits`() {
        let source = PiAdapter.extensionSource
        #expect(source.contains(AgentSetup.marker))
        #expect(source.contains("if (!cli || !process.env.CALM_SESSION_ID) return;"))
        #expect(source.contains("detached: true"))
        for event in ["agent_start", "agent_before_settle", "agent_settled", "ui_prompt_start", "ui_prompt_end"] {
            #expect(source.contains("pi.on(\"\(event)\""))
        }
    }

    @Test func `the pi extension says which conversation it is, without ever failing on it`() {
        let source = PiAdapter.extensionSource
        // Every report names the agent and, when pi knows it, the session file and id.
        #expect(source.contains(#"["status", "--agent", "pi", ...conversation(ctx), state]"#))
        #expect(source.contains("ctx?.sessionManager?.getSessionFile?.()"))
        #expect(source.contains("ctx?.sessionManager?.getSessionId?.()"))
        #expect(source.contains(#""--transcript", file"#))
        #expect(source.contains(#""--agent-session", id"#))
        // A missing or throwing accessor gives no flags rather than no report.
        #expect(source.contains("} catch {\n      return [];"))
    }

    @Test func `refresh brings Calm's own file up to date and touches nothing else`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let old = ["tool/extensions/calm.ts": "// \(AgentSetup.marker)\n// old\n"]
        let new = ["tool/extensions/calm.ts": "// \(AgentSetup.marker)\n// new\n", "tool/extensions/other.ts": "// \(AgentSetup.marker)\n"]
        // Not connected: nothing is added.
        #expect(try AgentSetupFiles.refresh(new, home: home).isEmpty)
        #expect(AgentSetupFiles.state(of: new, home: home) == .notInstalled)
        // Connected with an older version: rewritten; the file the user never installed stays absent.
        try AgentSetupFiles.install(old, home: home)
        #expect(try AgentSetupFiles.refresh(new, home: home) == ["tool/extensions/calm.ts"])
        #expect(try String(contentsOf: home.appending(path: "tool/extensions/calm.ts"), encoding: .utf8).contains("// new"))
        #expect(!FileManager.default.fileExists(atPath: home.appending(path: "tool/extensions/other.ts").path))
        // Up to date: nothing to do.
        #expect(try AgentSetupFiles.refresh(new, home: home).isEmpty)
    }

    @Test func `refresh leaves a file Calm didn't write alone`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appending(path: "tool/extensions/calm.ts")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// the user's own file\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(try AgentSetupFiles.refresh(["tool/extensions/calm.ts": "// \(AgentSetup.marker)\n"], home: home).isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "// the user's own file\n")
    }

    @Test func `install, notice, and remove only Calm's own files`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let files = ["tool/extensions/calm.ts": "// \(AgentSetup.marker)\n"]
        #expect(AgentSetupFiles.state(of: files, home: home) == .notInstalled)
        try AgentSetupFiles.install(files, home: home)
        #expect(AgentSetupFiles.state(of: files, home: home) == .connected)
        try AgentSetupFiles.remove(files, home: home)
        #expect(AgentSetupFiles.state(of: files, home: home) == .notInstalled)
    }

    @Test func `a file Calm didn't write is never touched`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appending(path: "tool/extensions/calm.ts")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "// the user's own file\n".write(to: url, atomically: true, encoding: .utf8)
        let files = ["tool/extensions/calm.ts": "// \(AgentSetup.marker)\n"]
        #expect(AgentSetupFiles.state(of: files, home: home) == .conflict("tool/extensions/calm.ts"))
        #expect(throws: (any Error).self) { try AgentSetupFiles.install(files, home: home) }
        try AgentSetupFiles.remove(files, home: home)
        #expect(try String(contentsOf: url, encoding: .utf8) == "// the user's own file\n")
    }

    @Test func `resume commands per agent, quoted for the shell`() {
        #expect(ClaudeCodeAdapter().resumeCommand(agentSessionID: "abc", transcriptPath: "/x/abc.jsonl") == "claude --resume 'abc'")
        #expect(ClaudeCodeAdapter().resumeCommand(agentSessionID: nil, transcriptPath: "/x/def.jsonl") == "claude --resume 'def'")
        #expect(CodexAdapter().resumeCommand(agentSessionID: "019a", transcriptPath: "/x.jsonl") == "codex resume '019a'")
        #expect(CodexAdapter().resumeCommand(agentSessionID: nil, transcriptPath: "/x.jsonl") == nil)
        #expect(PiAdapter().resumeCommand(agentSessionID: nil, transcriptPath: "/it's/s.jsonl") == #"pi --session '/it'\''s/s.jsonl'"#)
        #expect(OpenCodeAdapter().resumeCommand(agentSessionID: "ses_1", transcriptPath: "/db#ses_1") == "opencode --session 'ses_1'")
        #expect(OpenCodeAdapter().resumeCommand(agentSessionID: nil, transcriptPath: "/db") == nil)
    }

    @Test func `fork commands per agent, quoted for the shell`() {
        #expect(ClaudeCodeAdapter()
            .forkCommand(agentSessionID: "abc", transcriptPath: "/x/abc.jsonl") == "claude --resume 'abc' --fork-session")
        #expect(CodexAdapter().forkCommand(agentSessionID: "019a", transcriptPath: "/x.jsonl") == "codex fork '019a'")
        #expect(CodexAdapter().forkCommand(agentSessionID: nil, transcriptPath: "/x.jsonl") == nil)
        #expect(PiAdapter().forkCommand(agentSessionID: nil, transcriptPath: "/s/a b.jsonl") == "pi --fork '/s/a b.jsonl'")
        #expect(OpenCodeAdapter().forkCommand(agentSessionID: "x", transcriptPath: "/x") == nil)
    }
}
