import CalmModel
import SwiftUI

/// Colors for the sidebar, derived from the focused terminal's background so the chrome
/// always matches the theme (UIUX.md → Color).
struct SidebarStyle: Equatable {
    var background: Color
    var selection: Color
    var primary: Color
    var secondary: Color
    var tertiary: Color
    var isDark: Bool

    static func derived(from terminalBackground: NSColor) -> SidebarStyle {
        let base = terminalBackground.usingColorSpace(.sRGB) ?? terminalBackground
        let isDark = base.brightnessComponent < 0.5
        let shade = isDark ? NSColor.black : NSColor(white: 0.0, alpha: 1)
        let background = base.blended(withFraction: isDark ? 0.18 : 0.04, of: shade) ?? base
        let ink = isDark ? NSColor.white : NSColor.black
        return SidebarStyle(
            background: Color(nsColor: background),
            selection: Color(nsColor: ink.withAlphaComponent(isDark ? 0.08 : 0.07)),
            primary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.86 : 0.85)),
            secondary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.55 : 0.55)),
            tertiary: Color(nsColor: ink.withAlphaComponent(isDark ? 0.38 : 0.4)),
            isDark: isDark,
        )
    }
}

/// Projects and their sessions: the periphery, where status lives.
struct SidebarView: View {
    let manager: SessionManager
    let style: SidebarStyle
    let onSelect: (Session.ID) -> Void
    let onClose: (Session.ID) -> Void
    let onNewSession: () -> Void
    let onNewProject: () -> Void

    private var selectedSessionID: Session.ID? {
        manager.workspace.selectedLayout?.focusedSessionID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the window's traffic lights.
            Color.clear.frame(height: 38)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(manager.workspace.projects) { project in
                        projectSection(project)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.never)

            footer
        }
        .frame(maxHeight: .infinity)
        .background(style.background)
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(\.hasDirectoryPath)
            folders.forEach { manager.addProject(path: $0.path) }
            return !folders.isEmpty
        }
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    // MARK: Sections

    private func projectSection(_ project: Project) -> some View {
        let sessions = manager.workspace.sessions(in: project.id)
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                manager.toggleCollapsed(project.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(project.isCollapsed ? -90 : 0))
                        .frame(width: 10)
                    Text(project.name.uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .tracking(0.6)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if project.isCollapsed {
                        Text(summary(sessions))
                            .font(.system(size: 11))
                            .foregroundStyle(style.tertiary)
                    }
                }
                .foregroundStyle(style.secondary)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(project.path)

            if !project.isCollapsed {
                ForEach(sessions) { session in
                    SessionRow(
                        session: session,
                        isSelected: session.id == selectedSessionID,
                        style: style,
                    )
                    .onTapGesture { onSelect(session.id) }
                    .contextMenu {
                        Button(session.isPinned ? "Unpin from Project" : "Pin to Project") {
                            manager.togglePinned(session.id)
                        }
                        Divider()
                        Button("Close Session") { onClose(session.id) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func summary(_ sessions: [Session]) -> String {
        sessions.count == 1 ? "1 session" : "\(sessions.count) sessions"
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Button(action: onNewProject) {
                Label("New Project", systemImage: "plus")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.secondary)
            Spacer()
            Button(action: onNewSession) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(style.secondary)
            .help("New Session (⌘T)")
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
    }
}

/// A compact session row. Rich cards (state, progress, recap, worktree) arrive in Milestone 3.
struct SessionRow: View {
    let session: Session
    let isSelected: Bool
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(style.tertiary)
                .frame(width: 18, height: 18)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(style.tertiary.opacity(0.5)))
            Text(session.displayTitle)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? style.primary : style.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(style.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? style.selection : .clear),
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(session.displayTitle)\(session.isPinned ? ", pinned" : "")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
