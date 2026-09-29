@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct TranscriptParserTests {
    private func fixture(_ path: String) throws -> URL {
        let name = (path as NSString).lastPathComponent
        let folder = (path as NSString).deletingLastPathComponent
        return try #require(Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension, withExtension: (name as NSString).pathExtension,
            subdirectory: "Fixtures/\(folder)",
        ))
    }

    private func parse(_ adapter: some TranscriptIndexing, _ path: String) throws -> ([TranscriptMessage], TranscriptInfo) {
        let records = try #require(JSONLReader.read(fixture(path), from: 0)).records
        var info = TranscriptInfo()
        let messages = adapter.messages(in: records, info: &info)
        return (messages, info)
    }

    @Test func `claude code: prompts and answers, no tools or thinking`() throws {
        let (messages, info) = try parse(ClaudeCodeAdapter(), "claude-code/transcript.jsonl")
        #expect(messages == [
            TranscriptMessage(.user, "fix the login test"),
            TranscriptMessage(.agent, "I'll look at the test first."),
            TranscriptMessage(.agent, "Fixed the login test.\n\nThe mock returned an expired token; it now uses a fresh one."),
        ])
        #expect(info.agentSessionID == "4f6b2c1e-0000-4000-8000-000000000001")
        #expect(info.directory == "/Users/me/src/app")
        #expect(info.title == "login test")
        #expect(info.firstPrompt == "fix the login test")
    }

    @Test func `codex: skips its own instructions and injected context`() throws {
        let (messages, info) = try parse(CodexAdapter(), "codex/rollout.jsonl")
        #expect(messages == [
            TranscriptMessage(.user, "why does the rate limiter drop requests?"),
            TranscriptMessage(.agent, "The token bucket refills per second, but bursts above 10 are dropped."),
        ])
        #expect(info.agentSessionID == "019a-codex-0001")
        #expect(info.directory == "/Users/me/src/api")
        #expect(info.title == nil)
        #expect(info.firstPrompt == "why does the rate limiter drop requests?")
    }

    @Test func `pi: text only, with its session name`() throws {
        let (messages, info) = try parse(PiAdapter(), "pi/session.jsonl")
        #expect(messages == [TranscriptMessage(.user, "把首页的主题换成深色"), TranscriptMessage(.agent, "首页已换成深色主题。")])
        #expect(info.agentSessionID == "pi-0001")
        #expect(info.directory == "/Users/me/src/site")
        #expect(info.title == "深色主题")
    }

    @Test func `subagent transcripts are not sessions`() {
        let adapter = ClaudeCodeAdapter()
        #expect(adapter.isTranscript("/Users/me/.claude/projects/-a/abc.jsonl"))
        #expect(!adapter.isTranscript("/Users/me/.claude/projects/-a/abc/subagents/agent-1.jsonl"))
    }

    @Test func `reading resumes after the last complete line`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("{\"a\":1}\n{\"b\":2}\n{\"c\":".utf8).write(to: url)
        let first = try #require(JSONLReader.read(url, from: 0))
        #expect(first.records.count == 2)
        #expect(first.end == 16)
        // The agent finishes the line; the next read picks up only the new record.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("3}\n".utf8))
        try handle.close()
        let second = try #require(JSONLReader.read(url, from: first.end))
        #expect(second.records.count == 1)
        #expect(second.records.first?["c"] as? Int == 3)
        #expect(JSONLReader.read(url, from: second.end)?.records.isEmpty == true)
    }

    @Test func `every searchable agent has folders`() {
        #expect(Set(Agents.indexers.map(\.kind)) == [.claudeCode, .codex, .pi])
        #expect(Agents.indexers.allSatisfy { !$0.transcriptFolders.isEmpty })
    }

    /// Opt-in (CALM_REAL_HISTORY=1): parses this machine's transcripts and prints counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_HISTORY"] != nil))
    func `parses the real history`() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for indexer in Agents.indexers {
            var files = 0
            var messages = 0
            var characters = 0
            for folder in indexer.transcriptFolders {
                let root = home.appending(path: folder)
                let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
                while let url = enumerator?.nextObject() as? URL {
                    guard url.pathExtension == "jsonl", indexer.isTranscript(url.path),
                          let records = JSONLReader.read(url, from: 0)?.records
                    else { continue }
                    var info = TranscriptInfo()
                    let found = indexer.messages(in: records, info: &info)
                    if !found.isEmpty {
                        files += 1
                    }
                    messages += found.count
                    characters += found.reduce(0) { $0 + $1.text.count }
                }
            }
            print("real history \(indexer.kind.rawValue): \(files) files with messages, \(messages) messages, \(characters) characters")
        }
    }
}
