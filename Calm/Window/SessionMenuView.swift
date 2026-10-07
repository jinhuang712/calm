import AppKit
import CalmModel
import SwiftUI

/// Where the session menu opens: under the ⋯ button, its right edge on the button's, or at the
/// pointer for a right-click. In the window's content, top-left origin.
enum SessionMenuAnchor: Equatable {
    case below(CGRect)
    case point(CGPoint)
}

/// What changes while the menu is up: the highlighted item, the projects list beside it, and the
/// sizes that place both.
@MainActor
@Observable
final class SessionMenuState {
    var hot: Int?
    /// The tile ↓ left from, for ↑ to come back to.
    var lastTile = 0
    var projectsOpen = false
    var projectHot: Int?
    /// Where the menu and the projects list are, in the overlay (top-left origin): what the host
    /// takes the pointer on, and what places the list.
    var menuFrame = CGRect.zero
    var projectsFrame = CGRect.zero
    /// The menu's frame in the host itself: the same as `menuFrame` unless something moves the
    /// overlay inside the host (the title bar's safe area did, by 32 pt). Self-tests log both.
    var menuFrameInHost = CGRect.zero

    var menuSize: CGSize {
        menuFrame.size
    }

    var projectsSize: CGSize {
        projectsFrame.size
    }

    /// Move to Project's row, in the menu's own space.
    var moveRowFrame = CGRect.zero
    var appeared = false
    /// Where the pointer was when the menu opened. A menu opened under a pointer that hasn't
    /// moved highlights nothing, as a system menu doesn't: hovering counts once it moves.
    private var openPointer = CGPoint.zero
    private var pointerMoved = false

    func reset() {
        hot = nil
        lastTile = 0
        projectsOpen = false
        projectHot = nil
        menuFrame = .zero
        projectsFrame = .zero
        menuFrameInHost = .zero
        moveRowFrame = .zero
        appeared = false
        openPointer = NSEvent.mouseLocation
        pointerMoved = false
    }

    /// Whether a hover is the pointer's doing rather than the menu appearing under it.
    func hoverCounts() -> Bool {
        if !pointerMoved, NSEvent.mouseLocation != openPointer {
            pointerMoved = true
        }
        return pointerMoved
    }
}

/// The session menu (UIUX.md → Session cards → The session menu), drawn by Calm in the theme's
/// colors like ⌘P rather than as a system menu: a surface lifted off the terminal; the agent's
/// actions as tiles under its name, a verb over what it does now; the rest as quiet rows, the
/// copies under a small-caps label. Chosen by the author on 2026-10-06 (C of three, polished).
/// Laid over the whole window, so it can sit anywhere in it; `SessionMenuController` takes the
/// keys and the clicks outside.
struct SessionMenuOverlay: View {
    let content: SessionMenuContent
    let anchor: SessionMenuAnchor
    let style: SidebarStyle
    let state: SessionMenuState
    let choose: (Int) -> Void
    let chooseProject: (Int) -> Void

    nonisolated static let space = "sessionMenu"

    var body: some View {
        GeometryReader { proxy in
            let origin = Self.origin(for: anchor, size: state.menuSize, in: proxy.size)
            ZStack(alignment: .topLeading) {
                // Placed with padding rather than an offset, so the frame it reports is where it is.
                SessionMenuPanel(content: content, style: style, state: state, choose: choose)
                    .fixedSize()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { state.menuFrame = $0 }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { state.menuFrameInHost = $0 }
                    .scaleEffect(state.appeared ? 1 : 0.97, anchor: corner)
                    .opacity(state.appeared && state.menuSize != .zero ? 1 : 0)
                    .padding(.leading, origin.x)
                    .padding(.top, origin.y)
                if state.projectsOpen {
                    let place = Self.projectsOrigin(
                        menu: origin, menuSize: state.menuSize, row: state.moveRowFrame, size: state.projectsSize, in: proxy.size,
                    )
                    ProjectsPanel(projects: content.projects, style: style, state: state, choose: chooseProject)
                        .fixedSize()
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { state.projectsFrame = $0 }
                        .opacity(state.projectsSize == .zero ? 0 : 1)
                        .padding(.leading, place.x)
                        .padding(.top, place.y)
                        .onDisappear { state.projectsFrame = .zero }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .onAppear {
            Motion.animate(.easeOut(duration: 0.14)) { state.appeared = true }
        }
    }

    /// The menu grows from the corner it opens at.
    private var corner: UnitPoint {
        if case .below = anchor {
            return .topTrailing
        }
        return .topLeading
    }

    /// Under the button, or at the pointer; moved inside the window, and above the pointer when
    /// there's no room below, as a menu does.
    static func origin(for anchor: SessionMenuAnchor, size: CGSize, in bounds: CGSize, margin: CGFloat = 8) -> CGPoint {
        var origin: CGPoint
        switch anchor {
        case let .below(button):
            origin = CGPoint(x: button.maxX - size.width, y: button.maxY + 4)
        case let .point(point):
            origin = CGPoint(x: point.x + 2, y: point.y + 2)
            if origin.y + size.height > bounds.height - margin, point.y - size.height - 2 >= margin {
                origin.y = point.y - size.height - 2
            }
        }
        origin.x = min(max(origin.x, margin), max(margin, bounds.width - size.width - margin))
        origin.y = min(max(origin.y, margin), max(margin, bounds.height - size.height - margin))
        return origin
    }

    /// Beside Move to Project's row: to the right, or to the left when the right has no room.
    static func projectsOrigin(
        menu: CGPoint,
        menuSize: CGSize,
        row: CGRect,
        size: CGSize,
        in bounds: CGSize,
        margin: CGFloat = 8,
    ) -> CGPoint {
        var x = menu.x + menuSize.width + 4
        if x + size.width > bounds.width - margin {
            x = menu.x - size.width - 4
        }
        let y = min(max(menu.y + row.minY - 6, margin), max(margin, bounds.height - size.height - margin))
        return CGPoint(x: max(margin, x), y: y)
    }
}

/// The menu's own surface.
private struct SessionMenuPanel: View {
    let content: SessionMenuContent
    let style: SidebarStyle
    let state: SessionMenuState
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header = content.header {
                HStack(spacing: 7.scaled) {
                    AgentLogo(agent: header.agent, size: 16, style: style)
                    Text(header.agent.displayName)
                        .foregroundStyle(style.secondary)
                    if let version = header.version {
                        Text(version)
                            .monospacedDigit()
                            .foregroundStyle(style.tertiary)
                    }
                }
                .calmFont(size: 12)
                .lineLimit(1)
                .padding(.horizontal, 6.scaled)
                .frame(height: 26.scaled)
            }
            if !content.tiles.isEmpty {
                HStack(spacing: 5.scaled) {
                    ForEach(Array(content.tiles.enumerated()), id: \.offset) { index, tile in
                        TileView(tile: tile, style: style, hot: state.hot == index)
                            .onHover { inside in hover(index, inside) }
                            .onTapGesture { choose(index) }
                    }
                }
                .padding(.vertical, 1.scaled)
                Separator(style: style)
            }
            let offsets = groupOffsets
            ForEach(Array(content.groups.enumerated()), id: \.offset) { groupIndex, group in
                if groupIndex > 0 {
                    Separator(style: style)
                }
                if let label = group.label {
                    Text(label)
                        .calmFont(size: 10.5)
                        .tracking(0.9)
                        .foregroundStyle(style.tertiary)
                        .padding(.leading, 34.scaled)
                        .padding(.top, 7.scaled)
                        .padding(.bottom, 3.scaled)
                        .accessibilityAddTraits(.isHeader)
                }
                ForEach(Array(group.rows.enumerated()), id: \.offset) { rowIndex, row in
                    let index = offsets[groupIndex] + rowIndex
                    RowView(row: row, style: style, hot: state.hot == index)
                        .onHover { inside in hover(index, inside) }
                        .onTapGesture { choose(index) }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SessionMenuOverlay.space + "-panel")) } action: { frame in
                            if row.opensProjects {
                                state.moveRowFrame = frame
                            }
                        }
                }
            }
        }
        .padding(7.scaled)
        .frame(width: 288.scaled)
        .coordinateSpace(.named(SessionMenuOverlay.space + "-panel"))
        .background(PanelShape(style: style))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Session actions")
    }

    /// The index of each group's first row, counting the tiles first.
    private var groupOffsets: [Int] {
        var offsets: [Int] = []
        var next = content.tiles.count
        for group in content.groups {
            offsets.append(next)
            next += group.rows.count
        }
        return offsets
    }

    private func hover(_ index: Int, _ inside: Bool) {
        guard state.hoverCounts() else { return }
        if inside {
            state.hot = index
            if index < content.tiles.count {
                state.lastTile = index
            }
            state.projectsOpen = content.opensProjects(at: index)
            if state.projectsOpen {
                state.projectHot = nil
            }
        } else if state.hot == index, !state.projectsOpen {
            state.hot = nil
        }
    }
}

/// A verb over what it does now; an update waiting puts the tile in the hint's amber.
private struct TileView: View {
    let tile: SessionMenuContent.Tile
    let style: SidebarStyle
    let hot: Bool

    var body: some View {
        let color = tile.amber ? style.attention : style.primary
        VStack(spacing: 0) {
            Image(systemName: tile.symbol)
                .calmFont(size: 16, weight: .regular)
                .frame(height: 20.scaled)
                .padding(.bottom, 6.scaled)
            Text(tile.title)
                .calmFont(size: 12, weight: .medium)
            Text(tile.detail)
                .calmFont(size: 11)
                .foregroundStyle(tile.amber ? style.attention.opacity(0.8) : style.tertiary)
        }
        .foregroundStyle(color)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 70.scaled)
        .background(
            RoundedRectangle(cornerRadius: 11.scaled, style: .continuous)
                .fill(tile.amber ? style.attention.opacity(hot ? 0.24 : 0.13) : style.primary.opacity(fill)),
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11.scaled, style: .continuous)
                .strokeBorder((tile.amber ? style.attention : style.primary).opacity(style.isDark ? 0.07 : 0.06)),
        )
        .opacity(tile.action == nil ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 11.scaled, style: .continuous))
        .help(tile.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.name)
        .accessibilityAddTraits(.isButton)
    }

    private var fill: Double {
        style.isDark ? (hot ? 0.11 : 0.055) : (hot ? 0.1 : 0.05)
    }
}

private struct RowView: View {
    let row: SessionMenuContent.Row
    let style: SidebarStyle
    let hot: Bool

    var body: some View {
        HStack(spacing: 9.scaled) {
            Image(systemName: row.symbol)
                .calmFont(size: 12.5)
                .foregroundStyle(hot ? style.primary : style.tertiary)
                .frame(width: 18.scaled)
            Text(row.title)
                .calmFont(size: 13)
                .foregroundStyle(hot ? style.primary : style.secondary)
            Spacer(minLength: 8.scaled)
            if let key = row.key {
                Text(key)
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
            }
            if row.opensProjects {
                Image(systemName: "chevron.right")
                    .calmFont(size: 10, weight: .semibold)
                    .foregroundStyle(style.tertiary)
            }
        }
        .lineLimit(1)
        .padding(.leading, 7.scaled)
        .padding(.trailing, 8.scaled)
        .frame(height: 28.scaled)
        .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(hot ? style.selection : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title)
        .accessibilityAddTraits(.isButton)
    }
}

/// Move to Project's list, beside the menu, each project with its pixel mark.
private struct ProjectsPanel: View {
    let projects: [Project]
    let style: SidebarStyle
    let state: SessionMenuState
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(projects.enumerated()), id: \.element.id) { index, project in
                HStack(spacing: 9.scaled) {
                    GroupMark(project: project, style: style, side: 18)
                        .frame(width: 18.scaled, height: 18.scaled)
                    Text(project.name)
                        .calmFont(size: 13)
                        .foregroundStyle(state.projectHot == index ? style.primary : style.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8.scaled)
                .frame(height: 30.scaled)
                .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
                    .fill(state.projectHot == index ? style.selection : .clear))
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside, state.hoverCounts() {
                        state.projectHot = index
                    }
                }
                .onTapGesture { choose(index) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(project.name)
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(6.scaled)
        .frame(minWidth: 180.scaled, maxWidth: 260.scaled)
        .background(PanelShape(style: style))
    }
}

/// A surface lifted off what's under it, in the theme's own colors.
private struct PanelShape: View {
    let style: SidebarStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 15.scaled, style: .continuous)
        shape
            .fill(style.background)
            .overlay(shape.fill(Color.white.opacity(style.isDark ? 0.05 : 0.55)))
            .overlay(shape.strokeBorder(style.primary.opacity(style.isDark ? 0.14 : 0.12)))
            .shadow(color: .black.opacity(style.isDark ? 0.45 : 0.15), radius: 22, y: 12)
    }
}

private struct Separator: View {
    let style: SidebarStyle

    var body: some View {
        Rectangle()
            .fill(style.primary.opacity(style.isDark ? 0.1 : 0.09))
            .frame(height: 1)
            .padding(.horizontal, 7.scaled)
            .padding(.vertical, 6.scaled)
    }
}
