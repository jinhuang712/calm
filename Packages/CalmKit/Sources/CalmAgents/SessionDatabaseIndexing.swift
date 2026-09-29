import CalmModel
import Foundation

/// One session in an agent's own database, as search indexes it.
public struct DatabaseSession: Sendable, Equatable {
    public var id: String
    public var title: String?
    public var directory: String?
    /// When the session's newest message was written.
    public var lastActive: Date
    /// Changes whenever a message is added or rewritten (their count and newest change), so an
    /// unchanged session is never read again.
    public var version: (messages: Int64, updated: Int64)

    public init(id: String, title: String?, directory: String?, lastActive: Date, version: (messages: Int64, updated: Int64)) {
        self.id = id
        self.title = title
        self.directory = directory
        self.lastActive = lastActive
        self.version = version
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.directory == rhs.directory && lhs.lastActive == rhs.lastActive
            && lhs.version == rhs.version
    }
}

/// Agents that keep every session in one database of their own rather than a file per session
/// (OpenCode 2), so search reads them by session instead of by file and offset (FEATURES.md →
/// F7, DESIGNS.md → Search). The database is another program's: read-only, and anything
/// unexpected reads as nothing.
public protocol SessionDatabaseIndexing: AgentAdapter {
    /// The database under home, and the files beside it whose change means it changed (its
    /// write-ahead log).
    var sessionDatabase: String { get }
    /// Every top-level session worth searching, or nil when the database can't be read.
    func indexedSessions(in database: URL) -> [DatabaseSession]?
    /// A session's messages, in order: what the user and the agent wrote, nothing else.
    func messages(ofSession id: String, in database: URL) -> [TranscriptMessage]?
}

public extension Agents {
    static var databaseIndexers: [any SessionDatabaseIndexing] {
        adapters.compactMap { $0 as? any SessionDatabaseIndexing }
    }
}
