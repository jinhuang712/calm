#if DEBUG
    import AppKit
    import GhosttyKit

    /// Debug-only hooks for automated self-testing without Screen Recording permission.
    ///
    /// - `CALM_SELFTEST_TYPE="echo hi"` types this into the focused terminal, then Return.
    /// - `CALM_SELFTEST_ACTIONS="new_split:right,new_tab"` runs binding actions first, in order;
    ///   `calm.<name>` runs one of Calm's own (see `MainWindowController.performForTesting`).
    /// - `CALM_SNAPSHOT=/path/shot.png` saves the key window to a PNG once the UI settles.
    /// - `CALM_SELFTEST_TEXT=/path/screen.txt` saves the focused terminal's visible text.
    /// - `CALM_SNAPSHOT_DELAY=2.5` seconds to wait before capturing (default 1.5).
    /// - `CALM_SNAPSHOT_QUIT=1` quits after capturing.
    @MainActor
    enum SelfTest {
        private static func log(_ message: String) {
            FileHandle.standardError.write(Data("calm-selftest: \(message)\n".utf8))
        }

        static func scheduleIfRequested() {
            let env = ProcessInfo.processInfo.environment
            let snapshot = env["CALM_SNAPSHOT"].flatMap { $0.isEmpty ? nil : $0 }
            let textOut = env["CALM_SELFTEST_TEXT"].flatMap { $0.isEmpty ? nil : $0 }
            guard snapshot != nil || textOut != nil || env["CALM_SELFTEST_TYPE"] != nil else { return }
            let delay = env["CALM_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 1.5
            let quit = env["CALM_SNAPSHOT_QUIT"] == "1"

            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.8))
                for action in (env["CALM_SELFTEST_ACTIONS"] ?? "").split(separator: ",") {
                    let controller = TerminalWindowManager.shared.focusedController
                    let ok = action.hasPrefix("calm.")
                        ? controller?.performForTesting(String(action.dropFirst(5))) ?? false
                        : controller?.focusedPane?.perform(String(action)) ?? false
                    log("action \(action) → \(ok)")
                    try? await Task.sleep(for: .seconds(0.4))
                }
                let pane = TerminalWindowManager.shared.focusedController?.focusedPane
                if let text = env["CALM_SELFTEST_TYPE"], !text.isEmpty, let pane {
                    pane.typeForTesting(text)
                    log("typed \(text.count) characters")
                }
                if let keys = env["CALM_SELFTEST_KEYS"], !keys.isEmpty, let pane {
                    let sent = pane.pressKeysForTesting(keys)
                    log("pressed \(sent) keys through keyDown")
                }
                if let size = env["CALM_SELFTEST_RESIZE"], let pane, let window = pane.window {
                    let parts = size.split(separator: "x").compactMap { Double($0) }
                    if parts.count == 2 {
                        let before = pane.gridSizeForTesting
                        window.setContentSize(NSSize(width: parts[0], height: parts[1]))
                        try? await Task.sleep(for: .seconds(0.4))
                        log("resize \(size): grid \(before) → \(pane.gridSizeForTesting)")
                    }
                }
                if env["CALM_SELFTEST_DRAG"] == "1", let pane {
                    try? await Task.sleep(for: .seconds(0.6))
                    let copied = pane.dragAndCopyFirstRowForTesting()
                    log("drag-copied: \(copied.debugDescription)")
                }
                try? await Task.sleep(for: .seconds(delay))
                logLayout()
                if let snapshot {
                    let written = snapshotKeyWindow(to: URL(fileURLWithPath: snapshot))
                    log("snapshot \(written ? "written" : "failed") \(snapshot)")
                }
                if let textOut {
                    let text = TerminalWindowManager.shared.focusedController?.focusedPane?.viewportText() ?? ""
                    let written = (try? text.write(toFile: textOut, atomically: true, encoding: .utf8)) != nil
                    log("text \(written ? "written" : "failed") \(textOut) (\(text.count) characters)")
                }
                if quit {
                    // Skip the "processes still running" prompt: this is an automated run.
                    SessionManager.shared.prepareForQuit()
                    exit(0)
                }
            }
        }

        /// Where things are when the snapshot is taken: the focused pane's view chain, its
        /// rendered surface, and the window's parts. Explains blank or stale snapshots.
        private static func logLayout() {
            guard let controller = TerminalWindowManager.shared.focusedController else { return }
            if let pane = controller.focusedPane {
                var chain: [String] = []
                var view: NSView? = pane
                while let current = view {
                    chain.append("\(type(of: current))(alpha \(current.alphaValue), hidden \(current.isHidden))")
                    view = current.superview
                }
                log("focused pane \(pane.frame.size) in window \(pane.window != nil): " + chain.joined(separator: " < "))
                let layer = pane.layer
                let surface = (layer?.contents as? IOSurface).map { "IOSurface \($0.width)x\($0.height)px" } ?? "none"
                log("pane layer \(layer?.frame ?? .zero) presentation \(layer?.presentation()?.frame ?? .zero) contents \(surface)")
            }
            log("layout: \(controller.layoutForTesting)")
        }

        /// Renders the whole window frame (title bar included) through AppKit's cache.
        static func snapshotKeyWindow(to url: URL) -> Bool {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible),
                  let frameView = window.contentView?.superview
            else { return false }
            let bounds = frameView.bounds
            guard let rep = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return false }
            frameView.cacheDisplay(in: bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { return false }
            return (try? png.write(to: url)) != nil
        }
    }

    extension TerminalSurfaceView {
        /// Types text as if from the keyboard, then presses Return.
        func typeForTesting(_ text: String) {
            guard let surface else { return }
            text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
            var key = ghostty_input_key_s()
            key.action = GHOSTTY_ACTION_PRESS
            key.keycode = 36 // Return
            key.mods = GHOSTTY_MODS_NONE
            key.consumed_mods = GHOSTTY_MODS_NONE
            key.unshifted_codepoint = 13
            "\r".withCString { pointer in
                key.text = pointer
                _ = ghostty_surface_key(surface, key)
            }
            key.action = GHOSTTY_ACTION_RELEASE
            key.text = nil
            _ = ghostty_surface_key(surface, key)
        }
    }
#endif
