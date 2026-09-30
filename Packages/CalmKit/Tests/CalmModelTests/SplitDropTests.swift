@testable import CalmModel
import Testing

/// Where a session dropped on a split would land, and which pane takes the room of one that leaves.
struct SplitDropTests {
    typealias Tree = SplitTree<String>

    /// ┌───┬───┐
    /// │ a │ b │
    /// │   ├───┤
    /// │   │ c │
    /// └───┴───┘
    private var tree: Tree {
        Tree.leaf("a")
            .splitting("a", direction: .right, with: "b")
            .splitting("b", direction: .down, with: "c")
    }

    // MARK: The edge a drop lands on

    @Test func `the nearest edge of the pane under the pointer is where it lands`() {
        // Left pane, 0.5 wide and 1 tall: near its left edge, near its right, near its top, near its bottom.
        #expect(tree.drop(at: 0.03, 0.5) == .init(target: "a", direction: .left))
        #expect(tree.drop(at: 0.47, 0.5) == .init(target: "a", direction: .right))
        #expect(tree.drop(at: 0.25, 0.04) == .init(target: "a", direction: .up))
        #expect(tree.drop(at: 0.25, 0.96) == .init(target: "a", direction: .down))
    }

    @Test func `each pane answers for its own area`() {
        // b is the top right quarter, c the bottom right.
        #expect(tree.drop(at: 0.75, 0.02) == .init(target: "b", direction: .up))
        #expect(tree.drop(at: 0.75, 0.48) == .init(target: "b", direction: .down))
        #expect(tree.drop(at: 0.75, 0.52) == .init(target: "c", direction: .up))
        #expect(tree.drop(at: 0.97, 0.75) == .init(target: "c", direction: .right))
    }

    @Test func `the middle of a pane takes nothing`() {
        #expect(tree.drop(at: 0.25, 0.5) == nil)
        #expect(tree.drop(at: 0.75, 0.25) == nil)
    }

    @Test func `a pane can't be dropped onto itself`() {
        #expect(tree.drop(at: 0.03, 0.5, excluding: "a") == nil)
        #expect(tree.drop(at: 0.03, 0.5, excluding: "b") == .init(target: "a", direction: .left))
    }

    @Test func `outside the area nothing lands`() {
        #expect(tree.drop(at: -0.1, 0.5) == nil)
        #expect(tree.drop(at: 0.5, 1.2) == nil)
    }

    @Test func `the landing is the half the new pane would take`() {
        let frame = Tree.Frame(x: 0.5, y: 0, width: 0.5, height: 0.5)
        #expect(Tree.landingFrame(of: frame, toward: .left) == .init(x: 0.5, y: 0, width: 0.25, height: 0.5))
        #expect(Tree.landingFrame(of: frame, toward: .right) == .init(x: 0.75, y: 0, width: 0.25, height: 0.5))
        #expect(Tree.landingFrame(of: frame, toward: .up) == .init(x: 0.5, y: 0, width: 0.5, height: 0.25))
        #expect(Tree.landingFrame(of: frame, toward: .down) == .init(x: 0.5, y: 0.25, width: 0.5, height: 0.25))
    }

    // MARK: Who takes the room

    @Test func `the pane that takes a leaving pane's room is its sibling`() {
        #expect(tree.neighborAfterRemoving("b") == "c")
        #expect(tree.neighborAfterRemoving("c") == "b")
        // a's sibling is the b-over-c column: the first of its panes.
        #expect(tree.neighborAfterRemoving("a") == "b")
    }

    @Test func `a pane knows how the split it is in divides`() {
        // a sits beside the b-over-c column; b and c are stacked.
        #expect(tree.parentAxis(of: "a") == .horizontal)
        #expect(tree.parentAxis(of: "b") == .vertical)
        #expect(tree.parentAxis(of: "c") == .vertical)
        #expect(Tree.leaf("a").parentAxis(of: "a") == nil)
        #expect(tree.parentAxis(of: "zzz") == nil)
    }

    @Test func `a lone or unknown pane has no neighbor`() {
        #expect(Tree.leaf("a").neighborAfterRemoving("a") == nil)
        #expect(tree.neighborAfterRemoving("zzz") == nil)
    }
}
