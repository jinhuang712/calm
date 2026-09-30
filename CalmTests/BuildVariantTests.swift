@testable import Calm
import Foundation
import Testing

struct BuildVariantTests {
    /// project.yml and BuildVariant each hold the name; the bundle's (which the menu bar, the Dock
    /// and notifications show) must be the one Calm's own menus and alerts use.
    @Test func `the bundle carries the name and icon Calm shows for its own variant`() {
        let info = Bundle.main.infoDictionary ?? [:]
        #expect(info["CFBundleName"] as? String == BuildVariant.appName)
        #expect(info["CFBundleDisplayName"] as? String == BuildVariant.appName)
        #expect(info["CFBundleIconName"] as? String == (BuildVariant.isDev ? "AppIconDev" : "AppIcon"))
    }

    /// The dev build must never share the installed Calm's identity: macOS matches a running app to
    /// a pinned Dock tile, UserDefaults and notification settings by it.
    @Test func `the dev build has a bundle id of its own`() {
        #expect(Bundle.main.bundleIdentifier == (BuildVariant.isDev ? "com.jinhuang.calm.dev" : "com.jinhuang.calm"))
    }

    @MainActor
    @Test func `the app menu is named for the variant`() throws {
        #expect(BuildVariant.appName == (BuildVariant.isDev ? "Calm Dev" : "Calm"))
        let appMenu = try #require(MainMenu.make().items.first?.submenu)
        #expect(appMenu.title == BuildVariant.appName)
        #expect(appMenu.items.first?.title == "About \(BuildVariant.appName)")
    }
}
