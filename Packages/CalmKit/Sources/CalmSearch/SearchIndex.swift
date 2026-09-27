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

    public static let matchStart: Character = "\u{2}"
    public static let matchEnd: Character = "\u{3}"
}

/// What an index update did.
public struct IndexStats: Sendable, Equatable {
    public var filesSeen = 0
    public var filesUpdated = 0
    public var messagesAdded = 0
    public var filesRemoved = 0
}

/// The search index (DESIGNS.md → Search): SQLite FTS5 with the trigram tokenizer, updated
/// incrementally from each transcript's last read offset. All database access happens on one
/// serial queue, so any thread may call it.
public final class SearchIndex: @unchecked Sendable {
    private let queue = DispatchQueue(label: "calm.search")
    private let database: SQLiteDatabase
    static let schemaVersion = "1"

    public static var standardURL: URL {
        if let override = ProcessInfo.processInfo.environment["CALM_INDEX_FILE"], !override.isEmpty {
            return URL(filePath: override)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm/index.sqlite")
    }

    public init(url: URL = SearchIndex.standardURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        database = try SQLiteDatabase(path: url.path)
        try database.execute("PRAGMA journal_mode=WAL")
        var version: String?
        try? database.query("SELECT value FROM meta WHERE key = 'schema'") { version = $0.text(0) }
        if version != Self.schemaVersion {
            // An index is a cache of the transcripts: rebuild rather than migrate.
            try database.execute("DROP TABLE IF EXISTS files; DROP TABLE IF EXISTS messages; DROP TABLE IF EXISTS meta")
        }
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
            last_active REAL NOT NULL DEFAULT 0
        );
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
        var info: TranscriptInfo
    }

    /// Indexes what's new in every transcript under `home`, and forgets transcripts that are gone.
    @discardableResult
    public func update(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
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
            for (_, row) in known {
                try? database.query("DELETE FROM messages WHERE file_id = ?", [.integer(row.id)])
                try? database.query("DELETE FROM files WHERE id = ?", [.integer(row.id)])
                stats.filesRemoved += 1
            }
            return stats
        }
    }

    private func loadFiles() -> [String: FileRow] {
        var rows: [String: FileRow] = [:]
        try? database.query("SELECT id, path, offset, size, mtime, session_id, directory, title, first_prompt FROM files") { row in
            guard let path = row.text(1) else { return }
            rows[path] = FileRow(
                id: row.integer(0), offset: UInt64(row.integer(2)), size: UInt64(row.integer(3)), mtime: row.real(4),
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
            return nil
        }
        var row = known ?? FileRow(id: 0, offset: 0, size: 0, mtime: 0, info: TranscriptInfo())
        if size < row.offset {
            // Rewritten from the start: read it all again.
            try? database.query("DELETE FROM messages WHERE file_id = ?", [.integer(row.id)])
            row.offset = 0
            row.info = TranscriptInfo()
        }
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
                        first_prompt = ?, last_active = ? WHERE id = ?
                    """,
                    [
                        .integer(Int64(read.end)), .integer(Int64(size)), .real(mtime), Self.value(row.info.agentSessionID),
                        Self.value(row.info.directory), Self.value(row.info.title), Self.value(row.info.firstPrompt), .real(mtime),
                        .integer(row.id),
                    ],
                )
            }
        } catch {
            return nil
        }
        return messages.count
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
            var perTerm: [[Int64: (rank: Double, snippet: String)]] = []
            for term in terms {
                perTerm.append(matches(for: term))
            }
            var candidates = Set(perTerm[0].keys)
            for matches in perTerm.dropFirst() {
                candidates.formIntersection(matches.keys)
            }
            let best = perTerm.map { matches in matches.values.map(\.rank).min() ?? 0 }
            var results: [SearchResult] = []
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
                results.append(session.result(snippet: perTerm[0][id]?.snippet ?? "", score: score))
            }
            return Array(results.sorted { $0.score > $1.score }.prefix(limit))
        }
    }

    /// The best-ranked message per session for one term: FTS5 for three characters or more,
    /// a LIKE scan below that (trigrams can't match shorter text).
    private func matches(for term: String) -> [Int64: (rank: Double, snippet: String)] {
        var matches: [Int64: (rank: Double, snippet: String)] = [:]
        if term.count >= 3 {
            let sql = """
            SELECT file_id, bm25(messages), snippet(messages, 0, char(2), char(3), '…', 12)
            FROM messages WHERE messages MATCH ? ORDER BY bm25(messages) LIMIT 5000
            """
            try? database.query(sql, [.text(SearchQuery.phrase(term))]) { row in
                let id = row.integer(0)
                if matches[id] == nil {
                    matches[id] = (row.real(1), row.text(2) ?? "")
                }
            }
        } else {
            try? database.query(
                "SELECT file_id, text FROM messages WHERE text LIKE ? ESCAPE '\\' LIMIT 5000",
                [.text(SearchQuery.likePattern(term))],
            ) { row in
                let id = row.integer(0)
                if matches[id] == nil {
                    matches[id] = (0, SearchQuery.snippet(row.text(1) ?? "", around: term))
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

        func result(snippet: String, score: Double) -> SearchResult {
            SearchResult(
                transcriptPath: path, agent: agent, agentSessionID: sessionID, directory: directory,
                title: title ?? firstPrompt ?? (path as NSString).lastPathComponent,
                lastActive: lastActive, snippet: snippet, score: score,
            )
        }
    }

    private func loadSessions() -> [Int64: Session] {
        var sessions: [Int64: Session] = [:]
        try? database.query("SELECT id, path, agent, session_id, directory, title, first_prompt, last_active FROM files") { row in
            guard let path = row.text(1), let agent = row.text(2).flatMap(AgentKind.init(rawValue:)) else { return }
            sessions[row.integer(0)] = Session(
                path: path, agent: agent, sessionID: row.text(3), directory: row.text(4), title: row.text(5),
                firstPrompt: row.text(6), lastActive: Date(timeIntervalSince1970: row.real(7)),
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
