import CalmModel
import Foundation

// Record shapes seen in real files on 2026-09-27 (Claude Code 2.1.283, Codex 0.157.1, pi 0.87.1);
// see DESIGNS.md → Agents and Search.

extension ClaudeCodeAdapter: TranscriptIndexing {
    public var transcriptFolders: [String] {
        [".claude/projects"]
    }

    /// Top-level session files only; subagents' transcripts live in `<session>/subagents/`.
    public func isTranscript(_ path: String) -> Bool {
        !path.contains("/subagents/")
    }

    /// `user` records (plain-string or text-block content; not `isMeta`, not tag-wrapped) and
    /// `assistant` text blocks; titles from `custom-title`/`ai-title`.
    public func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage] {
        var messages: [TranscriptMessage] = []
        for record in records {
            if info.agentSessionID == nil {
                info.agentSessionID = record["sessionId"] as? String
            }
            if info.directory == nil {
                info.directory = record["cwd"] as? String
            }
            switch record["type"] as? String {
            case "custom-title":
                info.title = (record["customTitle"] as? String) ?? info.title
            case "ai-title":
                if info.title == nil {
                    info.title = record["aiTitle"] as? String
                }
            case "user" where record["isMeta"] as? Bool != true:
                for text in Self.texts(of: record) where !InjectedText.isInjected(text) {
                    messages.append(TranscriptMessage(.user, text))
                    if info.firstPrompt == nil {
                        info.firstPrompt = HookReport.recap(text, limit: 120)
                    }
                }
            case "assistant":
                for text in Self.texts(of: record) {
                    messages.append(TranscriptMessage(.agent, text))
                }
            default:
                break
            }
        }
        return messages
    }

    private static func texts(of record: [String: Any]) -> [String] {
        guard let message = record["message"] as? [String: Any] else { return [] }
        if let text = message["content"] as? String {
            return text.isEmpty ? [] : [text]
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { block in
            guard block["type"] as? String == "text", let text = block["text"] as? String, !text.isEmpty else { return nil }
            return text
        }
    }
}

extension CodexAdapter: TranscriptIndexing {
    public var transcriptFolders: [String] {
        [".codex/sessions"]
    }

    /// `response_item` messages: user `input_text` (not injected context) and assistant
    /// `output_text`; `developer` messages are Codex's own instructions. `session_meta` holds
    /// the session id and folder.
    public func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage] {
        var messages: [TranscriptMessage] = []
        for record in records {
            guard let payload = record["payload"] as? [String: Any] else { continue }
            switch record["type"] as? String {
            case "session_meta":
                info.agentSessionID = info.agentSessionID ?? (payload["id"] as? String) ?? (payload["session_id"] as? String)
                info.directory = info.directory ?? payload["cwd"] as? String
            case "response_item" where payload["type"] as? String == "message":
                let role: TranscriptMessage.Role
                switch payload["role"] as? String {
                case "user": role = .user
                case "assistant": role = .agent
                default: continue
                }
                let blocks = payload["content"] as? [[String: Any]] ?? []
                for block in blocks {
                    guard let text = block["text"] as? String, !text.isEmpty, !InjectedText.isInjected(text) else { continue }
                    messages.append(TranscriptMessage(role, text))
                    if role == .user, info.firstPrompt == nil {
                        info.firstPrompt = HookReport.recap(text, limit: 120)
                    }
                }
            default:
                break
            }
        }
        return messages
    }
}

extension PiAdapter: TranscriptIndexing {
    public var transcriptFolders: [String] {
        [".pi/agent/sessions"]
    }

    /// `message` records with role `user` or `assistant` and `text` blocks (not `thinking`,
    /// `toolCall`, `toolResult`); `session` holds the id and folder; `session_info` a name.
    public func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage] {
        PiTranscript.messages(in: records, info: &info)
    }
}

extension OmpAdapter: TranscriptIndexing {
    public var transcriptFolders: [String] {
        [".omp/agent/sessions"]
    }

    /// omp is a pi fork with the same records, plus `title_change` (from its docs; omp isn't
    /// installed on the machine these parsers were checked on).
    public func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage] {
        PiTranscript.messages(in: records, info: &info)
    }
}

enum PiTranscript {
    static func messages(in records: [[String: Any]], info: inout TranscriptInfo) -> [TranscriptMessage] {
        var messages: [TranscriptMessage] = []
        for record in records {
            switch record["type"] as? String {
            case "session":
                info.agentSessionID = info.agentSessionID ?? record["id"] as? String
                info.directory = info.directory ?? record["cwd"] as? String
            case "session_info":
                info.title = (record["name"] as? String) ?? info.title
            case "title_change":
                info.title = (record["title"] as? String) ?? info.title
            case "message":
                guard let message = record["message"] as? [String: Any] else { continue }
                let role: TranscriptMessage.Role
                switch message["role"] as? String {
                case "user": role = .user
                case "assistant": role = .agent
                default: continue
                }
                let content = message["content"]
                let texts: [String] = if let text = content as? String {
                    [text]
                } else {
                    (content as? [[String: Any]] ?? []).compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                }
                for text in texts where !text.isEmpty {
                    messages.append(TranscriptMessage(role, text))
                    if role == .user, info.firstPrompt == nil {
                        info.firstPrompt = HookReport.recap(text, limit: 120)
                    }
                }
            default:
                break
            }
        }
        return messages
    }
}
