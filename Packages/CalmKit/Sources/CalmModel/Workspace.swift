import Foundation

/// A folder the user works in. Sessions file themselves under the project that contains
/// their working directory (see FEATURES.md → F2).
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Absolute, standardized path without a trailing slash.
    public var path: String
    public var name: String
    /// Created by auto-grouping rather than by the user; removed again when empty.
    public var isAutomatic: Bool
    public var isCollapsed: Bool

    public init(id: UUID = UUID(), path: String, name: String? = nil, isAutomatic: Bool = false, isCollapsed: Bool = false) {
        self.id = id
        self.path = WorkspacePath.standardize(path)
        self.name = name ?? WorkspacePath.displayName(for: self.path)
        self.isAutomatic = isAutomatic
        self.isCollapsed = isCollapsed
    }

    /// Whether `directory` is this project's folder or inside it.
    public func contains(_ directory: String) -> Bool {
        WorkspacePath.isInside(WorkspacePath.standardize(directory), folder: path)
    }
}

/// One terminal: a shell, possibly running an agent.
public struct Session: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var projectID: Project.ID
    public var title: String
    public var workingDirectory: String
    /// Pinned sessions stay in their project when their folder changes.
    public var isPinned: Bool
    public var state: SessionState
    /// The latest report behind `state` (optional so older state files still load).
    public var lastReport: StatusReport?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        projectID: Project.ID,
        title: String = "",
        workingDirectory: String,
        isPinned: Bool = false,
        state: SessionState = .idle,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.workingDirectory = WorkspacePath.standardize(workingDirectory)
        self.isPinned = isPinned
        self.state = state
        self.createdAt = createdAt
    }

    /// Name of the persistent (zmx) session that keeps this shell alive across quits.
    /// Short on purpose: zmx creates a Unix socket named after it, and socket paths are length-limited.
    public var persistentName: String {
        "calm-" + id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(12)
    }

    /// A readable label when the shell hasn't set a title yet.
    public var displayTitle: String {
        title.isEmpty ? WorkspacePath.displayName(for: workingDirectory) : title
    }
}

/// How sessions are arranged on screen: one split tree per "stack". The main area shows
/// one layout at a time; picking a session in the sidebar shows the layout it lives in.
public struct PaneLayout: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var tree: SplitTree<Session.ID>
    public var focusedSessionID: Session.ID

    public init(id: UUID = UUID(), tree: SplitTree<Session.ID>, focusedSessionID: Session.ID) {
        self.id = id
        self.tree = tree
        self.focusedSessionID = focusedSessionID
    }
}

/// Everything the sidebar and main area show, as one value that can be saved and restored.
public struct Workspace: Codable, Hashable, Sendable {
    public var projects: [Project] = []
    public var sessions: [Session] = []
    public var layouts: [PaneLayout] = []
    public var selectedLayoutID: PaneLayout.ID?

    public init() {}

    // MARK: Queries

    public func session(_ id: Session.ID) -> Session? {
        sessions.first { $0.id == id }
    }

    public func project(_ id: Project.ID) -> Project? {
        projects.first { $0.id == id }
    }

    /// The most specific project containing `directory`.
    public func project(containing directory: String) -> Project? {
        projects
            .filter { $0.contains(directory) }
            .max { $0.path.count < $1.path.count }
    }

    /// Sessions of a project, oldest first (sidebar order never jumps).
    public func sessions(in projectID: Project.ID) -> [Session] {
        sessions.filter { $0.projectID == projectID }.sorted { $0.createdAt < $1.createdAt }
    }

    public func layout(containing sessionID: Session.ID) -> PaneLayout? {
        layouts.first { $0.tree.contains(sessionID) }
    }

    public var selectedLayout: PaneLayout? {
        layouts.first { $0.id == selectedLayoutID } ?? layouts.first
    }

    // MARK: Projects

    /// Adds a project for `path`, or returns the existing one. A user-added project stops
    /// being automatic. Sessions inside it are refiled.
    @discardableResult
    public mutating func addProject(path: String, name: String? = nil, gitRoot: (String) -> String? = { _ in nil }) -> Project {
        let standardized = WorkspacePath.standardize(path)
        if let index = projects.firstIndex(where: { $0.path == standardized }) {
            projects[index].isAutomatic = false
            if let name {
                projects[index].name = name
            }
            return projects[index]
        }
        let project = Project(path: standardized, name: name)
        // Automatic projects never sit inside one the user added: absorb them.
        let absorbed = Set(projects.filter { $0.isAutomatic && project.contains($0.path) }.map(\.id))
        projects.removeAll { absorbed.contains($0.id) }
        projects.append(project)
        for session in sessions {
            if absorbed.contains(session.projectID) {
                if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                    sessions[index].projectID = project.id
                }
            }
            refile(session.id, gitRoot: gitRoot)
        }
        return project
    }

    public mutating func setCollapsed(_ projectID: Project.ID, _ collapsed: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].isCollapsed = collapsed
    }

    // MARK: Sessions

    /// Creates a session in `directory`, filed under the right project, in a new layout of its own.
    @discardableResult
    public mutating func newSession(in directory: String, gitRoot: (String) -> String? = { _ in nil }) -> Session {
        let project = projectForFiling(directory, gitRoot: gitRoot)
        let session = Session(projectID: project.id, workingDirectory: directory)
        sessions.append(session)
        let layout = PaneLayout(tree: .leaf(session.id), focusedSessionID: session.id)
        layouts.append(layout)
        selectedLayoutID = layout.id
        return session
    }

    /// Creates a session next to `existing`, in the same layout.
    @discardableResult
    public mutating func splitSession(
        _ existing: Session.ID,
        direction: SplitTree<Session.ID>.Direction,
        in directory: String,
        gitRoot: (String) -> String? = { _ in nil },
    ) -> Session? {
        guard let layoutIndex = layouts.firstIndex(where: { $0.tree.contains(existing) }) else { return nil }
        let project = projectForFiling(directory, gitRoot: gitRoot)
        let session = Session(projectID: project.id, workingDirectory: directory)
        sessions.append(session)
        layouts[layoutIndex].tree = layouts[layoutIndex].tree.splitting(existing, direction: direction, with: session.id)
        layouts[layoutIndex].focusedSessionID = session.id
        return session
    }

    /// Removes a session everywhere: from its layout (the sibling takes the space), and its
    /// project if that was automatic and is now empty.
    public mutating func removeSession(_ id: Session.ID) {
        guard let session = session(id) else { return }
        sessions.removeAll { $0.id == id }
        if let layoutIndex = layouts.firstIndex(where: { $0.tree.contains(id) }) {
            if let remaining = layouts[layoutIndex].tree.removing(id) {
                layouts[layoutIndex].tree = remaining
                if layouts[layoutIndex].focusedSessionID == id, let first = remaining.leaves.first {
                    layouts[layoutIndex].focusedSessionID = first
                }
            } else {
                let removedID = layouts[layoutIndex].id
                layouts.remove(at: layoutIndex)
                if selectedLayoutID == removedID {
                    selectedLayoutID = layouts.last?.id
                }
            }
        }
        pruneAutomaticProject(session.projectID)
    }

    /// Records a new working directory and refiles the session if needed.
    /// Returns true when the session moved to another project.
    @discardableResult
    public mutating func updateWorkingDirectory(
        _ id: Session.ID,
        to directory: String,
        gitRoot: (String) -> String? = { _ in nil },
    ) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return false }
        sessions[index].workingDirectory = WorkspacePath.standardize(directory)
        return refile(id, gitRoot: gitRoot)
    }

    public mutating func setPinned(_ id: Session.ID, _ pinned: Bool) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].isPinned = pinned
    }

    public mutating func setTitle(_ id: Session.ID, _ title: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].title = title
    }

    public mutating func setState(_ id: Session.ID, _ state: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = state
    }

    /// Selects the layout that shows `sessionID` and focuses the session in it.
    public mutating func select(_ sessionID: Session.ID) {
        guard let index = layouts.firstIndex(where: { $0.tree.contains(sessionID) }) else { return }
        layouts[index].focusedSessionID = sessionID
        selectedLayoutID = layouts[index].id
        if let sessionIndex = sessions.firstIndex(where: { $0.id == sessionID }) {
            sessions[sessionIndex].state = sessions[sessionIndex].state.afterVisit()
        }
    }

    public mutating func updateTree(_ layoutID: PaneLayout.ID, _ tree: SplitTree<Session.ID>) {
        guard let index = layouts.firstIndex(where: { $0.id == layoutID }) else { return }
        layouts[index].tree = tree
    }

    // MARK: Filing

    /// Moves a session to the project its folder belongs to, unless it's pinned.
    @discardableResult
    mutating func refile(_ id: Session.ID, gitRoot: (String) -> String?) -> Bool {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !sessions[index].isPinned else { return false }
        let previous = sessions[index].projectID
        let target = projectForFiling(sessions[index].workingDirectory, gitRoot: gitRoot)
        guard target.id != previous else { return false }
        sessions[index].projectID = target.id
        pruneAutomaticProject(previous)
        return true
    }

    /// The project a session in `directory` belongs to, creating an automatic one if needed:
    /// the git repository root when there is one, otherwise the folder itself.
    mutating func projectForFiling(_ directory: String, gitRoot: (String) -> String?) -> Project {
        let folder = WorkspacePath.standardize(directory)
        let repository = gitRoot(folder).map(WorkspacePath.standardize)
        if let existing = project(containing: folder) {
            // A repository inside an *automatic* project (like the home folder) gets its own
            // project; projects the user added keep everything inside them.
            guard existing.isAutomatic, let repository, repository != existing.path,
                  WorkspacePath.isInside(repository, folder: existing.path)
            else { return existing }
            if let repoProject = projects.first(where: { $0.path == repository }) {
                return repoProject
            }
            let project = Project(path: repository, isAutomatic: true)
            projects.append(project)
            return project
        }
        let root = repository ?? folder
        let project = Project(path: root, isAutomatic: true)
        projects.append(project)
        return project
    }

    private mutating func pruneAutomaticProject(_ projectID: Project.ID) {
        guard let project = project(projectID), project.isAutomatic, sessions(in: projectID).isEmpty else { return }
        projects.removeAll { $0.id == projectID }
    }
}

/// Path helpers shared by the model. Pure string operations: no file system access.
public enum WorkspacePath {
    public static func standardize(_ path: String) -> String {
        var result = (path as NSString).expandingTildeInPath
        result = (result as NSString).standardizingPath
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    public static func isInside(_ directory: String, folder: String) -> Bool {
        directory == folder || directory.hasPrefix(folder == "/" ? "/" : folder + "/")
    }

    public static func displayName(for path: String) -> String {
        let standardized = standardize(path)
        if standardized == standardize("~") {
            return "~"
        }
        let name = (standardized as NSString).lastPathComponent
        return name.isEmpty ? standardized : name
    }
}
