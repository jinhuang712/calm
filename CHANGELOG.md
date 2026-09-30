# Changelog

What changed in each release of Calm Terminal. Before 1.0 anything may change between versions.

## 0.1.0 — public preview

The first release. Built from source only, for macOS 26 on Apple silicon; there is no download yet.
Its author has used it as their only terminal since 2026-09-29, and nobody else has tried it, so
expect rough edges (README → Known limits). Exact behavior of everything below is in
[FEATURES.md](FEATURES.md).

### The terminal
- Ghostty's engine (libghostty): it reads your Ghostty config for fonts, colors and keybindings.
- Smooth scrolling (including a program's scroll regions, like Claude Code's streaming view), a
  cursor glide, and a one-size text setting for every session.
- No tab bar. Splits by key (⌘D, ⌘⌥ + an arrow), with the pane you're in bright and the others
  receding. A session can be dragged from the sidebar onto a pane; each pane in a split has a small
  split icon for taking it out again, without ending its session.

### Sessions and projects
- Sessions file themselves under the project or folder they work in; projects you make stay put, and
  scratch sessions (⌘⇧N) are for throwaway work.
- Quitting Calm detaches your shells and relaunching brings everything back: sessions, splits,
  scrollback and running agents. Calm → Restart Calm does it in one step.
- Rename, resume and fork a conversation into a new split or tab; ⌘⇧T reopens a closed session.

### Agents
- Claude Code, Codex, OpenCode and pi are detected from their processes. Connect their hooks from
  Calm → Agents… for exact state (each asks first and can be undone).
- Each session card shows the agent's mark, its state (working, needs you, done, failed), what it
  last said, and its todo progress where the agent keeps a list. Only *needs you* notifies, at a
  natural pause.
- With the sidebar hidden, an arrival card tells you what happened in a session since you left it.

### Finding and reading
- ⌘K searches every agent's past conversations, grouped like the sidebar.
- ⌘P lists what Calm does that has no key everyone knows (one-shot commands).
- ⌘-click opens a URL, or a file at its line, and holding ⌘ shows a tag saying where it leads.
  ⌥-click copies a table cell.
- A files column (⌘\) shows the project's tree and changes, and a viewer opens Markdown, HTML, PDFs,
  images and code without leaving Calm.

### Look
- Five soft themes in light and dark pairs that follow the system, carried through the whole window;
  Ghostty's own colors are a last choice. Motion can be reduced or turned off.
- A small settings page (⌘,): Appearance, Agents, General and Shortcuts.

### Command line
- `calm open`, `list`, `search`, `status`, `notify` and `hook` talk to the running app; `status`,
  `notify` and `hook` are safe to run anywhere, outside Calm they do nothing.
