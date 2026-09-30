import AppKit

/// Which pane has the focus: the first responder gets the keys, and the model's focused session is
/// what the sidebar, the dim and the title strip show. They have to be the same pane, or ⌘W
/// closes one while the window points at another.
extension MainWindowController {
    /// A key went to `view`. If the model has the focus elsewhere, it moves: the indicators follow
    /// the keyboard, not the other way round.
    func surfaceDidReceiveInput(_ view: TerminalSurfaceView) {
        guard manager.workspace.selectedLayout?.focusedSessionID != view.id else { return }
        traceFocus("a key reached a pane the model did not have focused", view)
        surfaceDidBecomeFocused(view)
    }

    /// One line in the unified log (category `trace`; see `Trace`): which pane the event is about,
    /// which pane is the window's first responder and which the model has focused, by the first
    /// eight hex digits of their ids. Written when focus arrives and when a close is requested, so
    /// a ⌘W that lands on the wrong pane can be read back from the running app.
    func traceFocus(_ event: String, _ view: TerminalSurfaceView) {
        let responder = (window?.firstResponder as? TerminalSurfaceView).map { Trace.id($0.id) } ?? "none"
        let model = manager.workspace.selectedLayout.map { Trace.id($0.focusedSessionID) } ?? "none"
        Trace.note("\(event): pane \(Trace.id(view.id)), first responder \(responder), model \(model)")
    }
}
