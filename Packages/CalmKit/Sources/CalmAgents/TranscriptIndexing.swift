import CalmModel
import Foundation

/// A message worth searching: something the user or the agent wrote. Tool calls, tool output,
/// thinking and context the agent injected are left out (FEATURES.md → F7).
public struct TranscriptMessage: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case agent
    }

    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

/// What a transcript says about its session, gathered while reading it.
public struct TranscriptInfo: Sendable, Equatable {
    public var agentSessionID: String?
    public var directory: String?
    public var title: String?
    /// The first thing the user asked: a title when the agent keeps none.
    public var firstPrompt: String?

    public init(agentSessionID: String? = nil, directory: String? = nil, title: String? = nil, firstPrompt: String? = nil) {
        self.agentSessionID = agentSessionID
        self.directory = directory
        self.title = title
        self.firstPrompt = firstPrompt
    }
}

/// Agents whose transcripts can be searched (M4). Parsers read complete JSONL records and
/// skip anything they don't recognize.
public protocol TranscriptIndexing: AgentAdapter {
    /// Folders under home that hold this agent's transcripts (`*.jsonl`, searched recursively).
    var transcriptFolders: [String] { get }
    /// Whether a file under those folders is a session transcript (not, say, a subagent's).
    func isTranscript(_ path: String) -> Bool
    /// The messages in `records`, updating `info` with what they reveal about the session.
    func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage]
}

public extension TranscriptIndexing {
    func isTranscript(_: String) -> Bool {
        true
    }
}

public extension Agents {
    static var indexers: [any TranscriptIndexing] {
        adapters.compactMap { $0 as? any TranscriptIndexing }
    }
}

/// Reads a JSONL file from a byte offset, returning only complete lines, so a file an agent is
/// still writing can be read again later from where this left off.
public enum JSONLReader {
    public static func read(_ url: URL, from offset: UInt64) -> (records: [[String: Any]], end: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        guard size > offset else { return ([], min(offset, size)) }
        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), let lastNewline = data.lastIndex(of: 0x0A) else { return ([], offset) }
        let complete = data[data.startIndex ... lastNewline]
        let records = complete.split(separator: 0x0A).compactMap { line in
            (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        }
        return (records, offset + UInt64(complete.count))
    }
}

/// Text the agent injected rather than the user typed: tag-wrapped context (`<environment_context>`,
/// `<command-name>`, `<system-reminder>`…) and Codex's AGENTS.md block.
enum InjectedText {
    static func isInjected(_ text: String) -> Bool {
        let trimmed = text.drop { $0.isWhitespace }
        return trimmed.hasPrefix("<") || trimmed.hasPrefix("# AGENTS.md instructions")
    }
}
