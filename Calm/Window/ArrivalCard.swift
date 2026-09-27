import AppKit
import CalmModel
import SwiftUI

/// The arrival card (FEATURES.md → F6, UIUX.md → Arrival card): switching into an agent session
/// shows, at the top of its pane, what it is and what it last said, so there's no need to
/// scroll back to remember. It fades on the first keystroke or after a few seconds; ⌘⇧I
/// recalls it. It sits at the top, never over the agent's input line.
@MainActor
final class ArrivalCard {
    private weak var container: NSView?
    private var host: NSView?
    private var hostController: NSViewController?
    private var hideTask: Task<Void, Never>?
    private var keyMonitor: Any?

    static let visibleFor: Duration = .seconds(5)

    init(container: NSView) {
        self.container = container
    }

    /// Shows the card over the top of `pane` for an agent session; does nothing for plain shells.
    func show(for session: Session, over pane: NSView, style: SidebarStyle) {
        hide(animated: false)
        guard let container, let agent = session.agent, pane.window != nil else { return }
        let view = ArrivalCardView(session: session, agent: agent, style: style) { [weak self] in self?.hide(animated: true) }
        let controller = NSHostingController(rootView: view)
        let host = controller.view
        let paneFrame = pane.convert(pane.bounds, to: container)
        let width = min(paneFrame.width - 24, 560)
        let height = controller.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height
        host.frame = NSRect(x: paneFrame.midX - width / 2, y: paneFrame.maxY - height - 10, width: width, height: height)
        hostController = controller
        container.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.2)

        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.visibleFor)
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
        // The first keystroke means the user is back at work: step aside (the key still goes through).
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.hide(animated: true)
            return event
        }
    }

    func hide(animated: Bool) {
        hideTask?.cancel()
        hideTask = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        guard let host else { return }
        self.host = nil
        hostController = nil
        if animated {
            Motion.fadeOutAndRemove(host, duration: 0.25)
        } else {
            host.removeFromSuperview()
        }
    }

    var isShowing: Bool {
        host != nil
    }
}

struct ArrivalCardView: View {
    let session: Session
    let agent: AgentRun
    let style: SidebarStyle
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                StateMark(state: session.state, style: style)
                Text(session.title(agentTitle: agent.tail?.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                Text("·").foregroundStyle(style.tertiary)
                Text(session.state.label)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
                Text("·").foregroundStyle(style.tertiary)
                RelativeTimeText(date: session.lastReport?.date ?? agent.startedAt)
                    .font(.system(size: 12))
                    .foregroundStyle(style.tertiary)
                Spacer(minLength: 0)
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style.tertiary.opacity(0.25)))
        .shadow(color: .black.opacity(style.isDark ? 0.3 : 0.1), radius: 14, y: 4)
        .padding(.horizontal, 2)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .accessibilityElement(children: .combine)
    }

    /// What it asked, while it waits for you; otherwise the last thing it said.
    private var message: String? {
        if session.state == .needsYou {
            return session.lastReport?.message ?? agent.tail?.lastMessage
        }
        return agent.tail?.lastMessage ?? session.lastReport?.message
    }
}
