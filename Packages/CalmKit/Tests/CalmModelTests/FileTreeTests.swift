@testable import CalmModel
import Foundation
import Testing

struct FileTreeTests {
    @Test func `git status porcelain`() {
        let porcelain = " M Sources/App.swift\0A  docs/new.md\0?? notes.txt\0R  b.swift\0a.swift\0 D gone.txt\0MM both.swift\0"
        #expect(GitChange.parse(porcelain: porcelain) == [
            "Sources/App.swift": .modified,
            "docs/new.md": .added,
            "notes.txt": .untracked,
            "b.swift": .renamed,
            "gone.txt": .deleted,
            "both.swift": .modified,
        ])
        #expect(GitChange.parse(porcelain: "").isEmpty)
    }

    @Test func `a tree: folders first, natural order, changes marked up the tree`() {
        let paths = [
            "README.md",
            "Sources/App/main.swift",
            "Sources/App/View10.swift",
            "Sources/App/View2.swift",
            "docs/UIUX.md",
            "Package.swift",
        ]
        let tree = FileNode.tree(paths: paths, changes: ["docs/UIUX.md": .modified, "README.md": .added])
        #expect(tree.map(\.name) == ["docs", "Sources", "Package.swift", "README.md"])
        #expect(tree[0].change == .modified) // docs holds a change
        #expect(tree[1].change == nil)
        #expect(tree[3].change == .added)
        let app = tree[1].children?.first
        #expect(app?.path == "Sources/App")
        #expect(app?.children?.map(\.name) == ["main.swift", "View2.swift", "View10.swift"])
        #expect(app?.children?.allSatisfy { !$0.isFolder } == true)
    }

    @Test func `git diff numstat: counts by path, renames by their new path, binaries left out`() {
        let numstat = "1\t1\tREADME.md\0" + "2\t0\tAdded.md\0" + "0\t1\tgone.txt\0" + "-\t-\ticon.bin\0"
            + "1\t1\t\0src/Old.swift\0src/New.swift\0"
        #expect(LineCounts.parse(numstat: numstat) == [
            "README.md": LineCounts(added: 1, deleted: 1),
            "Added.md": LineCounts(added: 2, deleted: 0),
            "gone.txt": LineCounts(added: 0, deleted: 1),
            "src/New.swift": LineCounts(added: 1, deleted: 1),
        ])
        #expect(LineCounts.parse(numstat: "").isEmpty)
        #expect(LineCounts.parse(numstat: "garbage\0").isEmpty)
    }

    @Test func `a new file's lines are counted as git counts them`() {
        #expect(LineCounts.lines(in: Data("one\ntwo\n".utf8)) == 2)
        #expect(LineCounts.lines(in: Data("one\ntwo".utf8)) == 2) // no newline at the end
        #expect(LineCounts.lines(in: Data()) == 0)
        #expect(LineCounts.lines(in: Data([0x50, 0x4E, 0x47, 0x00, 0x0A])) == nil) // binary
    }

    @Test func `changes are listed by path in natural order, with their folder and lines`() {
        let changes: [String: GitChange] = ["UIUX.md": .modified, "Calm/View10.swift": .untracked, "Calm/View2.swift": .modified]
        let list = ChangedFile.list(changes: changes, lines: ["UIUX.md": LineCounts(added: 9, deleted: 4)])
        #expect(list.map(\.path) == ["Calm/View2.swift", "Calm/View10.swift", "UIUX.md"])
        #expect(list[0].name == "View2.swift")
        #expect(list[0].folder == "Calm")
        #expect(list[2].folder.isEmpty)
        #expect(ChangedFile(path: "Calm/Window/Files.swift", change: .modified).folderName == "Window")
        #expect(list[2].folderName.isEmpty)
        #expect(list[2].lines == LineCounts(added: 9, deleted: 4))
        #expect(list[0].lines == nil)
    }

    @Test func `the tree shows open folders' children, one level deeper`() {
        let tree = FileNode.tree(paths: ["Calm/Window/Files.swift", "Calm/App.swift", ".gitignore", "README.md"], changes: [:])
        #expect(FileNode.rows(tree, expanded: []).map(\.id) == ["Calm", ".gitignore", "README.md"])
        let open = FileNode.rows(tree, expanded: ["Calm", "Calm/Window"])
        #expect(open.map(\.id) == ["Calm", "Calm/Window", "Calm/Window/Files.swift", "Calm/App.swift", ".gitignore", "README.md"])
        #expect(open.map(\.depth) == [0, 1, 2, 1, 0, 0])
        // A folder inside a closed one stays hidden, even when it's open itself.
        #expect(FileNode.rows(tree, expanded: ["Calm/Window"]).map(\.id) == ["Calm", ".gitignore", "README.md"])
        #expect(open.first { $0.id == ".gitignore" }?.node.isHidden == true)
    }

    @Test func `an unread folder is an empty folder, until a listing reads it`() {
        let tree = FileNode.tree(paths: ["a.txt", "code/main.swift"], changes: [:], unread: ["Documents", "code/sub"])
        #expect(tree.map(\.name) == ["code", "Documents", "a.txt"])
        #expect(tree[1].isFolder)
        #expect(tree[1].children?.isEmpty == true)
        #expect(tree[0].children?.map(\.name) == ["sub", "main.swift"]) // nested, beside what was read
        #expect(FileNode.tree(paths: ["Documents/x.md"], changes: [:], unread: []).first?.children?.map(\.name) == ["x.md"])
    }

    @Test func `the guarded folders are Desktop, Documents and Downloads under home`() {
        #expect(GuardedFolders.paths(home: "/Users/me") == ["/Users/me/Desktop", "/Users/me/Documents", "/Users/me/Downloads"])
        #expect(GuardedFolders.paths(home: "/Users/me/") == GuardedFolders.paths(home: "/Users/me"))
    }
}
