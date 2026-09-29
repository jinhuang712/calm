import AppKit
import CalmModel
import SwiftUI

/// Hold ⌃ and press Tab to cycle sessions in sidebar order, top to bottom; release ⌃ to settle
/// on the chosen one (UIUX.md → Motion → Session switching). A quick ⌃Tab moves to the next
/// session down without showing anything; holding shows small live previews.
@MainActor
final class SessionSwitcher {
    private weak var controller: MainWindowController?
    private let model = SessionSwitcherModel()
    private var host: NSView?
    private var monitor: Any?
    private var showTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    var isActive: Bool {
        !model.sessions.isEmpty
    }

    init(controller: MainWindowController) {
        self.controller = controller
    }

    func install() {
        guard monitor == nil else { return }
        // Local monitors run on the main thread, before the event reaches the terminal.
        // Not `self?.handle(event) ?? event`: a nil from `handle` means "consumed", and `??`
        // would hand the event straight back to the terminal.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func uninstall() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        close()
    }

    // MARK: Keys

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window = controller?.window, event.window === window else { return event }
        let modifiers = event.modifierFlags.intersection([.control, .command, .option, .shift])
        switch event.type {
        case .keyDown where event.keyCode == KeyCode.tab && modifiers.subtracting(.shift) == .control:
            if isActive {
                move(modifiers.contains(.shift) ? -1 : 1)
            } else {
                open(backwards: modifiers.contains(.shift))
            }
            return nil
        case .keyDown where isActive:
            switch event.keyCode {
            case KeyCode.escape: close()
            case KeyCode.returnKey: commit()
            case KeyCode.leftArrow: move(-1)
            case KeyCode.rightArrow: move(1)
            default: break
            }
            return nil
        case .flagsChanged where isActive && !event.modifierFlags.contains(.control):
            commit()
            return event
        default:
            return event
        }
    }

    // MARK: Cycling

    private func open(backwards: Bool) {
        guard let manager = controller?.manager else { return }
        let sessions = manager.orderedSessions
        guard sessions.count > 1 else { return }
        let focused = manager.workspace.selectedLayout?.focusedSessionID
        // With no session selected the first press goes to the first session (⇧: the last).
        let current = sessions.firstIndex { $0.id == focused } ?? (backwards ? 0 : -1)
        model.sessions = sessions
        model.index = current
        move(backwards ? -1 : 1)
        // Like ⌘Tab: a quick press-and-release switches without flashing the switcher.
        showTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.show()
        }
    }

    private func move(_ step: Int) {
        guard isActive else { return }
        let count = model.sessions.count
        model.index = ((model.index + step) % count + count) % count
    }

    private func commit() {
        guard isActive, model.sessions.indices.contains(model.index) else { return close() }
        let id = model.sessions[model.index].id
        close()
        controller?.select(id)
    }

    /// Closes without switching, e.g. when the window stops being key while ⌃ is still held
    /// (the release would never reach Calm, and the switcher would keep swallowing keys).
    func cancel() {
        guard isActive else { return }
        close()
    }

    private func close() {
        showTask?.cancel()
        showTask = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        model.sessions = []
        model.previews = [:]
        controller?.restorePaneVisibility()
        guard let host else { return }
        self.host = nil
        Motion.fadeOutAndRemove(host, duration: 0.12)
    }

    // MARK: Showing

    private func show() {
        guard isActive, host == nil, let controller, let container = controller.window?.contentView else { return }
        refreshPreviews()
        let view = SessionSwitcherView(
            model: model,
            style: controller.sidebarStyle,
            projectName: { [weak controller] id in controller?.manager.workspace.project(id)?.name ?? "" },
            onPick: { [weak self] index in
                self?.model.index = index
                self?.commit()
            },
            onDismiss: { [weak self] in self?.close() },
        )
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        self.host = host
        Motion.fadeIn(host, duration: 0.14)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPreviews() }
        }
    }

    /// Keeps the previews live: panes in other layouts keep rendering while the switcher is
    /// open. Only cards near the selection are refreshed, so many sessions stay cheap.
    private func refreshPreviews() {
        guard let manager = controller?.manager else { return }
        var previews = model.previews
        for (index, session) in model.sessions.enumerated() where abs(index - model.index) <= 3 {
            guard let pane = manager.panes[session.id] else { continue }
            pane.setVisible(true)
            previews[session.id] = PanePreview.image(of: pane, width: SessionSwitcherView.previewSize.width * 2)
        }
        model.previews = previews
    }

    private enum KeyCode {
        static let tab: UInt16 = 48
        static let returnKey: UInt16 = 36
        static let escape: UInt16 = 53
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
    }
}

@MainActor
@Observable
final class SessionSwitcherModel {
    var sessions: [Session] = []
    var index = 0
    var previews: [Session.ID: NSImage] = [:]
}

/// A scaled-down picture of what a pane shows.
@MainActor
enum PanePreview {
    static func image(of pane: NSView, width: CGFloat) -> NSImage? {
        let bounds = pane.bounds
        guard bounds.width > 1, bounds.height > 1,
              let rep = pane.bitmapImageRepForCachingDisplay(in: bounds)
        else { return nil }
        pane.cacheDisplay(in: bounds, to: rep)
        let size = NSSize(width: width, height: width * bounds.height / bounds.width)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(origin: .zero, size: size))
        image.unlockFocus()
        return image
    }
}

struct SessionSwitcherView: View {
    static let previewSize = CGSize(width: 208, height: 130)

    let model: SessionSwitcherModel
    let style: SidebarStyle
    let projectName: (Project.ID) -> String
    let onPick: (Int) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.001) // catches clicks outside the switcher
                .onTapGesture(perform: onDismiss)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(model.sessions.enumerated()), id: \.element.id) { index, session in
                            card(session, isSelected: index == model.index)
                                .id(session.id)
                                .onTapGesture { onPick(index) }
                        }
                    }
                    .padding(14)
                }
                .scrollIndicators(.never)
                .onChange(of: model.index, initial: true) {
                    guard model.sessions.indices.contains(model.index) else { return }
                    Motion.animate(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(model.sessions[model.index].id, anchor: .center)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: min(CGFloat(model.sessions.count), 4.5) * (Self.previewSize.width + 10) + 28)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(style.background))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style.tertiary.opacity(0.25)))
            .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 24, y: 8)
            .padding(40)
        }
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    private func card(_ session: Session, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.selection)
                if let image = model.previews[session.id] {
                    Image(nsImage: image)
                        .resizable().scaledToFill()
                        .frame(width: Self.previewSize.width, height: Self.previewSize.height, alignment: .topLeading)
                        .clipped()
                } else {
                    Image(systemName: "terminal")
                        .calmFont(size: 20, weight: .light)
                        .foregroundStyle(style.tertiary)
                }
            }
            .frame(width: Self.previewSize.width, height: Self.previewSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? style.primary.opacity(0.55) : style.tertiary.opacity(0.2), lineWidth: isSelected ? 2 : 1),
            )
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .calmFont(size: 12, weight: isSelected ? .medium : .regular)
                    .foregroundStyle(isSelected ? style.primary : style.secondary)
                Text(projectName(session.projectID))
                    .calmFont(size: 11)
                    .foregroundStyle(style.tertiary)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: Self.previewSize.width, alignment: .leading)
        }
        .padding(4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
