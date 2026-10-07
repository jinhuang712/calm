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
│ ✳ New Claude Code Session ⌘N │
│ ✎ New Session            ⌘ T │                        │                                │
│ ▢ New Scratch Session  ⌘ ⇧ N │                        │                                │
│ + New Project…           ⌘ O │                        │                                │
│ ▭ Hide Files             ⌘ \ │                        │                                │
└──────────────────────────────┴────────────────────────┴────────────────────────────────┘
   sidebar (periphery)          files (⌘\, optional)     main area (center): the session,
                                                         or a viewed file (esc returns)
```

- **Sidebar:** session groups and session cards. The periphery, where status lives. At the top, under the traffic lights, a soft filled **Search sessions ⌘ K** field opens search. Then scratch sessions, projects you made (uppercase, each with its own pixel mark: a 5×5 pattern, mirrored like GitHub's identicons, made from the project's name, so the same name always gets the same mark; in one of eight soft, low-saturation hues on a pale 20 pt tile of it; clicking it crossfades to another, and never collapses the group), and folder groups (the folder's own name, and under it in 11 pt tertiary text where the folder is: its parent with the home folder as `~`, cut from the front when long, so the nearest folders stay; the line stays when the group is collapsed or hovered, so the header never changes height, and the home folder's own group has none). Scratch rows look like any other row, with no close button of their own (⌘W or the right-click menu closes one); a scratch session's folder never shows anywhere. Hovering a group header swaps its summary for two quiet controls: **+** (a new session there) and **⋯** (Make Project for a folder, Remove Project for a project; scratch has only +). Right-click offers the same. The footer is five rows, each with its icon on a small tile and its shortcut as key caps: **New *Agent* Session ⌘N** (the agent's own mark on the tile and its full name; under the pointer the key caps fade and a quiet ⌄ takes their place, opening the other agents and Choose What ⌘N Starts…; with no agent installed the row isn't there), New Session ⌘T, New Scratch Session ⌘⇧N, New Project… ⌘O and **Show Files ⌘\\** (a folder on the tile; **Hide Files**, with its tile and words lit, while the files column is up, the way the selected card stays lifted); each row lights up on hover. The last row is what tells a new user the files column exists. With the pointer over the footer, a quiet chevron (10 pt, tertiary, lighter under the pointer) fades in centered in a 16 pt strip just above the footer's hairline; clicking it folds the footer away, and the list takes its room. The strip is there either way, so nothing moves when the chevron shows. A folded footer leaves a 22 pt strip along the bottom edge that shows an up chevron under the pointer and brings the rows back. Sizes lean roomy (a 320 pt sidebar, 14 pt text, 40 pt rows, 26 pt agent marks in each agent's own soft tint) so the sidebar reads at a glance without leaning in.
- **No session chosen:** after the session on screen is closed, the sidebar stays, the title strip is blank and no row is selected: Calm doesn't pick the next session. The main area shows one of two things, and follows the sidebar as it changes:
  - **Waiting on you:** when any session waits for a look (needs you, done or failed), those sessions, under a small **WAITING ON YOU** header drawn like the lists' headers, as cards a size up from the sidebar's (600 pt wide at most, 14 pt corners, 22 pt inside, the state's own tint and faint edge): the agent's mark (still: its motion means *working*), the name in 17 pt and the time; the state line; everything the agent last said, in 14.5 pt (the sidebar card keeps two lines of it); the folder (never a scratch session's). Questions come first, then finished turns, each newest first; three at most, and under them in 13 pt tertiary "2 more waiting" and "5 still working" when there are. The keys go to the cards: ↑ ↓ move, ↵ opens the one that shows **↵ Open**; a click opens any, and the pointer brightens its tint. The block sits a little above center; a tall one scrolls.
  - **Search and lists:** with nothing waiting, the welcome page's search and lists (Recent sessions and Projects, same rows, keys and sizes) fill the main area, with the mark a size down (48 pt) and without the line of ways to start, which the sidebar's footer already has; while the footer is folded away, or the sidebar hidden, that line is back at the page's foot, as on the welcome page. Recent sessions leaves out the ones open in the sidebar, which already shows them, so it lists what you could pick back up; a search still finds open ones too, as ⌘K does. When every recent session is open, the list says so ("Your recent sessions are all open"). The field takes the keyboard as on the welcome page, and ⌘K puts the caret in it. With nothing to list yet, the mark alone.
  - A turn that ends while the lists are up brings its card in, unless you've typed in the search: then the lists stay until you leave, so the page never changes under your keys. The last waiting card going (answered elsewhere) brings the lists. The two crossfade (0.2 s; at once with Reduce Motion).
- **Welcome page:** with no session open, a page fills the whole window (no sidebar; only the traffic lights above it). **Calm's mark** stands at the top, always: the app icon, in its light or dark version with the theme (60 pt on the search page, 76 pt on the welcome, 48 pt in a small window). It arrives once: its ring draws itself in typing order, the center follows, and the cursor appears on the ring's last cell and takes the last step to its resting place slowly, settling once, as it does when an agent stops working. Then it waits, the cursor breathing slowly (down to 42% and back every 3.6 s) for eight breaths, and rests still, so an idle page doesn't keep redrawing; a click runs one lap of the chase, a small easter egg like the project marks'. With Reduce Motion (or `motion` reduced or off) it is the finished mark, still. The chase is the Dock icon's word for *working*, so the page never runs it by itself, and the agent marks on the page stay still for the same reason.
  - **Search and lists:** under the mark, a search field like the sidebar's, larger (46 pt, 14 pt corners), focused at once, with ⌘K on its right (a clear button once something is typed). Then two columns, 880 pt wide at most: **Recent sessions** on the left, six rows (three in a small window) of an agent mark, the session's title and under it its folder and how long ago; **Projects** on the right, the projects you made, each with its pixel mark (30 pt), name and folder, and under them a last row, **New project…**, drawn like the sidebar footer's row of that name at the list's size (a plus on a 30 pt tile in the mark's place, the label, ⌘ O as key caps): the arrows reach it and ↵ opens the folder picker, as ⌘O does. It stays below the list when the list scrolls, and while searching, after the matches (or "No projects match"). Rows are 54 pt tall (⌘K's were, before it grouped its results), and the one the arrow keys are on is filled, with a ↵ cap. A list taller than its room scrolls, fading out over its last row's height; moving with the arrows keeps a row of room past the one they're on, so it never sits under the fade. Typing filters both. A session shows, as in ⌘K, the matching text under its title with the words marked; a project matches its name or its folder as shown, with the words marked (bold, and underlined in the name); each header gains a count ("30+" when the search stops at its limit), and a list with no match says so. ↑ ↓ move through the rows; ← → change list (inside the field, only at the text's edge or once the arrows have been used); ↵ opens; Esc clears. With no past sessions the projects take the page alone, the field reading "Search projects"; with no projects the sessions do. A window narrower than 760 pt stacks them, sessions first, in one scrolling list. There is no heading on this page: the mark and the field say what it is.
  - **The way to start:** at the bottom, one line, shortcut first: **⌘N *Agent* ⌄ · ⌘T Shell · ⌘⇧N Scratch · ⌘O New project…** (with no agent installed: ⌘T New session · ⌘⇧N Scratch · ⌘O New project…). The ⌄ sits inside ⌘N's fill and opens the other agents. Each is a button with a faint fill of its own (5.5%, 11% under the pointer), 13.5 pt, the shortcut a step brighter than the words: no icons, no key caps and no border, so it reads as something to press without the weight of a toolbar.
  - **Welcome:** with no project made, the very first launch, and any time there is no past session either, the page is a welcome instead: the mark at 76 pt, "Welcome to Calm" (first launch only) with "A terminal that keeps you calm while your agents work.", and the ways to start as rows in the lists' own style (an icon on a small tile, the label, the shortcut as plain glyphs): Start *Agent* ⌘N, drawn as the selected row, with the agent's mark and a ⌄ at its end; Start a shell ⌘T; Try a scratch session ⌘⇧N; Open a project ⌘O. With no agent installed, Start a session ⌘T is the selected row instead of the first two. Making a project brings the lists back.
- **Files:** an optional column right of the sidebar, showing the focused session's project. The footer's Show Files row and the title strip's readout (see Title bar) are how it is found. One surface with the sidebar (a hairline between them, like the footer's), 272 pt wide, and level with it: the header sits on the search field's line (the project in 13.5 pt medium, the branch as plain text after it, the git mark and the name in 12 pt tertiary, drawn like the worktree in the title strip and on the session card, with no box, the line totals at the right in monospaced digits, added in *done*'s sage, removed in *failed*'s muted red), and the first section header on the sidebar's first group header's line. Section headers (**CHANGES** with its count, **FILES**) are drawn like project names: small capitals, tracked, tertiary. Change rows are 30 pt: the letter on a small tile, the name in the primary color, the nearest folder in tertiary, the lines at the right. Tree rows are 26 pt with 13.5 pt names: thin chevrons in a fixed 16 pt gutter so names line up at each depth, 16 pt more per level; names in the secondary color, changed files in the primary, dotfiles in tertiary. The viewed file gets the sidebar's selection; a row under the pointer gets half of it. Nothing is ever cut down to fragments: the branch and a change's folder show whole or not at all, and names lose their middle.
- **Main area:** the session's terminal. Calm never draws over it, except the arrival card, which fades, and the quiet marks and tag of links (see Links). A viewed file temporarily takes its place.
- **Narrowest window:** the sidebar and the files column as they are (each counts only while shown), plus 400 pt for the main area, all at the interface size, never more than the screen is wide; 320 pt tall. With the sidebar at the default size that is 720 pt, half of a 13-inch MacBook Air's screen, so two windows still tile side by side; hidden, 400 pt. Opening the sidebar or the files column in a window too narrow for it widens the window as the panel slides in, moving it left if it would leave the screen; so does a larger interface size. Before 2026-10-06 the narrowest was a fixed 560 pt, and at the Largest size the sidebar alone took 480 of it.

**Title bar:** there's no visible title bar; the strip at the top of the window (over the sidebar and above the terminal) stands in for it. It's 48 pt tall, a header row of its own below the traffic lights' line; the sidebar leaves the same room above its search field, so the two start level. Dragging it moves the window, and double-clicking it does what System Settings → Desktop & Dock says (Zoom by default, or Fill, Minimize, nothing); a window left filled comes back filled, and the next double-click still gives back its earlier size. At the left of the strip above the terminal, centered in it, are the session's group mark (a project's pixel tile, or the folder or scratch glyph, as in the sidebar; 24 pt here against the sidebar's 20, to go with the larger name, and not clickable here, so the text starts in the same place for every session) and two lines, like a window's title and subtitle: the focused session's name, the same one its card shows, 15 pt medium in the primary color, and under it, 12 pt in the tertiary color, the folder it's in ("~" for home). A name that only repeats the folder (a plain shell titled "calm" or "…/apps/calm") is left out, and the folder takes the name's line and style; a scratch session shows no folder. A long name ends in "…"; a long folder loses its front. When the session's work is in a linked git worktree, its name follows the folder on the same line, after a "·": the worktree mark and the name, in the folder's 12 pt tertiary, the look of the worktree line on the session card. No box: the strip has no shape but the group's mark. It shows whole or not at all, and only when the name and folder already fit whole: the title never gives up room for it (it does survive a long title, since it sits in the room under the name). A plain shell has no folder line, because its folder is the name, so the worktree takes the second line alone. A main checkout, a plain folder and a submodule show nothing, so the strip stays as quiet as before. The worktree follows the folder the agent works in, which can be a worktree while its shell is still in the main checkout. **The files readout** is at the strip's right end, before the ⋯ button, while the project has uncommitted changes and the files column is away: plain text in the worktree label's look (12 pt, tertiary), `3 changed +58 −6`, the lines in *done*'s sage and *failed*'s muted red as in the column's header. Under the pointer the words become `Show Files ⌘\` in the same place (both laid out at once, so nothing moves) on the selection's soft tile, and a click opens the column. It is absent for a clean project, a folder that isn't a git repository and a session in Desktop, Documents or Downloads themselves, and it goes while the column is up, which shows the same numbers. It shows whole or not at all, after the name and the folder: a narrow window drops the readout first, then the worktree. With the sidebar hidden it starts after the traffic lights. It doesn't animate when it changes (nor does the readout coming and going). **The update hint** sits after the readout, before ⋯, while the agent in front runs an older version than the one installed (FEATURES.md → F12): a capsule 24 pt tall in *needs you*'s amber, a soft fill (15%) and the amber text, 12 pt medium, after a small up arrow: `↑ Claude Code 2.1.291` (the installed version; "Claude Code updated" when the path names none). Chosen by the author on 2026-10-06 over an accent tile with the agent's mark and an outlined capsule with an amber dot, knowing amber otherwise means *needs you*: the hint is meant to be seen. Under the pointer the words become what a click does, `Restart Claude Code` (`Restart After This Turn` while the agent works or waits on you), on a stronger fill (27%), both laid out at once so nothing moves; the tooltip names both versions ("Claude Code 2.1.285 runs here; 2.1.291 is installed."). While a restart waits it says `Restarts after this turn` (a click, `Don't Restart`, takes it back), then `Restarting…` for the second it takes, both after a turning arrow; then it goes, since the session runs the new version. An agent Calm doesn't restart gets the capsule with no click, and its tooltip says to quit and start it again. It sits outside the rows that fit, so the title gives way to it, never the reverse. The welcome page, Settings and a viewed file cover it. The window's own title (hidden) carries the same name, so the Window menu, Mission Control and VoiceOver get it; with no session it's "Calm".

## Session cards

| Line | Content | Shown when |
|---|---|---|
| 1 | agent's mark · **session name** · time since last activity | always |
| 2 | state mark · state · current step (e.g. "Working · Running reconciliation", or just "Working"; "Working · Compacting" while the agent compacts its conversation); while working, the agent's moving mark stands in for the state mark. No minutes here: the time in the corner already counts them. A done card whose turn left shells running adds "· 2 shells running" in the tertiary color: a footnote, gone once you move on | not idle |
| 3 | thin progress bar · "3 of 5"; while the agent compacts, the compaction bar in its place (below) | not idle, and the agent keeps a todo list or compacts |
| 4 | recap: the latest agent message as plain text (no Markdown marks: headings, code blocks and bold go, a list reads "a; b; c"), two lines at most (one when idle). An idle card shows the agent's own summary instead when it wrote one after that message (Claude Code's recap): by then you've read the answer, and what you need is where you were. A done card keeps the message, since it's the news | always |
| 5 | worktree mark · worktree name | the session runs in a git worktree |

- A name too long for its line keeps its start and ends in "…". Rest the pointer on the card or row for half a second and the name glides once to its end and holds; it slides back when the pointer leaves. With motion reduced it stays truncated.
- Plain shells are a single compact line: the shell's title (the folder's name when it has none), plus the state mark when a long command finished. Hover shows the last such command's message, or else the folder.
- Each state has its own look (see Session states): *working* tints the card a soft blue, *needs you* amber, *done* sage until you move on from it; an idle card recedes (its mark in gray, its name dimmer) and is shorter: no state line or progress bar, one line of recap, tighter padding. That includes done and failed cards once you move on: clicking one keeps it tall while you read, and it settles to idle when you go to another session or leave Calm. The selected card is the one that stands out: a ring 1.5 pt wide in the text color (60% of it, 55% in light; nearly solid with Increase Contrast), the same in every state, and a surface lifted *lighter* than its neighbours in either theme (a darker card in light mode turned the tints muddy); a selected shell row gets the same. Sessions shown together in a split are lifted too, without the ring (Split panes). A state is told by color and the selection by the ring and the lift, so the two never blur: a slightly stronger sage alone read as "more done", not "selected". For the same reason a state's own card edge is faint (8% of its color): at 24% every tinted card drew an edge nearly as bright as the ring. The ring sits inside the card's edge, so choosing a card never moves anything.
- The agent mark is the agent's own logo in a small neutral tile (see Agent marks); a letter (C, X, O, π) stands in if a mark can't be drawn.
- **Compacting** (chosen by the author on 2026-10-06 from three mockups: the word alone, this bar, or a note that stays): an agent summarizing a conversation that filled up takes a minute or two (99 s at the median in the author's history), on its own mid-turn or after `/compact`. The card stays *working* (blue, the mark moving) and says "Working · Compacting". The todo bar's line holds a bar of the same look, full and breathing like the restoring bar (0.4 to 1 and back over 1.9 s; still with Reduce Motion), with the conversation's size beside it ("968k", from the agent's last reply). When it ends, the bar drains in 0.6 s to the share kept, the sizes saying "968k → 13k", and 5 s later it fades and the todo bar comes back, so the card never changes height when the agent keeps todos. A `/compact` you typed ends the turn: the card turns *done*, says "Conversation compacted.", and keeps the drained bar until you move on. Esc cancels a compaction; the card follows (a `/compact` goes back to idle). Nothing before it (Claude Code's own footer counts down to auto-compact), and no notification after. Compact shows "Working · Compacting" with a short bar (46 pt) where the todo count goes, then the sizes there; a `/compact`'s done line reads "Done · 968k → 13k · Conversation compacted." Minimal shows nothing more; its tooltip says "Working · Compacting". Claude Code only, for now.
- **Card sizes** (Settings → Appearance → Session cards): **Full** is the card above, and the default. **Compact** keeps the title line and puts the state and the recap on one line under it ("Working · Moved the token refresh…", the todo count at its end as "2/5"; "● Needs you · Should I also…"); an idle card is the title line alone. **Minimal** is the title line alone, with the time in the state's color (12 pt medium: blue working, amber needs you, sage done, the red of failed; idle stays gray) and no state mark. At both smaller sizes a card that waits for you (needs you, done, failed) grows a line: in Compact its message gets a second line, wrapping under the text, not the mark; in Minimal it gets one line under the title. It settles when the agent works again or when you move on from it, as done does today. Heights at the standard interface size: Full 111 pt for a working card, Compact 66 (83 grown), Minimal 40 (63 grown), the height of a shell row; idle cards are 40 in both smaller sizes. The worktree line shows only at Full (the title strip names it for the session you're in), and a smaller card's tooltip holds what it leaves out: the whole recap and the worktree. The size follows the saved state, so a card being restored keeps the size it will have. Shell rows and group headers don't change. With Differentiate Without Color on in System Settings, Minimal puts the state mark back before the time.
- **Shrink cards to fit** (a switch under the size chips, off by default): the chosen size becomes the largest the cards get, never passed: with Compact chosen they go down to Minimal and back to Compact, never to Full. The row's one line says so: "Cards step down from Compact when the sessions don't fit, and back when there's room." With Minimal chosen there's nothing smaller, so the line says that and the switch rests at 45% (it keeps its state for when a larger size is picked). When the sessions don't fit the sidebar without scrolling, every card steps down a size (Full → Compact → Minimal), and steps back up when sessions close, groups fold or the window grows and the larger size fits again. Stepping down follows what's drawn; stepping up guesses the larger size's height from the cards' own heights (a recap counted as filling its lines) and keeps 16 pt spare. Near the edge a guess a little short made the list flip between Full and Compact at every state change (the author's sidebar: Full needed 1005 pt of 1001, guessed at 985), so now each step down measures how short the guess was and later guesses add it; after a step down the cards stay down for 30 s, then look again; and a size drawn taller than its room isn't tried again until the sessions change or the room is as tall as it was drawn. When the window grows past the size the cards stepped down in, they don't wait: a size already drawn with the same sessions comes back as soon as its drawn height fits, without the 16 pt spare (a guess still keeps it). A launch used to lay the sidebar out once in the window's saved windowed frame before filling the screen again, and Full (998 pt in the author's filled 1001) stepped down there and never came back; the window now takes its saved frame, filled if it was left filled, before anything is laid out. Group headers and shell rows count toward the fit but never change. A change eases like a size picked by hand (0.25 s); in the sidebar's first second (a launch) it settles without motion, so many saved sessions come up small instead of shrinking in front of you. If even Minimal doesn't fit, the list scrolls.
- **A folded group** keeps one line, and at its right end says what's going on inside in the cards' own state marks, most urgent first: needs you (amber dot), failed (×), done (sage check, 11 pt here), working (blue ring). Up to three sessions in a state get a mark each, 3 pt apart, few enough to see without counting (three rings: three working); four or more get one mark and the number beside it, 12 pt medium in the state's color (○ 4). States sit 9 pt apart. Idle sessions show only when nothing else is going on (• • for two idle shells), and an empty group shows nothing. A session that needs you also tints the whole line amber, as a shell row that needs you is tinted, so folding a group never hides one. The marks are never cut: a long group name gives way and ends in "…". They crossfade when a state changes (0.25 s) and never move. The header's tooltip and VoiceOver say it in words: "3 working, 2 idle". Going to a session in a folded group unfolds it, sliding open over 0.18 s like a click on its header (at once with Reduce Motion), so the selected card is always in view; a new session's group opens along with its row.
- Secondary text stays muted; only the name is in the primary text color.

**Right-click a card**, or the **⋯ button** at the right of the title strip (for the session you're in), the same menu: Rename…, Resume <agent> Conversation (after the agent exited) or, while it runs, Restart <agent> (Restart <agent> After This Turn while it works or waits on you, Don't Restart <agent> while that waits, greyed out during the second a restart takes), Fork into New Split, Fork into New Tab (where the agent can fork); Copy Session ID, Copy Resume Command, Copy Folder Path, Open in Finder (where there is something to give); Move to Project, Let It Follow Its Folder (for a session kept in a project), or Keep as Project… (for a scratch session); Close Session. Rename edits the title in place, in the card's own spot. A copy leaves a quiet note by the pointer ("Path copied"). The ⋯ button is quiet (the tertiary color, 13 pt) until the pointer is on it, then it brightens on a soft tile.

## Links

- **At rest:** a faint dotted line (the terminal's text color at 45%, 1 pt dots) along the bottom of each link that opens. Only links that lead somewhere are marked, so a mark always means a ⌘-click works. Marks fade in over 0.2 s once the text has held still for 0.3 s, and a changed row's marks fade out at once; the rest stay where they are.
- **Holding ⌘:** libghostty underlines the link and shows the pointing hand; its dotted mark steps aside. A tag appears just under the link, left edge by the link's start, in a surface a step lighter than the terminal, 9 pt corners and a soft shadow: an icon (file, image, folder, globe, or a question mark), the name (12.5 pt medium, `:line` included) and, on the right, what a click does (11.5 pt, secondary); under them the folder with `~` for home, or the URL's path (11 pt monospaced, shortened in the middle). At most 440 pt wide. With no room below the link, it sits above.
- **A link a program cut across rows** (an agent's full-screen view breaking a long URL or path where its row ends) looks like any other under ⌘, whole: the pointing hand, the tag on the row under the pointer, and a solid 1 pt underline, in the text's own color, along every row of it (libghostty underlines only the piece of it that it sees). At rest it has the dotted mark on each row, like a link the terminal wrapped.
- **Images:** the tag shows Quick Look's thumbnail above the name, at most 220 × 140 pt; it fades in when ready, and the tag shows without it until then.
- **An agent's pasted image** (`[Image #4]`, or a picture of one above the prompt): the same tag with the picture large, at most 440 × 300 pt and never taller than the room on the bigger side of the link, named `Image #4` with its size in pixels under it (`2000 × 302`). Over a picture, the underline and the tag sit by its caption. The 440 × 300 is a first proposal, not yet picked by the author.
- **Pictures above Claude Code's prompt** (drawn by Calm's plugin, in Claude Code's own band): one row of tiles, each a rounded frame in Claude Code's dim border color holding the picture and, under it, its tag as a dim caption. A tile keeps its picture's shape, at most 8 rows tall; all of them shrink together to fit the band's width, and the row isn't drawn when even 2 rows don't fit.
- **Not found:** the name dims and the action reads "Not found", so you know before clicking.
- The tag takes no clicks and goes away on typing, clicking or scrolling, or when ⌘ or the pointer leaves the link.
- **Programs that take the mouse:** under ⌘ a link looks and behaves the same (underline, pointing hand, tag), but there are no resting marks, since such a screen is redrawn too often for them to hold still. The tag goes away when the link's text changes under a resting pointer.
- **Table cells, holding ⌥** (Copy Cell): the cell under the pointer gets the links' dots as a rounded outline (3 pt corners), inside the table's own lines. It follows the pointer from cell to cell, showing and going in 0.1 s so it never trails, and goes away on typing or scrolling, or when ⌥ or the pointer leaves the table. An ⌥-click leaves the small "Cell copied" note by the pointer, gone within a second. An ⌥-drag inside the cell shows its selection as bands in the theme's selection color at 40%, one per line and only over the text, inside the outline; on release it says "Copied" ("Cell copied" if it took the whole cell) and the bands fade after 0.6 s. The same happens in programs that take the mouse.

## Viewing files

- Opening a viewable file (Markdown, HTML, PDF, images, code) **covers the main area**. The sidebar and files column stay, and the viewer keeps to the main area as they slide in and out.
- The header shows the file name and path, **Open in editor**, and **esc · Back to <session>**.
- Content is centered at a comfortable reading width.
- **Esc** returns to the session exactly as it was. The session keeps running while the file is open; if it needs you, its card tints as usual.
- Going to another session leaves the file, as it leaves Settings, so "Back to <session>" always names the session behind the file.

## Session states

| State | Indicator | Loudness |
|---|---|---|
| idle | a shorter card: the agent's mark in gray at 45%, name dimmed, one line of recap (the agent's own summary when it wrote one) | silent |
| working | soft blue card; the agent's mark moves in its own way; "Working" (with the agent's step when it names one) in blue, a soft light crossing it every 2.6 s | silent |
| done | sage card with a filled check, until visited (then idle) | silent until visited |
| failed | small mark in the theme's muted red | silent until visited |
| **needs you** | amber card, plus a dot | the only state that may notify |

When the work ends, the mark settles once, in about a second, before it rests.

**Restoring.** After a launch or a Restart the sidebar comes back as it was left: each agent's mark, state and recap, and the time since its last activity. Calm checks every saved agent against the running one before the window opens (DESIGNS.md → Launch), so normally there is nothing to see. Only if that takes more than a quarter of a second do the rows hold what was saved, quietly: no tint, the mark gray and still, a soft bar that breathes where the state goes, the recap dimmed, and each card keeping its size so nothing moves. A line, "Restoring sessions…", sits in the gap under the search field, so nothing moves when it goes. When the check ends, every row settles together in one 0.45 s fade: at once if it was quick, but never sooner than 0.45 s after the loading began (so it never flashes), and after 2 s at the latest. The loading state asserts no state, so nothing shown is ever wrong. With Reduce Motion the bars stay still and the fade is a cut.

## Agent marks

Each agent shows its own logo, which moves only while the agent works. The motions follow each agent's own, slowed and softened where Calm poses them; they run at 30 frames a second, and not at all with Reduce Motion, or while nobody can see the window (minimized, covered, on another Space, the display asleep). Calm in the background with its window in view keeps them moving: a still mark would read as a stuck agent.

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
| running | any session is working | the chase: the cursor cell runs around the ring, a lap in 1.5 s. It holds on each place and jumps to the next, as a terminal spinner does (the welcome page's larger mark eases between them), and the opening travels just ahead of it. A four-cell trail follows the cursor, and the ring steps back to 60%, so the motion reads at Dock size |
| done | a session is done and not yet visited | the ring closes, and the cursor cell turns sage |
| failed | a session failed and not yet visited | the ring loses its warmth to grey, and the cursor cell turns muted red |

- There is one state for the whole app: failed outranks running, which outranks done. *Needs you* has its notification and leaves the icon as it is.
- When work stops, the cursor carries on to its resting place and takes the last step slowly, settling once as agent marks do. Then the icon turns into done or failed in half a second, or rests.
- With Reduce Motion (or `motion` reduced or off), running is shown still: the trail and the dimmed ring, without movement.
- The welcome page draws this same mark with the same view, so it is always the real icon, and gives it two motions of its own, an arrival and a breathing cursor, that never mean *working* (see Welcome page).
- No badges and no bouncing.

### The dev build

The Debug build ("Calm Dev": what `mise run run` and the self-tests launch) is set apart from the installed one in three small ways you can see, and one you can't, so the two are never taken for each other. Nothing else differs: themes, states, layout and motion are the shipped ones, so what is tested is what is installed.

- **Icon:** the same mark, the same states and motion, on a cool lavender tile, with violet where the shipped icon is warm (ring, center, cursor, glow). Violet because no state uses it: working is blue, done sage, needs you amber, failed red. Done and failed keep their colors. The welcome page's mark takes it too, since it is the same drawing.
- **Name:** "Calm Dev" in the menu bar, the Dock, notifications, the About panel, the Calm menu's items ("Quit Calm Dev") and the window's title when no session is open.
- **DEV tag:** plain small capitals (11 pt, tracked, semibold) in the icon's violet, at the right end of the strip above the sidebar's search field, level with the traffic lights. No box, and nothing else in the chrome takes the color.

The fourth is its own bundle identifier, `com.jinhuang.calm.dev` (the installed Calm's is `com.jinhuang.calm`). macOS keeps a Calm pinned in the Dock apart from the dev build running beside it, and the dev build has its own defaults (the window's saved frame), notification settings and privacy grants, which it asks for again the first time. Its state folder and control socket are still the installed Calm's, so the two still can't run at once.

## Arrival card

- Appears at the top of the pane when switching into an agent session, only when it adds something: the sidebar is hidden (its card would say the same) and the session had activity since the user left it. ⌘⇧I shows it any time.
- Content: state mark, title · state (with the card's "· 2 shells running" when a done turn left shells) · time since last activity, and one or two lines: what the agent asked while it needs you, the agent's own summary for an idle session that has one, otherwise the last thing it said (the card's recap, by the same rule).
- Fades out on the first keystroke or after a few seconds. A shortcut shows it again.
- Never covers the agent's input line.

## Search (⌘K)

- A centered panel, 680 pt wide (narrower in a small window), 90 pt from the top, in the chrome's own colors on a surface a step off the terminal's background (the link tag's), 14 pt corners and a soft shadow. Every size below grows with the interface size. Picked by the author from local mockups over several rounds (2026-09-30): grouped like the sidebar, then refined one decision at a time.
- **The field:** a quiet magnifying glass and "Search sessions" in 17 pt, 56 pt tall, a hairline under it. Nothing else: the headers carry the counts.
- **Groups:** a header per group, drawn like the sidebar's (the project's pixel mark, 20 pt, or the folder or scratch glyph; a project's name in small capitals, a folder's as it is on disk), 42 pt tall, pinned at the top while its rows scroll under it. At its right, what it holds, each only when it isn't zero: the working ring and how many are open in Calm and doing something (working, done, waiting on you or failed) in *working*'s blue, the idle dot and how many are open and idle, and how many are past on a small tile in the project's own mark colors (gray for a folder). Three numbers at most, whatever the history holds; the tooltip says it in words ("3 open (1 done, 2 working), 1 idle, 14 past"). The empty field's groups have no counts: nothing has been searched.
- **Rows:** the agent's mark (26 pt) and the title in a session card's type (14.5 pt medium), and at the line's end how long ago, written out ("just now", "4 minutes ago", "2 hours ago", "yesterday", "3 days ago", then "Sep 16"; the figures in the secondary color, the words a step quieter), or, for a session open in Calm, its state's mark from the sidebar (no word). A deleted transcript's title adds "· can't be resumed". Under the title, while searching, the lines that show the words (13 pt, secondary): each is built around its words (a few words of context either side, trimmed before a word ever is; "…" where words sit far apart or the message goes on before), and a line you wrote hangs the prompt's chevron in the gutter between the mark and the text, so every line starts under the title. The words typed are marked wherever they show, the title and the group's name included: a soft wash of the accent under them, in the primary color, medium. The selected row takes the sidebar's selection fill (10 pt corners) and a ↵ key after its time; nothing is kept for the key on other rows, so times, marks and counts sit 18 pt from the right edge, as the text does from the left. The tooltip says what ↵ does ("Go to this session", "Resume in ~/dev/calm", or why it can't be resumed).
- **More and less:** a group's last row, 38 pt: a chevron, then "13 more in calm" (the number in the project's ink); ↵ or a click shows five more above it and the row stays where it was, under the pointer. Once opened, "Show less ⌃" sits at the row's right and folds the group back to its first few, bringing its header to the top; with everything shown the row reads "All 16 in calm" (not clickable, so a click too many never folds it) and Show less. The header of an opened group has a fold chevron too, in reach while its rows scroll.
- **The list** is as tall as it needs to be, up to 560 pt (less in a short window), and always ends on a whole row with a 16 pt fade over the next while there is more, never half a row or a header alone.
- **Keys:** ↑ ↓ move through rows and the last rows of groups; ⇥ goes to the next group's first row and ⇧⇥ back (the group's header comes to the top); on an opened group's last row → and ← choose between more and Show less (in the field, once the arrows have been used or with the caret at the text's end); ↵ acts; Esc closes.
- **Nothing typed:** a switcher, not a wall: the sessions you could pick back up, four of your group's and two of each other's, eleven at most, one line each. "Your recent sessions are all open" when they are.
- Nothing found: "No session mentions that".

## Command palette (⌘P)

- A centered panel, 560 pt wide, 90 pt from the top, a regular material with a hairline and a soft shadow, a 50 pt field ("Run a command", 16 pt) with a hairline under it, and a list of at most 360 pt. Every size grows with the interface size.
- **Rows:** the name in 13 pt medium, and at the right the key that already does it, for the keys only Calm has (12 pt, secondary).
- **The description (chosen by the author, 2026-10-01, over a line under the list):** the selected row, and only it, says in one short sentence under its name what it does (12 pt, the secondary color, one line: "Start a copy of this conversation in a new split beside it."). It fades in as the row takes the selection and the row grows by that line, over 0.12 s (none with reduced motion), so the rows below it move by a line with each ↑ ↓. Every row has one (Calm's in `PaletteRow`, Ghostty's two as Ghostty words them), at most about 70 characters so it stays one line at every interface size, and typing a word of it finds the row.
- Nothing found: "No matching command", where the list was.
- **What's in it** is the rule of FEATURES.md → Command palette: what has no key everyone knows. The rows are kept by category (agent conversation, session and layout, view and navigation, folder, look, Calm, terminal), with no headers: the order is the grouping. The session in front's rows come with their category and not while Settings covers it. Every row is one-shot: no row opens a second list, a picker or a submenu.
- **Quiet notes:** Copy Last Reply ("Reply copied" or "No reply to copy"), Randomize Theme (the theme's name) and Dump Logs ("Collecting the log…", then Finder opens on the file) say what happened in the note by the pointer that copies use, since the palette has closed.
- **Keys:** ↑ ↓ move, ↵ runs the chosen row and closes the palette, esc or a click outside closes it. Nothing is typed into the terminal behind it.

## Split panes

With more than one pane on screen, the one you're in must be plain to see, and so must the one ⌘W is about to close. Neither is said with a border ("no rings around panes") or a name; the panes themselves say it.

- **The pane you're in is the bright one.** The others recede to 0.6 of their strength: a veil of the terminal's own background (the color along the pane's top edge, so a full-screen app that paints its own, OpenCode, fades into that), fading in and out over 0.16 s. It follows the layout's focused session, not the keyboard focus, so a question on another pane, or Calm losing focus, leaves it as it is. A lone pane is never dimmed. The value is Calm's own and fixed: the engine draws no such dim, and Ghostty's `unfocused-split-opacity` (0.9 in the author's config, a 10% dim that could not be seen) is not read.
- **⌘W on a pane with something running** (an agent, or a process Ghostty can see) puts the question in the middle of that pane, with no box: the pane clears a soft space (a vignette of its own background, near solid where the words are and gone at the edges, so terminal text doesn't show through them) and the words stand on it. The running program's mark comes first, in the tile the sidebar uses (an agent's own mark, else the shell's chevron tile), then "Claude Code is running here" (or "A program is running here") in 15 pt medium, "Closing the session ends it." under it in the secondary color, and two answers as plain words, **Keep** and **Close**, each with its key drawn beside it as a soft rounded key: Escape's mark (a circle broken at the upper left, an arrow leaving through the gap) and Return's arrow. Close is the medium one; the pointer lights a word with a soft fill and its key with it. While the question is up the other panes fade to 0.22 and the asked pane steps back to 0.5. Nothing carries the session's name: where the words stand is the answer. Return closes; Esc keeps; any other key, or a click outside the words, keeps and goes through; ⌘W again takes the question back. Focus arriving at any pane ends it too (a click on the other pane, ⌘[ and ⌘]), so the next ⌘W is about the pane you're in; it also goes away when the layout changes or the pane ends by itself. The same question comes from Close Session in the right-click menu and the ⋯ menu. An unsplit session keeps the window sheet ("Close this session?"), since the whole area is the pane.
- **A pane at a plain prompt closes at once**, with no question.
- **The split icon.** In a split, each pane has a small icon in its top right corner, 8 pt in: a window with a line through it, 16 pt, the line following the split the pane is in (upright for panes side by side, flat for stacked ones). It says that what there is to do about splitting is here. It is drawn in the chrome's tertiary color at rest, as quiet as the title strip's ⋯, and under the pointer it brightens to the primary on a soft tile. At rest only the pane you're in shows it; any pane shows its own while the pointer is on it, and while its menu is open or it is being dragged. A lone pane has none, and neither has a pane a close question stands on. The tooltip is the system's: "Split options · or drag to move it". It is not the session's mark: the dim, the title strip and the lit sidebar already say which session a pane is, and the icon says what it is for.
- **Its menu** opens on a click (a click also puts the focus on the pane): **Take Out of Split**, **Unsplit All**, a line, **Zoom Pane** (⌘⇧↵; **Show All Panes** while one is zoomed), **Equalize Splits** (⌘⌃=). Leaving comes first, since it is what you came for. Unsplit All is left out with two panes, where it would do what Take Out does. There is no Split Right or Down in it: the icon only exists inside a split, and making one has ⌘D, ⌘⌥ + an arrow and the Shell menu.
- **Taking a pane out of a split ends nothing.** The session is a session of its own in the sidebar again (a layout of its own), the other panes close up around the gap (the pane folds away like a closed one) and stay on screen, and if the focus was on the pane it goes to the pane that took its room. Unsplit All does that for every pane but the one you're in. Shell → Take Pane Out of Split and Unsplit All do the same, with no keys of their own. Dragging the icon onto the sidebar takes the pane out too: the card in your hand is the session's (its mark, its name, its folder), and while it is over the sidebar the pane it came from all but goes (a veil of 0.84), so the drag says what letting go will do.
- **Bringing a session into a split.** Drag its card from the sidebar onto a pane. A dotted outline, the one links and table cells use (round dots, 1.5 pt, four apart), with a hush of the chrome's ink inside, shows the half the new pane would take: the side of the pane under the pointer that the pointer is nearest, and nothing over the pane's middle (the middle 44% each way), so letting go over the text calls it off. The new pane grows in from that edge and has the focus. A session already in the split moves; one from another layout leaves it (the layout goes if that was its only pane). A pane dragged by its icon lands the same way. Files and text dropped on a pane are still pasted as a path or text: a dragged session has a type of its own (`com.jinhuang.calm.session`), which only the sidebar and the split's panes take. A card dropped back on the sidebar is nothing.
- **The sidebar lights the split.** Every session shown together is lifted in the sidebar (the selection's lift, with no ring); the one you're in keeps the ring. A lone session lifts nothing. Opening any session of a split lights all of them.
- **A closed pane folds away.** The panes that stay take their final frames at once, and a still picture of the closed pane's last frame shrinks and fades over them, toward the edge it shared with the pane that takes its room (0.22 s), so the eye follows where it went. With Reduce Motion it just goes.

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
| Smooth scrolling | scrolling moves by pixels, not whole rows. Scrollback follows the trackpad; a program that scrolls part of its screen (Claude Code's full-screen view as an answer streams in, `less`, vim), or moves it by redrawing every row (pi's full-screen view, OpenCode), has that part slide into place, a scrollbar or sidebar beside it staying where it is, each jump easing home in about a quarter second, so steady output reads as one flow, while something it keeps drawn over the scrolling part's edge (Claude Code's "Jump to bottom" hint) stays still and the text under and beside it keeps sliding; a resize or divider drag slides the content instead of stepping it. At rest, a pane whose height isn't a whole number of rows shows part of the scrollback row above its first row instead of an empty strip. Full motion only |
| Smooth cursor | a soft smear follows the cursor when it jumps (not when typing moves it one cell), fading out in about 140 ms. Calm's own shader `cursor_glide.glsl`, loaded through Ghostty's custom-shader support |
| Cursor trail | part of the same shader: the smear's tail catches up with its head, so it reads as a short trail |

**Window**

| Motion | Behavior |
|---|---|
| Splits | new panes grow into place, from the edge a dragged session landed on too; a closed pane, or one taken out, folds away toward the pane that takes its room, over panes already in their final place (0.22 s); the panes that don't have focus fade in and out with it (0.16 s), and so do the split icons and the dotted landing |
| Sidebar | when hidden, it peeks in over the terminal as the pointer reaches the window's left edge, and slides away shortly after the pointer leaves it |
| Session switching | hold ⌃ and press Tab to cycle sessions in sidebar order, top to bottom (⌃⇧Tab goes up, both wrap), over small live previews; release ⌃ to settle on the chosen one. While ⌃ is held, ← and → move too, Return settles and esc closes without switching. A quick ⌃Tab goes straight to the next session down without showing anything |
| Session cards | cards slide between projects; state changes cross-fade; the recap updates without jumping. The agent's mark moves while it works and settles once when the work ends (see Agent marks). A new card size eases every card to its height (0.25 s), and so does a smaller card growing a line for something that waits for you. A compaction's bar breathes while it runs (Core Animation, on the wall clock), drains in 0.6 s when it ends, and fades 5 s later |
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
- OpenCode in Calm wears the theme too, unless its own config names a theme: connected, Calm's `calm` theme (the theme's accent for its agent and bars, dim text clearly dimmer, message and prompt boxes barely lifted, headings in the strongest text rather than a color), following theme and appearance changes live; unconnected, its `system` theme.
- A connected pi wears Calm's `calm` theme the same way (the user's message on a slight lift instead of a colored slab, the prompt's frame in the accent, stronger with the thinking level), over pi's built-in themes only.
- Optional glass background uses the system's material; the terminal can float as a rounded card or run edge to edge.
- The padding around the terminal takes the color of the cells next to it, so an app that paints its own background (OpenCode, Neovim) fills the pane instead of sitting in a frame of the theme's color. The user's Ghostty `window-padding-color` wins. Edge to edge on a solid background, the title strip above the terminal takes the same color, so the two meet without a seam. Only when the app painted its pane in that color, out to the sides: a lighter band on just the first rows (Claude Code's sticky prompt) doesn't tint the strip, and neither does content in the middle of the pane, however much of it there is (a long diff's green); the strip then keeps the theme's background.

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
│                            │   Session cards                                 │
│                            │   Full  Compact  Minimal                        │
│                            │   ▭ Shrink cards to fit                  ( ○)   │
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
| **Appearance** | a live miniature of the window (its sidebar's cards at the chosen card size), the themes, interface size, session cards (full, compact, minimal: chips drawn like the interface sizes, each a slice of the sidebar at that size; under them a Shrink cards to fit switch, off, with its one line of help), glass or solid, edge to edge or card, motion (full, reduced, off) |
| **Agents** | one group: **⌘N starts** (⌘⇧N too, in a scratch folder) with a menu of the agents installed, then a row per agent: its mark on a 34 pt tile (moving while one of its sessions works), its name, and under it a chip per option it starts with (26 pt, 13.5 pt words; on is a soft fill of the accent with a check, off a quiet outline; pointing names the flag). The right side holds only what needs a hand: Connect, Left alone (why, under the pointer), Set Up… (a step in the agent's own settings, explained in a popover; no agent needs one today), or ••• for Disconnect where Calm added a file. Connected is the normal state and isn't written, and what the agent is doing stays in the sidebar. An agent whose whole command is set in config.toml (`calm config`, no field here) shows that command under its name in place of the chips, in 13 pt monospaced secondary text, cut in the middle when long; pointing at it says how to unset it. Then **Keys**, one row: "Send prompts with", the switch, and just before it ⌘ ↩ as two soft keys (a face a step off the card, a hairline edge, a one-point shadow; solid while on, an outline while off), which say what the switch turns on; under the title the marks of the agents it reaches, small and overlapping (hover: which, and why not Codex), and "Return starts a new line", or only when something needs a step: "OpenCode and pi switch when they start again", "Claude Code keeps your own Return" (its mark grayed), "Calm can't edit pi's keybindings.json" (the warning mark on it). Picked by the author from local mockups (2026-10-06): choices drawn from keys (two key groups with "or", boxes, chips) read as a legend rather than a control, so the keys label the switch. Then which states notify, and sound. Calm → Agents… opens this section |
| **General** | editor (automatic, an installed one, or Choose Application… for any app), where paths open, auto-grouping, and the config files (Calm's, Ghostty's with the font it sets, the themes folder) |
| **Shortcuts** | Calm's shortcuts as key caps, read-only; keys are changed in the Ghostty config |

- Going to any session (⌃Tab, ⌘1…9, search, a notification, a new session) leaves Settings.
- Each row starts with its icon on a small tile, as the section list and the sidebar's footer do.
- Quiet by default: no help line under a row unless the control can't do what it shows (Motion while the system's Reduce Motion is on) or its name can't say what it does (Shrink cards to fit, whose line names the size the cards step down from; chosen 2026-09-30 over a tooltip, a line that follows the sidebar, and chips and switch in one card), and none under an agent: a step it needs explains itself in a popover. A hand edit shows after Calm → Reload Configuration.
- The Editor menu ends with **Choose Application…** (the system's file picker, on /Applications); the app chosen stays in the menu, ticked. The row says "Opens the file, not at the line." only for an app that can't take a line.
- A section gets a small warning mark only when something in it is broken: Agents when macOS blocks Calm's notifications (with a button to System Settings), General when a line of config.toml can't be read (shown under the file).
- Settings reopens on the section it was left on. A window too narrow for the list and the page shows the list as icons.

Rules: one line of help text per setting at most; no setting that only shows or hides a button.

## Keyboard

| Shortcut | Action |
|---|---|
| ⌘K | Search sessions |
| ⌘P | Command palette |
| ⌘N | New session running the agent chosen in Settings → Agents |
| ⌘T / ⌘D / ⌘⇧D | New session / split right / split down |
| ⌘⌥← → ↑ ↓ | Split left / right / up / down |
| (none) | Shell → Take Pane Out of Split, Unsplit All; the split icon's menu; drag the icon to the sidebar |
| ⌘⇧N | New scratch session, running that agent |
| ⌘O | New project |
| ⌘W | Close the session, or Settings, search or a viewed file in front of it |
| ⌘⇧T | Reopen the session closed last |
| ⌘Z | Undo the last edit of the line being typed (sends Ctrl-_) |
| ⌘↵ | Return; with Send with ⌘ Return on, send an agent's prompt (Return starts a new line) |
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
- **⌘↵** is Ghostty's *toggle full screen*. Calm's defaults take it away (2026-10-06, the author's call: "cmd+enter shouldn't be fullscreen"; ⌃⌘F and the green button remain): it types Return (`text:\r`), and with Send with ⌘ Return on it is unbound, so programs get it as ⌘+Return (`ESC[13;9u` under the kitty keyboard protocol, `ESC[27;9;13~` without). Self-tests press it with `calm.cmd_return`, which hands the key to the pane's `keyDown` when nothing claims it, as AppKit does.
- **⌘⌥ + arrow** is Ghostty's *move focus to the split in that direction*. Calm's defaults rebind the four keys to *split toward that side* (2026-09-29, the author's call: moving focus by direction isn't worth the best chord, and ⌘[ / ⌘] still move it). The Shell menu lists these four; ⌘D and ⌘⇧D keep working for right and down, unlisted, since a menu item shows one key. Resize stays on ⌘⌃ + arrow. Calm's defaults load before the user's Ghostty config, so a user who has their own `goto_split` lines on ⌘⌥ + arrow (the author did) keeps focus movement there and gets no splits until those lines go. Self-tests press the keys with `calm.cmd_opt_left` (or `right`, `up`, `down`).
- **Restart Calm** (Calm menu) has no shortcut on purpose: it's rare, and next to ⌘Q it would be easy to hit by mistake.
- **⌘\\** toggles the files column. It was ⌘⇧E until the author's own Ghostty config turned out to bind that to *equalize splits*, so the column never opened; nothing in Ghostty's defaults uses backslash. 1Password's autofill is ⌘\\ by default, a global shortcut that takes the key first while 1Password runs; View → Toggle Files still works then.
- ⌘P, ⌘\\, ⌘⇧I, ⌘⇧N, ⌘O are free in Ghostty's defaults.
- **⌘N** is Ghostty's *new window*, which in Calm's one window was a second ⌘T. Calm's defaults unbind it and give it to New *Agent* Session (2026-10-06); a keybinding of your own for it still wins. ⌘1…9, ⌘[ / ⌘], ⌘⇧[ / ⌘⇧] keep Ghostty's meaning (tab/session by position, previous/next split, previous/next tab).

## Accessibility

- Full keyboard operation.
- VoiceOver labels for every sidebar row and state, as built; they have never been checked with VoiceOver running, and that isn't planned.
- State is never shown by color alone: each state also has a shape. Two exceptions. The Dock icon's *failed* state differs from idle mostly in color (a grey ring, a red cursor cell), and the session's card still marks it by shape. **Minimal** session cards, which the user chooses, drop the state mark (the author's call, 2026-09-30): the tint, the time's color and the agent's moving mark tell the state, and the words are in the tooltip and VoiceOver's label. With **Differentiate Without Color** on in System Settings, the mark comes back before the time.
- Respects Reduce Motion and Increase Contrast.
- **Interface size** (Settings → Appearance), chips under the themes and drawn the same way: each a strip of Calm in the picked theme at that size, its sidebar and cards growing (fewer fit) while the terminal's lines stay put, which is what the setting does. The chosen one is ringed in the accent like the chosen theme; names under them, the percentage as a tooltip. No window chrome or traffic lights: Calm's own picture, not the system's. Default, Large, Larger or Largest (100, 115, 130, 150%) scales every size and length in Calm's chrome at once: the sidebar and its width, cards, the title strip's text (the strip itself stays level with the traffic lights), the files column, search, the palette, the arrival card, the welcome page and Settings. The terminal keeps the Ghostty font's size (⌘+ and ⌘−). A change applies at once; saved as `ui-size` in `config.toml`.
- **Increase Contrast:** the chrome's secondary text, hints, selection and dividers get stronger. A Calm theme's text colors each reach 4.5:1 by moving toward white (dark) or black (light), so dim text stays dimmer than normal text. A theme from the user's Ghostty config is left as it is (Ghostty's `minimum-contrast` is theirs to set).
- A change to Reduce Motion, Increase Contrast or Differentiate Without Color in System Settings applies at once, without a relaunch.
- The files column's rows are buttons, so Full Keyboard Access and VoiceOver reach them: a file reads its name and change ("README.md, modified"), a change row adds its folder and lines ("FilesColumn.swift, in Calm/Window, modified, 64 lines added, 31 removed"), a folder says whether it's expanded, and the section titles are headers. The title strip's readout is a button that reads "3 files changed, 58 lines added, 6 removed" and adds that it shows the files column; the footer's row reads Show Files or Hide Files.
