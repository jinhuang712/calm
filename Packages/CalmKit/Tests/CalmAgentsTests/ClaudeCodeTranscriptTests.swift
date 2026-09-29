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
        print("real transcript: folder \(tail.directory?.count ?? -1) chars")
        #expect(tail.title != nil)
        #expect(tail.lastMessage != nil)
        #expect(tail.directory != nil)
    }
}
