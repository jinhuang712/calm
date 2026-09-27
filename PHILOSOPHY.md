# Philosophy

Calm Terminal exists to reduce the agitation of supervising many CLI agents. Every feature, setting and pixel is checked against the principles below. When a proposal conflicts with them, the principles win.

## Calm technology

The founding idea comes from Mark Weiser and John Seely Brown at Xerox PARC: calm technology is "that which informs but doesn't demand our focus or attention". Information lives in the **periphery** and moves to the **center** of attention only when it matters, then moves back.

For Calm Terminal, the periphery is the sidebar and the edges of the window. The center is the terminal you are working in. Agent status lives in the periphery. Only an agent that needs you may move to the center.

## Design guidelines

Four words guide every visual and interaction decision:

| | | Means |
|---|---|---|
| **克制** | Restraint | Show only what helps. One accent, one loud state, nothing decorative. When in doubt, leave it out. |
| **优雅** | Elegance | Careful type, spacing and motion. Nothing jumps, flashes or crowds. |
| **极简** | Minimalism | Few elements, few settings, few colors. Every element earns its place. |
| **Calming** | Calm | The interface lowers the pulse. Soft colors, quiet status, interruptions only when they matter. |

## Principles

1. **Sessions come first.** The unit of work is a session: a conversation with a goal, a folder, an agent and a history. Tabs and panes are only where a session is displayed.
2. **Organize by folder, automatically.** Projects are folders. Sessions file themselves under the project they work in. Nobody should arrange tabs by hand.
3. **Route attention calmly.** Calm knows each session's state and interrupts only when an agent needs you. Everything else stays quiet: no rings, no badges shouting counts, no tabs jumping around.
4. **Be reliable, not silent.** Calm never misses a "needs you". Trust is what lets you stop checking.
5. **Stay a terminal.** Agents keep their own interfaces. Calm improves the space around them: status, titles, links, reading and recall. No built-in chat, editor or browser.
6. **Work with every agent.** A thin adapter per agent and a small open contract any agent can call. No agent gets special treatment in the core.
7. **Built for reading.** Agent output is Markdown, tables, diffs and paths. Selecting, copying, opening and previewing them should feel effortless.
8. **Remember everything.** Every past conversation, across every agent, is one search away.
9. **Native and quiet.** Mac conventions, soft colors, gentle motion, one short config file, a settings screen you rarely open.
10. **The minimum technology needed.** Reuse what exists: phone access through agents' own remote features and SSH, browsers through Playwright, editing in your editor. No servers, accounts or cloud.

## Rules drawn from research

| Rule | Evidence |
|---|---|
| Keep status in the periphery; only "needs you" reaches the center | Weiser & Brown, *Designing Calm Technology* (1995); Amber Case, *Calm Technology* (2015) |
| Use graded notification levels: a quiet dot, then a soft highlight, and a banner only for the top level | Pousman & Stasko, *A Taxonomy of Ambient Information Systems* (AVI 2006) |
| Every interruption has an emotional cost, even when productivity looks unaffected | Mark, Gudith & Klocke, *The Cost of Interrupted Work* (CHI 2008) |
| Deliver interruptions at natural pauses, not mid-keystroke | Iqbal & Bailey, *Oasis* (ACM TOCHI 2010) |
| Fewer alerts reduce inattention; but turning all alerts off raises anxiety, so be reliable | Kushlev et al., *Silence Your Phones* (CHI 2016); Fitz et al., *Batching Smartphone Notifications* (2019) |
| On-screen interruptions measurably slow developers' code comprehension | Ma, Huang & Leach, *Breaking the Flow* (ICSE 2024) |
| Presence indicators plus context reduce the disruption caused by AI agents | Pu et al., *Assistance or Disruption?* (CHI 2025) |
| When switching, show context so attention left on the previous task fades quickly | Leroy, *Attention Residue* (2009) |
| A trustworthy record of open work frees the mind from tracking it | Masicampo & Baumeister, *Consider It Done!* (2011) |
| Saturated, bright colors raise arousal; use soft palettes and reserve red for real problems | Wilms & Oberfeld, *Color and Emotion* (2018) |
| Fewer choices lead to more satisfaction (a tendency; replications are mixed) | Iyengar & Lepper, *When Choice Is Demotivating* (2000) |

## What Calm refuses to be

- **An IDE.** No file editing, no code review panes.
- **An agent.** No built-in AI chat, no model calls of its own.
- **A platform.** No accounts, relays, cloud VMs, in-app browser or computer use.
- **A settings maze.** If an option needs a paragraph to explain, the default should simply be right.

## The test for every change

Before adding a feature, setting or visual element, ask:

1. Does it reduce what the user has to track, remember or look at?
2. Does it stay in the periphery unless it truly needs attention?
3. Could the default be right, so no setting is needed?
4. Is there already a tool that does this well outside the terminal?

If the answer to 1 or 2 is no, or to 4 is yes, it probably doesn't belong in Calm.
