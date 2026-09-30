import Foundation

/// What the title strip says about the project's uncommitted work while the files column is away
/// (FEATURES.md → F10): how many files changed, and the lines they add and remove ("3 changed
/// +58 −6"). The files column's Changes section lists the same files, so the two agree.
public struct ChangeSummary: Sendable, Equatable {
    public var count: Int
    /// Nil when git couldn't count any (a repository without commits, only binary files).
    public var lines: LineCounts?

    /// Nil when nothing changed: a clean project has nothing to report.
    public init?(changes: [String: GitChange], lines: [String: LineCounts]) {
        guard !changes.isEmpty else { return nil }
        count = changes.count
        self.lines = LineCounts.total(changes.keys.compactMap { lines[$0] })
    }

    /// The words of the readout, before its line counts.
    public var headline: String {
        "\(count) changed"
    }

    /// For VoiceOver: "3 files changed, 58 lines added, 6 removed".
    public var spoken: String {
        let files = "\(count) \(count == 1 ? "file" : "files") changed"
        guard let lines else { return files }
        return "\(files), \(lines.added) \(lines.added == 1 ? "line" : "lines") added, \(lines.deleted) removed"
    }
}

public extension LineCounts {
    /// The sum of `counts`; nil when there are none to add (git counted nothing).
    static func total(_ counts: [LineCounts]) -> LineCounts? {
        counts.isEmpty ? nil : counts.reduce(LineCounts(added: 0, deleted: 0), +)
    }
}
