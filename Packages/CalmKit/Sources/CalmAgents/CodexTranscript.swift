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
        return SessionHead(id: id, directory: payload["cwd"] as? String, isTerminalSession: startedByTerminal(payload))
    }

    /// Whether a person started this rollout from a terminal's `codex`, from the header's fields
    /// (checked on 184 real rollouts, 2026-09-29):
    ///
    /// - `originator` is `codex-tui` for the terminal (`codex_cli_rs` in early versions) and
    ///   `Codex Desktop` for the app. `source` can't tell them apart: under the shared daemon
    ///   (0.157+) the terminal's own rollouts say `vscode` too, and before it they said `cli`.
    /// - A subagent's thread has `thread_source: "subagent"` and an object for `source`, whoever
    ///   started its parent.
    static func startedByTerminal(_ header: [String: Any]) -> Bool {
        let terminalOriginators = ["codex-tui", "codex_cli_rs"]
        let isSubagent = header["thread_source"] as? String == "subagent" || header["source"] is [String: Any]
        return !isSubagent && terminalOriginators.contains(header["originator"] as? String ?? "")
    }

    public func readTail(of transcript: URL, agentSessionID _: String?, home _: URL) -> TranscriptTail? {
        var tail = TranscriptTail()
        var sawRecord = false
        var sawTurnMarker = false
        for record in JSONLTail(transcript) { // newest first
            sawRecord = true
            guard let payload = record["payload"] as? [String: Any] else { continue }
            switch (record["type"] as? String, payload["type"] as? String) {
            // Only the newest turn marker says where the turn stands: `task_started` opens a turn,
            // `task_complete` ends it, `turn_aborted` is Esc. Codex sends Calm nothing else to
            // say it is working (its notifications only tell a finished turn or an ask, and only
            // while its terminal isn't focused).
            case (_, "task_complete"?):
                if !sawTurnMarker {
                    tail.turn = .finished
                }
                sawTurnMarker = true
                if tail.lastMessage == nil {
                    tail.lastMessage = MessageText.recap(payload["last_agent_message"] as? String)
                }
            case (_, "turn_aborted"?):
                if !sawTurnMarker {
                    tail.interrupted = payload["reason"] as? String == "interrupted"
                }
                sawTurnMarker = true
            case (_, "task_started"?):
                if !sawTurnMarker {
                    tail.turn = .inProgress
                }
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

    public var readsLastReply: Bool {
        true
    }

    public func lastReply(of transcript: URL) -> String? {
        for record in JSONLTail(transcript) {
            guard let payload = record["payload"] as? [String: Any] else { continue }
            let text: String? = switch (record["type"] as? String, payload["type"] as? String) {
            case (_, "task_complete"?): payload["last_agent_message"] as? String
            case ("response_item"?, "message"?) where payload["role"] as? String == "assistant":
                Self.texts(of: payload).joined(separator: "\n\n")
            default: nil
            }
            if let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    private static func texts(of payload: [String: Any]) -> [String] {
        let blocks = payload["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { block in
            guard let text = block["text"] as? String, !text.isEmpty, !InjectedText.isInjected(text) else { return nil }
            return text
        }
    }
}
