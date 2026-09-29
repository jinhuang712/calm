import CalmModel
import Foundation

/// Codex's files, as seen on 2026-09-29 (version 0.158.0):
///
/// - `~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<uuid>.jsonl`: one JSON record per line,
///   `{type, ordinal, timestamp, payload}`. The first is `session_meta` (`payload.id`,
///   `payload.cwd`). A turn is bracketed by `event_msg` records: `task_started`, then
///   `task_complete` (`last_agent_message`) or `turn_aborted` (`reason: "interrupted"` for Esc).
///   `response_item` records with `payload.type == "message"` hold what the user and the agent
///   said (`payload.content[].text`).
/// - A single record can be megabytes (tool output), so the tail reader steps past long lines.
/// - There is no title (Codex keeps it in a versioned SQLite file) and, in recent rollouts, no
///   plan records, so a Codex card has a recap and an interruption but no step or progress.
extension CodexAdapter: TranscriptReading {
    public func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)? {
        Self.transcript(facts: ProcessFacts.of(processID), home: home)
    }

    /// Codex 0.157+ runs every session in one shared background server, and that server (not
    /// the `codex` in the terminal) holds the rollout open, so the process's open files only
    /// help in embedded mode. Three ways, most exact first: the rollout the process has open;
    /// the id in `codex resume <id>` (a resumed conversation appends to its old rollout, in an
    /// old date folder); the only terminal rollout for the folder since the process started.
    static func transcript(facts: ProcessFacts, home: URL) -> (agentSessionID: String, url: URL)? {
        let root = home.appending(path: ".codex/sessions")
        if let opened = TranscriptDiscovery.locate(facts: facts, roots: [root], candidates: { [] }, head: head(of:)) {
            return opened
        }
        if let id = resumedSessionID(in: facts.arguments),
           let url = TranscriptDiscovery.files(under: root, extension: "jsonl", since: nil)
           .first(where: { $0.lastPathComponent.hasSuffix("-\(id).jsonl") }),
           let session = head(of: url) {
            return (session.id, url)
        }
        return TranscriptDiscovery.locate(
            facts: ProcessFacts(directory: facts.directory, started: facts.started),
            roots: [root],
            candidates: { TranscriptDiscovery.files(under: root, extension: "jsonl", since: facts.started) },
            head: head(of:),
        )
    }

    /// The conversation id in `codex resume <id>` (not `fork`: that starts a new rollout).
    static func resumedSessionID(in arguments: [String]) -> String? {
        guard let resume = arguments.firstIndex(of: "resume") else { return nil }
        return arguments.dropFirst(resume + 1).first { UUID(uuidString: $0) != nil }
    }

    static func head(of url: URL) -> SessionHead? {
        guard let record = TranscriptDiscovery.firstRecord(of: url), record["type"] as? String == "session_meta",
              let payload = record["payload"] as? [String: Any],
              let id = (payload["id"] as? String) ?? (payload["session_id"] as? String)
        else { return nil }
        // `source` is "cli" for a terminal, "vscode" for the app; a subagent's thread has an
        // object there.
        return SessionHead(id: id, directory: payload["cwd"] as? String, isTerminalSession: payload["source"] as? String == "cli")
    }

    public func readTail(of transcript: URL, agentSessionID _: String?, home _: URL) -> TranscriptTail? {
        var tail = TranscriptTail()
        var sawRecord = false
        var sawTurnMarker = false
        for record in JSONLTail(transcript) { // newest first
            sawRecord = true
            guard let payload = record["payload"] as? [String: Any] else { continue }
            switch (record["type"] as? String, payload["type"] as? String) {
            case (_, "task_complete"?):
                sawTurnMarker = true
                if tail.lastMessage == nil {
                    tail.lastMessage = MessageText.recap(payload["last_agent_message"] as? String)
                }
            case (_, "turn_aborted"?):
                // Only the newest turn marker can show an interruption: a later prompt starts a new turn.
                if !sawTurnMarker {
                    tail.interrupted = payload["reason"] as? String == "interrupted"
                }
                sawTurnMarker = true
            case (_, "task_started"?):
                sawTurnMarker = true
            case ("response_item"?, "message"?) where payload["role"] as? String == "assistant":
                if tail.lastMessage == nil {
                    // Lines kept apart, so the cleaning can tell a heading from what follows it.
                    tail.lastMessage = MessageText.recap(Self.texts(of: payload).joined(separator: "\n"))
                }
            default:
                break
            }
            if tail.lastMessage != nil, sawTurnMarker {
                break
            }
        }
        return sawRecord ? tail : nil
    }

    private static func texts(of payload: [String: Any]) -> [String] {
        let blocks = payload["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { block in
            guard let text = block["text"] as? String, !text.isEmpty, !InjectedText.isInjected(text) else { return nil }
            return text
        }
    }
}
