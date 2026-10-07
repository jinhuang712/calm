import CalmModel
import Testing

/// ⌘N's settings in config.toml (FEATURES.md → New agent sessions): which agent, its options, the
/// flags and the whole command typed as written, each agent in a `[agents.<agent>]` section, and
/// quotes in those strings surviving a write and a read.
struct AgentLaunchSettingsTests {
    @Test func `an agent's name in config.toml goes both ways`() {
        for kind in AgentKind.allCases {
            #expect(AgentKind(configName: kind.configName) == kind)
        }
        #expect(AgentKind(configName: "Claude-Code") == .claudeCode)
        #expect(AgentKind(configName: "claudeCode") == nil)
    }

    @Test func `the agent ⌘N starts is the one config.toml names, if it names one Calm knows`() {
        #expect(CalmSettings(text: "[agents]\nnew-session = \"codex\"\n").newSessionAgent == .codex)
        #expect(CalmSettings(text: "[agents]\nnew-session = \"cursor\"\n").newSessionAgent == nil)
        #expect(CalmSettings().newSessionAgent == nil)
    }

    @Test func `an option is off until the agent's section turns it on`() {
        let settings = CalmSettings(text: "[agents.claude-code]\nworktree = true\n\n[agents.codex]\nworktree = false\n")
        #expect(settings.isOn("worktree", of: .claudeCode))
        #expect(!settings.isOn("worktree", of: .codex))
        #expect(!settings.isOn("skip-permissions", of: .claudeCode))
        #expect(CalmSettings.launchOptionKey("skip-permissions", of: .openCode) == "agents.opencode.skip-permissions")
    }

    @Test func `extra flags and the whole command are read as written, and blank ones are none`() {
        let text = "[agents.claude-code]\nflags = \"--model opus\"\ncommand = \"claude -w\"\n\n[agents.pi]\nflags = \"  \"\n"
        let settings = CalmSettings(text: text)
        #expect(settings.extraFlags(of: .claudeCode) == "--model opus")
        #expect(settings.command(of: .claudeCode) == "claude -w")
        #expect(settings.extraFlags(of: .pi) == nil)
        #expect(settings.command(of: .codex) == nil)
    }

    @Test func `a key with two dots is written in its agent's own section`() {
        var text = CalmSettings.setting("agents.sound", to: "true", in: "")
        text = CalmSettings.setting("agents.claude-code.worktree", to: "true", in: text)
        text = CalmSettings.setting("agents.claude-code.command", to: "claude -w", in: text)
        #expect(text == "[agents]\nsound = true\n\n[agents.claude-code]\nworktree = true\ncommand = \"claude -w\"\n")
        let removed = CalmSettings.removing("agents.claude-code.worktree", in: text)
        #expect(removed == "[agents]\nsound = true\n\n[agents.claude-code]\ncommand = \"claude -w\"\n")
        #expect(CalmSettings(text: removed).command(of: .claudeCode) == "claude -w")
    }

    @Test func `flags with quotes and backslashes survive a write and a read`() {
        let flags = #"--append-system-prompt "be brief, \ no # comments""#
        let text = CalmSettings.setting("agents.claude-code.flags", to: flags, in: "")
        #expect(text.contains(#"flags = "--append-system-prompt \"be brief, \\ no # comments\"""#))
        #expect(CalmSettings(text: text).extraFlags(of: .claudeCode) == flags)
    }

    @Test func `a comment after a value with an escaped quote is still a comment`() {
        let settings = CalmSettings(text: "[agents.pi]\nflags = \"--name \\\"#1\\\"\" # mine\n")
        #expect(settings.extraFlags(of: .pi) == ##"--name "#1""##)
    }

    @Test func `the keys for ⌘N are in the registry`() throws {
        let agent = try #require(CalmSettings.key(named: "agents.new-session"))
        #expect(agent.kind == .choice(["claude-code", "codex", "opencode", "pi"]))
        #expect(agent.defaultValue == "claude-code")
        let flags = try #require(CalmSettings.key(named: "agents.codex.flags"))
        let command = try #require(CalmSettings.key(named: "agents.codex.command"))
        #expect(flags.kind == .text)
        #expect(command.kind == .text)
        #expect(CalmSettings.change("--search", for: flags) == .success(.write("--search")))
        #expect(CalmSettings.change(" ", for: command) == .success(.remove))
        #expect(CalmSettings.change("Codex", for: agent) == .success(.write("codex")))
        #expect(CalmSettings.change("claude-code", for: agent) == .success(.remove))
    }
}
