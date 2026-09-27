@testable import CalmModel
import Testing

struct SplitTreeTests {
    typealias Tree = SplitTree<String>

    @Test func `split right places the new pane after the target`() {
        let tree = Tree.leaf("a").splitting("a", direction: .right, with: "b")
        #expect(tree == .split(.horizontal, ratio: 0.5, first: .leaf("a"), second: .leaf("b")))
        #expect(tree.leaves == ["a", "b"])
    }

    @Test func `split up places the new pane before the target`() {
        let tree = Tree.leaf("a").splitting("a", direction: .up, with: "b")
        #expect(tree == .split(.vertical, ratio: 0.5, first: .leaf("b"), second: .leaf("a")))
    }

    @Test func `splitting an unknown pane changes nothing`() {
        let tree = Tree.leaf("a")
        #expect(tree.splitting("zzz", direction: .right, with: "b") == tree)
    }

    @Test func `removing a pane lets its sibling take the space`() {
        let tree = Tree.leaf("a")
            .splitting("a", direction: .right, with: "b")
            .splitting("b", direction: .down, with: "c")
        #expect(tree.removing("b") == .split(.horizontal, ratio: 0.5, first: .leaf("a"), second: .leaf("c")))
        #expect(tree.removing("a") == .split(.vertical, ratio: 0.5, first: .leaf("b"), second: .leaf("c")))
    }

    @Test func `removing the last pane empties the tree`() {
        #expect(Tree.leaf("a").removing("a") == nil)
    }

    @Test func `frames divide the area by ratio`() {
        let tree = Tree.split(.horizontal, ratio: 0.25, first: .leaf("a"), second: .leaf("b"))
        let frames = tree.frames()
        #expect(frames["a"] == .init(x: 0, y: 0, width: 0.25, height: 1))
        #expect(frames["b"] == .init(x: 0.25, y: 0, width: 0.75, height: 1))
    }

    @Test func `ratios are clamped so no pane collapses`() {
        let tree = Tree.leaf("a").splitting("a", direction: .right, with: "b")
        let tiny = tree.settingRatio(0.01, forSplitContaining: "a")
        let huge = tree.settingRatio(5, forSplitContaining: "b")
        #expect(tiny == .split(.horizontal, ratio: Tree.minimumRatio, first: .leaf("a"), second: .leaf("b")))
        #expect(huge == .split(.horizontal, ratio: 1 - Tree.minimumRatio, first: .leaf("a"), second: .leaf("b")))
    }

    @Test func `equalize resets every ratio`() {
        let tree = Tree.split(
            .horizontal,
            ratio: 0.8,
            first: .leaf("a"),
            second: .split(.vertical, ratio: 0.2, first: .leaf("b"), second: .leaf("c")),
        )
        #expect(tree.equalized() == .split(
            .horizontal,
            ratio: 0.5,
            first: .leaf("a"),
            second: .split(.vertical, ratio: 0.5, first: .leaf("b"), second: .leaf("c")),
        ))
    }

    /// Layout used below:
    /// ┌───┬───┐
    /// │ a │ b │
    /// │   ├───┤
    /// │   │ c │
    /// └───┴───┘
    @Test func `neighbors follow the visual layout`() {
        let tree = Tree.leaf("a")
            .splitting("a", direction: .right, with: "b")
            .splitting("b", direction: .down, with: "c")
        #expect(tree.neighbor(of: "a", toward: .right) != nil)
        #expect(tree.neighbor(of: "b", toward: .down) == "c")
        #expect(tree.neighbor(of: "c", toward: .up) == "b")
        #expect(tree.neighbor(of: "c", toward: .left) == "a")
        #expect(tree.neighbor(of: "b", toward: .left) == "a")
        #expect(tree.neighbor(of: "a", toward: .left) == nil)
        #expect(tree.neighbor(of: "c", toward: .down) == nil)
    }
}
