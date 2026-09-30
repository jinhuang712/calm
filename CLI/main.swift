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
  calm search <text>                Search every agent's past sessions
  calm status <state> [message]     Report this session's state (for agents' hooks):
                                    working, needs-you, done, failed or idle
                                    [--agent <name> --transcript <file> --agent-session <id>
                                    say which agent and conversation, for its transcript]
  calm notify <message>             Notify about this session at the next pause
  calm hook <agent>                 Read an agent's hook payload on stdin and report it
                                    (used by the hooks Calm installs; agent: claude-code)
  calm --version                    Print the version
  calm --help                       Show this help

status and notify act on $CALM_SESSION_ID (or --session <id>). Outside Calm, or when
Calm isn't running, they do nothing and exit 0, so hooks are safe in any terminal.
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("calm: \(message)\n".utf8))
    exit(code)
}

/// Sends a request, starting Calm first if it isn't running.
func send(_ request: ControlRequest) -> ControlResponse {
    do {
        return try ControlClient.send(request)
    } catch ControlClient.ClientError.notRunning {
        let launcher = Process()
        launcher.executableURL = URL(filePath: "/usr/bin/open")
        launcher.arguments = ["-g", "-b", "com.jinhuang.calm"]
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
        FileHandle.standardError.write(Data("calm: \(error)\n".utf8))
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

/// One session per result: when, which agent, project, title, then the matching text.
func printSearchHits(_ hits: [ControlResponse.SearchHit]) {
    let styled = isatty(STDOUT_FILENO) == 1
    let bold = styled ? "\u{1B}[1m" : ""
    let dim = styled ? "\u{1B}[2m" : ""
    let reset = styled ? "\u{1B}[0m" : ""
    for hit in hits {
        let age = Date().timeIntervalSince1970 - hit.lastActive
        let when = age < 3600 ? "\(max(Int(age / 60), 0))m" : age < 86400 ? "\(Int(age / 3600))h" : "\(Int(age / 86400))d"
        let project = hit.directory.map { ($0 as NSString).lastPathComponent } ?? "-"
        print("\(dim)\(when)\t\(hit.agent)\t\(project)\(reset)\t\(bold)\(hit.title)\(reset)")
        let snippet = hit.snippet
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{2}", with: bold)
            .replacingOccurrences(of: "\u{3}", with: reset)
        if !snippet.isEmpty {
            print("    \(snippet)")
        }
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
        print("\(session.project)\t\(session.title)\t\(session.state)\t\(session.agent ?? "-")\t\(session.directory)")
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
    let payload = FileHandle.standardInput.readData(ofLength: 4_000_000)
    guard let hook = reporter.hookReport(from: payload) else { exit(0) }
    report(ControlRequest(
        cmd: .status, session: session, state: hook.state.reportName, message: hook.message,
        agent: reporter.kind.rawValue, agentSession: hook.agentSessionID, transcript: hook.transcriptPath,
        shells: hook.backgroundShells > 0 ? hook.backgroundShells : nil,
    ))
case "search", "s":
    let query = arguments.dropFirst().joined(separator: " ")
    var hits: [ControlResponse.SearchHit]
    if let response = try? ControlClient.send(ControlRequest(cmd: .search, query: query), timeout: 15), response.ok {
        hits = response.results ?? []
    } else {
        // Calm isn't running: read the index directly, bringing it up to date first.
        guard let index = try? SearchIndex() else { fail("couldn't open the search index") }
        index.update()
        hits = index.search(query, limit: 20).map { result in
            ControlResponse.SearchHit(
                title: result.title, agent: result.agent.displayName, directory: result.directory,
                lastActive: result.lastActive.timeIntervalSince1970, snippet: result.snippet, transcript: result.transcriptPath,
            )
        }
    }
    printSearchHits(hits)
case "notify":
    let (session, words) = sessionAndWords(Array(arguments.dropFirst()))
    guard !words.isEmpty else { fail("give a message", code: 64) }
    report(ControlRequest(cmd: .notify, session: session, message: words.joined(separator: " ")))
default:
    fail("unknown command '\(arguments[0])'\n\n\(usage)", code: 64)
}
