import Foundation

// Restarting a running agent on its conversation (FEATURES.md → F12, DESIGNS.md → Agents →
// Restart): ask it to quit the way that lets it tidy the terminal, then start it again with the
// options it was started with, so a restart after an update changes nothing but the version. The
// same options are kept for a resume or a fork once the agent has exited (`AgentRun.options`).

/// How Calm asks an agent to quit before starting it again. Each was checked against the real
/// agent in a pty (2026-10-07): it exits and turns off every terminal mode it turned on.
public enum AgentQuit: Sendable, Equatable {
    /// A signal the agent handles by tidying up and exiting.
    case signal(Int32)
    /// ⌃C as the keyboard sends it, and again every half second while the agent hasn't quit, up to
    /// `times`: for an agent that tidies up on its own quit key but dies untidily on any signal.
    case controlC(times: Int)
}

/// A command line's options, read the way the agent's own parser reads them, so a restart or a
/// resume can keep them and leave out what would start something else: a prompt (it would be sent
/// again), and options that pick or create the conversation, which the resume names itself.
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
        split(arguments).options
    }

    /// The kept options, and the positional arguments before any `--` (a prompt for most agents;
    /// OpenCode's folder).
    func split(_ arguments: [String]) -> (options: [String], positionals: [String]) {
        var kept: [String] = []
        var positionals: [String] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            index += 1
            if token == "--" {
                break
            }
            guard token.hasPrefix("-"), token.count > 1 else {
                positionals.append(token)
                continue
            }
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
        return (kept, positionals)
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
    var quit: AgentQuit? {
        .signal(SIGTERM)
    }

    /// Kept: everything that sets up the session (`--dangerously-skip-permissions`, `--model`,
    /// `--add-dir`, …). Left out: the prompt, and what picks or makes the conversation or the place
    /// it runs in (`-c`, `-r`, `--session-id`, `--fork-session`, `-w`, which would make another
    /// worktree, `--tmux`, `--teleport`, …).
    func resumeOptions(commandLine: [String]) -> [String]? {
        Self.commandLine.kept(Array(commandLine.dropFirst()))
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

public extension CodexAdapter {
    /// Codex (0.159.0, checked in a pty at its chat screen) dies on SIGTERM, SIGINT and SIGHUP alike
    /// and leaves the terminal in its full-screen view with the mouse, bracketed paste, kitty keys
    /// and focus events still on. Its own ⌃C quits cleanly: once at an empty prompt, twice with a
    /// draft (the first clears it), exit code 0, every mode off.
    var quit: AgentQuit? {
        .controlC(times: 4)
    }

    /// Left out: the prompt and the subcommand it may have been started with (`resume`, `fork` and
    /// their id are positional), the images attached to that prompt, the picker's `--last`, `--all`
    /// and `--include-non-interactive`, and `--worktree`, which would make another worktree.
    func resumeOptions(commandLine: [String]) -> [String]? {
        Self.commandLine.kept(Array(commandLine.dropFirst()))
    }

    /// Codex's options as `codex resume --help` lists them (0.159.0), the same as `codex --help`'s
    /// plus the picker's. `--yolo` (Calm's skip chip types it) takes no value, so it needs no entry.
    internal static let commandLine = CommandLineOptions(
        valued: [
            "-c", "--config", "--enable", "--disable", "--remote", "--remote-auth-token-env", "-m", "--model",
            "--local-provider", "-p", "--profile", "-s", "--sandbox", "-C", "--cd", "--add-dir", "-a", "--ask-for-approval",
        ],
        variadic: ["-i", "--image"],
        dropped: ["-i", "--image", "--last", "--all", "--include-non-interactive", "--worktree", "-h", "--help", "-V", "--version"],
    )
}

public extension OpenCodeAdapter {
    /// OpenCode (2.0.20, checked in a pty at its chat screen) quits on SIGTERM in under 0.1 s and
    /// turns off what it turned on (the alternate screen, the mouse, bracketed paste and
    /// modifyOtherKeys).
    var quit: AgentQuit? {
        .signal(SIGTERM)
    }

    /// OpenCode's one positional argument is the folder it starts in (not a prompt), so it stays,
    /// after the options. Left out: `-c`, `-s` and `--prompt`. Started through one of its
    /// subcommands (`mini`, `run`, …) it isn't the interface a restart would bring back, so there
    /// is no restart.
    func resumeOptions(commandLine: [String]) -> [String]? {
        let (options, positionals) = Self.commandLine.split(Array(commandLine.dropFirst()))
        if let first = positionals.first, Self.subcommands.contains(first) {
            return nil
        }
        return options + positionals.prefix(1)
    }

    /// OpenCode's flags as `opencode --help` lists them (2.0.20).
    internal static let commandLine = CommandLineOptions(
        valued: ["--server", "-s", "--session", "--prompt", "--log-level", "--completions"],
        dropped: ["-c", "--continue", "-s", "--session", "--prompt", "-h", "--help", "-v", "--version", "--wizard", "--completions"],
    )

    internal static let subcommands: Set<String> = [
        "upgrade", "update", "uninstall", "acp", "api", "debug", "auth", "mcp", "plugin", "models", "stats", "mini", "run",
        "session", "service", "reload", "pair", "serve",
    ]
}

public extension PiAdapter {
    /// pi (1.0.4, checked in a pty at its chat screen) quits on SIGTERM in under 0.1 s, exit code 0,
    /// every mode off. SIGINT kills it untidily.
    var quit: AgentQuit? {
        .signal(SIGTERM)
    }

    /// pi sets its process title, which overwrites its command line: what's left reads "pi" and
    /// the environment (checked 2026-10-07), so in practice there are no options to keep and the
    /// restart is `pi --session <file>`. Whether the session brings back the model and thinking
    /// level it last used hasn't been checked. Left out, were they readable: `-c`, `-r`, the
    /// session options, `-p`, `--export`, `--list-models`, and the messages and files it was
    /// started with.
    func resumeOptions(commandLine: [String]) -> [String]? {
        Self.commandLine.kept(Array(commandLine.dropFirst()))
    }

    /// pi's options as `pi --help` lists them (1.0.4).
    internal static let commandLine = CommandLineOptions(
        valued: [
            "--provider", "--model", "--api-key", "--system-prompt", "--append-system-prompt", "--mode", "--session", "--session-id",
            "--fork", "--session-dir", "-n", "--name", "--models", "-t", "--tools", "-xt", "--exclude-tools", "--thinking", "-e",
            "--extension", "--skill", "--prompt-template", "--theme", "--use-theme", "--export", "--tui-mode",
        ],
        optionalValue: ["--list-models"],
        dropped: [
            "-c", "--continue", "-r", "--resume", "--session", "--session-id", "--fork", "-p", "--print", "--export",
            "--list-models", "-h", "--help", "-v", "--version",
        ],
    )
}
