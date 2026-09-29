import AppKit
@testable import Calm
import Testing

@MainActor
struct FileViewerTests {
    /// A window's content view with a terminal area whose left edge moves, as it does when the
    /// files column or the sidebar slides.
    @MainActor
    private struct Window {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
        let area = NSView()
        let leading: NSLayoutConstraint

        init(leading offset: CGFloat) {
            area.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(area)
            leading = area.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: offset)
            NSLayoutConstraint.activate([
                leading,
                container.trailingAnchor.constraint(equalTo: area.trailingAnchor),
                container.bottomAnchor.constraint(equalTo: area.bottomAnchor),
                area.topAnchor.constraint(equalTo: container.topAnchor, constant: 28),
            ])
            container.layoutSubtreeIfNeeded()
        }
    }

    /// The smallest viewable file that needs no web view.
    private func makeImage() throws -> String {
        let image = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
        ))
        let data = try #require(image.representation(using: .png, properties: [:]))
        let path = NSTemporaryDirectory() + "calm-viewer-\(UUID().uuidString).png"
        try data.write(to: URL(filePath: path))
        return path
    }

    @Test func `the viewer stays on the terminal area while the columns beside it slide`() throws {
        let path = try makeImage()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let window = Window(leading: 550)
        let viewer = FileViewer(container: window.container)
        let style = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))
        #expect(viewer.show(path, line: nil, over: window.area, session: UUID(), sessionTitle: "Work", style: style) {})
        let root = try #require(window.container.subviews.last)
        window.container.layoutSubtreeIfNeeded()
        #expect(root.frame == NSRect(x: 550, y: 0, width: 450, height: 600))

        // The files column closes: the terminal area grows to the left, and so does the viewer.
        window.leading.constant = 300
        window.container.layoutSubtreeIfNeeded()
        #expect(root.frame == NSRect(x: 300, y: 0, width: 700, height: 600))
        // Its header and content follow.
        #expect(root.subviews.allSatisfy { $0.frame.width == 700 })

        // The sidebar goes too, and the column opens again.
        window.leading.constant = 0
        window.container.layoutSubtreeIfNeeded()
        #expect(root.frame == NSRect(x: 0, y: 0, width: 1000, height: 600))
        window.leading.constant = 272
        window.container.layoutSubtreeIfNeeded()
        #expect(root.frame == NSRect(x: 272, y: 0, width: 728, height: 600))
    }

    @Test func `the viewer remembers the session it was opened over until it closes`() throws {
        let path = try makeImage()
        defer { try? FileManager.default.removeItem(atPath: path) }
        let window = Window(leading: 300)
        let viewer = FileViewer(container: window.container)
        let style = SidebarStyle.derived(from: NSColor(white: 0.12, alpha: 1))
        let session = UUID()
        var closed = 0
        #expect(viewer.session == nil)
        #expect(viewer.show(path, line: nil, over: window.area, session: session, sessionTitle: "Work", style: style) { closed += 1 })
        #expect(viewer.isShowing)
        #expect(viewer.session == session)
        viewer.close()
        #expect(!viewer.isShowing)
        #expect(viewer.session == nil)
        #expect(closed == 1)
    }
}
