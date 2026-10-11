/// How big the viewer shows a file (FEATURES.md → F10): ⌘+ and ⌘− step through fixed sizes, as a
/// browser does, and ⌘0 goes back to 1. A page of text is sized against its own text; a picture or
/// a PDF against the size that fits the viewer.
public enum ViewerZoom {
    public enum Kind: Sendable {
        /// Markdown, code, text, HTML and the session page.
        case page
        /// Pictures (an SVG too) and PDFs, where 1 fits the viewer and inspecting wants more room.
        case picture

        public var steps: [Double] {
            switch self {
            case .page: [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]
            case .picture: [0.5, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]
            }
        }
    }

    /// The next size up (`bigger`) or down from `zoom`. A size between two steps (a trackpad
    /// pinch leaves one) goes to the nearer step that way; the ends stay where they are.
    public static func step(_ zoom: Double, bigger: Bool, kind: Kind) -> Double {
        let steps = kind.steps
        // A hundredth apart counts as the same step, so 0.67 isn't stepped "up" to itself.
        let next = bigger ? steps.first { $0 > zoom + 0.01 } : steps.last { $0 < zoom - 0.01 }
        return next ?? (bigger ? steps[steps.count - 1] : steps[0])
    }

    /// "125%": how the file's row says a size (UIUX.md → Viewing files).
    public static func percent(_ zoom: Double) -> String {
        "\(Int((zoom * 100).rounded()))%"
    }

    /// Whether the row shows the size: while it isn't the file's own, and while the pointer is on
    /// it, so a step onto 100% with its + or − doesn't take it away from under the pointer.
    public static func showsSize(_ zoom: Double, hovered: Bool) -> Bool {
        hovered || abs(zoom - 1) > 0.001
    }
}

// MARK: Saved size

public extension Workspace {
    /// Records the size pages of text are now read at (1 is stored as nil). Returns whether it
    /// changed, so callers save only then.
    mutating func noteViewerZoom(_ zoom: Double) -> Bool {
        let value = abs(zoom - 1) < 0.001 ? nil : zoom
        guard value != viewerZoom else { return false }
        viewerZoom = value
        return true
    }
}
