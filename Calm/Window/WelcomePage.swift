import AppKit
import CalmModel
import SwiftUI

/// What the window shows with no session open (FEATURES.md → F2): a welcome on Calm's very
/// first launch, and the same quiet page whenever the last session is closed. It covers the whole
/// window, sidebar included: with nothing open there's nothing for the sidebar to show. Calm
/// never opens a session nobody asked for.
@MainActor
final class WelcomePage {
    private weak var container: NSView?
    private var host: NSHostingView<WelcomeView>?

    init(container: NSView) {
        self.container = container
    }

    var isShowing: Bool {
        host != nil
    }

    func show(firstUse: Bool, style: SidebarStyle, background: NSColor, actions: WelcomeView.Actions) {
        let view = WelcomeView(firstUse: firstUse, style: style, background: Color(nsColor: background), actions: actions)
        if let host {
            host.rootView = view
            return
        }
        guard let container else { return }
        let host = NSHostingView(rootView: view)
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host, positioned: .above, relativeTo: nil)
        self.host = host
        Motion.fadeIn(host, duration: 0.2)
    }

    func hide() {
        guard let host else { return }
        self.host = nil
        Motion.fadeOutAndRemove(host, duration: 0.14)
    }
}

struct WelcomeView: View {
    struct Actions {
        let newSession: () -> Void
        let newScratchSession: () -> Void
        let newProject: () -> Void
        let setUpAgents: () -> Void
    }

    let firstUse: Bool
    let style: SidebarStyle
    /// The terminal's background: the page stands where the sessions would.
    let background: Color
    let actions: Actions

    private struct Choice: Identifiable {
        let title: String
        let detail: String
        let symbol: String
        let keys: [String]
        let action: () -> Void
        var id: String {
            title
        }
    }

    private var choices: [Choice] {
        [
            Choice(
                title: "New Session", detail: "A shell in your home folder",
                symbol: "square.and.pencil", keys: ["⌘", "T"], action: actions.newSession,
            ),
            Choice(
                title: "New Scratch Session", detail: "Try things, gone when you close it",
                symbol: "square.dashed", keys: ["⌘", "⇧", "N"], action: actions.newScratchSession,
            ),
            Choice(
                title: "New Project…", detail: "A folder whose sessions stay together",
                symbol: "plus", keys: ["⌘", "O"], action: actions.newProject,
            ),
        ]
    }

    private var title: String {
        firstUse ? "Welcome to Calm" : "No sessions open"
    }

    private var subtitle: String {
        firstUse ? "A terminal that keeps you calm while your agents work." : "Start one when you're ready."
    }

    var body: some View {
        // The roomy page when the window has room for it; a short list in a small window.
        ViewThatFits {
            roomy
            compact
            ScrollView { compact.padding(.vertical, 24) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Under the title bar too, so only the traffic lights show above it.
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    private var roomy: some View {
        VStack(spacing: 40) {
            VStack(spacing: 18) {
                CalmMark(color: style.attention)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 34, weight: .medium))
                        .tracking(-0.3)
                        .foregroundStyle(style.primary)
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundStyle(style.secondary)
                }
            }
            HStack(spacing: 16) {
                ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                    WelcomeCard(
                        title: choice.title, detail: choice.detail, symbol: choice.symbol, keys: choice.keys,
                        isFirst: index == 0, style: style, action: choice.action,
                    )
                }
            }
            .frame(width: 700)
            WelcomeAgents(style: style, action: actions.setUpAgents)
        }
        .padding(.horizontal, 24)
        // As tall as the title bar, so the block sits centered in the window, not under it.
        .padding(.bottom, 44)
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(style.primary)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(style.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(choices) { row($0) }
            }
            Button(action: actions.setUpAgents) {
                Text("Works with \(AgentKind.allCases.map(\.displayName).formatted(.list(type: .and))). Set up agents…")
                    .font(.system(size: 12))
                    .foregroundStyle(style.tertiary)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 420, alignment: .leading)
        .padding(.horizontal, 24)
    }

    private func row(_ choice: Choice) -> some View {
        Button(action: choice.action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(style.primary)
                    Text(choice.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(style.secondary)
                }
                Spacer(minLength: 8)
                Text(choice.keys.joined())
                    .font(.system(size: 12))
                    .foregroundStyle(style.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.selection))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Calm's mark: nested rounded squares settling toward a still center.
private struct CalmMark: View {
    let color: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(color.opacity(0.22), lineWidth: 1.5)
                .frame(width: 52, height: 52)
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(color.opacity(0.45), lineWidth: 1.5)
                .frame(width: 34, height: 34)
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(color.opacity(0.85))
                .frame(width: 16, height: 16)
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }
}

/// One way to start, as a card; the first one carries the accent.
private struct WelcomeCard: View {
    let title: String
    let detail: String
    let symbol: String
    let keys: [String]
    let isFirst: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(isFirst ? style.attention : style.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(isFirst ? style.attention.opacity(0.16) : style.primary.opacity(0.08)))
                    .padding(.bottom, 14)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(style.primary)
                    .padding(.bottom, 4)
                // Room for two lines on every card, so the key caps line up across them.
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(style.secondary)
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 12)
                KeyCaps(keys: keys, style: style, large: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 180)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(style.primary.opacity(hovering ? 0.085 : 0.055)),
            )
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(style.primary.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

/// The agents Calm watches, each with its own mark, and the way to set them up.
private struct WelcomeAgents: View {
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text("Works with")
                    .foregroundStyle(style.tertiary)
                ForEach(AgentKind.allCases, id: \.self) { agent in
                    HStack(spacing: 6) {
                        AgentLogo(agent: agent, size: 20, style: style)
                        Text(agent.displayName)
                            .foregroundStyle(style.secondary)
                    }
                }
                Rectangle()
                    .fill(style.primary.opacity(0.1))
                    .frame(width: 1, height: 14)
                HStack(spacing: 4) {
                    Text("Set up agents")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(hovering ? style.primary : style.secondary)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(style.primary.opacity(hovering ? 0.05 : 0)))
            .overlay(Capsule().strokeBorder(style.primary.opacity(0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
