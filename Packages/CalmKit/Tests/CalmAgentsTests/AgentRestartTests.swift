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

    /// Each checked in a pty against the real agent at its chat screen (2026-10-07).
    @Test func `each agent quits the way it tidies the terminal`() {
        #expect(ClaudeCodeAdapter().quit == .signal(SIGTERM))
        #expect(CodexAdapter().quit == .controlC(times: 4))
        #expect(OpenCodeAdapter().quit == .signal(SIGTERM))
        #expect(PiAdapter().quit == .signal(SIGTERM))
    }

    // MARK: Codex

    private func codex(_ arguments: [String], id: String? = "019a") -> String? {
        CodexAdapter().restartCommand(arguments: arguments, agentSessionID: id, transcriptPath: "/x.jsonl")
    }

    @Test func `a restarted Codex resumes with the options it was started with`() {
        let started = ["/Users/ada/.local/bin/codex", "--dangerously-bypass-approvals-and-sandbox", "-m", "o3", "fix the bug"]
        #expect(codex(started) == "codex resume --dangerously-bypass-approvals-and-sandbox -m o3 '019a'")
        #expect(codex(["codex", "--yolo", "-c", "model_reasoning_effort=high"]) ==
            "codex resume --yolo -c model_reasoning_effort=high '019a'")
        #expect(codex(["codex", "--sandbox", "workspace-write", "--search"]) == "codex resume --sandbox workspace-write --search '019a'")
    }

    @Test func `a Codex subcommand, prompt and images aren't carried over`() {
        #expect(codex(["codex", "resume", "old-id"]) == "codex resume '019a'")
        #expect(codex(["codex", "resume", "--last"]) == "codex resume '019a'")
        #expect(codex(["codex", "fork", "old-id", "try it"]) == "codex resume '019a'")
        #expect(codex(["codex", "-i", "a.png", "b.png", "--search", "look"]) == "codex resume --search '019a'")
        #expect(codex(["codex", "--worktree"]) == "codex resume '019a'")
        #expect(codex(["codex"], id: nil) == nil)
    }

    // MARK: OpenCode

    private func openCode(_ arguments: [String], id: String? = "ses_1") -> String? {
        OpenCodeAdapter().restartCommand(arguments: arguments, agentSessionID: id, transcriptPath: "/db#ses_1")
    }

    @Test func `a restarted OpenCode keeps its options and the folder it started in`() {
        let started = ["/Users/ada/.opencode/bin/opencode", "--auto", "/Users/ada/dev/app"]
        #expect(openCode(started) == "opencode --auto --session 'ses_1' /Users/ada/dev/app")
        #expect(openCode(["opencode", "--server", "http://127.0.0.1:4096"]) == "opencode --server http://127.0.0.1:4096 --session 'ses_1'")
        #expect(openCode(["opencode", "/Users/ada/My App"]) == "opencode --session 'ses_1' '/Users/ada/My App'")
    }

    @Test func `an OpenCode session and prompt give way, and a subcommand has no restart`() {
        #expect(openCode(["opencode", "-c"]) == "opencode --session 'ses_1'")
        #expect(openCode(["opencode", "--session", "ses_old", "--prompt", "hi"]) == "opencode --session 'ses_1'")
        #expect(openCode(["opencode", "mini"]) == nil)
        #expect(openCode(["opencode", "run", "hello"]) == nil)
        #expect(openCode(["opencode"], id: nil) == nil)
    }

    // MARK: pi

    private func pi(_ arguments: [String], transcript: String = "/Users/ada/.pi/agent/sessions/s.jsonl") -> String? {
        PiAdapter().restartCommand(arguments: arguments, agentSessionID: nil, transcriptPath: transcript)
    }

    /// What `KERN_PROCARGS2` gives for a running pi (2026-10-07): its title, then the environment.
    @Test func `pi's overwritten command line leaves just its session`() {
        let overwritten = ["pi", "MANPATH=:/usr/share/man", "TERM_PROGRAM=calm", "HOME=/Users/ada", "_=/Users/ada/bin/pi"]
        #expect(pi(overwritten) == "pi --session '/Users/ada/.pi/agent/sessions/s.jsonl'")
    }

    @Test func `pi's options carry over where they can be read`() {
        let readable = ["node", "/n/pi-coding-agent/dist/bundle/cli.js", "--thinking", "high", "-n", "probe", "hello there"]
        #expect(pi(readable) == "pi --thinking high -n probe --session '/Users/ada/.pi/agent/sessions/s.jsonl'")
        #expect(pi(["node", "/n/cli.js", "-c", "--session", "/old.jsonl", "-p", "x"]) ==
            "pi --session '/Users/ada/.pi/agent/sessions/s.jsonl'")
        #expect(pi(["pi"], transcript: "") == nil)
    }

    // MARK: Resume and fork

    /// A conversation as Calm keeps it once its agent exits: the options are read from the command
    /// line while the process runs (`AgentRun.options`).
    private func ended(_ kind: AgentKind, _ commandLine: [String], id: String? = nil, transcript: String? = nil) -> AgentConversation {
        let options = Agents.adapter(for: kind)?.resumeOptions(commandLine: commandLine)
        return AgentConversation(kind: kind, agentSessionID: id, transcriptPath: transcript, options: options)
    }

    /// Nothing chosen for ⌘N.
    private let none = CalmSettings()
    /// ⌘N with Skip permissions and a new worktree, and flags written in config.toml.
    private let newSession = CalmSettings(text: """
    [agents.claude-code]
    skip-permissions = true
    worktree = true
    flags = "--model opus --append-system-prompt 'be brief'"

    [agents.codex]
    skip-permissions = true
    worktree = true

    [agents.opencode]
    skip-permissions = true
    """)

    /// Seen 2026-10-10: a session started with `--dangerously-skip-permissions` came back from
    /// Resume as `claude --resume <id>`, asking for every tool again.
    @Test func `a resumed conversation keeps the options its agent was started with`() {
        let claude = ended(.claudeCode, ["claude", "--dangerously-skip-permissions", "--model", "opus", "fix the test"], id: "abc")
        #expect(ClaudeCodeAdapter().resumeCommand(for: claude, settings: none)
            == "claude --dangerously-skip-permissions --model opus --resume 'abc'")
        let codex = ended(.codex, ["codex", "--yolo", "-m", "o3", "fix it"], id: "019a")
        #expect(CodexAdapter().resumeCommand(for: codex, settings: none) == "codex resume --yolo -m o3 '019a'")
        let openCode = ended(.openCode, ["opencode", "--auto", "/Users/ada/dev/app"], id: "ses_1")
        #expect(OpenCodeAdapter().resumeCommand(for: openCode, settings: none) == "opencode --auto --session 'ses_1' /Users/ada/dev/app")
        let pi = ended(.pi, ["/n/cli.js", "--thinking", "high", "hello"], transcript: "/s.jsonl")
        #expect(PiAdapter().resumeCommand(for: pi, settings: none) == "pi --thinking high --session '/s.jsonl'")
    }

    @Test func `a fork keeps them too`() throws {
        let claude = ended(.claudeCode, ["claude", "--dangerously-skip-permissions", "-w"], id: "abc")
        #expect(ClaudeCodeAdapter().forkCommand(for: claude, settings: none)
            == "claude --dangerously-skip-permissions --resume 'abc' --fork-session")
        #expect(ClaudeCodeAdapter().forkCommand(for: claude, settings: none, prompt: "go on")
            == "claude --dangerously-skip-permissions --resume 'abc' --fork-session 'go on'")
        let codex = ended(.codex, ["codex", "--yolo"], id: "019a")
        #expect(CodexAdapter().forkCommand(for: codex, settings: none) == "codex fork --yolo '019a'")
        #expect(CodexAdapter().forkCommand(for: codex, settings: none, prompt: "go on") == "codex fork --yolo '019a' 'go on'")
        let pi = ended(.pi, ["/n/cli.js", "--thinking", "high"], transcript: "/s.jsonl")
        #expect(PiAdapter().forkCommand(for: pi, settings: none) == "pi --thinking high --fork '/s.jsonl'")
        let openCode = ended(.openCode, ["opencode", "--auto"], id: "ses_1")
        let fork = try #require(OpenCodeAdapter().forkCommand(for: openCode, settings: none))
        #expect(fork.hasPrefix(#"opencode --auto --session "$(opencode api session.fork --param sessionID='ses_1'"#))
    }

    /// Its own options win, none included: ⌘N's Skip permissions isn't added to a conversation
    /// Calm saw started without it.
    @Test func `the options a conversation was started with win over ⌘N's`() {
        let plain = ended(.claudeCode, ["claude", "fix the test"], id: "abc")
        #expect(plain.options == [])
        #expect(ClaudeCodeAdapter().resumeCommand(for: plain, settings: newSession) == "claude --resume 'abc'")
    }

    /// The author's call, 2026-10-10: a conversation found by ⌘K, or one that ended before Calm
    /// kept options, starts as ⌘N would start the agent, less the worktree it would make.
    @Test func `a conversation Calm didn't see run starts with ⌘N's options`() {
        let found = AgentConversation(kind: .claudeCode, agentSessionID: "abc", transcriptPath: nil)
        #expect(ClaudeCodeAdapter().resumeCommand(for: found, settings: none) == "claude --resume 'abc'")
        #expect(ClaudeCodeAdapter().resumeCommand(for: found, settings: newSession)
            == "claude --model opus --append-system-prompt 'be brief' --dangerously-skip-permissions --resume 'abc'")
        let codex = AgentConversation(kind: .codex, agentSessionID: "019a", transcriptPath: nil)
        #expect(CodexAdapter().resumeCommand(for: codex, settings: newSession) == "codex resume --yolo '019a'")
        #expect(CodexAdapter().forkCommand(for: codex, settings: newSession) == "codex fork --yolo '019a'")
        // So does one started through an OpenCode subcommand: those options are another interface's.
        let run = ended(.openCode, ["opencode", "run", "--model", "x", "hello"], id: "ses_1")
        #expect(run.options == nil)
        #expect(OpenCodeAdapter().resumeCommand(for: run, settings: none) == "opencode --session 'ses_1'")
        #expect(OpenCodeAdapter().resumeCommand(for: run, settings: newSession) == "opencode --auto --session 'ses_1'")
    }

    /// `agents.<agent>.command` replaces the whole of ⌘N's command; a line that needs the shell
    /// to read it gives no options rather than wrong ones.
    @Test func `⌘N's own command gives its options where Calm can read them`() {
        let found = AgentConversation(kind: .claudeCode, agentSessionID: "abc", transcriptPath: nil)
        let written = CalmSettings(text: "[agents.claude-code]\ncommand = \"claude --model opus -w\"\n")
        #expect(ClaudeCodeAdapter().resumeCommand(for: found, settings: written) == "claude --model opus --resume 'abc'")
        let shell = CalmSettings(text: "[agents.claude-code]\ncommand = \"claude $CLAUDE_FLAGS\"\n")
        #expect(ClaudeCodeAdapter().resumeCommand(for: found, settings: shell) == "claude --resume 'abc'")
    }
}

/// Each step `AgentUpdates.check` needs, as its own requirement, so a failure says which one it was
/// (a check came back empty in two full runs, never alone).
private func requireStandIn(_ process: Process, _ snapshot: ProcessSnapshot) throws {
    if !process.isRunning {
        process.waitUntilExit()
        let how = process.terminationReason == .uncaughtSignal ? "signal" : "exit"
        try #require(Bool(false), "the stand-in ended: \(how) \(process.terminationStatus)")
    }
    try #require(ProcessInspector.snapshot(of: process.processIdentifier) != nil, "the stand-in's arguments can't be read")
    let target = try #require(AgentUpdates.installedProgram(of: snapshot), "no installed program for \(snapshot.executablePath)")
    try #require(ProcessInspector.fileStatus(of: target) != nil, "no status for \(target)")
}

/// Telling a running agent from the one installed (DESIGNS.md → Agents → Updates).
struct AgentUpdateTests {
    /// Opt-in, against a real agent started from zsh: `CALM_REAL_AGENT_PID=<pid> swift test --filter
    /// "a real running agent"`. Prints what Calm reads; passes when it reads a version.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_AGENT_PID"] != nil))
    func `a real running agent shows the version it runs`() throws {
        let pid = try #require(ProcessInfo.processInfo.environment["CALM_REAL_AGENT_PID"].flatMap { Int32($0) })
        let snapshot = try #require(ProcessInspector.snapshot(of: pid))
        let found = AgentUpdates.check(snapshot)
        let agent = Agents.detect(snapshot)?.rawValue ?? "no agent"
        let update = String(describing: found?.update)
        print("real \(agent) \(pid): runs \(found?.running ?? "?"), update \(update), command \(snapshot.commandPath ?? "?")")
        #expect(found?.running != nil)
        #expect(found?.update == nil)
    }

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

    @Test func `a program says its version in its own words`() {
        #expect(AgentUpdates.version(inOutput: "opencode v2.0.20\n") == "2.0.20")
        #expect(AgentUpdates.version(inOutput: "codex-cli 0.159.0") == "0.159.0")
        #expect(AgentUpdates.version(inOutput: "1.0.4") == "1.0.4")
        #expect(AgentUpdates.version(inOutput: "2.1.292 (Claude Code)") == "2.1.292")
        #expect(AgentUpdates.version(inOutput: "v2 is coming") == nil)
        #expect(AgentUpdates.version(inOutput: "") == nil)
    }

    private func native(_ target: String, running: String?, installed: String? = nil, replaced: Bool = false) -> AgentVersions {
        AgentUpdates.decideNative(
            target: target,
            running: running,
            replaced: replaced,
            installed: installed ?? AgentUpdates.version(in: target),
        )
    }

    @Test func `the launcher pointing elsewhere is an update, unless it points back`() {
        let versions = "/Users/ada/.local/share/claude/versions/"
        #expect(native(versions + "2.1.291", running: versions + "2.1.291") == AgentVersions(running: "2.1.291", update: nil))
        #expect(native(versions + "2.1.291", running: versions + "2.1.287")
            == AgentVersions(running: "2.1.287", update: AgentUpdate(installed: "2.1.291", running: "2.1.287")))
        #expect(native(versions + "2.1.280", running: versions + "2.1.287") == AgentVersions(running: "2.1.287", update: nil))
        #expect(native("/opt/a/tool", running: "/opt/b/tool").update == AgentUpdate(installed: nil, running: nil))
    }

    @Test func `a running file deleted or replaced since the start is an update`() {
        #expect(native("/Users/ada/.local/share/claude/versions/2.1.291", running: nil).update == AgentUpdate(
            installed: "2.1.291",
            running: nil,
        ))
        // OpenCode's one file: its version from --version, and an update replaces the file.
        let openCode = "/Users/ada/.opencode/bin/opencode"
        #expect(native(openCode, running: openCode, installed: "2.0.20") == AgentVersions(running: "2.0.20", update: nil))
        #expect(native(openCode, running: openCode, installed: "2.0.24", replaced: true)
            == AgentVersions(running: nil, update: AgentUpdate(installed: "2.0.24", running: nil)))
        #expect(native(openCode, running: nil, installed: "2.0.24").update == AgentUpdate(installed: "2.0.24", running: nil))
    }

    @Test func `a script is its package's version until it changes under the process`() {
        #expect(AgentUpdates.decideScript(installed: "1.0.4", changedSinceStart: false) == AgentVersions(running: "1.0.4", update: nil))
        #expect(AgentUpdates.decideScript(installed: "1.0.5", changedSinceStart: true)
            == AgentVersions(running: nil, update: AgentUpdate(installed: "1.0.5", running: nil)))
    }

    @Test func `the package version is the nearest package json above the script`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-package-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "pi-coding-agent/dist/bundle")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(#"{"name":"@earendil-works/pi-coding-agent","version":"1.0.4"}"#.utf8)
            .write(to: root.appending(path: "pi-coding-agent/package.json"))
        #expect(AgentUpdates.packageVersion(near: bundle.appending(path: "cli.js").path) == "1.0.4")
        #expect(AgentUpdates.packageVersion(near: "/nowhere/at/all.js") == nil)
    }

    /// pi overwrites its argv with its title; the shell's `_` survives in the environment.
    @Test func `the command path comes from the shell's underscore, wherever it sits`() throws {
        func procargs(_ strings: [String], argc: Int32) -> [UInt8] {
            withUnsafeBytes(of: argc) { Array($0) } + strings.flatMap { Array($0.utf8) + [0] }
        }
        let overwritten = procargs(["/usr/local/bin/node", "pi", "MANPATH=/usr/share/man", "_=/Users/ada/bin/pi", "HOME=/x"], argc: 4)
        let snapshot = try #require(ProcessInspector.parseArguments(overwritten, processID: 1))
        #expect(snapshot.commandPath == "/Users/ada/bin/pi")
        #expect(snapshot.runsScript)
        let plain = procargs(["/Users/ada/.local/bin/codex", "codex", "--yolo", "HOME=/x", "_=/Users/ada/.local/bin/codex"], argc: 2)
        let codex = try #require(ProcessInspector.parseArguments(plain, processID: 1))
        #expect(codex.arguments == ["codex", "--yolo"])
        #expect(codex.commandPath == "/Users/ada/.local/bin/codex")
        #expect(!codex.runsScript)
    }

    /// The real syscalls for a script: a stand-in process with a pi-shaped package behind a link,
    /// then the package updated under it.
    @Test func `a live script is checked through its package`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-script-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let package = root.appending(path: "lib/node_modules/@earendil-works/pi-coding-agent")
        try FileManager.default.createDirectory(at: package.appending(path: "dist/bundle"), withIntermediateDirectories: true)
        let script = package.appending(path: "dist/bundle/cli.js")
        try Data("// stand-in\n".utf8).write(to: script)
        try Data(#"{"version":"1.0.4"}"#.utf8).write(to: package.appending(path: "package.json"))
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        let launcher = root.appending(path: "bin/pi")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: script)
        // Made before the process starts, so the script isn't newer than it.
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(filePath: "/bin/sleep")
        process.arguments = ["300"]
        try process.run()
        defer { process.terminate() }
        let snapshot = ProcessSnapshot(
            processID: process.processIdentifier, executablePath: "/usr/local/bin/node", arguments: ["pi"], commandPath: launcher.path,
        )
        // No slack: the test can't wait the two seconds a real check allows after the start.
        #expect(AgentUpdates.check(snapshot, slack: 0) == AgentVersions(running: "1.0.4", update: nil))

        // npm's way: new files, each with the 1985 modification date npm gives every packed file.
        try FileManager.default.removeItem(at: script)
        try Data("// stand-in, updated\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 499_162_500)], ofItemAtPath: script.path)
        try Data(#"{"version":"1.0.5"}"#.utf8).write(to: package.appending(path: "package.json"))
        try requireStandIn(process, snapshot)
        #expect(AgentUpdates.check(snapshot, slack: 0)
            == AgentVersions(running: nil, update: AgentUpdate(installed: "1.0.5", running: nil)))
    }

    /// The real syscalls for a program at a fixed path, OpenCode's way: asked its version, and the
    /// file it runs known by inode.
    @Test func `a live program at a fixed path is asked its version and known by inode`() throws {
        // Kept after the test, never removed (`StandInPrograms`).
        let program = try StandInPrograms.sleep(at: "bin/tool")

        let process = Process()
        process.executableURL = program
        process.arguments = ["300"]
        try process.run()
        defer { process.terminate() }
        let snapshot = try #require(ProcessInspector.snapshot(of: process.processIdentifier))
        var answer = "tool v2.0.20"
        let probe: (String) -> String? = { _ in AgentUpdates.version(inOutput: answer) }
        #expect(AgentUpdates.check(snapshot, probe: probe) == AgentVersions(running: "2.0.20", update: nil))

        // The inode read from the live process is the file's own: what a new file at the path would
        // differ from. The replacing itself isn't done here: a program file that changes while it
        // starts upsets macOS's signature check (`StandInPrograms`). `decideNative`'s tests take
        // the replaced case.
        let mapped = try #require(ProcessInspector.executableInode(of: process.processIdentifier))
        #expect(mapped == ProcessInspector.fileStatus(of: program.path)?.identity)
        #expect(mapped != ProcessInspector.fileStatus(of: "/bin/sleep")?.identity)
        answer = "tool v2.0.24"
        #expect(AgentUpdates.check(snapshot, probe: probe)?.running == "2.0.24")
    }

    /// The real syscalls: a program started through a link, as `claude` is through
    /// `~/.local/bin/claude`, then the link moved to a newer version. (Its old file being deleted
    /// is `decideNative`'s test: the stand-in sometimes died of it.)
    @Test func `a live process is checked through its launcher`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-update-\(UUID().uuidString)").resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "bin"), withIntermediateDirectories: true)
        // The programs are kept after the test, never removed (`StandInPrograms`); only the link,
        // here, comes and goes.
        let old = try StandInPrograms.sleep(at: "versions/1.0.0")
        let new = try StandInPrograms.sleep(at: "versions/1.1.0")
        let launcher = root.appending(path: "bin/agent")
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: old)

        let process = Process()
        process.executableURL = launcher
        process.arguments = ["300"]
        try process.run()
        defer { process.terminate() }
        let snapshot = try #require(ProcessInspector.snapshot(of: process.processIdentifier))
        #expect(snapshot.executablePath == launcher.path)
        // The path names the version, so the program is never asked.
        let probe: (String) -> String? = { _ in
            Issue.record("asked a program whose path names its version")
            return nil
        }
        #expect(AgentUpdates.check(snapshot, probe: probe) == AgentVersions(running: "1.0.0", update: nil))

        try FileManager.default.removeItem(at: launcher)
        try FileManager.default.createSymbolicLink(at: launcher, withDestinationURL: new)
        try requireStandIn(process, snapshot)
        #expect(AgentUpdates.check(snapshot)?.update == AgentUpdate(installed: "1.1.0", running: "1.0.0"))

        // Uninstalled rather than updated: nothing to say.
        try FileManager.default.removeItem(at: launcher)
        #expect(AgentUpdates.check(snapshot) == nil)
    }
}
