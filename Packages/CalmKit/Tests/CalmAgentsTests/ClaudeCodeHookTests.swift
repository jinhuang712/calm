@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct ClaudeCodeHookTests {
    private let adapter = ClaudeCodeAdapter()

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/claude-code"))
        return try Data(contentsOf: url)
    }

    @Test func `a prompt starts work`() throws {
        let report = try #require(adapter.hookReport(from: fixture("UserPromptSubmit")))
        #expect(report.state == .working)
        #expect(report.agentSessionID == "4f6b2c1e-0000-4000-8000-000000000001")
        #expect(report.transcriptPath?.hasSuffix("4f6b2c1e-0000-4000-8000-000000000001.jsonl") == true)
    }

    @Test func `a permission request needs you, with what it asks`() throws {
        let report = try #require(adapter.hookReport(from: fixture("PermissionRequest")))
        #expect(report.state == .needsYou)
        #expect(report.message == "Allow Bash: rm -rf build")
    }

    @Test func `only asking notifications need you`() throws {
        #expect(try adapter.hookReport(from: fixture("Notification-permission"))?.state == .needsYou)
        #expect(try adapter.hookReport(from: fixture("Notification-permission"))?.message == "Claude needs your permission to use Bash")
        #expect(try adapter.hookReport(from: fixture("Notification-idle")) == nil)
    }

    @Test func `stop is done, with a one-line recap`() throws {
        let report = try #require(adapter.hookReport(from: fixture("Stop")))
        #expect(report.state == .done)
        #expect(report.message == "Fixed the login test. The mock returned an expired token; it now uses a fresh one. All 42 tests pass.")
    }

    private func payload(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test func `the recap is what Claude said, without its Markdown`() throws {
        let message = "## Short answer\nNothing looks broken. **Two** things on that card are easy to misread.\n\n- the state\n- the title"
        let report = try #require(adapter.hookReport(from: payload(["hook_event_name": "Stop", "last_assistant_message": message])))
        #expect(report.state == .done)
        #expect(report.message == "Nothing looks broken. Two things on that card are easy to misread. the state; the title")
    }

    /// A long reply (5 MB held the hook for 3 s) is read only as far as its recap needs: the
    /// recap is the same as the whole reply's.
    @Test func `a long reply gets the recap the whole of it gives`() throws {
        let reply = "Fixed the parser. The rest is the log, as asked.\n\n```\n" + String(repeating: "log line\n", count: 1000) + "```\n"
            + String(repeating: "Line of the log that goes on and on. ", count: 6000)
        #expect(reply.count > ClaudeCodeAdapter.recapSource * 5)
        let report = try #require(adapter.hookReport(from: payload(["hook_event_name": "Stop", "last_assistant_message": reply])))

        #expect(report.state == .done)
        #expect(report.message == MessageText.recap(reply))
        #expect(report.message?.hasPrefix("Fixed the parser. The rest is the log, as asked. Line of the log") == true)
    }

    /// What someone is asked to allow is the command itself: never Markdown, never rewritten.
    @Test func `a permission request keeps its command as it is`() throws {
        let command = "find . -name '*.py' -o -name '*.js'\n# then\necho `date` | sort **/dist"
        let report = try #require(adapter.hookReport(from: payload([
            "hook_event_name": "PermissionRequest",
            "tool_name": "Bash",
            "tool_input": ["command": command],
        ])))
        #expect(report.message == "Allow Bash: find . -name '*.py' -o -name '*.js' # then echo `date` | sort **/dist")
    }

    /// A Stop whose `background_tasks` holds the given tasks (each a JSON object).
    private func stop(tasks: [String]) -> Data {
        Data(#"{"hook_event_name":"Stop","last_assistant_message":"Done.","background_tasks":[\#(tasks.joined(separator: ","))]}"#.utf8)
    }

    private let shell = #"{"id":"b1","type":"shell","status":"running","description":"Dev server"}"#
    private let agent = #"{"id":"a1","type":"subagent","status":"running","description":"Review the diff"}"#

    @Test func `a stop that leaves a shell running is done, and counts it`() throws {
        let report = try #require(adapter.hookReport(from: fixture("Stop-background")))
        #expect(report.state == .done)
        #expect(report.backgroundShells == 1)
        #expect(report.message == "The install is running. I'll tell you when it's done.")
    }

    @Test func `a stop that leaves a background agent running is still working`() throws {
        let report = try #require(adapter.hookReport(from: stop(tasks: [agent])))
        #expect(report.state == .working)
        #expect(report.backgroundShells == 0)
    }

    @Test func `an agent keeps it working, shells beside it or not`() throws {
        let report = try #require(adapter.hookReport(from: stop(tasks: [shell, agent, shell])))
        #expect(report.state == .working)
    }

    @Test func `shells are counted, a monitor and a kind nobody knows too`() throws {
        let monitor = #"{"id":"m1","type":"shell","status":"running"}"#
        let other = #"{"id":"w1","type":"something-new","status":"running"}"#
        let report = try #require(adapter.hookReport(from: stop(tasks: [shell, monitor, other])))
        #expect(report.state == .done)
        #expect(report.backgroundShells == 3)
    }

    @Test func `tasks that already ended are not running`() throws {
        let ended = ["completed", "failed", "stopped"].map { #"{"id":"x","type":"shell","status":"\#($0)"}"# }
        let endedAgent = #"{"id":"a2","type":"subagent","status":"completed"}"#
        let report = try #require(adapter.hookReport(from: stop(tasks: ended + [endedAgent])))
        #expect(report.state == .done)
        #expect(report.backgroundShells == 0)
    }

    @Test func `pending and status-less tasks are in flight`() throws {
        let pending = #"{"id":"p","type":"shell","status":"pending"}"#
        let bare = #"{"id":"n","type":"shell"}"#
        #expect(try #require(adapter.hookReport(from: stop(tasks: [pending, bare]))).backgroundShells == 2)
        let bareAgent = #"{"id":"a3","type":"subagent"}"#
        #expect(try #require(adapter.hookReport(from: stop(tasks: [bareAgent]))).state == .working)
    }

    @Test func `a stop without the background list is done`() throws {
        let payload = #"{"hook_event_name":"Stop","last_assistant_message":"Done."}"#
        let report = try #require(adapter.hookReport(from: Data(payload.utf8)))
        #expect(report.state == .done)
        #expect(report.backgroundShells == 0)
    }

    @Test func `stop failure is failed`() throws {
        let report = try #require(adapter.hookReport(from: fixture("StopFailure")))
        #expect(report.state == .failed)
        #expect(report.message == "Rate limited; try again in a few minutes.")
    }

    @Test func `other events and bad input change nothing`() throws {
        #expect(try adapter.hookReport(from: fixture("SessionStart")) == nil)
        #expect(adapter.hookReport(from: Data("not json".utf8)) == nil)
        #expect(adapter.hookReport(from: Data("{}".utf8)) == nil)
    }

    @Test func `long messages are cut for the recap`() {
        let long = String(repeating: "word ", count: 100)
        let recap = try? #require(HookReport.recap(long))
        #expect(recap?.count == 280)
        #expect(recap?.hasSuffix("…") == true)
        #expect(HookReport.recap("  \n ") == nil)
    }

    @Test func `the plugin registers every event with a safe command`() throws {
        let files = ClaudeCodeAdapter.pluginFiles()
        let manifest = try #require(files[".claude-plugin/plugin.json"])
        #expect(manifest.contains(#""name" : "calm""#))
        let hooks = try #require(files["hooks/hooks.json"])
        for event in ClaudeCodeAdapter.hookEvents {
            #expect(hooks.contains("\"\(event)\""))
        }
        // Silent and harmless outside Calm.
        #expect(hooks.contains(#"[ -n \"$CALM_CLI\" ]"#))
        #expect(hooks.contains("|| true"))
    }

    @Test func `the hook name finds the adapter`() {
        #expect(Agents.hookReporter(named: "claude-code")?.kind == .claudeCode)
        #expect(Agents.hookReporter(named: "nothing") == nil)
    }
}
