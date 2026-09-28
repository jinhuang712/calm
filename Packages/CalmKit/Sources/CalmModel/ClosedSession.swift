import Foundation

/// What Calm keeps of a session that was closed, to open its like again (FEATURES.md → F12).
/// Closing ends the shell, so what comes back is the place, not the process: the folder, the
/// name, the project, the spot in the sidebar and, if an agent was running, its conversation.
public struct ClosedSession: Hashable, Sendable {
    public var workingDirectory: String
    public var customName: String?
    /// The project the user made that the session was staying in; nil when it followed its folder.
    public var projectID: Project.ID?
    /// Keeps the session's place among its siblings in the sidebar, which sorts by it.
    public var createdAt: Date
    /// The conversation of the agent that was running when the session closed. One that had
    /// already exited isn't started again.
    public var conversation: AgentConversation?

    /// Nil for a scratch session: closing removes its folder, so there's nothing to come back to.
    public init?(_ session: Session, in workspace: Workspace) {
        guard !session.isScratch else { return nil }
        workingDirectory = session.workingDirectory
        customName = session.customName
        projectID = session.isPinned && workspace.project(session.projectID)?.kind == .project ? session.projectID : nil
        createdAt = session.createdAt
        conversation = session.agent?.conversation
    }
}

/// The last few closed sessions, newest first out. Kept in memory: a relaunch starts clean.
public struct ClosedSessions: Sendable {
    public static let limit = 10

    private var items: [ClosedSession] = []

    public init() {}

    public var isEmpty: Bool {
        items.isEmpty
    }

    public mutating func push(_ closed: ClosedSession) {
        items.append(closed)
        if items.count > Self.limit {
            items.removeFirst(items.count - Self.limit)
        }
    }

    public mutating func pop() -> ClosedSession? {
        items.popLast()
    }
}

public extension Workspace {
    /// Opens a session like `closed` in `directory`, in a layout of its own, with its name and
    /// its old place in the sidebar. It goes back to its project unless that project is gone.
    @discardableResult
    mutating func reopen(_ closed: ClosedSession, in directory: String, gitRoot: (String) -> String? = { _ in nil }) -> Session {
        let placement: Placement = closed.projectID.map { .project($0) } ?? .directory
        let session = newSession(in: directory, placement: placement, gitRoot: gitRoot)
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return session }
        sessions[index].customName = closed.customName
        sessions[index].createdAt = closed.createdAt
        return sessions[index]
    }
}
