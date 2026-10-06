import CalmModel
import Foundation

/// Claude Code's files, as seen on 2026-09-27 (version 2.1.283):
///
/// - `~/.claude/sessions/<pid>.json`: `{pid, sessionId, cwd, name, status, …}` per running
///   process (undocumented; a hint only).
/// - `~/.claude/projects/<folder, non-alphanumerics → ->/<sessionId>.jsonl`: one JSON record
///   per line. `ai-title` (`aiTitle`) and `custom-title` (`customTitle`) recur through the file;
///   `assistant` records hold `message.content[]` blocks (`text`, `tool_use`, `thinking`); an
///   interrupted turn leaves a `user` record whose text starts with "[Request interrupted".
///   The folder can differ from the session's current one, so a hook's `transcript_path` wins.
/// - A `system` record with `subtype: "away_summary"` holds Claude's recap (`content`): where the
///   conversation stands and what's next, the "※ recap:" line it prints about three minutes
///   after a turn ends (seen 2026-09-30, versions 2.1.260 to 2.1.284). Most end with the hint
///   "(disable recaps in /config)".
/// - `~/.claude/tasks/<sessionId>/<n>.json`: `{id, subject, activeForm, status}` per todo.
/// - Compaction (2.1.291, 2026-10-06): an `assistant` record's `message.usage` counts the context
///   it saw (`input_tokens` + `cache_creation_input_tokens` + `cache_read_input_tokens` +
///   `output_tokens`; in the author's 15 compactions, within 1.4% of the compaction's own count).
///   A compaction that finished leaves a `system` record, `subtype: "compact_boundary"`, whose
///   `compactMetadata` holds `trigger`, `preTokens`, `postTokens` and `durationMs`, then a `user`
///   record with `isCompactSummary`. One cancelled with Esc leaves only a `user` record. Every
///   record carries an ISO 8601 `timestamp`.
extension ClaudeCodeAdapter: TranscriptReading {
    public func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)? {
        let claude = home.appending(path: ".claude")
        guard let data = try? Data(contentsOf: claude.appending(path: "sessions/\(processID).json")),
              let session = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = session["sessionId"] as? String
        else { return nil }
        let projects = claude.appending(path: "projects")
        if let cwd = session["cwd"] as? String {
            let url = projects.appending(path: Self.projectFolder(for: cwd)).appending(path: "\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: url.path) {
                return (sessionID, url)
            }
        }
        // The session may have moved folders; look for its file in any project.
        let folders = (try? FileManager.default.contentsOfDirectory(atPath: projects.path)) ?? []
        for folder in folders {
            let url = projects.appending(path: folder).appending(path: "\(sessionID).jsonl")
            if FileManager.default.fileExists(atPath: url.path) {
                return (sessionID, url)
            }
        }
        return nil
    }

    public func readTail(of transcript: URL, agentSessionID: String?, home: URL) -> TranscriptTail? {
        var tail = TranscriptTail()
        var customTitle: String?
        var aiTitle: String?
        var sawConversation = false
        var sawRecord = false
        for record in JSONLTail(transcript) { // newest first
            sawRecord = true
            // Every conversation record says where Claude was when it wrote it; the newest one
            // is where it is now (`~/.claude/sessions/<pid>.json` keeps the launch folder).
            if tail.directory == nil, let cwd = record["cwd"] as? String, !cwd.isEmpty {
                tail.directory = cwd
            }
            switch record["type"] as? String {
            case "custom-title" where customTitle == nil:
                customTitle = record["customTitle"] as? String
            case "ai-title" where aiTitle == nil:
                aiTitle = record["aiTitle"] as? String
            case "assistant":
                if tail.lastMessage == nil {
                    // Lines kept apart, so the cleaning can tell a heading from what follows it.
                    tail.lastMessage = MessageText.recap(Self.texts(of: record).joined(separator: "\n"))
                }
                if tail.contextTokens == nil, record["isSidechain"] as? Bool != true {
                    tail.contextTokens = Self.contextTokens(of: record)
                }
                tail.newestMessageAt = tail.newestMessageAt ?? Self.date(of: record)
                sawConversation = true
            case "user":
                // The summary a compaction leaves is part of the compaction, not a message after it.
                if record["isCompactSummary"] as? Bool != true {
                    tail.newestMessageAt = tail.newestMessageAt ?? Self.date(of: record)
                }
                // Only the newest conversation record can show an interruption.
                if !sawConversation {
                    tail.interrupted = Self.texts(of: record).contains { $0.hasPrefix("[Request interrupted") }
                }
                sawConversation = true
            case "system" where record["subtype"] as? String == "compact_boundary":
                if tail.lastCompaction == nil, let date = Self.date(of: record) {
                    let metadata = record["compactMetadata"] as? [String: Any]
                    tail.lastCompaction = CompactedContext(
                        date: date, tokensBefore: metadata?["preTokens"] as? Int, tokensAfter: metadata?["postTokens"] as? Int,
                    )
                }
            case "system" where record["subtype"] as? String == "away_summary":
                // Only a recap newer than every message: a turn after it has moved on.
                if !sawConversation, tail.summary == nil {
                    tail.summary = Self.summary(record["content"] as? String)
                }
            default:
                break
            }
            if customTitle != nil, tail.lastMessage != nil, tail.directory != nil {
                break
            }
        }
        guard sawRecord else { return nil }
        tail.title = [customTitle, aiTitle].compactMap(\.self).first { !$0.isEmpty }
        let sessionID = agentSessionID ?? transcript.deletingPathExtension().lastPathComponent
        let (step, progress) = Self.todos(in: home.appending(path: ".claude/tasks/\(sessionID)"))
        tail.step = step
        tail.progress = progress
        return tail
    }

    public var readsLastReply: Bool {
        true
    }

    public func lastReply(of transcript: URL) -> String? {
        for record in JSONLTail(transcript) where record["type"] as? String == "assistant" {
            let text = Self.texts(of: record).joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// `/Users/me/src/app` → `-Users-me-src-app`: every character that isn't a letter or digit
    /// becomes a hyphen.
    static func projectFolder(for path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
    }

    /// A recap as plain text, without the hint Claude adds for the terminal.
    static func summary(_ content: String?) -> String? {
        guard var text = content?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        let hint = "(disable recaps in /config)"
        if text.hasSuffix(hint) {
            text = String(text.dropLast(hint.count))
        }
        return MessageText.recap(text)
    }

    /// The context the reply saw: everything sent to the model, cached or not, and what it wrote.
    static func contextTokens(of record: [String: Any]) -> Int? {
        guard let usage = (record["message"] as? [String: Any])?["usage"] as? [String: Any] else { return nil }
        let counts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
            .compactMap { usage[$0] as? Int }
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }

    /// A record's `timestamp`: "2026-10-06T15:42:35.880Z", sometimes without the milliseconds.
    static func date(of record: [String: Any]) -> Date? {
        guard let text = record["timestamp"] as? String else { return nil }
        return (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
            ?? (try? Date(text, strategy: .iso8601))
    }

    private static func texts(of record: [String: Any]) -> [String] {
        guard let message = record["message"] as? [String: Any] else { return [] }
        if let text = message["content"] as? String {
            return [text]
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }

    private static func todos(in folder: URL) -> (step: String?, progress: TodoProgress?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let tasks = files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? JSONSerialization.jsonObject(with: Data(contentsOf: $0)) as? [String: Any] }
        guard !tasks.isEmpty else { return (nil, nil) }
        let done = tasks.count { $0["status"] as? String == "completed" }
        let current = tasks.first { $0["status"] as? String == "in_progress" }
        let step = (current?["activeForm"] as? String) ?? (current?["subject"] as? String)
        return (step, TodoProgress(done: done, total: tasks.count))
    }
}
