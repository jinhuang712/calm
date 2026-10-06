import CalmModel
import Foundation

// What ⌘N types to start each agent (FEATURES.md → New agent sessions): its command, the flags
// written in config.toml, then the options chosen in Settings → Agents, each one of the agent's
// own flags. Read from each agent's `--help` on 2026-10-06: Claude Code 2.1.291, Codex 0.159.0,
// OpenCode 2.0.20, pi 0.99.1 (which asks before nothing, so it has no option to skip asking).

public extension ClaudeCodeAdapter {
    var launchCommand: String {
        "claude"
    }

    var launchOptions: [LaunchOption] {
        [
            LaunchOption(
                id: "skip-permissions", label: "Skip permissions", flag: "--dangerously-skip-permissions",
                about: "Claude Code on ⌘N runs every tool without asking (--dangerously-skip-permissions)",
            ),
            // `-w, --worktree [name]`: last, so nothing after it is taken for the name.
            LaunchOption(
                id: "worktree", label: "New worktree", flag: "-w", onlyInGitRepository: true,
                about: "Claude Code on ⌘N starts in a new git worktree, in a git repository (-w)",
            ),
        ]
    }
}

public extension CodexAdapter {
    var launchCommand: String {
        "codex"
    }

    var launchOptions: [LaunchOption] {
        [
            // Its help calls it "EXTREMELY DANGEROUS": it also leaves Codex's sandbox, so the chip says so.
            LaunchOption(
                id: "skip-permissions", label: "Skip approvals and sandbox", flag: "--dangerously-bypass-approvals-and-sandbox",
                about: "Codex on ⌘N runs commands without asking and outside its sandbox (--dangerously-bypass-approvals-and-sandbox)",
            ),
            LaunchOption(
                id: "worktree", label: "New worktree", flag: "--worktree", onlyInGitRepository: true,
                about: "Codex on ⌘N starts in a new git worktree it manages, in a git repository (--worktree)",
            ),
        ]
    }
}

public extension OpenCodeAdapter {
    var launchCommand: String {
        "opencode"
    }

    var launchOptions: [LaunchOption] {
        [
            LaunchOption(
                id: "skip-permissions", label: "Auto-approve", flag: "--auto",
                about: "OpenCode on ⌘N approves every permission that isn't explicitly denied (--auto)",
            ),
        ]
    }
}

public extension PiAdapter {
    var launchCommand: String {
        "pi"
    }
}

public extension AgentAdapter {
    /// What ⌘N types: the agent's command, the flags config.toml adds, then the options that are
    /// on. An option that needs a git repository is left out anywhere else (the home folder of
    /// the welcome page, a scratch folder), where the agent would refuse to start.
    func launchCommand(settings: CalmSettings, inGitRepository: Bool) -> String {
        var parts = [launchCommand]
        if let extra = settings.extraFlags(of: kind) {
            parts.append(extra)
        }
        parts += launchOptions
            .filter { settings.isOn($0.id, of: kind) && (inGitRepository || !$0.onlyInGitRepository) }
            .map(\.flag)
        return parts.joined(separator: " ")
    }
}

public extension Agents {
    /// The agents installed under `home` (their config folder is there), in Calm's order.
    static func installed(home: URL) -> [AgentKind] {
        adapters.compactMap { adapter in
            guard let folder = adapter.configFolder, FileManager.default.fileExists(atPath: home.appending(path: folder).path)
            else { return nil }
            return adapter.kind
        }
    }

    /// The agent ⌘N starts: the one config.toml names (even when it looks uninstalled: the user
    /// chose it, and its folder may just not exist yet), else the first installed, which is
    /// Claude Code when it is. Nil when there is none: ⌘N then opens a plain shell, as ⌘T does.
    static func newSessionAgent(settings: CalmSettings, installed: [AgentKind]) -> AgentKind? {
        settings.newSessionAgent ?? installed.first
    }

    /// Every key `calm config` knows: Calm's own, and each agent's options (`agents.<agent>-<id>`),
    /// which the adapters declare.
    static var settingsKeys: [CalmSettings.Key] {
        CalmSettings.keys + adapters.flatMap { adapter in
            adapter.launchOptions.map { option in
                CalmSettings.Key(
                    name: CalmSettings.launchOptionKey(option.id, of: adapter.kind),
                    kind: .bool, defaultValue: "false", about: option.about,
                )
            }
        }
    }

    static func settingsKey(named name: String) -> CalmSettings.Key? {
        settingsKeys.first { $0.name == name.lowercased() }
    }
}
