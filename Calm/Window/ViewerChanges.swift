import CalmModel
import Foundation

/// What git says about a file in the viewer (FEATURES.md → F10), against the last commit, as the
/// files column counts it: staged and unstaged changes together.
enum ViewerChange: Equatable {
    /// Not changed, outside a repository, or ignored by git.
    case unchanged
    /// Not in the last commit (untracked, or added and not committed yet): every line is new, so
    /// there is nothing to mark or compare.
    case new
    /// Changed: its diff, and the last commit's version of it for the diff's left side.
    case changed(FileDiff, oldText: String)

    /// Reads the file's state from git. Blocking: call it off the main thread.
    static func read(_ path: String) -> ViewerChange {
        let url = URL(filePath: path)
        let folder = url.deletingLastPathComponent().path
        let name = url.lastPathComponent
        // `--no-ext-diff` and `--no-textconv` keep a user's diff tools out of it, `--no-color`
        // their colors; the path is relative to the file's folder, where git runs.
        let diff = GitCommand.run(
            ["diff", "--no-color", "--no-ext-diff", "--no-textconv", "-U3", "HEAD", "--", name], in: folder,
        ).flatMap(FileDiff.parse)
        if let diff {
            // A file added to the index but not yet committed shows as one hunk of added lines.
            let isNew = diff.removed == 0 && diff.hunks.count == 1 && diff.hunks[0].oldStart == 0 && diff.hunks[0].oldCount == 0
            if isNew {
                return .new
            }
            // `HEAD:./name` is the path relative to the folder git runs in.
            let old = GitCommand.run(["show", "HEAD:./\(name)"], in: folder) ?? ""
            return .changed(diff, oldText: old)
        }
        // Untracked, or added in a repository with no commits yet (no HEAD to compare with).
        let status = GitCommand.run(["status", "--porcelain=v1", "-z", "--", name], in: folder) ?? ""
        if status.hasPrefix("??") || status.hasPrefix("A") {
            return .new
        }
        return .unchanged
    }

    /// The lines added and removed, for the header's `+3 −3`.
    var lines: LineCounts? {
        guard case let .changed(diff, _) = self else { return nil }
        return LineCounts(added: diff.added, deleted: diff.removed)
    }

    /// What the viewer's page takes (`calmSetChanges`): the marks beside the file, and each hunk's
    /// rows for the unified diff and pairs for the split one, by line number on each side.
    var pagePayload: [String: Any]? {
        guard case let .changed(diff, oldText) = self else { return nil }
        let marks = Dictionary(uniqueKeysWithValues: diff.marks.map { (String($0.key), $0.value.rawValue) })
        let hunks: [[String: Any]] = diff.hunks.map { hunk in
            let emphases = FileDiff.emphases(in: hunk)
            let rows: [[String: Any]] = hunk.lines.enumerated().map { index, line in
                var row: [String: Any] = ["k": Self.pageKind(line.kind)]
                row["o"] = line.old
                row["n"] = line.new
                if let emphasis = emphases[index] {
                    row["em"] = [emphasis.lowerBound, emphasis.upperBound]
                }
                return row
            }
            let pairs: [[String: Any]] = FileDiff.pairs(of: hunk).map { pair in
                var result: [String: Any] = [:]
                if let left = pair.left {
                    var side: [String: Any] = ["k": Self.pageKind(left.kind), "o": left.old ?? 0]
                    if let emphasis = pair.emphasis {
                        side["em"] = [emphasis.old.lowerBound, emphasis.old.upperBound]
                    }
                    result["l"] = side
                }
                if let right = pair.right {
                    var side: [String: Any] = ["k": Self.pageKind(right.kind), "n": right.new ?? 0]
                    if let emphasis = pair.emphasis {
                        side["em"] = [emphasis.new.lowerBound, emphasis.new.upperBound]
                    }
                    result["r"] = side
                }
                return result
            }
            return [
                "header": hunk.header, "section": hunk.section,
                "newStart": hunk.newStart, "newCount": hunk.newCount, "rows": rows, "pairs": pairs,
            ]
        }
        return ["marks": marks, "deletions": diff.deletions, "oldText": oldText, "hunks": hunks]
    }

    private static func pageKind(_ kind: FileDiff.Kind) -> String {
        switch kind {
        case .context: "ctx"
        case .removed: "del"
        case .added: "add"
        }
    }
}
