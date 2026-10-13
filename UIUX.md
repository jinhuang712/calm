# UI and UX

How Calm Terminal looks, moves and behaves. Principles are in [PHILOSOPHY.md](PHILOSOPHY.md). Behavior details are in [FEATURES.md](FEATURES.md).

The design guidelines are restraint, elegance, minimalism, calm (see PHILOSOPHY.md). Every screen is checked against them.

The periphery is the sidebar and the edges of the window. The center is the terminal the user works in. Agent status stays in the periphery. Only a session that needs the user comes to the center.

This file holds the rules. Sizes, colors and durations live in the Swift types named in each section.

## Layout

The window has up to three columns: the sidebar (the periphery, where status lives), the files column and the main area.

```
┌─────────────────────────┬──────────────────┬───────────────────────────┐
│ ⌕ Search sessions   ⌘ K │ calm ⎇ main +52  │ ▦ fix link marks        ⋯ │
│ ▾ ▦ CALM                │ CHANGES 2        │   ~/dev/apps/calm         │
│ ┌─────────────────────┐ │ M UIUX.md   +12  │                           │
│ │ C fix link marks 4m │ │ FILES            │   (the agent's own TUI,   │
│ │   Running swift test│ │ ▾ docs         • │    untouched)             │
│ └─────────────────────┘ │   plan.md      A │                           │
│ ✳ New Claude Code Session ⌘N · ✎ New Session ⌘T · ▢ New Scratch ⌘⇧N   │
└─────────────────────────┴──────────────────┴───────────────────────────┘
  sidebar (periphery)       files (⌘\)         main area: the session, or a viewed file
```

- **Sidebar:** session groups and session cards, in `SidebarView`. A soft **Search sessions ⌘K** field under the traffic lights opens search.
- **Groups:** scratch sessions, then projects (names in uppercase), then folder groups. A folder group shows its name and, under it, the parent folder in tertiary text.
- **Scratch rows** look like other rows and never show a folder. ⌘W or the right-click menu closes one.
- **Project mark:** a 5×5 mirrored pixel pattern made from the project's name, in one of eight soft hues. A click on the mark crossfades to another mark and does not fold the group.
- **Project header:** a click shows the project's home. Only the chevron folds a project. A click on a folder's or scratch's header folds it.
- **Footer:** rows with an icon tile and key caps: New *Agent* Session ⌘N, New Session ⌘T, New Scratch Session ⌘⇧N, New Project… ⌘O, Show Files ⌘\\ (Hide Files while the column is up).
- Under the pointer, the ⌘N row shows a ⌄ that opens the other agents and Choose What ⌘N Starts…. With no agent installed, the row is absent.
- A chevron above the footer's hairline folds the footer away. A thin strip along the bottom edge brings it back.
- **Group header controls** replace the summary under the pointer: the ⌘N agent's mark starts that agent there, **>_** starts a plain shell, **⋯** is Make Project or Remove Project. Scratch has only **+**.
- **Dragging a project's bar** moves the project among the others. A press that does not move is a click. Folder groups and scratch do not drag. With Reduce Motion, the other projects jump aside. See `ProjectReorder`.
- **The update notice** (FEATURES.md → F17): `↑ 0.2.0` at the right end of the strip above the search field, before the dev build's tag. It is quiet text, not amber, because an update never needs the user.
- A click opens a menu: Update and Restart (absent for Homebrew and Debug builds), Release Notes, Copy Update Command, Skip 0.2.0. It goes away when the release is skipped or running. See `UpdateNotice`.
- **No session chosen:** after the session on screen closes, no row is selected and Calm does not pick the next one. The main area follows the sidebar and shows one of two things. See `NoSessionContent`.
- **Waiting on you:** when any session needs a look (needs you, done, failed), large cards show under a **WAITING ON YOU** header. Questions come first, then finished turns, each newest first.
- A card shows the agent's mark (still), name, time, state line, the agent's last message and the folder. At most three cards show, then "2 more waiting" and "5 still working".
- ↑ ↓ move between cards. ↵ opens the card that shows **↵ Open**. A click opens any card.
- **Search and lists:** with nothing waiting, the welcome page's search and lists fill the main area, without the line of ways to start, because the footer has it. That line returns while the footer is folded or the sidebar is hidden.
- When a turn ends while the lists are up, its card comes in, unless the user has typed in the search. When the last waiting card goes, the lists return.
- **Welcome page:** with no session open, a page fills the window, with no sidebar. Calm's mark stands at the top: the app icon in its light or dark version (`WelcomeMark`).
- The mark arrives once: the ring draws itself, the cursor settles and breathes a few times, then rests, so an idle page does not redraw. A click runs one lap of the chase. See `WelcomeMarkMotion`.
- The page never runs the chase by itself, because the chase means *working*. Agent marks on the page stay still. With Reduce Motion, the mark is finished and still.
- Under the mark is a search field with focus at once, then two columns. **Recent sessions** (left) lists sessions with agent mark, title, folder and age.
- **Projects** (right) lists the projects the user made. A last row, **New project…**, opens the folder picker, as ⌘O does.
- No row is filled until the arrow keys move, because a filled first row looks chosen before the user has chosen. Once the user types, the top match is filled and ↵ opens it, as in ⌘K.
- Typing filters both lists. A session shows the matching text under its title. A project matches its name or folder. Headers gain counts. Recent sessions leaves out sessions open in the sidebar.
- ↑ ↓ move through rows. ← → change list. ↵ opens. Esc clears. With only one kind of item, it takes the page. Below 760 pt the lists stack.
- **The way to start:** one line at the bottom, shortcut first: **⌘N *Agent* ⌄ · ⌘T Shell · ⌘⇧N Scratch · ⌘O New project…**. With no agent installed: ⌘T New session replaces the first two.
- **Welcome:** with no project and no past session (including the first launch), the page shows the mark, "Welcome to Calm" (first launch only), "A terminal that keeps you calm while your agents work." and the ways to start as rows. See `WelcomeContent`.
- **Project home:** opening a project (⌘O, a dropped folder, `calm open`, a welcome row) or clicking its header shows it in the main area. The sidebar stays and the title strip is blank.
- It shows the project's pixel mark, name, folder and branch, the start line **⌘N *Agent* ⌄ · ⌘T Shell**, and **EARLIER IN *PROJECT*** with up to six past sessions not open in the sidebar. See `ProjectHomeView`.
- No row is filled at first. ↑ ↓ fill a row and show a ↵ cap. Only then does ↵ open it. Esc leaves the page.
- **Files column:** an optional column for the focused session's project, one surface with the sidebar. The footer's Show Files row and the title strip's readout lead the user to it. See `FilesColumn`.
- Its header shows the project, the branch and the line totals (added in *done*'s sage, removed in *failed*'s muted red). **CHANGES** lists changed files with their lines. **FILES** is the tree.
- **Narrowest window:** the shown panels plus 400 pt for the main area, never wider than the screen. At the default sidebar, 720 pt, so two windows tile on a 13-inch screen. A panel opened in a window too narrow for it widens the window.
- **Corners:** square while the window fills the screen. Otherwise rounded as macOS draws them. Where Calm cannot change them (DESIGNS.md → Window), they stay rounded. See `SquareCorners`.

**Title bar:** there is no visible title bar. A strip at the top stands in for it. The window's hidden title carries the session's name, or "Calm" with no session. A double-click on the strip does what System Settings → Desktop & Dock says.

- **Name and folder:** the group's mark and two lines. Line 1 is the session's name, as its card shows it. Line 2 is the folder (`~` for home). A name that repeats the folder is left out. A scratch session shows no folder.
- **Worktree label:** when the session works in a linked git worktree, its mark and name follow the folder after a "·". A main checkout, a plain folder and a submodule show nothing.
- **Files readout:** `3 changed +58 −6` at the right end, while the project has uncommitted changes and the files column is away. Under the pointer it reads `Show Files ⌘\`. It is absent for a clean project, a non-git folder and Desktop, Documents or Downloads themselves.
- Each item shows whole or not at all. A narrow window drops the readout first, then the worktree label.
- **Update hint** (FEATURES.md → F12): an amber capsule, `↑ Claude Code 2.1.291`, while the agent in front runs an older version than the one installed. It uses amber on purpose, because the hint must be seen. See `AgentUpdateHint`.
- Under the pointer, it names the click: `Restart Claude Code`, or `Restart After This Turn` while the agent works or waits. A waiting restart reads `Restarts after this turn`. A click takes it back.
- An agent that Calm does not restart gets the capsule with no click. Its tooltip says to quit and start the agent again. The title gives way to the hint, never the reverse.

## Session cards

An agent session is a card of up to five lines. Sizes and heights are in `SessionCardLayout`.

| Line | Content | Shown when |
|---|---|---|
| 1 | agent's mark · **session name** · time since last activity (while working, the turn's length) | always |
| 2 | state mark · state. While working, what the agent does now ("Reading SessionCard.swift", "Thinking", "Compacting"; "Working" when hooks say nothing) | not idle |
| 3 | the todo list in words: "3 of 5 · Adding tests". Not a progress bar. A compaction bar replaces it | not idle, and the agent keeps todos |
| 4 | recap: the latest agent message as plain text, two lines at most (one when idle) | always |
| 5 | worktree mark · worktree name | the session runs in a git worktree |

- **Recap:** an idle card shows the agent's own summary when it wrote one after the last message (Claude Code's recap). A done card keeps the message, because it is the news.
- Claude Code's stand-in replies ("API Error: …", "No response requested.") are never the message, except an error that ended the newest turn.
- When the last turn left shells running, a done or idle card adds "2 shells running", because a shell that ends wakes the agent.
- Plain shells are one compact line: the shell's title, plus the state mark when a long command finished.
- *Working* tints the card soft blue, *needs you* amber, *done* sage until the user moves on. An idle card recedes: gray mark, dimmer name, one line of recap.
- **The selected card** has a ring in the text color, the same in every state, and a surface lifted *lighter* than its neighbours in both themes. Color tells the state and the ring tells the selection, so a state's own edge is faint.
- Sessions shown together in a split are lifted too, without the ring. The agent mark is the agent's logo in a neutral tile (a letter stands in when it cannot be drawn).

**Compacting** (Claude Code only): the agent summarizes a full conversation, which takes a minute or two. See `Compaction`.

- The card stays *working* and says "Compacting". A breathing bar replaces the todo line, with the conversation's size ("968k").
- When it ends, the bar drains to the share kept ("968k → 13k"), then fades and the todo line returns, so the card never changes height.
- A `/compact` the user typed ends the turn: the card turns *done* with "Conversation compacted." and keeps the drained bar until the next turn starts. Calm sends no notification for a compaction.

**The live line** (Claude Code only; other agents say "Working"): line 2 says what the agent does, taken from hooks the agent already sends, so nothing polls. See `LiveLine`.

- Each tool call is a step: "Reading SessionCard.swift", "Editing UIUX.md", "Searching the web", a subagent's description. Claude's bookkeeping (todo list, asking the user) leaves the line as it was.
- A command shows as Claude describes it ("Running the full test suite"), else "Running swift test".
- Words hold briefly, so a burst of parallel calls does not flash. Steps of one kind add up ("Reading 3 files"). A prompt starts at "Thinking", and a quiet gap returns to it.

**Card sizes** (Settings → Appearance → Session cards). **Full** is the default.

| Size | Content |
|---|---|
| **Full** | The card in the table above. |
| **Compact** | The title line, then one line with the state and the recap. The todo count ends the line ("2/5"). An idle card is the title line alone, plus one line while its shells run. |
| **Minimal** | The title line alone. The time is in the state's color and there is no state mark. The tooltip says what a working agent does. |

- At the smaller sizes, a card that waits for the user grows a line until the agent works again or the user moves on. The worktree line shows only at Full. A smaller card's tooltip holds what it leaves out.
- With Differentiate Without Color on, Minimal puts the state mark back before the time.
- **Shrink cards to fit** (off by default): the chosen size becomes the largest the cards get. When the sessions do not fit without scrolling, every card steps down a size, and steps up when there is room. See `SessionCardFit`.
- The fit avoids flipping: a step down remembers how short the estimate was, holds for 30 s, and a size drawn too tall is not retried until the sessions or room change. At launch it settles without motion.

**A folded group** keeps one line that shows what goes on inside, in the cards' own state marks, most urgent first: needs you (amber dot), failed (×), done (sage check), working (blue ring). See `GroupSummary`.

- Up to three sessions in a state get one mark each. Four or more get one mark and the number. Idle sessions show only when nothing else goes on.
- A session that needs the user also tints the whole line amber, so folding never hides one. Going to a session in a folded group unfolds it.

**The session menu.** Right-click a card or shell row (or ⌃-click), or click the **⋯ button** in the title strip. All three open the same menu, drawn by Calm in the theme's colors (`SessionMenuView`).

- At the top: the agent's mark, name and running version, then up to three action tiles: **Restart** (now, after the turn, or "↑ 2.1.291" in amber when a newer version is installed), **Don't Restart**, **Restarting…**, **Resume** (after the agent exits) and **Fork** (new split, new tab).
- Rows, in groups: Rename…; under **COPY**, Session ID, Resume Command and Folder Path; Open in Finder, Move to Project ›, Let It Follow Its Folder or Keep as Project…; Close Session (with ⌘W where it closes this session).
- A plain shell has no name and no tiles. ↑ ↓ move, ← → move along the tiles and open or close Move to Project's list, a letter jumps, ↵ chooses, Esc closes. Its keys never reach the terminal.

## Links

- **At rest:** a faint dotted line runs under each link that opens, so a mark always means a ⌘-click works. Marks fade in once the text holds still (`LinkMarksView`).
- **Holding ⌘:** libghostty underlines the link and shows the pointing hand. A tag appears under the link with an icon, the name, what a click does and the folder or URL path (`LinkTag`). It takes no clicks.
- A link a program cut across rows looks whole under ⌘: one tag and a solid underline on every row.
- **Images:** the tag shows Quick Look's thumbnail. An agent's pasted image (`[Image #4]`) shows large. A missing file dims the name and reads "Not found".
- **Programs that take the mouse:** under ⌘ a link behaves the same, but there are no resting marks, because such a screen redraws too often.
- **Table cells, holding ⌥** (Copy Cell): the cell under the pointer gets a dotted outline. An ⌥-click copies it ("Cell copied"). An ⌥-drag selects text inside the cell ("Copied").

## Viewing files

- **Cover:** opening a viewable file (Markdown, HTML, PDF, images, code) covers the main area on the terminal's own background. The sidebar and files column stay. Esc returns to the session as it was.
- **The title strip stays the session's.** Its name dims and becomes the way back. ⋯ and the update hint stay. The files readout steps away.
- **The file's row** (`ViewerHeader`): back button, name, folder. At the right: a picture's or PDF's kind, or a changed file's `+3 −3` and the **File | Unified | Split** switch. Then the size, then **Open in Editor** (**Open in Preview** for pictures and PDFs).
- A new file says **New** and has no switch. Code has no line numbers. A changed line has a bar left of its text (sage added, the accent modified).
- **Unified diff:** removed lines on muted red, added on sage, changed words stronger, hunk headers, and unchanged stretches as one row ("⋯ 6 unchanged lines"). **Split diff:** side by side under "LAST COMMIT" and "NOW". Markdown diffs show the source.
- **Size (⌘+, ⌘−, ⌘0):** while not at 100%, the row says the size (`125%`). Under the pointer, **−** and **+** appear. A click on the number resets it. The viewer's own parts keep their size (`ViewerZoom`).
- The session keeps running under the file. Going to another session leaves the file, as it leaves Settings, so the strip always names the session behind the file.

## Session states

| State | Indicator | Loudness |
|---|---|---|
| idle | a shorter card: gray mark, dimmed name, one line of recap | silent |
| working | soft blue card; the agent's mark moves; what it does in blue | silent |
| done | sage card with a filled check, until visited (then idle) | silent until visited |
| failed | small mark in the theme's muted red | silent until visited |
| **needs you** | amber card, plus a dot | the only state that may notify |

- There are no numeric badges, no rings around panes, and no reordering of rows when states change.
- A session the user leaves (for another session or another app) clears *done* and *failed* to idle. Arriving keeps them while the user reads.

**Restoring.** After a launch or a Restart, the sidebar comes back as it was left. Calm checks every saved agent first (DESIGNS.md → Launch), so normally there is nothing to see.

- When the check takes longer than a quarter second, rows hold what was saved, quietly: no tint, a still gray mark, a breathing bar, and "Restoring sessions…" under the search field. Then every row settles together in one fade (a cut with Reduce Motion).

## Agent marks

Each agent shows its own logo. The logo moves only while the agent works, in the agent's own way, slowed and softened. See `AgentMarkArt`, `MarkMotion` and `AgentLogo`.

| Agent | Mark | Working |
|---|---|---|
| Claude Code | the spark, in clay | Claude Code's own spinner, running forwards and backwards |
| Codex | OpenAI's Blossom, one color | one eased turn, then a short rest |
| OpenCode | its block frame | twelve small squares breathing on their own rhythms |
| pi | the pixel π in coral, blue and gold | the pieces drop into place, hold and fall away |

- Marks do not move with Reduce Motion, or while nobody can see the window. Calm in the background with its window in view keeps them moving, because a still mark would read as a stuck agent.

## Notifications

- **Needs you** in a session the user is not looking at sends a macOS notification. Calm holds it until the user pauses. A click brings Calm forward and focuses that session.
- The title is a mark for the state, then the session's name: ✋ needs you, ✅ done, ⚠️ failed (the last two only when the user opts in). A notice that is not a state change has the name alone.
- There is no subtitle: Calm's icon says the source and the name says the session. The mark is an emoji, because it is the only way to give a banner color.
- The body is what the agent said, in the card's plain words, cut at a sentence. For *needs you*, it is the last question. A command to allow shows exactly as it is. With no message, or one that repeats the title, the body is left out.
- No sound by default. Nothing else notifies unless the user opts in. See `NotificationText`.

## App icon

Calm's mark is a 5 × 5 grid of soft square cells: an open ring of ten, a still center, and the cursor cell just past the ring's end. Light is warm cream with a tan ring. Dark uses Calm dark's tile with the accent center. The mark is flat: no Liquid Glass.

While Calm runs, the Dock icon shows one state for the whole app. Failed outranks running, which outranks done. *Needs you* has its notification and leaves the icon as it is. See `AppIcon` and `DockIcon`.

| State | When | Icon |
|---|---|---|
| idle | nothing below | the mark, still |
| running | any session is working | the chase: the cursor cell runs around the ring, with a short trail |
| done | a session is done, not yet visited | the ring closes, and the cursor cell turns sage |
| failed | a session failed, not yet visited | the ring turns grey, and the cursor cell turns muted red |

- When work stops, the cursor takes the last step slowly, then the icon turns into done or failed, or rests. With Reduce Motion, running is shown still.
- The welcome page draws the same mark with the same view. No badges and no bouncing.

### The dev build

The Debug build ("Calm Dev": what `mise run run` and the self-tests launch) differs from the installed one so the user never takes one for the other. Themes, states, layout and motion are the shipped ones. See `BuildVariant`.

- **Icon:** the same mark on a cool lavender tile, with violet where the shipped icon is warm. No state uses violet.
- **Name:** "Calm Dev" in the menu bar, Dock, notifications, About panel, the Calm menu and the window's title with no session. A **DEV tag** in violet sits at the right end of the strip above the search field (`DevTag`).
- **Bundle id:** `com.jinhuang.calm.dev` (the installed Calm's is `com.jinhuang.calm`). So the Dock pin, `UserDefaults`, notification settings and privacy grants are separate.
- **State and socket:** they are not separate. A Debug build run by hand uses the installed Calm's state folder and control socket (`~/Library/Application Support/Calm`). If that socket answers, the Debug Calm quits at once (`SingleInstance`), so the two cannot run together.
- Self-tests set `CALM_STATE_FILE`, `CALM_SUPPORT_DIR` and `CALM_SOCKET` to their own paths, so they run beside the installed Calm (AGENTS.md, DESIGNS.md → Testing).

## Arrival card

- It appears at the top of the pane when the user switches into an agent session, only when it adds something: the sidebar is hidden and the session had activity since the user left. ⌘⇧I shows it at any time.
- It shows the state, title, time and one or two lines: the question while the agent needs the user, else the agent's summary, else the card's recap. It fades on the first keystroke and never covers the agent's input line.

## Search (⌘K)

A centered panel on a surface a step off the terminal's background, in the chrome's colors. Sizes grow with the interface size. See `SearchPanel`.

- **Groups:** a header per group, drawn like the sidebar's and pinned while its rows scroll. It shows counts that are not zero: open and active sessions, open and idle sessions, and past sessions. See `SearchGroups`.
- **Rows:** the agent's mark, the title and how long ago, written out ("just now", "4 minutes ago", "Sep 16"), or the state's mark for a session open in Calm (`WrittenTime`). A deleted transcript adds "· can't be resumed".
- While searching, lines under the title show the typed words with context, marked with a wash of the accent (`SearchLines`). The selected row shows a ↵ key. Its tooltip says what ↵ does.
- A group's last row, "13 more in calm", shows five more on ↵ or a click. Then "Show less ⌃" folds the group back. The list ends on a whole row, never half a row.
- **Keys:** ↑ ↓ move through rows. ⇥ and ⇧⇥ jump between groups. ↵ acts. Esc closes.
- **Nothing typed:** a switcher of sessions to pick back up: four of the user's group and two of each other group, eleven at most. **Nothing found:** "No session mentions that".

## Find (⌘F)

See FEATURES.md → F16. The look is Calm's own, drawn over the terminal as a flat fill. The pill is the engine's own cell fill, so its ends are square and flush with the letters. Colors come from `FindColors`.

- **The field** stands in the title strip where the files readout was, in the look of the sidebar's search field, with the count and a **⌘F** cap that closes it (`FindField`). When the strip is short of room, the field narrows first, and the count never goes.
- **`.*`:** the field's one switch. On, the typed words turn monospaced. A half-typed pattern reads "Incomplete pattern". Help text: "Regular expression (⌥⌘R)". A PDF or web page has no switch.
- **Screen | Session:** while a full-screen program is in front, a two-way switch follows `.*`. The session page shows what the session showed, like a viewed file, with its own header and no Open button. Esc or Screen goes back.
- When nothing on screen matches, a note offers **Search all of it ⌘K** (for an agent: "Claude Code keeps the conversation, not the terminal."). The count reads "2 of 3 on screen" or "None on screen".
- **Every match** has a solid rounded accent underline. **The current match** is a pill with the text in the background color, a band across its line and an accent bar at the pane's edge.
- **The map:** a thin track along the pane's right edge with a tick per matching line, a longer tick for the current match and a box for the part on screen (`FindMap`, `FindMapView`).
- **With links:** a match's underline replaces the link's dots. ⌘ over a link shows the link's own underline and tag until ⌘ is let go.
- **A viewed file:** the same field in the file's row. Code gets the band. Rendered Markdown does not, because its lines reflow. A picture shows "Nothing to find in a picture".
- **Colors:** every theme must pass these checks: pill text at 4.5:1, underline, bar and ticks at 3:1, and a band distinct from the background and from a selection. Calm's amber is not used, because it means *needs you*.

## Command palette (⌘P)

- **Panel:** centered, on a regular material, with a field ("Run a command") and a list. Rows show the name, and the key that already does it for the keys only Calm has.
- Only the selected row says in one short sentence what it does ("Start a copy of this conversation in a new split beside it."). Every row has one, in `PaletteRow`, and typing a word of it finds the row.
- The palette holds what has no key everyone knows (FEATURES.md → Command palette). Rows are grouped by category with no headers. Every row is one-shot: none opens a second list.

## Split panes

With more than one pane on screen, the pane the user is in and the pane that ⌘W would close must be plain to see. Calm does not use a border or a name for this. The panes themselves say it.

- **The pane the user is in is the bright one.** The others recede under a veil of the terminal's own background. It follows the layout's focused session, not the keyboard focus. A lone pane is never dimmed. See `PaneDim`.
- **⌘W on a pane with something running** puts a question in the middle of that pane, with no box: the program's mark, "Claude Code is running here", "Closing the session ends it.", and **Keep** and **Close** with their keys.
- Return closes. Esc keeps. Any other key keeps and goes through. ⌘W again takes the question back. Focus arriving at another pane ends it. An unsplit session keeps the window sheet "Close this session?". See `ClosePrompt`.
- **A pane at a plain prompt closes at once**, with no question.
- **The split icon** sits in each pane's top right corner in a split. Its line follows the split. At rest, only the pane the user is in shows it. Any pane shows it under the pointer, with its menu open, or while dragged. See `SplitHandle`.
- **The icon's menu:** **Take Out of Split**, **Unsplit All** (left out with two panes), **Zoom Pane** (⌘⇧↵), **Equalize Splits** (⌘⌃=). It has no Split Right or Down, because ⌘D, ⌘⌥ + arrow and the Shell menu make splits.
- **Taking a pane out ends nothing.** The session is a session of its own in the sidebar again, and the other panes close up. Dragging the icon onto the sidebar does the same.
- **Bringing a session into a split:** the user drags a session's card from the sidebar onto a pane, or drags a pane by its icon. A dotted outline shows the half the new pane would take, the side nearest the pointer. Over the pane's middle, a drop does nothing. See `SplitTree+Drop`.
- Files and text dropped on a pane are pasted as a path or text. A dragged session has its own type (`com.jinhuang.calm.session`), which only the sidebar and the panes take.
- **The sidebar lights the split:** every session shown together is lifted, and the session the user is in keeps the ring. A closed pane folds away toward the edge it shared with its neighbour.

## Color

- **Palette:** soft palettes only: low contrast between text and background, low saturation, bright white only a step above the text. The default, Calm, is neutral, neither black nor white. Each other theme is a direction of its own. See `Theme`.
- **Accent:** used sparingly: a switch that is on, the picked theme and interface size, the welcome page's mark and the line a viewed file opens at. The accent never colors a state.
- **State colors:** *needs you* is amber, *working* soft blue and *done* sage on every theme. *Failed* takes the theme's own muted red. Every state also has its own mark and words, so color never carries a state alone.
- **Project mark:** the one other tint in the sidebar. Red appears only for *failed* and real errors. Chrome takes its colors from the theme, never from a fixed system tint.

## Typography

- The terminal uses the user's Ghostty font. Chrome uses the system font (SF Pro) at small, regular weights. Titles are medium, never bold.

## Motion

Motion is on by default, soft and never showy. Settings → Appearance holds one control (full, reduced or off), saved as `motion` in `config.toml`. The system's Reduce Motion always wins. See `Motion`.

- A panel that changes the terminal's size resizes it once, and only the picture glides, because a resize per frame would make an agent's screen flicker.

| Motion | Behavior |
|---|---|
| Smooth scrolling | scrolling moves by pixels, not rows. A program that scrolls or redraws part of its screen (Claude Code's full-screen view, `less`, vim, pi, OpenCode) has that part slide into place. Full motion only |
| Smooth cursor and trail | a soft smear follows the cursor when it jumps. It is Calm's own shader `cursor_glide.glsl`, loaded through Ghostty's custom-shader support |
| Splits | new panes grow into place. A closed or taken-out pane folds away. The dim, the split icons and the dotted landing fade |
| Sidebar | when hidden, it peeks in as the pointer reaches the window's left edge and slides away after it leaves (`SidebarPeek`) |
| Session switching | hold ⌃ and press Tab to cycle sessions in sidebar order over small live previews (⌃⇧Tab goes up). Release ⌃ to settle. A quick ⌃Tab goes straight to the next session (`SessionSwitcher`) |
| Session cards | cards slide between projects. State changes cross-fade. A new card size eases every card to its height |
| Files and viewer | the files column slides in. A viewed file fades up over the session, and esc fades it back |
| Arrival card, adaptive background | the card fades in and dissolves on typing. The chrome follows the background color a full-screen app paints |

## Themes

- **Picker:** in Settings → Appearance, small previews under a live miniature of the window. The user's Ghostty colors, when their config sets any, are a separate last choice (`ThemePicker`).
- Themes come in light and dark pairs and follow the system appearance. A theme in the user's Ghostty config wins over Calm's default theme. A theme picked in Calm wins over both.
- **OpenCode** and **pi** wear the theme too. A connected OpenCode uses Calm's `calm` theme and follows changes live, unless its own config names a theme. A connected pi does the same over pi's built-in themes only.
- **Glass:** an optional background using the system's material. The terminal can float as a rounded card or run edge to edge (`WindowStyle`).
- **Padding:** the padding takes the color of the cells next to it, so an app that paints its own background (OpenCode, Neovim) fills the pane. The user's Ghostty `window-padding-color` wins.
- Edge to edge on a solid background, the title strip takes the same color when the app painted its pane in it out to the sides, so the two meet without a seam (`SurfaceEdgeColor`).

## Settings screen

⌘, turns the whole window into Settings. ⌘, again or esc goes back to the session as it was. A list of sections takes the sidebar's place and the page sits beside it at a reading width.

| Section | Contents |
|---|---|
| **Appearance** | a live miniature of the window, themes, interface size, session cards (and Shrink cards to fit), glass or solid, edge to edge or card, motion |
| **Agents** | one group, then Keys, then which states notify, and sound. Calm → Agents… opens this section |
| **General** | editor (automatic, an installed one, or Choose Application…), where paths open, auto-grouping, update checks, and the config files |
| **Shortcuts** | Calm's shortcuts as key caps, read-only. The user changes keys in the Ghostty config |

**Agents section:**

- **⌘N starts** (⌘⇧N too, in a scratch folder), with a menu of the agents installed.
- **A row per agent:** its mark, its name and a chip per option it starts with. On is a soft accent fill with a check. Off is a quiet outline. Pointing at a chip names the flag.
- The right side of a row holds only what needs a hand: Connect, Left alone (why, under the pointer), Set Up… or ••• for Disconnect. Connected is the normal state and is not written.
- **Keys:** one row, "Send prompts with" a switch with ⌘ ↩ drawn as two soft keys. The keys label the switch, because choices drawn from keys read as a legend, not as a control. A line under the title says when an agent needs a step.

**Settings rules:**

- Going to any session leaves Settings. Each row starts with its icon on a small tile.
- A row has no help line unless the control cannot do what it shows or its name cannot say what it does. One help line per setting at most. No setting that only shows or hides a button.
- A section shows a small warning mark only when something in it is broken: Agents when macOS blocks notifications, General when a line of `config.toml` cannot be read.
- Settings reopens on the section it was left on. A window too narrow for the list and the page shows the list as icons. A hand edit shows after Calm → Reload Configuration.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘K | Search sessions |
| ⌘F / ⌘G / ⌘⇧G / ⌘E | Find; the older / newer match; find the selected text |
| ⌘P | Command palette |
| ⌘N / ⌘⇧N | New session / new scratch session, running the agent chosen in Settings → Agents |
| ⌘T / ⌘D / ⌘⇧D | New session / split right / split down |
| ⌘⌥← → ↑ ↓ | Split left / right / up / down |
| ⌘O | New project |
| ⌘W | Close the session, or Settings, search or a viewed file in front of it |
| ⌘⇧T | Reopen the session closed last |
| ⌘Z | Undo the last edit of the line being typed (sends Ctrl-_) |
| ⌘↵ | Return; with Send with ⌘ Return on, send an agent's prompt |
| ⌘1…9, ⌘⇧[ / ⌘⇧] | Jump to session by position; previous / next session |
| ⌃Tab / ⌃⇧Tab | Cycle sessions down / up the sidebar (hold ⌃) |
| ⌘⇧A | Jump to the next session that needs you |
| ⌘⌃S / ⌘\\ | Show or hide the sidebar / the files column |
| esc, ⌘⇧I, ⌘, | Return from a viewed file; show the arrival card; Settings |

Calm's shortcuts follow Ghostty's macOS defaults, with these changes. Calm's defaults load before the user's Ghostty config, so the user's own keybindings still win.

- **⌘K** (Ghostty: clear screen) opens search. Clear screen moves to **⌘⇧K**. **⌘⇧J** (write screen to file) is not used, so "next session that needs you" is **⌘⇧A**.
- **⌃Tab** always opens the session switcher, because sessions are Calm's tabs. **⌘,** (open config) opens Settings. **⌘N** (new window) starts an agent session, because Calm has one window.
- **⌘⇧T** (undo close) is Reopen Closed Session. If it stayed bound, Ghostty would take it first and the menu would never see it.
- **⌘Z** (undo) sends Ctrl-_, the undo of zsh, readline and Claude Code, because macOS encodes no bytes for an unbound ⌘-letter. Calm keeps no undo of its own, because the line belongs to the shell.
- **⌘↵** (toggle full screen) types Return. ⌃⌘F and the green button remain. With Send with ⌘ Return on, programs get ⌘+Return (`ESC[13;9u` under the kitty keyboard protocol, `ESC[27;9;13~` without).
- **⌘⌥ + arrow** (move focus) splits toward that side. ⌘[ and ⌘] still move focus. ⌘D and ⌘⇧D keep working, unlisted in the Shell menu. A user with their own `goto_split` lines on those keys gets no splits until the lines go.
- **⌘\\** toggles the files column. 1Password's autofill takes ⌘\\ first while it runs. View → Toggle Files still works then.
- **Check for Updates…** and **Restart Calm** (Calm menu) have no shortcut. Updates are checked once a day, and next to ⌘Q a Restart would be easy to hit by mistake (FEATURES.md → F17).

## Accessibility

- Full keyboard operation. VoiceOver labels exist for every sidebar row and state. Calm has not been checked with VoiceOver running, and no check is planned.
- **State is never shown by color alone:** each state also has a shape. Two exceptions: the Dock icon's *failed* state differs from idle mostly in color, and **Minimal** cards drop the state mark. Their tint, time color and tooltip carry the state.
- Calm follows Reduce Motion, Increase Contrast and Differentiate Without Color, and applies a change at once (`AccessibilitySettings`).
- **Interface size** (Settings → Appearance): Default, Large, Larger or Largest (100, 115, 130, 150%) scales every size in Calm's chrome. The terminal keeps the Ghostty font's size. Saved as `ui-size` in `config.toml` (`InterfaceScale`).
- **Increase Contrast:** secondary text, hints, selection and dividers get stronger. A Calm theme's text colors each reach 4.5:1. A theme from the user's Ghostty config is left as it is.
- **Files column:** rows are buttons that read name and change ("README.md, modified"). A folder says whether it is expanded. The title strip's readout is a button that reads "3 files changed, 58 lines added, 6 removed".
