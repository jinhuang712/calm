import AppKit
import CalmModel
import QuickLookThumbnailing
import SwiftUI

/// The tag beside a ⌘-hovered link (FEATURES.md → F8, UIUX.md → Links): what the link is, where it
/// is, and what a click does, with a small picture of an image. It shows only while ⌘ is held
/// over the link, just under it (above it near the pane's bottom), and takes no clicks.
@MainActor
final class LinkTag {
    private weak var container: NSView?
    private var host: NSView?
    private var monitor: Any?
    private var shown: Shown?
    private var thumbnailRequest: QLThumbnailGenerator.Request?
    /// Which request a thumbnail answers, so one for a link already left is dropped.
    private var thumbnailGeneration = 0

    /// The tag's widest, before its path is shortened in the middle.
    static let maximumWidth: CGFloat = 440
    /// Room around the tag for its shadow.
    static let shadowRoom: CGFloat = 12
    /// A picture's largest, in points before the interface size: a linked image's thumbnail, and
    /// the large one of an agent's pasted image, which is the point of hovering its tag.
    static let pictureSize = CGSize(width: 220, height: 140)
    static let largePictureSize = CGSize(width: 440, height: 300)
    /// What the tag needs besides its picture (padding, name and folder lines), for fitting a large
    /// picture into the room the pane has.
    private static let textHeight: CGFloat = 64

    private struct Shown {
        var preview: LinkPreview
        var cells: NSRect
        var pane: NSRect
        var surface: Color
        var style: SidebarStyle
        var isLarge: Bool
        var thumbnail: NSImage?
    }

    init(container: NSView) {
        self.container = container
    }

    /// Shows the tag for a link whose cells are `cells`, inside `pane` (both in the container);
    /// `isLarge` shows its picture large.
    func show(
        _ preview: LinkPreview,
        image: String?,
        isLarge: Bool = false,
        under cells: NSRect,
        in pane: NSRect,
        background: NSColor?,
        style: SidebarStyle,
    ) {
        hide(animated: false)
        shown = Shown(
            preview: preview, cells: cells, pane: pane, surface: Self.surface(on: background, style: style), style: style,
            isLarge: isLarge,
        )
        place(fadeIn: true)
        // Typing, clicking or scrolling means the user has moved on (the click itself opens the link).
        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown,
            .leftMouseDown,
            .rightMouseDown,
            .scrollWheel,
        ]) { [weak self] event in
            self?.hide(animated: false)
            return event
        }
        if let image {
            let size = isLarge ? Self.largePictureSize : Self.pictureSize
            loadThumbnail(of: image, size: CGSize(width: size.width.scaled, height: size.height.scaled))
        }
    }

    func hide(animated: Bool) {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        if let thumbnailRequest {
            QLThumbnailGenerator.shared.cancel(thumbnailRequest)
        }
        thumbnailRequest = nil
        shown = nil
        guard let host else { return }
        self.host = nil
        if animated {
            Motion.fadeOutAndRemove(host, duration: 0.12)
        } else {
            host.removeFromSuperview()
        }
    }

    /// Just under the link, starting where it starts; above it when there's no room below. A large
    /// picture is cut to fit the bigger of the two rooms, so the tag never runs past the pane.
    private func place(fadeIn: Bool) {
        guard let container, let shown else { return }
        host?.removeFromSuperview()
        let below = shown.cells.minY - 4 - (shown.pane.minY + 6)
        let above = shown.pane.maxY - 6 - (shown.cells.maxY + 4)
        var picture = shown.isLarge ? Self.largePictureSize : Self.pictureSize
        picture = CGSize(width: picture.width.scaled, height: picture.height.scaled)
        if shown.isLarge {
            picture.height = max(48, min(picture.height, max(below, above) - Self.textHeight.scaled))
        }
        let view = PassthroughHostingView(rootView: LinkTagView(
            preview: shown.preview, thumbnail: shown.thumbnail, pictureSize: picture, surface: shown.surface, style: shown.style,
        ))
        let room = Self.shadowRoom
        let ideal = view.fittingSize
        let width = min(ideal.width, max(Self.maximumWidth, picture.width + 20) + 2 * room, shown.pane.width + 2 * room - 12)
        let height = ideal.height
        var x = shown.cells.minX - 10 - room
        x = max(shown.pane.minX + 6 - room, min(x, shown.pane.maxX - 6 + room - width))
        var y = shown.cells.minY - 4 + room - height
        if y + room < shown.pane.minY + 6 {
            y = shown.cells.maxY + 4 - room
        }
        // Nor past its top.
        y = min(y, shown.pane.maxY - 6 + room - height)
        view.frame = NSRect(x: x, y: y, width: width, height: height)
        container.addSubview(view, positioned: .above, relativeTo: nil)
        if fadeIn {
            Motion.fadeIn(view, duration: 0.12)
        }
        host = view
    }

    /// Quick Look's own thumbnail, which fades in when it's ready; the tag shows without one until then.
    private func loadThumbnail(of path: String, size: CGSize) {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(filePath: path),
            size: size,
            scale: container?.window?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail,
        )
        thumbnailRequest = request
        thumbnailGeneration += 1
        let generation = thumbnailGeneration
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            // NSImage isn't Sendable; this one is made here and only used on main from now on.
            let image = UncheckedSendable(representation?.nsImage)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.thumbnailGeneration == generation, self.shown != nil, let thumbnail = image.value else { return }
                    self.shown?.thumbnail = thumbnail
                    self.place(fadeIn: false)
                }
            }
        }
    }

    /// A surface a step off the terminal's background, so the tag floats over the text.
    private static func surface(on background: NSColor?, style: SidebarStyle) -> Color {
        guard let background = background?.usingColorSpace(.sRGB) else { return style.background }
        let lifted = background.blended(withFraction: style.isDark ? 0.07 : 0.55, of: .white) ?? background
        return Color(nsColor: lifted)
    }

    #if DEBUG
        var descriptionForTesting: String {
            guard let shown, let host else { return "no link tag" }
            let preview = shown.preview
            return "link tag \(preview.title) · \(preview.detail ?? "-") · \(preview.action), "
                + "thumbnail \(shown.thumbnail != nil), frame \(host.frame), link \(shown.cells)"
        }
    #endif
}

/// Takes no clicks: the pointer stays the terminal's.
private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_: NSPoint) -> NSView? {
        nil
    }
}

struct LinkTagView: View {
    let preview: LinkPreview
    let thumbnail: NSImage?
    /// The picture's largest, interface size applied.
    let pictureSize: CGSize
    let surface: Color
    let style: SidebarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 4.scaled) {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: pictureSize.width, maxHeight: pictureSize.height, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.25)))
                    .padding(.bottom, 3.scaled)
            }
            HStack(spacing: 7.scaled) {
                Image(systemName: symbol)
                    .font(.system(size: 11.scaled))
                    .foregroundStyle(style.secondary)
                    .frame(width: 14.scaled)
                Text(preview.title)
                    .calmFont(size: 12.5, weight: .medium)
                    .foregroundStyle(preview.kind == .missing ? style.secondary : style.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 16.scaled)
                Text(preview.action)
                    .calmFont(size: 11.5)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            if let detail = preview.detail {
                Text(detail)
                    .calmFont(size: 11, design: .monospaced)
                    .foregroundStyle(style.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.leading, 21.scaled)
            }
        }
        .padding(.horizontal, 10.scaled)
        .padding(.vertical, 7.scaled)
        .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.22)))
        .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 10, y: 4)
        .padding(LinkTag.shadowRoom)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch preview.kind {
        case .web: "globe"
        case .file: "doc"
        case .image: "photo"
        case .folder: "folder"
        case .missing: "questionmark.circle"
        }
    }
}
