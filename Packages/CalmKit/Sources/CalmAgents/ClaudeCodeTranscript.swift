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
/// - `~/.claude/tasks/<sessionId>/<n>.json`: `{id, subject, activeForm, status}` per todo.
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
        let records = JSONLTail.records(at: transcript)
        guard !records.isEmpty else { return nil }
        var tail = TranscriptTail()
        var customTitle: String?
        var aiTitle: String?
        var sawConversation = false
        for record in records { // newest first
            switch record["type"] as? String {
            case "custom-title" where customTitle == nil:
                customTitle = record["customTitle"] as? String
            case "ai-title" where aiTitle == nil:
                aiTitle = record["aiTitle"] as? String
            case "assistant":
                if tail.lastMessage == nil {
                    tail.lastMessage = HookReport.recap(Self.texts(of: record).joined(separator: " "))
                }
                sawConversation = true
            case "user":
                // Only the newest conversation record can show an interruption.
                if !sawConversation {
                    tail.interrupted = Self.texts(of: record).contains { $0.hasPrefix("[Request interrupted") }
                }
                sawConversation = true
            default:
                break
            }
            if customTitle != nil, tail.lastMessage != nil {
                break
            }
        }
        tail.title = [customTitle, aiTitle].compactMap(\.self).first { !$0.isEmpty }
        let sessionID = agentSessionID ?? transcript.deletingPathExtension().lastPathComponent
        let (step, progress) = Self.todos(in: home.appending(path: ".claude/tasks/\(sessionID)"))
        tail.step = step
        tail.progress = progress
        return tail
    }

    /// `/Users/me/src/app` → `-Users-me-src-app`: every character that isn't a letter or digit
    /// becomes a hyphen.
    static func projectFolder(for path: String) -> String {
        String(path.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
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
