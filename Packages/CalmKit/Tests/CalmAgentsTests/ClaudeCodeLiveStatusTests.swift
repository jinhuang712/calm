@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct ClaudeCodeLiveStatusTests {
    private let adapter = ClaudeCodeAdapter()

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/claude-code"))
        return try Data(contentsOf: url)
    }

    @Test func `busy and idle read with the time the agent changed`() throws {
        let busy = try #require(ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-status-busy.json"), processID: 4242))
        #expect(busy.phase == .busy)
        #expect(busy.since == Date(timeIntervalSince1970: 1_790_691_945.147))

        let idle = try #require(ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-status-idle.json"), processID: 4242))
        #expect(idle.phase == .idle)
        #expect(idle.since == Date(timeIntervalSince1970: 1_790_692_115.226))
    }

    @Test func `waiting reads as waiting, whatever it waits for`() throws {
        let waiting = try #require(ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-status-waiting.json"), processID: 4242))
        #expect(waiting.phase == .waiting)
    }

    @Test func `wording it doesn't know reads as nothing known`() throws {
        #expect(try ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-status-unknown.json"), processID: 4242) == nil)
    }

    @Test func `a status without a time reads as nothing known`() throws {
        // The older fixture has `status` but no `statusUpdatedAt`.
        #expect(try ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-4242.json"), processID: 4242) == nil)
    }

    @Test func `another process's file reads as nothing known`() throws {
        #expect(try ClaudeCodeAdapter.liveStatus(fromSessionFile: fixture("session-status-other-pid.json"), processID: 4242) == nil)
    }

    @Test func `damaged files read as nothing known`() {
        for text in [
            "",
            "not json",
            "[]",
            "{}",
            #"{"pid":4242,"status":"busy","statusUpdatedAt":"soon"}"#,
            #"{"pid":4242,"status":"busy","statusUpdatedAt":0}"#,
        ] {
            #expect(ClaudeCodeAdapter.liveStatus(fromSessionFile: Data(text.utf8), processID: 4242) == nil, "\(text)")
        }
    }

    @Test func `reads the file of the process from a home folder`() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-claude-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let sessions = home.appending(path: ".claude/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try fixture("session-status-busy.json").write(to: sessions.appending(path: "4242.json"))
        #expect(adapter.liveStatus(processID: 4242, home: home)?.phase == .busy)
        // No file for another process, and none at all in an empty home.
        #expect(adapter.liveStatus(processID: 4243, home: home) == nil)
        #expect(adapter.liveStatus(processID: 4242, home: home.appending(path: "nowhere")) == nil)
    }

    @Test func `only Claude Code keeps a status file so far`() {
        #expect(Agents.liveStatusReader(for: .claudeCode) != nil)
        #expect(Agents.liveStatusReader(for: .codex) == nil)
    }
}
