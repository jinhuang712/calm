import CalmModel
import Foundation

/// The working line for Claude Code (UIUX.md → Session cards): each tool call's PreToolUse and
/// PostToolUse hooks, which Calm already hears, say what it's doing. The tool names and inputs are
/// Claude Code's own (2.1.291, 2026-10-09); counts of how often each runs are from the author's
/// transcripts, so the common ones read best.
extension ClaudeCodeAdapter {
    /// What a tool call is, in words: "Reading SessionCard.swift", "Running the full test suite"
    /// (Claude's own description of a command, which it gives for 86% of them). Nil for Claude's
    /// bookkeeping (its todo list, finding a tool, asking you), which leaves the line as it was.
    static func activity(tool: String?, input: Payload.ToolInput?) -> AgentActivity? {
        guard let tool else { return nil }
        let file = (input?.filePath ?? input?.notebookPath).map { URL(filePath: $0).lastPathComponent }
        switch tool {
        case "Read":
            return AgentActivity(file.map { "Reading \($0)" } ?? "Reading", group: "Reading # files")
        case "Edit", "MultiEdit", "NotebookEdit":
            return AgentActivity(file.map { "Editing \($0)" } ?? "Editing", group: "Editing # files")
        case "Write":
            return AgentActivity(file.map { "Writing \($0)" } ?? "Writing", group: "Writing # files")
        case "Bash":
            let words = input?.description.flatMap(ActivityWords.ongoing)
                ?? input?.command.flatMap(ActivityWords.program).map { "Running \($0)" }
                ?? "Running a command"
            return AgentActivity(words, group: "Running # commands")
        case "Grep", "Glob", "LSP":
            return AgentActivity("Searching the code")
        case "WebSearch":
            return AgentActivity("Searching the web")
        case "WebFetch":
            let host = input?.url.flatMap { URL(string: $0)?.host() }
            return AgentActivity(host.map { "Reading \($0)" } ?? "Reading the web", group: "Reading # pages")
        case "Task", "Agent":
            let words = input?.description.flatMap(ActivityWords.ongoing) ?? "Running an agent"
            return AgentActivity(words, group: "Running # agents")
        case "Skill":
            return AgentActivity(input?.skill.map { "Using \($0)" } ?? "Using a skill")
        case _ where bookkeeping.contains(tool):
            return nil
        case _ where tool.hasPrefix("mcp__"):
            return AgentActivity("Using \(server(of: tool))")
        default:
            return AgentActivity("Using \(tool)")
        }
    }

    /// Claude's own housekeeping: quick, and not what the turn is about.
    private static let bookkeeping: Set = [
        "TodoWrite", "TaskCreate", "TaskUpdate", "TaskList", "TaskGet", "TaskOutput", "TaskStop", "BashOutput", "KillShell",
        "KillBash", "ToolSearch", "AskUserQuestion", "EnterPlanMode", "ExitPlanMode", "ReadNotifications", "ListAgents",
        "SendMessage", "SendFeedback", "PushNotification", "ScheduleWakeup",
    ]

    /// An MCP tool's server, as people know it: "mcp__claude_ai_Google_Drive__search" → "Google
    /// Drive", "mcp__plugin_design_figma__x" → "figma"; a server named by an id is "a connector".
    static func server(of tool: String) -> String {
        let parts = tool.components(separatedBy: "__")
        guard parts.count > 1 else { return tool }
        var name = parts[1]
        if name.hasPrefix("claude_ai_") {
            name.removeFirst("claude_ai_".count)
        } else if name.hasPrefix("plugin_"), let last = name.split(separator: "_").last {
            name = String(last)
        }
        if UUID(uuidString: name) != nil || name.isEmpty {
            return "a connector"
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }
}
