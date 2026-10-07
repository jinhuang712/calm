import AppKit
import CalmAgents
import CalmModel

/// The session menu (UIUX.md → Session cards → The session menu): from the title strip's ⋯ for
/// the session in front, or a right-click on a card or a shell row for that one.
extension MainWindowController {
    /// Opens the menu for `id` under the title strip's ⋯ button.
    func showSessionMenuFromTitle(_ id: Session.ID) {
        if sessionMenu.isShowing, sessionMenu.sessionID == id {
            sessionMenu.hide()
            return
        }
        guard let titleHost else { return }
        showSessionMenu(id, at: .below(rectInContainer(titleHost.menuFrame, from: titleHost)))
    }

    /// Opens the menu for `id` at a point in the window (a right-click).
    func showSessionMenu(_ id: Session.ID, atWindowPoint point: CGPoint) {
        let local = container.convert(point, from: nil)
        showSessionMenu(id, at: .point(CGPoint(x: local.x, y: container.isFlipped ? local.y : container.bounds.height - local.y)))
    }

    func showSessionMenu(_ id: Session.ID, at anchor: SessionMenuAnchor) {
        guard let session = manager.workspace.session(id) else { return }
        // From the last version check (every 10 s, off the main thread): asking OpenCode its version
        // here would hold the menu up.
        let content = SessionMenuContent.make(
            for: session, phase: manager.restarts[id], update: manager.agentUpdates[id], runningVersion: manager.runningVersions[id],
            projects: manager.workspace.orderedProjects, isFront: id == manager.workspace.selectedLayout?.focusedSessionID,
        )
        sessionMenu.show(content, for: id, at: anchor, style: sidebarStyle) { [weak self] action in
            self?.perform(action, on: id)
        }
    }

    /// What a menu item does: the same as its ⌘P row, where it has one.
    func perform(_ action: SessionMenuContent.Action, on id: Session.ID) {
        switch action {
        case .restart: restartAgent(in: id)
        case .cancelRestart: manager.cancelRestart(id)
        case .resume: resumeConversation(in: id)
        case .forkSplit: forkConversation(of: id, into: .split)
        case .forkTab: forkConversation(of: id, into: .tab)
        case .rename: beginRename(id)
        case let .copy(copy): self.copy(copy, of: id)
        case .openFolder: openFolder(of: id)
        case .keepScratch: keepScratchAsProject(id)
        case let .moveTo(project): manager.move(id, to: project)
        case .followFolder: manager.followFolder(id)
        case .close: requestCloseSession(id)
        }
    }

    /// A rect in `view`'s own space with a top-left origin (as SwiftUI reports frames), in the
    /// container's, also top-left.
    private func rectInContainer(_ rect: CGRect, from view: NSView) -> CGRect {
        let flippedY = view.isFlipped ? rect.minY : view.bounds.height - rect.maxY
        let inContainer = view.convert(CGRect(x: rect.minX, y: flippedY, width: rect.width, height: rect.height), to: container)
        let top = container.isFlipped ? inContainer.minY : container.bounds.height - inContainer.maxY
        return CGRect(x: inContainer.minX, y: top, width: inContainer.width, height: inContainer.height)
    }
}
