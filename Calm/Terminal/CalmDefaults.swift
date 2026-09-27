import AppKit
import CalmModel

/// Calm's own Ghostty settings, written to Application Support on each launch and loaded
/// before the user's config, so the user's keys always win.
enum CalmDefaults {
    /// `~/Library/Application Support/Calm`, overridable with `CALM_SUPPORT_DIR` (self-tests).
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["CALM_SUPPORT_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm", directoryHint: .isDirectory)
    }

    static var fileURL: URL {
        directory.appending(path: "defaults.ghostty")
    }

    /// The settings Calm applies by default.
    static func contents(reduceMotion: Bool, cursorShader: URL?, theme: [String] = []) -> String {
        var lines = ["# Written by Calm on every launch. Put your own settings in your Ghostty config."]
        // Calm's default theme; a theme or colors in the user's Ghostty config win (TerminalTheme).
        lines += theme
        // ⌘K searches sessions in Calm (UIUX.md → Keyboard); clear screen moves to ⌘⇧K.
        lines.append("keybind = super+k=unbind")
        lines.append("keybind = super+shift+k=clear_screen")
        if !reduceMotion, let cursorShader {
            // A soft cursor glide (UIUX.md → Motion). The animation loop only runs in the focused pane.
            lines.append("custom-shader = \(cursorShader.path)")
            lines.append("custom-shader-animation = true")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    @MainActor
    @discardableResult
    static func write() -> URL? {
        let shader = Bundle.main.url(forResource: "cursor_glide", withExtension: "glsl")
        // Same rule as `Motion.isReduced`, read directly: this runs while the engine starts.
        let settings = CalmSettings.load()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || settings.motion != .full
        let theme = TerminalTheme.defaultLines(settings: settings, directory: directory)
        let text = contents(reduceMotion: reduceMotion, cursorShader: shader, theme: theme)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try text.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            FileHandle.standardError.write(Data("calm: could not write defaults: \(error)\n".utf8))
            return nil
        }
    }
}
