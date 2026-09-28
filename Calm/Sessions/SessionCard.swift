import CalmModel
import SwiftUI

/// An agent session in the sidebar (UIUX.md → Session cards): who, what state, what it last
/// said, and where. Only *needs you* tints the card.
struct SessionCard: View {
    let session: Session
    let agent: AgentKind
    let isSelected: Bool
    let style: SidebarStyle
    /// Set while a scratch card offers its ×; it takes the time's place.
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AgentMark(agent: agent, isWorking: session.state == .working, style: style)
                Text(title)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let onClose {
                    ScratchCloseButton(style: style, action: onClose)
                } else if let date = session.lastReport?.date ?? session.agent?.startedAt {
                    RelativeTimeText(date: date)
                        .font(.system(size: 12))
                        .foregroundStyle(style.tertiary)
                }
            }
            HStack(spacing: 7) {
                StateMark(state: session.state, style: style)
                Text(stateLine)
                    .font(.system(size: 13))
                    .foregroundStyle(session.state == .needsYou ? style.attention : style.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, Self.indent)
            if let progress = session.agent?.tail?.progress, progress.total > 0 {
                TodoProgressLine(progress: progress, style: style)
                    .padding(.leading, Self.indent)
            }
            if let message = recap {
                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(1.5)
                    .foregroundStyle(style.secondary)
                    .lineLimit(2)
                    .padding(.leading, Self.indent)
                    .transition(.opacity)
            }
            if let worktree = GitRoot.worktreeName(session.workingDirectory) {
                Label(worktree, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 12))
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .padding(.leading, Self.indent)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(border))
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The agent's own title (from its transcript) is steadier than the terminal title.
    private var title: String {
        session.title(agentTitle: session.agent?.tail?.title)
    }

    /// "Working · Fixing the token mock".
    private var stateLine: String {
        guard session.state == .working, let step = session.agent?.tail?.step else { return session.state.label }
        return "\(session.state.label) · \(step)"
    }

    /// While the agent waits for you, what it asked; otherwise the latest thing it said.
    private var recap: String? {
        if session.state == .needsYou {
            return session.lastReport?.message ?? session.agent?.tail?.lastMessage
        }
        return session.agent?.tail?.lastMessage ?? session.lastReport?.message
    }

    /// The detail lines start under the title, past the agent mark.
    static let indent: CGFloat = 36

    private var background: Color {
        if session.state == .needsYou {
            return style.attention.opacity(isSelected ? 0.2 : 0.14)
        }
        return isSelected ? style.selection : .clear
    }

    /// A hairline that gives a highlighted card its edge.
    private var border: Color {
        if session.state == .needsYou {
            return style.attention.opacity(0.22)
        }
        return isSelected ? style.primary.opacity(0.07) : .clear
    }

    private var accessibilityText: String {
        [agent.displayName, title, stateLine, recap]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// A thin bar and "3 of 5": the agent's todo list.
struct TodoProgressLine: View {
    let progress: TodoProgress
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.selection)
                    Capsule()
                        .fill(style.secondary)
                        .frame(width: geometry.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                }
            }
            .frame(height: 4)
            Text("\(progress.done) of \(progress.total)")
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(style.tertiary)
                .fixedSize()
        }
        .animation(.easeInOut(duration: 0.3), value: progress)
    }
}

/// The agent's letter mark, in the agent's own soft tint. While the agent works it breathes slowly
/// and faintly, never enough to pull the eye (and not at all with Reduce Motion).
struct AgentMark: View {
    let agent: AgentKind
    let isWorking: Bool
    let style: SidebarStyle
    @State private var dimmed = false

    var body: some View {
        let tint = agent.tint(dark: style.isDark)
        Text(agent.monogram)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: 26, height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.16)))
            .opacity(isWorking && dimmed ? 0.45 : 1)
            .onAppear(perform: updatePulse)
            .onChange(of: isWorking) { updatePulse() }
    }

    private func updatePulse() {
        guard isWorking, !Motion.isReduced else {
            withAnimation(.easeOut(duration: 0.3)) { dimmed = false }
            return
        }
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
            dimmed = true
        }
    }
}

/// The state's shape: shape as well as color, so state never depends on color alone.
struct StateMark: View {
    let state: SessionState
    let style: SidebarStyle

    var body: some View {
        switch state {
        case .needsYou:
            Circle().fill(style.attention).frame(width: 8, height: 8)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.tertiary)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.failure)
        case .working:
            Circle().stroke(style.secondary, lineWidth: 1.5).frame(width: 8, height: 8)
        case .idle:
            Circle().fill(style.tertiary.opacity(0.6)).frame(width: 6, height: 6)
        }
    }
}

/// "now", "2m", "3h", "4d", refreshed twice a minute.
struct RelativeTimeText: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text(Self.format(context.date.timeIntervalSince(date)))
                .monospacedDigit()
        }
    }

    static func format(_ interval: TimeInterval) -> String {
        switch interval {
        case ..<60: "now"
        case ..<3600: "\(Int(interval / 60))m"
        case ..<86400: "\(Int(interval / 3600))h"
        default: "\(Int(interval / 86400))d"
        }
    }
}

extension SessionState {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .working: "Working"
        case .needsYou: "Needs you"
        case .done: "Done"
        case .failed: "Failed"
        }
    }
}

extension AgentKind {
    /// A soft color of its own for the agent's mark, so agents tell apart at a glance; low in
    /// saturation, and the mark's letter keeps it from resting on color alone.
    func tint(dark: Bool) -> Color {
        let hue = switch self {
        case .claudeCode: 0.07
        case .codex: 0.6
        case .openCode: 0.48
        case .pi: 0.8
        case .omp: 0.33
        }
        return Color(hue: hue, saturation: dark ? 0.32 : 0.45, brightness: dark ? 0.88 : 0.5)
    }

    /// A letter mark, not the agent's logo.
    var monogram: String {
        switch self {
        case .claudeCode: "C"
        case .codex: "X"
        case .openCode: "O"
        case .pi: "π"
        case .omp: "ω"
        }
    }
}
