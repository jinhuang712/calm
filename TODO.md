# Todo

Small things found in review, not scheduled.

- [ ] **Sidebar ordering:** the author wants a way to order the sidebar beyond dragging a project's header (2026-10-12; a screenshot of ten projects, several folded). What to order (projects automatically, sessions inside a project, or a pinned area) is not decided; a design pass comes first.
- [ ] **Reduce Motion gaps:** `SessionCard.swift:70` and `AgentLogo.swift:48` animate a state change even under Reduce Motion or `motion = off`, while the lines beside them check `Motion.isReduced`. Gate both on it.
- [ ] **PDF is read twice:** `FileViewer.detail` builds a `PDFDocument` for the page count, and `makeContent` builds it again. Share one.
