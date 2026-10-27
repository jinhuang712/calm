<!-- what-we-build: drafted 2026-10-28 -->

<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.png">
  <img src="assets/logo.png" alt="Calm's app icon: a ring of soft squares with one amber cursor" width="128">
</picture>

# Calm Terminal

> A minimal macOS terminal that keeps you calm and focused.

[![CI](https://github.com/jinhuang712/calm/actions/workflows/ci.yml/badge.svg)](https://github.com/jinhuang712/calm/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-2563eb?style=flat-square)](LICENSE)
![macOS 14.5+](https://img.shields.io/badge/macOS-14.5%2B-111827?style=flat-square&logo=apple&logoColor=white)
![Apple silicon](https://img.shields.io/badge/Apple%20silicon-only-111827?style=flat-square)
![Swift 6](https://img.shields.io/badge/Swift-6-F05138?style=flat-square&logo=swift&logoColor=white)
![Status: public preview](https://img.shields.io/badge/status-public%20preview-f59e0b?style=flat-square)

<br>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/hero-dark.png">
  <img src="assets/hero-light.png" alt="Calm with three Claude Code sessions in the sidebar: one finished, one thinking, and one that needs you, with its question on screen" width="100%">
</picture>

</div>

Calm is a terminal for days spent supervising CLI coding agents such as Claude Code, Codex, OpenCode and pi. It interrupts you for one thing only: an agent that needs you. Calm stays a terminal, so the agents keep their own interfaces.

> [!NOTE]
> Version [0.1.4](CHANGELOG.md), a public preview. Only the author has used it, since 2026-09-29, so expect rough edges (see Known limits below).

## 🔔 One look tells you who needs you

The sidebar above shows three real Claude Code sessions: one has finished, one is thinking, and one wants to run a command. Only *needs you* sends a notification, at the next natural pause. **⌘⇧A** jumps to the session that has waited longest.

## 🧭 Resume, restart or fork any session

<img src="assets/menu.png" alt="The session menu: Restart after this turn, Fork into a split or a tab, Rename, copy the session id or the resume command" width="100%">

Quit Calm and every shell, split and running agent comes back. Restart an agent on its conversation, fork it, or copy its resume command. **⌘K** searches the history of every agent, even after an agent deletes its transcripts.

## ⌘P Actions that have no key

<img src="assets/palette.png" alt="The command palette, with rows such as Rename Session, New Codex Session and Show File Tree" width="100%">

Start any agent, hide the files column, go to the welcome page. Each row runs once.

## 📖 Read what an agent changed

<img src="assets/files.png" alt="The files column beside a viewed Markdown file, with its tables rendered" width="100%">

A files column and a read-only viewer for Markdown, HTML, PDF, images, code and diffs. **⌘-click** a path opens it at its line, **⌥-click** copies one table cell, and **⌘F** finds in a session, even in a full-screen agent.

## 🪟 Splits that say where you are

<img src="assets/split.png" alt="Two panes side by side; the pane the user is in is bright and the other is dimmed" width="100%">

Split toward any side with **⌘⌥ + arrow**, drag a session card in, or take a pane out. The pane you are in is the bright one.

## 🎨 Soft themes, few settings

<table>
  <tr>
    <td width="33%"><img src="assets/theme-Dusk.png" alt="The Dusk theme, deep blue"></td>
    <td width="33%"><img src="assets/theme-Forest.png" alt="The Forest theme, green-gray"></td>
    <td width="33%"><img src="assets/theme-Plum.png" alt="The Plum theme, violet-gray"></td>
  </tr>
  <tr>
    <td align="center">Dusk</td>
    <td align="center">Forest</td>
    <td align="center">Plum</td>
  </tr>
  <tr>
    <td colspan="2"><img src="assets/settings.png" alt="Settings, Appearance: five themes, interface size and card sizes, each with a preview"></td>
    <td><img src="assets/welcome.png" alt="The welcome page: Start Claude Code, Start a shell, Try a scratch session, Open a project"></td>
  </tr>
  <tr>
    <td colspan="2" align="center">Settings → Appearance</td>
    <td align="center">The welcome page</td>
  </tr>
</table>

> [!NOTE]
> The pictures are headless screenshots of the development build (Calm Dev, which is why the mark is violet and the sidebar says DEV). The sessions are real Claude Code 2.1.311 with Haiku 5.5 in manual permission mode, and no command was approved. `scripts/readme-shots.sh` makes them again.

## ⌨️ Keys

| To do this | Press |
|---|---|
| Start your agent / a shell / a scratch session | ⌘N / ⌘T / ⌘⇧N |
| Open a project | ⌘O |
| Jump to the session that needs you | ⌘⇧A |
| Search every past conversation | ⌘K |
| Find in this session | ⌘F |
| Show or hide the files column | ⌘\ |
| Run an action that has no key | ⌘P |
| Reopen the session you closed | ⌘⇧T |
| Settings | ⌘, |

Every key is in [UIUX.md](specs/UIUX.md). The `calm` command reaches Calm from a shell: [CLI.md](specs/CLI.md).

## 📦 Install

Calm needs macOS 14.5 or later on Apple silicon.

```sh
curl -fsSL https://raw.githubusercontent.com/jinhuang712/calm/main/get.sh | bash
```

That downloads the newest release, puts Calm in Applications and links the `calm` command into `~/.local/bin`. Homebrew, the disk image, the newest build of `main`, building from source, updating and uninstalling are in [INSTALL.md](INSTALL.md).

## 💡 Good to know

- **Agents need no setup to be seen.** Calm detects them from their process. For exact state, connect them in **Calm → Agents…**. Each connection asks first and can be undone.
- **Calm is a terminal and nothing more.** It has no chat, editor, browser or account. Its own code uses the network once a day, to ask GitHub for the newest release. **Settings → General → Check for updates** turns that off.
- **The first launch asks for permissions once:** notifications, then Documents, Desktop and Downloads.
- **Quitting keeps your shells running.** Close the sessions you want to end first (⌘W).

## ⚠️ Known limits

- Apple has not signed the download, so each update asks again for folder access. Homebrew's own cask list takes only signed apps, so Calm has its own tap.
- Nobody has checked the first minute of a new user ([GOALS.md](GOALS.md) G10). Three features have more settings than the budget allows (G9).
- The OpenCode plugin, which reports state, has run only against a fake context.
- A window left in full screen can come back filled but not in full screen. The cause is unknown.
- A link set with OSC 8 gets no dotted mark. Calm does not join some links that a program cut across lines.
- There is no VoiceOver pass, and VoiceOver support is not a goal.

## 🛟 Reporting a problem

Open an [issue](https://github.com/jinhuang712/calm/issues). **⌘P → Dump Logs** writes a text file with the version, settings and session states. It holds only ids, states and counts, never a folder, a title or a word that anyone wrote. It is safe to attach.

## 📚 Documents

| Document | Answers |
|---|---|
| [PROPOSAL.md](PROPOSAL.md) | Why did we start this? |
| [PHILOSOPHY.md](PHILOSOPHY.md) | Why is it this way? |
| [DESIGNS.md](DESIGNS.md) | How is it built, and why that way? |
| [GOALS.md](GOALS.md) | What do we measure? |
| [FEATURES.md](specs/FEATURES.md) | What does it do, and what will it do? |
| [UIUX.md](specs/UIUX.md) | How does it look and move? |
| [CLI.md](specs/CLI.md) | What does every `calm` command do? |
| [ROADMAP.md](plans/ROADMAP.md) | When, and how far along? |
| [INSTALL.md](INSTALL.md) | How do I install, update and remove it? |
| [RUNBOOK.md](RUNBOOK.md) | How do I build, release and install it? |
| [TODO.md](plans/TODO.md) | What is still open? |
| [CHANGELOG.md](CHANGELOG.md) | What changed in each release? |
| [AGENTS.md](AGENTS.md) | How do coding agents work in this repository? |

## 📄 License

[Apache-2.0](LICENSE). See [NOTICE](NOTICE) for third-party attributions. Calm's terminal engine is libghostty from [Ghostty](https://github.com/ghostty-org/ghostty).
