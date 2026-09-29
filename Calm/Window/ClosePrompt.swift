import AppKit
import SwiftUI

/// The question ⌘W asks when something runs in a pane of a split (UIUX.md → Split panes): a small
/// card in the middle of that pane. A sheet on the window says what would end but not which pane
/// it is; where this card stands is the answer, and the workspace dims the other panes while it's
/// up. Return closes, Esc keeps; any other key, or a click elsewhere, keeps and goes through.
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
        about pane: TerminalSurfaceView, in workspace: TerminalWorkspaceView, agentName: String?, style: SidebarStyle,
        close: @escaping () -> Void,
    ) {
        workspace.setAsked(pane.id)
        show(over: pane, agentName: agentName, style: style) { [weak workspace] closes in
            workspace?.setAsked(nil)
            if closes {
                close()
            }
        }
    }

    /// Puts the question on `pane`. `then` gets true for Close and false for Keep, once, however
    /// the question ends.
    private func show(over pane: NSView, agentName: String?, style: SidebarStyle, then finish: @escaping (Bool) -> Void) {
        dismiss()
        guard let container, pane.window != nil else {
            finish(false)
            return
        }
        self.finish = finish
        let view = ClosePromptView(
            agentName: agentName, style: style,
            onClose: { [weak self] in self?.answer(close: true) },
            onKeep: { [weak self] in self?.answer(close: false) },
        )
        let controller = NSHostingController(rootView: view)
        let host = controller.view
        let size = controller.sizeThatFits(in: CGSize(width: 360, height: CGFloat.greatestFiniteMagnitude))
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
            // Another ⌘W doesn't stack a second question, or answer this one.
            if held == .command, event.charactersIgnoringModifiers == "w" {
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

struct ClosePromptView: View {
    let agentName: String?
    let style: SidebarStyle
    let onClose: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2.scaled) {
            Text("\(agentName ?? "Something") is running here")
                .calmFont(size: 13, weight: .medium)
                .foregroundStyle(style.primary)
            Text("Closing the session ends it.")
                .calmFont(size: 12)
                .foregroundStyle(style.secondary)
            HStack(spacing: 8.scaled) {
                Spacer(minLength: 0)
                PromptButton(title: "Keep", key: "esc", isDefault: false, style: style, action: onKeep)
                PromptButton(title: "Close", key: "↵", isDefault: true, style: style, action: onClose)
            }
            .padding(.top, 10.scaled)
        }
        .padding(.horizontal, 16.scaled)
        .padding(.vertical, 13.scaled)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 12.scaled, style: .continuous).fill(style.background))
        .overlay(RoundedRectangle(cornerRadius: 12.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.3)))
        .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 10, y: 4)
        .padding(14)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(agentName ?? "A process") is running in this pane. Close the session?")
    }
}

private struct PromptButton: View {
    let title: String
    let key: String
    let isDefault: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8.scaled, style: .continuous)
        Button(action: action) {
            HStack(spacing: 6.scaled) {
                Text(title)
                    .calmFont(size: 12.5, weight: isDefault ? .medium : nil)
                    .foregroundStyle(isDefault ? style.primary : style.secondary)
                Text(key)
                    .calmFont(size: 11)
                    .foregroundStyle(style.tertiary)
            }
            .padding(.horizontal, 11.scaled)
            .padding(.vertical, 4.scaled)
            // Closing is the one filled button; keeping is outlined. Neither is a state's color.
            .background(shape.fill(isDefault ? style.selection : .clear))
            .background(shape.fill(hovered ? style.selection : .clear))
            .overlay(shape.strokeBorder(style.tertiary.opacity(isDefault ? 0.45 : 0.3)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
