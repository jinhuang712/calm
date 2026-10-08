@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct ClaudeCodeActivityTests {
    private let adapter = ClaudeCodeAdapter()

    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/claude-code"))
        return try Data(contentsOf: url)
    }

    @Test func `a prompt says thinking, a tool call begins a step and its result ends it`() throws {
        #expect(try adapter.hookReport(from: fixture("UserPromptSubmit"))?.activity == .thinking)
        let bash = try #require(adapter.hookReport(from: fixture("PreToolUse-Bash")))
        #expect(bash.state == .working)
        #expect(bash.activity == .began(AgentActivity("Running the full test suite", group: "Running # commands")))
        #expect(try adapter.hookReport(from: fixture("PostToolUse-Bash"))?.activity == .ended)
        let read = try adapter.hookReport(from: fixture("PreToolUse-Read"))
        #expect(read?.activity == .began(AgentActivity("Reading SessionCard.swift", group: "Reading # files")))
    }

    @Test func `a failed call ends its step and says nothing of the state, an Esc nothing at all`() throws {
        let failed = #"{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{"command":"swift test"},"#
            + #""error":"Exit code 1"}"#
        let report = try #require(adapter.hookReport(from: Data(failed.utf8)))
        #expect(report.activity == .ended)
        #expect(!report.changesState)
        let interrupted = #"{"hook_event_name":"PostToolUseFailure","tool_name":"Bash","tool_input":{},"error":"x","is_interrupt":true}"#
        #expect(adapter.hookReport(from: Data(interrupted.utf8)) == nil)
        #expect(ClaudeCodeAdapter.hookEvents.contains("PostToolUseFailure"))
        // Every other hook says the state, as before.
        #expect(try adapter.hookReport(from: fixture("PostToolUse-Bash"))?.changesState == true)
    }

    @Test func `bookkeeping leaves the line alone, both halves`() throws {
        // Both halves say nothing, so a step running beside it isn't counted as ended.
        let pre = try #require(adapter.hookReport(from: fixture("PreToolUse-TaskUpdate")))
        #expect(pre.state == .working)
        #expect(pre.activity == nil)
        #expect(try adapter.hookReport(from: fixture("PostToolUse-TaskUpdate"))?.activity == nil)
    }

    @Test func `an input that isn't text loses only itself, never the hook`() throws {
        let payload = #"{"hook_event_name":"PermissionRequest","tool_name":"mcp__x__fetch","tool_input":{"url":["a","b"],"description":7}}"#
        let report = try #require(adapter.hookReport(from: Data(payload.utf8)))
        #expect(report.state == .needsYou)
        #expect(report.message == "Allow mcp__x__fetch?")
    }

    @Test func `each tool in words`() {
        typealias Input = ClaudeCodeAdapter.Payload.ToolInput
        func words(_ tool: String, _ input: Input = Input()) -> String? {
            ClaudeCodeAdapter.activity(tool: tool, input: input)?.words
        }
        #expect(words("Edit", Input(filePath: "/a/UIUX.md")) == "Editing UIUX.md")
        #expect(words("Write", Input(filePath: "/a/make_fixture.py")) == "Writing make_fixture.py")
        #expect(words("NotebookEdit", Input(notebookPath: "/a/plot.ipynb")) == "Editing plot.ipynb")
        #expect(words("Bash", Input(command: "cd app && swift test --filter X")) == "Running swift test")
        #expect(words("Bash") == "Running a command")
        #expect(words("Grep") == "Searching the code")
        #expect(words("WebSearch") == "Searching the web")
        #expect(words("WebFetch", Input(url: "https://developer.apple.com/documentation/swiftui")) == "Reading developer.apple.com")
        #expect(words("Agent", Input(description: "Locate the card's status code")) == "Locating the card's status code")
        #expect(words("Skill", Input(skill: "playwright-cli")) == "Using playwright-cli")
        #expect(words("mcp__claude_ai_Google_Drive__search_files") == "Using Google Drive")
        #expect(words("mcp__plugin_design_figma__get_file") == "Using figma")
        #expect(words("mcp__334af37d-995a-412a-8b78-81c3a12ff3e9__run") == "Using a connector")
        #expect(words("Artifact") == "Using Artifact")
        #expect(words("ToolSearch") == nil)
        #expect(words("AskUserQuestion") == nil)
        #expect(ClaudeCodeAdapter.activity(tool: nil, input: nil) == nil)
    }

    @Test func `a description becomes what Claude is doing`() {
        // First words as counted in the author's transcripts (2026-10-09).
        #expect(ActivityWords.ongoing("Run the full CalmKit test suite") == "Running the full CalmKit test suite")
        #expect(ActivityWords.ongoing("Read the session probe's timer") == "Reading the session probe's timer")
        #expect(ActivityWords.ongoing("Write the fixture and README note") == "Writing the fixture and README note")
        #expect(ActivityWords.ongoing("Show changed files") == "Showing changed files")
        #expect(ActivityWords.ongoing("Stop the server") == "Stopping the server")
        #expect(ActivityWords.ongoing("Commit the fix") == "Committing the fix")
        #expect(ActivityWords.ongoing("Edit the card") == "Editing the card")
        #expect(ActivityWords.ongoing("See what changed") == "Seeing what changed")
        #expect(ActivityWords.ongoing("Use the cache") == "Using the cache")
        #expect(ActivityWords.ongoing("Tidy the imports") == "Tidying the imports")
        #expect(ActivityWords.ongoing("Snapshot the card") == "Snapshotting the card")
        #expect(ActivityWords.ongoing("Re-run the tests") == "Re-running the tests")
        #expect(ActivityWords.ongoing("Fast-forward main") == "Fast-forwarding main")
        #expect(ActivityWords.ongoing("Lint, build and test") == "Linting, build and test")
        #expect(ActivityWords.ongoing("Build") == "Building")
        #expect(ActivityWords.ongoing("Debug the crash") == "Debugging the crash")
        #expect(ActivityWords.ongoing("Format sources") == "Formatting sources")
        #expect(ActivityWords.ongoing("Dry-run the release") == "Dry-running the release")
        // A hyphenated noun isn't a verb.
        #expect(ActivityWords.ongoing("Pre-commit checks") == "Pre-commit checks")
        #expect(ActivityWords.ongoing("Run-time check") == "Run-time check")
        // Not a verb on the list: as it is, never wrong English.
        #expect(ActivityWords.ongoing("No-op build to confirm") == "No-op build to confirm")
        #expect(ActivityWords.ongoing("Full rebuild") == "Full rebuild")
        #expect(ActivityWords.ongoing("  ") == nil)
    }

    @Test func `a command's program, past the setting up`() {
        #expect(ActivityWords.program("git status --short") == "git status")
        #expect(ActivityWords.program("cd /x && swift test 2>&1 | tail") == "swift test")
        #expect(ActivityWords.program("env FOO=1 taskpolicy -b mise run test") == "mise run")
        #expect(ActivityWords.program("FOO=1 /usr/bin/grep -n x file") == "grep")
        #expect(ActivityWords.program("python3 /tmp/x.py") == "python3")
        #expect(ActivityWords.program("cd /x") == nil)
        #expect(ActivityWords.program("# check what's there\nls -la") == "ls")
    }
}
