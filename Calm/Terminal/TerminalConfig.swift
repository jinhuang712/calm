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
        // A theme picked in Calm comes after the user's config, so its colors win.
        if let theme = TerminalTheme.pickedFile(settings: CalmSettings.load(), directory: CalmDefaults.directory) {
            theme.path.withCString { ghostty_config_load_file(raw, $0) }
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

    // MARK: Typed reads

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
