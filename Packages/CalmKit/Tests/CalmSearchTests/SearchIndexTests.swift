import CalmAgents
import CalmModel
@testable import CalmSearch
import CalmSQLite
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

    @Test func `a rewritten file is read again`() throws {
        let fixture = try makeFixture()
        try fixture.write(".claude/projects/-a/one.jsonl", [Self.claudeUser("short")])
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("zmx").isEmpty)
        #expect(fixture.index.search("short").count == 1)
    }

    @Test func `a deleted transcript stays searchable, marked deleted`() throws {
        let fixture = try makeFixture()
        try FileManager.default.removeItem(at: fixture.home.appending(path: ".codex"))
        #expect(fixture.index.update(home: fixture.home).filesRemoved == 1)
        #expect(fixture.index.update(home: fixture.home).filesRemoved == 0) // counted once
        let codex = try #require(fixture.index.search("looks wrong").first)
        #expect(codex.transcriptDeleted)
        #expect(fixture.index.search("daemon").first?.transcriptDeleted == false)
        // Back on disk: resumable again.
        try fixture.write(".codex/sessions/2026/09/27/rollout-1.jsonl", [
            #"{"type":"session_meta","payload":{"id":"C1","cwd":"/Users/me/src/api"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","#
                + #""content":[{"type":"input_text","text":"the sidebar looks wrong"}]}}"#,
        ])
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("looks wrong").map(\.transcriptDeleted) == [false])
    }

    private static func historyLine(_ text: String, session: String, milliseconds: Int = 1_776_182_341_656) -> String {
        #"{"display":"\#(text)","pastedContents":{},"timestamp":\#(milliseconds),"project":"/Users/me/src/old","sessionId":"\#(session)"}"#
    }

    @Test func `sessions whose transcripts were deleted are found in the prompt history`() throws {
        let fixture = try makeFixture()
        try fixture.write(".claude/history.jsonl", [
            Self.historyLine("/model", session: "OLD"),
            Self.historyLine("why does the pager flicker?", session: "OLD"),
            Self.historyLine("how does zmx keep shells alive?", session: "S"), // has a transcript
        ])
        let stats = fixture.index.update(home: fixture.home)
        #expect(stats.messagesAdded == 1)
        let old = try #require(fixture.index.search("pager").first)
        #expect(old.title == "why does the pager flicker?")
        #expect(old.directory == "/Users/me/src/old")
        #expect(old.agentSessionID == "OLD")
        #expect(old.transcriptDeleted)
        #expect(old.lastActive == Date(timeIntervalSince1970: 1_776_182_341.656))
        #expect(fixture.index.search("/model").isEmpty)
        #expect(fixture.index.search("zmx").count == 1) // not doubled by its history entry

        // Read incrementally, into the same session.
        try fixture.append(".claude/history.jsonl", Self.historyLine("and the scrollbar?", session: "OLD"))
        #expect(fixture.index.update(home: fixture.home).messagesAdded == 1)
        #expect(fixture.index.search("pager scrollbar").count == 1)
        #expect(fixture.index.update(home: fixture.home).messagesAdded == 0)

        // A transcript that turns up later replaces the stand-in.
        try fixture.write(".claude/projects/-c/old.jsonl", [
            #"{"type":"user","sessionId":"OLD","cwd":"/Users/me/src/old","#
                + #""message":{"role":"user","content":"why does the pager flicker?"}}"#,
        ])
        fixture.index.update(home: fixture.home)
        #expect(fixture.index.search("pager").map(\.transcriptDeleted) == [false])
        #expect(fixture.index.search("scrollbar").isEmpty)
    }

    /// `calm show`: one conversation by its agent's id, with what the user and the agent wrote, in order.
    @Test func `a conversation is found by its id, with its messages in order`() throws {
        let fixture = try makeFixture()
        try fixture.write(".claude/projects/-d/three.jsonl", [
            #"{"type":"custom-title","customTitle":"pager flicker"}"#,
            #"{"type":"user","sessionId":"S3","cwd":"/Users/me/src/app","message":{"role":"user","content":"why does it flicker?"}}"#,
            Self.claudeAgent("The pager redraws twice."),
            Self.claudeTool("SECRET_TOOL_OUTPUT"),
            #"{"type":"user","sessionId":"S3","cwd":"/Users/me/src/app","message":{"role":"user","content":"fix it"}}"#,
        ])
        fixture.index.update(home: fixture.home)
        let found = try fixture.index.conversation(id: "S3").get()
        #expect(found.result.title == "pager flicker")
        #expect(found.result.agent == .claudeCode)
        #expect(found.firstPrompt == "why does it flicker?")
        #expect(!found.fromHistory)
        #expect(found.messages == [
            TranscriptMessage(.user, "why does it flicker?"),
            TranscriptMessage(.agent, "The pager redraws twice."),
            TranscriptMessage(.user, "fix it"),
        ])
        #expect(fixture.index.conversation(id: "nope") == .failure(.none))
    }

    /// Two files with one id (the fixture's "S" is in two transcripts): the newer one is the conversation.
    @Test func `two files with one id give the newer one`() throws {
        let fixture = try makeFixture()
        let earlier = Date(timeIntervalSince1970: 1_780_000_000)
        try fixture.write(".claude/projects/-a/one.jsonl", [Self.claudeUser("the older file")], modified: earlier)
        try fixture.write(".claude/projects/-b/two.jsonl", [Self.claudeUser("the newer file")], modified: earlier.addingTimeInterval(60))
        fixture.index.update(home: fixture.home)
        #expect(try fixture.index.conversation(id: "S").get().firstPrompt == "the newer file")
    }

    @Test func `a conversation is found by the start of its id, when only one starts so`() throws {
        let fixture = try makeFixture()
        try fixture.write(".codex/sessions/2026/09/28/rollout-2.jsonl", [
            #"{"type":"session_meta","payload":{"id":"019a7c11-aaaa","cwd":"/Users/me/src/api"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"one"}]}}"#,
        ])
        try fixture.write(".codex/sessions/2026/09/28/rollout-3.jsonl", [
            #"{"type":"session_meta","payload":{"id":"019a7c22-bbbb","cwd":"/Users/me/src/api"}}"#,
            #"{"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"two"}]}}"#,
        ])
        fixture.index.update(home: fixture.home)
        #expect(try fixture.index.conversation(id: "019a7c11").get().firstPrompt == "one")
        #expect(fixture.index.conversation(id: "019a7c") == .failure(.several(["019a7c11-aaaa", "019a7c22-bbbb"])))
        // Too short a start is no match at all, rather than every id that begins so.
        #expect(fixture.index.conversation(id: "019a") == .failure(.none))
    }

    @Test func `a transcript's copy of a conversation wins over the prompt history's`() throws {
        let fixture = try makeFixture()
        try fixture.write(".claude/history.jsonl", [Self.historyLine("why does the pager flicker?", session: "OLD")])
        fixture.index.update(home: fixture.home)
        #expect(try fixture.index.conversation(id: "OLD").get().fromHistory)
        try fixture.write(".claude/projects/-c/old.jsonl", [
            #"{"type":"user","sessionId":"OLD","cwd":"/Users/me/src/old","#
                + #""message":{"role":"user","content":"why does the pager flicker?"}}"#,
        ])
        fixture.index.update(home: fixture.home)
        #expect(try !fixture.index.conversation(id: "OLD").get().fromHistory)
    }

    @Test func `a version 1 index keeps its sessions`() throws {
        let fixture = Fixture()
        let url = fixture.home.appending(path: "v1.sqlite")
        try FileManager.default.createDirectory(at: fixture.home, withIntermediateDirectories: true)
        let old = try SQLiteDatabase(path: url.path)
        try old.execute("""
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE files (id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, agent TEXT NOT NULL,
            offset INTEGER NOT NULL DEFAULT 0, size INTEGER NOT NULL DEFAULT 0, mtime REAL NOT NULL DEFAULT 0,
            session_id TEXT, directory TEXT, title TEXT, first_prompt TEXT, last_active REAL NOT NULL DEFAULT 0);
        CREATE VIRTUAL TABLE messages USING fts5(text, file_id UNINDEXED, role UNINDEXED, tokenize = 'trigram');
        INSERT INTO meta VALUES ('schema', '1');
        INSERT INTO files (id, path, agent, title) VALUES (1, '/gone.jsonl', 'claudeCode', 'kept');
        INSERT INTO messages (text, file_id, role) VALUES ('a message about lanterns', 1, 'user');
        """)
        let index = try SearchIndex(url: url)
        index.update(home: fixture.home) // no transcripts on disk
        let result = try #require(index.search("lanterns").first)
        #expect(result.title == "kept")
        #expect(result.transcriptDeleted)
    }

    @Test func `snippets open just before the match`() {
        let text = String(repeating: "filler words here ", count: 10) + "the needle is here\nand more after it"
        let snippet = SearchQuery.snippet(text, around: "needle")
        #expect(snippet.hasPrefix("…"))
        #expect(snippet.contains("\u{2}needle\u{3} is here and more"))
        let lead = snippet.components(separatedBy: "\u{2}")[0]
        #expect(lead.count <= 30)
        #expect(!lead.dropFirst().hasPrefix(" ")) // starts on a whole word
        #expect(SearchQuery.snippet("Needle first", around: "needle") == "\u{2}Needle\u{3} first")
    }

    @Test func `a folder's recent sessions are the ones inside it, newest first`() throws {
        let fixture = Fixture()
        let now = Date()
        try fixture.write(
            ".claude/projects/-a/old.jsonl", [Self.claudeUser("old", cwd: "/work/app")], modified: now.addingTimeInterval(-86400),
        )
        try fixture.write(".claude/projects/-b/new.jsonl", [Self.claudeUser("new", cwd: "/work/app/web")], modified: now)
        try fixture.write(".claude/projects/-c/other.jsonl", [Self.claudeUser("other", cwd: "/work/application")], modified: now)
        fixture.index.update(home: fixture.home)
        // A folder whose name only starts the same isn't inside it.
        #expect(fixture.index.recent(inside: "/work/app").map(\.directory) == ["/work/app/web", "/work/app"])
        #expect(fixture.index.recent(inside: "/work/app", limit: 1).map(\.directory) == ["/work/app/web"])
        #expect(fixture.index.recent(inside: "/elsewhere").isEmpty)
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

    @Test func `one or two letters match only where a word starts`() throws {
        let fixture = Fixture()
        try fixture.write(".claude/projects/-a/inside.jsonl", [Self.claudeUser("the hardware is fine")])
        try fixture.write(".claude/projects/-b/start.jsonl", [Self.claudeUser("the arrow keys (arrows) move")])
        fixture.index.update(home: fixture.home)
        // "ar" is inside "hardware", and starts "arrow".
        #expect(fixture.index.search("ar").map(\.snippet) == ["the \u{2}ar\u{3}row keys (arrows) move"])
        #expect(fixture.index.search("AR").count == 1)
        // From three letters on, anywhere counts.
        #expect(fixture.index.search("dwa").count == 1)
    }

    @Test func `results bring the messages that hold each word`() throws {
        let fixture = try makeFixture()
        let result = try #require(fixture.index.search("zmx sidebar", lines: true).first)
        #expect(result.lines.map(\.terms) == [["zmx"], ["sidebar"]])
        #expect(result.lines.map(\.text) == ["how does zmx keep shells alive?", "and the sidebar notifications?"])
        #expect(result.lines.allSatisfy { $0.role == .user && !$0.cutBefore })
        let agent = try #require(fixture.index.search("daemon", lines: true).first?.lines.first)
        #expect(agent.role == .agent)
        // Asked for nothing, it brings nothing.
        #expect(fixture.index.search("zmx").first?.lines.isEmpty == true)
    }

    @Test func `a word naming the group counts as found in all of it`() throws {
        let fixture = try makeFixture()
        let name: (String?) -> String? = { $0.map { ($0 as NSString).lastPathComponent } }
        // One's folder is …/src/app: "app" isn't said in it, but names its group.
        #expect(fixture.index.search("app zmx", groupName: name).map(\.title) == ["zmx persistence"])
        #expect(fixture.index.search("site zmx", groupName: name).isEmpty)
        #expect(fixture.index.search("app", groupName: name).count == 1)
        // Without names, words only match what was said.
        #expect(fixture.index.search("app zmx").isEmpty)
        let lines = try #require(fixture.index.search("app zmx", groupName: name, lines: true).first?.lines)
        #expect(lines.map(\.terms) == [["zmx"]])
    }

    @Test func `excerpts keep the stretch around the words`() {
        let text = String(repeating: "filler ", count: 100) + "first word here " + String(repeating: "middle ", count: 10) + "second one"
        let excerpt = SearchQuery.excerpt(text, around: ["first", "second"], margin: 20)
        #expect(excerpt.cutBefore)
        #expect(excerpt.text.hasPrefix("filler filler"))
        #expect(excerpt.text.hasSuffix("second one"))
        #expect(SearchQuery.excerpt("short first", around: ["first"]) == ("short first", false))
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
