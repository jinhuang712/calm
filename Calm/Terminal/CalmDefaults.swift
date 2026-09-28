import AppKit
import CalmModel

/// Calm's own Ghostty settings, written to Application Support on each launch and loaded
/// before the user's config, so the user's keys always win.
enum CalmDefaults {
    /// `~/Library/Application Support/Calm`, overridable with `CALM_SUPPORT_DIR` (self-tests).
    static var directory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CALM_SUPPORT_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        // Unit tests host the app: a folder of their own, or they'd rewrite the running Calm's
        // files (found in real use: its cursor shader pointed into a worktree's Debug build).
        if environment["XCTestConfigurationFilePath"] != nil {
            return testDirectory
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm", directoryHint: .isDirectory)
    }

    private static let testDirectory = FileManager.default.temporaryDirectory
        .appending(path: "calm-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    static var fileURL: URL {
        directory.appending(path: "defaults.ghostty")
    }

    /// The settings Calm applies by default.
    static func contents(reduceMotion: Bool, cursorShader: URL?, theme: [String] = []) -> String {
        var lines = ["# Written by Calm on every launch. Put your own settings in your Ghostty config."]
        // Calm's default theme; a theme or colors in the user's Ghostty config win (TerminalTheme).
        lines += theme
        // A full-screen app that paints its own background (OpenCode, Neovim) would otherwise sit
        // in a frame of the theme's background: the padding takes the nearest cell's color instead.
        // Ghostty keeps the theme color at a shell prompt, where extending looks worse.
        lines.append("window-padding-color = extend")

        // ⌘K searches sessions in Calm (UIUX.md → Keyboard); clear screen moves to ⌘⇧K.
        lines.append("keybind = super+k=unbind")
        lines.append("keybind = super+shift+k=clear_screen")
        // ⌘, opens Settings, the Mac convention; Ghostty's open_config isn't supported in Calm.
        lines.append("keybind = super+,=unbind") // the character, as Ghostty binds it (`comma` is the physical key)
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
        let reduceMotion = AccessibilitySettings.reduceMotion || settings.motion != .full
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
