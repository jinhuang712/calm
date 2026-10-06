import Foundation

// Restarting a running agent on its conversation (FEATURES.md → F12, DESIGNS.md → Agents →
// Restart): quit it with a signal that lets it tidy the terminal, then start it again with the
// options it was started with, so a restart after an update changes nothing but the version.

/// A command line's options, read the way the agent's own parser reads them, so a restart can
/// keep them and leave out what would start something else: a prompt (it would be sent again), and
/// options that pick or create the conversation, which the restart names itself.
struct CommandLineOptions {
    /// Options that take a value (`--model opus`, or `--model=opus`).
    var valued: Set<String> = []
    /// Options whose value is optional: the next argument is theirs unless it is an option itself.
    var optionalValue: Set<String> = []
    /// Options that take every argument up to the next option (`--add-dir a b`).
    var variadic: Set<String> = []
    /// Options left out, with their values.
    var dropped: Set<String> = []

    /// The options in `arguments` (argv without the program) that are kept, each with its value.
    /// Positional arguments go, and so does everything after `--`.
    func kept(_ arguments: [String]) -> [String] {
        var kept: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            index += 1
            if token == "--" {
                break
            }
            // A positional argument: the prompt the agent was started with.
            guard token.hasPrefix("-"), token.count > 1 else { continue }
            let equals = token.hasPrefix("--") ? token.firstIndex(of: "=") : nil
            let name = equals.map { String(token[..<$0]) } ?? token
            var option = [token]
            if equals == nil {
                if variadic.contains(name) {
                    while index < arguments.count, !arguments[index].hasPrefix("-") {
                        option.append(arguments[index])
                        index += 1
                    }
                } else if valued.contains(name), index < arguments.count {
                    option.append(arguments[index])
                    index += 1
                } else if optionalValue.contains(name), index < arguments.count, !arguments[index].hasPrefix("-") {
                    option.append(arguments[index])
                    index += 1
                }
            }
            if !dropped.contains(name) {
                kept += option
            }
        }
        return kept
    }
}

/// A word for a command line: as it is when the shell would read it back unchanged, quoted
/// otherwise, so the typed command stays readable (`--dangerously-skip-permissions`, not quoted).
func shellWord(_ value: String) -> String {
    let plain = !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
        CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || "-_./=:,@%+".unicodeScalars.contains(scalar)
    }
    return plain ? value : shellQuoted(value)
}

public extension ClaudeCodeAdapter {
    /// Claude Code (2.1.291, checked in a pty with a made-up conversation) quits on SIGTERM in about
    /// 0.3 s, turns off every terminal mode it turned on (alternate screen, mouse, bracketed
    /// paste, kitty keys, focus events) and prints how to resume. An unsent prompt is lost.
    var quitSignal: Int32? {
        SIGTERM
    }

    /// `claude <its options> --resume <id>`. Kept: everything that sets up the session
    /// (`--dangerously-skip-permissions`, `--model`, `--add-dir`, …). Left out: the prompt, and
    /// what picks or makes the conversation or the place it runs in (`-c`, `-r`, `--session-id`,
    /// `--fork-session`, `-w`, which would make another worktree, `--tmux`, `--teleport`, …).
    func restartCommand(arguments: [String], agentSessionID: String?, transcriptPath: String) -> String? {
        let id = agentSessionID ?? URL(filePath: transcriptPath).deletingPathExtension().lastPathComponent
        guard !id.isEmpty else { return nil }
        let options = Self.commandLine.kept(Array(arguments.dropFirst()))
        return (["claude"] + options.map(shellWord) + ["--resume", shellQuoted(id)]).joined(separator: " ")
    }

    /// Claude Code's options as `claude --help` lists them (2.1.291), plus the hidden ones its docs
    /// name. One missing here reads as a switch with no value: its value would then look like
    /// the prompt and be left out, and Claude Code would say the option needs one.
    internal static let commandLine = CommandLineOptions(
        valued: [
            "--agent", "--agents", "--append-system-prompt", "--append-system-prompt-file", "--autocompact", "--debug-file",
            "--effort", "--environment", "--fallback-model", "--input-format", "--json-schema", "--max-budget-usd",
            "--max-turns", "--model", "-n", "--name", "--output-format", "--permission-mode", "--permission-prompts",
            "--permission-prompt-tool", "--plugin-dir", "--plugin-url", "--remote-control-session-name-prefix",
            "--session-id", "--setting-sources", "--settings", "--system-prompt", "--system-prompt-file",
            "--system-prompt-snapshot",
        ],
        optionalValue: [
            "-d", "--debug", "--from-pr", "--prompt-suggestions", "--remote-control", "-r", "--resume", "--teleport",
            "--cloud", "-w", "--worktree",
        ],
        variadic: [
            "--add-dir", "--allowedTools", "--allowed-tools", "--betas", "--disallowedTools", "--disallowed-tools", "--file",
            "--mcp-config", "--tools",
        ],
        dropped: [
            "-c", "--continue", "-r", "--resume", "--session-id", "--fork-session", "-p", "--print", "--from-pr",
            "--teleport", "--cloud", "--desktop", "--bg", "--background", "-w", "--worktree", "--tmux", "--file",
            "-h", "--help", "-v", "--version",
        ],
    )
}
