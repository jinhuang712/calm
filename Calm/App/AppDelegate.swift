import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.mainMenu = MainMenu.make()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.title = "Calm"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("CalmMainWindow")
        window.contentView = NSHostingView(rootView: PlaceholderView())
        window.makeKeyAndOrderFront(nil)
        self.window = window

        NSApp.activate()

        #if DEBUG
            SelfTest.scheduleIfRequested()
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }
}

/// Shown until the terminal lands in Milestone 1.
private struct PlaceholderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Calm")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
            Text(GhosttyRuntime.statusLine)
                .font(.system(size: 13))
                .foregroundStyle(Color(white: 0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(white: 0.15))
    }
}
