import CalmModel
import Foundation

/// A group ⌘K shows results under (UIUX.md → Search): the one the sidebar would put the
/// session in.
struct SearchGroup: Hashable, Sendable {
    enum Key: Hashable, Sendable {
        case project(Project.ID)
        case scratch
        /// A folder's own group: its git repository's root, or the folder itself.
        case folder(String)
        /// A session the index knows no folder for.
        case none
    }

    let key: Key
    /// What the header draws its mark and name from: the project, or one made to stand in for a
    /// folder or scratch group (never saved). Nil for `.none`.
    let project: Project?
    /// As the header shows it: a project's or scratch group's name, a folder's own ("~" for home).
    let name: String
}

/// Which group a folder's sessions go under: a snapshot of the projects you made, so the index
/// can ask from its own thread while it searches.
struct SearchGrouping: Sendable {
    private let projects: [Project]
    private let scratchRoot: String
    /// Where scratch folders are outside a self-test, which keeps its own: a test searching the
    /// real history still shows those sessions as Scratch.
    private let standardScratchRoot: String
    /// The group of the session you're in, shown first.
    let current: SearchGroup.Key?

    @MainActor
    init(workspace: Workspace) {
        projects = workspace.madeProjects
        scratchRoot = WorkspacePath.standardize(ScratchFolders.root.path)
        standardScratchRoot = WorkspacePath
            .standardize(ScratchFolders.standardRoot(home: FileManager.default.homeDirectoryForCurrentUser).path)
        let focused = workspace.selectedLayout
            .flatMap { workspace.session($0.focusedSessionID) }
            .flatMap { workspace.project($0.projectID) }
        switch focused?.kind {
        case .project?: current = focused.map { .project($0.id) }
        case .scratch?: current = .scratch
        case .directory?: current = focused.map { .folder($0.path) }
        case nil: current = nil
        }
    }

    /// The sidebar's rule (Workspace.projectForFiling): scratch folders in Scratch, else the most
    /// specific project you made that holds the folder, else the folder's repository or itself.
    func group(for directory: String?) -> SearchGroup {
        guard let directory, !directory.isEmpty else { return SearchGroup(key: .none, project: nil, name: "No folder") }
        let folder = WorkspacePath.standardize(directory)
        if WorkspacePath.isInside(folder, folder: scratchRoot) || WorkspacePath.isInside(folder, folder: standardScratchRoot) {
            return SearchGroup(key: .scratch, project: Project(path: scratchRoot, kind: .scratch), name: "Scratch")
        }
        if let project = projects.filter({ $0.contains(folder) }).max(by: { $0.path.count < $1.path.count }) {
            return SearchGroup(key: .project(project.id), project: project, name: project.name)
        }
        let root = GitRoot.find(folder).map(WorkspacePath.standardize) ?? folder
        return SearchGroup(key: .folder(root), project: Project(path: root, kind: .directory), name: WorkspacePath.displayName(for: root))
    }
}
