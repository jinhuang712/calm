import CalmModel
import SwiftUI

/// An agent session in the sidebar (UIUX.md → Session cards): who, what state, what it last
/// said, and where. Each state has its look: idle recedes, working is a soft blue with the
/// agent's mark in motion, *needs you* is amber, done is sage until you look. An idle card
/// (read, or never started) is also shorter, so the sessions that need a look stand out.
/// Settings → Appearance → Session cards makes every card smaller (`SessionCardLayout`).
struct SessionCard: View {
    let session: Session
    let agent: AgentKind
    let isSelected: Bool
    let style: SidebarStyle
    /// How much the card shows: every line, the state and recap on one line, or the title.
    var size = CalmSettings.SessionCardSize.full
    /// The pointer rests on the card: a long title glides to its end.
    var isHovered = false
    /// The saved row is still being checked against the running agent (only when that takes
    /// longer than the window can wait): the card keeps its saved size but says nothing about
    /// the state, so nothing shown is wrong. UIUX.md → Restoring.
    var isConfirming = false
    /// On screen beside the session you're in, in a split: lifted like the selected card, with no
    /// ring (UIUX.md → Split panes).
    var inView = false

    var body: some View {
        VStack(alignment: .leading, spacing: (size == .full ? 6 : 4).scaled) {
            HStack(spacing: 10.scaled) {
                AgentLogo(agent: agent, state: isConfirming ? .idle : session.state, style: style)
                ScrollingTitle(text: title, isHovered: isHovered)
                    .calmFont(size: 14.5, weight: .medium)
                    .foregroundStyle(isAsleep || isConfirming ? style.secondary : style.primary)
                Spacer(minLength: 4)
                if showsStateMarkByTime {
                    StateMark(state: session.state, style: style, compact: true)
                }
                if let date = session.lastReport?.date ?? session.agent?.startedAt {
                    RelativeTimeText(date: date)
                        .calmFont(size: 12, weight: timeColor == nil ? nil : .medium)
                        .foregroundStyle(timeColor ?? style.tertiary)
                }
            }
            detail
            // The title strip names the worktree of the session you're in; the smaller cards
            // leave it to the tooltip.
            if size == .full, let worktree = session.worktreeName {
                Label(worktree, systemImage: "arrow.triangle.branch")
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .padding(.leading, Self.indent)
            }
        }
        .padding(.horizontal, 12.scaled)
        .padding(.vertical, verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Self.shape.fill(background))
        // Under the card's own fill, so the selected card comes out lighter than the rest.
        .background(Self.shape.fill(isSelected || inView ? style.selectionLift : .clear))
        .overlay(Self.shape.strokeBorder(border, lineWidth: SidebarStyle.selectionRingWidth))
        .contentShape(Rectangle())
        .help(tooltip)
        .animation(.easeInOut(duration: 0.25), value: session.state)
        .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.45), value: isConfirming)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// What goes under the title, by the saved state, so a card being restored keeps its size.
    private var layout: SessionCardLayout {
        SessionCardLayout(size: size, state: session.state)
    }

    @ViewBuilder
    private var detail: some View {
        switch layout {
        case .titleOnly:
            EmptyView()
        case let .recap(lines):
            recapText(lines: lines)
        case .stacked:
            Group {
                if isConfirming {
                    LoadingBar(style: style)
                } else {
                    stateLine
                }
            }
            .padding(.leading, Self.indent)
            if !isConfirming, let progress = session.agent?.tail?.progress, progress.total > 0 {
                TodoProgressLine(progress: progress, style: style)
                    .padding(.leading, Self.indent)
            }
            recapText(lines: 2)
        case let .merged(lines):
            mergedLine(lines: lines)
                .padding(.leading, Self.indent)
        }
    }

    @ViewBuilder
    private func recapText(lines: Int) -> some View {
        if let message = session.recap {
            Text(message)
                .calmFont(size: 13)
                .lineSpacing(1.5)
                .foregroundStyle(isConfirming ? style.tertiary : style.secondary)
                .lineLimit(lines)
                .padding(.leading, Self.indent)
                .transition(.opacity)
        }
    }

    /// Compact's line: the state, then what the agent last said. While it works, "Working · step"
    /// or "Working · the recap", with the todo count at the end; a card that waits for a look
    /// gives its question or answer a second line.
    @ViewBuilder
    private func mergedLine(lines: Int) -> some View {
        if isConfirming {
            HStack(alignment: .top, spacing: 8.scaled) {
                LoadingBar(style: style, width: 60)
                if let recap = session.recap {
                    Text(recap)
                        .calmFont(size: 13)
                        .lineSpacing(1.5)
                        .foregroundStyle(style.tertiary)
                        .lineLimit(lines)
                }
            }
        } else if session.state == .working {
            HStack(spacing: 5.scaled) {
                ShimmerText(text: workingLine, color: style.working, highlight: style.workingHighlight)
                    .calmFont(size: 13, weight: .medium)
                    .lineLimit(1)
                    .layoutPriority(1)
                if session.agent?.tail?.step == nil, let recap = session.recap {
                    Text("·")
                        .calmFont(size: 13)
                        .foregroundStyle(style.tertiary)
                    Text(recap)
                        .calmFont(size: 13)
                        .foregroundStyle(style.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 6.scaled)
                if let progress = session.agent?.tail?.progress, progress.total > 0 {
                    Text("\(progress.done)/\(progress.total)")
                        .calmFont(size: 12)
                        .monospacedDigit()
                        .foregroundStyle(style.tertiary)
                        .fixedSize()
                }
            }
        } else {
            // Read outside the guide's closure, which isn't on the main actor.
            let lift = 4.5.scaled
            HStack(alignment: .firstTextBaseline, spacing: 6.scaled) {
                StateMark(state: session.state, style: style, compact: true)
                    // Centered on the first line's lowercase letters, not sat on its baseline.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + lift }
                mergedText
                    .calmFont(size: 13)
                    .lineSpacing(1.5)
                    .foregroundStyle(style.secondary)
                    .lineLimit(lines)
            }
        }
    }

    /// "Needs you · Should I also update…", one run of text so a second line wraps under the first.
    private var mergedText: Text {
        var parts = [Text(session.state.label).foregroundStyle(stateColor).fontWeight(session.state == .done ? .medium : .regular)]
        if let shells = Self.shellsLine(session.shellsStillRunning) {
            parts.append(Text("· \(shells)").foregroundStyle(style.tertiary))
        }
        if let recap = session.recap {
            parts.append(Text("·").foregroundStyle(style.tertiary))
            parts.append(Text(recap))
        }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0) \($1)") }
    }

    private var verticalPadding: CGFloat {
        switch layout {
        case .stacked: 12.scaled
        case .merged: 10.scaled
        case .recap: 8.scaled
        // As tall as a shell row.
        case .titleOnly: 7.scaled
        }
    }

    /// Minimal says the state in the time's color: there's no state line to say it.
    var timeColor: Color? {
        guard size == .minimal, !isConfirming else { return nil }
        switch session.state {
        case .working: return style.working
        case .needsYou: return style.attention
        case .done: return style.done
        case .failed: return style.failure
        case .idle: return nil
        }
    }

    /// Minimal leaves the state mark out, so there color is the state's only sign besides the
    /// tint; with Differentiate Without Color the mark comes back before the time.
    private var showsStateMarkByTime: Bool {
        timeColor != nil && AccessibilitySettings.differentiateWithoutColor
    }

    /// What a smaller card leaves out: the whole recap and the worktree.
    private var tooltip: String {
        guard size != .full else { return "" }
        return [session.recap, session.worktreeName.map { "Worktree: \($0)" }]
            .compactMap(\.self)
            .joined(separator: "\n")
    }

    @MainActor
    private static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12.scaled, style: .continuous)
    }

    /// The agent's own title (from its transcript) is steadier than the terminal title.
    private var title: String {
        session.title(agentTitle: session.agent?.tail?.title)
    }

    /// Idle, and not the session you're in: the card recedes. (Its size follows the state alone,
    /// selected or not, so picking a card never makes the list jump.)
    private var isAsleep: Bool {
        session.state == .idle && !isSelected
    }

    @ViewBuilder
    private var stateLine: some View {
        if session.state == .working {
            ShimmerText(text: workingLine, color: style.working, highlight: style.workingHighlight)
                .calmFont(size: 13, weight: .medium)
                .lineLimit(1)
        } else {
            HStack(spacing: 7.scaled) {
                StateMark(state: session.state, style: style)
                Text(session.state.label)
                    .calmFont(size: 13, weight: session.state == .done ? .medium : .regular)
                    .foregroundStyle(stateColor)
                    .lineLimit(1)
                if let shells = Self.shellsLine(session.shellsStillRunning) {
                    // Not part of the state's own color: the turn is done, this is a footnote.
                    Text("· \(shells)")
                        .calmFont(size: 13)
                        .foregroundStyle(style.tertiary)
                        .lineLimit(1)
                }
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

    /// "Working · Fixing the token mock", or "Working" when the agent names no step. No minutes:
    /// the time in the card's corner already counts them.
    var workingLine: String {
        session.agent?.tail?.step.map { "\(SessionState.working.label) · \($0)" } ?? SessionState.working.label
    }

    /// "2 shells running" for what a finished turn left behind; nothing when there are none.
    static func shellsLine(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 shell running"
        default: "\(count) shells running"
        }
    }

    /// The detail lines start under the title, past the agent mark.
    @MainActor
    static var indent: CGFloat {
        36.scaled
    }

    /// The state's color and how strongly the card takes it.
    private struct Tint {
        let color: Color
        let fill: Double
        let selectedFill: Double
    }

    /// How much of its color a state's card keeps at its edge. Faint on purpose: at 0.24 a row of
    /// tinted cards each drew an edge nearly as bright as the selection ring, so the selected one
    /// didn't stand out.
    private static let stateEdge = 0.08

    private var tint: Tint? {
        // While the state is being checked the card doesn't wear it.
        guard !isConfirming else { return nil }
        switch session.state {
        case .needsYou: return Tint(color: style.attention, fill: 0.14, selectedFill: 0.2)
        case .working: return Tint(color: style.working, fill: 0.1, selectedFill: 0.15)
        case .done: return Tint(color: style.done, fill: 0.1, selectedFill: 0.15)
        case .idle, .failed: return nil
        }
    }

    private var background: Color {
        guard let tint else { return isSelected ? style.selection : .clear }
        return tint.color.opacity(isSelected ? tint.selectedFill : tint.fill)
    }

    /// A faint edge for a card that wears a state; the selected card's is the ring, the same in
    /// every state, so which card you're in never depends on telling two tints apart.
    var border: Color {
        if isSelected {
            return style.selectionEdge
        }
        guard let tint else { return .clear }
        return tint.color.opacity(Self.stateEdge)
    }

    private var accessibilityText: String {
        let state = isConfirming ? "Restoring" : session.state == .working ? workingLine : session.state.label
        return [agent.displayName, title, state, Self.shellsLine(session.shellsStillRunning), session.recap]
            .compactMap(\.self)
            .joined(separator: ", ")
    }
}

/// Where a card's state goes while the state is being checked: a soft bar that breathes, as tall
/// as the state's own line so the card keeps its size. Still with Reduce Motion.
struct LoadingBar: View {
    let style: SidebarStyle
    /// About as wide as the state it stands in for: Full's state line, or Compact's label.
    var width: CGFloat = 92
    @State private var dimmed = true

    var body: some View {
        RoundedRectangle(cornerRadius: 4.5.scaled, style: .continuous)
            .fill(style.primary.opacity(0.14))
            .frame(width: width.scaled, height: 9.scaled)
            .opacity(dimmed && !Motion.isReduced ? 0.4 : 1)
            .padding(.vertical, 3.5.scaled)
            .onAppear {
                guard !Motion.isReduced else { return }
                withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) { dimmed = false }
            }
            .accessibilityHidden(true)
    }
}

/// A thin bar and "3 of 5": the agent's todo list.
struct TodoProgressLine: View {
    let progress: TodoProgress
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 8.scaled) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(style.selection)
                    Capsule()
                        .fill(style.secondary)
                        .frame(width: geometry.size.width * CGFloat(progress.done) / CGFloat(max(progress.total, 1)))
                }
            }
            .frame(height: 4.scaled)
            Text("\(progress.done) of \(progress.total)")
                .calmFont(size: 12)
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
    /// A folded group's line: done's check shrinks to sit level with the dots and rings beside it.
    var compact = false

    var body: some View {
        switch state {
        case .needsYou:
            Circle().fill(style.attention).frame(width: 8.scaled, height: 8.scaled)
        case .done:
            // Filled, so done reads at a glance next to the other marks.
            Circle()
                .fill(style.done)
                .frame(width: (compact ? 11 : 14).scaled, height: (compact ? 11 : 14).scaled)
                .overlay(
                    Image(systemName: "checkmark")
                        .calmFont(size: compact ? 6 : 7.5, weight: .heavy)
                        .foregroundStyle(style.background),
                )
        case .failed:
            Image(systemName: "xmark")
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(style.failure)
        case .working:
            Circle().stroke(style.working, lineWidth: 1.5).frame(width: 8.scaled, height: 8.scaled)
        case .idle:
            Circle().fill(style.tertiary.opacity(0.6)).frame(width: 6.scaled, height: 6.scaled)
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
        }
    }
}
