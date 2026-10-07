import Foundation

/// One way an agent can be started (FEATURES.md → New agent sessions): a flag of the agent's own,
/// shown as a chip under its name in Settings → Agents. Each adapter declares its own options;
/// the core only reads whether one is on.
public struct LaunchOption: Sendable, Equatable, Identifiable {
    /// The key's last part in config.toml: `agents.<agent>-<id>`.
    public let id: String
    /// The chip's words.
    public let label: String
    /// What it adds to the command, as the agent's `--help` spells it.
    public let flag: String
    /// Only added in a git repository (a new worktree needs one): ⌘N on the welcome page starts in
    /// the home folder, and ⌘⇧N in a scratch folder, and the agent would refuse there.
    public let onlyInGitRepository: Bool
    /// One line for `calm config`.
    public let about: String

    public init(id: String, label: String, flag: String, onlyInGitRepository: Bool = false, about: String) {
        self.id = id
        self.label = label
        self.flag = flag
        self.onlyInGitRepository = onlyInGitRepository
        self.about = about
    }
}

public extension CalmSettings {
    /// The agent ⌘N and ⌘⇧N start, when config.toml names one (`agents.new-session`). Unset, Calm
    /// picks among the agents installed (`Agents.newSessionAgent`).
    var newSessionAgent: AgentKind? {
        values["agents.new-session"].flatMap { AgentKind(configName: $0) }
    }

    /// `agents.<agent>.<option>` (a `[agents.<agent>]` section in config.toml): whether that agent
    /// starts with that option.
    static func launchOptionKey(_ option: String, of kind: AgentKind) -> String {
        "agents.\(kind.configName).\(option)"
    }

    func isOn(_ option: String, of kind: AgentKind) -> Bool {
        bool(Self.launchOptionKey(option, of: kind), default: false)
    }

    /// `agents.<agent>.flags`: anything else to start the agent with, typed as written after its
    /// name. There are chips only for the options most people want; this is for the rest
    /// (`--model opus`).
    static func extraFlagsKey(of kind: AgentKind) -> String {
        "agents.\(kind.configName).flags"
    }

    func extraFlags(of kind: AgentKind) -> String? {
        text(Self.extraFlagsKey(of: kind))
    }

    /// `agents.<agent>.command`: the whole command ⌘N types for that agent, as written, in place of
    /// its name, flags and chips. Set with `calm config` only (Settings shows it, but has no field
    /// for it): a way out for whoever wants the line exactly so.
    static func commandKey(of kind: AgentKind) -> String {
        "agents.\(kind.configName).command"
    }

    func command(of kind: AgentKind) -> String? {
        text(Self.commandKey(of: kind))
    }

    private func text(_ key: String) -> String? {
        values[key].flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
    }
}
