import AppKit
@testable import Calm
import GhosttyKit
import Testing

/// A pane's command starts with the grid the pane keeps (engine patch 0013). A program
/// reattached through zmx after a relaunch read a placeholder 41×13 first, then the real size,
/// and its screen came back with most of its footer blank.
@MainActor
struct PaneStartSizeTests {
    private static let size = NSSize(width: 780, height: 672)

    private func pane(size: NSSize?, fontSize: Float = 0) throws -> TerminalSurfaceView {
        var options = TerminalSurfaceOptions.session
        // Something that stays alive and reads nothing; `teardown` ends it.
        options.command = "/bin/sleep 30"
        options.size = size
        options.fontSize = fontSize
        let pane = TerminalSurfaceView(options: options)
        try #require(pane.surface != nil)
        return pane
    }

    /// The size libghostty gets later from the layout, in pixels as the pane computes them.
    private func resize(_ pane: TerminalSurfaceView, to size: NSSize) throws {
        let surface = try #require(pane.surface)
        let scale = Double(NSScreen.main?.backingScaleFactor ?? 2)
        ghostty_surface_set_size(surface, UInt32(size.width * scale), UInt32(size.height * scale))
    }

    private func configuredFontSize() throws -> Float {
        try #require(TerminalEngine.shared.config?.float("font-size"))
    }

    @Test func `a pane starts with the grid of the size it is given`() throws {
        let sized = try pane(size: Self.size)
        let later = try pane(size: nil)
        defer {
            sized.teardown()
            later.teardown()
        }
        let placeholder = later.gridSize
        try resize(later, to: Self.size)
        #expect(sized.gridSize == later.gridSize)
        #expect(sized.gridSize != placeholder)
    }

    @Test func `a pane starts at the text size it is given`() throws {
        let points = try configuredFontSize() * 2
        let big = try pane(size: Self.size, fontSize: points)
        let later = try pane(size: Self.size)
        let plain = try pane(size: Self.size)
        defer {
            big.teardown()
            later.teardown()
            plain.teardown()
        }
        later.setFontSize(points)
        #expect(big.gridSize == later.gridSize)
        #expect(big.gridSize != plain.gridSize)
    }

    /// The first color scheme changes the conditional theme, which rebuilds libghostty's config;
    /// the text size a pane started at stays, and resetting still goes back to the configured one.
    @Test func `the text size a pane starts at stays until reset`() throws {
        let big = try pane(size: Self.size, fontSize: configuredFontSize() * 2)
        let plain = try pane(size: Self.size)
        defer {
            big.teardown()
            plain.teardown()
        }
        let started = big.gridSize
        let other = TerminalEngine.shared.colorScheme == GHOSTTY_COLOR_SCHEME_DARK ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
        big.setColorScheme(other)
        #expect(big.gridSize == started)
        big.setFontSize(nil)
        #expect(big.gridSize == plain.gridSize)
    }
}
