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
        #expect(tail.title != nil)
        #expect(tail.lastMessage != nil)
    }
}
