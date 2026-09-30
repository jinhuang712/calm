public extension Workspace {
    mutating func setCollapsed(_ projectID: Project.ID, _ collapsed: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].isCollapsed = collapsed
    }

    /// Whether the sidebar hides `sessionID` because its group is collapsed.
    func isInCollapsedGroup(_ sessionID: Session.ID) -> Bool {
        session(sessionID).flatMap { project($0.projectID) }?.isCollapsed ?? false
    }

    /// Opens the group holding `sessionID` if it is collapsed. A session put on screen is never
    /// out of sight in the sidebar, whichever way it got there (FEATURES.md → F2).
    mutating func reveal(_ sessionID: Session.ID) {
        guard let projectID = session(sessionID)?.projectID else { return }
        setCollapsed(projectID, false)
    }
}
