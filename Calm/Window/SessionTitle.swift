import AppKit
import CalmModel
import SwiftUI

/// The focused session's name in the header row above the terminal (UIUX.md → Title bar), with
/// the folder it's in on a quieter line below, like a window's title and subtitle, and a ⋯ button
/// at the right with the session's actions.
struct SessionTitleView: View {
    /// 16 points at the standard interface size.
    @MainActor
    static var leadingInset: CGFloat {
        16.scaled
    }

    /// The group's mark, at the standard interface size: larger than the sidebar's 20, to go with
    /// the 15 pt name.
    static let markSide: CGFloat = 24

    let manager: SessionManager
    let style: SidebarStyle
    let actions: SidebarActions
    let onRename: (Session.ID) -> Void
    let onClose: (Session.ID) -> Void
    /// Gets the window title whenever it changes.
    var onChange: (String) -> Void = { _ in }
    /// Gets the ⋯ button's frame, so the host takes clicks there and nowhere else.
    var onMenuFrame: (CGRect) -> Void = { _ in }
    @State private var menuHovered = false

    var body: some View {
        let strip = strip
        // Alone (a plain shell), the folder is the title and takes its line.
        let title = strip.title ?? strip.folder ?? ""
        let worktree = session?.worktreeName
        HStack(spacing: 8.scaled) {
            Group {
                // The worktree joins the folder line and shows whole or not at all: the name and
                // the folder come first, so a long one never trades for it. (Two explicit
                // children: ViewThatFits mustn't get an empty one.)
                if let worktree {
                    ViewThatFits(in: .horizontal) {
                        titleBlock(strip: strip, title: title, worktree: worktree)
                        titleBlock(strip: strip, title: title, worktree: nil)
                    }
                } else {
                    titleBlock(strip: strip, title: title, worktree: nil)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(nil, value: strip.folder)
            .animation(nil, value: strip.title)
            .animation(nil, value: worktree)
            if let session {
                menu(for: session)
            }
        }
        .padding(.leading, Self.leadingInset)
        .padding(.trailing, 12.scaled)
        // The strip's height stays CalmWindow.titleStripHeight, level with the traffic lights; two
        // lines at the largest size still fit in it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .coordinateSpace(.named("titleStrip"))
        .onChange(of: title, initial: true) { _, title in onChange(title) }
    }

    /// The group's mark and the two lines of text: the name, then the folder with the worktree
    /// after it. A plain shell has its folder as the name, so the worktree takes the second line
    /// alone.
    private func titleBlock(strip: (folder: String?, title: String?), title: String, worktree: String?) -> some View {
        let folder = strip.title == nil ? nil : strip.folder
        return HStack(spacing: 10.scaled) {
            // The group's own mark (the sidebar's GroupMark): a project's pixel tile, or the
            // folder or scratch glyph, so the text starts in the same place for every session.
            if let project {
                GroupMark(project: project, style: style, side: Self.markSide)
                    .foregroundStyle(style.tertiary)
                    .frame(width: Self.markSide.scaled, height: Self.markSide.scaled)
                    // The window's title carries the name for VoiceOver, the Window menu and
                    // Mission Control, so the name, the folder and the mark stay out of it.
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .calmFont(size: 15, weight: .medium)
                    .foregroundStyle(style.primary)
                    .truncationMode(.tail)
                    .accessibilityHidden(true)
                if folder != nil || worktree != nil {
                    HStack(spacing: 6.scaled) {
                        if let folder {
                            Text(folder)
                                .truncationMode(.head)
                                .accessibilityHidden(true)
                        }
                        if let worktree {
                            if folder != nil {
                                Text("·")
                                    .accessibilityHidden(true)
                            }
                            // The files column's branch, drawn the same way; it keeps its own VoiceOver label.
                            GitLabel(text: worktree, kind: "worktree", style: style)
                        }
                    }
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
                }
            }
            .lineLimit(1)
        }
    }

    /// Quiet until the pointer is on it: the row is a title first.
    private func menu(for session: Session) -> some View {
        Menu {
            SessionMenu(
                session: session, manager: manager, actions: actions,
                onRename: { onRename(session.id) }, onClose: { onClose(session.id) },
            )
        } label: {
            Image(systemName: "ellipsis")
                .calmFont(size: 13, weight: .semibold)
                .foregroundStyle(menuHovered ? style.primary : style.tertiary)
                .frame(width: 30.scaled, height: 26.scaled)
                .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(menuHovered ? style.selection : .clear))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { menuHovered = $0 }
        .help("Session actions")
        .accessibilityLabel("Session actions")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("titleStrip")) } action: { onMenuFrame($0) }
    }

    private var session: Session? {
        manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID) }
    }

    private var project: Project? {
        session.flatMap { manager.workspace.project($0.projectID) }
    }

    private var strip: (folder: String?, title: String?) {
        guard let session else { return (nil, nil) }
        return session.titleStrip(agentTitle: session.agent?.tail?.title)
    }
}

/// Hosts the title. It takes clicks only on the ⋯ button, so the strip under the rest of it
/// still drags the window and its double-click still reaches CalmWindow.
final class SessionTitleHost: NSHostingView<SessionTitleView> {
    /// The button's frame in this view's own space, top left origin, as SwiftUI reports it.
    var menuFrame = CGRect.zero

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let y = isFlipped ? local.y : bounds.height - local.y
        return menuFrame.contains(CGPoint(x: local.x, y: y)) ? super.hitTest(point) : nil
    }
}

// MARK: Title strip

extension MainWindowController {
    /// The focused session's name and folder, at the left of the strip above the terminal.
    func installTitle() {
        let title = SessionTitleHost(rootView: makeTitle(style: sidebarStyle))
        title.sizingOptions = []
        // The strip lies under the transparent title bar, whose safe area would push the text down
        // onto the terminal's first row. It's centered in the whole strip instead.
        title.safeAreaRegions = []
        title.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(title)
        // Over the terminal's left edge, but never under the traffic lights: with the sidebar
        // hidden the terminal starts at the window's edge, where they sit.
        let follow = title.leadingAnchor.constraint(equalTo: mainArea.leadingAnchor)
        follow.priority = .defaultHigh
        NSLayoutConstraint.activate([
            follow,
            title.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: trafficLightsEnd),
            title.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            title.topAnchor.constraint(equalTo: container.topAnchor),
            title.heightAnchor.constraint(equalToConstant: CalmWindow.titleStripHeight),
        ])
        titleHost = title
    }

    /// Where the traffic lights end, from the window's left edge (70 if AppKit has none to measure).
    private var trafficLightsEnd: CGFloat {
        guard let zoom = window?.standardWindowButton(.zoomButton) else { return 70 }
        return zoom.convert(zoom.bounds, to: nil).maxX
    }

    func makeTitle(style: SidebarStyle) -> SessionTitleView {
        SessionTitleView(
            manager: manager, style: style, actions: sessionActions,
            onRename: { [weak self] id in self?.beginRename(id) },
            onClose: { [weak self] id in self?.requestCloseSession(id) },
            // The window's title stays hidden (titleVisibility), but the system still shows it.
            onChange: { [weak self] title in self?.window?.title = title.isEmpty ? "Calm" : title },
            onMenuFrame: { [weak self] frame in self?.titleHost?.menuFrame = frame },
        )
    }
}
