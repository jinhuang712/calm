import AppKit

/// A PNG of a window as AppKit draws it, title bar included. It asks the view hierarchy to draw
/// into a bitmap, so it needs no Screen Recording permission and works for a window that is
/// hidden or covered (a headless run's is fully transparent).
enum WindowSnapshot {
    @MainActor
    static func png(of window: NSWindow) -> Data? {
        guard let frameView = window.contentView?.superview else { return nil }
        let bounds = frameView.bounds
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
