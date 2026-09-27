import AppKit
import CalmModel
import SwiftUI

/// Settings → Appearance → Window (ROADMAP.md → M6.4): background, layout and motion. A change
/// is saved to config.toml (a default removes its key) and applied at once.
@MainActor
@Observable
final class WindowOptionsModel {
    private(set) var background = CalmSettings.WindowBackground.solid
    private(set) var layout = CalmSettings.WindowLayout.edge
    private(set) var motion = CalmSettings.MotionLevel.full

    func refresh() {
        let settings = SessionManager.shared.settings
        background = settings.windowBackground
        layout = settings.windowLayout
        motion = settings.motion
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

struct WindowOptionsView: View {
    let model: WindowOptionsModel

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            row("Background", selection: model.background, set: model.setBackground) { value in
                switch value {
                case .solid: "Solid"
                case .glass: "Glass"
                }
            }
            row("Layout", selection: model.layout, set: model.setLayout) { value in
                switch value {
                case .edge: "Edge to edge"
                case .card: "Card"
                }
            }
            row("Motion", selection: model.motion, set: model.setMotion) { value in
                switch value {
                case .full: "Full"
                case .reduced: "Reduced"
                case .off: "Off"
                }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                Text("The system's Reduce Motion always wins.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row<Value: Hashable & CaseIterable>(
        _ title: String, selection: Value, set: @escaping (Value) -> Void, label: @escaping (Value) -> String,
    ) -> some View where Value.AllCases: RandomAccessCollection {
        GridRow {
            Text(title)
                .font(.system(size: 12))
                .gridColumnAlignment(.trailing)
            Picker(title, selection: Binding(get: { selection }, set: { set($0) })) {
                ForEach(Array(Value.allCases), id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}
