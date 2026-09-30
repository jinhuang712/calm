import AppKit
import CalmModel
import SwiftUI

/// The question ⌘W asks when something runs in a pane of a split (UIUX.md → Split panes): words
/// in the middle of that pane, on a clearing of its own background. A sheet on the window says
/// what would end but not which pane it is; where these words stand is the answer, and the
/// workspace dims the other panes while it's up. Return closes, Esc keeps; any other key, or a
/// click elsewhere, keeps and goes through.
@MainActor
final class ClosePrompt {
    private weak var container: NSView?
    private var host: NSView?
    private var hostController: NSViewController?
    private var monitor: Any?
    private var finish: ((Bool) -> Void)?

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        host != nil
    }

    /// Asks about `pane`, with the split's other panes dimmed while the question is up. Calls
    /// `close` if the answer is Close.
    func ask(
        about pane: TerminalSurfaceView, in workspace: TerminalWorkspaceView, agent: AgentKind?, style: SidebarStyle,
        close: @escaping () -> Void,
    ) {
        workspace.setAsked(pane.id)
        show(over: pane, agent: agent, style: style) { [weak workspace] closes in
            workspace?.setAsked(nil)
            if closes {
                close()
            }
        }
    }

    /// Puts the question on `pane`. `then` gets true for Close and false for Keep, once, however
    /// the question ends.
    private func show(over pane: NSView, agent: AgentKind?, style: SidebarStyle, then finish: @escaping (Bool) -> Void) {
        dismiss()
        guard let container, pane.window != nil else {
            finish(false)
            return
        }
        self.finish = finish
        let view = ClosePromptView(
            agent: agent, style: style,
            onClose: { [weak self] in self?.answer(close: true) },
            onKeep: { [weak self] in self?.answer(close: false) },
        )
        let controller = NSHostingController(rootView: view)
        let host = controller.view
        // Narrow enough for its pane, so the line wraps in a small one instead of running out of it.
        let size = controller.sizeThatFits(in: CGSize(width: min(360, pane.bounds.width - 32), height: CGFloat.greatestFiniteMagnitude))
        let paneFrame = pane.convert(pane.bounds, to: container)
        host.frame = NSRect(x: paneFrame.midX - size.width / 2, y: paneFrame.midY - size.height / 2, width: size.width, height: size.height)
        hostController = controller
        container.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.16)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            let incoming = UncheckedSendable(event)
            return MainActor.assumeIsolated { () -> UncheckedSendable<NSEvent?> in
                guard let self else { return UncheckedSendable(incoming.value) }
                return UncheckedSendable(self.handle(incoming.value))
            }.value
        }
    }

    /// Keep, when the question is still up (the layout changed, or the pane went by itself).
    func dismiss() {
        answer(close: false)
    }

    /// What Return and Esc do, for self-tests (a headless window is never key).
    func answerForTesting(close: Bool) {
        answer(close: close)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let host, event.window === host.window else { return event }
        switch event.type {
        case .keyDown:
            let held = event.modifierFlags.intersection([.command, .control, .option])
            if held.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
                answer(close: true)
                return nil
            }
            if event.keyCode == 53 {
                answer(close: false)
                return nil
            }
            // ⌘W again takes the question back. The key is used up: it must not reach the menu
            // and ask again.
            if held == .command, event.charactersIgnoringModifiers == "w" {
                answer(close: false)
                return nil
            }
            answer(close: false)
            return event
        default:
            if let container, !host.frame.contains(container.convert(event.locationInWindow, from: nil)) {
                answer(close: false)
            }
            return event
        }
    }

    private func answer(close: Bool) {
        guard let host else { return }
        self.host = nil
        hostController = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        Motion.fadeOutAndRemove(host, duration: 0.12)
        let finish = finish
        self.finish = nil
        finish?(close)
    }
}
