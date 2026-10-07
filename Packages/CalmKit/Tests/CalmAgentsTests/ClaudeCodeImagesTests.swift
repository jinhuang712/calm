@testable import CalmAgents
import Foundation
import Testing

struct ClaudeCodeImagesTests {
    private let sessionID = "4f6b2c1e-0000-4000-8000-000000000002"
    private let uid: uid_t = 501

    /// A temporary folder holding a home with the running session's file, and Claude Code's
    /// temporary folder (`CLAUDE_CODE_TMPDIR`).
    private struct Layout {
        let base: URL
        var home: URL {
            base.appending(path: "home")
        }

        var tmp: URL {
            base.appending(path: "tmp")
        }

        @discardableResult
        func paste(_ number: Int, project: String = "-Users-me-src-app", session: String) throws -> URL {
            let folder = tmp.appending(path: "claude-501/\(project)/\(session)/images")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "\(number).png")
            try Data([0x89, 0x50, 0x4E, 0x47]).write(to: url)
            return url
        }
    }

    private func makeLayout() throws -> Layout {
        let layout = Layout(base: FileManager.default.temporaryDirectory.appending(path: "calm-images-\(UUID().uuidString)"))
        let sessions = layout.home.appending(path: ".claude/sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let fixture = try #require(Bundle.module.url(
            forResource: "session-2.1.291.json",
            withExtension: nil,
            subdirectory: "Fixtures/claude-code",
        ))
        try FileManager.default.copyItem(at: fixture, to: sessions.appending(path: "4343.json"))
        return layout
    }

    private func find(_ number: Int, in layout: Layout, processID: Int32 = 4343, agentSessionID: String? = nil) -> URL? {
        let query = PastedImageQuery(
            number: number, processID: processID, agentSessionID: agentSessionID,
            home: layout.home, environment: ["CLAUDE_CODE_TMPDIR": layout.tmp.path],
        )
        return ClaudeCodeAdapter.pastedImage(query, uid: uid)
    }

    @Test func `the tag's pattern captures its number`() throws {
        let pattern = try NSRegularExpression(pattern: ClaudeCodeAdapter().pastedImagePattern)
        let text = "look at [Image #12] and [Image #3]" as NSString
        let numbers = pattern.matches(in: text as String, range: NSRange(location: 0, length: text.length)).map {
            text.substring(with: $0.range(at: 1))
        }
        #expect(numbers == ["12", "3"])
        #expect(Agents.pastedImageResolver(for: .claudeCode) != nil)
        #expect(Agents.pastedImageResolver(for: .codex) == nil)
    }

    @Test func `the running session's file finds the folder`() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let image = try layout.paste(3, session: sessionID)
        #expect(find(3, in: layout) == image)
        #expect(find(4, in: layout) == nil)
        #expect(find(0, in: layout) == nil)
    }

    @Test func `a session whose folder moved is found by scanning`() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let image = try layout.paste(1, project: "-Users-me-src-elsewhere", session: sessionID)
        #expect(find(1, in: layout) == image)
    }

    @Test func `the running session is asked before the hooks, and with no process the hooks are`() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        let running = try layout.paste(1, session: sessionID)
        let reported = try layout.paste(1, session: "from-hooks")
        #expect(find(1, in: layout, agentSessionID: "from-hooks") == running)
        #expect(find(1, in: layout, processID: 0, agentSessionID: "from-hooks") == reported)
        #expect(find(1, in: layout, processID: 0) == nil)
    }

    @Test func `a tag from before a clear finds nothing rather than another image`() throws {
        let layout = try makeLayout()
        defer { try? FileManager.default.removeItem(at: layout.base) }
        // #1 was pasted before the /clear; the numbers went on, so the new session has #2.
        try layout.paste(1, session: "before-clear")
        try layout.paste(2, session: sessionID)
        #expect(find(1, in: layout) == nil)
        #expect(find(2, in: layout) != nil)
    }
}
