import AppKit
import CalmModel
import GhosttyKit

/// An owned libghostty config.
///
/// Calm reads the user's Ghostty config, so an existing setup carries over, then
/// layers `~/.config/calm/terminal.ghostty` on top for Calm-only overrides.
final class TerminalConfig: @unchecked Sendable {
    /// libghostty config handle, freed in `deinit`. Safe to share: it is only read after loading.
    let raw: ghostty_config_t
    private(set) var diagnostics: [String] = []

    /// Calm's own override file, loaded after the Ghostty config.
    static var overridesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".config/calm/terminal.ghostty")
    }

    init(owning raw: ghostty_config_t) {
        self.raw = raw
    }

    deinit {
        ghostty_config_free(raw)
    }

    @MainActor
    static func load() -> TerminalConfig {
        guard let raw = ghostty_config_new() else {
            fatalError("libghostty could not allocate a config")
        }
        TerminalTheme.refreshLibrary()
        // Calm's defaults go first so anything in the user's own config wins.
        if let defaults = CalmDefaults.write() {
            defaults.path.withCString { ghostty_config_load_file(raw, $0) }
        }
        // Self-tests leave the user's own files out (CALM_GHOSTTY_CONFIG=none), so runs don't
        // depend on them.
        let readsUserConfig = ProcessInfo.processInfo.environment["CALM_GHOSTTY_CONFIG"] != "none"
        if readsUserConfig {
            ghostty_config_load_default_files(raw)
        }
        // Choices made in Calm's settings (a picked theme, glass) come after the user's config, so they win.
        if let choices = TerminalTheme.choicesFile(settings: CalmSettings.load(), directory: CalmDefaults.directory) {
            choices.path.withCString { ghostty_config_load_file(raw, $0) }
        }
        if readsUserConfig, FileManager.default.fileExists(atPath: overridesURL.path) {
            overridesURL.path.withCString { ghostty_config_load_file(raw, $0) }
        }
        ghostty_config_load_recursive_files(raw)
        ghostty_config_finalize(raw)

        let config = TerminalConfig(owning: raw)
        let count = ghostty_config_diagnostics_count(raw)
        for index in 0 ..< count {
            let diagnostic = ghostty_config_get_diagnostic(raw, index)
            if let message = diagnostic.message {
                config.diagnostics.append(String(cString: message))
            }
        }
        for message in config.diagnostics {
            FileHandle.standardError.write(Data("calm: config: \(message)\n".utf8))
        }
        return config
    }

    /// The colors the user's own Ghostty config sets for one appearance, read without Calm's
    /// files; `nil` when it leaves them at Ghostty's defaults. The theme picker offers these as the
    /// "Ghostty" choice.
    ///
    /// A config only resolves `theme = light:…,dark:…` inside a surface, so the pair is read from
    /// the files and the probe gets one extra line naming the variant; colors the user set
    /// directly still win over it, as they do in the terminal.
    @MainActor
    static func userColors(dark: Bool) -> Colors? {
        guard ProcessInfo.processInfo.environment["CALM_GHOSTTY_CONFIG"] != "none", let raw = ghostty_config_new() else {
            return nil
        }
        ghostty_config_load_default_files(raw)
        let text = userConfigFiles.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        if let pair = CalmTheme.ghosttyThemePair(configText: text) {
            let probe = CalmDefaults.directory.appending(path: "ghostty-theme-probe.ghostty")
            try? FileManager.default.createDirectory(at: CalmDefaults.directory, withIntermediateDirectories: true)
            if (try? "theme = \(dark ? pair.dark : pair.light)\n".write(to: probe, atomically: true, encoding: .utf8)) != nil {
                probe.path.withCString { ghostty_config_load_file(raw, $0) }
            }
        }
        ghostty_config_load_recursive_files(raw)
        ghostty_config_finalize(raw)
        let config = TerminalConfig(owning: raw)
        guard let background = config.color("background"), let foreground = config.color("foreground") else { return nil }
        // Ghostty's own defaults (Config.zig): the user set no colors.
        if background.hexString == "#282c34", foreground.hexString == "#ffffff" {
            return nil
        }
        return Colors(background: background, foreground: foreground, palette: config.palette)
    }

    struct Colors {
        var background: NSColor
        var foreground: NSColor
        var palette: [NSColor]
    }

    /// The Ghostty config file to open for editing: the first that exists, else the usual one.
    static var userConfigFile: URL {
        userConfigFiles.first { FileManager.default.fileExists(atPath: $0.path) } ?? userConfigFiles[0]
    }

    /// The files `ghostty_config_load_default_files` reads on macOS, in its order.
    private static var userConfigFiles: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"].map { URL(filePath: $0) }
            ?? home.appending(path: ".config")
        let support = home.appending(path: "Library/Application Support/com.mitchellh.ghostty")
        return [
            xdg.appending(path: "ghostty/config"), xdg.appending(path: "ghostty/config.ghostty"),
            support.appending(path: "config"), support.appending(path: "config.ghostty"),
        ]
    }

    // MARK: Typed reads

    /// The 16 ANSI colors.
    var palette: [NSColor] {
        var value = ghostty_config_palette_s()
        guard get("palette", into: &value) else { return [] }
        return withUnsafeBytes(of: value.colors) { bytes in
            bytes.bindMemory(to: ghostty_config_color_s.self).prefix(16).map {
                NSColor(srgbRed: CGFloat($0.r) / 255, green: CGFloat($0.g) / 255, blue: CGFloat($0.b) / 255, alpha: 1)
            }
        }
    }

    func bool(_ key: String) -> Bool? {
        var value = false
        return get(key, into: &value) ? value : nil
    }

    func double(_ key: String) -> Double? {
        var value = 0.0
        return get(key, into: &value) ? value : nil
    }

    func string(_ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        guard get(key, into: &value), let value else { return nil }
        return String(cString: value)
    }

    func color(_ key: String) -> NSColor? {
        var value = ghostty_config_color_s()
        guard get(key, into: &value) else { return nil }
        return NSColor(srgbRed: CGFloat(value.r) / 255, green: CGFloat(value.g) / 255, blue: CGFloat(value.b) / 255, alpha: 1)
    }

    private func get(_ key: String, into value: UnsafeMutableRawPointer) -> Bool {
        key.withCString { ghostty_config_get(raw, value, $0, UInt(key.utf8.count)) }
    }

    private func get(_ key: String, into value: inout some Any) -> Bool {
        withUnsafeMutablePointer(to: &value) { get(key, into: UnsafeMutableRawPointer($0)) }
    }

    // MARK: Derived values

    var backgroundColor: NSColor {
        color("background") ?? NSColor(white: 0.15, alpha: 1)
    }

    var backgroundOpacity: Double {
        double("background-opacity") ?? 1
    }
}
