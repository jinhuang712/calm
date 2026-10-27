# Todo

Small open items, not scheduled. Design questions are in [ROADMAP.md → Waiting for design](ROADMAP.md#waiting-for-design).

- [ ] **Reduce Motion gaps:** `SessionCard.swift:70` and `AgentLogo.swift:48` animate a state change under Reduce Motion or `motion = off`. Gate both on `Motion.isReduced`.
- [ ] **PDF is read twice:** `FileViewer.detail` and `makeContent` each build a `PDFDocument`. Share one.
- [ ] **Square-corner test fails on macOS 27:** the `CalmWindowTests` corner test was red on 27.0.1 and green on CI (macOS 26) when last run. Calm degrades to round corners. Run it again, then fix the test or the override. Not re-run in the docs rewrite.
- [ ] **Search timing has no script (G3):** commit a script that times a query and a no-change update on a fixture history, so the number can be reproduced.
- [ ] **Cost readings are missing (G6, G7):** run `mise run perf` and record the readings and the date in GOALS.md.
- [ ] **Never-missed check is short (G2):** the goal asks for a week and was met on 4 days. Measure a full week and record it.
- [ ] **F2 has no named gap:** FEATURES.md marks Projects and auto-grouping 🚧 and names nothing. Name the gap or mark it ✅.
- [ ] **Second copy of the Weiser and Brown quotes:** PHILOSOPHY.md quotes them from one copy (calmtech.com). Check them against another.
