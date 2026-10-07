import AppKit
import CalmModel
import SwiftUI

/// Shows the session menu over the window and does what a system menu would: ↑ ↓ ← → move, ↵ or
/// space chooses, → opens Move to Project and ← or esc closes it, a letter jumps to the next item
/// that starts with it, esc or a click outside closes the menu. Keys go to the menu while it's
/// up, never to the terminal behind it (a local monitor, as `ClosePrompt` does).
@MainActor
final class SessionMenuController {
    private weak var container: NSView?
    private var host: SessionMenuHost?
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private(set) var sessionID: Session.ID?
    private(set) var content = SessionMenuContent()
    let state = SessionMenuState()
    private var perform: (SessionMenuContent.Action) -> Void = { _ in }

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        host != nil
    }

    func show(
        _ content: SessionMenuContent, for id: Session.ID, at anchor: SessionMenuAnchor, style: SidebarStyle,
        perform: @escaping (SessionMenuContent.Action) -> Void,
    ) {
        hide()
        guard let container else { return }
        self.content = content
        self.perform = perform
        sessionID = id
        state.reset()
        let view = SessionMenuOverlay(
            content: content, anchor: anchor, style: style, state: state,
            choose: { [weak self] index in self?.choose(index) },
            chooseProject: { [weak self] index in self?.chooseProject(index) },
        )
        let host = SessionMenuHost(rootView: view)
        host.menuFrames = { [weak self] in self?.frames ?? [] }
        // Under the transparent title bar the host's safe area moved the whole overlay down 32 pt,
        // so the menu opened that far below the ⋯ button and the pointer, and its frames missed
        // the clicks on its top. The overlay takes the window's whole content, as the title does.
        host.safeAreaRegions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.host = host
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
        ]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: container.window, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        self.anchor = anchor
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: session menu: \(describe())\n".utf8))
        }
    }

    /// Where the menu was asked to open, for the self-test log.
    private var anchor: SessionMenuAnchor?

    func hide() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        host?.removeFromSuperview()
        host = nil
        sessionID = nil
    }

    /// The menu's and the projects list's frames, top-left origin, as the overlay reports them.
    private var frames: [CGRect] {
        [state.menuFrame, state.projectsOpen ? state.projectsFrame : .zero].filter { !$0.isEmpty }
    }

    // MARK: Keys and clicks

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .keyDown:
            return key(event) ? nil : event
        default:
            // A click outside closes the menu, as a system menu's does; a right-click goes on, so
            // a right-click on another card opens that card's menu.
            guard let host, event.window === host.window else {
                hide()
                return event
            }
            if host.isOnMenu(host.convert(event.locationInWindow, from: nil)) {
                return event
            }
            hide()
            return event.type == .leftMouseDown ? nil : event
        }
    }

    /// One key, from the monitor or a self-test. True when the menu used it.
    @discardableResult
    func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: press(.up)
        case 125: press(.down)
        case 123: press(.left)
        case 124: press(.right)
        case 36, 76, 49: pressReturn()
        case 53: pressEscape()
        default:
            guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]),
                  let letter = event.charactersIgnoringModifiers?.first, letter.isLetter
            else {
                // ⌘ keys go on (⌘W still closes the session, and the menu with it).
                hide()
                return false
            }
            if state.projectsOpen {
                return true
            }
            state.hot = content.item(startingWith: letter, after: state.hot) ?? state.hot
        }
        return true
    }

    enum TestKey: String {
        case up, down, left, right, enter, esc
    }

    func pressForTesting(_ key: TestKey) {
        switch key {
        case .up: press(.up)
        case .down: press(.down)
        case .left: press(.left)
        case .right: press(.right)
        case .enter: pressReturn()
        case .esc: pressEscape()
        }
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: session menu key \(key.rawValue): \(describe())\n".utf8))
        }
    }

    private func press(_ key: SessionMenuContent.Key) {
        if state.projectsOpen, state.hot.map(content.opensProjects(at:)) == true, state.projectHot != nil || key == .right {
            switch key {
            case .down: state.projectHot = min((state.projectHot ?? -1) + 1, content.projects.count - 1)
            case .up: state.projectHot = max((state.projectHot ?? 1) - 1, 0)
            case .right: state.projectHot = state.projectHot ?? 0
            case .left: state.projectHot = nil
                state.projectsOpen = false
            }
            return
        }
        if key == .right, let hot = state.hot, content.opensProjects(at: hot) {
            state.projectsOpen = true
            state.projectHot = 0
            return
        }
        let next = content.next(from: state.hot, key: key, lastTile: state.lastTile)
        if let next, next < content.tiles.count {
            state.lastTile = next
        }
        state.hot = next
        state.projectsOpen = next.map(content.opensProjects(at:)) == true
        state.projectHot = nil
    }

    private func pressReturn() {
        if state.projectsOpen, let index = state.projectHot {
            chooseProject(index)
        } else if let hot = state.hot {
            choose(hot)
        }
    }

    private func pressEscape() {
        if state.projectsOpen, state.projectHot != nil {
            state.projectsOpen = false
            state.projectHot = nil
        } else {
            hide()
        }
    }

    private func choose(_ index: Int) {
        if content.opensProjects(at: index) {
            state.hot = index
            state.projectsOpen = true
            state.projectHot = state.projectHot ?? 0
            return
        }
        guard let action = content.action(at: index) else { return }
        let perform = perform
        hide()
        perform(action)
    }

    private func chooseProject(_ index: Int) {
        guard content.projects.indices.contains(index) else { return }
        let perform = perform
        let project = content.projects[index].id
        hide()
        perform(.moveTo(project))
    }

    /// The menu in one line, for self-test logs: the header, the tiles, the rows by group, and
    /// what is highlighted.
    func describe() -> String {
        var parts: [String] = []
        if let header = content.header {
            parts.append("header \(header.agent.displayName)\(header.version.map { " " + $0 } ?? "")")
        }
        if !content.tiles.isEmpty {
            parts
                .append("tiles " + content.tiles
                    .map { "\($0.title)/\($0.detail)\($0.amber ? " amber" : "")\($0.action == nil ? " off" : "")" }
                    .joined(separator: ", "))
        }
        for group in content.groups {
            let rows = group.rows.map { $0.title + ($0.key.map { " " + $0 } ?? "") + ($0.opensProjects ? " ›" : "") }
                .joined(separator: ", ")
            parts.append((group.label.map { $0 + ": " } ?? "") + rows)
        }
        if let hot = state.hot, let title = content.title(at: hot) {
            parts.append("hot \(title)")
        }
        if state.projectsOpen {
            parts.append("projects " + content.projects.map(\.name).joined(separator: ", ")
                + (state.projectHot.flatMap { content.projects.indices.contains($0) ? " (hot \(content.projects[$0].name))" : nil } ?? ""))
        }
        // Where it was asked to open and where it is, both top-left in the window's content.
        switch anchor {
        case let .below(button): parts.append("under \(Self.rounded(button))")
        case let .point(point): parts.append("at pointer \(Int(point.x)),\(Int(point.y))")
        case nil: break
        }
        if !state.menuFrame.isEmpty {
            parts.append("menu \(Self.rounded(state.menuFrame)) (in host \(Self.rounded(state.menuFrameInHost)))")
        }
        return parts.joined(separator: " | ")
    }
}

private extension SessionMenuController {
    static func rounded(_ rect: CGRect) -> String {
        "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))×\(Int(rect.height))"
    }
}

/// The overlay's host. It takes clicks only on the menu and the projects list: everywhere else
/// it is see-through, and `SessionMenuController` closes the menu on a click there.
private final class SessionMenuHost: NSHostingView<SessionMenuOverlay> {
    var menuFrames: () -> [CGRect] = { [] }

    /// Whether a point in this view's own space falls on the menu or the projects list.
    func isOnMenu(_ point: NSPoint) -> Bool {
        let topLeft = CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
        return menuFrames().contains { $0.contains(topLeft) }
    }

    /// SwiftUI answers for the whole overlay; only the menu's own frames take the pointer, so the
    /// rest stays see-through to hover and clicks.
    override func hitTest(_ point: NSPoint) -> NSView? {
        isOnMenu(convert(point, from: superview)) ? super.hitTest(point) : nil
    }
}
