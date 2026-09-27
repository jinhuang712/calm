import CalmModel
import Foundation

/// Agents whose transcripts Calm can read for session cards (DESIGNS.md → Agents). Formats are
/// undocumented and change: anything unexpected reads as "nothing known", never an error.
public protocol TranscriptReading: AgentAdapter {
    /// The transcript of the agent running as `processID`, found without hooks.
    func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)?
    /// Reads what the transcript says now. `agentSessionID` finds the agent's side files (todos).
    func readTail(of transcript: URL, agentSessionID: String?, home: URL) -> TranscriptTail?
}

public extension Agents {
    static func transcriptReader(for kind: AgentKind) -> (any TranscriptReading)? {
        adapter(for: kind) as? any TranscriptReading
    }
}

/// Reads the end of a JSONL file: the last complete lines within `limit` bytes, newest first.
enum JSONLTail {
    static func records(at url: URL, limit: Int = 512 * 1024) -> [[String: Any]] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return [] }
        let start = size > UInt64(limit) ? size - UInt64(limit) : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }
        var lines = data.split(separator: 0x0A)
        if start > 0, !lines.isEmpty {
            lines.removeFirst() // started mid-line
        }
        return lines.reversed().compactMap { line in
            (try? JSONSerialization.jsonObject(with: line)) as? [String: Any]
        }
    }
}
