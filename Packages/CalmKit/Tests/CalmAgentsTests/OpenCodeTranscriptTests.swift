@testable import CalmAgents
import CalmModel
import CalmSQLite
import Foundation
import Testing

struct OpenCodeTranscriptTests {
    private let adapter = OpenCodeAdapter()

    /// The columns of OpenCode 2.0.18's tables that Calm reads (the real ones have more).
    private static let schema = """
    CREATE TABLE session_v2 (id TEXT PRIMARY KEY, project_id TEXT NOT NULL DEFAULT 'p', directory TEXT NOT NULL,
      title TEXT NOT NULL, parent_id TEXT, time_archived INTEGER, time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL);
    CREATE TABLE session_message (id TEXT PRIMARY KEY, session_id TEXT NOT NULL, type TEXT NOT NULL, seq INTEGER NOT NULL,
      time_created INTEGER NOT NULL, time_updated INTEGER NOT NULL, data TEXT NOT NULL);
    """

    private struct Message {
        var type: String
        var json: String
    }

    private static let now = Int64(Date().timeIntervalSince1970 * 1000)

    private static let user = Message(type: "user", json: #"{"text":"Fix the flaky login test","time":{"created":1}}"#)
    private static let idle = Message(type: "idle", json: #"{"outcome":"succeeded","time":{"created":1}}"#)
    private static let interrupted = Message(type: "idle", json: #"{"outcome":"interrupted","time":{"created":1}}"#)
    private static func assistant(_ text: String?) -> Message {
        var blocks = [#"{"type":"reasoning","text":"Thinking","state":"done","time":{}}"#]
        if let text {
            blocks.append(#"{"type":"text","text":\#(json(text))}"#)
        }
        blocks.append(#"{"type":"tool","id":"t1","name":"shell","state":{},"executed":true,"time":{}}"#)
        return Message(
            type: "assistant",
            json: #"{"agent":"build","content":[\#(blocks.joined(separator: ","))],"finish":"stop","time":{}}"#,
        )
    }

    private static func json(_ text: String) -> String {
        String(data: (try? JSONEncoder().encode(text)) ?? Data(), encoding: .utf8) ?? "\"\""
    }

    private struct Session {
        var id = "ses_a"
        var directory = "/Users/me/src/app"
        var title = "Fix the login test"
        var parent: String?
        var archived = false
        var updated = OpenCodeTranscriptTests.now
        var messages: [Message] = []
    }

    /// A temporary home with OpenCode's database holding `sessions`.
    private func makeHome(_ sessions: [Session]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-\(UUID().uuidString)")
        let folder = home.appending(path: ".local/share/opencode")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let database = try SQLiteDatabase(path: folder.appending(path: "opencode.db").path)
        try database.execute(Self.schema)
        for session in sessions {
            try database.query(
                """
                INSERT INTO session_v2 (id, directory, title, parent_id, time_archived, time_created, time_updated)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                [
                    .text(session.id), .text(session.directory), .text(session.title),
                    session.parent.map { .text($0) } ?? .null, session.archived ? .integer(Self.now) : .null,
                    .integer(Self.now), .integer(session.updated),
                ],
            )
            for (index, message) in session.messages.enumerated() {
                try database.query(
                    """
                    INSERT INTO session_message (id, session_id, type, seq, time_created, time_updated, data)
                    VALUES (?, ?, ?, ?, ?, ?, ?)
                    """,
                    [
                        .text("\(session.id)-\(index)"), .text(session.id), .text(message.type), .integer(Int64(index + 1)),
                        .integer(Self.now), .integer(Self.now), .text(message.json),
                    ],
                )
            }
        }
        return home
    }

    private func tail(_ session: Session) throws -> TranscriptTail {
        let home = try makeHome([session])
        defer { try? FileManager.default.removeItem(at: home) }
        return try #require(adapter.readTail(of: OpenCodeAdapter.database(in: home), agentSessionID: session.id, home: home))
    }

    @Test func `a finished turn: the agent's last words and the session's title`() throws {
        let tail = try tail(Session(messages: [
            Self.user,
            Self.assistant("Fixed the login test.\n\nThe mock returned an expired token."),
            Self.idle,
        ]))
        #expect(tail.title == "Fix the login test")
        #expect(tail.lastMessage == "Fixed the login test. The mock returned an expired token.")
        #expect(tail.interrupted == false)
        #expect(tail.turn == .finished)
        #expect(tail.step == nil)
        #expect(tail.progress == nil)
    }

    @Test func `a turn with no idle record after it is still in progress`() throws {
        // OpenCode writes `idle` when a turn ends: until then it is working, and (without its
        // plugin) says so nowhere else.
        #expect(try tail(Session(messages: [Self.user])).turn == .inProgress)
        #expect(try tail(Session(messages: [Self.user, Self.assistant("Reading the parser.")])).turn == .inProgress)
        #expect(try tail(Session(messages: [Self.user, Self.assistant(nil)])).turn == .inProgress)
    }

    @Test func `a turn that ended in failure is failed`() throws {
        let failed = Message(type: "idle", json: #"{"outcome":"failed","time":{"created":1}}"#)
        let tail = try tail(Session(messages: [Self.user, Self.assistant("Trying."), failed]))
        #expect(tail.turn == .failed)
        #expect(tail.interrupted == false)
    }

    @Test func `the placeholder title is no title`() throws {
        let tail = try tail(Session(title: "New session - 2026-09-29T02:46:30.000Z", messages: [Self.user, Self.assistant("On it.")]))
        #expect(tail.title == nil)
        #expect(tail.lastMessage == "On it.")
    }

    @Test func `an interrupted turn is noticed, keeping the last words before it`() throws {
        let tail = try tail(Session(messages: [Self.user, Self.assistant("Starting with the tokenizer."), Self.interrupted]))
        #expect(tail.interrupted)
        #expect(tail.turn == nil) // interrupted, not working
        #expect(tail.lastMessage == "Starting with the tokenizer.")
    }

    @Test func `a new prompt after an interruption clears it`() throws {
        let tail = try tail(Session(messages: [Self.user, Self.assistant("Starting."), Self.interrupted, Self.user]))
        #expect(tail.interrupted == false)
        #expect(tail.turn == .inProgress)
    }

    @Test func `steps with only tools and thinking don't replace the last words`() throws {
        let tail = try tail(Session(messages: [Self.user, Self.assistant("Reading the parser."), Self.assistant(nil), Self.assistant(nil)]))
        #expect(tail.lastMessage == "Reading the parser.")
    }

    @Test func `another session, a missing database or a different schema read as nothing`() throws {
        let home = try makeHome([Session(messages: [Self.user])])
        defer { try? FileManager.default.removeItem(at: home) }
        let database = OpenCodeAdapter.database(in: home)
        #expect(adapter.readTail(of: database, agentSessionID: "ses_other", home: home) == nil)
        #expect(adapter.readTail(of: database, agentSessionID: nil, home: home) == nil)

        // Opened read-only: a database that isn't there is not created.
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).db")
        #expect(adapter.readTail(of: missing, agentSessionID: "ses_a", home: home) == nil)
        #expect(!FileManager.default.fileExists(atPath: missing.path))

        let other = FileManager.default.temporaryDirectory.appending(path: "other-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: other) }
        try SQLiteDatabase(path: other.path).execute("CREATE TABLE unrelated (x TEXT)")
        #expect(adapter.readTail(of: other, agentSessionID: "ses_a", home: home) == nil)
    }

    @Test func `the write-ahead log is watched along with the database`() {
        let markers = adapter.changeMarkers(of: URL(filePath: "/x/opencode.db")).map(\.path)
        #expect(markers == ["/x/opencode.db", "/x/opencode.db-wal"])
    }

    // MARK: Finding the session

    private var started: Date {
        Date().addingTimeInterval(-60)
    }

    @Test func `the only session in the folder since the process started is found`() throws {
        let home = try makeHome([
            Session(id: "ses_a", messages: [Self.user]),
            Session(id: "ses_old", updated: Self.now - 3_600_000),
            Session(id: "ses_elsewhere", directory: "/Users/me/src/other"),
            Session(id: "ses_child", parent: "ses_a"),
            Session(id: "ses_archived", archived: true),
        ])
        defer { try? FileManager.default.removeItem(at: home) }
        let facts = ProcessFacts(directory: "/Users/me/src/app", started: started)
        let found = try #require(OpenCodeAdapter.transcript(facts: facts, home: home))
        #expect(found.agentSessionID == "ses_a")
        #expect(found.url == OpenCodeAdapter.database(in: home))
    }

    @Test func `two sessions in the folder are ambiguous, so none is chosen`() throws {
        let home = try makeHome([Session(id: "ses_a"), Session(id: "ses_b")])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(OpenCodeAdapter.transcript(facts: ProcessFacts(directory: "/Users/me/src/app", started: started), home: home) == nil)
    }

    @Test func `nothing is found without a folder, a start time or a database`() throws {
        let home = try makeHome([Session()])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(OpenCodeAdapter.transcript(facts: ProcessFacts(), home: home) == nil)
        #expect(OpenCodeAdapter.transcript(facts: ProcessFacts(directory: "/Users/me/src/app"), home: home) == nil)
        let later = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(3600))
        #expect(OpenCodeAdapter.transcript(facts: later, home: home) == nil)
        let empty = FileManager.default.temporaryDirectory.appending(path: "calm-opencode-none-\(UUID().uuidString)")
        #expect(OpenCodeAdapter.transcript(facts: ProcessFacts(directory: "/x", started: started), home: empty) == nil)
    }

    /// Opt-in survey of the most recent real sessions (CALM_REAL_OPENCODE_DB=<path>): counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_OPENCODE_DB"] != nil))
    func `reads real sessions`() throws {
        let path = try #require(ProcessInfo.processInfo.environment["CALM_REAL_OPENCODE_DB"])
        let url = URL(filePath: path)
        let database = try SQLiteDatabase(path: path, readOnly: true)
        var ids: [String] = []
        try database.query("SELECT id FROM session_v2 ORDER BY time_updated DESC LIMIT 60") { row in
            if let id = row.text(0) {
                ids.append(id)
            }
        }
        var recaps = 0, titled = 0, interrupted = 0, unreadable = 0
        let clock = ContinuousClock()
        var slowest = Duration.zero
        for id in ids {
            var tail: TranscriptTail?
            slowest = max(slowest, clock.measure { tail = adapter.readTail(of: url, agentSessionID: id, home: url) })
            guard let tail else {
                unreadable += 1
                continue
            }
            recaps += tail.lastMessage != nil ? 1 : 0
            titled += tail.title != nil ? 1 : 0
            interrupted += tail.interrupted ? 1 : 0
        }
        print("real opencode sessions: \(ids.count) read, \(recaps) with a recap, \(titled) titled, \(interrupted) interrupted")
        print("real opencode sessions: \(unreadable) unreadable, slowest \(slowest)")
        #expect(unreadable == 0)
        #expect(!ids.isEmpty)
    }
}
