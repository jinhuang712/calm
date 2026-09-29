import CalmAgents
import CalmModel
@testable import CalmSearch
import CalmSQLite
import Foundation
import Testing

/// OpenCode's history in search (FEATURES.md → F7): one database of OpenCode's own, shaped like
/// 2.0.19's (the columns Calm reads; the real tables have more).
struct OpenCodeSearchTests {
    private static let schema = """
    CREATE TABLE session_v2 (id TEXT PRIMARY KEY, directory TEXT NOT NULL, title TEXT NOT NULL, parent_id TEXT,
      fork_session_id TEXT, time_archived INTEGER, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
    CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
    """

    private final class Fixture {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-search-\(UUID().uuidString)")
        lazy var index = try! SearchIndex(url: home.appending(path: "index.sqlite")) // swiftlint:disable:this force_try
        let database: SQLiteDatabase
        var url: URL {
            home.appending(path: ".local/share/opencode/opencode.db")
        }

        init() throws {
            let folder = home.appending(path: ".local/share/opencode")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            database = try SQLiteDatabase(path: folder.appending(path: "opencode.db").path)
            try database.execute(OpenCodeSearchTests.schema)
        }

        func session(
            _ id: String,
            title: String = "Untitled",
            directory: String = "/Users/me/src/app",
            parent: String? = nil,
            fork: String? = nil,
            created: Int64 = 1000,
        ) throws {
            try database.query(
                """
                INSERT INTO session_v2 (id, directory, title, parent_id, fork_session_id, time_created, time_updated)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(id),
                    .text(directory),
                    .text(title),
                    parent.map { .text($0) } ?? .null,
                    fork.map { .text($0) } ?? .null,
                    .integer(created),
                    .integer(created),
                ],
            )
        }

        private var seq: Int64 = 0

        func message(_ session: String, _ type: String, _ json: String, created: Int64 = 2000, updated: Int64? = nil) throws {
            seq += 1
            try database.query(
                "INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data) VALUES (?, ?, ?, ?, ?, ?, ?)",
                [
                    .text("msg_\(seq)"),
                    .text(session),
                    .text(type),
                    .integer(seq),
                    .integer(created),
                    .integer(updated ?? created),
                    .text(json),
                ],
            )
        }

        func user(_ session: String, _ text: String, created: Int64 = 2000) throws {
            try message(session, "user", #"{"text":\#(Self.json(text)),"files":[{"data":"iVBORw0K"}]}"#, created: created)
        }

        func agent(_ session: String, _ text: String, created: Int64 = 3000) throws {
            let blocks = [
                #"{"type":"reasoning","text":"SECRET_REASONING"}"#,
                #"{"type":"text","text":\#(Self.json(text))}"#,
                #"{"type":"tool","name":"shell","state":{"content":[{"type":"text","text":"SECRET_TOOL_OUTPUT"}]}}"#,
            ]
            try message(session, "assistant", #"{"content":[\#(blocks.joined(separator: ","))]}"#, created: created)
        }

        static func json(_ text: String) -> String {
            String(data: (try? JSONEncoder().encode(text)) ?? Data(), encoding: .utf8) ?? "\"\""
        }

        @discardableResult
        func update() -> IndexStats {
            index.update(home: home, indexers: [], databaseIndexers: [OpenCodeAdapter()])
        }

        deinit {
            try? FileManager.default.removeItem(at: home)
        }
    }

    @Test func `finds what the user and the agent wrote, and nothing else`() throws {
        let fixture = try Fixture()
        try fixture.session("ses_a", title: "Flaky login test")
        try fixture.user("ses_a", "why does the login test flake on CI?")
        try fixture.agent("ses_a", "The mock clock drifts; freeze it in setUp.")
        try fixture.message("ses_a", "synthetic", #"{"text":"SECRET_SHELL_OUTPUT"}"#)
        try fixture.message("ses_a", "idle", #"{"outcome":"succeeded"}"#)
        try fixture.update()

        let results = fixture.index.search("mock clock")
        #expect(results.count == 1)
        #expect(results.first?.agent == .openCode)
        #expect(results.first?.agentSessionID == "ses_a")
        #expect(results.first?.title == "Flaky login test")
        #expect(results.first?.directory == "/Users/me/src/app")
        #expect(results.first?.transcriptDeleted == false)
        #expect(fixture.index.search("flake on CI").count == 1)
        for hidden in ["SECRET_REASONING", "SECRET_TOOL_OUTPUT", "SECRET_SHELL_OUTPUT", "iVBORw0K"] {
            #expect(fixture.index.search(hidden).isEmpty, "\(hidden) was indexed")
        }
    }

    @Test func `subagents, empty sessions and placeholder titles`() throws {
        let fixture = try Fixture()
        try fixture.session("ses_root", title: "New session - 2026-09-30T01:02:03")
        try fixture.user("ses_root", "rename the sidebar footer rows")
        try fixture.session("ses_child", parent: "ses_root")
        try fixture.user("ses_child", "SUBAGENT_PROMPT")
        try fixture.session("ses_empty")
        try fixture.update()

        #expect(fixture.index.search("SUBAGENT_PROMPT").isEmpty)
        #expect(fixture.index.counts().sessions == 1)
        // The placeholder isn't a title: the first prompt stands in.
        #expect(fixture.index.search("sidebar footer").first?.title == "rename the sidebar footer rows")
    }

    @Test func `a fork's copied messages are found once, in the session they came from`() throws {
        let fixture = try Fixture()
        try fixture.session("ses_parent", title: "Parent", created: 1000)
        try fixture.user("ses_parent", "plan the zmx upgrade", created: 2000)
        try fixture.session("ses_fork", title: "Fork", fork: "ses_parent", created: 5000)
        try fixture.user("ses_fork", "plan the zmx upgrade", created: 2000) // copied, written before the fork
        try fixture.user("ses_fork", "now try the other branch", created: 6000)
        try fixture.update()

        #expect(fixture.index.search("zmx upgrade").map(\.agentSessionID) == ["ses_parent"])
        #expect(fixture.index.search("other branch").map(\.agentSessionID) == ["ses_fork"])
    }

    @Test func `sessions are read again when they change, and kept when they're gone`() throws {
        let fixture = try Fixture()
        try fixture.session("ses_a", title: "Themes")
        try fixture.user("ses_a", "soften the theme colors")
        #expect(fixture.update().filesUpdated == 1)
        // Nothing changed: nothing is read.
        #expect(fixture.update().filesUpdated == 0)

        // A new message, and one rewritten in place (OpenCode does both).
        try fixture.agent("ses_a", "Lowered the saturation.", created: 4000)
        try fixture.database.query(
            "UPDATE session_message SET data = ?, time_updated = 5000 WHERE seq = 1",
            [.text(#"{"text":"calmer palette please"}"#)],
        )
        #expect(fixture.update().filesUpdated == 1)
        #expect(fixture.index.search("saturation").count == 1)
        #expect(fixture.index.search("calmer palette").count == 1)
        #expect(fixture.index.search("soften").isEmpty)
        #expect(fixture.index.counts().messages == 2)

        // Deleted in OpenCode: still found, marked gone, so it isn't offered for resuming.
        try fixture.database.query("DELETE FROM session_v2 WHERE id = 'ses_a'")
        #expect(fixture.update().filesRemoved == 1)
        #expect(fixture.index.search("saturation").first?.transcriptDeleted == true)
    }

    @Test func `no database, or one of another shape, reads as nothing`() throws {
        let fixture = try Fixture()
        try fixture.database.execute("DROP TABLE session_message")
        #expect(fixture.update().filesSeen == 0)
        let empty = SearchIndexTestsHome()
        #expect(empty.index.update(home: empty.home, indexers: [], databaseIndexers: [OpenCodeAdapter()]).filesSeen == 0)
    }

    /// Opt-in: the real database, indexed into a temporary index (CALM_REAL_OPENCODE_DB=<path to
    /// opencode.db>). Prints counts and timings only, never text.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_OPENCODE_DB"] != nil))
    func `real opencode history indexes quickly`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CALM_REAL_OPENCODE_DB"])
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-real-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = home.appending(path: ".local/share/opencode")
        try FileManager.default.createDirectory(at: folder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: folder, withDestinationURL: URL(filePath: path).deletingLastPathComponent())
        let index = try SearchIndex(url: home.appending(path: "index.sqlite"))
        let clock = ContinuousClock()
        var first = IndexStats()
        let full = clock.measure { first = index.update(home: home, indexers: [], databaseIndexers: [OpenCodeAdapter()]) }
        var second = IndexStats()
        let idle = clock.measure { second = index.update(home: home, indexers: [], databaseIndexers: [OpenCodeAdapter()]) }
        let counts = index.counts()
        print("opencode real: \(first.filesSeen) sessions seen, \(counts.sessions) indexed, \(counts.messages) messages")
        print("opencode real: first \(full), again \(idle) (\(second.filesUpdated) re-read)")
        #expect(counts.sessions > 0)
    }
}

/// A home with nothing in it.
private final class SearchIndexTestsHome {
    let home = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-none-\(UUID().uuidString)")
    lazy var index = try! SearchIndex(url: home.appending(path: "index.sqlite")) // swiftlint:disable:this force_try

    deinit {
        try? FileManager.default.removeItem(at: home)
    }
}
