import Foundation

/// Ghostty's shell integration (working directory, prompt marks, titles) for shells that
/// run inside zmx.
///
/// libghostty injects the integration only when the command it launches is a shell; a
/// persistent session's command is `zmx attach`, so Calm sets the same variables itself and
/// zmx hands them to the login shell it starts. This mirrors Ghostty's own setup for zsh,
/// fish and elvish (src/termio/shell_integration.zig). Bash needs its command line rewritten
/// and nushell its arguments, so those shells rely on the process-based working directory.
///
/// zsh starts through Calm's own startup file (`zshStartup`) first, which teaches it ⌘ Return
/// and then hands over to Ghostty's.
enum ShellIntegration {
    /// `mode` is the `shell-integration` config value: `detect`, `none` or a shell name.
    /// `calmZsh` is the folder holding Calm's zsh startup file, when it was written.
    static func environment(
        shell: String?,
        mode: String?,
        resourcesDirectory: String?,
        inherited: [String: String],
        calmZsh: String? = nil,
    ) -> [String: String] {
        guard let resourcesDirectory, mode != "none" else { return [:] }
        let name = mode.flatMap { $0 == "detect" ? nil : $0 } ?? shell.map { ($0 as NSString).lastPathComponent }
        let integration = (resourcesDirectory as NSString).appendingPathComponent("shell-integration")

        switch name {
        case "zsh":
            let ghostty = (integration as NSString).appendingPathComponent("zsh")
            var environment = if let calmZsh {
                ["ZDOTDIR": calmZsh, "CALM_GHOSTTY_ZSH_DIR": ghostty]
            } else {
                ["ZDOTDIR": ghostty]
            }
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

    /// Where Calm's zsh startup file goes, beside its Ghostty defaults (Application Support, or the
    /// self-test's own folder).
    static var zshDirectory: URL {
        CalmDefaults.directory.appending(path: "zsh", directoryHint: .isDirectory)
    }

    /// Writes Calm's zsh startup file, at each launch before any shell starts. Returns its folder,
    /// or nil when it couldn't be written (zsh then starts through Ghostty's alone).
    @discardableResult
    static func prepare() -> String? {
        let file = zshDirectory.appending(path: ".zshenv")
        do {
            try FileManager.default.createDirectory(at: zshDirectory, withIntermediateDirectories: true)
            if (try? String(contentsOf: file, encoding: .utf8)) != zshStartup {
                try zshStartup.write(to: file, atomically: true, encoding: .utf8)
            }
            return zshDirectory.path
        } catch {
            FileHandle.standardError.write(Data("calm: could not write the zsh startup: \(error)\n".utf8))
            return nil
        }
    }

    /// The folder to give a new shell, if Calm's zsh startup is there.
    static var preparedZshDirectory: String? {
        let file = zshDirectory.appending(path: ".zshenv")
        return FileManager.default.fileExists(atPath: file.path) ? zshDirectory.path : nil
    }

    /// zsh reads this `.zshenv` first, from `ZDOTDIR`. It hands over to Ghostty's own `.zshenv`
    /// (`CALM_GHOSTTY_ZSH_DIR`), which puts the user's `ZDOTDIR` back, runs their `.zshenv` and loads
    /// the integration, so the user's startup files run as they always do.
    ///
    /// ⌘ Return: with Send with ⌘ Return on, Calm lets ⌘↵ through to programs (`CalmDefaults`), and
    /// a shell gets it as `ESC[27;9;13~` (or `ESC[13;9u` under the kitty keyboard protocol), which
    /// zsh doesn't know: it beeped and typed `;9;13~`. It's bound to whatever Return does in each
    /// keymap, at the first prompt, so after the user's `.zshrc` has set its keymaps up. Quoted
    /// builtins, as Ghostty's file does, because it can run with the user's aliases on.
    static let zshStartup = """
    # Written by Calm Terminal at each launch: zsh starts here, then goes on to Ghostty's shell
    # integration, which restores your ZDOTDIR and runs your own startup files as usual.

    if [[ -o 'interactive' ]]; then
        # ⌘ Return arrives as ESC[27;9;13~ (ESC[13;9u under the kitty keyboard protocol) and
        # does what Return does. Bound at the first prompt, once your .zshrc set its keymaps up.
        _calm_command_return() {
            'builtin' 'local' keymap widget
            for keymap in emacs viins vicmd; do
                widget=${${(z)"$('builtin' 'bindkey' -M "$keymap" '^M' 2>/dev/null)"}[2]}
                [[ -n "$widget" && "$widget" != 'undefined-key' ]] || widget='accept-line'
                'builtin' 'bindkey' -M "$keymap" '^[[27;9;13~' "$widget"
                'builtin' 'bindkey' -M "$keymap" '^[[13;9u' "$widget"
            done
            precmd_functions=(${precmd_functions:#_calm_command_return})
            'builtin' 'unfunction' '_calm_command_return'
        }
        'builtin' 'typeset' -ag precmd_functions
        precmd_functions+=(_calm_command_return)
    fi

    'builtin' 'typeset' _calm_ghostty="$CALM_GHOSTTY_ZSH_DIR"
    'builtin' 'unset' 'CALM_GHOSTTY_ZSH_DIR'
    if [[ -n "$_calm_ghostty" && -r "$_calm_ghostty/.zshenv" ]]; then
        # Ghostty's file finds its integration beside itself.
        'builtin' 'source' '--' "$_calm_ghostty/.zshenv"
    else
        # Nothing to hand over to: put back your ZDOTDIR and run your .zshenv, as Ghostty's would.
        if [[ -n "${GHOSTTY_ZSH_ZDOTDIR+X}" ]]; then
            'builtin' 'export' ZDOTDIR="$GHOSTTY_ZSH_ZDOTDIR"
            'builtin' 'unset' 'GHOSTTY_ZSH_ZDOTDIR'
        else
            'builtin' 'unset' 'ZDOTDIR'
        fi
        [[ ! -r "${ZDOTDIR-$HOME}/.zshenv" ]] || 'builtin' 'source' '--' "${ZDOTDIR-$HOME}/.zshenv"
    fi
    'builtin' 'unset' '_calm_ghostty'

    """
}
