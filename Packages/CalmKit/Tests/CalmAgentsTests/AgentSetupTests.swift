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
        #expect(setups[.omp] == .notifications)
        guard case .hint = try #require(setups[.openCode]) else { Issue.record("OpenCode should be a hint"); return }
        guard case let .files(files) = try #require(setups[.pi]) else { Issue.record("pi should install a file"); return }
        #expect(files.keys.sorted() == [".pi/agent/extensions/calm.ts"])
        #expect(Agents.adapters.allSatisfy { $0.configFolder != nil })
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
        #expect(OpenCodeAdapter().resumeCommand(agentSessionID: "x", transcriptPath: "/x") == nil)
    }

    @Test func `fork commands per agent, quoted for the shell`() {
        #expect(ClaudeCodeAdapter()
            .forkCommand(agentSessionID: "abc", transcriptPath: "/x/abc.jsonl") == "claude --resume 'abc' --fork-session")
        #expect(CodexAdapter().forkCommand(agentSessionID: "019a", transcriptPath: "/x.jsonl") == "codex fork '019a'")
        #expect(CodexAdapter().forkCommand(agentSessionID: nil, transcriptPath: "/x.jsonl") == nil)
        #expect(PiAdapter().forkCommand(agentSessionID: nil, transcriptPath: "/s/a b.jsonl") == "pi --fork '/s/a b.jsonl'")
        #expect(OmpAdapter().forkCommand(agentSessionID: "s1", transcriptPath: "/x") == "omp --fork 's1'")
        #expect(OpenCodeAdapter().forkCommand(agentSessionID: "x", transcriptPath: "/x") == nil)
    }
}
