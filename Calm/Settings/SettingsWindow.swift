import AppKit
import SwiftUI

/// The settings screen (FEATURES.md → F14, UIUX.md → Settings screen), a native window opened
/// with ⌘,. Appearance comes first; the other sections arrive with M6.5.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    let themes = ThemePickerModel()
    let windowOptions = WindowOptionsModel()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        let host = NSHostingView(rootView: SettingsView(themes: themes, windowOptions: windowOptions))
        // The window takes the content's height, which grows with the number of themes.
        host.sizingOptions = [.minSize, .maxSize]
        window.contentView = host
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    func show() {
        themes.refresh()
        windowOptions.refresh()
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        if Headless.isOn {
            Headless.present(window)
        } else {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }
}

struct SettingsView: View {
    let themes: ThemePickerModel
    let windowOptions: WindowOptionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Theme")
                .font(.system(size: 13, weight: .medium))
            Text("Follows the system's light or dark appearance.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
                .padding(.bottom, 16)
            ThemePickerView(model: themes)
            Divider()
                .padding(.vertical, 20)
            Text("Window")
                .font(.system(size: 13, weight: .medium))
                .padding(.bottom, 12)
            WindowOptionsView(model: windowOptions)
        }
        .padding(24)
        .frame(width: 560, alignment: .topLeading)
    }
}
