import AppKit
import CalmModel

/// A picture in the viewer (FEATURES.md → F10): fitted to the viewer and never grown past its own
/// size, as before; ⌘+ and ⌘− (or a pinch) magnify it, with room to scroll around it. Smaller than
/// the view, it sits in the middle.
final class ViewerPictureView: NSScrollView {
    private let imageView: NSImageView
    private let imageSize: NSSize

    init(image: NSImage) {
        imageSize = image.size
        imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        super.init(frame: .zero)
        contentView = CenteringClipView()
        contentView.drawsBackground = false
        drawsBackground = false
        documentView = imageView
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        let steps = ViewerZoom.Kind.picture.steps
        minMagnification = steps[0]
        maxMagnification = steps[steps.count - 1]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func tile() {
        super.tile()
        fit()
    }

    /// The picture's size at magnification 1: its own, shrunk to fit the view. `contentSize`
    /// doesn't change with magnification, so the fit follows only the window.
    private func fit() {
        let room = contentSize
        guard imageSize.width > 0, imageSize.height > 0, room.width > 0, room.height > 0 else { return }
        let scale = min(1, room.width / imageSize.width, room.height / imageSize.height)
        let size = NSSize(width: (imageSize.width * scale).rounded(), height: (imageSize.height * scale).rounded())
        if imageView.frame.size != size {
            imageView.setFrameSize(size)
        }
    }

    /// ⌘+ (`bigger`), ⌘− or ⌘0 (nil): magnified about the middle of what's in view.
    func zoom(bigger: Bool?) {
        let next = bigger.map { ViewerZoom.step(magnification, bigger: $0, kind: .picture) } ?? 1
        let bounds = contentView.bounds
        setMagnification(next, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
    }
}

/// Keeps a document smaller than the view in its middle; NSClipView pins it to a corner.
private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var bounds = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return bounds }
        if bounds.width > document.width {
            bounds.origin.x = document.minX - (bounds.width - document.width) / 2
        }
        if bounds.height > document.height {
            bounds.origin.y = document.minY - (bounds.height - document.height) / 2
        }
        return bounds
    }
}
