/// Dropping a session onto a split (UIUX.md → Split panes): which pane it lands beside, on which
/// side, and what a pane leaving gives its room to.
public extension SplitTree {
    /// A drop's landing: the new pane goes on `direction`'s side of `target`.
    struct Drop: Hashable, Sendable {
        public let target: Leaf
        public let direction: Direction

        public init(target: Leaf, direction: Direction) {
            self.target = target
            self.direction = direction
        }
    }

    /// The middle of a pane, as fractions of its width and of its height, takes nothing: a drop
    /// has to be meant for an edge, and letting go over the text is how you call one off.
    static var dropDeadZone: ClosedRange<Double> {
        0.28 ... 0.72
    }

    /// Where a drop at (`x`, `y`), fractions of the whole area from its top left, lands: beside the
    /// pane under the pointer, on the side of it the pointer is nearest. Nil outside the area, in a
    /// pane's middle, or over `excluding` (the pane being dragged can't land beside itself).
    func drop(at x: Double, _ y: Double, excluding: Leaf? = nil) -> Drop? {
        for (leaf, frame) in frames() where leaf != excluding {
            guard x >= frame.x, x <= frame.x + frame.width, y >= frame.y, y <= frame.y + frame.height else { continue }
            let u = (x - frame.x) / frame.width
            let v = (y - frame.y) / frame.height
            if Self.dropDeadZone.contains(u), Self.dropDeadZone.contains(v) {
                return nil
            }
            let nearest = min(u, 1 - u, v, 1 - v)
            let direction: Direction = switch nearest {
            case u: .left
            case 1 - u: .right
            case v: .up
            default: .down
            }
            return Drop(target: leaf, direction: direction)
        }
        return nil
    }

    /// The part of `frame` a pane dropped on `direction`'s side of it would take: that half.
    static func landingFrame(of frame: Frame, toward direction: Direction) -> Frame {
        switch direction {
        case .left: Frame(x: frame.x, y: frame.y, width: frame.width / 2, height: frame.height)
        case .right: Frame(x: frame.x + frame.width / 2, y: frame.y, width: frame.width / 2, height: frame.height)
        case .up: Frame(x: frame.x, y: frame.y, width: frame.width, height: frame.height / 2)
        case .down: Frame(x: frame.x, y: frame.y + frame.height / 2, width: frame.width, height: frame.height / 2)
        }
    }

    /// How the split that holds `target` divides its area: side by side (`.horizontal`) or stacked
    /// (`.vertical`). The pane's icon draws the line the same way. Nil for a lone pane.
    func parentAxis(of target: Leaf) -> Axis? {
        guard case let .split(axis, _, first, second) = self else { return nil }
        if first == .leaf(target) || second == .leaf(target) {
            return axis
        }
        return first.parentAxis(of: target) ?? second.parentAxis(of: target)
    }

    /// The pane that takes `target`'s room when it leaves: the first pane of its sibling. Nil for a
    /// lone pane or one that isn't in the tree. (What closing a pane refocuses today is the first
    /// pane of the whole layout, which can be the far side of the window.)
    func neighborAfterRemoving(_ target: Leaf) -> Leaf? {
        guard case let .split(_, _, first, second) = self else { return nil }
        if first == .leaf(target) {
            return second.leaves.first
        }
        if second == .leaf(target) {
            return first.leaves.first
        }
        return first.neighborAfterRemoving(target) ?? second.neighborAfterRemoving(target)
    }
}
