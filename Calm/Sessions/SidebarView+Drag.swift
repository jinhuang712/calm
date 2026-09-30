import CalmModel
import SwiftUI
import UniformTypeIdentifiers

/// Sessions picked up from the sidebar, and put back on it (UIUX.md → Split panes).
extension SidebarView {
    /// What a dragged session is called on the pasteboard (Info.plist exports it).
    static let sessionType = UTType(exportedAs: SessionDrag.typeIdentifier, conformingTo: .data)

    /// A pane dragged here by its icon leaves its split. A card dragged from the sidebar and dropped
    /// back on it is nothing.
    func dropSession(_ providers: [NSItemProvider]) -> Bool {
        guard providers.contains(where: { $0.hasItemConformingToTypeIdentifier(SessionDrag.typeIdentifier) }),
              let drag = ActiveSessionDrag.current, drag.origin == .pane
        else { return false }
        actions.takeOut(drag.sessionID)
        return true
    }
}

extension View {
    /// A session's card or row can be picked up and put into a split. Not while it's being renamed:
    /// the name field takes the drag for selecting text.
    @ViewBuilder
    func dragSession(_ id: Session.ID, enabled: Bool) -> some View {
        if enabled {
            onDrag { ActiveSessionDrag.provider(for: id) }
        } else {
            self
        }
    }
}
