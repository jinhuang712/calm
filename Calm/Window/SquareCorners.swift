import AppKit
import ObjectiveC
import OSLog

/// Square corners for a Calm window that fills the screen (UIUX.md → Window). macOS rounds every
/// titled window, so a filled one let the desktop show through a sliver at each corner, against
/// the menu bar and the screen's edges (seen 2026-10-07). AppKit has no public API for a window's
/// corners, so this overrides four private methods of `NSThemeFrame`, the view that draws a
/// window's frame and gives the window server its shape: for a `CalmWindow` that asks for square
/// corners they answer none, and for every other window they ask AppKit's own.
///
/// Checked on macOS 26.5 by reading `_cornerMask`, the shape the window server is handed: square
/// for the window that asks, round for another window at the same time, round again after
/// (CalmWindowTests); no test sees the screen itself. A macOS without these methods, or with
/// other types for them, gets nothing overridden, and its corners stay round.
@MainActor
enum SquareCorners {
    private static let log = Logger(subsystem: "com.jinhuang.calm", category: "window")
    private static var isInstalled = false

    private typealias RadiusMethod = @convention(c) (AnyObject, Selector) -> Double
    private typealias SizeMethod = @convention(c) (AnyObject, Selector) -> CGSize

    private static let radiusMethods = ["_cornerRadius", "_getCachedWindowCornerRadius"]
    private static let sizeMethods = ["_topCornerSize", "_bottomCornerSize"]

    /// Overrides the methods once, for the whole app; all four or none.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        guard let frameClass = NSClassFromString("NSThemeFrame") else {
            log.info("no NSThemeFrame: window corners stay round")
            return
        }
        let expected = radiusMethods.map { ($0, "d16@0:8") } + sizeMethods.map { ($0, "{CGSize=dd}16@0:8") }
        var methods: [String: Method] = [:]
        for (name, types) in expected {
            guard let method = class_getInstanceMethod(frameClass, NSSelectorFromString(name)),
                  method_getTypeEncoding(method).map({ String(cString: $0) }) == types
            else {
                log.info("NSThemeFrame.\(name, privacy: .public) is missing or changed: window corners stay round")
                return
            }
            methods[name] = method
        }
        for name in radiusMethods {
            guard let method = methods[name] else { continue }
            let selector = NSSelectorFromString(name)
            let original = unsafeBitCast(method_getImplementation(method), to: RadiusMethod.self)
            let replacement: @convention(block) (AnyObject) -> Double = { frame in
                wantsSquareCorners(frame) ? 0 : original(frame, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
        for name in sizeMethods {
            guard let method = methods[name] else { continue }
            let selector = NSSelectorFromString(name)
            let original = unsafeBitCast(method_getImplementation(method), to: SizeMethod.self)
            let replacement: @convention(block) (AnyObject) -> CGSize = { frame in
                wantsSquareCorners(frame) ? .zero : original(frame, selector)
            }
            method_setImplementation(method, imp_implementationWithBlock(replacement))
        }
    }

    /// Whether the frame view belongs to a Calm window that asks for square corners. AppKit asks
    /// on the main thread; anywhere else, the answer is AppKit's own.
    private nonisolated static func wantsSquareCorners(_ frame: AnyObject) -> Bool {
        guard Thread.isMainThread else { return false }
        // AppKit's view, read on the main thread it belongs to; the closure just runs there.
        let view = UncheckedSendable(frame)
        return MainActor.assumeIsolated {
            ((view.value as? NSView)?.window as? CalmWindow)?.hasSquareCorners == true
        }
    }

    /// Has the window's frame build its shape again, after `hasSquareCorners` changed.
    static func refresh(_ window: NSWindow) {
        let changed = NSSelectorFromString("windowCornerMaskChanged")
        if let frame = window.contentView?.superview, frame.responds(to: changed) {
            frame.perform(changed)
        }
        window.invalidateShadow()
    }
}
