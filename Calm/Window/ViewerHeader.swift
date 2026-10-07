import CalmModel
import SwiftUI

/// Whether a file is open over the session: the title strip dims the session's name while it is,
/// and the name becomes the way back (UIUX.md → Viewing files).
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
}

/// The file's row under the title strip (UIUX.md → Viewing files): its name and folder, lined up
/// under the session's name; at the right, for a changed file its `+3 −3` and the switch between
/// the file and its diff, find's field while it's open (FEATURES.md → F16), then Open in Editor and
/// the esc key cap that goes back (it steps away while find is open, since esc closes find first).
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
    /// "Open in Editor", or for a picture or a PDF the app that opens it.
    let openTitle: String
    let style: SidebarStyle
    let model: ViewerModel
    let find: ViewerFindModel
    let onMode: (ViewerModel.Mode) -> Void
    let onOpen: () -> Void
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10.scaled) {
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
                    .frame(width: 300.scaled)
            }
            ViewerOpenButton(title: openTitle, style: style, action: onOpen)
            if !find.isOpen {
                ViewerBackKey(style: style, action: onBack)
            }
        }
        .lineLimit(1)
        .padding(.leading, Self.leading)
        .padding(.trailing, 12.scaled)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
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

/// A soft box, the search field's fill, brighter under the pointer.
private struct ViewerOpenButton: View {
    let title: String
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6.scaled) {
                Image(systemName: "arrow.up.forward.square")
                    .calmFont(size: 11.5)
                Text(title)
                    .calmFont(size: 12.5)
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
}

/// The esc key cap: what esc does, and a click does the same.
private struct ViewerBackKey: View {
    let style: SidebarStyle
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text("esc")
                .calmFont(size: 11)
                .foregroundStyle(hovered ? style.primary : style.secondary)
                .padding(.horizontal, 7.scaled)
                .frame(height: 22.scaled)
                .background(
                    RoundedRectangle(cornerRadius: 6.scaled, style: .continuous)
                        .strokeBorder(style.primary.opacity(hovered ? 0.35 : 0.22), lineWidth: 1),
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .onHover { hovered = $0 }
        .help("Back to the session")
        .accessibilityLabel("Back to the session")
    }
}
