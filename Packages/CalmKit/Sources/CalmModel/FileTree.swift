import Foundation

/// A changed file in the files column (FEATURES.md → F10), from `git status`.
public enum GitChange: String, Sendable, Equatable {
    case modified = "M"
    case added = "A"
    case deleted = "D"
    case renamed = "R"
    case untracked = "U"

    /// Parses `git status --porcelain=v1 -z`: `XY path\0`, and for renames or copies a second
    /// `\0`-separated field with the old path.
    public static func parse(porcelain: String) -> [String: GitChange] {
        var changes: [String: GitChange] = [:]
        var fields = porcelain.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)[...]
        while let field = fields.popFirst() {
            guard field.count > 3 else { continue }
            let status = field.prefix(2)
            let path = String(field.dropFirst(3))
            let index = status.first!
            let worktree = status.last!
            if index == "R" || index == "C" {
                _ = fields.popFirst() // the old path
                changes[path] = .renamed
            } else if status == "??" {
                changes[path] = .untracked
            } else if index == "A" {
                changes[path] = .added
            } else if index == "D" || worktree == "D" {
                changes[path] = .deleted
            } else if index == "M" || worktree == "M" || index == "T" || worktree == "T" || worktree == "A" {
                changes[path] = .modified
            }
        }
        return changes
    }
}

/// One entry of the files column.
public struct FileNode: Identifiable, Sendable, Equatable {
    /// The path relative to the project folder.
    public var path: String
    public var name: String
    public var children: [FileNode]?
    /// The file's change, or for a folder, whether anything inside changed (`.modified`).
    public var change: GitChange?

    public var id: String {
        path
    }

    public var isFolder: Bool {
        children != nil
    }

    /// A tree from relative paths (as `git ls-files` lists them): folders first, then files, each
    /// in a case-insensitive order. Folders holding changes are marked.
    public static func tree(paths: [String], changes: [String: GitChange]) -> [FileNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [String] = []
        }
        let root = Folder()
        for path in paths where !path.isEmpty {
            let parts = path.split(separator: "/").map(String.init)
            var folder = root
            for part in parts.dropLast() {
                if folder.folders[part] == nil {
                    folder.folders[part] = Folder()
                }
                folder = folder.folders[part]!
            }
            folder.files.append(parts.last!)
        }
        func nodes(_ folder: Folder, prefix: String) -> [FileNode] {
            let sorted: (String, String) -> Bool = { $0.localizedStandardCompare($1) == .orderedAscending }
            let folders = folder.folders.keys.sorted(by: sorted).map { name -> FileNode in
                let path = prefix + name
                let children = nodes(folder.folders[name]!, prefix: path + "/")
                let changed = children.contains { $0.change != nil }
                return FileNode(path: path, name: name, children: children, change: changed ? .modified : nil)
            }
            let files = folder.files.sorted(by: sorted).map { name in
                FileNode(path: prefix + name, name: name, children: nil, change: changes[prefix + name])
            }
            return folders + files
        }
        return nodes(root, prefix: "")
    }
}
