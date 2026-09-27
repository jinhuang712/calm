/// A binary layout tree of panes, as used by splits.
///
/// Leaves hold pane identifiers; branches split their area between two children.
/// The tree is a value type: every edit returns a new tree, which keeps undo,
/// persistence and testing simple.
public indirect enum SplitTree<Leaf: Hashable & Sendable>: Hashable, Sendable {
    case leaf(Leaf)
    case split(Axis, ratio: Double, first: SplitTree, second: SplitTree)

    /// `.horizontal` places children side by side (a vertical divider);
    /// `.vertical` stacks them (a horizontal divider).
    public enum Axis: String, Hashable, Sendable, Codable {
        case horizontal
        case vertical
    }

    public enum Direction: Hashable, Sendable {
        case left, right, up, down

        var axis: Axis {
            switch self {
            case .left, .right: .horizontal
            case .up, .down: .vertical
            }
        }

        /// Whether the new or target pane sits after the reference pane on its axis.
        var isForward: Bool {
            self == .right || self == .down
        }
    }

    /// A pane's position in normalized coordinates (0…1, origin at top-left).
    public struct Frame: Hashable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var midX: Double {
            x + width / 2
        }

        var midY: Double {
            y + height / 2
        }
    }

    public static var minimumRatio: Double {
        0.1
    }

    // MARK: Queries

    /// Leaves in reading order (left to right, top to bottom).
    public var leaves: [Leaf] {
        switch self {
        case let .leaf(leaf): [leaf]
        case let .split(_, _, first, second): first.leaves + second.leaves
        }
    }

    public func contains(_ leaf: Leaf) -> Bool {
        leaves.contains(leaf)
    }

    /// Normalized frames of every leaf.
    public func frames(in frame: Frame = Frame(x: 0, y: 0, width: 1, height: 1)) -> [Leaf: Frame] {
        switch self {
        case let .leaf(leaf):
            return [leaf: frame]
        case let .split(axis, ratio, first, second):
            let (a, b) = Self.divide(frame, axis: axis, ratio: ratio)
            return first.frames(in: a).merging(second.frames(in: b)) { lhs, _ in lhs }
        }
    }

    // MARK: Edits

    /// Splits `target` in `direction`, placing `newLeaf` on that side with an even ratio.
    /// Returns the tree unchanged if `target` isn't in it.
    public func splitting(_ target: Leaf, direction: Direction, with newLeaf: Leaf) -> SplitTree {
        switch self {
        case let .leaf(leaf) where leaf == target:
            let existing = SplitTree.leaf(leaf)
            let added = SplitTree.leaf(newLeaf)
            return direction.isForward
                ? .split(direction.axis, ratio: 0.5, first: existing, second: added)
                : .split(direction.axis, ratio: 0.5, first: added, second: existing)
        case .leaf:
            return self
        case let .split(axis, ratio, first, second):
            return .split(
                axis,
                ratio: ratio,
                first: first.splitting(target, direction: direction, with: newLeaf),
                second: second.splitting(target, direction: direction, with: newLeaf),
            )
        }
    }

    /// Removes `target`, letting its sibling take the space. Returns nil when the
    /// tree becomes empty.
    public func removing(_ target: Leaf) -> SplitTree? {
        switch self {
        case let .leaf(leaf):
            return leaf == target ? nil : self
        case let .split(axis, ratio, first, second):
            let newFirst = first.removing(target)
            let newSecond = second.removing(target)
            switch (newFirst, newSecond) {
            case let (a?, b?): return .split(axis, ratio: ratio, first: a, second: b)
            case let (a?, nil): return a
            case let (nil, b?): return b
            case (nil, nil): return nil
            }
        }
    }

    /// Sets the ratio of the split that directly contains `target`, clamped so no pane collapses.
    public func settingRatio(_ newRatio: Double, forSplitContaining target: Leaf) -> SplitTree {
        switch self {
        case .leaf:
            return self
        case let .split(axis, ratio, first, second):
            if first == .leaf(target) || second == .leaf(target) {
                return .split(axis, ratio: Self.clamp(newRatio), first: first, second: second)
            }
            return .split(
                axis,
                ratio: ratio,
                first: first.settingRatio(newRatio, forSplitContaining: target),
                second: second.settingRatio(newRatio, forSplitContaining: target),
            )
        }
    }

    /// Resets every split to an even ratio.
    public func equalized() -> SplitTree {
        switch self {
        case .leaf:
            self
        case let .split(axis, _, first, second):
            .split(axis, ratio: 0.5, first: first.equalized(), second: second.equalized())
        }
    }

    // MARK: Navigation

    /// The nearest pane in `direction` from `origin`, judged by pane centers.
    public func neighbor(of origin: Leaf, toward direction: Direction) -> Leaf? {
        let all = frames()
        guard let from = all[origin] else { return nil }
        let candidates = all.filter { leaf, frame in
            guard leaf != origin else { return false }
            switch direction {
            case .left: return frame.x + frame.width <= from.x + 1e-9
            case .right: return frame.x >= from.x + from.width - 1e-9
            case .up: return frame.y + frame.height <= from.y + 1e-9
            case .down: return frame.y >= from.y + from.height - 1e-9
            }
        }
        return candidates.min { lhs, rhs in
            Self.distance(from, lhs.value, direction) < Self.distance(from, rhs.value, direction)
        }?.key
    }

    // MARK: Helpers

    static func clamp(_ ratio: Double) -> Double {
        min(max(ratio, minimumRatio), 1 - minimumRatio)
    }

    static func divide(_ frame: Frame, axis: Axis, ratio: Double) -> (Frame, Frame) {
        switch axis {
        case .horizontal:
            let firstWidth = frame.width * ratio
            return (
                Frame(x: frame.x, y: frame.y, width: firstWidth, height: frame.height),
                Frame(x: frame.x + firstWidth, y: frame.y, width: frame.width - firstWidth, height: frame.height),
            )
        case .vertical:
            let firstHeight = frame.height * ratio
            return (
                Frame(x: frame.x, y: frame.y, width: frame.width, height: firstHeight),
                Frame(x: frame.x, y: frame.y + firstHeight, width: frame.width, height: frame.height - firstHeight),
            )
        }
    }

    /// Distance along the travel axis first, then drift on the cross axis.
    static func distance(_ from: Frame, _ to: Frame, _ direction: Direction) -> Double {
        let along = direction.axis == .horizontal ? abs(to.midX - from.midX) : abs(to.midY - from.midY)
        let across = direction.axis == .horizontal ? abs(to.midY - from.midY) : abs(to.midX - from.midX)
        return along + across * 2
    }
}

/// Layouts are saved with the rest of the workspace.
extension SplitTree: Codable where Leaf: Codable {}

extension SplitTree.Direction: Codable {}
