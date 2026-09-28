import Foundation

/// The hidden folders scratch sessions start in (FEATURES.md → F2): one per ⌘⇧N, kept across
/// restarts rather than in a temporary directory, which macOS clears on its own.
enum ScratchFolders {
    /// Self-tests and unit tests keep theirs with their own support files, away from the real ones.
    static var root: URL {
        CalmDefaults.isolatedDirectory?.appending(path: "Scratch", directoryHint: .isDirectory)
            ?? standardRoot(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// `~/.local/share/calm/scratch`: a shell's working folder, so no spaces (Application Support
    /// has one, which trips tools that don't quote paths) and short in a prompt. A fixed path next
    /// to `~/.config/calm`, not `$XDG_DATA_HOME`: an app opened from the Dock doesn't get the
    /// shell's environment, so honoring it would move the folder with how Calm was started.
    static func standardRoot(home: URL) -> URL {
        home.appending(path: ".local/share/calm/scratch", directoryHint: .isDirectory)
    }

    /// A new empty folder, named after the time it was made (never shown).
    static func make(in root: URL = root, now: Date = Date()) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMdd-HHmmss"
        let stamp = formatter.string(from: now)
        var folder = root.appending(path: stamp, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: folder.path) {
            folder = root.appending(path: "\(stamp)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        excludeFromBackup(root)
        return folder
    }

    /// Throwaway work stays out of Time Machine. Set on the root, not on each folder: the flag
    /// travels with a folder that's moved, so one kept as a project would never be backed up.
    private static func excludeFromBackup(_ root: URL) {
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    /// The files a user would care about: Finder's `.DS_Store` doesn't count.
    static func contents(of folder: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0 != ".DS_Store" }
    }

    /// Removes a folder that has nothing in it; one with files goes to the Trash instead.
    static func discard(_ folder: String) {
        let url = URL(filePath: folder, directoryHint: .isDirectory)
        if contents(of: folder).isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else {
            try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }
}
