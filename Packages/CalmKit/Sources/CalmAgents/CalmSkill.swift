import Foundation

/// What every agent learns about the `calm` command (DESIGNS.md → Teaching agents about `calm`):
/// one Agent Skills file, the same for all four agents, which each adapter delivers its own way.
/// Claude Code's is in Calm's plugin, pi's comes from Calm's extension, OpenCode's and Codex's are
/// files that Connect adds. A Swift string, not a resource file, so the CLI can name the files
/// without `Bundle.module` (`ClaudeCodeAdapter.pluginFileNames`).
public enum CalmSkill {
    /// The skill's name and its folder's, as the Agent Skills format wants them to match.
    public static let name = "calm"

    /// Where Calm keeps a copy for agents that load a skill from a path of Calm's (pi), rewritten
    /// at each launch like Claude Code's plugin.
    public static func directory(in support: URL) -> URL {
        support.appending(path: "agents/skills/\(name)", directoryHint: .isDirectory)
    }

    /// Checked 2026-10-13: each agent forks cleanly while its own `calm fork` call still runs.
    /// Claude Code, Codex and pi close that call as interrupted, aborted or failed. OpenCode copies
    /// only finished messages, so its fork doesn't see the call.
    ///
    /// The description sits in every session's context, so it stays short. No `allowed-tools`:
    /// in Claude Code it makes loading the skill itself ask (2.1.19's changelog, seen on 2.1.296),
    /// and its grant ends with the turn; Codex ignores it, and pi never asks. No permission rule
    /// matches a command that starts with a variable (Claude Code 2.1.296, Codex 0.162, OpenCode
    /// 2.0.12), so the skill runs `calm` and keeps `"$CALM_CLI"` for when `calm` isn't on `PATH`.
    public static let text = """
    ---
    name: \(name)
    description: The `calm` command of Calm Terminal. Use it when the user asks about past agent conversations (find one, \
    see what it did or how to resume it), asks to fork this conversation into a new session, or asks about Calm's \
    sessions or settings.
    ---

    <!-- \(AgentSetup.marker), which keeps this file current. -->

    # calm

    Calm Terminal's `calm` command reaches Calm. Inside Calm, every shell has `CALM_SESSION_ID`. Outside Calm, \
    `calm search` and `calm show` still work, and the commands about this session fail.

    Run `calm …` as a command of its own. Only when the shell answers `command not found`, run `"$CALM_CLI" …` \
    instead: Calm sets that variable in its shells. No permission rule matches that form, so it can ask each time. Do \
    not join the two in one command.

    ## Past conversations

    - `calm search <words>` finds past conversations of every agent (Claude Code, Codex, OpenCode, pi), best first. \
    Each line ends with the conversation's id.
    - `calm show <id>` prints one conversation on one screen: what it was for, recent prompts, recap, last reply, and \
    the commands that resume or fork it. The start of an id (6 characters or more) works, and so does a session id \
    from `calm list` or `calm fork`. `--prompts` lists every prompt. `--all` prints every prompt and reply, without \
    tool calls.

    Look a conversation up before you guess what it did.

    ## Fork this conversation

    `calm fork --background "<first message>"` starts a new Calm session with a copy of this conversation, and sends \
    it the message.

    - Always pass `--background`. The user stays where they are, and the fork appears in Calm's sidebar. Without it, \
    Calm moves the user to the fork.
    - It prints the new session's id. No answer comes back to you. Tell the user that the fork runs in the sidebar.
    - When the user asks how the fork went, `calm show <session id>` gives its state and last reply. Do not wait or \
    poll for it.
    - When Calm says the agent can't start a fork with a message, run `calm fork --background` alone, and tell the \
    user what to ask the fork.
    - `--in <folder>` runs the fork in another folder. For Claude Code, the folder must be a git worktree of this \
    repository.
    - Fork only when the user asks.
    - A session that `calm fork` started cannot fork.
    - In the fork, the `calm fork` call that made it shows as unfinished, or not at all. That is expected: do what the \
    first message asks.

    ## Sessions and settings

    - `calm list` prints the open sessions, one per line: session id, state, project, title, agent, folder.
    - `calm config` prints every setting with its value and what it takes. `calm config get <key>` prints one value.
    - `calm config set <key> <value>` and `calm config unset <key>` change a setting. Change one only when the user \
    asks.
    - `calm doctor` checks that Calm and its hooks work. Run it when Calm shows this session in the wrong state.

    ## Do not

    - Do not run `calm status` or `calm notify`. Calm already knows this session's state, and it notifies the user \
    itself.

    """
}
