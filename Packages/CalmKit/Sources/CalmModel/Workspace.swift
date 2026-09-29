import Foundation

/// A group of sessions in the sidebar (FEATURES.md → F2): a project the user made, a folder
/// sessions happen to be in, or the scratch sessions.
public struct Project: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Made by the user; sessions started in it stay in it.
        case project
        /// Where sessions are: a git repository's root, else a folder. Removed when empty.
        case directory
        /// The scratch sessions (⌘⇧N), each in a hidden folder of its own. Removed when empty.
        case scratch
    }

    public let id: UUID
    /// Absolute, standardized path without a trailing slash.
    public var path: String
    public var name: String
    public var kind: Kind
    public var isCollapsed: Bool
    /// Set when the user clicked the project's mark for another one (an easter egg); nil keeps
    /// the mark its name gives.
    public var markSeed: UInt64?

    /// Made by grouping rather than by the user, so removed again when empty.
    public var isAutomatic: Bool {
        kind != .project
    }

    public init(id: UUID = UUID(), path: String, name: String? = nil, kind: Kind = .project, isCollapsed: Bool = false) {
        self.id = id
        self.path = WorkspacePath.standardize(path)
        self.name = name ?? (kind == .scratch ? "Scratch" : WorkspacePath.displayName(for: self.path))
        self.kind = kind
        self.isCollapsed = isCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case id, path, name, kind, isAutomatic, isCollapsed, markSeed
    }

    /// State files before kinds had `isAutomatic`: automatic projects were directory groups.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        path = try container.decode(String.self, forKey: .path)
        name = try container.decode(String.self, forKey: .name)
        isCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isCollapsed) ?? false
        markSeed = try container.decodeIfPresent(UInt64.self, forKey: .markSeed)
        if let kind = try container.decodeIfPresent(Kind.self, forKey: .kind) {
            self.kind = kind
        } else {
            kind = try container.decodeIfPresent(Bool.self, forKey: .isAutomatic) == true ? .directory : .project
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(path, forKey: .path)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(isAutomatic, forKey: .isAutomatic) // still read by older builds
        try container.encode(isCollapsed, forKey: .isCollapsed)
        try container.encodeIfPresent(markSeed, forKey: .markSeed)
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
    /// When a report last changed `state` ("Working · 4m"); nil in older state files.
    public var stateSince: Date?
    /// The latest report behind `state` (optional so older state files still load).
    public var lastReport: StatusReport?
    /// The agent in the foreground, if one is running.
    public var agent: AgentRun?
    public var createdAt: Date
    /// A name the user gave the session (FEATURES.md → F12); wins over every other title.
    public var customName: String?
    /// The agent conversation that last ran here, kept after the agent exits so it can be resumed.
    public var lastConversation: AgentConversation?
    /// A scratch session's own folder (⌘⇧N). Calm never shows it.
    public var scratchFolder: String?

    public var isScratch: Bool {
        scratchFolder != nil
    }

    /// Shells the agent's turn left running, while the card says *done* ("Done · 2 shells
    /// running"); none once it has moved on to another state or been settled by a visit.
    public var shellsStillRunning: Int {
        guard state == .done, lastReport?.source == .hook else { return 0 }
        return lastReport?.backgroundShells ?? 0
    }

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

    /// The user's name for the session, else the shell's title, else the folder. A scratch
    /// session is "Scratch · 14:32" instead: its folder (and a shell title naming it) stays hidden.
    public var displayTitle: String {
        if let customName {
            return customName
        }
        if isScratch {
            return scratchLabel
        }
        let title = Self.shellTitle(title)
        return title.isEmpty ? WorkspacePath.displayName(for: workingDirectory) : title
    }

    /// A shell title without the status glyph an agent puts in front of it: Claude Code shows
    /// "✳" when idle and a turning half circle ("◐◓◑◒") or braille dots while working. The
    /// card already shows the state, and a glyph that turns would make the title flicker.
    public static func shellTitle(_ raw: String) -> String {
        var title = Substring(raw)
        while let first = title.unicodeScalars.first, isStatusGlyph(first) {
            title = Substring(title.unicodeScalars.dropFirst()).drop(while: \.isWhitespace)
        }
        return String(title)
    }

    private static func isStatusGlyph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2733, 0x25D0 ... 0x25D3, 0x2800 ... 0x28FF: true // ✳, ◐◓◑◒, braille
        default: false
        }
    }

    /// "Scratch · 14:32", or with the day for an older one.
    public var scratchLabel: String {
        let format: Date.FormatStyle = Calendar.current.isDateInToday(createdAt)
            ? .dateTime.hour().minute()
            : .dateTime.month(.abbreviated).day()
        return "Scratch · " + createdAt.formatted(format)
    }

    /// The title a card shows: the user's name, else the agent's own title for its conversation.
    public func title(agentTitle: String?) -> String {
        customName ?? agentTitle.flatMap { $0.isEmpty ? nil : $0 } ?? displayTitle
    }

    /// Where the work happens: the running agent's own folder when its transcript says (Claude Code
    /// can move into a git worktree while its shell stays in the main checkout), else the shell's.
    /// Only what depends on the checkout uses it; the session's folder, project and title stay the shell's.
    public var activeDirectory: String {
        agent?.tail?.directory.map(WorkspacePath.standardize) ?? workingDirectory
    }

    /// What the title strip above the terminal shows (UIUX.md → Title bar): the session's title
    /// and the folder it's in. The title is left out when it only repeats the folder (a
    /// plain shell titled "~" or "calm"); a scratch session shows no folder, as everywhere else.
    public func titleStrip(agentTitle: String?, home: String = NSHomeDirectory()) -> (folder: String?, title: String?) {
        let title = title(agentTitle: agentTitle)
        if isScratch {
            return (nil, title)
        }
        let folder = WorkspacePath.abbreviated(workingDirectory, home: home)
        return (folder, repeatsFolder(title, folder: folder) ? nil : title)
    }

    /// Whether a title only names the folder: its path, its name, or a prompt's shortened path
    /// ("…/apps/calm").
    private func repeatsFolder(_ title: String, folder: String) -> Bool {
        if title.isEmpty || title == folder || title == WorkspacePath.displayName(for: workingDirectory)
            || WorkspacePath.standardize(title) == workingDirectory {
            return true
        }
        for ellipsis in ["…", "..."] where title.hasPrefix(ellipsis) {
            let tail = title.dropFirst(ellipsis.count)
            if tail.hasPrefix("/"), workingDirectory.hasSuffix(tail) {
                return true
            }
        }
        return false
    }

    /// The conversation that can be forked: the running agent's, else the last one.
    public var conversation: AgentConversation? {
        agent?.conversation ?? lastConversation
    }

    /// An agent conversation that ended here and can be resumed in place.
    public var resumableConversation: AgentConversation? {
        agent == nil ? lastConversation : nil
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
    /// The text size, in points, that every session shows after ⌘+ or ⌘−; nil means the
    /// config's `font-size` (FEATURES.md → F1).
    public var fontSize: Float?
    /// True when the window was last left filling the screen (Zoom, Fill or a window manager's
    /// maximize), nil otherwise. The size it had before is the window frame AppKit autosaves,
    /// which stays at the windowed size while the window is zoomed (FEATURES.md → F1).
    public var windowFilled: Bool?
    /// True when the window was last left in full screen, nil otherwise. Kept apart from
    /// `windowFilled`: the window under full screen may be filled too, and leaving full screen
    /// goes back to it (FEATURES.md → F1).
    public var windowFullScreen: Bool?

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

    /// The layout on screen. Nil while none is chosen: closing the session you're in leaves the
    /// choice to you, so no session takes its place.
    public var selectedLayout: PaneLayout? {
        layouts.first { $0.id == selectedLayoutID }
    }

    /// The sidebar's order (UIUX.md → Layout): scratch sessions on top, then the projects the user
    /// made, then the directory groups, each in the order they appeared.
    public var orderedProjects: [Project] {
        let rank: (Project.Kind) -> Int = { kind in
            switch kind {
            case .scratch: 0
            case .project: 1
            case .directory: 2
            }
        }
        return projects.enumerated()
            .sorted { (rank($0.element.kind), $0.offset) < (rank($1.element.kind), $1.offset) }
            .map(\.element)
    }

    /// The projects the user made, in the sidebar's order, sessions or none: what the welcome page
    /// offers a new session in (folder and scratch groups go with their last session).
    public var madeProjects: [Project] {
        orderedProjects.filter { $0.kind == .project }
    }

    // MARK: Projects

    /// Adds a project for `path`, or returns the existing one; a directory group there becomes
    /// the project. Sessions inside it are refiled.
    @discardableResult
    public mutating func addProject(path: String, name: String? = nil, gitRoot: (String) -> String? = { _ in nil }) -> Project {
        let standardized = WorkspacePath.standardize(path)
        if let index = projects.firstIndex(where: { $0.path == standardized && $0.kind != .scratch }) {
            projects[index].kind = .project
            if let name {
                projects[index].name = name
            }
            return projects[index]
        }
        let project = Project(path: standardized, name: name)
        // Directory groups never sit inside a project the user made: absorb them.
        let absorbed = Set(projects.filter { $0.kind == .directory && project.contains($0.path) }.map(\.id))
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

    /// A directory group becomes a project (the group's "Make Project"): it stays when empty, and
    /// its sessions stay in it.
    public mutating func makeProject(_ projectID: Project.ID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }), projects[index].kind == .directory else { return }
        projects[index].kind = .project
        for session in sessions where session.projectID == projectID {
            setPinned(session.id, true)
        }
    }

    /// A project the user made goes away (its "Remove Project"), undoing "Make Project": its
    /// sessions stay open and group by their folders again. Nothing on disk is touched.
    public mutating func removeProject(_ projectID: Project.ID, gitRoot: (String) -> String? = { _ in nil }) {
        guard project(projectID)?.kind == .project else { return }
        let members = sessions.filter { $0.projectID == projectID }.map(\.id)
        projects.removeAll { $0.id == projectID }
        for id in members {
            setPinned(id, false)
            refile(id, gitRoot: gitRoot)
        }
    }

    public mutating func setCollapsed(_ projectID: Project.ID, _ collapsed: Bool) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].isCollapsed = collapsed
    }

    /// Gives a project the mark `seed` makes instead of the one its name gives.
    public mutating func setMarkSeed(_ projectID: Project.ID, _ seed: UInt64) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[index].markSeed = seed
    }

    // MARK: Sessions

    /// Where a new session goes (FEATURES.md → F2).
    public enum Placement: Hashable, Sendable {
        /// Grouped by its folder, moving when the folder changes.
        case directory
        /// In a project the user made, staying there.
        case project(Project.ID)
        /// A scratch session in its own folder (`directory`), on top of the sidebar.
        case scratch
    }

    /// Creates a session in `directory`, placed as asked, in a new layout of its own.
    @discardableResult
    public mutating func newSession(
        in directory: String,
        placement: Placement = .directory,
        gitRoot: (String) -> String? = { _ in nil },
    ) -> Session {
        if let left = selectedLayout?.focusedSessionID {
            settle(left)
        }
        let session = makeSession(in: directory, placement: placement, gitRoot: gitRoot)
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
        placement: Placement = .directory,
        gitRoot: (String) -> String? = { _ in nil },
    ) -> Session? {
        guard let layoutIndex = layouts.firstIndex(where: { $0.tree.contains(existing) }) else { return nil }
        settle(layouts[layoutIndex].focusedSessionID)
        let session = makeSession(in: directory, placement: placement, gitRoot: gitRoot)
        sessions.append(session)
        layouts[layoutIndex].tree = layouts[layoutIndex].tree.splitting(existing, direction: direction, with: session.id)
        layouts[layoutIndex].focusedSessionID = session.id
        return session
    }

    private mutating func makeSession(in directory: String, placement: Placement, gitRoot: (String) -> String?) -> Session {
        switch placement {
        case .directory:
            return Session(projectID: projectForFiling(directory, gitRoot: gitRoot).id, workingDirectory: directory)
        case let .project(projectID):
            guard project(projectID) != nil else { return makeSession(in: directory, placement: .directory, gitRoot: gitRoot) }
            return Session(projectID: projectID, workingDirectory: directory, isPinned: true)
        case .scratch:
            var session = Session(projectID: scratchGroup(inside: directory).id, workingDirectory: directory, isPinned: true)
            session.scratchFolder = WorkspacePath.standardize(directory)
            return session
        }
    }

    /// The one scratch group, made when the first scratch session appears.
    private mutating func scratchGroup(inside folder: String) -> Project {
        if let group = projects.first(where: { $0.kind == .scratch }) {
            return group
        }
        let group = Project(path: (WorkspacePath.standardize(folder) as NSString).deletingLastPathComponent, kind: .scratch)
        projects.append(group)
        return group
    }

    /// The placement a session opened from `id` (⌘T, a split) inherits: a project session's
    /// project; everything else by folder (scratch sessions come only from ⌘⇧N).
    public func inheritedPlacement(from id: Session.ID?) -> Placement {
        guard let session = id.flatMap(session), let project = project(session.projectID),
              project.kind == .project, session.isPinned else { return .directory }
        return .project(project.id)
    }

    /// Moves a session into a project the user made, where it stays.
    public mutating func move(_ id: Session.ID, to projectID: Project.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), project(projectID)?.kind == .project else { return }
        let previous = sessions[index].projectID
        sessions[index].projectID = projectID
        sessions[index].isPinned = true
        pruneAutomaticProject(previous)
    }

    /// A project session starts following its folder, like any other (its "Let It Follow Its Folder").
    public mutating func followFolder(_ id: Session.ID, gitRoot: (String) -> String? = { _ in nil }) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), !sessions[index].isScratch else { return }
        sessions[index].isPinned = false
        refile(id, gitRoot: gitRoot)
    }

    /// A scratch session whose folder moved to `path` becomes a project there (its "Keep as Project…").
    public mutating func keepScratchAsProject(_ id: Session.ID, at path: String, gitRoot: (String) -> String? = { _ in nil }) {
        guard let index = sessions.firstIndex(where: { $0.id == id }), sessions[index].isScratch else { return }
        let previous = sessions[index].projectID
        sessions[index].scratchFolder = nil
        sessions[index].workingDirectory = WorkspacePath.standardize(path)
        let project = addProject(path: path, gitRoot: gitRoot)
        sessions[index].projectID = project.id
        sessions[index].isPinned = true
        pruneAutomaticProject(previous)
    }

    /// Files every session that follows its folder again, under today's rules (at launch).
    public mutating func refileAll(gitRoot: (String) -> String? = { _ in nil }) {
        for session in sessions {
            refile(session.id, gitRoot: gitRoot)
        }
        for project in projects where project.isAutomatic {
            pruneAutomaticProject(project.id)
        }
    }

    /// Removes a session everywhere: from its layout (the sibling takes the space), and its
    /// group if that was automatic and is now empty.
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
                    selectedLayoutID = nil
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
        sessions[index].title = Session.shellTitle(title)
    }

    public mutating func setState(_ id: Session.ID, _ state: SessionState) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = state
    }

    /// Selects the layout that shows `sessionID` and focuses the session in it. The session
    /// being left settles: a finished one stays *done* while you read it, and goes quiet once
    /// you move on.
    public mutating func select(_ sessionID: Session.ID) {
        guard let index = layouts.firstIndex(where: { $0.tree.contains(sessionID) }) else { return }
        if let left = selectedLayout?.focusedSessionID, left != sessionID {
            settle(left)
        }
        layouts[index].focusedSessionID = sessionID
        selectedLayoutID = layouts[index].id
    }

    /// The user has seen a session and moved on (to another session, or away from Calm).
    public mutating func settle(_ id: Session.ID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].state = sessions[index].state.afterVisit()
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

    /// The group a session in `directory` belongs to: the most specific project the user made
    /// that contains it, else the directory group of its git repository's root, or of the folder
    /// itself outside a repository (made if needed). A directory group holds only its own
    /// repository or folder, so one made for the home folder doesn't swallow everything under it.
    mutating func projectForFiling(_ directory: String, gitRoot: (String) -> String?) -> Project {
        let folder = WorkspacePath.standardize(directory)
        if let project = projects.filter({ $0.kind == .project && $0.contains(folder) }).max(by: { $0.path.count < $1.path.count }) {
            return project
        }
        let key = gitRoot(folder).map(WorkspacePath.standardize) ?? folder
        if let group = projects.first(where: { $0.kind == .directory && $0.path == key }) {
            return group
        }
        let group = Project(path: key, kind: .directory)
        projects.append(group)
        return group
    }

    private mutating func pruneAutomaticProject(_ projectID: Project.ID) {
        guard let project = project(projectID), project.isAutomatic, sessions(in: projectID).isEmpty else { return }
        projects.removeAll { $0.id == projectID }
    }
}

// MARK: Text size

public extension Workspace {
    /// Records the text size a pane now shows (`configured` is the config's `font-size`, which
    /// is stored as nil). Returns whether the shared size changed, so the other panes should follow.
    mutating func noteFontSize(_ points: Float, configured: Float?) -> Bool {
        let isConfigured = configured.map { abs(points - $0) < 0.01 } ?? false
        let size = isConfigured ? nil : points
        guard size != fontSize else { return false }
        fontSize = size
        return true
    }
}

// MARK: Window

public extension Workspace {
    /// Records whether the window now fills the screen (false is stored as nil). Returns whether
    /// that changed, so callers save only then: a resize reports this on every step.
    mutating func noteWindowFilled(_ filled: Bool) -> Bool {
        let value = filled ? true : nil
        guard value != windowFilled else { return false }
        windowFilled = value
        return true
    }

    /// Records whether the window is now in full screen (false is stored as nil). Returns
    /// whether that changed.
    mutating func noteWindowFullScreen(_ fullScreen: Bool) -> Bool {
        let value = fullScreen ? true : nil
        guard value != windowFullScreen else { return false }
        windowFullScreen = value
        return true
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

    /// A folder with the home folder written as "~": "~/dev/calm", "/opt/tools".
    public static func abbreviated(_ path: String, home: String = NSHomeDirectory()) -> String {
        let path = standardize(path)
        let home = standardize(home)
        guard home != "/", isInside(path, folder: home) else { return path }
        return "~" + path.dropFirst(home.count)
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
