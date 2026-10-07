import AppKit
import SwiftUI

extension View {
    /// Calls `action` on a right-click (or a ⌃-click) on this view, with the point in the window:
    /// for a menu Calm draws itself, which `.contextMenu` can't show (it takes system menus only).
    func onRightClick(_ action: @escaping (CGPoint) -> Void) -> some View {
        overlay(RightClickCatcher(action: action))
    }
}

/// See-through to everything but a right-click: clicks, drags and hovering go to the view under it.
private struct RightClickCatcher: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context _: Context) -> CatcherView {
        let view = CatcherView()
        view.action = action
        return view
    }

    func updateNSView(_ view: CatcherView, context _: Context) {
        view.action = action
    }

    final class CatcherView: NSView {
        var action: (CGPoint) -> Void = { _ in }

        /// Only the event being delivered says which button it is, so the view is there for a
        /// right-click and nowhere for anything else.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent, Self.isRightClick(event) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            action(event.locationInWindow)
        }

        override func mouseDown(with event: NSEvent) {
            if Self.isRightClick(event) {
                action(event.locationInWindow)
            }
        }

        override func menu(for _: NSEvent) -> NSMenu? {
            nil
        }

        private static func isRightClick(_ event: NSEvent) -> Bool {
            event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control)
        }
    }
}
