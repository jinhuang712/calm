import CalmAgents
import CalmModel
import SwiftUI

/// What the close question says (UIUX.md → Split panes): the running program's mark, one line
/// and a quieter one, and the two answers. No card: the words stand on the asked pane's clearing
/// (`ClearingView`), so nothing has a border.
struct ClosePromptView: View {
    let agent: AgentKind?
    let style: SidebarStyle
    let onClose: () -> Void
    let onKeep: () -> Void

    private var name: String {
        agent?.displayName ?? "A program"
    }

    var body: some View {
        VStack(spacing: 0) {
            mark
            Text("\(name) is running here")
                .calmFont(size: 15, weight: .medium)
                .foregroundStyle(style.primary)
                .padding(.top, 14.scaled)
            Text("Closing the session ends it.")
                .calmFont(size: 12.5)
                .foregroundStyle(style.secondary)
                .padding(.top, 3.scaled)
            HStack(spacing: 6.scaled) {
                PromptAnswer(title: "Keep", key: .escape, isDefault: false, style: style, action: onKeep)
                PromptAnswer(title: "Close", key: .return, isDefault: true, style: style, action: onClose)
            }
            .padding(.top, 20.scaled)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8.scaled)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name) is running in this pane. Close the session?")
    }

    /// An agent's own mark in its tile, as in the sidebar; a plain program gets the sidebar's
    /// shell tile.
    @ViewBuilder
    private var mark: some View {
        let side = 34.scaled
        if let agent {
            AgentLogo(agent: agent, size: 34, style: style)
        } else {
            Image(systemName: "chevron.right")
                .calmFont(size: 12, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side * 0.3, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
                .accessibilityHidden(true)
        }
    }
}

/// A word and the key that says it: plain, with a soft key beside it. Hovering lights the word.
private struct PromptAnswer: View {
    let title: String
    let key: PromptKey
    let isDefault: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9.scaled) {
                Text(title)
                    .calmFont(size: 13, weight: isDefault ? .medium : nil)
                    .foregroundStyle(isDefault || hovered ? style.primary : style.secondary)
                KeyCap(key: key, style: style, ink: keyInk)
            }
            .padding(.leading, 14.scaled)
            .padding(.trailing, 12.scaled)
            .padding(.vertical, 6.scaled)
            .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(hovered ? style.selection : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel(title)
        .accessibilityHint(key == .escape ? "Escape" : "Return")
    }

    /// The key is quiet until the word is: Close's a little less so, and both light with the pointer.
    private var keyInk: Color {
        if hovered {
            return isDefault ? style.primary : style.secondary
        }
        return isDefault ? style.secondary : style.tertiary
    }
}

enum PromptKey {
    case escape
    case `return`
}

/// A key drawn as it is on a Mac's menus: a soft rounded square with the mark of the key.
private struct KeyCap: View {
    let key: PromptKey
    let style: SidebarStyle
    let ink: Color

    var body: some View {
        KeyGlyph(key: key)
            .stroke(ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            .frame(width: 13.scaled, height: 13.scaled)
            .frame(width: 21.scaled, height: 18.scaled)
            .background(RoundedRectangle(cornerRadius: 5.5.scaled, style: .continuous).fill(style.selection))
            .accessibilityHidden(true)
    }
}

/// The two marks, on a 16 × 16 grid: Return's arrow, bent down and back to the left; Escape's
/// circle broken at the upper left, with an arrow leaving through the gap.
private struct KeyGlyph: Shape {
    let key: PromptKey

    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 16
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        switch key {
        case .return:
            path.move(to: point(12.25, 3.75))
            path.addLine(to: point(12.25, 7.25))
            path.addQuadCurve(to: point(10.25, 9.25), control: point(12.25, 9.25))
            path.addLine(to: point(4, 9.25))
            path.move(to: point(6.25, 6.75))
            path.addLine(to: point(3.75, 9.25))
            path.addLine(to: point(6.25, 11.75))
        case .escape:
            // The circle is sampled rather than drawn with an arc: angles run the other way in a
            // flipped space, and an arc there is easy to get backwards. From 251° round through
            // the right, the bottom and the left to 199°, which leaves the gap at the upper left.
            let center = (x: 8.7, y: 8.7), radius = 5.3
            let angles = Array(stride(from: 251.0, through: 559.0, by: 4.0))
            for (index, degrees) in angles.enumerated() {
                let radians = degrees * .pi / 180
                let next = point(center.x + radius * cos(radians), center.y + radius * sin(radians))
                if index == 0 {
                    path.move(to: next)
                } else {
                    path.addLine(to: next)
                }
            }
            path.move(to: point(8.7, 8.7))
            path.addLine(to: point(4.4, 4.4))
            path.move(to: point(7.5, 4.4))
            path.addLine(to: point(4.4, 4.4))
            path.addLine(to: point(4.4, 7.5))
        }
        return path
    }
}
