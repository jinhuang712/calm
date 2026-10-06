import CalmModel
import Testing

/// ⌘N's settings in config.toml (FEATURES.md → New agent sessions): which agent, its options, the
/// flags typed as written, and quotes in those flags surviving a write and a read.
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

    @Test func `an option is off until config.toml turns it on`() {
        let settings = CalmSettings(text: "[agents]\nclaude-code-worktree = true\ncodex-worktree = false\n")
        #expect(settings.isOn("worktree", of: .claudeCode))
        #expect(!settings.isOn("worktree", of: .codex))
        #expect(!settings.isOn("skip-permissions", of: .claudeCode))
        #expect(CalmSettings.launchOptionKey("skip-permissions", of: .openCode) == "agents.opencode-skip-permissions")
    }

    @Test func `extra flags are read as written, and blank ones are none`() {
        let settings = CalmSettings(text: "[agents]\nclaude-code-flags = \"--model opus\"\npi-flags = \"  \"\n")
        #expect(settings.extraFlags(of: .claudeCode) == "--model opus")
        #expect(settings.extraFlags(of: .pi) == nil)
        #expect(settings.extraFlags(of: .codex) == nil)
    }

    @Test func `flags with quotes and backslashes survive a write and a read`() {
        let flags = #"--append-system-prompt "be brief, \ no # comments""#
        let text = CalmSettings.setting("agents.claude-code-flags", to: flags, in: "")
        #expect(text.contains(#"claude-code-flags = "--append-system-prompt \"be brief, \\ no # comments\"""#))
        #expect(CalmSettings(text: text).extraFlags(of: .claudeCode) == flags)
    }

    @Test func `a comment after a value with an escaped quote is still a comment`() {
        let settings = CalmSettings(text: "[agents]\npi-flags = \"--name \\\"#1\\\"\" # mine\n")
        #expect(settings.extraFlags(of: .pi) == ##"--name "#1""##)
    }

    @Test func `the keys for ⌘N are in the registry`() throws {
        let agent = try #require(CalmSettings.key(named: "agents.new-session"))
        #expect(agent.kind == .choice(["claude-code", "codex", "opencode", "pi"]))
        #expect(agent.defaultValue == "claude-code")
        let flags = try #require(CalmSettings.key(named: "agents.codex-flags"))
        #expect(flags.kind == .text)
        #expect(CalmSettings.change("--search", for: flags) == .success(.write("--search")))
        #expect(CalmSettings.change(" ", for: flags) == .success(.remove))
        #expect(CalmSettings.change("Codex", for: agent) == .success(.write("codex")))
        #expect(CalmSettings.change("claude-code", for: agent) == .success(.remove))
    }
}
