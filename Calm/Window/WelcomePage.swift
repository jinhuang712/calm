import AppKit
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

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text(firstUse ? "Welcome to Calm" : "No sessions open")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(style.primary)
                Text(firstUse ? "A terminal that keeps you calm while your agents work." : "Start one when you're ready.")
                    .font(.system(size: 13))
                    .foregroundStyle(style.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                row("New Session", detail: "A shell in your home folder", shortcut: "⌘T", action: actions.newSession)
                row(
                    "New Scratch Session",
                    detail: "Somewhere to try things, gone when you close it",
                    shortcut: "⌘⇧N",
                    action: actions.newScratchSession,
                )
                row("New Project…", detail: "A folder whose sessions stay together", shortcut: nil, action: actions.newProject)
            }
            if firstUse {
                Button(action: actions.setUpAgents) {
                    Text("Calm notices Claude Code, Codex, OpenCode, pi and omp on its own. Set up agents…")
                        .font(.system(size: 12))
                        .foregroundStyle(style.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 420, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Under the title bar too, so only the traffic lights show above it.
        .background(background.ignoresSafeArea())
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    private func row(_ title: String, detail: String, shortcut: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(style.primary)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(style.secondary)
                }
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 12))
                        .foregroundStyle(style.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(style.selection))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
