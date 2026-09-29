import SwiftUI

/// A git name in plain quiet type: the git mark and a name, in the tertiary color at 12 pt. The
/// files column's branch and the title strip's worktree. One view, so the two read as the same
/// kind of thing, and as the session card's worktree line: the chrome has no boxes for them.
struct GitLabel: View {
    let text: String
    /// What the name is, for VoiceOver ("branch", "worktree").
    let kind: String
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 4.scaled) {
            Image(systemName: "arrow.triangle.branch")
                .calmFont(size: 11, weight: .medium)
            Text(text)
                .calmFont(size: 12)
                .lineLimit(1)
        }
        .foregroundStyle(style.tertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind) \(text)")
    }
}
