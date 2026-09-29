import AppKit
import GhosttyKit

/// How a new surface should start.
struct TerminalSurfaceOptions {
    /// A Calm session's pane. Every session lives in the one main window, so libghostty
    /// treats it like a split (for inherited settings).
    static var session: TerminalSurfaceOptions {
        TerminalSurfaceOptions(context: GHOSTTY_SURFACE_CONTEXT_SPLIT)
    }

    var workingDirectory: String?
    var command: String?
    var fontSize: Float = 0
    var context: ghostty_surface_context_e = GHOSTTY_SURFACE_CONTEXT_WINDOW
    var environment: [String: String] = [:]
    /// The pane's size in points, when the layout already knows it: the command starts with
    /// this grid (with `fontSize`) rather than a placeholder's, which a resize replaces 25 ms
    /// later (engine patch 0013). A program reattached through zmx redrew for both and lost
    /// its footer.
    var size: NSSize?

    /// Starts from the parent's settings (font size, working directory), as libghostty computes them.
    @MainActor
    static func inheriting(from parent: TerminalSurfaceView?, context: ghostty_surface_context_e) -> TerminalSurfaceOptions {
        var options = TerminalSurfaceOptions(context: context)
        guard let parent, let surface = parent.surface else { return options }
        let inherited = ghostty_surface_inherited_config(surface, context)
        options.fontSize = inherited.font_size
        if let directory = inherited.working_directory {
            // libghostty allocates this and offers no way to free it; copy and leave it (tiny, per split).
            options.workingDirectory = String(cString: directory)
        }
        return options
    }
}
