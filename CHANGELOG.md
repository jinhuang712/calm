# Changelog

What changed in each release of Calm Terminal. Before 1.0 anything may change between versions.

## Unreleased

### Agents
- `calm new --model <name>` starts the new session with that model, for a script that wants a cheaper or stronger one than ⌘N's default.
- `calm doctor --report` prints a redacted Markdown bug report (the checks and the last minutes of the trace) that an agent can show you and, once you agree, file as an issue. Calm uploads nothing.

### Fixes
- A long first message (about 800 bytes, or 270 Chinese characters) in `calm new` or `calm fork` is no longer cut off in the middle of a character and left unsent. Calm types a short `source` line and the whole command comes from a private file that removes itself.
- A permission prompt you answered no longer keeps the card on "Needs you" while Claude Code works. The card returns to Working when Claude's status says it is busy.
- A relative path in a link opens the file in the agent's git worktree first, then in the session's folder.

## 0.1.4 — 2026-10-22

A public preview for macOS 14.5 and later on Apple silicon. These changes follow 0.1.3. Exact behavior is in [FEATURES.md](specs/FEATURES.md) and [CLI.md](specs/CLI.md).

**Update** with **Update and Restart** in the sidebar's update notice, or run `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash` again and choose Calm → Restart Calm. Your shells keep running. Restart soon after installing: until then, the old Calm's shells can lose access to Desktop, Documents and Downloads.

### Agents
- `calm new "<first message>" --in <folder> [--background]` starts a clean session with a first message. It works from a script outside Calm.
- While an agent's card says "1 shell running", its mark keeps moving as if working, and settles when the last shell ends.
- After Calm restarts, a card keeps its count of running shells.

### Fixes
- `claude -p` run from inside a Claude Code session (by its Bash tool, say) no longer flips that session's card between done and working, or notifies for each nested answer.
- Markdown files show their local pictures, hide HTML comments as GitHub does, and show front matter (the `---` block at the top of a SKILL.md) as a quiet key/value list, not a heading.
- The About panel says "Version 0.1.4", not "0.1.4 (1)".

## 0.1.3 — 2026-10-13

A public preview for macOS 14.5 and later on Apple silicon. These changes follow 0.1.2. Exact behavior is in [FEATURES.md](specs/FEATURES.md) and [CLI.md](specs/CLI.md).

**Update** with **Update and Restart** in the sidebar's update notice, or run `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash` again and choose Calm → Restart Calm. Your shells keep running. Restart soon after installing: until then, the old Calm's shells can lose access to Desktop, Documents and Downloads.

### Agents
- Claude Code, Codex, OpenCode and pi now know the `calm` commands. One shared skill teaches them to search, show, fork (always with `--background`) and list sessions. Claude Code gets it through Calm's plugin, pi through its extension, and OpenCode and Codex through Connect in Settings → Agents. Codex now has a Connect step.
- `calm show <session id>` shows what a session is running or last ran, so an agent can check a fork without waiting. `calm list` prints the session id first on every row.

### Fixes
- After `/compact`, the compaction bar stays only on the finished card. It no longer hangs on the next turn's working card or comes back when that turn ends.

## 0.1.2 — 2026-10-12

A public preview for macOS 14.5 and later on Apple silicon. These changes follow 0.1.1. Exact behavior is in [FEATURES.md](specs/FEATURES.md).

**Update** with **Update and Restart** in the sidebar's update notice, or run `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash` again and choose Calm → Restart Calm. Your shells keep running. Restart soon after installing: until then, the old Calm's shells can lose access to Desktop, Documents and Downloads. A new install: [README → Install](README.md#install).

### Compatibility and updates
- Calm now runs on macOS 14.5 and later. Older macOS versions use AppKit fallbacks for scrolling and text-field carets; CI type-checks the app and CLI against the minimum version.
- The update notice offers Update and Restart: it installs the selected release with `get.sh`, then restarts Calm on that version.
- After an installer moves a running Calm aside, the old copy is removed once it quits, so Restart Calm opens the newly installed app.

### Reliability and reading
- A stuck zmx process, control client or updater no longer blocks Calm indefinitely.
- Viewed HTML runs no page scripts, and text files can open in encodings other than UTF-8.
- First launch requests notification and Desktop, Documents and Downloads access once, one prompt at a time. A saved session file that cannot be read or saved reports the failure; an unreadable file is kept for recovery.

## 0.1.1 — 2026-10-12

A public preview still, for macOS 26 on Apple silicon: what changed since 0.1.0. Exact behavior of everything below is in [FEATURES.md](specs/FEATURES.md).

**Update** by running the one line again: `curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash`. With Homebrew, run `brew upgrade --cask calm`, then `/usr/bin/xattr -dr com.apple.quarantine /Applications/Calm.app`. From the disk image (`Calm-0.1.1.dmg` below), quit Calm, drag the new one over the old one, run the same `xattr` line and open Calm. Your shells keep running: after the one line or Homebrew, choose Calm → Restart Calm to switch to 0.1.1. macOS asks again for Desktop, Documents and Downloads. A new install: [README → Install](README.md#install).

### Agents
- A working card says what Claude Code is doing, from the hooks it already sends: "Reading SessionCard.swift", "Running the full test suite", "Thinking". A todo list is a quiet line, "3 of 5 · Adding tests", in place of the thin bar. Other agents still say "Working".
- Esc on a prompt you just sent, or on a permission prompt or dialog, ends the card's working or needs-you state. Claude Code sends no hook for it, so the card used to stay on "Thinking" or "Needs you".
- An idle card says how many shells its agent left running: "2 shells running ·" before the recap.
- Until a new turn replies, its card shows Claude's recap of the last one, when Claude wrote one. A stand-in reply (the error Claude Code writes when the Mac sleeps mid-response) no longer shows as the latest message, or as a conversation of size 0 beside the compaction bar.
- Resume, ⌘⇧T, the resume after a restart of the Mac, Copy Resume Command, Fork and `calm fork` keep the options the agent was started with, such as `--dangerously-skip-permissions`. A conversation Calm didn't see start (⌘K's resume, `calm show`) takes the options ⌘N starts the agent with.
- Claude Code in a scratch session (⌘⇧N) no longer asks whether you trust the folder: Calm marks the scratch root trusted in `~/.claude.json`, once.

### Sessions and projects
- Opening a project (⌘O, a dropped folder, `calm open`, the welcome page, a click on the project's header) shows its home: its name, folder and branch, a line to start an agent or a shell, and the sessions that ran there. The header's chevron folds it.
- Projects can be dragged into another order by their header.

### Finding and reading
- ⌘+, ⌘− and ⌘0 size the open file, not the terminal under it. A page of text keeps its size for the next file and the next launch; a PDF or a picture starts fitted. The file's row shows the size when it isn't 100%, with − and + under the pointer, and a click on the number goes back to 100%.
- The way back from a file is a quiet chevron at the left of its row, in place of the outlined esc key.
- An untracked folder with more than 500 files is one row in the files column. A project whose `node_modules` wasn't ignored showed 57,000 rows and kept Calm busy.

### Updates
- Calm tells you when a newer release is out: once a day it asks GitHub, and the sidebar's top strip shows `↑ 0.2.0`; a click on it offers Release Notes, Copy Update Command and Skip. Calm → Check for Updates… asks now. Settings → General → Check for updates turns the daily check off. Calm only tells: it doesn't install the update.
- `get.sh --edge` installs the newest build of `main`, which CI keeps as the `edge` pre-release, for a Mac without Xcode. It is not a release, and its version names its commit (`0.1.1-<commit>`).

### Command line
- `calm screenshot [<file>]` saves a PNG of Calm's window. Calm draws it itself, so it needs no Screen Recording permission.

## 0.1.0 — 2026-10-08

The first release, a public preview, for macOS 26 on Apple silicon. Its author has used it as their only terminal since 2026-09-29, and nobody else has tried it, so expect rough edges (README → Known limits). Exact behavior of everything below is in [FEATURES.md](specs/FEATURES.md).

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
- `calm open`, `list`, `search`, `show`, `fork`, `config`, `doctor` and `trace` for you and your agents; `status`, `hook` and `notify` for agents' hooks, safe to run anywhere: outside Calm they do nothing. Every command is in [CLI.md](specs/CLI.md).
