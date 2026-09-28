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
│  + New Project            ⌘O │              │                                     │
└──────────────────────────────┴──────────────┴─────────────────────────────────────┘
   sidebar (periphery)          files (⌘⇧E,     main area (center): the session,
                                optional)       or a viewed file (esc returns)
```

- **Sidebar:** session groups and session cards. The periphery, where status lives. At the top, under the traffic lights, a soft filled **Search sessions ⌘ K** field opens search. Then scratch sessions, projects you made (uppercase, with a project mark), and folder groups (the folder's own name, its parent folder on the right). Scratch rows show a quiet × on hover or while selected, in the place of the time or state mark so nothing overlaps; a scratch session's folder never shows anywhere. The footer is three rows, each with its icon on a small tile and its shortcut as key caps: New Session ⌘T, New Scratch Session ⌘⇧N, New Project… ⌘O; each row lights up on hover. Sizes lean roomy (a 320 pt sidebar, 14 pt text, 40 pt rows, 26 pt agent marks in each agent's own soft tint) so the sidebar reads at a glance without leaning in.
- **Welcome page:** with no session open, a short page fills the whole window (no sidebar; only the traffic lights above it), centered: Calm's mark (nested rounded squares in the theme's accent), a title ("Welcome to Calm" the first time, "No sessions open" later), three cards (New Session ⌘T, the one in the accent; New Scratch Session ⌘⇧N; New Project… ⌘O), and under them a quiet pill showing the agents Calm works with, each with its own mark, that opens Settings → Agents. A window too small for that gets the same choices as a short list. It replaces the first-launch Agents panel.
- **Files:** an optional column right of the sidebar, showing the focused session's project.
- **Main area:** the session's terminal. Calm never draws over it, except the arrival card, which fades. A viewed file temporarily takes its place.

**Title bar:** there's no visible title bar; the strip at the top of the window (over the sidebar and above the terminal) stands in for it. Dragging it moves the window, and double-clicking it does what System Settings → Desktop & Dock says (Zoom by default, or Fill, Minimize, nothing).

## Session cards

| Line | Content | Shown when |
|---|---|---|
| 1 | agent's mark · **session name** · time since last activity | always |
| 2 | state mark · state · current step (e.g. "Running reconciliation"), or how long it's been working ("Working · 4m") | not idle |
| 3 | thin progress bar · "3 of 5 todos" | not idle, and the agent keeps a todo list |
| 4 | recap: the latest agent message, two lines at most (one when idle) | always |
| 5 | worktree mark · worktree name · diff size | the session runs in a git worktree |

- A name too long for its line keeps its start and ends in "…". Rest the pointer on the card or row for half a second and the name glides once to its end and holds; it slides back when the pointer leaves. With motion reduced it stays truncated.
- Plain shells are a single compact line: name and folder, plus the state mark when a long command finished (hover shows its message).
- Each state has its own look (see Session states): *working* tints the card a soft blue, *needs you* amber, *done* sage until you move on from it; an idle card recedes (its mark in gray, its name dimmer) and is shorter: no state line or progress bar, one line of recap, tighter padding. That includes done and failed cards once you move on: clicking one keeps it tall while you read, and it settles to idle when you go to another session or leave Calm. The selected card gets a slightly lighter surface.
- The agent mark is the agent's own logo in a small neutral tile (see Agent marks); a letter (C, X, O, π, ω) stands in if a mark can't be drawn.
- Collapsed projects summarize what needs a look: "3 sessions · 1 needs you".
- Secondary text stays muted; only the name is in the primary text color.
- Projects collapse to one line with a summary.

**Right-click a card:** Rename…, Resume <agent> Conversation (after the agent exited), Fork into New Split, Fork into New Tab (where the agent can fork), Pin to Project, Close Session. Rename edits the title in place, in the card's own spot.

## Viewing files

- Opening a viewable file (Markdown, HTML, PDF, images, code) **covers the main area**. The sidebar and files column stay.
- The header shows the file name and path, **Open in editor**, and **esc · Back to <session>**.
- Content is centered at a comfortable reading width.
- **Esc** returns to the session exactly as it was. The session keeps running while the file is open; if it needs you, its card tints as usual.

## Session states

| State | Indicator | Loudness |
|---|---|---|
| idle | a shorter card: the agent's mark in gray at 45%, name dimmed, one line of recap | silent |
| working | soft blue card; the agent's mark moves in its own way; "Working · 4m" in blue, a soft light crossing it every 2.6 s | silent |
| done | sage card with a filled check, until visited (then idle) | silent until visited |
| failed | small mark in the theme's muted red | silent until visited |
| **needs you** | amber card, plus a dot | the only state that may notify |

When the work ends, the mark settles once, in about a second, before it rests.

## Agent marks

Each agent shows its own logo, which moves only while the agent works. The motions follow each agent's own, slowed and softened where Calm poses them; they run at 30 frames a second, and not at all with Reduce Motion.

| Agent | Mark | Working | Finishing up |
|---|---|---|---|
| Claude Code | the spark, in clay | Claude Code's own spinner: a dot opening into the spark and drawing back in without a pause, running forwards and backwards (4 s) | the spinner fades into the resting spark |
| Codex | OpenAI's Blossom, one color | one eased turn, then a short rest (1.6 s + 0.6 s) | slows to a stop |
| OpenCode | its block frame | twelve small squares breathing on their own rhythms, as OpenCode's app spinner does | the squares fade into the mark |
| pi | the pixel π in coral, blue and gold | the pieces drop into place, hold and fall away (3.2 s), after pi.dev's logo | the last piece lands and the π brightens twice, softly |
| omp | the block π in its pink-violet-cyan gradient | the gradient turns inside the π while a shine crosses it | the turn slows, one last shine |

The marks belong to their owners (see NOTICE) and are shown only to say which agent a session runs.

Rules:

- Never more than one level of emphasis at a time per row.
- No numeric badges, no rings around panes, no reordering rows when states change.
- A session you leave (for another session, or another app) clears *done* and *failed* back to idle; arriving keeps them while you read.

## Notifications

1. **Needs you** in a session the user is not looking at → a macOS notification, held until the user pauses (stops typing for a moment or switches focus).
2. The notification says which session and what it asked, in one line.
3. Clicking it brings Calm forward and focuses that session.
4. No sound by default.
5. Nothing else notifies unless the user opts in.

## Arrival card

- Appears at the top of the pane when switching into an agent session, only when it adds something: the sidebar is hidden (its card would say the same) and the session had activity since the user left it. ⌘⇧I shows it any time.
- Content: state mark, title · state · time since last activity, and one or two lines: what the agent asked while it needs you, otherwise the last thing it said.
- Fades out on the first keystroke or after a few seconds. A shortcut shows it again.
- Never covers the agent's input line.

## Search (⌘K)

- A centered, native-feeling panel with one text field behind a quiet magnifying glass; it hugs a short list of results and shows seven and a half rows before scrolling.
- Results update as the user types; each row has one fixed height and two lines: agent icon, title, then project · time on the right ("3h" within a week, a date like "Apr 14" after); below, one line of snippet that opens a few words before the match, so the highlighted match is always visible.
- ↑/↓ to move, Enter to jump or resume, Esc to close. A quiet footer line says what Enter does for the selected row, so rows never change height: "↵ Open" for a session open in Calm, "↵ Resume in <folder>" otherwise (a new session runs the agent's resume command there), and "↵ New session in <folder> · <agent> deleted this conversation, so it can't be resumed" when the transcript is gone.
- An empty field lists the most recent sessions.
- The current project's sessions rank slightly higher.

## Color

- Soft palettes only in the default set: low contrast between text and background (roughly 6:1 to 11:1), low accent saturation, neutral backgrounds.
- The accent color is used sparingly: a switch that's on, the picked theme and the project mark. It never colors a state.
- Each state keeps one color on every theme: amber for *needs you* (whatever the theme's accent), a soft blue for *working*, sage for *done* (until you move on), muted red for *failed*. Every state also has its own mark and words, so color never carries it alone.
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
- An agent's mark moves only while it works, in its own way, slowed and softened so it never pulls the eye; when the work ends it settles once and rests.
- Everything respects **Reduce Motion**.
- A panel that changes the terminal's size resizes it once; only the picture glides. Programs redraw on every resize, and a resize per frame would make an agent's screen flicker.

**Terminal**

| Motion | Behavior |
|---|---|
| Smooth scrolling | scrollback glides with the trackpad instead of jumping line by line. **Blocked:** upstream Ghostty scrolls by whole rows; pixel-smooth scrolling needs an engine change (see DESIGNS.md) |
| Smooth cursor | a soft smear follows the cursor when it jumps (not when typing moves it one cell), fading in about 140 ms. Calm's own shader `cursor_glide.glsl`, loaded through Ghostty's custom-shader support |
| Cursor trail | part of the same shader: the smear's tail catches up with its head, so it reads as a short trail |

**Window**

| Motion | Behavior |
|---|---|
| Splits | new panes grow into place and closed panes fold away |
| Sidebar | when hidden, it peeks in over the terminal as the pointer reaches the window's left edge, and slides away shortly after the pointer leaves it |
| Session switching | hold ⌃ and press Tab to cycle sessions in sidebar order, top to bottom (⌃⇧Tab goes up, both wrap), over small live previews; release ⌃ to settle on the chosen one. A quick ⌃Tab goes straight to the next session down without showing anything |
| Session cards | cards slide between projects; state changes cross-fade; the recap updates without jumping. The agent's mark moves while it works and settles once when the work ends (see Agent marks) |
| Files and viewer | the files column slides in from the sidebar's edge; a viewed file fades up over the session, and esc fades it back |
| Arrival card | fades in on arrival and dissolves when you type |
| Adaptive background | the window's chrome gently follows the background color a full-screen app paints |

**Settings:** Settings → Appearance holds one motion control (full, reduced or off), saved as `motion` in `config.toml`; it dims and says why while the system's Reduce Motion is on. The system's Reduce Motion always wins. Individual effects stay adjustable in the config file.

## Themes

- The picker, in Settings → Appearance, is a row of small previews under a live miniature of the window (sidebar and terminal in the picked theme, layout and background). A solid window fills the page's width; glass sits on a soft desktop that shows through it. The user's Ghostty colors, when their config sets any, are a separate last choice.
- Themes come in light and dark pairs and follow the system appearance.
- Calm's default theme gives way to a theme set in the user's Ghostty config; a theme picked in Calm wins.
- Optional glass background uses the system's material; the terminal can float as a rounded card or run edge to edge.
- The padding around the terminal takes the color of the cells next to it, so an app that paints its own background (OpenCode, Neovim) fills the pane instead of sitting in a frame of the theme's color. The user's Ghostty `window-padding-color` wins. Edge to edge on a solid background, the title strip above the terminal takes the same color, so the two meet without a seam.

## Settings screen

⌘, turns the whole window into Settings, as the welcome page fills it; ⌘, again or esc goes back to the session exactly as it was (it keeps running underneath). A list of sections takes the sidebar's place, as wide as the sidebar and drawn like its footer (14 pt rows of 40 pt, each icon on a small tile), so ⌘, reads as the sidebar changing what it lists. The page sits beside it at a reading width (720 pt at most, 14 pt labels, 52 pt rows), in the theme's own colors: the sidebar's color for the list, the terminal's for the page, the theme's accent for the picked theme and a switch that's on. A chosen segment is a lighter surface, as a selected card is.

```
┌────────────────────┬──────────────────────────────────────────────┐
│ ● ● ●              │   Appearance                                 │
│                    │   ┌ live miniature of the window ──────────┐ │
│ Settings           │   └────────────────────────────────────────┘ │
│ ◐ Appearance       │   Theme              ▢ ▢ ▢ ▢ ▢ ▢ │ ▢ Ghostty │
│ ✦ Agents        ⚠  │   ┌──────────────────────────────────────┐   │
│ ≡ General          │   │ Background            [Solid | Glass] │   │
│ ⌨ Shortcuts        │   │ Layout         [Edge to edge | Card]  │   │
│                    │   │ Motion        [Full | Reduced | Off]  │   │
│ ┌ fix login test ┐ │   │ Terminal font   Open Ghostty Config   │   │
│ └ Needs you ─────┘ │   └──────────────────────────────────────┘   │
│ esc Back           │                                              │
└────────────────────┴──────────────────────────────────────────────┘
```

| Section | Contents |
|---|---|
| **Appearance** | a live miniature of the window, the themes, glass or solid, edge to edge or card, motion (full, reduced, off), and which font the terminal uses (it's set in the Ghostty config) |
| **Agents** | each installed agent with its mark and where it stands (Connected, One step left, or Connect/Disconnect where Calm must add a file), the agents not installed, which states notify, sound. Calm → Agents… opens this section |
| **General** | editor, where paths open, auto-grouping, and the config files (Calm's, Ghostty's, the themes folder) with Reload Files |
| **Shortcuts** | Calm's shortcuts as key caps, read-only; keys are changed in the Ghostty config |

- A session that needs you shows at the foot of the list, in its card's tint; one click goes to it. Going to any session (⌃Tab, ⌘1…9, search, a new session) leaves Settings.
- A section gets a small warning mark only when something in it is broken: Agents when macOS blocks Calm's notifications (with a button to System Settings), General when a line of config.toml can't be read (shown under the file).
- Settings reopens on the section it was left on. A window too narrow for the list and the page shows the list as icons.

Rules: one line of help text per setting at most; no setting that only shows or hides a button.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘K | Search sessions |
| ⌘P | Command palette |
| ⌘T / ⌘D / ⌘⇧D | New tab / split right / split down |
| ⌘⇧N | New scratch session |
| ⌘O | New project |
| ⌘1…9 | Jump to session by position |
| ⌃Tab / ⌃⇧Tab | Cycle sessions down / up the sidebar (hold ⌃) |
| ⌘⇧A | Jump to the next session that needs you |
| ⌘⇧E | Toggle the files column |
| esc | Close a viewed file and return to the session |
| ⌘⇧I | Show the arrival card again |
| ⌘, | Settings |

Audited against Ghostty's macOS defaults (M1.10):

- **⌘K** is Ghostty's *clear screen*. Calm takes it for search (M4): Calm's built-in defaults unbind it and move clear screen to **⌘⇧K** (the Edit menu shows it there). Calm's defaults load before the user's Ghostty config, so the user's own keybindings still win.
- **⌘⇧J** is Ghostty's *write screen to file*, so "jump to the next session that needs you" uses **⌘⇧A** (A for attention).
- **⌃Tab** is Ghostty's *next tab* on some platforms and a key a few TUIs read; in Calm it always opens the session switcher, since sessions are Calm's tabs.
- **⌘,** is Ghostty's *open config*, which Calm doesn't support; Calm's defaults unbind it so it opens Settings, the Mac convention.
- ⌘P, ⌘⇧E, ⌘⇧I, ⌘⇧N, ⌘O are free in Ghostty's defaults (Ghostty's ⌘N, new window, becomes a new session in Calm's one window). ⌘1…9, ⌘[ / ⌘], ⌘⇧[ / ⌘⇧] keep Ghostty's meaning (tab/session by position, previous/next split, previous/next tab).

## Accessibility

- Full keyboard operation.
- VoiceOver labels for every sidebar row and state.
- State is never shown by color alone: each state also has a shape.
- Respects Reduce Motion, Increase Contrast and system text size for chrome.
- **Increase Contrast:** the chrome's secondary text, hints, selection and dividers get stronger. A Calm theme's text colors each reach 4.5:1 by moving toward white (dark) or black (light), so dim text stays dimmer than normal text. A theme from the user's Ghostty config is left as it is (Ghostty's `minimum-contrast` is theirs to set).
- A change to Reduce Motion or Increase Contrast in System Settings applies at once, without a relaunch.
- The files column's files are buttons, so Full Keyboard Access and VoiceOver reach them; each reads its name and change ("README.md, modified").
