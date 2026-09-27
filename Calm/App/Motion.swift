import AppKit
import SwiftUI

/// Calm's motion switch (UIUX.md → Motion): soft animation by default, none when the system's
/// Reduce Motion is on or `motion = reduced` / `off` in config.toml.
@MainActor
enum Motion {
    static var isReduced: Bool {
        AccessibilitySettings.reduceMotion || SessionManager.shared.settings.motion != .full
    }

    /// A duration, or zero when motion is reduced.
    static func duration(_ seconds: TimeInterval) -> TimeInterval {
        isReduced ? 0 : seconds
    }

    /// Fades a layer-backed view in. Presentation-only: the view's alpha is 1 at once, so a
    /// fade that never runs can't leave the view invisible.
    static func fadeIn(_ view: NSView, duration: TimeInterval) {
        view.alphaValue = 1
        guard !isReduced, let layer = view.layer else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "calm.fade")
    }

    /// Fades a view out and removes it. Removal is timed, not tied to an animation
    /// completion, so an overlay can never linger invisibly and take clicks.
    static func fadeOutAndRemove(_ view: NSView, duration: TimeInterval) {
        guard !isReduced, let layer = view.layer else {
            view.removeFromSuperview()
            return
        }
        view.alphaValue = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        layer.add(fade, forKey: "calm.fade")
        Task {
            try? await Task.sleep(for: .seconds(duration))
            view.removeFromSuperview()
        }
    }

    /// Changes constraints and animates `container`'s subviews to their new frames. Presentation-only:
    /// frames take their final values at once and only the layers glide, so the terminal is resized
    /// once, not on every step (each resize reaches the program running in it), and a layout that
    /// never animates is still right. AppKit's `animator()` frame animation steps on a timer that
    /// stalls outside event handling. Views that shrink should clip content laid out at full width.
    static func animateLayout(of container: NSView, duration: TimeInterval = 0.2, _ change: () -> Void) {
        let before = container.subviews.map { ($0, $0.frame) }
        change()
        container.layoutSubtreeIfNeeded()
        guard !isReduced else { return }
        for (view, old) in before where view.frame != old {
            guard let layer = view.layer else { continue }
            let anchor = layer.anchorPoint
            let position = CABasicAnimation(keyPath: "position")
            position.fromValue = NSPoint(x: old.minX + anchor.x * old.width, y: old.minY + anchor.y * old.height)
            let size = CABasicAnimation(keyPath: "bounds.size")
            size.fromValue = old.size
            let group = CAAnimationGroup()
            group.animations = [position, size]
            group.duration = duration
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(group, forKey: "calm.layout")
        }
    }

    /// Applies a state change with animation, or directly when motion is reduced.
    static func animate(_ animation: Animation = .smooth(duration: 0.3), _ body: () -> Void) {
        if isReduced {
            body()
        } else {
            withAnimation(animation, body)
        }
    }
}
