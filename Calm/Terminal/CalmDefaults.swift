import AppKit
import CalmModel

/// Calm's own Ghostty settings, written to Application Support on each launch and loaded
/// before the user's config, so the user's keys always win.
enum CalmDefaults {
    /// `~/Library/Application Support/Calm`, overridable with `CALM_SUPPORT_DIR` (self-tests).
    static var directory: URL {
        isolatedDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Calm", directoryHint: .isDirectory)
    }

    /// The folder self-tests (`CALM_SUPPORT_DIR`) and unit tests keep Calm's files in, instead
    /// of the real ones; nil in the real app.
    static var isolatedDirectory: URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CALM_SUPPORT_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        // Unit tests host the app: a folder of their own, or they'd rewrite the running Calm's
        // files (found in real use: its cursor shader pointed into a worktree's Debug build).
        if environment["XCTestConfigurationFilePath"] != nil {
            return testDirectory
        }
        return nil
    }

    private static let testDirectory = FileManager.default.temporaryDirectory
        .appending(path: "calm-tests-\(ProcessInfo.processInfo.processIdentifier)", directoryHint: .isDirectory)

    static var fileURL: URL {
        directory.appending(path: "defaults.ghostty")
    }

    /// The settings Calm applies by default.
    static func contents(reduceMotion: Bool, cursorShader: URL?, smoothScroll: Bool = false, theme: [String] = []) -> String {
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
        // ⌘⇧T reopens the last closed session. Ghostty binds it to undo, which Calm doesn't do; that
        // binding would take the key first and pass it on to the shell.
        lines.append("keybind = super+shift+t=unbind")
        // ⌘N starts the agent chosen in Settings → Agents. Ghostty binds it to new_window, which in
        // Calm's one window was a second ⌘T; left bound, Ghostty would take the key before the menu.
        lines.append("keybind = super+n=unbind")
        // ⌘Z undoes the last edit of the line being typed (a paste, a ⌘⌫): it sends Ctrl-_, which
        // zsh, readline and Claude Code take as undo. Ghostty binds ⌘Z to `undo` (a closed tab),
        // which Calm doesn't do, and macOS encodes no bytes for an unbound ⌘-letter, so it did nothing.
        lines.append("keybind = super+z=text:\\x1f")
        // ⌘⌥ + arrow splits toward that side (⌘D and ⌘⇧D stay for right and down). Ghostty binds the
        // same keys to move focus between splits; Calm leaves focus to ⌘[ and ⌘], so the keys are
        // rebound here. A `goto_split` line in the user's own config still wins over this.
        for direction in ["left", "right", "up", "down"] {
            lines.append("keybind = super+alt+\(direction)=new_split:\(direction)")
        }
        if !reduceMotion, let cursorShader {
            // A soft cursor glide (UIUX.md → Motion). The animation loop runs in the focused pane
            // only, and only for a second after its cursor moves (engine patch 0014); with `true`
            // it redrew every 8 ms all day. An engine without the patch reports `cursor` as an
            // invalid value and keeps `true`.
            lines.append("custom-shader = \(cursorShader.path)")
            lines.append("custom-shader-animation = cursor")
        }
        if !reduceMotion, smoothScroll {
            // Scrolling moves by pixels (UIUX.md → Motion): trackpad scrollback, and a program
            // scrolling a region of its screen (Claude Code's full-screen view, less) slides instead
            // of jumping rows. The key comes with Calm's engine patch (scripts/ghostty-patches); an
            // engine without it would report an unknown key, so it's left out there.
            lines.append("smooth-scroll = true")
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
        let text = contents(
            reduceMotion: reduceMotion,
            cursorShader: shader,
            smoothScroll: GhosttyRuntime.hasSmoothScroll,
            theme: theme,
        )
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
