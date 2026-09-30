import Foundation

/// What a dragged session carries (UIUX.md → Split panes): whose it is, and where it was picked
/// up. The terminal panes already take dropped files and text (a path is pasted), so a session
/// travels under a type of its own, which only the sidebar and the split's panes accept.
public struct SessionDrag: Hashable, Sendable {
    /// Where the drag started: a card in the sidebar, or the split icon on a pane. Only a pane's
    /// drag can take the session out by dropping on the sidebar; a card dropped on the sidebar it
    /// came from is nothing.
    public enum Origin: String, Sendable {
        case card, pane
    }

    public static let typeIdentifier = "com.jinhuang.calm.session"

    public let origin: Origin
    public let sessionID: UUID

    public init(origin: Origin, sessionID: UUID) {
        self.origin = origin
        self.sessionID = sessionID
    }

    /// The text put on the pasteboard under `typeIdentifier`.
    public var text: String {
        "\(origin.rawValue):\(sessionID.uuidString)"
    }

    public init?(text: String) {
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let origin = Origin(rawValue: parts[0]), let id = UUID(uuidString: parts[1]) else { return nil }
        self.init(origin: origin, sessionID: id)
    }
}
