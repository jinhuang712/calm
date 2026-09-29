import CalmModel
import CalmSQLite
import Foundation

/// OpenCode 2's data, as seen on 2026-09-29 (2.0.18): one SQLite database in write-ahead mode,
/// `~/.local/share/opencode/opencode.db`, shared by every OpenCode process. Version 2 moved
/// sessions to new tables and left the old `session`, `message` and `part` ones behind
/// (untouched since the upgrade), so only these are read:
///
/// - `session_v2`: `id` (`ses_…`), `directory`, `title` (a placeholder `New session - <time>`
///   until it is named), `parent_id` (a subagent's session has one), `time_archived`,
///   `time_updated` (milliseconds).
/// - `session_message`: `session_id`, `seq` (rises with each message in the session), `type`
///   and a JSON `data`. `user` has `text`; `assistant` has `content[]` blocks (`text`,
///   `reasoning`, `tool`); `idle` has `outcome`: `succeeded`, `failed` or `interrupted` (Esc).
/// - No todo records appear in recent use, so an OpenCode card has a title, a recap and an
///   interruption but no step or progress.
///
/// The database is another program's: it is opened read-only, never created or written to,
/// and a schema that isn't this one reads as nothing.
extension OpenCodeAdapter: TranscriptReading {
    static func database(in home: URL) -> URL {
        home.appending(path: ".local/share/opencode/opencode.db")
    }

    public func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)? {
        Self.transcript(facts: ProcessFacts.of(processID), home: home)
    }

    /// The database holds every process's sessions and OpenCode's process has no file of its own
    /// open, so: the only top-level session in the process's folder updated since it started.
    /// Two are ambiguous (two OpenCodes in one folder, or one after a `/new`), and then none is
    /// chosen.
    static func transcript(facts: ProcessFacts, home: URL) -> (agentSessionID: String, url: URL)? {
        guard let directory = facts.directory, let started = facts.started else { return nil }
        let url = database(in: home)
        guard let database = try? SQLiteDatabase(path: url.path, readOnly: true) else { return nil }
        var ids: [String] = []
        let sinceMilliseconds = Int64((started.timeIntervalSince1970 - 2) * 1000)
        try? database.query(
            """
            SELECT id FROM session_v2
            WHERE directory IN (?, ?) AND parent_id IS NULL AND time_archived IS NULL AND time_updated >= ?
            LIMIT 3
            """,
            [.text(directory), .text(TranscriptDiscovery.resolved(directory)), .integer(sinceMilliseconds)],
        ) { row in
            if let id = row.text(0) {
                ids.append(id)
            }
        }
        return ids.count == 1 ? (ids[0], url) : nil
    }

    /// `transcript` is the database file and `agentSessionID` the session in it.
    public func readTail(of transcript: URL, agentSessionID: String?, home _: URL) -> TranscriptTail? {
        guard let agentSessionID, let database = try? SQLiteDatabase(path: transcript.path, readOnly: true) else { return nil }
        var tail = TranscriptTail()
        var found = false
        do {
            try database.query("SELECT title FROM session_v2 WHERE id = ?", [.text(agentSessionID)]) { row in
                found = true
                tail.title = Self.title(row.text(0))
            }
            guard found else { return nil }
            var sawConversation = false
            try database.query(
                """
                SELECT type, data FROM session_message
                WHERE session_id = ? AND type IN ('user', 'assistant', 'idle')
                ORDER BY seq DESC LIMIT 40
                """,
                [.text(agentSessionID)],
            ) { row in
                guard tail.lastMessage == nil, let type = row.text(0) else { return }
                let json = row.text(1).flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) }
                let data = json as? [String: Any] ?? [:]
                switch type {
                case "idle":
                    // Only the newest record can show an interruption: a later prompt starts a new turn.
                    if !sawConversation {
                        tail.interrupted = data["outcome"] as? String == "interrupted"
                    }
                case "assistant":
                    // Lines kept apart, so the cleaning can tell a heading from what follows it.
                    tail.lastMessage = MessageText.recap(Self.texts(of: data).joined(separator: "\n"))
                default:
                    break
                }
                sawConversation = true
            }
        } catch {
            return nil
        }
        return tail
    }

    /// The database and its write-ahead log, which is what grows while OpenCode works.
    public func changeMarkers(of transcript: URL) -> [URL] {
        [transcript, URL(filePath: transcript.path + "-wal")]
    }

    /// OpenCode names a session `New session - <time>` until it has a real title.
    private static func title(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              !text.hasPrefix("New session - "), !text.hasPrefix("Child session - ")
        else { return nil }
        return text
    }

    private static func texts(of data: [String: Any]) -> [String] {
        let blocks = data["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }
}
