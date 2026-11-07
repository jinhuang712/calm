import Foundation

/// Sessions the user pinned to the top of the sidebar (specs/FEATURES.md → F2). A pin is
/// `Session.pinnedAt`, which has nothing to do with `Session.isPinned` (a session that stays in its
/// project). It places the card and nothing else: the session keeps its project, and closing it
/// ends the pin, because a closed session is found again through search and the project's home.
public extension Workspace {
    /// The pinned sessions, first pinned on top, so a new pin moves nobody.
    var pinnedSessions: [Session] {
        sessions.filter { $0.pinnedAt != nil }.sorted { ($0.pinnedAt ?? .distantPast) < ($1.pinnedAt ?? .distantPast) }
    }

    /// What a group shows: its sessions without the pinned ones, whose cards sit in Pinned.
    func unpinnedSessions(in projectID: Project.ID) -> [Session] {
        sessions(in: projectID).filter { $0.pinnedAt == nil }
    }

    /// The groups the sidebar draws. A folder or scratch group exists only for its sessions, so
    /// with all of them pinned it has nothing to show. A project the user made always stays.
    var sidebarProjects: [Project] {
        orderedProjects.filter { !$0.isAutomatic || !unpinnedSessions(in: $0.id).isEmpty }
    }

    /// Every session in the sidebar's order, pinned ones first: ⌘1…9 and ⌃Tab count these.
    var sidebarSessions: [Session] {
        pinnedSessions + sidebarProjects.flatMap { unpinnedSessions(in: $0.id) }
    }

    /// Pins or unpins `id`. A session on screen is never out of sight in the sidebar, so if its
    /// new place is folded, that place opens. One that isn't on screen goes in folded.
    mutating func setPin(_ id: Session.ID, _ pinned: Bool, at date: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        guard (sessions[index].pinnedAt != nil) != pinned else { return }
        sessions[index].pinnedAt = pinned ? date : nil
        if selectedLayout?.tree.contains(id) == true {
            reveal(id)
        }
    }
}
