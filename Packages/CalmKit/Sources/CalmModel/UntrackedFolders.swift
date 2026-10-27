import Foundation

/// A folder with nothing tracked in it, as the files column shows it (specs/FEATURES.md → F10).
/// `git status` reports one as a single `dir/` entry; the column lists the files inside, unless
/// there are too many to be worth listing (a `node_modules` nobody ignored): then it is one row
/// with the count, and nothing inside is read, counted or drawn.
public struct UntrackedFolder: Sendable, Equatable {
    /// More files than this and the folder stays one row. A listing longer than this is not a
    /// listing anyone reads, and every file would be read again every 5 seconds.
    public static let limit = 500

    /// Relative to the project folder, without a trailing slash.
    public var path: String
    public var count: Int
    /// Every untracked file in it, relative to the project folder; empty for a collapsed folder.
    public var files: [String]

    public var isCollapsed: Bool {
        files.isEmpty && count >= 1
    }

    public init(path: String, count: Int, files: [String]) {
        self.path = path
        self.count = count
        self.files = files
    }

    /// The folders in a plain `git status`: its entries that end in a slash, without it.
    public static func paths(in changes: [String: GitChange]) -> [String] {
        changes.compactMap { $0.key.hasSuffix("/") ? String($0.key.dropLast()) : nil }.sorted()
    }

    /// Reads `git ls-files -o --exclude-standard -z -- <path>`. The files are counted without being
    /// decoded and listed only when there are few, so a huge folder costs a pass over the bytes.
    /// The project folder itself (an empty `path`) is always listed: it can't be one row.
    public static func read(path: String, lsFiles: Data) -> UntrackedFolder {
        let count = lsFiles.count { $0 == 0 }
        guard count <= limit || path.isEmpty else { return UntrackedFolder(path: path, count: count, files: []) }
        let files = (String(bytes: lsFiles, encoding: .utf8) ?? "")
            .split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
        return UntrackedFolder(path: path, count: files.count, files: files)
    }

    /// Replaces each folder's entry in `changes` (`dir/`) with what the column shows for it: its
    /// files, each untracked, or for a collapsed folder one untracked entry for the folder
    /// itself. Returns the collapsed folders and how many files each holds.
    public static func merge(_ folders: [UntrackedFolder], into changes: inout [String: GitChange]) -> [String: Int] {
        var collapsed: [String: Int] = [:]
        for folder in folders {
            changes[folder.path + "/"] = nil
            if folder.isCollapsed {
                changes[folder.path] = .untracked
                collapsed[folder.path] = folder.count
            }
            for file in folder.files {
                changes[file] = .untracked
            }
        }
        return collapsed
    }
}
