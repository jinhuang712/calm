# Todo

Small open items, not scheduled. Design questions are in [ROADMAP.md → Waiting for design](ROADMAP.md#waiting-for-design).

- [ ] **Reduce Motion gaps:** `SessionCard.swift:70` and `AgentLogo.swift:48` animate a state change under Reduce Motion or `motion = off`. Gate both on `Motion.isReduced`.
- [ ] **PDF is read twice:** `FileViewer.detail` and `makeContent` each build a `PDFDocument`. Share one.
- [ ] **Search timing has no script (G3):** commit a script that times a query and a no-change update on a fixture history, so the number can be reproduced.
- [ ] **Cost readings are missing (G6, G7):** run `mise run perf` and record the readings and the date in GOALS.md.
- [ ] **Never-missed check is short (G2):** the goal asks for a week and was met on 4 days. Measure a full week and record it.
- [ ] **A scratch session leaves its conversation behind:** closing one removes its folder, and the agent's transcript stays under `~/.claude/projects` (12 folders, about 34 MB on 2026-11-14, counted by hand). Claude Code's docs say `CLAUDE_CODE_SKIP_PROMPT_HISTORY=1` stops transcripts in any mode; not tried here. What scratch should keep is a design question for the owner of F2.
- [ ] **F2 has no named gap:** specs/FEATURES.md marks Projects and auto-grouping 🚧 and names nothing. Name the gap or mark it ✅.
- [ ] **Second copy of the Weiser and Brown quotes:** PHILOSOPHY.md quotes them from one copy (calmtech.com). Check them against another.
