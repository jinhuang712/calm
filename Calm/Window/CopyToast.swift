import AppKit
import SwiftUI

/// A small, quiet note by the pointer after Copy Cell, gone in a moment: confirmation without a
/// sound or a banner.
@MainActor
enum CopyToast {
    static func show(_ text: String, at point: NSPoint, in container: NSView) {
        let host = NSHostingView(rootView: Text(text)
            .calmFont(size: 11, weight: .medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule()))
        host.frame.size = host.fittingSize
        host.frame.origin = NSPoint(x: point.x + 8, y: point.y + 8)
        container.addSubview(host, positioned: .above, relativeTo: nil)
        Motion.fadeIn(host, duration: 0.12)
        Task {
            try? await Task.sleep(for: .milliseconds(900))
            Motion.fadeOutAndRemove(host, duration: 0.3)
        }
    }
}
