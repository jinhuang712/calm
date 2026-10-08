import CalmAgents
import CalmControl
import CalmSearch
import Foundation

// The `calm` command-line tool: talks to the running app over its local socket
// (see DESIGNS.md → Control protocol).

let version = "0.1.0"
let usage = """
calm \(version) — a minimal macOS terminal that keeps you calm and focused

Usage:
  calm open <folder>                Add the folder as a project and open a session in it
  calm open <file>[:line]           View the file in Calm (or open it in your editor)
  calm list                         List sessions
  calm search <text>                Search every agent's past sessions (each ends with its id)
  calm show <conversation>          Everything Calm knows about one conversation
                                    [--prompts: every prompt; --all: the whole of it; --json]
  calm notify <message>             Notify about this session at the next pause
  calm fork ["<prompt>"]            Fork this session's conversation into a new session
                                    [--background: stay here; --in <folder>; --session <id>]
  calm config [list]                Calm's settings: each one's value, and what it takes
  calm config get <key>             Print one setting's value
  calm config set <key> <value…>    Change a setting in config.toml; Calm applies it at once
  calm config unset <key>           Put a setting back to its default
  calm doctor [--json]              Check that Calm, this calm and the agents' hooks work
  calm trace [--last 5m] [--session <id>] [--follow]
                                    Print Calm's trace: what decided each session's row
  calm --version                    Print the version
  calm --help                       Show this help

For agents' hooks:
  calm status <state> [message]     Report this session's state:
                                    working, needs-you, done, failed or idle
                                    [--agent <name> --transcript <file> --agent-session <id>
                                    say which agent and conversation, for its transcript]
  calm hook <agent>                 Read an agent's hook payload on stdin and report it
                                    (used by the hooks Calm installs; agent: claude-code)

status, hook and notify act on $CALM_SESSION_ID (or --session <id>). Outside Calm, or when
Calm isn't running, they do nothing and exit 0, so hooks are safe in any terminal.
"""

func warn(_ message: String) {
    FileHandle.standardError.write(Data("calm: \(message)\n".utf8))
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    warn(message)
    exit(code)
}

/// Sends a request, starting Calm first if it isn't running (the Calm this CLI came with, and
/// only for the standard socket: `CalmLaunch`).
func send(_ request: ControlRequest) -> ControlResponse {
    do {
        return try ControlClient.send(request)
    } catch let error as ControlClient.ClientError {
        guard case .notRunning = error else { fail("\(error)") }
        let executable = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
        guard let openArguments = CalmLaunch.openArguments(executable: executable, socketPath: ControlProtocol.defaultSocketPath)
        else { fail("\(error)") }
        let launcher = Process()
        launcher.executableURL = URL(filePath: "/usr/bin/open")
        launcher.arguments = openArguments
        try? launcher.run()
        launcher.waitUntilExit()
        for _ in 0 ..< 50 {
            usleep(100_000)
            if let response = try? ControlClient.send(request) {
                return response
            }
        }
        fail("Calm didn't start.")
    } catch {
        fail("\(error)")
    }
}

/// For hooks: report quietly and never fail the agent. No session or no Calm means nothing to do.
func report(_ request: ControlRequest) -> Never {
    guard request.session != nil else { exit(0) }
    guard let response = try? ControlClient.send(request, timeout: 1) else { exit(0) }
    if !response.ok, let error = response.error {
        warn(error)
    }
    exit(0)
}

/// Splits the options out of the arguments; the session defaults to the one Calm started this shell in.
func statusArguments(_ words: [String]) -> StatusArguments {
    StatusArguments.parse(words, defaultSession: ProcessInfo.processInfo.environment["CALM_SESSION_ID"])
}

func sessionAndWords(_ words: [String]) -> (session: String?, words: [String]) {
    let parsed = statusArguments(words)
    return (parsed.session, parsed.words)
}

/// Calm isn't there to ask: read the index directly, bringing it up to date first.
func searchIndex(_ query: String) -> [ControlResponse.SearchHit] {
    guard let index = try? SearchIndex() else { fail("couldn't open the search index") }
    index.update()
    return index.search(query, limit: 20).map { result in
        ControlResponse.SearchHit(
            title: result.title, agent: result.agent.displayName, directory: result.directory,
            lastActive: result.lastActive.timeIntervalSince1970, snippet: result.snippet, transcript: result.transcriptPath,
            conversation: result.agentSessionID,
        )
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--version", "-v":
    print("calm \(version)")
case nil, "--help", "-h", "help":
    print(usage)
case "list", "ls":
    let response = send(ControlRequest(cmd: .list))
    guard response.ok else { fail(response.error ?? "failed") }
    for session in response.sessions ?? [] {
        print(CLIOutput.line(for: session))
    }
case "open":
    let target = arguments.count > 1 ? arguments[1] : FileManager.default.currentDirectoryPath
    let absolute = target.hasPrefix("/") || target.hasPrefix("~")
        ? target
        : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(target)
    let response = send(ControlRequest(cmd: .open, path: absolute))
    guard response.ok else { fail(response.error ?? "failed") }
case "status":
    let parsed = statusArguments(Array(arguments.dropFirst()))
    guard let state = parsed.words.first else { fail("give a state: working, needs-you, done, failed or idle", code: 64) }
    let message = parsed.words.dropFirst().joined(separator: " ")
    report(ControlRequest(
        cmd: .status, session: parsed.session, state: state, message: message.isEmpty ? nil : message,
        agent: parsed.agent, agentSession: parsed.agentSession, transcript: parsed.transcript,
    ))
case "hook":
    // Called by agents' hooks on every event: read the payload, report, never fail the agent.
    guard arguments.count > 1, let reporter = Agents.hookReporter(named: arguments[1]) else { exit(0) }
    let (session, _) = sessionAndWords([])
    guard let payload = HookInput.read(), let hook = reporter.hookReport(from: payload) else { exit(0) }
    var words: (words: String?, group: String?) = (nil, nil)
    if case let .began(activity) = hook.activity {
        words = (activity.words, activity.group)
    }
    report(ControlRequest(
        cmd: .status, session: session, state: hook.changesState ? hook.state.reportName : nil, message: hook.message,
        agent: reporter.kind.rawValue, agentSession: hook.agentSessionID, transcript: hook.transcriptPath,
        shells: hook.backgroundShells > 0 ? hook.backgroundShells : nil, compaction: hook.compaction?.reportName,
        activity: hook.activity?.reportName, activityWords: words.words, activityGroup: words.group,
    ))
case "search", "s":
    let query = arguments.dropFirst().joined(separator: " ")
    // A long wait is allowed: a cold index takes Calm more than ten seconds to search.
    let answer = Result { try ControlClient.send(ControlRequest(cmd: .search, query: query), timeout: 15) }
    let hits: [ControlResponse.SearchHit]
    switch SearchRoute.from(answer) {
    case let .results(found):
        hits = found
    case let .refused(error):
        fail(error)
    case let .index(notice):
        if let notice {
            warn(notice)
        }
        hits = searchIndex(query)
    }
    let styled = isatty(STDOUT_FILENO) == 1
    for hit in hits {
        CLIOutput.lines(for: hit, now: .now, styled: styled).forEach { print($0) }
    }
case "notify":
    let (session, words) = sessionAndWords(Array(arguments.dropFirst()))
    guard !words.isEmpty else { fail("give a message", code: 64) }
    report(ControlRequest(cmd: .notify, session: session, message: words.joined(separator: " ")))
case "config":
    ConfigCommand.run(Array(arguments.dropFirst()))
case "fork":
    ForkCommand.run(Array(arguments.dropFirst()))
case "show":
    ShowCommand.run(Array(arguments.dropFirst()))
case "doctor":
    DoctorCommand.run(Array(arguments.dropFirst()), cliVersion: version)
case "trace":
    TraceCommand.run(Array(arguments.dropFirst()))
default:
    fail("unknown command '\(arguments[0])'\n\n\(usage)", code: 64)
}
