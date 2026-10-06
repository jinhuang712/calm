@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct ClaudeCodeTranscriptTests {
    private let adapter = ClaudeCodeAdapter()
    private let sessionID = "4f6b2c1e-0000-4000-8000-000000000001"

    /// A temporary home laid out like `~/.claude`, from the fixtures.
    private func makeHome(tasks: Bool = true) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-claude-\(UUID().uuidString)")
        let claude = home.appending(path: ".claude")
        func copy(_ fixture: String, to path: String) throws {
            let source = try #require(Bundle.module.url(forResource: fixture, withExtension: nil, subdirectory: "Fixtures/claude-code"))
            let destination = claude.appending(path: path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: destination)
        }
        try copy("transcript.jsonl", to: "projects/-Users-me-src-app/\(sessionID).jsonl")
        try copy("session-4242.json", to: "sessions/4242.json")
        if tasks {
            for index in 1 ... 3 {
                try copy("task-\(index).json", to: "tasks/\(sessionID)/\(index).json")
            }
        }
        return home
    }

    @Test func `finds the transcript from the agent's process`() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let found = try #require(adapter.transcript(forProcess: 4242, home: home))
        #expect(found.agentSessionID == sessionID)
        #expect(found.url.lastPathComponent == "\(sessionID).jsonl")
        #expect(adapter.transcript(forProcess: 1, home: home) == nil)
    }

    @Test func `reads title, recap, step and progress`() throws {
        let home = try makeHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = home.appending(path: ".claude/projects/-Users-me-src-app/\(sessionID).jsonl")
        let tail = try #require(adapter.readTail(of: transcript, agentSessionID: nil, home: home))
        // A title the user set wins over the generated one.
        #expect(tail.title == "login test")
        #expect(tail.lastMessage == "Fixed the login test. The mock returned an expired token; it now uses a fresh one.")
        #expect(tail.step == "Fixing the token mock")
        #expect(tail.progress == TodoProgress(done: 1, total: 3))
        #expect(tail.interrupted == false)
        #expect(tail.directory == "/Users/me/src/app")
    }

    @Test func `the folder is where Claude is now, not where it started`() throws {
        let url = try #require(Bundle.module.url(
            forResource: "transcript-worktree",
            withExtension: "jsonl",
            subdirectory: "Fixtures/claude-code",
        ))
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: FileManager.default.temporaryDirectory))
        // The records after the move say so; the ones after them (last-prompt, ai-title) have no folder.
        #expect(tail.directory == "/Users/me/src/app/.claude/worktrees/dark-mode")
        #expect(tail.lastMessage == "Added the toggle in the worktree.")
        #expect(tail.title == "Add dark mode toggle")
    }

    @Test func `a transcript that never names a folder has none`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let records: [[String: Any]] = [
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": "Hello."]]]],
            ["type": "user", "cwd": "", "message": ["role": "user", "content": "hi"]],
        ]
        let transcript = folder.appending(path: "t.jsonl")
        let lines = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data("\n".utf8) }
        try lines.reduce(Data(), +).write(to: transcript)
        let tail = try #require(adapter.readTail(of: transcript, agentSessionID: sessionID, home: folder))
        #expect(tail.directory == nil)
    }

    @Test func `the recap is what Claude said, without its Markdown`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // Two text blocks, as a turn that spoke before and after a tool call.
        let record: [String: Any] = [
            "type": "assistant",
            "message": ["role": "assistant", "content": [
                ["type": "text", "text": "## Short answer"],
                ["type": "text", "text": "Nothing looks broken. Two things on that card are easy to misread."],
            ]],
        ]
        let transcript = folder.appending(path: "t.jsonl")
        try (JSONSerialization.data(withJSONObject: record) + Data("\n".utf8)).write(to: transcript)
        let tail = try #require(adapter.readTail(of: transcript, agentSessionID: sessionID, home: folder))
        #expect(tail.lastMessage == "Nothing looks broken. Two things on that card are easy to misread.")
    }

    @Test func `no todos means no progress`() throws {
        let home = try makeHome(tasks: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let transcript = home.appending(path: ".claude/projects/-Users-me-src-app/\(sessionID).jsonl")
        let tail = try #require(adapter.readTail(of: transcript, agentSessionID: sessionID, home: home))
        #expect(tail.progress == nil)
        #expect(tail.step == nil)
    }

    @Test func `an interrupted turn is noticed`() throws {
        let url = try #require(Bundle.module.url(
            forResource: "transcript-interrupted",
            withExtension: "jsonl",
            subdirectory: "Fixtures/claude-code",
        ))
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: FileManager.default.temporaryDirectory))
        #expect(tail.interrupted)
        #expect(tail.title == "Refactor the parser")
        #expect(tail.lastMessage == "Starting with the tokenizer.")
    }

    @Test func `the summary is Claude's recap after its last message, without its hint`() throws {
        let url = try #require(Bundle.module.url(
            forResource: "transcript-recap",
            withExtension: "jsonl",
            subdirectory: "Fixtures/claude-code",
        ))
        let tail = try #require(adapter.readTail(of: url, agentSessionID: nil, home: FileManager.default.temporaryDirectory))
        // Plain text, like every recap: the backticks around `main` go too.
        let summary = "You're choosing a cache library, and we've narrowed it to two. Next, benchmark the first one against main."
        #expect(tail.summary == summary)
        // The latest message is still read: a card that isn't idle shows it.
        #expect(tail.lastMessage == "Caveats on the second option: It hasn't been released since spring.")
        #expect(tail.title == "Pick a cache library")
    }

    @Test func `a recap older than the latest turn is no summary`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-claude-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let records: [[String: Any]] = [
            ["type": "assistant", "message": ["role": "assistant", "content": [["type": "text", "text": "Picked the first one."]]]],
            ["type": "system", "subtype": "away_summary", "content": "You're choosing a cache library. (disable recaps in /config)"],
            ["type": "user", "message": ["role": "user", "content": "now benchmark it"]],
        ]
        let transcript = folder.appending(path: "t.jsonl")
        let lines = try records.map { try JSONSerialization.data(withJSONObject: $0) + Data("\n".utf8) }
        try lines.reduce(Data(), +).write(to: transcript)
        let tail = try #require(adapter.readTail(of: transcript, agentSessionID: sessionID, home: folder))
        #expect(tail.summary == nil)
        #expect(tail.lastMessage == "Picked the first one.")
    }

    @Test func `a recap reads the same with or without the hint`() {
        #expect(ClaudeCodeAdapter.summary("Next, ship it. (disable recaps in /config)") == "Next, ship it.")
        #expect(ClaudeCodeAdapter.summary("Next, ship it.") == "Next, ship it.")
        #expect(ClaudeCodeAdapter.summary("(disable recaps in /config)") == nil)
        #expect(ClaudeCodeAdapter.summary(nil) == nil)
    }

    @Test func `project folders replace every other character with a hyphen`() {
        #expect(ClaudeCodeAdapter.projectFolder(for: "/Users/me/src/app") == "-Users-me-src-app")
        #expect(ClaudeCodeAdapter
            .projectFolder(for: "/Users/me/dev/apps/calm/.claude/worktrees/m0") == "-Users-me-dev-apps-calm--claude-worktrees-m0")
    }

    @Test func `missing or broken files read as nothing`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).jsonl")
        #expect(adapter.readTail(of: missing, agentSessionID: nil, home: missing) == nil)
        let broken = FileManager.default.temporaryDirectory.appending(path: "broken-\(UUID().uuidString).jsonl")
        try Data("not json\n{also not".utf8).write(to: broken)
        defer { try? FileManager.default.removeItem(at: broken) }
        #expect(adapter.readTail(of: broken, agentSessionID: nil, home: broken) == nil)
    }

    /// Opt-in check against a real transcript (CALM_REAL_CLAUDE_TRANSCRIPT=<path>): prints only
    /// which fields were found and their lengths, never content.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_CLAUDE_TRANSCRIPT"] != nil))
    func `reads a real transcript`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CALM_REAL_CLAUDE_TRANSCRIPT"])
        let tail = try #require(adapter.readTail(
            of: URL(filePath: path), agentSessionID: nil, home: FileManager.default.homeDirectoryForCurrentUser,
        ))
        let progress = tail.progress.map { "\($0.done)/\($0.total)" } ?? "none"
        print("real transcript: title \(tail.title?.count ?? -1) chars, recap \(tail.lastMessage?.count ?? -1) chars")
        print("real transcript: step \(tail.step != nil), progress \(progress), interrupted \(tail.interrupted)")
        print("real transcript: folder \(tail.directory?.count ?? -1) chars, summary \(tail.summary?.count ?? -1) chars")
        #expect(tail.title != nil)
        #expect(tail.lastMessage != nil)
        #expect(tail.directory != nil)
    }

    // Compaction fixtures: what Claude Code 2.1.291 wrote against a stand-in API (README).

    private func compactionTail(_ name: String) throws -> TranscriptTail {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/claude-code"))
        return try #require(adapter.readTail(of: url, agentSessionID: nil, home: FileManager.default.temporaryDirectory))
    }

    private func date(_ text: String) throws -> Date {
        try #require(ClaudeCodeAdapter.date(of: ["timestamp": text]))
    }

    @Test func `the last reply's context is what a compaction starts from`() throws {
        let tail = try compactionTail("transcript-compacting")
        // input + cache creation + cache read + output, of the reply before Claude compacts.
        #expect(tail.contextTokens == 985_010)
        // The /compact earlier in the conversation, with its sizes.
        #expect(try tail.lastCompaction == CompactedContext(date: date("2026-10-06T15:42:47.166Z"), tokensBefore: 5010, tokensAfter: 1165))
    }

    @Test func `a compaction that finished is recorded, and its summary is no message`() throws {
        let tail = try compactionTail("transcript-compacted")
        let recorded = try CompactedContext(date: date("2026-10-06T15:43:09.829Z"), tokensBefore: 985_037, tokensAfter: 1192)
        #expect(tail.lastCompaction == recorded)
        // The prompt before it began: the summary it left is part of it.
        #expect(try tail.newestMessageAt == date("2026-10-06T15:43:05.296Z"))
        #expect(tail.contextTokens == 985_010)
        #expect(tail.lastMessage == "Here is the big answer.")
    }

    @Test func `one cancelled with Esc leaves a message and no record`() throws {
        let tail = try compactionTail("transcript-compact-cancelled")
        #expect(tail.lastCompaction == nil)
        #expect(try tail.newestMessageAt == date("2026-10-06T15:44:49.570Z"))
    }

    @Test func `timestamps read with and without milliseconds`() throws {
        #expect(try abs(date("2026-10-06T15:44:49.570Z").timeIntervalSince(date("2026-10-06T15:44:49Z")) - 0.57) < 0.001)
        #expect(ClaudeCodeAdapter.date(of: ["timestamp": "yesterday"]) == nil)
    }
}
