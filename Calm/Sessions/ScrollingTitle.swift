import SwiftUI

/// A session's name on one line (UIUX.md → Session cards). A long name keeps its start and
/// ends in "…"; while the pointer rests on its row, it glides once to its end and holds there,
/// then slides back when the pointer leaves. With motion reduced it stays truncated.
///
/// Font and color come from the caller, so both copies of the text match.
struct ScrollingTitle: View {
    let text: String
    let isHovered: Bool

    /// The room the title has, and the width it wants.
    @State private var boxWidth: CGFloat = 0
    @State private var fullWidth: CGFloat = 0
    /// Whether the untruncated copy is showing, and how far it has moved (zero or negative).
    @State private var isScrolling = false
    @State private var offset: CGFloat = 0

    var body: some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.tail)
            .opacity(isScrolling ? 0 : 1)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .background(alignment: .leading) {
                // Measures the whole name; never drawn.
                Text(text)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { fullWidth = $0 }
            }
            .overlay(alignment: .leading) {
                if isScrolling {
                    Text(text)
                        .fixedSize()
                        .offset(x: offset)
                        .frame(width: boxWidth, alignment: .leading)
                        .clipped()
                }
            }
            .onChange(of: text) {
                isScrolling = false
                offset = 0
            }
            .task(id: trigger) { await follow(trigger) }
    }

    private var trigger: Trigger {
        Trigger(text: text, isActive: isHovered && !Motion.isReduced)
    }

    private struct Trigger: Equatable {
        let text: String
        let isActive: Bool
    }

    private func follow(_ trigger: Trigger) async {
        if trigger.isActive {
            // A pass across the list shouldn't set every name moving: wait for the pointer to rest.
            try? await Task.sleep(for: .seconds(Self.restDelay))
            let overflow = fullWidth - boxWidth
            guard !Task.isCancelled, overflow > 0.5 else { return }
            isScrolling = true
            withAnimation(.easeInOut(duration: Self.scrollDuration(overflow: overflow))) { offset = -overflow }
        } else {
            guard isScrolling else { return }
            withAnimation(.easeOut(duration: Self.returnDuration)) { offset = 0 }
            try? await Task.sleep(for: .seconds(Self.returnDuration))
            // Hovered again mid-return: the new task owns the text now.
            guard !Task.isCancelled else { return }
            isScrolling = false
        }
    }

    static let restDelay: TimeInterval = 0.5
    static let returnDuration: TimeInterval = 0.25

    /// Slow enough to read along (about 40 pt a second), never a jolt for a name barely too long.
    static func scrollDuration(overflow: CGFloat) -> TimeInterval {
        max(0.6, Double(overflow) / 40)
    }
}
