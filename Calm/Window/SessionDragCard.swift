import AppKit
import CalmAgents
import CalmModel
import SwiftUI

/// The card in your hand while a session is dragged by a pane's icon (UIUX.md → Split panes): the
/// session's mark, its name and where it is, on the sidebar's own surface. (A card dragged from the
/// sidebar shows itself.)
struct SessionDragCard: View {
    let session: Session
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 10) {
            mark
            VStack(alignment: .leading, spacing: 1) {
                Text(session.displayTitle)
                    .calmFont(size: 14.5, weight: .medium)
                    .foregroundStyle(style.primary)
                    .lineLimit(1)
                if !session.isScratch {
                    Text(session.workingDirectory.abbreviatingHome)
                        .calmFont(size: 12)
                        .foregroundStyle(style.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: 250, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.background))
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(style.selectionLift))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(style.tertiary.opacity(0.35)))
        // Room for the edge to show, since the image is cut at the card's bounds.
        .padding(2)
    }

    @ViewBuilder
    private var mark: some View {
        if let agent = session.agent?.kind {
            AgentLogo(agent: agent, state: .idle, size: 26, style: style)
        } else {
            Image(systemName: "chevron.right")
                .calmFont(size: 10, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(style.tertiary.opacity(0.4)))
        }
    }

    /// The card as a picture, at the window's scale.
    @MainActor
    static func image(of session: Session, style: SidebarStyle, scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: SessionDragCard(session: session, style: style).environment(
            \.colorScheme,
            style.isDark ? .dark : .light,
        ))
        renderer.scale = scale
        return renderer.nsImage
    }
}

private extension String {
    /// The folder with the home folder as `~`, as the title strip shows it.
    var abbreviatingHome: String {
        (self as NSString).abbreviatingWithTildeInPath
    }
}

/// The session being dragged, for the time a drop can't read it back from the pasteboard (the data
/// a SwiftUI drag promises is written when it is first asked for). Only ever used beside a
/// pasteboard that carries the session type, so a stale value can't start a drop by itself.
@MainActor
enum ActiveSessionDrag {
    static var current: SessionDrag?

    /// What a sidebar card carries when it is dragged.
    static func provider(for id: Session.ID) -> NSItemProvider {
        let drag = SessionDrag(origin: .card, sessionID: id)
        current = drag
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: SessionDrag.typeIdentifier, visibility: .ownProcess) { completion in
            completion(Data(drag.text.utf8), nil)
            return nil
        }
        return provider
    }
}
