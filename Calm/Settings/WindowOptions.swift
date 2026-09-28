import AppKit
import CalmModel
import SwiftUI

/// Settings → Appearance (ROADMAP.md → M6.4): background, layout and motion, and the terminal
/// font's name. A change is saved to config.toml (a default removes its key) and applied at once.
@MainActor
@Observable
final class WindowOptionsModel {
    private(set) var background = CalmSettings.WindowBackground.solid
    private(set) var layout = CalmSettings.WindowLayout.edge
    private(set) var motion = CalmSettings.MotionLevel.full
    /// "JetBrains Mono · 13 pt": set in the Ghostty config, which is where it's changed.
    private(set) var terminalFont = ""

    func refresh() {
        let settings = SessionManager.shared.settings
        background = settings.windowBackground
        layout = settings.windowLayout
        motion = settings.motion
        terminalFont = TerminalConfig.fontDescription
    }

    func setBackground(_ value: CalmSettings.WindowBackground) {
        guard value != background else { return }
        background = value
        // The terminal's opacity lives in the Ghostty config.
        save("window.background", value == .solid ? nil : value.rawValue, reloadsTerminal: true)
    }

    func setLayout(_ value: CalmSettings.WindowLayout) {
        guard value != layout else { return }
        layout = value
        save("window.layout", value == .edge ? nil : value.rawValue, reloadsTerminal: false)
    }

    func setMotion(_ value: CalmSettings.MotionLevel) {
        guard value != motion else { return }
        motion = value
        // The cursor glide is a Ghostty shader, on only with full motion.
        save("motion", value == .full ? nil : value.rawValue, reloadsTerminal: true)
    }

    /// `set:<key>=<value>` in self-tests goes through here, like a click.
    func set(_ key: String, _ value: String) {
        switch key {
        case "background": CalmSettings.WindowBackground(rawValue: value).map(setBackground)
        case "layout": CalmSettings.WindowLayout(rawValue: value).map(setLayout)
        case "motion": CalmSettings.MotionLevel(rawValue: value).map(setMotion)
        default: break
        }
    }

    private func save(_ key: String, _ value: String?, reloadsTerminal: Bool) {
        do {
            SessionManager.shared.settings = try CalmSettings.save(key, value)
        } catch {
            FileHandle.standardError.write(Data("calm: could not save \(key): \(error)\n".utf8))
            return
        }
        if reloadsTerminal {
            TerminalEngine.shared.reloadConfig(soft: false)
        }
        TerminalWindowManager.shared.controllers.forEach { $0.applyAppearance() }
    }
}
