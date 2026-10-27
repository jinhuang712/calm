import AppKit
import CalmModel
import SwiftUI

/// Whether a file is open over the session: the title strip dims the session's name while it is,
/// and the name becomes the way back (specs/UIUX.md → Viewing files).
@MainActor @Observable
final class ViewerPresence {
    var isShowing = false
}

/// What the viewer's header shows besides the file's name: its changes, and how they're shown.
@MainActor @Observable
final class ViewerModel {
    enum Mode: String, CaseIterable {
        case file, unified, split

        var title: String {
            switch self {
            case .file: "File"
            case .unified: "Unified"
            case .split: "Split"
            }
        }
    }

    var change = ViewerChange.unchanged
    var mode = Mode.file
    /// The size the viewer shows the file at, against its own (a picture's or a PDF's against
    /// fitting it); the row shows it while it isn't 1 (FileViewer+Zoom).
    var zoom = 1.0
    /// The pointer is on the size, which keeps it in the row at 1.
    var zoomHovered = false
    /// The size's − and + (true, false) and the size itself (nil, back to 1).
    @ObservationIgnored var onZoom: (Bool?) -> Void = { _ in }
    #if DEBUG
        /// Draws the size as under the pointer, for a self-test's snapshot: a headless window
        /// gets no hover.
        var zoomHoverForTesting = false
    #endif
}

/// The file's row under the title strip (specs/UIUX.md → Viewing files): its name and folder, lined up
/// under the session's name, with the back button at its left, under the session's mark (it steps
/// away while find is open, since esc closes find first); at the right,
/// for a changed file its `+3 −3` and the switch between the file and its diff, find's field while
/// it's open (specs/FEATURES.md → F16), the size while it isn't 100% (F10), then Open in Editor.
struct ViewerHeader: View {
    /// Where the name starts: under the title strip's name (its inset, the group's mark and the gap).
    @MainActor
    static var leading: CGFloat {
        SessionTitleView.leadingInset + SessionTitleView.markSide.scaled + 10.scaled
    }

    let name: String
    /// The file's folder, relative to the session's project when it's inside it; nil at its top.
    let folder: String?
    /// "PNG · 2000 × 302 · 84 KB", "PDF · 6 pages": what a picture or a document is.
    let detail: String?
    /// "Open in Editor", or for a picture or a PDF the app that opens it; nil for the session page.
    let openTitle: String?
    let style: SidebarStyle
    let model: ViewerModel
    let find: ViewerFindModel
    let onMode: (ViewerModel.Mode) -> Void
    let onOpen: () -> Void
    let onBack: () -> Void

    var body: some View {
        // Marks and boxes with no text of their own say where their baseline would be.
        let nameCapMiddle = NSFont.systemFont(ofSize: 14.scaled).capHeight / 2
        let chevronLift = 0.5.scaled
        let buttonText = NSFont.systemFont(ofSize: 12.5.scaled)
        let buttonBaselineBelowMiddle = (buttonText.ascender + buttonText.descender) / 2
        // One baseline for every piece of text in the row (the 14 pt name; the 12 pt folder,
        // counts and size; the 12.5 pt buttons). Centred one by one, they sat up to a pixel apart.
        HStack(alignment: .firstTextBaseline, spacing: 10.scaled) {
            // The button's slot is the mark's width and gap, so the name stays under the session's
            // name, and the button is as wide as the mark. Its space stays while find is open, so
            // the name doesn't move.
            ZStack {
                if !find.isOpen {
                    ViewerBackButton(style: style, action: onBack)
                }
            }
            .frame(width: SessionTitleView.markSide.scaled)
            // The chevron's middle on the name's cap middle. SF's chevron draws half a point under
            // its frame's middle (measured on a 2x snapshot), so the frame sits that much higher.
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + nameCapMiddle + chevronLift }
            Text(name)
                .calmFont(size: 14, weight: .medium)
                .foregroundStyle(style.primary)
                .truncationMode(.middle)
                .layoutPriority(2)
            if let folder {
                Text(folder)
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
                    .truncationMode(.head)
            }
            Spacer(minLength: 12.scaled)
            if find.showsPictureNote {
                Text("Nothing to find in a picture")
                    .calmFont(size: 12)
                    .foregroundStyle(style.secondary)
                    .fixedSize()
            }
            if let detail, !find.isOpen {
                Text(detail)
                    .calmFont(size: 12)
                    .foregroundStyle(style.tertiary)
                    .fixedSize()
            }
            switch model.change {
            case .unchanged:
                EmptyView()
            case .new:
                Text("New")
                    .calmFont(size: 12, weight: .medium)
                    .foregroundStyle(style.done)
                    .fixedSize()
                    .help("Not in the last commit")
            case .changed:
                if let lines = model.change.lines {
                    LineCountsLabel(lines: lines, size: 12, style: style)
                }
                ViewerModeSwitch(mode: model.mode, style: style, onMode: onMode)
            }
            if find.isOpen {
                FindFieldView(model: find, style: style) { _, _ in }
                    .frame(width: find.showsScope ? 380.scaled : 300.scaled)
                    // Its middle level with the buttons' middles.
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + buttonBaselineBelowMiddle }
            }
            if ViewerZoom.showsSize(model.zoom, hovered: sizeOpen) {
                ViewerSizeControl(model: model, open: sizeOpen, style: style)
                    .transition(.opacity)
            }
            if let openTitle {
                ViewerOpenButton(title: openTitle, style: style, action: onOpen)
            }
        }
        .lineLimit(1)
        .padding(.leading, SessionTitleView.leadingInset)
        .padding(.trailing, 12.scaled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
    }

    /// The pointer is on the size, so its − and + show.
    private var sizeOpen: Bool {
        #if DEBUG
            model.zoomHovered || model.zoomHoverForTesting
        #else
            model.zoomHovered
        #endif
    }
}

/// The size while it isn't the file's own (specs/UIUX.md → Viewing files): quiet text at rest, like the
/// title strip's readout; under the pointer − and + come in around it on the switch's soft track,
/// and a click on the size goes back to 100%. The size stays where it is, so only the track and
/// the two buttons come and go, and it stays while the pointer is on it, even at 100%.
private struct ViewerSizeControl: View {
    let model: ViewerModel
    let open: Bool
    let style: SidebarStyle
    @State private var sizeHovered = false

    var body: some View {
        HStack(spacing: 0) {
            ViewerStepButton(bigger: false, shown: open, style: style) { model.onZoom(false) }
            Button { model.onZoom(nil) } label: {
                Text(ViewerZoom.percent(model.zoom))
                    .monospacedDigit()
                    .calmFont(size: 12)
                    .foregroundStyle(sizeHovered ? style.primary : open ? style.secondary : style.tertiary)
                    .frame(minWidth: 44.scaled, minHeight: 22.scaled)
                    .background(
                        RoundedRectangle(cornerRadius: 5.scaled, style: .continuous).fill(style.primary.opacity(sizeHovered ? 0.14 : 0)),
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { sizeHovered = $0 }
            .help("Actual Size · ⌘0")
            .accessibilityLabel("Size \(ViewerZoom.percent(model.zoom)), back to actual size")
            ViewerStepButton(bigger: true, shown: open, style: style) { model.onZoom(true) }
        }
        .padding(2.scaled)
        .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(style.primary.opacity(open ? 0.07 : 0)))
        .fixedSize()
        .onHover { model.zoomHovered = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// − or +: drawn, not typed, since SF's own sit on the math axis, a pixel under the figures'
/// middle beside them; a 1 pt stroke, 8 pt long, in the middle of the button, where the size's
/// figures are centred too.
private struct ViewerStepButton: View {
    let bigger: Bool
    let shown: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Rectangle().frame(width: 8.scaled, height: 1.scaled)
                if bigger {
                    Rectangle().frame(width: 1.scaled, height: 8.scaled)
                }
            }
            .foregroundStyle(hovered ? style.primary : style.secondary)
            .frame(width: 22.scaled, height: 22.scaled)
            .background(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous).fill(style.primary.opacity(hovered ? 0.14 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(shown ? 1 : 0)
        .onHover { hovered = $0 }
        .help(bigger ? "Bigger · ⌘+" : "Smaller · ⌘−")
        .accessibilityLabel(bigger ? "Bigger" : "Smaller")
    }
}

/// File, Unified, Split: Calm's own segmented control, a soft track with the chosen one lifted.
private struct ViewerModeSwitch: View {
    let mode: ViewerModel.Mode
    let style: SidebarStyle
    let onMode: (ViewerModel.Mode) -> Void

    var body: some View {
        HStack(spacing: 2.scaled) {
            ForEach(ViewerModel.Mode.allCases, id: \.self) { option in
                ViewerModeOption(title: option.title, chosen: option == mode, style: style) { onMode(option) }
            }
        }
        .padding(2.scaled)
        .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(style.primary.opacity(0.07)))
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Show the file or its changes")
    }
}

private struct ViewerModeOption: View {
    let title: String
    let chosen: Bool
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .calmFont(size: 12.5)
                .foregroundStyle(chosen || hovered ? style.primary : style.secondary)
                .padding(.horizontal, 10.scaled)
                .frame(height: 22.scaled)
                .background(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous).fill(style.primary.opacity(chosen ? 0.14 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A soft box, the search field's fill, brighter under the pointer. At least as wide as "Open in
/// Preview", so what stands left of it (the size, the switch) stays put from file to file.
private struct ViewerOpenButton: View {
    let title: String
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                label("Open in Preview").hidden()
                label(title)
            }
            .foregroundStyle(hovered ? style.primary : style.secondary)
            .padding(.horizontal, 10.scaled)
            .frame(height: 26.scaled)
            .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(style.primary.opacity(hovered ? 0.13 : 0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
    }

    private func label(_ title: String) -> some View {
        HStack(spacing: 6.scaled) {
            Image(systemName: "arrow.up.forward.square")
                .calmFont(size: 11.5)
            Text(title)
                .calmFont(size: 12.5)
        }
    }
}

/// The way back, what esc does: a quiet chevron with no box, and a soft tile under the pointer.
private struct ViewerBackButton: View {
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .calmFont(size: 12, weight: .semibold)
                .foregroundStyle(hovered ? style.primary : style.secondary)
                .frame(width: SessionTitleView.markSide.scaled, height: SessionTitleView.markSide.scaled)
                .background(RoundedRectangle(cornerRadius: 7.scaled, style: .continuous).fill(style.primary.opacity(hovered ? 0.11 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .help("Back to the session · esc")
        .accessibilityLabel("Back to the session")
    }
}
