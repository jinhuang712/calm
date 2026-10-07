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
    /// The files column's model: the readout's numbers, and whether the column is already up.
    let files: FilesModel
    /// The folder the files column would show for the focused session (its project, or a scratch
    /// session's folder).
    let filesRoot: () -> String?
    /// Opens the session menu under the ⋯ button.
    let onShowMenu: (Session.ID) -> Void
    /// Gets the window title whenever it changes.
    var onChange: (String) -> Void = { _ in }
    /// Gets the ⋯ button's frame, so the host takes clicks there and nowhere else.
    var onMenuFrame: (CGRect) -> Void = { _ in }
    /// Gets the frames of the controls besides ⋯ (the files readout, the update hint; nil once
    /// one goes), keyed by the view that draws it.
    var onControlFrame: (UUID, CGRect?) -> Void = { _, _ in }
    /// The update hint's click: restart the agent, or take back a restart still waiting.
    var onRestart: (Session.ID) -> Void = { _ in }
    var onCancelRestart: (Session.ID) -> Void = { _ in }
    /// Find (FEATURES.md → F16): while it's open its field takes the readout's place.
    let find: FindModel
    @State private var menuHovered = false
    /// While finding: the row the title and the field share, and the title's whole width with
    /// its worktree, which the field gives way to before the title does.
    @State private var findRowWidth: CGFloat = 0
    @State private var findTitleWidth: CGFloat = 0

    /// What the files readout follows: the project, and whether an agent is working in it.
    private struct Watch: Equatable {
        var root: String?
        var working: Bool
    }

    var body: some View {
        let strip = strip
        // Alone (a plain shell), the folder is the title and takes its line.
        let title = strip.title ?? strip.folder ?? ""
        let worktree = session?.worktreeName
        // The readout gives way to the column, which shows the same numbers, and to find's field.
        let summary = files.isShown || find.isOpen ? nil : files.summary
        let watch = Watch(root: filesRoot(), working: session?.state == .working)
        HStack(spacing: 8.scaled) {
            Group {
                if find.isOpen {
                    findingRow(strip: strip, title: title, worktree: worktree)
                } else {
                    // The worktree and the readout join the title's lines and show whole or not at
                    // all: the name and the folder come first, so a long one never trades for them,
                    // and the readout goes before the worktree does (which worktree you're in is
                    // part of where you are; the count is news). Four explicit children:
                    // ViewThatFits mustn't get an empty or optional one.
                    ViewThatFits(in: .horizontal) {
                        titleRow(strip: strip, title: title, worktree: worktree, summary: summary)
                        titleRow(strip: strip, title: title, worktree: worktree, summary: nil)
                        titleRow(strip: strip, title: title, worktree: nil, summary: summary)
                        titleRow(strip: strip, title: title, worktree: nil, summary: nil)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(nil, value: strip.folder)
            .animation(nil, value: strip.title)
            .animation(nil, value: worktree)
            .animation(nil, value: summary)
            if let session, let hint = updateHint(for: session) {
                // Outside the fitting rows: it is news the title gives way to, never the reverse.
                AgentUpdateHintView(hint: hint, style: style, onFrame: onControlFrame) {
                    if hint.cancels {
                        onCancelRestart(session.id)
                    } else {
                        onRestart(session.id)
                    }
                }
            }
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
        // The project's changes are read again when it changes and when an agent starts or stops
        // working in it (files.watchSummary).
        .onChange(of: watch, initial: true) { _, watch in files.watchSummary(of: watch.root, working: watch.working) }
    }

    /// While finding (UIUX.md → Find): the title and, at the right, the field. When the row is short
    /// the field narrows from 340 to 240 pt first; then the worktree goes, the name shortens down to
    /// 96 pt, the name and folder go leaving the mark, and the mark goes. Only the title changes
    /// between ViewThatFits's children, so the field is never rebuilt and keeps the keyboard.
    private func findingRow(strip: (folder: String?, title: String?), title: String, worktree: String?) -> some View {
        let gap = 8.scaled
        let field = Self.findFieldWidth(row: findRowWidth, title: findTitleWidth, gap: gap, widest: 340.scaled, narrowest: 240.scaled)
        return HStack(spacing: gap) {
            ViewThatFits(in: .horizontal) {
                titleBlock(strip: strip, title: title, worktree: worktree)
                titleBlock(strip: strip, title: title, worktree: nil)
                titleBlock(strip: strip, title: title, worktree: nil)
                    .frame(minWidth: 96.scaled, idealWidth: 96.scaled, maxWidth: .infinity, alignment: .leading)
                groupMark
                Color.clear.frame(width: 0, height: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FindFieldView(model: find, style: style, onFrame: onControlFrame)
                .frame(width: field)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { findRowWidth = $0 }
        .background(alignment: .leading) {
            // The title's whole width, measured where it can't be seen.
            titleBlock(strip: strip, title: title, worktree: worktree)
                .fixedSize()
                .hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { findTitleWidth = $0 }
        }
    }

    /// The find field's width in a row `row` wide whose title wants `title`: `widest` at most,
    /// giving way to the title down to `narrowest`, and never wider than the row.
    nonisolated static func findFieldWidth(row: CGFloat, title: CGFloat, gap: CGFloat, widest: CGFloat, narrowest: CGFloat) -> CGFloat {
        guard row > 0 else { return narrowest }
        return min(row, min(widest, max(narrowest, row - title - gap)))
    }

    /// The group's mark alone: what's left of the title in a short row while finding.
    @ViewBuilder private var groupMark: some View {
        if let project {
            GroupMark(project: project, style: style, side: Self.markSide)
                .foregroundStyle(style.tertiary)
                .frame(width: Self.markSide.scaled, height: Self.markSide.scaled)
                .accessibilityHidden(true)
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// The title block with, at the right of the strip's room, the readout when there is one.
    private func titleRow(
        strip: (folder: String?, title: String?),
        title: String,
        worktree: String?,
        summary: ChangeSummary?,
    ) -> some View {
        HStack(spacing: 0) {
            titleBlock(strip: strip, title: title, worktree: worktree)
            Spacer(minLength: summary == nil ? 0 : 8.scaled)
            if let summary {
                ChangeReadoutView(summary: summary, style: style, action: actions.toggleFiles, onFrame: onControlFrame)
            }
        }
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
        // Calm draws the menu itself (SessionMenuController), so this is a plain button.
        Button {
            onShowMenu(session.id)
        } label: {
            Image(systemName: "ellipsis")
                .calmFont(size: 13, weight: .semibold)
                .foregroundStyle(menuHovered ? style.primary : style.tertiary)
                .frame(width: 30.scaled, height: 26.scaled)
                .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(menuHovered ? style.selection : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { menuHovered = $0 }
        .help("Session actions")
        .accessibilityLabel("Session actions")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("titleStrip")) } action: { onMenuFrame($0) }
    }

    private var session: Session? {
        manager.workspace.selectedLayout.flatMap { manager.workspace.session($0.focusedSessionID) }
    }

    private func updateHint(for session: Session) -> AgentUpdateHint? {
        guard let agent = session.agent?.kind else { return nil }
        return AgentUpdateHint(
            agent: agent, state: session.state, update: manager.agentUpdates[session.id], phase: manager.restarts[session.id],
            canRestart: SessionManager.restartableAgent(session) != nil,
        )
    }

    private var project: Project? {
        session.flatMap { manager.workspace.project($0.projectID) }
    }

    private var strip: (folder: String?, title: String?) {
        guard let session else { return (nil, nil) }
        return session.titleStrip(agentTitle: session.agent?.tail?.title)
    }
}

/// "3 changed +58 −6": what the project's work has changed, plain text at the strip's right in the
/// look of the worktree label, there for the moment you want to know what the agent did. It is
/// also how a new user finds the files column: under the pointer the words swap for
/// "Show Files ⌘\" (both laid out at once, so nothing moves), and a click opens the column. It
/// goes once the column is up, which shows the same numbers, and when nothing changed.
private struct ChangeReadoutView: View {
    let summary: ChangeSummary
    let style: SidebarStyle
    let action: () -> Void
    let onFrame: (UUID, CGRect?) -> Void
    @State private var hovered = false
    /// Keys this view's frame, so one variant of the row going can't erase the frame of the one
    /// that took its place.
    @State private var id = UUID()

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                HStack(spacing: 6.scaled) {
                    Text(summary.headline)
                    if let lines = summary.lines {
                        LineCountsLabel(lines: lines, size: 11.5, style: style)
                    }
                }
                .opacity(hovered ? 0 : 1)
                HStack(spacing: 7.scaled) {
                    Text("Show Files")
                    KeyCaps(keys: ["⌘", "\\"], style: style)
                }
                .opacity(hovered ? 1 : 0)
            }
            .calmFont(size: 12)
            .foregroundStyle(hovered ? style.primary : style.tertiary)
            .padding(.horizontal, 8.scaled)
            .frame(height: 26.scaled)
            .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(hovered ? style.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .accessibilityLabel(summary.spoken)
        .accessibilityHint("Shows the files column")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("titleStrip")) } action: { onFrame(id, $0) }
        .onDisappear { onFrame(id, nil) }
    }
}

/// Hosts the title. It takes clicks only on its controls (the ⋯ button and the files readout), so
/// the strip under the rest of it still drags the window and its double-click still reaches
/// CalmWindow.
final class SessionTitleHost: NSHostingView<SessionTitleView> {
    /// The button's frame in this view's own space, top left origin, as SwiftUI reports it.
    var menuFrame = CGRect.zero
    /// The other controls' frames (the readout, the update hint), one per view that draws one.
    private var controlFrames: [UUID: CGRect] = [:]

    func setControlFrame(_ frame: CGRect?, for id: UUID) {
        controlFrames[id] = frame
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let spot = CGPoint(x: local.x, y: isFlipped ? local.y : bounds.height - local.y)
        let onControl = menuFrame.contains(spot) || controlFrames.values.contains { $0.contains(spot) }
        return onControl ? super.hitTest(point) : nil
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
            files: filesColumn.model,
            filesRoot: { [weak self] in self?.focusedProjectPath },
            onShowMenu: { [weak self] id in self?.showSessionMenuFromTitle(id) },
            // The window's title stays hidden (titleVisibility), but the system still shows it.
            onChange: { [weak self] title in self?.window?.title = title.isEmpty ? BuildVariant.appName : title },
            onMenuFrame: { [weak self] frame in self?.titleHost?.menuFrame = frame },
            onControlFrame: { [weak self] id, frame in self?.titleHost?.setControlFrame(frame, for: id) },
            onRestart: { [weak self] id in self?.restartAgent(in: id) },
            onCancelRestart: { [weak self] id in self?.manager.cancelRestart(id) },
            find: find,
        )
    }
}
