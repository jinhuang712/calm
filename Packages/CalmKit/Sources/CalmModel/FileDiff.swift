import Foundation

/// One file's changes against the last commit, from `git diff -U3 HEAD -- <file>` (FEATURES.md →
/// F10): the viewer's changed-line marks, its unified diff and its split diff all come from it.
public struct FileDiff: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case context, removed, added
    }

    public struct Line: Sendable, Equatable {
        public var kind: Kind
        public var text: String
        /// The line's number in the last commit's version; nil for an added line.
        public var old: Int?
        /// The line's number in the file as it is now; nil for a removed line.
        public var new: Int?

        public init(kind: Kind, text: String, old: Int?, new: Int?) {
            self.kind = kind
            self.text = text
            self.old = old
            self.new = new
        }
    }

    public struct Hunk: Sendable, Equatable {
        public var oldStart: Int
        public var oldCount: Int
        public var newStart: Int
        public var newCount: Int
        /// The words git shows after the second `@@` (the function the hunk is in), maybe empty.
        public var section: String
        public var lines: [Line]

        /// `@@ −4,4 +4,4 @@`, with a real minus sign.
        public var header: String {
            "@@ −\(oldStart),\(oldCount) +\(newStart),\(newCount) @@"
        }
    }

    /// How a line of the file as it is now changed: shown as a mark beside it.
    public enum Mark: String, Sendable, Equatable {
        case added, modified
    }

    /// A row of the split diff: the last commit's line on the left, the new one on the right,
    /// either missing where lines were only removed or only added.
    public struct Pair: Sendable, Equatable {
        public var left: Line?
        public var right: Line?
        /// The part of each side that changed, when the two are worth comparing word by word.
        public var emphasis: Emphasis?
    }

    /// The changed part of a modified line, in UTF-16 offsets (what the viewer's page counts in).
    public struct Emphasis: Sendable, Equatable {
        public var old: Range<Int>
        public var new: Range<Int>
    }

    public var hunks: [Hunk]

    public init(hunks: [Hunk]) {
        self.hunks = hunks
    }

    public var added: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } }
    }

    public var removed: Int {
        hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } }
    }

    /// Parses the output of `git diff` for one file. Nil when it has no hunks: an unchanged file,
    /// a binary one ("Binary files … differ"), or output that isn't a diff.
    public static func parse(_ text: String) -> FileDiff? {
        var hunks: [Hunk] = []
        var old = 0
        var new = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? raw.dropLast() : raw
            if line.hasPrefix("@@") {
                guard let hunk = header(String(line)) else { continue }
                hunks.append(hunk)
                old = hunk.oldStart
                new = hunk.newStart
                continue
            }
            guard !hunks.isEmpty, let first = line.first else { continue }
            let body = String(line.dropFirst())
            switch first {
            case " ":
                hunks[hunks.count - 1].lines.append(Line(kind: .context, text: body, old: old, new: new))
                old += 1
                new += 1
            case "-":
                hunks[hunks.count - 1].lines.append(Line(kind: .removed, text: body, old: old, new: nil))
                old += 1
            case "+":
                hunks[hunks.count - 1].lines.append(Line(kind: .added, text: body, old: nil, new: new))
                new += 1
            default:
                // "\ No newline at end of file", or the next file's header (there is none: one file).
                continue
            }
        }
        hunks.removeAll { $0.lines.isEmpty }
        return hunks.isEmpty ? nil : FileDiff(hunks: hunks)
    }

    /// `@@ -4,4 +4,5 @@ section`; a count left out is 1.
    private static func header(_ line: String) -> Hunk? {
        let parts = line.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
        guard parts.count >= 4, parts[0] == "@@", parts[3] == "@@",
              let (oldStart, oldCount) = range(parts[1], sign: "-"),
              let (newStart, newCount) = range(parts[2], sign: "+")
        else { return nil }
        let section = parts.count > 4 ? String(parts[4]) : ""
        return Hunk(oldStart: oldStart, oldCount: oldCount, newStart: newStart, newCount: newCount, section: section, lines: [])
    }

    private static func range(_ field: Substring, sign: Character) -> (Int, Int)? {
        guard field.first == sign else { return nil }
        let numbers = field.dropFirst().split(separator: ",", omittingEmptySubsequences: false)
        guard let start = Int(numbers[0]) else { return nil }
        guard numbers.count > 1 else { return (start, 1) }
        guard let count = Int(numbers[1]) else { return nil }
        return (start, count)
    }

    // MARK: Runs

    /// A stretch of removed lines followed by added ones (either may be empty), with the number
    /// the next line of the file as it is now has.
    private struct Run {
        var removed: [Line] = []
        var added: [Line] = []
        var nextNew = 0
    }

    /// Each hunk's lines as context lines and runs of changes, in order.
    private enum Piece {
        case context(Line)
        case run(Run)
    }

    private static func pieces(of hunk: Hunk) -> [Piece] {
        var pieces: [Piece] = []
        var run = Run()
        var new = hunk.newStart
        func flush() {
            guard !run.removed.isEmpty || !run.added.isEmpty else { return }
            run.nextNew = new
            pieces.append(.run(run))
            run = Run()
        }
        for line in hunk.lines {
            switch line.kind {
            case .context:
                flush()
                pieces.append(.context(line))
                new += 1
            case .removed:
                // A removed line after added ones starts a new run (git writes removals first).
                if !run.added.isEmpty {
                    flush()
                }
                run.removed.append(line)
            case .added:
                run.added.append(line)
                new += 1
            }
        }
        flush()
        return pieces
    }

    // MARK: The file's marks

    /// The marks beside the file as it is now, by line number: in a run, as many added lines as
    /// there were removed ones count as modified, the rest as added.
    public var marks: [Int: Mark] {
        var marks: [Int: Mark] = [:]
        for hunk in hunks {
            for case let .run(run) in Self.pieces(of: hunk) {
                for (index, line) in run.added.enumerated() {
                    if let new = line.new {
                        marks[new] = index < run.removed.count ? .modified : .added
                    }
                }
            }
        }
        return marks
    }

    /// Where lines were only removed, as the number of the line of the file as it is now that
    /// follows them (one past the last line when they were at the end).
    public var deletions: [Int] {
        var deletions: [Int] = []
        for hunk in hunks {
            for case let .run(run) in Self.pieces(of: hunk) where run.removed.count > run.added.count {
                deletions.append(run.nextNew)
            }
        }
        return deletions
    }

    // MARK: Split rows

    /// The split diff's rows for `hunk`: context lines on both sides, and in a run the removed
    /// and added lines side by side, one-sided where one run is longer.
    public static func pairs(of hunk: Hunk) -> [Pair] {
        var pairs: [Pair] = []
        for piece in pieces(of: hunk) {
            switch piece {
            case let .context(line):
                pairs.append(Pair(left: line, right: line, emphasis: nil))
            case let .run(run):
                for index in 0 ..< max(run.removed.count, run.added.count) {
                    let left = index < run.removed.count ? run.removed[index] : nil
                    let right = index < run.added.count ? run.added[index] : nil
                    let changed = left.flatMap { left in right.flatMap { Self.emphasis(old: left.text, new: $0.text) } }
                    pairs.append(Pair(left: left, right: right, emphasis: changed))
                }
            }
        }
        return pairs
    }

    /// The emphasis of each changed line in `hunk`, keyed by its index in `hunk.lines`, for the
    /// unified diff: the same pairing as the split one.
    public static func emphases(in hunk: Hunk) -> [Int: Range<Int>] {
        var result: [Int: Range<Int>] = [:]
        var index = 0
        for piece in pieces(of: hunk) {
            switch piece {
            case .context:
                index += 1
            case let .run(run):
                for offset in 0 ..< min(run.removed.count, run.added.count) {
                    if let emphasis = emphasis(old: run.removed[offset].text, new: run.added[offset].text) {
                        result[index + offset] = emphasis.old
                        result[index + run.removed.count + offset] = emphasis.new
                    }
                }
                index += run.removed.count + run.added.count
            }
        }
        return result
    }

    /// The part of `old` and `new` between what they share at the start and at the end. Nil when
    /// they're the same, or share too little for the difference to read as an edit (then the
    /// whole line is the change and nothing is singled out).
    public static func emphasis(old: String, new: String) -> Emphasis? {
        let oldCharacters = Array(old)
        let newCharacters = Array(new)
        var prefix = 0
        while prefix < oldCharacters.count, prefix < newCharacters.count, oldCharacters[prefix] == newCharacters[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < oldCharacters.count - prefix, suffix < newCharacters.count - prefix,
              oldCharacters[oldCharacters.count - 1 - suffix] == newCharacters[newCharacters.count - 1 - suffix] {
            suffix += 1
        }
        let shared = prefix + suffix
        guard shared < max(oldCharacters.count, newCharacters.count) else { return nil }
        // Less than a third of the longer line in common: a rewrite, not an edit.
        guard shared * 3 >= max(oldCharacters.count, newCharacters.count) else { return nil }
        func utf16(_ characters: ArraySlice<Character>) -> Int {
            characters.reduce(0) { $0 + $1.utf16.count }
        }
        let oldStart = utf16(oldCharacters[..<prefix])
        let newStart = utf16(newCharacters[..<prefix])
        let oldEnd = oldStart + utf16(oldCharacters[prefix ..< oldCharacters.count - suffix])
        let newEnd = newStart + utf16(newCharacters[prefix ..< newCharacters.count - suffix])
        return Emphasis(old: oldStart ..< oldEnd, new: newStart ..< newEnd)
    }
}
