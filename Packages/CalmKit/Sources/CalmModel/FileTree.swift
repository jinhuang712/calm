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

/// The lines a change adds and removes (the files column's `+64 −31`).
public struct LineCounts: Sendable, Equatable {
    public var added: Int
    public var deleted: Int

    public init(added: Int, deleted: Int) {
        self.added = added
        self.deleted = deleted
    }

    public static func + (lhs: LineCounts, rhs: LineCounts) -> LineCounts {
        LineCounts(added: lhs.added + rhs.added, deleted: lhs.deleted + rhs.deleted)
    }

    /// Parses `git diff --numstat -z`: `added\tdeleted\tpath\0`, or for a rename or copy
    /// `added\tdeleted\t\0old\0new\0`, keyed by the new path. Binary files (`-\t-`) are left out.
    public static func parse(numstat: String) -> [String: LineCounts] {
        var counts: [String: LineCounts] = [:]
        var fields = numstat.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)[...]
        while let field = fields.popFirst() {
            let parts = field.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            var path = String(parts[2])
            if path.isEmpty {
                _ = fields.popFirst() // the old path
                path = fields.popFirst() ?? ""
            }
            guard !path.isEmpty, let added = Int(parts[0]), let deleted = Int(parts[1]) else { continue }
            counts[path] = LineCounts(added: added, deleted: deleted)
        }
        return counts
    }

    /// A new file's lines, counted as git counts them (a last line without a newline counts);
    /// nil for binary data (a NUL byte in the first 8 KB, git's own test).
    public static func lines(in data: Data) -> Int? {
        guard !data.prefix(8000).contains(0) else { return nil }
        let newlines = data.count { $0 == 0x0A }
        return data.last.map { $0 == 0x0A ? newlines : newlines + 1 } ?? 0
    }
}

/// A row of the files column's Changes: one changed file, with its folder and line counts.
public struct ChangedFile: Identifiable, Sendable, Equatable {
    /// The path relative to the project folder.
    public var path: String
    public var change: GitChange
    /// Nil when git can't count them (a binary file, a repository without commits).
    public var lines: LineCounts?

    public var id: String {
        path
    }

    public var name: String {
        (path as NSString).lastPathComponent
    }

    /// The folder it's in, relative to the project; empty at the top.
    public var folder: String {
        (path as NSString).deletingLastPathComponent
    }

    /// The folder nearest the file (`Window` for `Calm/Window/Files.swift`), the part of the
    /// path that tells the most in a narrow column.
    public var folderName: String {
        (folder as NSString).lastPathComponent
    }

    /// Every change, in the natural order of its path (`View2` before `View10`).
    public static func list(changes: [String: GitChange], lines: [String: LineCounts]) -> [ChangedFile] {
        changes
            .map { ChangedFile(path: $0.key, change: $0.value, lines: lines[$0.key]) }
            .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}

/// A row of the files column's tree: a file or folder at its depth, shown because every folder
/// above it is open.
public struct FileRow: Identifiable, Sendable, Equatable {
    public var node: FileNode
    public var depth: Int

    public var id: String {
        node.path
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

    /// A dotfile or dot folder (`.gitignore`, `.github`): shown, but quieter.
    public var isHidden: Bool {
        name.hasPrefix(".")
    }

    /// The rows the tree shows with the `expanded` folders open, top to bottom.
    public static func rows(_ nodes: [FileNode], expanded: Set<String>, depth: Int = 0) -> [FileRow] {
        nodes.flatMap { node -> [FileRow] in
            let row = FileRow(node: node, depth: depth)
            guard let children = node.children, expanded.contains(node.path) else { return [row] }
            return [row] + rows(children, expanded: expanded, depth: depth + 1)
        }
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
