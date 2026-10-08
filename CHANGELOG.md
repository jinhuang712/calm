# Changelog

What changed in each release of Calm Terminal. Before 1.0 anything may change between versions.

## 0.1.0 — 2026-10-08

The first release, a public preview, for macOS 26 on Apple silicon. Its author has used it as their only terminal since 2026-09-29, and nobody else has tried it, so expect rough edges (README → Known limits). Exact behavior of everything below is in [FEATURES.md](FEATURES.md).

**Install** with one line: `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash` (it downloads `Calm-0.1.0.dmg`, puts Calm in Applications and takes macOS's download mark off), or with Homebrew: `brew install --cask jinhuang712/tap/calm`. To install `Calm-0.1.0.dmg` below by hand, drag Calm onto Applications, then run `/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app` once before opening it, since Calm isn't signed by Apple yet (also after `brew install`). macOS asks again for Desktop, Documents and Downloads after each update. All the ways, and building from source: [README → Install](README.md#install).

### The terminal
- Ghostty's engine (libghostty): it reads your Ghostty config for fonts, colors and keybindings.
- Smooth scrolling (including a program's scroll regions, like Claude Code's streaming view), a cursor glide, and a one-size text setting for every session.
- No tab bar. ⌘T opens a shell and ⌘N your agent, each as a session in the sidebar. Splits by key (⌘D, ⌘⌥ + an arrow), with the pane you're in bright and the others receding. A session can be dragged from the sidebar onto a pane; each pane in a split has a small split icon for taking it out again, without ending its session.
- ⌘F finds in a session: every match marked as you type, the newest first, and a map of all of them along the pane's edge; `.*` (⌥⌘R) takes a regular expression. In a full-screen program such as Claude Code, **Screen | Session** searches everything the session showed, not only the screen.
- Input methods and dictation type into a pane as the keyboard does, and ⌘V pastes a copied image as a file an agent can attach.

### Sessions and projects
- Sessions file themselves under the project or folder they work in; projects you make stay put, and scratch sessions (⌘⇧N) are for throwaway work.
- Quitting Calm detaches your shells and relaunching brings everything back: sessions, splits, scrollback and running agents. Calm → Restart Calm does it in one step. After the Mac restarts, a session that had an agent running resumes its conversation the first time you open it.
- One menu for a session, on its card's right-click and the ⋯ in its title strip: rename, resume, restart, fork a conversation into a new split or tab, and copy its id, resume command or folder. ⌘⇧T reopens a closed session.

### Agents
- Claude Code, Codex, OpenCode and pi are detected from their processes. Connect their hooks from Calm → Agents… for exact state (each asks first and can be undone).
- ⌘N starts the agent you choose in Settings → Agents, with the options you picked there, such as skipping permissions or a new worktree. An empty worktree it made goes when its session closes.
- Each session card shows the agent's mark, its state (working, needs you, done, failed), what it last said (once you've read it and it sits idle, Claude Code's own recap), its todo progress where the agent keeps a list, and a bar while Claude Code compacts its conversation. Only *needs you* notifies, at a natural pause.
- After you update an agent, the title strip says so, and Restart starts it again on the same conversation, once the turn it's in has ended.
- Send with ⌘ Return (off by default): ⌘↵ sends an agent's prompt and Return starts a new line, set in each agent's own key settings.
- With the sidebar hidden, an arrival card tells you what happened in a session since you left it.

### Finding and reading
- ⌘K searches every agent's past conversations, grouped like the sidebar.
- ⌘P lists what Calm does that has no key everyone knows (one-shot commands).
- ⌘-click opens a URL, or a file at its line, and holding ⌘ shows a tag saying where it leads; over Claude Code's `[Image #n]`, the image itself. ⌥-click copies a table cell.
- A files column (⌘\\) shows the project's tree and changes, and a viewer opens Markdown, HTML, PDFs, images and code without leaving Calm; a changed file shows its diff, unified or side by side.

### Look
- Five soft themes in light and dark pairs that follow the system, carried through the whole window; Ghostty's own colors are a last choice. Motion can be reduced or turned off.
- A small settings page (⌘,): Appearance, Agents, General and Shortcuts.

### Command line
- `calm open`, `list`, `search`, `show`, `fork`, `config`, `doctor` and `trace` for you and your agents; `status`, `hook` and `notify` for agents' hooks, safe to run anywhere: outside Calm they do nothing. Every command is in [CLI.md](CLI.md).
