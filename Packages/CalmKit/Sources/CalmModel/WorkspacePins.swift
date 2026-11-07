import Foundation

extension Session {
    /// Where the state puts a pinned card: needs you, failed, done, working, idle.
    var pinnedRank: Int {
        switch state {
        case .needsYou: 0
        case .failed: 1
        case .done: 2
        case .working: 3
        case .idle: 4
        }
    }

    /// When the state last changed, else when the session was pinned.
    var pinnedActivity: Date {
        stateSince ?? pinnedAt ?? .distantPast
    }
}

public extension Session {
    /// The size this card is drawn at, of the two `TieredCardFit` keeps.
    func cardSize(
        others: CalmSettings.SessionCardSize, pinned: CalmSettings.SessionCardSize,
    ) -> CalmSettings.SessionCardSize {
        pinnedAt == nil ? others : pinned
    }
}

/// Sessions the user pinned to the top of the sidebar (specs/FEATURES.md → F2). A pin is
/// `Session.pinnedAt`, which has nothing to do with `Session.isPinned` (a session that stays in its
/// project). It places the card and nothing else: the session keeps its project, and closing it
/// ends the pin, because a closed session is found again through search and the project's home.
public extension Workspace {
    /// The pinned sessions, what wants the user first and the latest change first within a state.
    /// The one place rows reorder when states change (specs/FEATURES.md → F2).
    var pinnedSessions: [Session] {
        sessions.filter { $0.pinnedAt != nil }.sorted { first, second in
            if first.pinnedRank != second.pinnedRank {
                return first.pinnedRank < second.pinnedRank
            }
            if first.pinnedActivity != second.pinnedActivity {
                return first.pinnedActivity > second.pinnedActivity
            }
            return first.id.uuidString < second.id.uuidString
        }
    }

    /// `pinnedSessions` kept in `order` while the pointer holds it still. A session pinned since
    /// goes last, and one that left is dropped.
    func pinnedSessions(heldIn order: [Session.ID]?) -> [Session] {
        let sorted = pinnedSessions
        guard let order else { return sorted }
        let held = order.compactMap { id in sorted.first { $0.id == id } }
        return held + sorted.filter { !order.contains($0.id) }
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

    /// Every session in the sidebar's order, pinned ones first: ⌘1…9 and ⌃Tab count these, so
    /// a number always means the place on screen.
    func sidebarSessions(heldIn order: [Session.ID]? = nil) -> [Session] {
        pinnedSessions(heldIn: order) + sidebarProjects.flatMap { unpinnedSessions(in: $0.id) }
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
