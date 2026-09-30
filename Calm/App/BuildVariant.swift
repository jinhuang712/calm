import Foundation

/// Which Calm this is. The Debug build ("Calm Dev": what `mise run run` and the self-tests launch)
/// looks a little different from the installed Release build, so the two are never taken for each
/// other: a violet icon instead of the warm one, the name "Calm Dev" in the menu bar, and a quiet
/// DEV tag above the sidebar's search field. Nothing else changes: themes, states and layout stay
/// as they ship, so what you test is what you install.
enum BuildVariant {
    static let isDev: Bool = {
        #if DEBUG
            true
        #else
            false
        #endif
    }()

    /// The app's name where Calm names itself. project.yml gives the bundle the same one
    /// (APP_DISPLAY_NAME), for the Dock, the menu bar and notifications.
    static let appName = isDev ? "Calm Dev" : "Calm"
}
