import CalmAgents
import CalmModel
@testable import CalmSearch
import Foundation
import Testing

struct SearchIndexTests {
    /// A temporary home with transcripts, and an index in it.
    private final class Fixture {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-search-\(UUID().uuidString)")
        lazy var index = try! SearchIndex(url: home.appending(path: "index.sqlite")) // swiftlint:disable:this force_try

        func write(_ relativePath: String, _ lines: [String], modified: Date? = nil) throws {
            let url = home.appending(path: relativePath)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
            if let modified {
                try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
            }
        }

        func append(_ relativePath: String, _ line: String) throws {
            let handle = try FileHandle(forWritingTo: home.appending(path: relativePath))
            try handle.seekToEnd()
            try handle.write(contentsOf: Data((line + "\n").utf8))
            try handle.close()
        }

        deinit {
            try? FileManager.default.removeItem(at: home)
        }
    }

    private static func claudeUser(_ text: String, cwd: String = "/Users/me/src/app") -> String {
        #"{"type":"user","sessionId":"S","cwd":"\#(cwd)","message":{"role":"user","content":"\#(text)"}}"#
    }

    private static func claudeAgent(_ text: String) -> String {
        #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"\#(text)"}]}}"#
    }

    private static func claudeTool(_ output: String) -> String {
        #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t","content":"\#(output)"}]}}"#
    }

    private func makeFixture() throws -> Fixture {
        let fixture = Fixture()
        try fixture.write(".claude/projects/-a/one.jsonl", [
            #"{"type":"custom-title","customTitle":"zmx persistence"}"#,
            Self.claudeUser("how does zmx keep shells alive?"),
            Self.claudeAgent("It detaches the client; the daemon keeps the shell."),
            Self.claudeTool("SECRET_TOOL_OUTPUT build log"),
            Self.claudeUser("and the sidebar notifications?"),
        ])
        try fixture.write(".claude/projects/-b/two.jsonl", [
            Self.claudeUser("把终端的主题换成深色", cwd: "/Users/me/src/site"),
            Self.claudeAgent("终端主题已更新，审核记录也已处理。"),
        ])
        try fixture.write(".codex/sessions/2026/09/27/rollout-1.jsonl", [
            #"{"type":"session_meta","payload":{"id":"C1","cwd":"/Users/me/src/api"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","#
                + #""content":[{"type":"input_text","text":"the sidebar looks wrong"}]}}"#,
        ])
        try fixture.write(".claude/projects/-a/one/subagents/agent-1.jsonl", [Self.claudeUser("zmx in a subagent")])
        _ = fixture.index.update(home: fixture.home)
        return fixture
    }

    @Test func `finds sessions by English, partial words and Chinese`() throws {
        let fixture = try makeFixture()
        #expect(fixture.index.search("zmx").map(\.title) == ["zmx persistence"])
        #expect(fixture.index.search("notif").count == 1) // part of "notifications"
        #expect(fixture.index.search("审核记录").count == 1) // four characters: FTS5
        #expect(fixture.index.search("终端").count == 1) // two characters: LIKE
        #expect(fixture.index.search("sidebar").count == 2)
    }

    @Test func `every term must appear somewhere in the session`() throws {
        let fixture = try makeFixture()
        // "zmx" and "sidebar" are in different messages of the same session.
        let both = fixture.index.search("zmx sidebar")
        #expect(both.map(\.title) == ["zmx persistence"])
        #expect(fixture.index.search("zmx 深色").isEmpty)
    }

    @Test func `tool output and subagents are not searched`() throws {
        let fixture = try makeFixture()
        #expect(fixture.index.search("SECRET_TOOL_OUTPUT").isEmpty)
        #expect(fixture.index.counts().sessions == 3)
    }

    @Test func `snippets mark the match and results carry session details`() throws {
        let fixture = try makeFixture()
        let result = try #require(fixture.index.search("daemon").first)
        #expect(result.snippet.contains("\u{2}daemon\u{3}"))
        #expect(result.agent == .claudeCode)
        #expect(result.agentSessionID == "S")
        #expect(result.directory == "/Users/me/src/app")
        let codex = try #require(fixture.index.search("looks wrong").first)
        #expect(codex.agent == .codex)
        #expect(codex.title == "the sidebar looks wrong") // no title: the first prompt
        #expect(fixture.index.search("主题").first?.snippet.contains("\u{2}主题\u{3}") == true)
    }

    @Test func `indexing is incremental`() throws {
        let fixture = try makeFixture()
        #expect(fixture.index.update(home: fixture.home).filesUpdated == 0)
        try fixture.append(".claude/projects/-b/two.jsonl", Self.claudeAgent("tokenizer benchmark done"))
        let stats = fixture.index.update(home: fixture.home)
        #expect(stats.filesUpdated == 1)
        #expect(stats.messagesAdded == 1)
        #expect(fixture.index.search("tokenizer").count == 1)
    }

    @Test func `a rewritten file is read again, a removed one is forgotten`() throws {
        let fixture = try makeFixture()
        try fixture.write(".claude/projects/-a/one.jsonl", [Self.claudeUser("short")])
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("zmx").isEmpty)
        #expect(fixture.index.search("short").count == 1)
        try FileManager.default.removeItem(at: fixture.home.appending(path: ".codex"))
        #expect(fixture.index.update(home: fixture.home).filesRemoved == 1)
        #expect(fixture.index.search("sidebar").isEmpty)
    }

    @Test func `recency, titles and the current project lift results`() throws {
        let fixture = Fixture()
        let now = Date()
        try fixture.write(
            ".claude/projects/-x/old.jsonl",
            [Self.claudeUser("deploy notes", cwd: "/work/old")],
            modified: now.addingTimeInterval(-90 * 86400),
        )
        try fixture.write(".claude/projects/-y/new.jsonl", [Self.claudeUser("deploy notes", cwd: "/work/new")], modified: now)
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("deploy", now: now).map(\.directory) == ["/work/new", "/work/old"])
        // The current project ranks slightly higher (UIUX.md): enough to beat a few days, not months.
        #expect(fixture.index.search("deploy", currentProject: "/work/old", now: now).first?.directory == "/work/new")
        try fixture.write(
            ".claude/projects/-x/old.jsonl",
            [Self.claudeUser("deploy notes", cwd: "/work/old")],
            modified: now.addingTimeInterval(-3 * 86400),
        )
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("deploy", currentProject: "/work/old", now: now).first?.directory == "/work/old")
        // An empty query lists recent sessions.
        #expect(fixture.index.search("", now: now).map(\.directory) == ["/work/new", "/work/old"])
    }

    @Test func `ranking helpers`() {
        #expect(SearchRanking.relevance(rank: -2, best: -4) == 0.5)
        #expect(SearchRanking.relevance(rank: 0, best: 0) == 1)
        let now = Date()
        #expect(SearchRanking.recency(of: now, now: now) == 1)
        #expect(abs(SearchRanking.recency(of: now.addingTimeInterval(-7 * 86400), now: now) - 0.5) < 0.001)
        #expect(SearchQuery.terms(in: "  zmx   sidebar ") == ["zmx", "sidebar"])
        #expect(SearchQuery.phrase(#"say "hi""#) == #""say ""hi""""#)
        #expect(SearchQuery.likePattern("50%_") == #"%50\%\_%"#)
    }
}
