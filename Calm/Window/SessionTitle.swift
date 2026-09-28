import AppKit
import CalmModel
import SwiftUI

/// The focused session's name in the header row above the terminal (UIUX.md → Title bar), with
/// the folder it's in on a quieter line below, like a window's title and subtitle.
struct SessionTitleView: View {
    static let leadingInset: CGFloat = 16

    let manager: SessionManager
    let style: SidebarStyle
    /// Gets the window title whenever it changes.
    var onChange: (String) -> Void = { _ in }

    var body: some View {
        let strip = strip
        // Alone (a plain shell), the folder is the title and takes its line.
        let title = strip.title ?? strip.folder ?? ""
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(style.primary)
                .truncationMode(.tail)
            if strip.title != nil, let folder = strip.folder {
                Text(folder)
                    .font(.system(size: 11))
                    .foregroundStyle(style.tertiary)
                    .truncationMode(.head)
            }
        }
        .lineLimit(1)
        .padding(.leading, Self.leadingInset)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .animation(nil, value: strip.folder)
        .animation(nil, value: strip.title)
        // The window's title carries it for VoiceOver, the Window menu and Mission Control.
        .accessibilityHidden(true)
        .onChange(of: title, initial: true) { _, title in onChange(title) }
    }

    private var strip: (folder: String?, title: String?) {
        guard let layout = manager.workspace.selectedLayout,
              let session = manager.workspace.session(layout.focusedSessionID)
        else { return (nil, nil) }
        return session.titleStrip(agentTitle: session.agent?.tail?.title)
    }
}

/// Hosts the title without taking clicks: the strip under it still drags the window, and its
/// double-click still reaches CalmWindow.
final class SessionTitleHost: NSHostingView<SessionTitleView> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
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
        // The window's title stays hidden (titleVisibility), but the system still shows it.
        SessionTitleView(manager: manager, style: style) { [weak self] title in
            self?.window?.title = title.isEmpty ? "Calm" : title
        }
    }
}
