import Foundation

// MARK: The order

public extension Workspace {
    /// Moves a project the user made to `position` among them, `madeProjects`'s order, where the
    /// sidebar's drag let it go (FEATURES.md → F2). Scratch and folder groups keep their places, and
    /// the order is saved with the rest of the workspace.
    mutating func moveProject(_ projectID: Project.ID, to position: Int) {
        guard let from = projects.firstIndex(where: { $0.id == projectID && $0.kind == .project }) else { return }
        let project = projects.remove(at: from)
        // The groups are ranked by kind before they're ordered (`orderedProjects`), so placing it
        // among the other projects is all that counts.
        let others = projects.indices.filter { projects[$0].kind == .project }
        let slot = min(max(position, 0), others.count)
        // After the last project when it goes to the end; back where it was when it's the only one.
        let index = slot < others.count ? others[slot] : others.last.map { $0 + 1 } ?? from
        projects.insert(project, at: index)
    }
}

// MARK: The drag

/// A project's header dragged to another place among the projects (UIUX.md → Layout): where it
/// would land, and how far each project is drawn from its place meanwhile. The sidebar measures
/// the sections and draws them; the rules are here, so they're tested.
public struct ProjectReorder: Hashable, Sendable {
    /// A section's top and bottom edges, in the list's coordinates (y grows downward).
    public struct Span: Hashable, Sendable {
        public let top: Double
        public let bottom: Double

        public init(top: Double, bottom: Double) {
            self.top = top
            self.bottom = bottom
        }

        public var height: Double {
            bottom - top
        }

        public var middle: Double {
            (top + bottom) / 2
        }
    }

    /// The projects' sections, top to bottom, as they were laid out when the drag began.
    public let spans: [Span]
    /// The one being dragged.
    public let index: Int
    /// The room between two sections.
    public let spacing: Double

    /// Nil for fewer than two projects, which have no order to change.
    public init?(spans: [Span], index: Int, spacing: Double) {
        guard spans.count > 1, spans.indices.contains(index) else { return nil }
        self.spans = spans
        self.index = index
        self.spacing = spacing
    }

    /// How far the pointer has taken the dragged section's top from its place as laid out now, for a
    /// drag that began with that top at `startTop` and a pointer that has moved `moved` since. The
    /// sections can change height during a drag (an agent's card grows a line), which moves the
    /// dragged one's place, and it has to stay under the pointer all the same.
    public func travel(from startTop: Double, moved: Double) -> Double {
        startTop + moved - spans[index].top
    }

    /// How far the dragged section is drawn from its place for a pointer that moved `offset`: as
    /// far, but held between the first project's top and the last one's bottom, so it never covers
    /// the scratch group or a folder's.
    public func clamped(_ offset: Double) -> Double {
        let dragged = spans[index]
        let lowest = spans[0].top - dragged.top
        let highest = spans[spans.count - 1].bottom - dragged.bottom
        return min(max(offset, lowest), highest)
    }

    /// Where the dragged section lands, among the projects, for a pointer that moved `offset`: past
    /// every section whose middle its leading edge has crossed (its bottom going down, its top going
    /// up), so a tall project doesn't have to travel its own height to pass a short one.
    public func target(for offset: Double) -> Int {
        let offset = clamped(offset)
        let dragged = spans[index]
        if offset > 0 {
            let edge = dragged.bottom + offset
            return index + spans[(index + 1)...].prefix { edge > $0.middle }.count
        }
        let edge = dragged.top + offset
        return index - spans[..<index].reversed().prefix { edge < $0.middle }.count
    }

    /// How far section `section` is drawn from its place while the dragged one would land at
    /// `target`: each one it passed steps over by its height and a gap, which leaves a hole its
    /// size where it would land. The dragged one follows the pointer instead (`clamped`).
    public func shift(of section: Int, toward target: Int) -> Double {
        let room = spans[index].height + spacing
        if section > index, section <= target {
            return -room
        }
        if section < index, section >= target {
            return room
        }
        return 0
    }
}
