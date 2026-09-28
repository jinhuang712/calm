import CalmAgents
import CalmModel
import Foundation

/// One session found by a search (FEATURES.md → F7): sessions, not lines.
public struct SearchResult: Sendable, Equatable {
    public var transcriptPath: String
    public var agent: AgentKind
    public var agentSessionID: String?
    public var directory: String?
    public var title: String
    public var lastActive: Date
    /// The best matching text, with matches between `SearchResult.matchStart` and `matchEnd`.
    public var snippet: String
    public var score: Double
    /// The agent deleted the transcript (Claude Code does after 30 days), so the conversation
    /// can be found but no longer resumed.
    public var transcriptDeleted = false

    public static let matchStart: Character = "\u{2}"
    public static let matchEnd: Character = "\u{3}"
}

/// What an index update did.
public struct IndexStats: Sendable, Equatable {
    public var filesSeen = 0
    public var filesUpdated = 0
    public var messagesAdded = 0
    /// Transcripts that disappeared from disk this update; their sessions stay searchable.
    public var filesRemoved = 0
}

/// The search index (DESIGNS.md → Search): SQLite FTS5 with the trigram tokenizer, updated
/// incrementally from each transcript's last read offset. All database access happens on one
/// serial queue, so any thread may call it.
///
/// Agents delete old transcripts, so the index is the only copy of those sessions: it keeps them
/// when their file goes, and a schema change migrates rather than rebuilds.
public final class SearchIndex: @unchecked Sendable {
    private let queue = DispatchQueue(label: "calm.search")
    private let database: SQLiteDatabase
    static let schemaVersion = "2"

    public static var standardURL: URL {
        if let override = ProcessInfo.processInfo.environment["CALM_INDEX_FILE"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm/index.sqlite")
    }

    /// Where transcripts are looked for: the home folder, or `CALM_SEARCH_HOME` (self-tests).
    public static var defaultHome: URL {
        if let override = ProcessInfo.processInfo.environment["CALM_SEARCH_HOME"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    public init(url: URL = SearchIndex.standardURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: url.path)
        try database.execute("PRAGMA journal_mode=WAL")
        var version: String?
        try? database.query("SELECT value FROM meta WHERE key = 'schema'") { version = $0.text(0) }
        switch version {
        case Self.schemaVersion:
            break
        case "1":
            // Version 1 forgot sessions whose transcript was deleted; everything else carries over.
            try database.execute("""
            ALTER TABLE files ADD COLUMN origin TEXT NOT NULL DEFAULT 'transcript';
            ALTER TABLE files ADD COLUMN gone INTEGER NOT NULL DEFAULT 0;
            """)
        default:
            // No index yet, or one from a newer or unknown schema: start over. Sessions whose
            // transcripts are gone are lost, apart from what prompt histories still hold.
            try database.execute("""
            DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS messages; DROP TABLE IF EXISTS sources;
            DROP TABLE IF EXISTS meta
            """)
        }
        // `origin` is 'transcript' (path is the transcript) or 'history' (a session known only
        // from the agent's prompt log; path is `<log>#<session id>`). `gone`: the transcript
        // was deleted.
        try database.execute("""
        CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
        CREATE TABLE IF NOT EXISTS files (
            id INTEGER PRIMARY KEY,
            path TEXT UNIQUE NOT NULL,
            agent TEXT NOT NULL,
            offset INTEGER NOT NULL DEFAULT 0,
            size INTEGER NOT NULL DEFAULT 0,
            mtime REAL NOT NULL DEFAULT 0,
            session_id TEXT, directory TEXT, title TEXT, first_prompt TEXT,
            last_active REAL NOT NULL DEFAULT 0,
            origin TEXT NOT NULL DEFAULT 'transcript',
            gone INTEGER NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS sources (path TEXT PRIMARY KEY, offset INTEGER NOT NULL);
        CREATE VIRTUAL TABLE IF NOT EXISTS messages USING fts5(text, file_id UNINDEXED, role UNINDEXED, tokenize = 'trigram');
        INSERT OR REPLACE INTO meta (key, value) VALUES ('schema', '\(Self.schemaVersion)');
        """)
    }

    // MARK: Updating

    private struct FileRow {
        var id: Int64
        var offset: UInt64
        var size: UInt64
        var mtime: Double
        var gone = false
        var info: TranscriptInfo
    }

    /// Indexes what's new in every transcript under `home` and in the agents' prompt histories,
    /// and marks transcripts that are gone (their sessions stay searchable).
    @discardableResult
    public func update(
        home: URL = SearchIndex.defaultHome,
        indexers: [any TranscriptIndexing] = Agents.indexers,
    ) -> IndexStats {
        queue.sync {
            var stats = IndexStats()
            var known = loadFiles()
            for indexer in indexers {
                for folder in indexer.transcriptFolders {
                    let root = home.appending(path: folder)
                    let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                    )
                    while let url = enumerator?.nextObject() as? URL {
                        guard url.pathExtension == "jsonl", indexer.isTranscript(url.path) else { continue }
                        stats.filesSeen += 1
                        let added = indexFile(url, indexer: indexer, known: known[url.path])
                        known[url.path] = nil
                        if let added {
                            stats.filesUpdated += 1
                            stats.messagesAdded += added
                        }
                    }
                }
            }
            // Whatever is left wasn't found on disk: the agent cleaned it up.
            for (_, row) in known where !row.gone {
                try? database.query("UPDATE files SET gone = 1 WHERE id = ?", [.integer(row.id)])
                stats.filesRemoved += 1
            }
            for indexer in indexers {
                stats.messagesAdded += indexPromptHistory(home: home, indexer: indexer)
            }
            return stats
        }
    }

    private func loadFiles() -> [String: FileRow] {
        var rows: [String: FileRow] = [:]
        let sql = """
        SELECT id, path, offset, size, mtime, session_id, directory, title, first_prompt, gone
        FROM files WHERE origin = 'transcript'
        """
        try? database.query(sql) { row in
            guard let path = row.text(1) else { return }
            rows[path] = FileRow(
                id: row.integer(0), offset: UInt64(row.integer(2)), size: UInt64(row.integer(3)), mtime: row.real(4),
                gone: row.integer(9) != 0,
                info: TranscriptInfo(agentSessionID: row.text(5), directory: row.text(6), title: row.text(7), firstPrompt: row.text(8)),
            )
        }
        return rows
    }

    /// Returns how many messages were added, or nil when the file hadn't changed.
    private func indexFile(_ url: URL, indexer: any TranscriptIndexing, known: FileRow?) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = UInt64(values?.fileSize ?? 0)
        let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        if let known, known.size == size, known.mtime == mtime {
            if known.gone {
                // Back on disk unchanged (a folder that was briefly unreadable, say).
                try? database.query("UPDATE files SET gone = 0 WHERE id = ?", [.integer(known.id)])
            }
            return nil
        }
        var row = known ?? FileRow(id: 0, offset: 0, size: 0, mtime: 0, info: TranscriptInfo())
        if size < row.offset {
            // Rewritten from the start: read it all again.
            try? database.query("DELETE FROM messages WHERE file_id = ?", [.integer(row.id)])
            row.offset = 0
            row.info = TranscriptInfo()
        }
        let knewSessionID = row.info.agentSessionID != nil
        guard let read = JSONLReader.read(url, from: row.offset) else { return nil }
        let messages = indexer.messages(in: read.records, info: &row.info)
        do {
            try database.transaction {
                if row.id == 0 {
                    try database.query("INSERT INTO files (path, agent) VALUES (?, ?)", [.text(url.path), .text(indexer.kind.rawValue)])
                    row.id = database.lastInsertedRowID
                }
                for message in messages {
                    try database.query(
                        "INSERT INTO messages (text, file_id, role) VALUES (?, ?, ?)",
                        [.text(message.text), .integer(row.id), .text(message.role.rawValue)],
                    )
                }
                try database.query(
                    """
                    UPDATE files SET offset = ?, size = ?, mtime = ?, session_id = ?, directory = ?, title = ?,
                        first_prompt = ?, last_active = ?, gone = 0 WHERE id = ?
                    """,
                    [
                        .integer(Int64(read.end)), .integer(Int64(size)), .real(mtime), Self.value(row.info.agentSessionID),
                        Self.value(row.info.directory), Self.value(row.info.title), Self.value(row.info.firstPrompt), .real(mtime),
                        .integer(row.id),
                    ],
                )
                if !knewSessionID, let sessionID = row.info.agentSessionID {
                    // The transcript has everything its prompt-history stand-in had, and more.
                    try removeHistorySession(sessionID, agent: indexer.kind)
                }
            }
        } catch {
            return nil
        }
        return messages.count
    }

    /// Reads what's new in the agent's prompt history, keeping the prompts of sessions that have
    /// no transcript in the index: conversations deleted before Calm saw them. Returns how many
    /// prompts were added.
    private func indexPromptHistory(home: URL, indexer: any TranscriptIndexing) -> Int {
        guard let file = indexer.promptHistoryFile else { return 0 }
        let url = home.appending(path: file)
        let agent = indexer.kind.rawValue
        let size = UInt64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        var offset: UInt64 = 0
        try? database.query("SELECT offset FROM sources WHERE path = ?", [.text(url.path)]) { offset = UInt64($0.integer(0)) }
        if size < offset {
            // Rewritten: read it again, and what stood in for deleted sessions with it.
            let prefix = url.path + "#"
            try? database.query(
                "DELETE FROM messages WHERE file_id IN (SELECT id FROM files WHERE origin = 'history' AND substr(path, 1, ?) = ?)",
                [.integer(Int64(prefix.count)), .text(prefix)],
            )
            try? database.query(
                "DELETE FROM files WHERE origin = 'history' AND substr(path, 1, ?) = ?",
                [.integer(Int64(prefix.count)), .text(prefix)],
            )
            offset = 0
        }
        guard size > offset, let read = JSONLReader.read(url, from: offset) else { return 0 }
        let prompts = read.records.compactMap(indexer.historyPrompt(in:))

        var transcripts = Set<String>()
        try? database.query(
            "SELECT session_id FROM files WHERE origin = 'transcript' AND agent = ? AND session_id IS NOT NULL",
            [.text(agent)],
        ) { row in
            if let sessionID = row.text(0) {
                transcripts.insert(sessionID)
            }
        }
        var added = 0
        try? database.transaction {
            for prompt in prompts where !transcripts.contains(prompt.agentSessionID) {
                let path = "\(url.path)#\(prompt.agentSessionID)"
                var id: Int64?
                try database.query("SELECT id FROM files WHERE path = ?", [.text(path)]) { id = $0.integer(0) }
                if id == nil {
                    try database.query(
                        """
                        INSERT INTO files (path, agent, origin, gone, session_id, directory, first_prompt)
                        VALUES (?, ?, 'history', 1, ?, ?, ?)
                        """,
                        [
                            .text(path), .text(agent), .text(prompt.agentSessionID), Self.value(prompt.directory),
                            Self.value(HookReport.recap(prompt.text, limit: 120)),
                        ],
                    )
                    id = database.lastInsertedRowID
                }
                guard let id else { continue }
                try database.query(
                    "INSERT INTO messages (text, file_id, role) VALUES (?, ?, ?)",
                    [.text(prompt.text), .integer(id), .text(TranscriptMessage.Role.user.rawValue)],
                )
                try database.query(
                    "UPDATE files SET last_active = max(last_active, ?) WHERE id = ?",
                    [.real(prompt.date.timeIntervalSince1970), .integer(id)],
                )
                added += 1
            }
            try database.query(
                "INSERT OR REPLACE INTO sources (path, offset) VALUES (?, ?)",
                [.text(url.path), .integer(Int64(read.end))],
            )
        }
        return added
    }

    private func removeHistorySession(_ sessionID: String, agent: AgentKind) throws {
        let values: [SQLiteDatabase.Value] = [.text(sessionID), .text(agent.rawValue)]
        try database.query(
            "DELETE FROM messages WHERE file_id IN (SELECT id FROM files WHERE origin = 'history' AND session_id = ? AND agent = ?)",
            values,
        )
        try database.query("DELETE FROM files WHERE origin = 'history' AND session_id = ? AND agent = ?", values)
    }

    private static func value(_ text: String?) -> SQLiteDatabase.Value {
        text.map { .text($0) } ?? .null
    }

    // MARK: Searching

    /// Sessions matching every term of `query` (anywhere in the session), best first. An empty
    /// query lists the most recent sessions.
    public func search(_ query: String, limit: Int = 20, currentProject: String? = nil, now: Date = Date()) -> [SearchResult] {
        queue.sync {
            let terms = SearchQuery.terms(in: query)
            let sessions = loadSessions()
            guard !terms.isEmpty else {
                return sessions.values
                    .sorted { $0.lastActive > $1.lastActive }
                    .prefix(limit)
                    .map { $0.result(snippet: $0.firstPrompt ?? "", score: 0) }
            }
            // Per term: the best match in each session.
            var perTerm: [[Int64: Match]] = []
            for term in terms {
                perTerm.append(matches(for: term))
            }
            var candidates = Set(perTerm[0].keys)
            for matches in perTerm.dropFirst() {
                candidates.formIntersection(matches.keys)
            }
            let best = perTerm.map { matches in matches.values.map(\.rank).min() ?? 0 }
            var scored: [(id: Int64, score: Double)] = []
            for id in candidates {
                guard let session = sessions[id] else { continue }
                let relevance = zip(perTerm, best).map { matches, best in
                    SearchRanking.relevance(rank: matches[id]?.rank ?? 0, best: best)
                }.reduce(0, +) / Double(terms.count)
                let score = SearchRanking.score(
                    relevance: relevance,
                    titleMatches: terms.allSatisfy { session.title?.localizedCaseInsensitiveContains($0) == true },
                    lastActive: session.lastActive,
                    inCurrentProject: currentProject
                        .map { project in session.directory.map { WorkspacePath.isInside($0, folder: project) } ?? false } ?? false,
                    now: now,
                )
                scored.append((id, score))
            }
            // Snippets only for what's shown: the matching message, cut to start just before
            // the first term, so a one-line row always shows the match.
            return scored.sorted { $0.score > $1.score }.prefix(limit).compactMap { id, score in
                guard let session = sessions[id], let match = perTerm[0][id] else { return nil }
                var text = ""
                try? database.query("SELECT text FROM messages WHERE rowid = ?", [.integer(match.message)]) { text = $0.text(0) ?? "" }
                return session.result(snippet: SearchQuery.snippet(text, around: terms[0]), score: score)
            }
        }
    }

    private struct Match {
        var rank: Double
        /// The message's rowid.
        var message: Int64
    }

    /// The best-ranked message per session for one term: FTS5 for three characters or more,
    /// and a LIKE scan below that (trigrams can't match shorter text).
    private func matches(for term: String) -> [Int64: Match] {
        var matches: [Int64: Match] = [:]
        if term.count >= 3 {
            let sql = """
            SELECT file_id, bm25(messages), rowid FROM messages WHERE messages MATCH ?
            ORDER BY bm25(messages) LIMIT 5000
            """
            try? database.query(sql, [.text(SearchQuery.phrase(term))]) { row in
                let id = row.integer(0)
                if matches[id] == nil {
                    matches[id] = Match(rank: row.real(1), message: row.integer(2))
                }
            }
        } else {
            try? database.query(
                "SELECT file_id, rowid FROM messages WHERE text LIKE ? ESCAPE '\\' LIMIT 5000",
                [.text(SearchQuery.likePattern(term))],
            ) { row in
                let id = row.integer(0)
                if matches[id] == nil {
                    matches[id] = Match(rank: 0, message: row.integer(1))
                }
            }
        }
        return matches
    }

    private struct Session {
        var path: String
        var agent: AgentKind
        var sessionID: String?
        var directory: String?
        var title: String?
        var firstPrompt: String?
        var lastActive: Date
        var gone: Bool

        func result(snippet: String, score: Double) -> SearchResult {
            SearchResult(
                transcriptPath: path, agent: agent, agentSessionID: sessionID, directory: directory,
                title: title ?? firstPrompt ?? (path as NSString).lastPathComponent,
                lastActive: lastActive, snippet: snippet, score: score, transcriptDeleted: gone,
            )
        }
    }

    private func loadSessions() -> [Int64: Session] {
        var sessions: [Int64: Session] = [:]
        let sql = "SELECT id, path, agent, session_id, directory, title, first_prompt, last_active, gone FROM files"
        try? database.query(sql) { row in
            guard let path = row.text(1), let agent = row.text(2).flatMap(AgentKind.init(rawValue:)) else { return }
            sessions[row.integer(0)] = Session(
                path: path, agent: agent, sessionID: row.text(3), directory: row.text(4), title: row.text(5),
                firstPrompt: row.text(6), lastActive: Date(timeIntervalSince1970: row.real(7)), gone: row.integer(8) != 0,
            )
        }
        return sessions
    }

    /// Indexed sessions and messages, for tests and the performance check.
    public func counts() -> (sessions: Int, messages: Int) {
        queue.sync {
            var sessions = 0
            var messages = 0
            try? database.query("SELECT count(*) FROM files") { sessions = Int($0.integer(0)) }
            try? database.query("SELECT count(*) FROM messages") { messages = Int($0.integer(0)) }
            return (sessions, messages)
        }
    }
}
