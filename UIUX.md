# UI and UX

How Calm Terminal looks, moves and behaves. Principles come from [PHILOSOPHY.md](PHILOSOPHY.md); behavior details from [FEATURES.md](FEATURES.md).

The design guidelines are **克制 restraint, 优雅 elegance, 极简 minimalism, calming** (see PHILOSOPHY.md). Every screen is checked against them.

A visual mock of these screens lives on the design canvas "Calm Terminal UI".

## Layout

```
┌──────────────────────────────┬────────────────────────┬────────────────────────────────┐
│ ● ● ●                        │                        │ ▦ fix link marks             ⋯ │
│                              │                        │   ~/dev/apps/calm              │
│ ⌕ Search sessions        ⌘ K │ calm ⎇ main     +52 −4 │                                │
│                              │                        │                                │
│ ▾ ▦ CALM                     │ CHANGES 2              │                                │
│ ┌──────────────────────────┐ │ M UIUX.md       +12 −4 │                                │
│ │ C fix link marks     now │ │ A plan.md  docs    +40 │                                │
│ │   Working · Adding tests │ │ ────────────────────── │                                │
│ │   ▬▬▬▬▬▬▬▬───── 3 of 5   │ │ FILES                  │   (the agent's own TUI,        │
│ │   Marks now wait for the │ │ › Calm                 │    untouched)                  │
│ │   text to hold still.    │ │ ▾ docs               • │                                │
│ └──────────────────────────┘ │     plan.md          A │                                │
│ ┌──────────────────────────┐ │   README.md            │                                │
│ │ C fix login test      2m │ │   UIUX.md            M │                                │
│ │   ● Needs you            │ │                        │                                │
│ │   Should I also update…  │ │                        │                                │
│ │   ⎇ wt-fix-login         │ │                        │                                │
│ └──────────────────────────┘ │                        │                                │
│                              │                        │                                │
│ ──────────────────────────── │                        │                                │
│ ✎ New Session            ⌘ T │                        │                                │
│ ▢ New Scratch Session  ⌘ ⇧ N │                        │                                │
│ + New Project…           ⌘ O │                        │                                │
└──────────────────────────────┴────────────────────────┴────────────────────────────────┘
   sidebar (periphery)          files (⌘\, optional)     main area (center): the session,
                                                         or a viewed file (esc returns)
```

- **Sidebar:** session groups and session cards. The periphery, where status lives. At the top, under the traffic lights, a soft filled **Search sessions ⌘ K** field opens search. Then scratch sessions, projects you made (uppercase, each with its own pixel mark: a 5×5 pattern, mirrored like GitHub's identicons, made from the project's name, so the same name always gets the same mark; in one of eight soft, low-saturation hues on a pale 20 pt tile of it; clicking it crossfades to another, and never collapses the group), and folder groups (the folder's own name, and under it in 11 pt tertiary text where the folder is: its parent with the home folder as `~`, cut from the front when long, so the nearest folders stay; the line stays when the group is collapsed or hovered, so the header never changes height, and the home folder's own group has none). Scratch rows look like any other row, with no close button of their own (⌘W or the right-click menu closes one); a scratch session's folder never shows anywhere. Hovering a group header swaps its summary for two quiet controls: **+** (a new session there) and **⋯** (Make Project for a folder, Remove Project for a project; scratch has only +). Right-click offers the same. The footer is three rows, each with its icon on a small tile and its shortcut as key caps: New Session ⌘T, New Scratch Session ⌘⇧N, New Project… ⌘O; each row lights up on hover. Sizes lean roomy (a 320 pt sidebar, 14 pt text, 40 pt rows, 26 pt agent marks in each agent's own soft tint) so the sidebar reads at a glance without leaning in.
- **No session chosen:** after the session on screen is closed, the sidebar stays and the main area is plain terminal background, its title strip blank, with no selected row. Nothing takes the keyboard; the user chooses.
- **Welcome page:** with no session open, a page fills the whole window (no sidebar; only the traffic lights above it). **Calm's mark** stands at the top, always: the app icon, in its light or dark version with the theme (60 pt on the search page, 76 pt on the welcome, 48 pt in a small window). It arrives once: its ring draws itself in typing order, the center follows, and the cursor appears on the ring's last cell and takes the last step to its resting place slowly, settling once, as it does when an agent stops working. Then it waits, the cursor breathing slowly (down to 42% and back every 3.6 s) for eight breaths, and rests still, so an idle page doesn't keep redrawing; a click runs one lap of the chase, a small easter egg like the project marks'. With Reduce Motion (or `motion` reduced or off) it is the finished mark, still. The chase is the Dock icon's word for *working*, so the page never runs it by itself, and the agent marks on the page stay still for the same reason.
  - **Search and lists:** under the mark, a search field like the sidebar's, larger (46 pt, 14 pt corners), focused at once, with ⌘K on its right (a clear button once something is typed). Then two columns, 880 pt wide at most: **Recent sessions** on the left, six rows (three in a small window) of an agent mark, the session's title and under it its folder and how long ago; **Projects** on the right, the projects you made, each with its pixel mark (30 pt), name and folder. Rows are 54 pt tall like ⌘K's, and the one the arrow keys are on is filled, with a ↵ cap. A list taller than its room scrolls, fading out at its foot. Typing filters both. A session shows, as in ⌘K, the matching text under its title with the words marked; a project matches its name or its folder as shown, with the words marked (bold, and underlined in the name); each header gains a count, and a list with no match says so. ↑ ↓ move through the rows; ← → change list (inside the field, only at the text's edge or once the arrows have been used); ↵ opens; Esc clears. With no past sessions the projects take the page alone, the field reading "Search projects"; with no projects the sessions do. A window narrower than 760 pt stacks them, sessions first, in one scrolling list. There is no heading on this page: the mark and the field say what it is.
  - **The way to start:** at the bottom, one line, shortcut first: **⌘T New session · ⌘⇧N Scratch · ⌘O New project…**. Each is a button with a faint fill of its own (5.5%, 11% under the pointer), 13.5 pt, the shortcut a step brighter than the words: no icons, no key caps and no border, so it reads as something to press without the weight of a toolbar.
  - **Welcome:** with no project made, the very first launch, and any time there is no past session either, the page is a welcome instead: the mark at 76 pt, "Welcome to Calm" (first launch only) with "A terminal that keeps you calm while your agents work.", and the three ways to start as rows in the lists' own style (an icon on a small tile, the label, the shortcut as plain glyphs): Start a session ⌘T, drawn as the selected row; Try a scratch session ⌘⇧N; Open a project ⌘O. Making a project brings the lists back.
- **Files:** an optional column right of the sidebar, showing the focused session's project. One surface with the sidebar (a hairline between them, like the footer's), 272 pt wide, and level with it: the header sits on the search field's line (the project in 13.5 pt medium, the branch in a small pill like the search field, the line totals at the right in monospaced digits, added in *done*'s sage, removed in *failed*'s muted red), and the first section header on the sidebar's first group header's line. Section headers (**CHANGES** with its count, **FILES**) are drawn like project names: small capitals, tracked, tertiary. Change rows are 30 pt: the letter on a small tile, the name in the primary color, the nearest folder in tertiary, the lines at the right. Tree rows are 26 pt with 13.5 pt names: thin chevrons in a fixed 16 pt gutter so names line up at each depth, 16 pt more per level; names in the secondary color, changed files in the primary, dotfiles in tertiary. The viewed file gets the sidebar's selection; a row under the pointer gets half of it. Nothing is ever cut down to fragments: the branch pill and a change's folder show whole or not at all, and names lose their middle.
- **Main area:** the session's terminal. Calm never draws over it, except the arrival card, which fades, and the quiet marks and tag of links (see Links). A viewed file temporarily takes its place.

**Title bar:** there's no visible title bar; the strip at the top of the window (over the sidebar and above the terminal) stands in for it. It's 48 pt tall, a header row of its own below the traffic lights' line; the sidebar leaves the same room above its search field, so the two start level. Dragging it moves the window, and double-clicking it does what System Settings → Desktop & Dock says (Zoom by default, or Fill, Minimize, nothing); a window left filled comes back filled, and the next double-click still gives back its earlier size. At the left of the strip above the terminal, centered in it, are the session's group mark (a project's pixel tile, or the folder or scratch glyph, as in the sidebar; 20 pt, not clickable here, so the text starts in the same place for every session) and two lines, like a window's title and subtitle: the focused session's name, the same one its card shows, 13.5 pt medium in the primary color, and under it, 11 pt in the tertiary color, the folder it's in ("~" for home). A name that only repeats the folder (a plain shell titled "calm" or "…/apps/calm") is left out, and the folder takes the name's line and style; a scratch session shows no folder. A long name ends in "…"; a long folder loses its front. When the session's work is in a linked git worktree, a small pill follows the text, in the look of the files column's branch pill: the worktree mark and the worktree's name (12 pt, secondary, on a faint tile, 20 pt tall). It shows whole or not at all, and only when the name and folder already fit whole: the title never gives up room for it. A main checkout, a plain folder and a submodule have no pill, so the strip stays as quiet as before. The pill follows the folder the agent works in, which can be a worktree while its shell is still in the main checkout. With the sidebar hidden it starts after the traffic lights. It doesn't animate when it changes. The welcome page, Settings and a viewed file cover it. The window's own title (hidden) carries the same name, so the Window menu, Mission Control and VoiceOver get it; with no session it's "Calm".

## Session cards

| Line | Content | Shown when |
|---|---|---|
| 1 | agent's mark · **session name** · time since last activity | always |
| 2 | state mark · state · current step (e.g. "Running reconciliation"), or how long it's been working ("Working · 4m"); while working, the agent's moving mark stands in for the state mark. A done card whose turn left shells running adds "· 2 shells running" in the tertiary color: a footnote, gone once you move on | not idle |
| 3 | thin progress bar · "3 of 5" | not idle, and the agent keeps a todo list |
| 4 | recap: the latest agent message as plain text (no Markdown marks: headings, code blocks and bold go, a list reads "a; b; c"), two lines at most (one when idle) | always |
| 5 | worktree mark · worktree name | the session runs in a git worktree |

- A name too long for its line keeps its start and ends in "…". Rest the pointer on the card or row for half a second and the name glides once to its end and holds; it slides back when the pointer leaves. With motion reduced it stays truncated.
- Plain shells are a single compact line: the shell's title (the folder's name when it has none), plus the state mark when a long command finished. Hover shows the last such command's message, or else the folder.
- Each state has its own look (see Session states): *working* tints the card a soft blue, *needs you* amber, *done* sage until you move on from it; an idle card recedes (its mark in gray, its name dimmer) and is shorter: no state line or progress bar, one line of recap, tighter padding. That includes done and failed cards once you move on: clicking one keeps it tall while you read, and it settles to idle when you go to another session or leave Calm. The selected card gets a slightly lighter surface and a hairline ring in the text color (30% of it; stronger with Increase Contrast), the same in every state, and so does a selected shell row. A state is told by color and the selection by the ring, so the two never blur: a lighter sage alone read as "more done", not "selected". The ring sits inside the card's edge, so choosing a card never moves anything.
- The agent mark is the agent's own logo in a small neutral tile (see Agent marks); a letter (C, X, O, π) stands in if a mark can't be drawn.
- **A folded group** keeps one line, and at its right end says what's going on inside in the cards' own state marks, most urgent first: needs you (amber dot), failed (×), done (sage check, 11 pt here), working (blue ring). Up to three sessions in a state get a mark each, 3 pt apart, few enough to see without counting (three rings: three working); four or more get one mark and the number beside it, 12 pt medium in the state's color (○ 4). States sit 9 pt apart. Idle sessions show only when nothing else is going on (• • for two idle shells), and an empty group shows nothing. A session that needs you also tints the whole line amber, as a shell row that needs you is tinted, so folding a group never hides one. The marks are never cut: a long group name gives way and ends in "…". They crossfade when a state changes (0.25 s) and never move. The header's tooltip and VoiceOver say it in words: "3 working, 2 idle".
- Secondary text stays muted; only the name is in the primary text color.

**Right-click a card**, or the **⋯ button** at the right of the title strip (for the session you're in), the same menu: Rename…, Resume <agent> Conversation (after the agent exited), Fork into New Split, Fork into New Tab (where the agent can fork); Copy Session ID, Copy Resume Command, Copy Folder Path, Reveal in Finder (where there is something to give); Move to Project, Let It Follow Its Folder (for a session kept in a project), or Keep as Project… (for a scratch session); Close Session. Rename edits the title in place, in the card's own spot. A copy leaves a quiet note by the pointer ("Path copied"). The ⋯ button is quiet (the tertiary color, 13 pt) until the pointer is on it, then it brightens on a soft tile.

## Links

- **At rest:** a faint dotted line (the terminal's text color at 45%, 1 pt dots) along the bottom of each link that opens. Only links that lead somewhere are marked, so a mark always means a ⌘-click works. Marks fade in over 0.2 s once the text has held still for 0.3 s, and a changed row's marks fade out at once; the rest stay where they are.
- **Holding ⌘:** libghostty underlines the link and shows the pointing hand; its dotted mark steps aside. A tag appears just under the link, left edge by the link's start, in a surface a step lighter than the terminal, 9 pt corners and a soft shadow: an icon (file, image, folder, globe, or a question mark), the name (12.5 pt medium, `:line` included) and, on the right, what a click does (11.5 pt, secondary); under them the folder with `~` for home, or the URL's path (11 pt monospaced, shortened in the middle). At most 440 pt wide. With no room below the link, it sits above.
- **A link a program cut across rows** (an agent's full-screen view breaking a long URL or path where its row ends) looks like any other under ⌘, whole: the pointing hand, the tag on the row under the pointer, and a solid 1 pt underline, in the text's own color, along every row of it (libghostty underlines only the piece of it that it sees). At rest it has the dotted mark on each row, like a link the terminal wrapped.
- **Images:** the tag shows Quick Look's thumbnail above the name, at most 220 × 140 pt; it fades in when ready, and the tag shows without it until then.
- **Not found:** the name dims and the action reads "Not found", so you know before clicking.
- The tag takes no clicks and goes away on typing, clicking or scrolling, or when ⌘ or the pointer leaves the link.
- **Programs that take the mouse:** under ⌘ a link looks and behaves the same (underline, pointing hand, tag), but there are no resting marks, since such a screen is redrawn too often for them to hold still. The tag goes away when the link's text changes under a resting pointer.

## Viewing files

- Opening a viewable file (Markdown, HTML, PDF, images, code) **covers the main area**. The sidebar and files column stay, and the viewer keeps to the main area as they slide in and out.
- The header shows the file name and path, **Open in editor**, and **esc · Back to <session>**.
- Content is centered at a comfortable reading width.
- **Esc** returns to the session exactly as it was. The session keeps running while the file is open; if it needs you, its card tints as usual.
- Going to another session leaves the file, as it leaves Settings, so "Back to <session>" always names the session behind the file.

## Session states

| State | Indicator | Loudness |
|---|---|---|
| idle | a shorter card: the agent's mark in gray at 45%, name dimmed, one line of recap | silent |
| working | soft blue card; the agent's mark moves in its own way; "Working · 4m" in blue, a soft light crossing it every 2.6 s | silent |
| done | sage card with a filled check, until visited (then idle) | silent until visited |
| failed | small mark in the theme's muted red | silent until visited |
| **needs you** | amber card, plus a dot | the only state that may notify |

When the work ends, the mark settles once, in about a second, before it rests.

**Restoring.** After a launch or a Restart the sidebar comes back as it was left: each agent's mark, state and recap, and how long it has been working. Calm checks every saved agent against the running one before the window opens (DESIGNS.md → Launch), so normally there is nothing to see. Only if that takes more than a quarter of a second do the rows hold what was saved, quietly: no tint, the mark gray and still, a soft bar that breathes where the state goes, the recap dimmed, and each card keeping its size so nothing moves. A line, "Restoring sessions…", sits in the gap under the search field, so nothing moves when it goes. When the check ends, every row settles together in one 0.45 s fade: at once if it was quick, but never sooner than 0.45 s after the loading began (so it never flashes), and after 2 s at the latest. The loading state asserts no state, so nothing shown is ever wrong. With Reduce Motion the bars stay still and the fade is a cut.

## Agent marks

Each agent shows its own logo, which moves only while the agent works. The motions follow each agent's own, slowed and softened where Calm poses them; they run at 30 frames a second, and not at all with Reduce Motion.

| Agent | Mark | Working | Finishing up |
|---|---|---|---|
| Claude Code | the spark, in clay | Claude Code's own spinner: a dot opening into the spark and drawing back in without a pause, running forwards and backwards (4 s) | the spinner fades into the resting spark |
| Codex | OpenAI's Blossom, one color | one eased turn, then a short rest (1.6 s + 0.6 s) | slows to a stop |
| OpenCode | its block frame | twelve small squares breathing on their own rhythms, as OpenCode's app spinner does | the squares fade into the mark |
| pi | the pixel π in coral, blue and gold | the pieces drop into place, hold and fall away (3.2 s), after pi.dev's logo | the last piece lands and the π brightens twice, softly |

The marks belong to their owners (see NOTICE) and are shown only to say which agent a session runs.

Rules:

- Never more than one level of emphasis at a time per row.
- No numeric badges, no rings around panes, no reordering rows when states change.
- A session you leave (for another session, or another app) clears *done* and *failed* back to idle; arriving keeps them while you read.

## Notifications

1. **Needs you** in a session the user is not looking at → a macOS notification, held until the user pauses (stops typing for a moment or switches focus).
2. The title is a mark for the state, then the session's name (the one its card shows): ✋ needs you, ✅ done, ⚠️ failed (the last two only when opted in). A notice that isn't a state change (`calm notify`, a plain shell's own notification) has the name alone. There is no subtitle and no project or agent name: Calm's icon says where it comes from, and the name says which session. The mark is an emoji because it's the only way to give a banner color: macOS sets its text in fixed styles.
3. The body is what the agent said, in the same plain words as the card's recap, at most about two lines, cut at a sentence and never in the middle of a word. For *needs you* it's the last question the agent asked; otherwise its first sentences while they fit. No message, or one that only repeats the title, leaves the body out. What someone is asked to allow (a command) is shown exactly as it is, never read as Markdown.
4. Clicking it brings Calm forward and focuses that session.
5. No sound by default.
6. Nothing else notifies unless the user opts in.

```
✋ Fix login
Should I delete the old migration too?
```

## App icon

Calm's mark is a 5 × 5 grid of soft square cells: an open ring of ten, a still center, and the cursor cell just past the ring's end, where the next character goes. There are two versions, and the Finder and the Dock switch between them with the system's appearance:

- **Light:** a warm cream tile, a tan ring, a brown center, and an ember cursor cell with a soft glow.
- **Dark:** Calm dark's tile, a dim warm ring, the accent center, and a pale cursor cell.

The mark is flat: no Liquid Glass.

While Calm runs, the Dock icon shows how the work is going, one state at a time:

| State | When | Icon |
|---|---|---|
| idle | nothing below | the mark, still: the app's own icon, in the user's icon style |
| running | any session is working | the chase: the cursor cell runs around the ring, a lap in 1.5 s. It holds on each place and steps to the next, and the opening travels just ahead of it. A four-cell trail follows the cursor, and the ring steps back to 60%, so the motion reads at Dock size |
| done | a session is done and not yet visited | the ring closes, and the cursor cell turns sage |
| failed | a session failed and not yet visited | the ring loses its warmth to grey, and the cursor cell turns muted red |

- There is one state for the whole app: failed outranks running, which outranks done. *Needs you* has its notification and leaves the icon as it is.
- When work stops, the cursor carries on to its resting place and takes the last step slowly, settling once as agent marks do. Then the icon turns into done or failed in half a second, or rests.
- With Reduce Motion (or `motion` reduced or off), running is shown still: the trail and the dimmed ring, without movement.
- The welcome page draws this same mark with the same view, so it is always the real icon, and gives it two motions of its own, an arrival and a breathing cursor, that never mean *working* (see Welcome page).
- No badges and no bouncing.

## Arrival card

- Appears at the top of the pane when switching into an agent session, only when it adds something: the sidebar is hidden (its card would say the same) and the session had activity since the user left it. ⌘⇧I shows it any time.
- Content: state mark, title · state (with the card's "· 2 shells running" when a done turn left shells) · time since last activity, and one or two lines: what the agent asked while it needs you, otherwise the last thing it said.
- Fades out on the first keystroke or after a few seconds. A shortcut shows it again.
- Never covers the agent's input line.

## Search (⌘K)

- A centered, native-feeling panel with one text field behind a quiet magnifying glass; it hugs a short list of results and shows seven and a half rows before scrolling.
- Results update as the user types; each row has one fixed height and two lines: agent icon, title, then project · time on the right ("3h" within a week, a date like "Apr 14" after); below, one line of snippet that opens a few words before the match, so the highlighted match is always visible.
- ↑/↓ to move, Enter to jump or resume, Esc to close. A quiet footer line says what Enter does for the selected row, so rows never change height: "↵ Open" for a session open in Calm, "↵ Resume in <folder>" otherwise (a new session runs the agent's resume command there), and "↵ New session in <folder> · <agent> deleted this conversation, so it can't be resumed" when the transcript is gone.
- An empty field lists the most recent sessions.
- The current project's sessions rank slightly higher.

## Color

- Soft palettes only in the built-in set: low contrast between text and background (roughly 6:1 to 11:1), low saturation, and bright white only a step above the text. The default, Calm, is neutral and neither black nor white; each other theme is a direction of its own (a hue, a depth), never a tint of another.
- The accent color is used sparingly: a switch that's on, the picked theme and interface size, the welcome page's mark and first card, and the line a viewed file opens at. It never colors a state.
- A project's pixel mark is the one other tint in the sidebar: its own soft hue, pale and small, so it names the project without reading as a state.
- *Needs you*, *working* and *done* keep one color on every theme: amber for *needs you* (whatever the theme's accent), a soft blue for *working*, sage for *done* (until you move on). *Failed* takes the theme's own muted red. Every state also has its own mark and words, so color never carries it alone.
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
| Smooth scrolling | scrolling moves by pixels, not whole rows. Scrollback follows the trackpad; a program that scrolls part of its screen (Claude Code's full-screen view as an answer streams in, `less`, vim), or moves it by redrawing every row (pi's full-screen view), has that part slide into place, each jump easing home in about a quarter second, so steady output reads as one flow, while something it keeps drawn over the scrolling part's edge (Claude Code's "Jump to bottom" hint) stays still and the text under and beside it keeps sliding; a resize or divider drag slides the content instead of stepping it. At rest, a pane whose height isn't a whole number of rows shows part of the scrollback row above its first row instead of an empty strip. Full motion only |
| Smooth cursor | a soft smear follows the cursor when it jumps (not when typing moves it one cell), fading out in about 140 ms. Calm's own shader `cursor_glide.glsl`, loaded through Ghostty's custom-shader support |
| Cursor trail | part of the same shader: the smear's tail catches up with its head, so it reads as a short trail |

**Window**

| Motion | Behavior |
|---|---|
| Splits | new panes grow into place and closed panes fold away |
| Sidebar | when hidden, it peeks in over the terminal as the pointer reaches the window's left edge, and slides away shortly after the pointer leaves it |
| Session switching | hold ⌃ and press Tab to cycle sessions in sidebar order, top to bottom (⌃⇧Tab goes up, both wrap), over small live previews; release ⌃ to settle on the chosen one. While ⌃ is held, ← and → move too, Return settles and esc closes without switching. A quick ⌃Tab goes straight to the next session down without showing anything |
| Session cards | cards slide between projects; state changes cross-fade; the recap updates without jumping. The agent's mark moves while it works and settles once when the work ends (see Agent marks) |
| Restoring | after a launch nothing moves: rows come back as they were left. If the check is slow, rows hold their saved look with a placeholder that breathes (1.9 s) and settle together in one 0.45 s fade (see Session states) |
| Files and viewer | the files column slides in from the sidebar's edge; a viewed file fades up over the session, and esc fades it back |
| Arrival card | fades in on arrival and dissolves when you type |
| Adaptive background | the window's chrome gently follows the background color a full-screen app paints |
| Dock icon | the chase while an agent works, settling once when it stops; done and failed ease in over half a second (see App icon) |
| Welcome page mark | the ring draws itself, the cursor settles, then it breathes for a while and rests; a click runs one lap (see Welcome page) |

**Settings:** Settings → Appearance holds one motion control (full, reduced or off), saved as `motion` in `config.toml`; it dims and says why while the system's Reduce Motion is on. The system's Reduce Motion always wins. Individual effects stay adjustable in the config file.

## Themes

- The picker, in Settings → Appearance, is a row of small previews under a live miniature of the window (sidebar and terminal in the picked theme, layout and background). A solid window fills the page's width; glass sits on a soft desktop that shows through it. The user's Ghostty colors, when their config sets any, are a separate last choice.
- Themes come in light and dark pairs and follow the system appearance.
- Calm's default theme gives way to a theme set in the user's Ghostty config; a theme picked in Calm wins.
- Optional glass background uses the system's material; the terminal can float as a rounded card or run edge to edge.
- The padding around the terminal takes the color of the cells next to it, so an app that paints its own background (OpenCode, Neovim) fills the pane instead of sitting in a frame of the theme's color. The user's Ghostty `window-padding-color` wins. Edge to edge on a solid background, the title strip above the terminal takes the same color, so the two meet without a seam. Only when the app painted the whole pane in it: a lighter band on just the first rows (Claude Code's sticky prompt) doesn't tint the strip, which then takes the pane's own background.

## Settings screen

⌘, turns the whole window into Settings, as the welcome page fills it; ⌘, again or esc goes back to the session exactly as it was (it keeps running underneath). A list of sections takes the sidebar's place, as wide as the sidebar and drawn like its footer, a size up (16 pt rows of 46 pt, each icon on a small tile), so ⌘, reads as the sidebar changing what it lists. The page sits beside it at a reading width (780 pt at most, 34 pt titles, 17 pt labels, 64 pt rows), centered in its pane until it would stand more than 112 pt from the list, so a wide window keeps list and page together, in the theme's own colors: the sidebar's color for the list, the terminal's for the page, the theme's accent for the picked theme and a switch that's on. A chosen segment is a lighter surface, as a selected card is.

```
┌────────────────────────────┬─────────────────────────────────────────────────┐
│ ● ● ●                      │                                                 │
│                            │   Appearance                                    │
│ Settings                   │   ┌ live miniature of the window ───────────┐   │
│ ◐ Appearance               │   └─────────────────────────────────────────┘   │
│ ✦ Agents                   │   Theme                                         │
│ ≡ General                  │   Calm  Ink  Dusk  Forest  Plum │ Your Ghostty  │
│ ⌨ Shortcuts                │   Interface size                                │
│                            │   Default  Large  Larger  Largest               │
│                            │   ┌─────────────────────────────────────────┐   │
│                            │   │ Background              [Solid | Glass] │   │
│                            │   │ Layout            [Edge to edge | Card] │   │
│                            │   │ Motion           [Full | Reduced | Off] │   │
│ ────────────────────────── │   └─────────────────────────────────────────┘   │
│ esc  Back to your sessions │                                                 │
└────────────────────────────┴─────────────────────────────────────────────────┘
```

| Section | Contents |
|---|---|
| **Appearance** | a live miniature of the window, the themes, interface size, glass or solid, edge to edge or card, motion (full, reduced, off) |
| **Agents** | a card per installed agent, two to a row: its mark (moving while one of its sessions works), where it stands in quiet text (✓ Connected), or the one thing it needs as a button (Connect; Set Up… for a step in the agent's own settings, which explains itself in a popover), what it's doing now ("2 sessions · 1 working", or "Not running"), and Connect, or Disconnect under ⋯, where Calm must add a file. Then which states notify, and sound. Calm → Agents… opens this section |
| **General** | editor (automatic, an installed one, or Choose Application… for any app), where paths open, auto-grouping, and the config files (Calm's, Ghostty's with the font it sets, the themes folder) |
| **Shortcuts** | Calm's shortcuts as key caps, read-only; keys are changed in the Ghostty config |

- Going to any session (⌃Tab, ⌘1…9, search, a notification, a new session) leaves Settings.
- Each row starts with its icon on a small tile, as the section list and the sidebar's footer do.
- Quiet by default: no help line under a row unless the control can't do what it shows (Motion while the system's Reduce Motion is on), and none under an agent: a step it needs explains itself in a popover. A hand edit shows after Calm → Reload Configuration.
- The Editor menu ends with **Choose Application…** (the system's file picker, on /Applications); the app chosen stays in the menu, ticked. The row says "Opens the file, not at the line." only for an app that can't take a line.
- A section gets a small warning mark only when something in it is broken: Agents when macOS blocks Calm's notifications (with a button to System Settings), General when a line of config.toml can't be read (shown under the file).
- Settings reopens on the section it was left on. A window too narrow for the list and the page shows the list as icons.

Rules: one line of help text per setting at most; no setting that only shows or hides a button.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘K | Search sessions |
| ⌘P | Command palette |
| ⌘T / ⌘D / ⌘⇧D | New session / split right / split down |
| ⌘⌥← → ↑ ↓ | Split left / right / up / down |
| ⌘⇧N | New scratch session |
| ⌘O | New project |
| ⌘W | Close the session, or Settings, search or a viewed file in front of it |
| ⌘⇧T | Reopen the session closed last |
| ⌘Z | Undo the last edit of the line being typed (sends Ctrl-_) |
| ⌘1…9 | Jump to session by position |
| ⌘⇧[ / ⌘⇧] | Previous / next session in the sidebar |
| ⌃Tab / ⌃⇧Tab | Cycle sessions down / up the sidebar (hold ⌃) |
| ⌘⇧A | Jump to the next session that needs you |
| ⌘⌃S | Show or hide the sidebar |
| ⌘\\ | Toggle the files column |
| esc | Close a viewed file and return to the session |
| ⌘⇧I | Show the arrival card again |
| ⌘, | Settings |

Audited against Ghostty's macOS defaults (M1.10):

- **⌘K** is Ghostty's *clear screen*. Calm takes it for search (M4): Calm's built-in defaults unbind it and move clear screen to **⌘⇧K** (the Edit menu shows it there). Calm's defaults load before the user's Ghostty config, so the user's own keybindings still win.
- **⌘⇧J** is Ghostty's *write screen to file*, so "jump to the next session that needs you" uses **⌘⇧A** (A for attention).
- **⌃Tab** is Ghostty's *next tab* on some platforms and a key a few TUIs read; in Calm it always opens the session switcher, since sessions are Calm's tabs.
- **⌘,** is Ghostty's *open config*, which Calm doesn't support; Calm's defaults unbind it so it opens Settings, the Mac convention.
- **⌘⇧T** is Ghostty's *undo* (of a closed tab or split), which Calm doesn't do. Calm's defaults unbind it and give it to Reopen Closed Session, the browser convention. Left bound, Ghostty would take the key first and send it on to the shell, and the menu would never see it.
- **⌘Z** is Ghostty's *undo* too, which Calm doesn't do, so the key did nothing (macOS encodes no bytes for an unbound ⌘-letter). Calm's defaults bind it to `text:\x1f`, Ctrl-_: the undo of zsh, readline and Claude Code (`chat:undo`), which take back a paste or a ⌘⌫ (zsh: one step per paste or kill, checked on a pty; Claude Code 2.1.284: ⌘Z at an empty input changes nothing and doesn't exit, and it takes back typing in steps that follow its own pauses). Calm holds no undo of its own, since the line belongs to the shell. ⌘⇧Z, Ghostty's redo, stays unused: none of them has a redo. A program that doesn't know Ctrl-_ ignores it, and one that rings the bell on an empty undo sends Calm a bell, which counts only while an agent was working (not checked: zsh at an empty prompt showed no change). Self-tests press it with `calm.cmd_z`, and ⌘⌫ with `calm.cmd_delete`. Not checked: bash 5, fish, Codex, OpenCode, pi.
- **⌘⌥ + arrow** is Ghostty's *move focus to the split in that direction*. Calm's defaults rebind the four keys to *split toward that side* (2026-09-29, the author's call: moving focus by direction isn't worth the best chord, and ⌘[ / ⌘] still move it). The Shell menu lists these four; ⌘D and ⌘⇧D keep working for right and down, unlisted, since a menu item shows one key. Resize stays on ⌘⌃ + arrow. Calm's defaults load before the user's Ghostty config, so a user who has their own `goto_split` lines on ⌘⌥ + arrow (the author did) keeps focus movement there and gets no splits until those lines go. Self-tests press the keys with `calm.cmd_opt_left` (or `right`, `up`, `down`).
- **Restart Calm** (Calm menu) has no shortcut on purpose: it's rare, and next to ⌘Q it would be easy to hit by mistake.
- **⌘\\** toggles the files column. It was ⌘⇧E until the author's own Ghostty config turned out to bind that to *equalize splits*, so the column never opened; nothing in Ghostty's defaults uses backslash. 1Password's autofill is ⌘\\ by default, a global shortcut that takes the key first while 1Password runs; View → Toggle Files still works then.
- ⌘P, ⌘\\, ⌘⇧I, ⌘⇧N, ⌘O are free in Ghostty's defaults (Ghostty's ⌘N, new window, becomes a new session in Calm's one window). ⌘1…9, ⌘[ / ⌘], ⌘⇧[ / ⌘⇧] keep Ghostty's meaning (tab/session by position, previous/next split, previous/next tab).

## Accessibility

- Full keyboard operation.
- VoiceOver labels for every sidebar row and state.
- State is never shown by color alone: each state also has a shape. One exception is the Dock icon's *failed* state. It differs from idle mostly in color (a grey ring, a red cursor cell), and the session's card still marks it by shape.
- Respects Reduce Motion and Increase Contrast.
- **Interface size** (Settings → Appearance), chips under the themes and drawn the same way: each a strip of Calm in the picked theme at that size, its sidebar and cards growing (fewer fit) while the terminal's lines stay put, which is what the setting does. The chosen one is ringed in the accent like the chosen theme; names under them, the percentage as a tooltip. No window chrome or traffic lights: Calm's own picture, not the system's. Default, Large, Larger or Largest (100, 115, 130, 150%) scales every size and length in Calm's chrome at once: the sidebar and its width, cards, the title strip's text (the strip itself stays level with the traffic lights), the files column, search, the palette, the arrival card, the welcome page and Settings. The terminal keeps the Ghostty font's size (⌘+ and ⌘−). A change applies at once; saved as `ui-size` in `config.toml`.
- **Increase Contrast:** the chrome's secondary text, hints, selection and dividers get stronger. A Calm theme's text colors each reach 4.5:1 by moving toward white (dark) or black (light), so dim text stays dimmer than normal text. A theme from the user's Ghostty config is left as it is (Ghostty's `minimum-contrast` is theirs to set).
- A change to Reduce Motion or Increase Contrast in System Settings applies at once, without a relaunch.
- The files column's rows are buttons, so Full Keyboard Access and VoiceOver reach them: a file reads its name and change ("README.md, modified"), a change row adds its folder and lines ("FilesColumn.swift, in Calm/Window, modified, 64 lines added, 31 removed"), a folder says whether it's expanded, and the section titles are headers.
