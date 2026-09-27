import Foundation

/// Ghostty's shell integration (working directory, prompt marks, titles) for shells that
/// run inside zmx.
///
/// libghostty injects the integration only when the command it launches is a shell; a
/// persistent session's command is `zmx attach`, so Calm sets the same variables itself and
/// zmx hands them to the login shell it starts. This mirrors Ghostty's own setup for zsh,
/// fish and elvish (src/termio/shell_integration.zig). Bash needs its command line rewritten
/// and nushell its arguments, so those shells rely on the process-based working directory.
enum ShellIntegration {
    /// `mode` is the `shell-integration` config value: `detect`, `none` or a shell name.
    static func environment(
        shell: String?,
        mode: String?,
        resourcesDirectory: String?,
        inherited: [String: String],
    ) -> [String: String] {
        guard let resourcesDirectory, mode != "none" else { return [:] }
        let name = mode.flatMap { $0 == "detect" ? nil : $0 } ?? shell.map { ($0 as NSString).lastPathComponent }
        let integration = (resourcesDirectory as NSString).appendingPathComponent("shell-integration")

        switch name {
        case "zsh":
            var environment = ["ZDOTDIR": (integration as NSString).appendingPathComponent("zsh")]
            if let original = inherited["ZDOTDIR"] {
                environment["GHOSTTY_ZSH_ZDOTDIR"] = original
            }
            return environment
        case "fish", "elvish":
            // The same default XDG_DATA_DIRS the XDG spec gives when it is unset.
            let existing = inherited["XDG_DATA_DIRS"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/local/share:/usr/share"
            return [
                "XDG_DATA_DIRS": "\(integration):\(existing)",
                "GHOSTTY_SHELL_INTEGRATION_XDG_DIR": integration,
            ]
        default:
            return [:]
        }
    }
}
