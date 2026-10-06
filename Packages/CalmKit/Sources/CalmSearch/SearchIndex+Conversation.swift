import CalmAgents
import CalmModel
import CalmSQLite
import Foundation

/// A conversation as the index holds it (`SearchIndex.conversation(id:)`).
public struct IndexedConversation: Sendable, Equatable {
    /// Its path, agent, ids, folder, title, last activity, and whether its transcript is gone.
    public var result: SearchResult
    public var firstPrompt: String?
    /// Known only from the agent's prompt history: the prompts are there, the replies aren't.
    public var fromHistory: Bool
    /// What the user and the agent wrote, in order (no tool calls, output or thinking).
    public var messages: [TranscriptMessage]
}

public enum ConversationLookupError: Error, Sendable, Equatable {
    case none
    /// The id's start fits more than one conversation.
    case several([String])
}

public extension SearchIndex {
    /// One conversation as the index holds it, for `calm show`: by the agent's own id, or by the
    /// start of one (6 characters or more) that only one conversation's id begins with. A
    /// transcript's (or an agent database's) row wins over the prompt history's copy, which only
    /// stands in once the transcript is gone. Messages come in the order they were indexed.
    func conversation(id: String) -> Result<IndexedConversation, ConversationLookupError> {
        queue.sync {
            var rows: [Row] = []
            let sql = """
            SELECT id, path, agent, session_id, directory, title, first_prompt, last_active, gone, origin FROM files
            WHERE session_id = ? OR (length(?) >= 6 AND substr(session_id, 1, length(?)) = ?)
            """
            try? database.query(sql, [.text(id), .text(id), .text(id), .text(id)]) { row in
                guard let path = row.text(1), let agent = row.text(2).flatMap(AgentKind.init(rawValue:)) else { return }
                let session = Session(
                    path: path, agent: agent, sessionID: row.text(3), directory: row.text(4), title: row.text(5),
                    firstPrompt: row.text(6), lastActive: Date(timeIntervalSince1970: row.real(7)), gone: row.integer(8) != 0,
                )
                rows.append(Row(row: row.integer(0), session: session, origin: row.text(9) ?? "transcript"))
            }
            let exact = rows.filter { $0.session.sessionID == id }
            let candidates = exact.isEmpty ? rows : exact
            let ids = Set(candidates.compactMap(\.session.sessionID))
            guard ids.count <= 1 else { return .failure(.several(ids.sorted())) }
            let best = candidates.min { lhs, rhs in
                (lhs.origin == "history" ? 1 : 0, -lhs.session.lastActive.timeIntervalSince1970)
                    < (rhs.origin == "history" ? 1 : 0, -rhs.session.lastActive.timeIntervalSince1970)
            }
            guard let chosen = best else { return .failure(.none) }
            var messages: [TranscriptMessage] = []
            try? database.query("SELECT role, text FROM messages WHERE file_id = ? ORDER BY rowid", [.integer(chosen.row)]) { row in
                guard let role = row.text(0).flatMap(TranscriptMessage.Role.init(rawValue:)), let text = row.text(1) else { return }
                messages.append(TranscriptMessage(role, text))
            }
            return .success(IndexedConversation(
                result: chosen.session.result(snippet: "", score: 0), firstPrompt: chosen.session.firstPrompt,
                fromHistory: chosen.origin == "history", messages: messages,
            ))
        }
    }
}

/// A row of `files` for one conversation, and where it came from.
private struct Row {
    var row: Int64
    var session: SearchIndex.Session
    var origin: String
}
