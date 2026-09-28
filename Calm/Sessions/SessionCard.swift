import CalmModel
import SwiftUI

/// An agent session in the sidebar (UIUX.md → Session cards): who, what state, what it last
/// said, and where. Each state has its look: idle recedes, working is a soft blue with the
/// agent's mark in motion, *needs you* is amber, done is sage until you look. An idle card
/// (read, or never started) is also shorter, so the sessions that need a look stand out.
struct SessionCard: View {
    let session: Session
    let agent: AgentKind
    let isSelected: Bool
    let style: SidebarStyle
    /// The pointer rests on the card: a long title glides to its end.
    var isHovered = false
    /// Set while a scratch card offers its ×; it takes the time's place.
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AgentLogo(agent: agent, state: session.state, style: style)
                ScrollingTitle(text: title, isHovered: isHovered)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(isAsleep ? style.secondary : style.primary)
                Spacer(minLength: 4)
                if let onClose {
                    ScratchCloseButton(style: style, action: onClose)
                } else if let date = session.lastReport?.date ?? session.agent?.startedAt {
                    RelativeTimeText(date: date)
                        .font(.system(size: 12))
                        .foregroundStyle(style.tertiary)
                }
            }
            if !isCompact {
                stateLine
                    .padding(.leading, Self.indent)
            }
            if !isCompact, let progress = session.agent?.tail?.progress, progress.total > 0 {
                TodoProgressLine(progress: progress, style: style)
                    .padding(.leading, Self.indent)
            }
            if let message = recap {
                Text(message)
                    .font(.system(size: 13))
                    .lineSpacing(1.5)
                    .foregroundStyle(style.secondary)
                    .lineLimit(isCompact ? 1 : 2)
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
        .padding(.horizontal, 12)
        .padding(.vertical, isCompact ? 8 : 12)
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

    /// Idle cards drop the state line and the progress bar and keep one line of recap. Selected
    /// or not, so picking a card never makes the list jump.
    private var isCompact: Bool {
        session.state == .idle
    }

    /// Idle, and not the session you're in: the card recedes.
    private var isAsleep: Bool {
        session.state == .idle && !isSelected
    }

    @ViewBuilder
    private var stateLine: some View {
        if session.state == .working {
            // Twice a minute, for the time it's been at it.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ShimmerText(text: workingLine(at: context.date), color: style.working, highlight: style.workingHighlight)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        } else {
            HStack(spacing: 7) {
                StateMark(state: session.state, style: style)
                Text(session.state.label)
                    .font(.system(size: 13, weight: session.state == .done ? .medium : .regular))
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
            }
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .needsYou: style.attention
        case .done: style.done
        case .idle: style.tertiary
        case .working, .failed: style.secondary
        }
    }

    /// "Working · Fixing the token mock", or "Working · 4m" when the agent names no step.
    func workingLine(at now: Date) -> String {
        if let step = session.agent?.tail?.step {
            return "\(SessionState.working.label) · \(step)"
        }
        guard let since = session.stateSince, let elapsed = Self.elapsed(now.timeIntervalSince(since)) else {
            return SessionState.working.label
        }
        return "\(SessionState.working.label) · \(elapsed)"
    }

    /// "4m", "2h"; nothing in the first minute.
    static func elapsed(_ interval: TimeInterval) -> String? {
        switch interval {
        case ..<60: nil
        case ..<3600: "\(Int(interval / 60))m"
        default: "\(Int(interval / 3600))h"
        }
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

    /// The state's color and how strongly the card takes it.
    private struct Tint {
        let color: Color
        let fill: Double
        let selectedFill: Double
        let edge: Double
    }

    private var tint: Tint? {
        switch session.state {
        case .needsYou: Tint(color: style.attention, fill: 0.14, selectedFill: 0.2, edge: 0.22)
        case .working: Tint(color: style.working, fill: 0.1, selectedFill: 0.15, edge: 0.24)
        case .done: Tint(color: style.done, fill: 0.1, selectedFill: 0.15, edge: 0.24)
        case .idle, .failed: nil
        }
    }

    private var background: Color {
        guard let tint else { return isSelected ? style.selection : .clear }
        return tint.color.opacity(isSelected ? tint.selectedFill : tint.fill)
    }

    /// A hairline that gives a highlighted card its edge.
    private var border: Color {
        guard let tint else { return isSelected ? style.primary.opacity(0.07) : .clear }
        return tint.color.opacity(tint.edge)
    }

    private var accessibilityText: String {
        let state = session.state == .working ? workingLine(at: .now) : session.state.label
        return [agent.displayName, title, state, recap]
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

/// The state's shape: shape as well as color, so state never depends on color alone.
struct StateMark: View {
    let state: SessionState
    let style: SidebarStyle

    var body: some View {
        switch state {
        case .needsYou:
            Circle().fill(style.attention).frame(width: 8, height: 8)
        case .done:
            // Filled, so done reads at a glance next to the other marks.
            Circle()
                .fill(style.done)
                .frame(width: 14, height: 14)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 7.5, weight: .heavy))
                        .foregroundStyle(style.background),
                )
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(style.failure)
        case .working:
            Circle().stroke(style.working, lineWidth: 1.5).frame(width: 8, height: 8)
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
    /// A letter for where a mark can't be drawn.
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
