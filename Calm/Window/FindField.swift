import AppKit
import SwiftUI

/// The find field in the title strip (UIUX.md → Find): the words, the count, ↑ ↓ and a ⌘F cap
/// that closes it, in the sidebar search field's soft fill. ↵ goes to the older match and ⇧↵ to
/// the newer; esc closes it. ⌘F, ⌘G and ⌘E come through the Edit menu while it has the keyboard.
struct FindFieldView: View {
    @Bindable var model: FindModel
    let style: SidebarStyle
    /// The field's frame in the strip, so the strip takes clicks there (SessionTitleHost).
    let onFrame: (UUID, CGRect?) -> Void
    @FocusState private var focused: Bool
    @State private var id = UUID()
    /// Faded in when find opens (UIUX.md → Find, motion).
    @State private var shown = false

    var body: some View {
        HStack(spacing: 4.scaled) {
            Image(systemName: "magnifyingglass")
                .calmFont(size: 11.5, weight: .medium)
                .foregroundStyle(style.tertiary)
                .padding(.trailing, 3.scaled)
                .accessibilityHidden(true)
            TextField("Find in this session", text: $model.query)
                .textFieldStyle(.plain)
                .calmFont(size: 13.5)
                .foregroundStyle(style.primary)
                .focused($focused)
                .onKeyPress(.return, phases: .down) { press in
                    model.step(press.modifiers.contains(.shift) ? .newer : .older)
                    return .handled
                }
                .onExitCommand { model.close() }
                .accessibilityLabel("Find in this session")
            Text(model.countText)
                .calmFont(size: 12)
                .monospacedDigit()
                .foregroundStyle(style.tertiary)
                .fixedSize()
                .padding(.horizontal, 4.scaled)
            arrow("chevron.up", help: "Older match (↵ or ⌘G)", disabled: model.olderDisabled) { model.step(.older) }
            arrow("chevron.down", help: "Newer match (⇧↵ or ⌘⇧G)", disabled: model.newerDisabled) { model.step(.newer) }
            Button { model.close() } label: {
                Text("⌘F")
                    .calmFont(size: 11)
                    .foregroundStyle(style.tertiary)
                    .fixedSize() // the words give way at the field's narrowest, never the cap
                    .padding(.horizontal, 6.scaled)
                    .frame(height: 20.scaled)
                    .background(RoundedRectangle(cornerRadius: 5.scaled, style: .continuous).fill(style.primary.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .help("Close (⌘F)")
            .accessibilityLabel("Close find")
            .padding(.leading, 4.scaled)
        }
        .padding(.leading, 10.scaled)
        .padding(.trailing, 4.scaled)
        .frame(height: 30.scaled)
        .background(RoundedRectangle(cornerRadius: 8.scaled, style: .continuous).fill(style.primary.opacity(0.07)))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("titleStrip")) } action: { frame in
            onFrame(id, frame)
            model.fieldFrame = frame
        }
        .onDisappear {
            onFrame(id, nil)
            model.fieldFrame = nil
        }
        .onChange(of: model.focusRequest, initial: true) {
            focused = true
            // What's in it is selected, so typing replaces the last search (FEATURES.md → F16).
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        // The strip swaps its whole row when find opens, so a transition here would never run: the
        // field fades in as it appears. It goes at once on closing, as the readout comes back.
        .opacity(shown ? 1 : 0)
        .onAppear {
            if Motion.isReduced {
                shown = true
            } else {
                withAnimation(.easeOut(duration: 0.16)) { shown = true }
            }
        }
    }

    private func arrow(_ symbol: String, help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .calmFont(size: 11, weight: .semibold)
                .foregroundStyle(style.tertiary)
                .frame(width: 22.scaled, height: 22.scaled)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.35 : 1)
        .help(help)
        .accessibilityLabel(help)
    }
}
