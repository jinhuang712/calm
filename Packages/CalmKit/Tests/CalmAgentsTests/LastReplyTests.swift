@testable import CalmAgents
import CalmModel
import Foundation
import Testing

/// "Copy Last Reply" (FEATURES.md → Command palette): the agent's newest message as it wrote it,
/// where `readTail`'s `lastMessage` is a recap cut to a line.
struct LastReplyTests {
    private func transcript(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-reply-\(UUID().uuidString).jsonl")
        try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
        return url
    }

    private func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private let reply = "## Done\n\nAdded `retry` to the fetcher.\n\n- three attempts\n- backoff"

    // MARK: Claude Code

    private func claude(_ content: [[String: Any]]) -> String {
        json(["type": "assistant", "message": ["role": "assistant", "content": content]])
    }

    @Test func `the last reply of Claude Code keeps its Markdown where the recap flattens it`() throws {
        let url = try transcript([
            json(["type": "user", "message": ["role": "user", "content": "add a retry"]]),
            claude([["type": "text", "text": reply]]),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = ClaudeCodeAdapter()
        #expect(adapter.lastReply(of: url) == reply)
        let recap = try #require(adapter.readTail(of: url, agentSessionID: nil, home: url)?.lastMessage)
        #expect(recap != reply)
        #expect(!recap.contains("\n"))
    }

    @Test func `the newest Claude Code message with text wins over a later tool call`() throws {
        let url = try transcript([
            claude([["type": "text", "text": reply]]),
            claude([["type": "tool_use", "id": "t1", "name": "Bash", "input": [String: String]()]]),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ClaudeCodeAdapter().lastReply(of: url) == reply)
    }

    @Test func `a transcript with no message has no reply`() throws {
        let url = try transcript([json(["type": "user", "message": ["role": "user", "content": "hi"]])])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(ClaudeCodeAdapter().lastReply(of: url) == nil)
        #expect(ClaudeCodeAdapter().lastReply(of: url.appendingPathExtension("missing")) == nil)
    }

    // MARK: Codex

    private func codexMessage(_ text: String) -> String {
        json(["type": "response_item", "payload": [
            "type": "message", "role": "assistant", "content": [["type": "output_text", "text": text]],
        ]])
    }

    @Test func `a finished Codex turn gives the message it ended on`() throws {
        let url = try transcript([
            codexMessage("an earlier message"),
            json(["type": "event_msg", "payload": ["type": "task_complete", "last_agent_message": reply]]),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CodexAdapter().lastReply(of: url) == reply)
    }

    @Test func `the newest Codex assistant message is the reply while a turn runs`() throws {
        let url = try transcript([
            codexMessage("an earlier message"),
            codexMessage(reply),
            json(["type": "event_msg", "payload": ["type": "task_started"]]),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(CodexAdapter().lastReply(of: url) == reply)
    }

    // MARK: pi

    @Test func `pi's newest assistant message is the reply, past a tool result`() throws {
        let url = try transcript([
            json(["type": "message", "message": ["role": "assistant", "content": [["type": "text", "text": reply]], "stopReason": "stop"]]),
            json(["type": "message", "message": ["role": "toolResult", "content": [["type": "text", "text": "ok"]]]]),
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PiAdapter().lastReply(of: url) == reply)
    }

    // MARK: Which agents can

    @Test func `the agents that keep a transcript file say they can, OpenCode does not`() throws {
        #expect(ClaudeCodeAdapter().readsLastReply)
        #expect(CodexAdapter().readsLastReply)
        #expect(PiAdapter().readsLastReply)
        #expect(!OpenCodeAdapter().readsLastReply)
        let url = try transcript([claude([["type": "text", "text": reply]])])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(OpenCodeAdapter().lastReply(of: url) == nil)
    }
}
