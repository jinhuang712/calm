import AppKit
import CalmModel
import SwiftUI

/// The window options (UIUX.md → Themes, ROADMAP.md → M6.4): a solid or glass background, and
/// the terminal area edge to edge or floating as a rounded card.
@MainActor
final class WindowStyle {
    static let cardInset: CGFloat = 8
    static let cardRadius: CGFloat = 10
    /// How much of the sidebar's color stays on glass: the blur shows through, text stays legible.
    static let glassSurfaceOpacity = 0.55

    private let glass = NSVisualEffectView()
    private var insets: [NSLayoutConstraint] = []
    private(set) var layout = CalmSettings.WindowLayout.edge

    var cornerRadius: CGFloat {
        layout == .card ? Self.cardRadius : 0
    }

    /// Pins the terminal area between `leadingView` and the window's edges, leaving the title bar
    /// strip above it, and puts the glass under everything.
    func install(mainArea: NSView, after leadingView: NSView, in container: NSView) {
        glass.material = .underWindowBackground
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.isHidden = true
        glass.frame = container.bounds
        glass.autoresizingMask = [.width, .height]
        container.addSubview(glass, positioned: .below, relativeTo: nil)
        insets = [
            mainArea.leadingAnchor.constraint(equalTo: leadingView.trailingAnchor),
            container.trailingAnchor.constraint(equalTo: mainArea.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: mainArea.bottomAnchor),
        ]
        NSLayoutConstraint.activate(insets + [mainArea.topAnchor.constraint(
            equalTo: container.topAnchor,
            constant: CalmWindow.titleStripHeight,
        )])
    }

    /// Applies the options in `settings`: adjusts `style` for glass and returns the color the
    /// window itself should have.
    func apply(
        _ settings: CalmSettings, style: inout SidebarStyle, terminalBackground: NSColor, mainArea: NSView, container: NSView,
    ) -> NSColor {
        let isGlass = settings.windowBackground == .glass
        glass.isHidden = !isGlass
        container.window?.isOpaque = !isGlass
        style.surfaceOpacity = isGlass ? Self.glassSurfaceOpacity : 1

        if settings.windowLayout != layout {
            layout = settings.windowLayout
            let inset = layout == .card ? Self.cardInset : 0
            Motion.animateLayout(of: container) {
                insets.forEach { $0.constant = inset }
            }
        }
        mainArea.wantsLayer = true
        mainArea.layer?.cornerRadius = cornerRadius
        mainArea.layer?.cornerCurve = .continuous
        mainArea.layer?.masksToBounds = layout == .card
        mainArea.layer?.borderWidth = layout == .card ? 1 : 0
        mainArea.layer?.borderColor = NSColor(style.tertiary).withAlphaComponent(0.12).cgColor

        if isGlass {
            return .clear
        }
        // A card floats on the sidebar's color; edge to edge, the title strip matches the terminal.
        return layout == .card ? NSColor(style.background) : terminalBackground
    }
}
