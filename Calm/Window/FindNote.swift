import AppKit
import Observation
import SwiftUI

/// The note under find's field when a full-screen program's screen has none of the words
/// (FEATURES.md → F16, UIUX.md → Find): such a screen keeps no scrollback, but Calm kept what the
/// session showed, and the note's button searches all of it (the session page). With nothing kept,
/// an agent's conversation is in ⌘K, and the button takes the words there. It hangs under the
/// field's right end, over the terminal, on the ⌘-link tag's surface, and shows only while
/// `FindModel.showsNote`.
@MainActor
final class FindNote {
    private weak var container: NSView?
    private let model: FindModel
    private var host: NoteHost?
    /// The strip's frame in the container, the colors, and what the button does.
    var strip: () -> NSRect? = { nil }
    var style: () -> SidebarStyle = { SidebarStyle.derived(from: .black) }
    var background: () -> NSColor? = { nil }
    var onSearchAll: () -> Void = {}
    var onSession: () -> Void = {}

    init(container: NSView, model: FindModel) {
        self.container = container
        self.model = model
    }

    /// Follows the model from now on.
    func start() {
        withObservationTracking {
            _ = model.showsNote
            _ = model.noteText
            _ = model.noteButton
            _ = model.fieldFrame
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.update()
                    self?.start()
                }
            }
        }
    }

    private func update() {
        guard model.showsNote, let container, let strip = strip(), let field = model.fieldFrame else {
            if let host {
                self.host = nil
                Motion.fadeOutAndRemove(host, duration: 0.12)
            }
            return
        }
        let style = style()
        let button = model.noteButton
        let view = FindNoteView(
            text: model.noteText, button: button?.title, style: style,
            surface: Self.surface(on: background(), style: style),
            onButton: { [weak self] in
                switch button {
                case .session: self?.onSession()
                case .searchAll: self?.onSearchAll()
                case nil: break
                }
            },
        )
        let host = host ?? {
            let created = NoteHost(rootView: view)
            container.addSubview(created, positioned: .above, relativeTo: nil)
            Motion.fadeIn(created, duration: 0.16)
            self.host = created
            return created
        }()
        host.rootView = view
        // Under the field's right end, 4 pt below the strip; the host has room for the shadow.
        let room = LinkTag.shadowRoom
        let size = host.fittingSize
        let right = strip.minX + field.maxX + room
        let top = strip.minY - 4 + room
        host.frame = NSRect(x: right - size.width, y: top - size.height, width: size.width, height: size.height)
    }

    /// A step off the terminal's background, as the ⌘-link tag and ⌘K's panel are.
    private static func surface(on background: NSColor?, style: SidebarStyle) -> Color {
        guard let background = background?.usingColorSpace(.sRGB) else { return style.background }
        return Color(nsColor: background.blended(withFraction: style.isDark ? 0.07 : 0.55, of: .white) ?? background)
    }

    #if DEBUG
        var descriptionForTesting: String {
            guard let host else { return "no note" }
            return "note \"\(model.noteText)\", button \"\(model.noteButton?.title ?? "none")\", frame \(host.frame)"
        }
    #endif
}

/// Takes clicks only on the note itself, not on the room around it for the shadow.
private final class NoteHost: NSHostingView<FindNoteView> {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.insetBy(dx: LinkTag.shadowRoom, dy: LinkTag.shadowRoom).contains(local) ? super.hitTest(point) : nil
    }
}

struct FindNoteView: View {
    let text: String
    let button: String?
    let style: SidebarStyle
    let surface: Color
    let onButton: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6.scaled) {
            Text(text)
                .calmFont(size: 12)
                .foregroundStyle(style.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let button {
                Button(action: onButton) {
                    Text(button)
                        .calmFont(size: 12)
                        .foregroundStyle(style.primary)
                        .padding(.horizontal, 8.scaled)
                        .padding(.vertical, 3.scaled)
                        .background(RoundedRectangle(cornerRadius: 6.scaled, style: .continuous).fill(style.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 11.scaled)
        .padding(.vertical, 8.scaled)
        .frame(maxWidth: 330.scaled, alignment: .leading)
        .fixedSize()
        .background(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).fill(surface))
        .overlay(RoundedRectangle(cornerRadius: 9.scaled, style: .continuous).strokeBorder(style.tertiary.opacity(0.22)))
        .shadow(color: .black.opacity(style.isDark ? 0.35 : 0.12), radius: 10, y: 4)
        .padding(LinkTag.shadowRoom)
        .environment(\.colorScheme, style.isDark ? .dark : .light)
        .accessibilityElement(children: .contain)
    }
}
