@testable import CalmModel
import Foundation
import Testing

struct UntrackedFoldersTests {
    /// What `git ls-files -o -z` prints for `count` files under `folder`.
    private func listing(_ folder: String, count: Int) -> Data {
        Data((1 ... count).map { "\(folder)/file\($0).js\0" }.joined().utf8)
    }

    @Test func `folders are the status entries that end in a slash`() {
        let changes = GitChange.parse(porcelain: "?? build/\0?? notes.txt\0 M App.swift\0?? tools/scripts/\0")
        #expect(UntrackedFolder.paths(in: changes) == ["build", "tools/scripts"])
        #expect(UntrackedFolder.paths(in: [:]).isEmpty)
    }

    @Test func `a small folder is listed file by file`() {
        let folder = UntrackedFolder.read(path: "docs", lsFiles: listing("docs", count: 3))
        #expect(folder.count == 3)
        #expect(folder.files == ["docs/file1.js", "docs/file2.js", "docs/file3.js"])
        #expect(!folder.isCollapsed)
    }

    @Test func `a folder with more files than the limit is counted, not listed`() {
        let limit = UntrackedFolder.limit
        let atLimit = UntrackedFolder.read(path: "dist", lsFiles: listing("dist", count: limit))
        #expect(!atLimit.isCollapsed)
        #expect(atLimit.files.count == limit)

        let over = UntrackedFolder.read(path: "dist", lsFiles: listing("dist", count: limit + 1))
        #expect(over.isCollapsed)
        #expect(over.count == limit + 1)
        #expect(over.files.isEmpty)
    }

    @Test func `the project folder itself is never one row`() {
        let folder = UntrackedFolder.read(path: "", lsFiles: listing("src", count: UntrackedFolder.limit + 5))
        #expect(!folder.isCollapsed)
        #expect(folder.files.count == UntrackedFolder.limit + 5)
    }

    @Test func `nothing found is nothing shown`() {
        let folder = UntrackedFolder.read(path: "gone", lsFiles: Data())
        #expect(folder == UntrackedFolder(path: "gone", count: 0, files: []))
        #expect(!folder.isCollapsed)
    }

    @Test func `merging swaps a folder's entry for its files, or for one entry when it is collapsed`() {
        var changes: [String: GitChange] = ["docs/": .untracked, "node_modules/": .untracked, "App.swift": .modified]
        let folders = [
            UntrackedFolder.read(path: "docs", lsFiles: listing("docs", count: 2)),
            UntrackedFolder.read(path: "node_modules", lsFiles: listing("node_modules", count: UntrackedFolder.limit + 1)),
        ]
        let collapsed = UntrackedFolder.merge(folders, into: &changes)
        #expect(changes == [
            "docs/file1.js": .untracked,
            "docs/file2.js": .untracked,
            "node_modules": .untracked,
            "App.swift": .modified,
        ])
        #expect(collapsed == ["node_modules": UntrackedFolder.limit + 1])
    }

    @Test func `a collapsed folder is one empty untracked folder in the tree, and one row in Changes`() {
        let collapsed = ["plugins/workbench": 57190]
        let changes: [String: GitChange] = ["plugins/workbench": .untracked]
        let tree = FileNode.tree(paths: ["plugins/README.md", "main.swift"], changes: changes, collapsed: collapsed)
        let plugins = tree.first
        #expect(plugins?.name == "plugins")
        #expect(plugins?.change == .modified) // the dot: something inside is untracked
        let workbench = plugins?.children?.first
        #expect(workbench?.path == "plugins/workbench")
        #expect(workbench?.isFolder == true)
        #expect(workbench?.children?.isEmpty == true)
        #expect(workbench?.change == .untracked)
        #expect(workbench?.unlisted == 57190)
        #expect(plugins?.children?.last?.unlisted == nil)

        let list = ChangedFile.list(changes: changes, lines: [:], collapsed: collapsed)
        #expect(list.count == 1)
        #expect(list.first?.files == 57190)
        #expect(list.first?.lines == nil)
        #expect(list.first?.folderName == "plugins")
    }

    @Test func `the readout counts the files in a collapsed folder`() {
        let changes: [String: GitChange] = ["App.swift": .modified, "dist": .untracked]
        let summary = ChangeSummary(changes: changes, lines: ["App.swift": LineCounts(added: 3, deleted: 1)], collapsed: ["dist": 900])
        #expect(summary?.count == 901)
        #expect(summary?.lines == LineCounts(added: 3, deleted: 1))
        #expect(ChangeSummary(changes: changes, lines: [:])?.count == 2)
    }
}
