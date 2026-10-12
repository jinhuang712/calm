# Todo

Small open items, not scheduled.

- [ ] **Sidebar ordering:** add a way to order the sidebar beyond dragging a project's header. Open question: what to order (projects automatically, sessions inside a project, or a pinned area). A design pass comes first.
- [ ] **Reduce Motion gaps:** `SessionCard.swift:70` and `AgentLogo.swift:48` animate a state change under Reduce Motion or `motion = off`. Gate both on `Motion.isReduced`.
- [ ] **PDF is read twice:** `FileViewer.detail` and `makeContent` each build a `PDFDocument`. Share one.
