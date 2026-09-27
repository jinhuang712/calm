@testable import CalmModel
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
}
