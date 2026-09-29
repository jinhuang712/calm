import CalmModel
import CalmSQLite
import Foundation

/// OpenCode 2's history for search (FEATURES.md → F7), read from `session_v2` and
/// `session_message` (see OpenCodeTranscript.swift for the tables). Checked against 2.0.19's
/// database on 2026-09-30:
///
/// - Top-level sessions only: a subagent's has a `parent_id`. A session nobody wrote in is left
///   out, and so is a placeholder title (`New session - <time>`).
/// - `session_v2.time_updated` doesn't follow message writes, and messages are rewritten in
///   place for days, so a session's version is its messages' count and newest `time_updated`.
/// - User text is `data.text`; the agent's is its `content[]` blocks of type `text`. Tool calls
///   and output, reasoning, attached files, and the `synthetic`, `system` and `idle` rows are
///   skipped, as for the other agents.
/// - A fork (`fork_session_id`) starts with copies of its parent's messages, written before the
///   fork itself: those are left to the parent, so a match isn't found twice.
extension OpenCodeAdapter: SessionDatabaseIndexing {
    public var sessionDatabase: String {
        ".local/share/opencode/opencode.db"
    }

    public func indexedSessions(in database: URL) -> [DatabaseSession]? {
        guard let db = try? SQLiteDatabase(path: database.path, readOnly: true) else { return nil }
        var sessions: [DatabaseSession] = []
        do {
            try db.query(
                """
                SELECT s.id, s.title, s.directory, m.messages, m.updated, m.last
                FROM session_v2 s JOIN (
                    SELECT session_id, count(*) AS messages, max(time_updated) AS updated, max(time_created) AS last
                    FROM session_message GROUP BY session_id
                ) m ON m.session_id = s.id
                WHERE s.parent_id IS NULL
                """,
            ) { row in
                guard let id = row.text(0) else { return }
                sessions.append(DatabaseSession(
                    id: id, title: Self.title(row.text(1)), directory: row.text(2),
                    lastActive: Date(timeIntervalSince1970: Double(row.integer(5)) / 1000),
                    version: (row.integer(3), row.integer(4)),
                ))
            }
        } catch {
            return nil
        }
        return sessions
    }

    public func messages(ofSession id: String, in database: URL) -> [TranscriptMessage]? {
        guard let db = try? SQLiteDatabase(path: database.path, readOnly: true) else { return nil }
        var messages: [TranscriptMessage] = []
        do {
            // A fork's copied messages were written before the fork was made.
            var since: Int64 = 0
            if Self.hasColumn("fork_session_id", in: db) {
                try db.query("SELECT time_created FROM session_v2 WHERE id = ? AND fork_session_id IS NOT NULL", [.text(id)]) {
                    since = $0.integer(0)
                }
            }
            // The text is taken out in SQL, so the tool output around it (most of an assistant
            // record's bytes) never reaches Swift.
            try db.query(
                """
                SELECT seq, 0, 'user', json_extract(data, '$.text') FROM session_message
                WHERE session_id = ? AND type = 'user' AND time_created >= ?
                UNION ALL
                SELECT m.seq, c.key, 'agent', json_extract(c.value, '$.text')
                FROM session_message m, json_each(m.data, '$.content') c
                WHERE m.session_id = ? AND m.type = 'assistant' AND m.time_created >= ?
                    AND json_extract(c.value, '$.type') = 'text'
                ORDER BY 1, 2
                """,
                [.text(id), .integer(since), .text(id), .integer(since)],
            ) { row in
                guard let text = row.text(3)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                if row.text(2) == "user" {
                    if !InjectedText.isInjected(text) {
                        messages.append(TranscriptMessage(.user, text))
                    }
                } else {
                    messages.append(TranscriptMessage(.agent, text))
                }
            }
        } catch {
            return nil
        }
        return messages
    }

    private static func hasColumn(_ name: String, in db: SQLiteDatabase) -> Bool {
        var found = false
        try? db.query("SELECT 1 FROM pragma_table_info('session_v2') WHERE name = ?", [.text(name)]) { _ in found = true }
        return found
    }
}
