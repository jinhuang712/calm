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
        guard case let .files(opencode) = try #require(setups[.openCode]) else { Issue.record("OpenCode should install a plugin"); return }
        // A folder with only a TUI entry: the shared service looks for `server` or `index`, so it never loads it.
        #expect(opencode.keys.sorted() == [".config/opencode/plugins/calm/tui.ts"])
        guard case let .files(files) = try #require(setups[.pi]) else { Issue.record("pi should install a file"); return }
        #expect(files.keys.sorted() == [".pi/agent/extensions/calm.ts"])
        #expect(Agents.adapters.allSatisfy { $0.configFolder != nil })
    }

    @Test func `agents keep their static setup`() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        for adapter in Agents.adapters {
            #expect(adapter.currentSetup(home: home) == adapter.setup, "\(adapter.kind)")
        }
    }

    @Test func `the opencode plugin is safe outside Calm and never waits`() {
        let source = OpenCodeAdapter.pluginSource
        #expect(source.contains(AgentSetup.marker))
        // 2.0.19 loads only a module whose default export is `{ id, setup }`.
        #expect(source.contains("export default {\n  id: \"calm\",\n  setup(context: any) {"))
        #expect(source.contains("if (!cli || !process.env.CALM_SESSION_ID) return;"))
        #expect(source.contains("detached: true"))
        #expect(!source.contains("await "))
        for event in [
            "session.execution.started", "session.execution.succeeded", "session.execution.failed", "session.execution.interrupted",
            "permission.asked", "permission.replied", "form.created", "form.replied", "form.cancelled",
        ] {
            #expect(source.contains("listen(\"\(event)\""), "\(event)")
        }
    }

    @Test func `the opencode plugin names the session on its own screen`() {
        let source = OpenCodeAdapter.pluginSource
        // `openCode` is AgentKind's raw value, which `calm status --agent` takes.
        #expect(source.contains(#"["status", "--agent", "\#(AgentKind.openCode.rawValue)", "--agent-session", session"#))
        #expect(source.contains(#""--transcript", database"#))
        #expect(source.contains("context.ui.router.current()"))
        #expect(source.contains("context.data.session.root(route.sessionID)"))
        // A turn counts only for the session itself; an ask counts anywhere under it.
        #expect(source.contains("if (session && sessionID === session) report(session, state, message);"))
        #expect(source.contains("if (context.data.session.root(sessionID) !== session) return;"))
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

    @Test func `the pi extension counts a prompt only during a run, and only answers one it counted`() {
        let source = PiAdapter.extensionSource
        // pi reports a passive overlay (pi-briefly's, opened at session_start and never closed)
        // as a prompt too; outside a run it is not the agent waiting. Replayed against the real
        // source with node on 2026-09-30: no reports for an overlay at start, or a picker opened
        // and closed at idle; needs-you then working for an ask during a run.
        #expect(source.contains("pi.on(\"ui_prompt_start\", (event: any, ctx: any) => {\n    if (!running) return;"))
        #expect(source.contains("pi.on(\"ui_prompt_end\", (_event: any, ctx: any) => {\n    if (!asked) return;"))
        // The end of a prompt goes back to working only while the run is still on, or it would
        // overwrite the state the run settled to.
        #expect(source.contains("if (running) report(ctx, \"working\");"))
        // A run's start and settle both close the books on any prompt.
        #expect(source.contains("running = true;\n    asked = false;"))
        #expect(source.contains("running = false;\n    asked = false;"))
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
        #expect(OpenCodeAdapter().forkCommand(agentSessionID: nil, transcriptPath: "/db") == nil)
    }

    /// `calm fork "<prompt>"`: the prompt is the fork's first message where the agent's own command
    /// line takes one; elsewhere the fork can't start with one rather than drop it.
    @Test func `a fork with a first message, where the agent takes one`() {
        let prompt = "Try the CRDT approach; don't merge it"
        let claude = AgentConversation(kind: .claudeCode, agentSessionID: "abc", transcriptPath: "/x/abc.jsonl")
        #expect(ClaudeCodeAdapter().forkCommand(for: claude, prompt: prompt)
            == "claude --resume 'abc' --fork-session 'Try the CRDT approach; don'\\''t merge it'")
        let codex = AgentConversation(kind: .codex, agentSessionID: "019a", transcriptPath: "/x.jsonl")
        #expect(CodexAdapter().forkCommand(for: codex, prompt: "go on") == "codex fork '019a' 'go on'")
        let pi = AgentConversation(kind: .pi, agentSessionID: nil, transcriptPath: "/s/a.jsonl")
        #expect(PiAdapter().forkCommand(for: pi, prompt: "go on") == nil)
        let openCode = AgentConversation(kind: .openCode, agentSessionID: "ses_1", transcriptPath: "/db")
        #expect(OpenCodeAdapter().forkCommand(for: openCode, prompt: "go on") == nil)
    }

    /// OpenCode forks through its API and opens the new session: run in a real shell, with a
    /// stand-in `opencode` that answers the way 2.0.19's `opencode api` does (one line of JSON).
    @Test func `the opencode fork opens the session the api made`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-fork-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let stub = folder.appending(path: "opencode")
        try """
        #!/bin/sh
        if [ "$1" = api ]; then
          printf '%s\\n' "$*" > "$STUB_LOG.api"
          printf '{"data":{"id":"ses_fork","location":{"directory":"/x","id":"loc_1"},"title":"t"}}\\n'
        else
          printf '%s\\n' "$*" > "$STUB_LOG.tui"
        fi
        """.write(to: stub, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stub.path)
        let plain = try #require(OpenCodeAdapter().forkCommand(agentSessionID: "ses_it's", transcriptPath: "/db"))
        // With the options it was started with, and its folder after the session, as a resume has them.
        let started = AgentConversation(
            kind: .openCode,
            agentSessionID: "ses_it's",
            transcriptPath: "/db",
            options: ["--auto", "/a/My App"],
        )
        let withOptions = try #require(OpenCodeAdapter().forkCommand(for: started))

        for (command, opened) in [(plain, "--session ses_fork"), (withOptions, "--auto --session ses_fork /a/My App")] {
            for shell in ["/bin/zsh", "/bin/bash"] {
                let process = Process()
                process.executableURL = URL(filePath: shell)
                process.arguments = ["-c", command]
                let log = folder.appending(path: "log").path
                process.environment = ["PATH": "\(folder.path):/usr/bin:/bin", "STUB_LOG": log]
                try process.run()
                process.waitUntilExit()
                #expect(process.terminationStatus == 0, "\(shell)")
                #expect(try String(contentsOfFile: log + ".api", encoding: .utf8) == "api session.fork --param sessionID=ses_it's -d {}\n")
                #expect(try String(contentsOfFile: log + ".tui", encoding: .utf8) == opened + "\n", "\(shell)")
            }
        }
    }
}
