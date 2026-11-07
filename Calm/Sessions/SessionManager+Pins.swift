import CalmModel

/// Pinning from the session menu and ⌘P (specs/FEATURES.md → F2). `WorkspacePins` holds the rules.
extension SessionManager {
    func togglePinnedCollapsed() {
        changeWorkspace(animation: .easeInOut(duration: 0.18)) {
            $0.pinnedIsCollapsed = $0.pinnedIsCollapsed == true ? nil : true
        }
        scheduleSave()
    }

    /// Pins a session to the top of the sidebar, or sends a pinned one back to its group.
    func togglePin(_ id: Session.ID) {
        guard let session = workspace.session(id) else { return }
        changeWorkspace(animation: .smooth(duration: 0.3)) { $0.setPin(id, session.pinnedAt == nil) }
        scheduleSave()
    }
}
