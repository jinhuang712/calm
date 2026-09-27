# UI and UX

How Calm Terminal looks, moves and behaves. Principles come from [PHILOSOPHY.md](PHILOSOPHY.md); behavior details from [FEATURES.md](FEATURES.md).

The design guidelines are **克制 restraint, 优雅 elegance, 极简 minimalism, calming** (see PHILOSOPHY.md). Every screen is checked against them.

A visual mock of these screens lives on the design canvas "Calm Terminal UI".

## Layout

```
┌──────────────────────────────┬──────────────┬─────────────────────────────────────┐
│  ⌘K  Search sessions         │  calm        │  ┌ arrival card (fades) ─────────┐  │
│                              │  main · 2 Δ  │  │ fix login test · needs you    │  │
│  VIBE-BILLING                │              │  │ "Should I also update the…"   │  │
│  ┌────────────────────────┐  │  ▸ Sources   │  └───────────────────────────────┘  │
│  │ C 审核记录未处理    now │  │  ▸ Tests     │                                     │
│  │ ◠ Working · reconciling│  │  ▾ docs      │   (the agent's own TUI, untouched)  │
│  │ ▬▬▬▬▬▬───── 3 of 5     │  │  README.md A │                                     │
│  │ Matching unprocessed…  │  │  UIUX.md   M │                                     │
│  └────────────────────────┘  │              │                                     │
│  ┌────────────────────────┐  │              │                                     │
│  │ C fix login test    2m │  │              │                                     │
│  │ ● Needs you · asked    │  │              │                                     │
│  │ Should I also update…  │  │              │                                     │
│  │ ⎇ wt-fix-login  +12 −4 │  │              │                                     │
│  └────────────────────────┘  │              │                                     │
│  + New Project               │              │                                     │
└──────────────────────────────┴──────────────┴─────────────────────────────────────┘
   sidebar (periphery)          files (⌘⇧E,     main area (center): the session,
                                optional)       or a viewed file (esc returns)
```

- **Sidebar:** projects and session cards. The periphery, where status lives.
- **Files:** an optional column right of the sidebar, showing the focused session's project.
- **Main area:** the session's terminal. Calm never draws over it, except the arrival card, which fades. A viewed file temporarily takes its place.

## Session cards

| Line | Content | Shown when |
|---|---|---|
| 1 | agent icon · **session name** · time since last activity | always |
| 2 | state mark · state · current step (e.g. "Running reconciliation") | always |
| 3 | thin progress bar · "3 of 5 todos" | the agent keeps a todo list |
| 4 | recap: the latest agent message, two lines at most | always |
| 5 | worktree mark · worktree name · diff size | the session runs in a git worktree |

- Plain shells are a single compact line: name and folder.
- Only *needs you* tints a card. The selected card gets a slightly lighter surface.
- Secondary text stays muted; only the name is in the primary text color.
- Projects collapse to one line with a summary.

## Viewing files

- Opening a viewable file (Markdown, HTML, PDF, images, code) **covers the main area**. The sidebar and files column stay.
- The header shows the file name and path, **Open in editor**, and **esc · Back to <session>**.
- Content is centered at a comfortable reading width.
- **Esc** returns to the session exactly as it was. The session keeps running while the file is open; if it needs you, its card tints as usual.

## Session states

| State | Indicator | Loudness |
|---|---|---|
| idle | nothing | silent |
| working | a slow, subtle pulse on the agent icon | silent |
| done | small check, muted | silent until visited |
| failed | small mark in the theme's muted red | silent until visited |
| **needs you** | soft highlight on the row, plus a dot | the only state that may notify |

Rules:

- Never more than one level of emphasis at a time per row.
- No numeric badges, no rings around panes, no reordering rows when states change.
- A visited session clears *done* and *failed* back to idle.

## Notifications

1. **Needs you** in a session the user is not looking at → a macOS notification, held until the user pauses (stops typing for a moment or switches focus).
2. The notification says which session and what it asked, in one line.
3. Clicking it brings Calm forward and focuses that session.
4. No sound by default.
5. Nothing else notifies unless the user opts in.

## Arrival card

- Appears at the top of the pane when switching into an agent session.
- Content: title · state · time since last activity, and one or two lines of the last agent message.
- Fades out on the first keystroke or after a few seconds. A shortcut shows it again.
- Never covers the agent's input line.

## Search (⌘K)

- A centered, native-feeling panel with one text field.
- Results update as the user types; each row shows agent icon, title, project, relative time and a highlighted snippet.
- ↑/↓ to move, Enter to jump or resume, Esc to close.
- The current project's sessions rank slightly higher.

## Color

- Soft palettes only in the default set: low contrast between text and background (roughly 6:1 to 11:1), low accent saturation, neutral backgrounds.
- The accent color is used sparingly: the selected row and the *needs you* highlight.
- Red appears only for *failed* and real errors.
- Chrome (sidebar, panels) takes its colors from the theme, never from a fixed system tint that clashes with the terminal.

## Typography

- The terminal uses the user's Ghostty font.
- Chrome uses the system font (SF Pro) at small, regular weights. Titles are medium weight, never bold.
- One size step between session titles and secondary text; no more.

## Motion

Smooth, fluid motion is part of what makes Calm feel calm. Motion is on by default; it is soft, never showy.

**Principles**

- Motion explains change: rows slide when sessions move between projects, panels ease in and out.
- Durations are short and easing is gentle; nothing bounces or flashes.
- The *working* pulse is slow and low-contrast so it never pulls the eye.
- Everything respects **Reduce Motion**.

**Terminal**

| Motion | Behavior |
|---|---|
| Smooth scrolling | scrollback glides with the trackpad instead of jumping line by line |
| Smooth cursor | the cursor glides to its new position instead of teleporting (through Ghostty's custom-shader support) |
| Cursor trail | a faint, short trail behind fast cursor moves; subtle enough to go unnoticed until it's gone |

**Window**

| Motion | Behavior |
|---|---|
| Splits | new panes grow into place and closed panes fold away |
| Sidebar | when hidden, it peeks in as the pointer nears the edge and slides away again |
| Session switching | cycling sessions shows small live previews, then settles on the chosen one |
| Session cards | cards slide between projects; state changes cross-fade; the recap updates without jumping |
| Files and viewer | the files column slides in from the sidebar's edge; a viewed file fades up over the session, and esc fades it back |
| Arrival card | fades in on arrival and dissolves when you type |
| Adaptive background | the window's chrome gently follows the background color a full-screen app paints |

**Settings:** Settings → Appearance holds one motion control (full, reduced or off). Individual effects stay adjustable in the config file.

## Themes

- The picker is a grid of live previews (sidebar, tabs and terminal together), in Settings → Appearance.
- Themes come in light and dark pairs and follow the system appearance.
- Optional glass background uses the system's material; the terminal can float as a rounded card or run edge to edge.

## Settings screen

| Section | Contents |
|---|---|
| **Appearance** | theme picker, font and size, glass or solid, motion (full, reduced, off) |
| **General** | editor, where paths open, auto-grouping |
| **Agents** | which states notify, sound |
| **Keys** | shortcuts |
| **Advanced** (collapsed) | open config file, updates, SSH options |

Rules: one line of help text per setting at most; no setting that only shows or hides a button.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘K | Search sessions |
| ⌘P | Command palette |
| ⌘T / ⌘D / ⌘⇧D | New tab / split right / split down |
| ⌘1…9 | Jump to session by position |
| ⌘⇧A | Jump to the next session that needs you |
| ⌘⇧E | Toggle the files column |
| esc | Close a viewed file and return to the session |
| ⌘⇧I | Show the arrival card again |
| ⌘, | Settings |

Audited against Ghostty's macOS defaults (M1.10):

- **⌘K** is Ghostty's *clear screen*. Calm takes it for search when search lands (M4); Calm's built-in defaults then move clear screen to ⌘⇧K. Calm's defaults load before the user's Ghostty config, so the user's own keybindings still win.
- **⌘⇧J** is Ghostty's *write screen to file*, so "jump to the next session that needs you" uses **⌘⇧A** (A for attention).
- ⌘P, ⌘⇧E, ⌘⇧I are free in Ghostty's defaults. ⌘1…9, ⌘[ / ⌘], ⌘⇧[ / ⌘⇧] keep Ghostty's meaning (tab/session by position, previous/next split, previous/next tab).

## Accessibility

- Full keyboard operation.
- VoiceOver labels for every sidebar row and state.
- State is never shown by color alone: each state also has a shape.
- Respects Reduce Motion, Increase Contrast and system text size for chrome.
