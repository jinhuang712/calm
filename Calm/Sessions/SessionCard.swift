import CalmModel
import SwiftUI

/// An agent session in the sidebar (UIUX.md → Session cards): who, what state, what it last
/// said, and where. Only *needs you* tints the card.
struct SessionCard: View {
    let session: Session
    let agent: AgentKind
    let isSelected: Bool
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AgentMark(agent: agent, isWorking: session.state == .working, style: style)
                Text(session.displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                if let date = session.lastReport?.date ?? session.agent?.startedAt {
                    RelativeTimeText(date: date)
                        .font(.system(size: 11))
                        .foregroundStyle(style.tertiary)
                }
            }
            HStack(spacing: 6) {
                StateMark(state: session.state, style: style)
                Text(session.state.label)
                    .font(.system(size: 12))
                    .foregroundStyle(session.state == .needsYou ? style.primary : style.secondary)
            }
            .padding(.leading, 26)
            if let message = session.lastReport?.message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(style.secondary)
                    .lineLimit(2)
                    .padding(.leading, 26)
                    .transition(.opacity)
            }
            if let worktree = GitRoot.worktreeName(session.workingDirectory) {
                Label(worktree, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 26)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(background),
        )
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if session.state == .needsYou {
            return style.attention.opacity(isSelected ? 0.26 : 0.19)
        }
        return isSelected ? style.selection : .clear
    }

    private var accessibilityText: String {
        [agent.displayName, session.displayTitle, session.state.label, session.lastReport?.message]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// The agent's letter mark. While the agent works it breathes slowly and faintly, never enough
/// to pull the eye (and not at all with Reduce Motion).
struct AgentMark: View {
    let agent: AgentKind
    let isWorking: Bool
    let style: SidebarStyle
    @State private var dimmed = false

    var body: some View {
        Text(agent.monogram)
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(style.secondary)
            .frame(width: 18, height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(style.selection))
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
            Circle().fill(style.attention).frame(width: 7, height: 7)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.tertiary)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.failure)
        case .working:
            Circle().stroke(style.tertiary, lineWidth: 1.2).frame(width: 7, height: 7)
        case .idle:
            Circle().fill(style.tertiary.opacity(0.5)).frame(width: 5, height: 5)
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
