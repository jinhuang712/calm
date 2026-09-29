import CalmModel
import SwiftUI

/// The main area with no session chosen (UIUX.md → No session chosen): the sessions that wait for a
/// look, each with all it last said, or with none waiting the welcome page's search and lists.
struct NoSessionView: View {
    struct Actions {
        /// Goes to a session, as a click on its card in the sidebar does.
        let open: (Session.ID) -> Void
        let welcome: WelcomeView.Actions
    }

    let manager: SessionManager
    @Bindable var model: NoSessionModel
    let style: SidebarStyle
    let background: Color
    let actions: Actions

    @FocusState private var cardsFocused: Bool

    /// How wide the cards get: a comfortable line for what an agent said.
    private static let width: CGFloat = 600

    var body: some View {
        ZStack {
            switch model.content {
            case let .waiting(waiting):
                waitingPage(waiting)
                    .transition(.opacity)
            case .lists:
                WelcomeView(model: model.welcome, style: style, background: background, actions: actions.welcome, placement: .mainArea)
                    .transition(.opacity)
            }
        }
        .animation(Motion.isReduced ? nil : .easeInOut(duration: 0.2), value: model.content == .lists)
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        // Follows the sidebar as it changes: a turn ending, a question answered elsewhere.
        .onChange(of: manager.workspace.sessions) { _, sessions in model.update(sessions: sessions) }
        .onChange(of: manager.workspace.madeProjects) { _, projects in model.welcome.projects = projects }
        .onChange(of: model.welcome.query) { _, query in
            if !query.isEmpty {
                model.searched = true
            }
        }
    }

    // MARK: Waiting

    private func waitingPage(_ waiting: NoSessionContent.Waiting) -> some View {
        GeometryReader { proxy in
            let width = min(Self.width.scaled, proxy.size.width - 48.scaled)
            ViewThatFits(in: .vertical) {
                waitingColumn(waiting, width: width)
                    // As tall as the title bar, so the block sits centered in the window.
                    .padding(.bottom, 60.scaled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    waitingColumn(waiting, width: width)
                        .padding(.vertical, 32.scaled)
                        .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.never)
            }
        }
        .focusable()
        .focused($cardsFocused)
        .focusEffectDisabled()
        .onAppear { cardsFocused = true }
        .onChange(of: model.focusRequests) { cardsFocused = true }
        .onKeyPress(.downArrow) {
            model.step(1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.step(-1)
            return .handled
        }
        .onKeyPress(.return) {
            guard let id = model.selected else { return .ignored }
            actions.open(id)
            return .handled
        }
    }

    private func waitingColumn(_ waiting: NoSessionContent.Waiting, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12.scaled) {
            Text("WAITING ON YOU")
                .calmFont(size: 12, weight: .semibold)
                .tracking(0.7)
                .foregroundStyle(style.tertiary)
                .padding(.horizontal, 4.scaled)
                .accessibilityAddTraits(.isHeader)
            ForEach(waiting.sessionIDs, id: \.self) { id in
                if let session = manager.workspace.session(id) {
                    WaitingCard(session: session, isSelected: model.selected == id, style: style) {
                        actions.open(id)
                    }
                }
            }
            if let footnote = waiting.footnote {
                Text(footnote)
                    .calmFont(size: 13)
                    .foregroundStyle(style.tertiary)
                    .padding(.horizontal, 4.scaled)
                    .padding(.top, 8.scaled)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}

/// A session that waits for a look, drawn like its sidebar card a size up, with room for all the
/// agent last said (the sidebar keeps two lines of it). ↵ opens the one the keys are on.
private struct WaitingCard: View {
    let session: Session
    let isSelected: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    /// The detail lines start under the title, past the mark.
    private static let indent: CGFloat = 42

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10.scaled) {
                HStack(spacing: 12.scaled) {
                    mark
                    Text(session.title(agentTitle: session.agent?.tail?.title))
                        .calmFont(size: 17, weight: .medium)
                        .foregroundStyle(style.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8.scaled)
                    if let date = session.lastReport?.date ?? session.stateSince {
                        RelativeTimeText(date: date)
                            .calmFont(size: 12)
                            .foregroundStyle(style.tertiary)
                    }
                }
                stateLine
                    .padding(.leading, Self.indent.scaled)
                if let recap = session.recap {
                    Text(recap)
                        .calmFont(size: 14.5)
                        .lineSpacing(4)
                        .foregroundStyle(style.primary.opacity(0.8))
                        .lineLimit(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, Self.indent.scaled)
                }
                footer
                    .padding(.leading, Self.indent.scaled)
                    .padding(.top, 4.scaled)
            }
            .padding(.horizontal, 22.scaled)
            .padding(.top, 20.scaled)
            .padding(.bottom, 18.scaled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tint.opacity(hovering ? tintFill.hovered : tintFill.resting)))
            .overlay(shape.strokeBorder(tint.opacity(0.08), lineWidth: SidebarStyle.selectionRingWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help("Go to this session")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @MainActor
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14.scaled, style: .continuous)
    }

    /// The agent's mark, still (its motion means *working*, and nothing here works); a plain
    /// shell's chevron tile as its sidebar row has.
    @ViewBuilder
    private var mark: some View {
        if let agent = session.agent?.kind {
            AgentLogo(agent: agent, size: 30, style: style)
        } else {
            Image(systemName: "chevron.right")
                .calmFont(size: 11, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 30.scaled, height: 30.scaled)
                .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
        }
    }

    private var stateLine: some View {
        HStack(spacing: 7.scaled) {
            StateMark(state: session.state, style: style)
            Text(session.state.label)
                .calmFont(size: 13.5, weight: session.state == .done ? .medium : .regular)
                .foregroundStyle(stateColor)
            if let shells = SessionCard.shellsLine(session.shellsStillRunning) {
                Text("· \(shells)")
                    .calmFont(size: 13.5)
                    .foregroundStyle(style.tertiary)
            }
        }
        .lineLimit(1)
    }

    /// Where it is (a scratch session's folder stays hidden), and ↵ on the card the keys are on.
    private var footer: some View {
        HStack(spacing: 8.scaled) {
            if !session.isScratch {
                Text(WorkspacePath.abbreviated(session.workingDirectory))
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 8.scaled)
            HStack(spacing: 7.scaled) {
                KeyCaps(keys: ["↵"], style: style, large: true)
                Text("Open")
                    .calmFont(size: 12.5)
                    .foregroundStyle(style.tertiary)
            }
            .opacity(isSelected ? 1 : 0)
            .accessibilityHidden(true)
        }
    }

    /// The card wears its state's color, as in the sidebar: amber for a question, sage for a
    /// finished turn; a failed one stays neutral there too.
    private var tint: Color {
        switch session.state {
        case .needsYou: style.attention
        case .done: style.done
        case .idle, .working, .failed: style.primary
        }
    }

    private var tintFill: (resting: Double, hovered: Double) {
        switch session.state {
        case .needsYou: (0.14, 0.2)
        case .done: (0.1, 0.15)
        case .idle, .working, .failed: (0.04, 0.07)
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
}
