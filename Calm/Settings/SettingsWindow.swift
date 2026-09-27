import AppKit
import SwiftUI

/// The settings screen (FEATURES.md → F14, UIUX.md → Settings screen): a native window opened
/// with ⌘,, one toolbar tab per section. Everything it changes is saved to config.toml.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    enum Section: String, CaseIterable {
        case appearance, general, agents, keys, advanced

        var title: String {
            rawValue.capitalized
        }

        var symbol: String {
            switch self {
            case .appearance: "paintpalette"
            case .general: "gearshape"
            case .agents: "sparkles"
            case .keys: "keyboard"
            case .advanced: "slider.horizontal.3"
            }
        }
    }

    static let shared = SettingsWindowController()
    let themes = ThemePickerModel()
    let windowOptions = WindowOptionsModel()
    let general = GeneralSettingsModel()
    let agents = AgentsPanelModel()
    private let tabs = SettingsTabs()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false,
        )
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
        tabs.tabStyle = .toolbar
        // The window takes each section's size (SettingsTabs names it after the section).
        tabs.transitionOptions = [.allowUserInteraction]
        for section in Section.allCases {
            let item = NSTabViewItem(viewController: controller(for: section))
            item.label = section.title
            item.image = NSImage(systemSymbolName: section.symbol, accessibilityDescription: section.title)
            item.identifier = section.rawValue
            tabs.addTabViewItem(item)
        }
        window.contentViewController = tabs
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("not supported")
    }

    private func controller(for section: Section) -> NSViewController {
        let root = switch section {
        case .appearance: AnyView(AppearanceSettingsView(themes: themes, windowOptions: windowOptions))
        case .general: AnyView(GeneralSettingsView(model: general))
        case .agents: AnyView(SettingsPane { AgentsContent(model: agents) })
        case .keys: AnyView(KeysSettingsView())
        case .advanced: AnyView(AdvancedSettingsView())
        }
        let controller = NSHostingController(rootView: root)
        controller.sizingOptions = [.preferredContentSize]
        controller.title = section.title
        return controller
    }

    /// Opens Settings, at `section` if given (else where it was left).
    func show(_ section: Section? = nil) {
        themes.refresh()
        windowOptions.refresh()
        general.refresh()
        agents.refresh()
        if let section, let index = Section.allCases.firstIndex(of: section) {
            tabs.selectedTabViewItemIndex = index
        }
        guard let window else { return }
        window.title = tabs.tabViewItems[tabs.selectedTabViewItemIndex].label
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

/// Names the window after the selected section, as macOS settings windows do (the tab view
/// controller's own title propagation left the window untitled).
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        view.window?.title = item?.label ?? "Settings"
    }
}

struct AppearanceSettingsView: View {
    let themes: ThemePickerModel
    let windowOptions: WindowOptionsModel

    var body: some View {
        SettingsPane {
            SettingsHeading(title: "Theme", note: "Follows the system's light or dark appearance.")
            ThemePickerView(model: themes)
            Divider()
                .padding(.vertical, 20)
            SettingsHeading(title: "Window")
            WindowOptionsView(model: windowOptions)
        }
    }
}
