@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct CodexTranscriptTests {
    private let adapter = CodexAdapter()
    private let sessionID = "01a0e957-0881-7db0-b94f-5b490b5b9f77"

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/codex"))
    }

    private func tail(_ name: String) throws -> TranscriptTail {
        try #require(adapter.readTail(of: fixture(name), agentSessionID: nil, home: FileManager.default.temporaryDirectory))
    }

    private static let otherID = "01a0e957-0000-7000-8000-000000000002"

    /// Who started a rollout: the header's `originator`, `source` and `thread_source`, as captured
    /// from real ones (2026-09-29). Under the shared daemon (0.157+) the terminal's own `codex`
    /// says `source: "vscode"`; only `originator` tells it from the desktop app.
    private enum Origin {
        static let terminalUnderDaemon = #""originator":"codex-tui","source":"vscode","thread_source":"user""#
        static let terminalBeforeDaemon = #""originator":"codex-tui","source":"cli","thread_source":"user""#
        static let desktopApp = #""originator":"Codex Desktop","source":"vscode","thread_source":"user""#
        static let subagentOfTerminal = #""originator":"codex-tui","source":{"subagent":{}},"thread_source":"subagent""#
        static let subagentOfApp = #""originator":"Codex Desktop","source":{"subagent":{}},"thread_source":"subagent""#
    }

    private struct Rollout {
        var id: String
        var fixture = "rollout-done"
        var day = "2026/09/29"
        /// Replaces the fixture's header fields (which are `Origin.terminalUnderDaemon`).
        var origin = Origin.terminalUnderDaemon
    }

    /// A temporary home with rollouts copied from fixtures into `.codex/sessions/<day>/`.
    private func makeHome(_ rollouts: [Rollout]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-codex-\(UUID().uuidString)")
        for rollout in rollouts {
            let folder = home.appending(path: ".codex/sessions/\(rollout.day)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var text = try String(contentsOf: fixture(rollout.fixture), encoding: .utf8)
            text = text.replacingOccurrences(of: sessionID, with: rollout.id)
            text = text.replacingOccurrences(of: Origin.terminalUnderDaemon, with: rollout.origin)
            try Data(text.utf8).write(to: folder.appending(path: "rollout-2026-09-29T02-46-30-\(rollout.id).jsonl"))
        }
        return home
    }

    @Test func `a finished turn's last message is the recap`() throws {
        let tail = try tail("rollout-done")
        #expect(tail.lastMessage == "Fixed the login test. The mock returned an expired token; it now uses a fresh one.")
        #expect(tail.interrupted == false)
        #expect(tail.turn == .finished)
        // Codex keeps no title in its rollouts and, in recent ones, no plan.
        #expect(tail.title == nil)
        #expect(tail.step == nil)
        #expect(tail.progress == nil)
    }

    @Test func `a running turn shows the latest thing the agent said`() throws {
        let tail = try tail("rollout-running")
        #expect(tail.lastMessage == "Running the whole suite now.")
        #expect(tail.interrupted == false)
        // The newest turn started and hasn't ended: Codex is working, and says so nowhere else.
        #expect(tail.turn == .inProgress)
    }

    @Test func `an interrupted turn is noticed`() throws {
        let tail = try tail("rollout-interrupted")
        #expect(tail.interrupted)
        #expect(tail.turn == nil) // interrupted, not working: the interruption settles it
        #expect(tail.lastMessage == "Starting with the tokenizer.")
    }

    @Test func `a new prompt after an interruption clears it`() throws {
        let interrupted = try String(contentsOf: fixture("rollout-interrupted"), encoding: .utf8)
        let next = #"{"type":"event_msg","ordinal":6,"timestamp":"2026-09-29T02:51:00.000Z","#
            + #""payload":{"type":"task_started","turn_id":"t2"}}"#
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-codex-\(UUID().uuidString).jsonl")
        try Data((interrupted + next + "\n").utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: url))
        #expect(tail.interrupted == false)
        #expect(tail.turn == .inProgress) // the new prompt's turn
    }

    @Test func `a huge tool output as the newest record doesn't hide the messages before it`() throws {
        // Codex's tool outputs reach megabytes; the recap must still be found.
        let done = try String(contentsOf: fixture("rollout-running"), encoding: .utf8)
        let output = #"{"type":"response_item","ordinal":9,"payload":{"type":"custom_tool_call_output","#
            + #""id":"o2","call_id":"call2","output":""# + String(repeating: "x", count: 3_000_000) + #""}}"#
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-codex-\(UUID().uuidString).jsonl")
        try Data((done + output + "\n").utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: url))
        #expect(tail.lastMessage == "Running the whole suite now.")
    }

    @Test func `missing or broken files read as nothing`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).jsonl")
        #expect(adapter.readTail(of: missing, agentSessionID: nil, home: missing) == nil)
        let broken = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString).jsonl")
        try Data("not json\n{also not".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        #expect(adapter.readTail(of: broken, agentSessionID: nil, home: broken) == nil)
    }

    // MARK: Finding the transcript

    @Test func `the session header gives the id and folder`() throws {
        let head = try #require(CodexAdapter.head(of: fixture("rollout-done")))
        #expect(head.id == sessionID)
        #expect(head.directory == "/Users/me/src/app")
    }

    @Test func `a rollout the process has open is found exactly`() throws {
        let home = try makeHome([Rollout(id: sessionID), Rollout(id: Self.otherID)])
        defer { try? FileManager.default.removeItem(at: home) }
        let opened = home.appending(path: ".codex/sessions/2026/09/29/rollout-2026-09-29T02-46-30-\(sessionID).jsonl")
        // This test process is the "agent": it holds the rollout open, as Codex does while it runs.
        let handle = try FileHandle(forReadingFrom: opened)
        defer { try? handle.close() }
        let facts = ProcessFacts.of(getpid())
        #expect(facts.openFiles.contains { $0.hasSuffix("rollout-2026-09-29T02-46-30-\(sessionID).jsonl") })
        // Two rollouts in the same folder would be ambiguous by folder alone; the open file is not.
        let found = try #require(CodexAdapter.transcript(facts: facts, home: home))
        #expect(found.agentSessionID == sessionID)
        #expect(found.url.lastPathComponent.hasSuffix("\(sessionID).jsonl"))
    }

    @Test func `the only rollout for the folder since the process started is found`() throws {
        let home = try makeHome([Rollout(id: sessionID)])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60))
        let found = try #require(CodexAdapter.transcript(facts: facts, home: home))
        #expect(found.agentSessionID == sessionID)
    }

    @Test func `two rollouts for the folder are ambiguous, so none is chosen`() throws {
        let home = try makeHome([Rollout(id: sessionID), Rollout(id: Self.otherID, fixture: "rollout-running")])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60))
        #expect(CodexAdapter.transcript(facts: facts, home: home) == nil)
    }

    @Test func `another folder, or a rollout older than the process, is not chosen`() throws {
        let home = try makeHome([Rollout(id: sessionID)])
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = ProcessFacts(directory: "/Users/me/src/other", started: Date().addingTimeInterval(-60))
        #expect(CodexAdapter.transcript(facts: elsewhere, home: home) == nil)
        let later = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(3600))
        #expect(CodexAdapter.transcript(facts: later, home: home) == nil)
        #expect(CodexAdapter.transcript(facts: ProcessFacts(), home: home) == nil)
    }

    @Test func `a terminal codex under the shared daemon is found, though its rollout says vscode`() throws {
        // The real case that was missed: Codex 0.159 in a Calm session. Its rollout's `source` is
        // "vscode"; only `originator: "codex-tui"` says it's a terminal.
        let home = try makeHome([Rollout(id: sessionID, origin: Origin.terminalUnderDaemon)])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60), arguments: ["codex", "--yolo"])
        #expect(CodexAdapter.transcript(facts: facts, home: home)?.agentSessionID == sessionID)
    }

    @Test func `a terminal codex from before the daemon is found too`() throws {
        let home = try makeHome([Rollout(id: sessionID, origin: Origin.terminalBeforeDaemon)])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60))
        #expect(CodexAdapter.transcript(facts: facts, home: home)?.agentSessionID == sessionID)
    }

    @Test func `who started a rollout is read from its originator and thread source`() throws {
        func head(_ origin: String) throws -> SessionHead {
            let home = try makeHome([Rollout(id: sessionID, origin: origin)])
            defer { try? FileManager.default.removeItem(at: home) }
            let url = home.appending(path: ".codex/sessions/2026/09/29/rollout-2026-09-29T02-46-30-\(sessionID).jsonl")
            return try #require(CodexAdapter.head(of: url))
        }
        #expect(try head(Origin.terminalUnderDaemon).isTerminalSession)
        #expect(try head(Origin.terminalBeforeDaemon).isTerminalSession)
        #expect(try !head(Origin.desktopApp).isTerminalSession)
        #expect(try !head(Origin.subagentOfTerminal).isTerminalSession)
        #expect(try !head(Origin.subagentOfApp).isTerminalSession)
    }

    @Test func `subagent threads and the desktop app's sessions don't make a folder ambiguous`() throws {
        let home = try makeHome([
            Rollout(id: sessionID),
            Rollout(id: Self.otherID, origin: Origin.subagentOfTerminal),
            Rollout(id: "01a0e957-0000-7000-8000-000000000003", origin: Origin.desktopApp),
            Rollout(id: "01a0e957-0000-7000-8000-000000000004", origin: Origin.subagentOfApp),
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60))
        #expect(CodexAdapter.transcript(facts: facts, home: home)?.agentSessionID == sessionID)
    }

    @Test func `codex resume finds the old rollout by its id`() throws {
        // A resumed conversation appends to its rollout from weeks ago, so the folder date and
        // the process start time say nothing; the id on the command line does.
        let home = try makeHome([
            Rollout(id: sessionID, day: "2026/08/10"),
            Rollout(id: Self.otherID, fixture: "rollout-running"),
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(
            directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60),
            arguments: ["node", "/x/@openai/codex/bin/codex.js", "resume", sessionID],
        )
        #expect(CodexAdapter.transcript(facts: facts, home: home)?.agentSessionID == sessionID)
    }

    @Test func `only resume names the conversation, not fork`() {
        #expect(CodexAdapter.resumedSessionID(in: ["codex", "resume", sessionID]) == sessionID)
        #expect(CodexAdapter.resumedSessionID(in: ["codex", "resume", "--last"]) == nil)
        #expect(CodexAdapter.resumedSessionID(in: ["codex", "fork", sessionID]) == nil)
        #expect(CodexAdapter.resumedSessionID(in: ["codex"]) == nil)
    }

    /// Opt-in survey of every real rollout under a folder (CALM_REAL_CODEX_SESSIONS=<folder>):
    /// prints counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_CODEX_SESSIONS"] != nil))
    func `reads every real rollout`() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["CALM_REAL_CODEX_SESSIONS"])
        let files = TranscriptDiscovery.files(under: URL(filePath: folder), extension: "jsonl", since: nil)
        var headers = 0, terminal = 0, recaps = 0, interrupted = 0, unreadable = 0
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for url in files {
                if let head = CodexAdapter.head(of: url) {
                    headers += 1
                    terminal += head.isTerminalSession ? 1 : 0
                }
                guard let tail = adapter.readTail(of: url, agentSessionID: nil, home: url) else {
                    unreadable += 1
                    continue
                }
                recaps += tail.lastMessage != nil ? 1 : 0
                interrupted += tail.interrupted ? 1 : 0
            }
        }
        print("real rollouts: \(files.count) files, \(headers) headers, \(terminal) terminal sessions")
        print("real rollouts: \(recaps) with a recap, \(interrupted) interrupted, \(unreadable) unreadable, \(elapsed) in all")
        #expect(headers == files.count)
        #expect(unreadable == 0)
    }

    /// Opt-in check of a real running Codex (CALM_REAL_CODEX_PID=<pid>): whether its rollout is
    /// found from the process, and what it reads; prints no content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_CODEX_PID"] != nil))
    func `finds the rollout of a real running codex`() throws {
        let pid = try #require(ProcessInfo.processInfo.environment["CALM_REAL_CODEX_PID"].flatMap { Int32($0) })
        let facts = ProcessFacts.of(pid)
        let found = CodexAdapter.transcript(facts: facts, home: FileManager.default.homeDirectoryForCurrentUser)
        print(
            "real codex: folder known \(facts.directory != nil), start known \(facts.started != nil), open files \(facts.openFiles.count)",
        )
        let tail = found.flatMap { adapter.readTail(of: $0.url, agentSessionID: nil, home: $0.url) }
        print("real codex: found \(found != nil), recap \(tail?.lastMessage?.count ?? -1) chars, interrupted \(tail?.interrupted ?? false)")
        #expect(found != nil)
    }

    /// Opt-in check against a real rollout (CALM_REAL_CODEX_ROLLOUT=<path>): prints only which
    /// fields were found and their lengths, never content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_CODEX_ROLLOUT"] != nil))
    func `reads a real rollout`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CALM_REAL_CODEX_ROLLOUT"])
        let url = URL(filePath: path)
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: FileManager.default.homeDirectoryForCurrentUser))
        print("real rollout: recap \(tail.lastMessage?.count ?? -1) chars, interrupted \(tail.interrupted)")
        print("real rollout: header \(CodexAdapter.head(of: url) != nil)")
        #expect(tail.lastMessage != nil)
        #expect(CodexAdapter.head(of: url) != nil)
    }
}
