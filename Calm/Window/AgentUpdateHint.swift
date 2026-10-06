import CalmAgents
import CalmModel
import SwiftUI

/// What the title strip's update hint says (UIUX.md → Title bar): the agent in front runs an
/// older version than the one installed, or a restart is waiting or under way. Nil when there is
/// nothing to say.
struct AgentUpdateHint: Equatable {
    /// At rest: "Claude Code 2.1.291", "Restarts after this turn", "Restarting…".
    let label: String
    /// Under the pointer, what a click does; nil when a click does nothing.
    let action: String?
    /// The click takes back a restart that is waiting.
    let cancels: Bool
    let help: String
    let symbol: String

    init?(agent: AgentKind, state: SessionState, update: AgentUpdate?, phase: RestartPhase?, canRestart: Bool) {
        let name = agent.displayName
        switch phase {
        case .restarting:
            label = "Restarting…"
            action = nil
            cancels = false
            help = "\(name) is starting again on this conversation."
            symbol = "arrow.clockwise"
        case .afterTurn:
            label = "Restarts after this turn"
            action = "Don't Restart"
            cancels = true
            help = "\(name) restarts on this conversation when its turn ends."
            symbol = "arrow.clockwise"
        case nil:
            guard let update else { return nil }
            label = update.installed.map { "\(name) \($0)" } ?? "\(name) updated"
            action = canRestart ? (SessionManager.isMidTurn(state) ? "Restart After This Turn" : "Restart \(name)") : nil
            cancels = false
            let running = update.running.map { "\(name) \($0) runs here" } ?? "An older \(name) runs here"
            let installed = update.installed.map { "\(running); \($0) is installed." } ?? "\(running); a newer one is installed."
            help = canRestart ? installed : installed + " Quit it and start it again to use the new one."
            symbol = "arrow.up"
        }
    }
}

/// The hint: needs you's amber as a soft capsule, quiet text otherwise (chosen by the author,
/// 2026-10-06, over an accent tile and an outlined capsule). Under the pointer the words become
/// what a click does, on a stronger fill; both are laid out at once, so nothing moves.
struct AgentUpdateHintView: View {
    let hint: AgentUpdateHint
    let style: SidebarStyle
    let onFrame: (UUID, CGRect?) -> Void
    let perform: () -> Void
    @State private var hovered = false
    /// Keys this view's frame for the strip's hit test, as the files readout does.
    @State private var id = UUID()

    var body: some View {
        let active = hovered && hint.action != nil
        Button {
            if hint.action != nil {
                perform()
            }
        } label: {
            HStack(spacing: 6.scaled) {
                Image(systemName: hint.symbol)
                    .calmFont(size: 9.5, weight: .bold)
                ZStack {
                    Text(hint.label)
                        .opacity(active ? 0 : 1)
                    if let action = hint.action {
                        Text(action)
                            .opacity(active ? 1 : 0)
                    }
                }
            }
            .calmFont(size: 12, weight: .medium)
            .foregroundStyle(style.attention)
            .lineLimit(1)
            .padding(.leading, 9.scaled)
            .padding(.trailing, 11.scaled)
            .frame(height: 24.scaled)
            .background(Capsule().fill(style.attention.opacity(active ? 0.27 : 0.15)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .help(hint.help)
        .accessibilityLabel(hint.label)
        .accessibilityHint(hint.action ?? "")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("titleStrip")) } action: { onFrame(id, $0) }
        .onDisappear { onFrame(id, nil) }
    }
}
