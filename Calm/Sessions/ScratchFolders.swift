import Foundation

/// The hidden folders scratch sessions start in (FEATURES.md → F2): one per ⌘⇧N, under Calm's
/// support folder rather than a temporary directory, which macOS clears on its own.
enum ScratchFolders {
    static var root: URL {
        CalmDefaults.directory.appending(path: "Scratch", directoryHint: .isDirectory)
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
        return folder
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
