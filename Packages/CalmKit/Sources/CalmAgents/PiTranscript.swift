import CalmModel
import Foundation

/// pi's session files, as seen on 2026-09-29 (0.87.1, 192 sessions on the machine this was
/// checked on):
///
/// - `~/.pi/agent/sessions/--<folder>--/<timestamp>_<uuid>.jsonl`, one JSON record per line.
///   The header is `session` (`id`, `cwd`). `message` records hold `message.role` `user`,
///   `assistant`, `toolResult`…; an assistant message has `content[]` blocks (`text`,
///   `thinking`, `toolCall`) and a `stopReason`: `stop`, `toolUse`, `error`, or `aborted` when
///   the user interrupted. pi names a session with `session_info` (`name`).
/// - A record can be megabytes (tool results): the tail reader steps past long lines.
/// - No todo records, so a pi card has a title, a recap and an interruption but no step or
///   progress.
///
/// The search parser for the same files is in `TranscriptParsers.swift`.
extension PiTranscript {
    static func head(of url: URL) -> SessionHead? {
        guard let record = TranscriptDiscovery.firstRecord(of: url), record["type"] as? String == "session",
              let id = record["id"] as? String
        else { return nil }
        return SessionHead(id: id, directory: record["cwd"] as? String)
    }

    static func readTail(of transcript: URL) -> TranscriptTail? {
        var tail = TranscriptTail()
        var sawRecord = false
        var sawConversation = false
        var title: String?
        for record in JSONLTail(transcript) { // newest first
            sawRecord = true
            switch record["type"] as? String {
            case "session_info" where title == nil:
                title = Self.title(record["name"])
            case "message":
                let message = record["message"] as? [String: Any] ?? [:]
                switch message["role"] as? String {
                case "assistant":
                    // Only the newest conversation record can show an interruption.
                    if !sawConversation {
                        tail.interrupted = message["stopReason"] as? String == "aborted"
                    }
                    sawConversation = true
                    if tail.lastMessage == nil {
                        // Lines kept apart, so the cleaning can tell a heading from what follows it.
                        tail.lastMessage = MessageText.recap(texts(of: message).joined(separator: "\n"))
                    }
                case "user":
                    sawConversation = true
                default:
                    break
                }
            default:
                break
            }
        }
        guard sawRecord else { return nil }
        tail.title = title
        return tail
    }

    private static func title(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private static func texts(of message: [String: Any]) -> [String] {
        if let text = message["content"] as? String {
            return [text]
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
    }
}

extension PiAdapter: TranscriptReading {
    public func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)? {
        Self.transcript(facts: ProcessFacts.of(processID), home: home)
    }

    /// pi's extension reports its session file when it is connected (and then this isn't
    /// asked). Without it: the only session for the folder written since pi started.
    static func transcript(facts: ProcessFacts, home: URL) -> (agentSessionID: String, url: URL)? {
        let root = home.appending(path: ".pi/agent/sessions")
        return TranscriptDiscovery.locate(
            facts: facts,
            roots: [root],
            candidates: { TranscriptDiscovery.files(inFoldersOf: root, extension: "jsonl", since: facts.started) },
            head: PiTranscript.head(of:),
        )
    }

    public func readTail(of transcript: URL, agentSessionID _: String?, home _: URL) -> TranscriptTail? {
        PiTranscript.readTail(of: transcript)
    }
}
