import Foundation

/// The home folders macOS keeps behind a privacy prompt (System Settings → Privacy & Security →
/// Files & Folders). Reading one asks the user, and asks again whenever the app's signature isn't
/// the one they granted. Calm reads them only when the user opens one (DESIGNS.md → Files and
/// viewer). iCloud Drive, removable and network volumes are guarded too, but a walk never reaches
/// them by itself: iCloud Drive sits in the hidden `Library`.
public enum GuardedFolders {
    public static let names = ["Desktop", "Documents", "Downloads"]

    /// The guarded folders' absolute paths under `home`, spelled as a walk builds them (no
    /// trailing slash, symlinks left alone).
    public static func paths(home: String = NSHomeDirectory()) -> Set<String> {
        let base = home.count > 1 && home.hasSuffix("/") ? String(home.dropLast()) : home
        return Set(names.map { base + "/" + $0 })
    }
}
