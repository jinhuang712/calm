import CalmModel
import SwiftUI

/// A project dragged by its header to another place among the projects (UIUX.md → Layout): it
/// follows the pointer, lifted over the list; the projects it passes step aside; letting go settles
/// it into the hole they left. Only projects the user made move, and only among themselves. Where it
/// lands and how far each section is drawn are `ProjectReorder`'s rules (CalmModel, tested); this
/// holds the drag, measures the sections, and scrolls the list when the pointer nears its edge.
@MainActor
@Observable
final class ProjectDragModel {
    /// How the projects step aside, and how the dragged one settles when it's let go.
    static let motion = Animation.easeInOut(duration: 0.2)

    struct Drag {
        let projectID: Project.ID
        /// The projects in the sidebar's order when the drag began.
        let order: [Project.ID]
        /// Their sections as laid out now: an agent's card can grow or shrink during the drag.
        var reorder: ProjectReorder
        /// Where the dragged section's top was in the list when the drag began.
        let startTop: Double
        /// How far the pointer has moved since it pressed the header.
        var moved = 0.0
        /// How far the list has scrolled under it since then: the dragged section stays under the pointer.
        var scrolled = 0.0

        private var travel: Double {
            reorder.travel(from: startTop, moved: moved + scrolled)
        }

        var offset: Double {
            reorder.clamped(travel)
        }

        var target: Int {
            reorder.target(for: travel)
        }
    }

    /// The scroll view's numbers, for scrolling it near its edges.
    struct Scroll: Equatable {
        var offset = 0.0
        var visible = 0.0
        var content = 0.0

        var furthest: Double {
            max(content - visible, 0)
        }
    }

    private(set) var drag: Drag?
    /// The project just let go, while it settles: it stays above the others until it's in place.
    private(set) var settling: Project.ID?
    /// Bound to the list's scroll view, so the drag can scroll it.
    var scrollPosition = ScrollPosition()

    @ObservationIgnored private var spans: [Project.ID: ProjectReorder.Span] = [:]
    @ObservationIgnored private var scroll = Scroll()
    @ObservationIgnored private var scrolledAtStart = 0.0
    @ObservationIgnored private var edgeSpeed = 0.0
    @ObservationIgnored private var autoscroll: Task<Void, Never>?

    /// The list laid a group's section out at `frame`, in the list's coordinates (where it is laid
    /// out, not where a drag draws it). During a drag the sections are taken again as they are now.
    func measured(_ id: Project.ID, _ frame: CGRect) {
        let span = ProjectReorder.Span(top: frame.minY, bottom: frame.maxY)
        guard spans[id] != span else { return }
        spans[id] = span
        guard let drag, drag.order.contains(id) else { return }
        let now = drag.order.compactMap { spans[$0] }
        if now.count == drag.order.count,
           let reorder = ProjectReorder(spans: now, index: drag.reorder.index, spacing: drag.reorder.spacing) {
            self.drag?.reorder = reorder
        }
    }

    func scrolled(_ new: Scroll) {
        scroll = new
        if drag != nil {
            drag?.scrolled = new.offset - scrolledAtStart
        }
    }

    /// The pointer pressed on `projectID`'s header has moved `moved` since, and is `location` below
    /// the top of the list's visible part. The first call starts the drag, from the sections as they
    /// are laid out now; `order` is the projects in the sidebar's order.
    func changed(_ projectID: Project.ID, order: [Project.ID], spacing: Double, moved: Double, location: Double) {
        if drag == nil {
            let measured = order.compactMap { spans[$0] }
            guard measured.count == order.count, let index = order.firstIndex(of: projectID),
                  let reorder = ProjectReorder(spans: measured, index: index, spacing: spacing) else { return }
            scrolledAtStart = scroll.offset
            settling = nil
            drag = Drag(projectID: projectID, order: order, reorder: reorder, startTop: measured[index].top)
        }
        guard drag?.projectID == projectID else { return }
        drag?.moved = moved
        scrollNearEdges(location)
    }

    /// Lets the dragged project go: `commit` puts it where it would land, if that's a new place
    /// (its index among the projects), and the sections settle together. Safe to call twice.
    func end(commit: (Project.ID, Int) -> Void) {
        stopScrolling()
        guard let drag else { return }
        let target = drag.target
        settling = drag.projectID
        Motion.animate(Self.motion) {
            self.drag = nil
            if target != drag.reorder.index {
                commit(drag.projectID, target)
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.3))
            if self?.settling == drag.projectID {
                self?.settling = nil
            }
        }
    }

    // MARK: Drawing

    /// The dragged project's section: drawn lifted, following the pointer.
    func isLifted(_ id: Project.ID) -> Bool {
        drag?.projectID == id
    }

    /// Drawn above the other sections: the dragged one, and the one settling.
    func isAbove(_ id: Project.ID) -> Bool {
        isLifted(id) || settling == id
    }

    /// How far the dragged section is drawn from its place: where the pointer has taken it.
    var liftedOffset: Double {
        drag?.offset ?? 0
    }

    /// How far another section is drawn from its place: aside, if the dragged one has passed it.
    func shift(of id: Project.ID) -> Double {
        guard let drag, id != drag.projectID, let section = drag.order.firstIndex(of: id) else { return 0 }
        return drag.reorder.shift(of: section, toward: drag.target)
    }

    // MARK: Scrolling

    /// The highest speed, in points per frame, with the pointer at the list's very edge.
    private static let fastest = 10.0

    /// Near the list's top or bottom, it scrolls under the dragged project, faster the nearer the
    /// pointer is to the edge, so a project can be taken past what's on screen.
    private func scrollNearEdges(_ location: Double) {
        let zone = Double(36.scaled)
        if location < zone, scroll.offset > 0 {
            edgeSpeed = -Self.fastest * min((zone - location) / zone, 1)
        } else if location > scroll.visible - zone, scroll.offset < scroll.furthest {
            edgeSpeed = Self.fastest * min((location - (scroll.visible - zone)) / zone, 1)
        } else {
            edgeSpeed = 0
        }
        if edgeSpeed == 0 {
            stopScrolling()
        } else if autoscroll == nil {
            autoscroll = Task { [weak self] in
                while !Task.isCancelled, self?.scrollStep() == true {
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }
    }

    /// One frame's scroll. False when there's nothing left to do: the pointer left the edge, the
    /// drag ended or the list can't go further.
    private func scrollStep() -> Bool {
        let next = min(max(scroll.offset + edgeSpeed, 0), scroll.furthest)
        guard drag != nil, edgeSpeed != 0, next != scroll.offset else {
            autoscroll = nil
            return false
        }
        scrollPosition.scrollTo(y: next)
        return true
    }

    private func stopScrolling() {
        edgeSpeed = 0
        autoscroll?.cancel()
        autoscroll = nil
    }
}

extension SessionManager {
    /// A project dragged to another place among the projects (FEATURES.md → F2). Not animated here:
    /// the drag animates it together with its own end, so the two settle as one.
    func moveProject(_ projectID: Project.ID, to position: Int) {
        if changeWorkspace({ $0.moveProject(projectID, to: position) }) {
            scheduleSave()
        }
    }
}

/// What a project's header needs to be dragged to another place (nil for a header that can't be:
/// a folder's, scratch's, or the only project's).
struct HeaderDrag {
    /// The pointer moved `moved` since it pressed, and is `location` below the list's visible top.
    let changed: (_ moved: CGFloat, _ location: CGFloat) -> Void
    let ended: () -> Void
    /// While it's dragged, and while it settles: the header's click is the drag's release then.
    let isActive: () -> Bool
    /// VoiceOver's way to do the same, a place at a time; nil at the top or the bottom.
    let moveUp: (() -> Void)?
    let moveDown: (() -> Void)?
}

extension SidebarView {
    /// The room between two groups.
    @MainActor
    static var groupSpacing: CGFloat {
        22.scaled
    }

    /// The list's content, where the sections are measured.
    nonisolated static let listSpace = "calm.sidebar.list"
    /// The list's visible part, where the pointer is followed (the dragged section moves under it,
    /// so its own coordinates would move too).
    nonisolated static let viewportSpace = "calm.sidebar.viewport"

    /// A project's header can be dragged once there's another project to pass.
    func headerDrag(for project: Project) -> HeaderDrag? {
        let order = manager.workspace.madeProjects.map(\.id)
        guard project.kind == .project, order.count > 1, let index = order.firstIndex(of: project.id) else { return nil }
        let model = projectDrag
        let manager = manager
        let commit: (Project.ID, Int) -> Void = { id, position in manager.moveProject(id, to: position) }
        return HeaderDrag(
            changed: { moved, location in
                model.changed(project.id, order: order, spacing: Self.groupSpacing, moved: moved, location: location)
            },
            ended: { model.end(commit: commit) },
            isActive: { model.isAbove(project.id) },
            moveUp: index > 0 ? { Motion.animate(ProjectDragModel.motion) { commit(project.id, index - 1) } } : nil,
            moveDown: index < order.count - 1 ? { Motion.animate(ProjectDragModel.motion) { commit(project.id, index + 1) } } : nil,
        )
    }
}

/// A group's section in the list, measured for a drag and drawn where the drag puts it. Its own
/// modifier, so a drag redraws the sections and not the whole sidebar.
struct ReorderableSection: ViewModifier {
    let id: Project.ID
    let model: ProjectDragModel
    let style: SidebarStyle

    func body(content: Content) -> some View {
        let lifted = model.isLifted(id)
        let shift = model.shift(of: id)
        content
            .background {
                ZStack {
                    if lifted {
                        // Lifted off the list: the sidebar's own color, so the sections it passes
                        // over don't show through, and a soft shadow.
                        RoundedRectangle(cornerRadius: 14.scaled, style: .continuous)
                            .fill(style.background)
                            .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 10, y: 4)
                            .padding(.horizontal, -6.scaled)
                            .padding(.vertical, -8.scaled)
                            .transition(.opacity)
                    }
                }
                .animation(Motion.isReduced ? nil : .easeOut(duration: 0.15), value: lifted)
            }
            // The dragged section follows the pointer at once; the others ease aside.
            .offset(y: lifted ? model.liftedOffset : shift)
            // After the offset, so it sees where the section is laid out, not where it's drawn.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SidebarView.listSpace)) } action: { frame in
                model.measured(id, frame)
            }
            .animation(Motion.isReduced ? nil : ProjectDragModel.motion, value: shift)
            .zIndex(model.isAbove(id) ? 1 : 0)
    }
}
