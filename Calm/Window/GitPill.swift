import SwiftUI

/// A quiet pill with the git mark and a name: the files column's branch, the title strip's
/// worktree. One view, so the two read as the same kind of thing.
struct GitPill: View {
    let text: String
    /// What the name is, for VoiceOver ("branch", "worktree").
    let kind: String
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 4.scaled) {
            Image(systemName: "arrow.triangle.branch")
                .calmFont(size: 10, weight: .medium)
            Text(text)
                .calmFont(size: 12)
                .lineLimit(1)
        }
        .foregroundStyle(style.secondary)
        .padding(.horizontal, 7.scaled)
        .frame(height: 20.scaled)
        .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(style.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).strokeBorder(style.primary.opacity(0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind) \(text)")
    }
}
