import Foundation

/// What a full-screen program showed (FEATURES.md → F16, the whole session; DESIGNS.md → Find).
/// Its screen keeps no history, so the pane reads it a few times a second while it draws, and
/// this keeps what went between two reads:
///
/// - Rows that moved up out of a scrolling region (an answer streaming in) are kept as they leave
///   the top. Scrolling back moves where the program's view is in the kept lines, so the lines
///   that come back and go again aren't kept twice.
/// - A view mostly replaced (another page, a dialog, a jump further than the region's height)
///   keeps the view that went, less any run of it already kept.
/// - Rows that change in place (a spinner, a timer, a status bar) keep nothing.
///
/// Lines that came and went between two reads are missed, the accepted trade. Each line keeps
/// when it was first on screen. Up to `limit` lines (50,000); the oldest go.
public struct ScreenKeeper: Sendable {
    public struct Line: Equatable, Sendable {
        public let text: String
        /// When it was first on screen.
        public let shown: Date
        /// The first line kept after the program moved on: its first, or the first after a view
        /// was replaced. The session page puts a time mark there.
        public let startsPart: Bool
    }

    /// How many lines are kept at most.
    public let limit: Int

    /// What was kept, oldest first.
    public private(set) var lines: [Line] = []
    /// Lines that went over the limit.
    public private(set) var dropped = 0

    /// The screen as last read, a row each, without trailing spaces, and when each row was first shown.
    private var screen: [String] = []
    /// Its rows as compared (`key`).
    private var screenKeys: [Int] = []
    private var shown: [Date] = []
    private var columns = 0
    /// Where the program's view is in `lines`: the index of the line its scrolling region's top row
    /// is (`lines.count` when that row hasn't been kept yet); nil when not known.
    private var head: Int?
    private var startsPart = true
    /// Where each non-blank line is in `lines`, counted with `dropped` lines, for finding a run
    /// that was kept already.
    private var positions: [String: [Int]] = [:]

    /// Where a program began, for the session page, which puts the shell's output before it first.
    public struct Program: Equatable, Sendable {
        /// Its first kept line, counted with the dropped ones.
        public let firstLine: Int
        /// How many lines the shell's screen had when it started (`SessionPage.shellLines`).
        public let shellLines: Int
    }

    /// Each program that took the screen, in order.
    public private(set) var programs: [Program] = []

    public init(limit: Int = 50000) {
        self.limit = limit
    }

    public var isEmpty: Bool {
        lines.isEmpty
    }

    /// A program took the screen, when the shell's screen had `shellLines` lines.
    public mutating func startProgram(shellLines: Int) {
        programs.append(Program(firstLine: dropped + lines.count, shellLines: shellLines))
    }

    /// The program's screen, `rows` as read at `time` in a pane `columns` wide.
    public mutating func see(_ rows: [String], columns: Int, at time: Date) {
        let rows = rows.map(Self.trimmed)
        guard !screen.isEmpty, rows.count == screen.count, columns == self.columns else {
            // The first read, or a new size: the program draws its view again for it, so nothing went.
            start(rows, columns: columns, at: time)
            return
        }
        let keys = rows.map(Self.key)
        guard keys != screenKeys else { return }
        var times = shown
        var moved = 0 ..< 0
        if let move = Self.move(from: screenKeys, to: keys) {
            if move.by > 0 {
                keepScrolled(move)
            } else {
                scrolledBack(move, to: rows)
            }
            // The rows that moved keep their times; those that came in are new.
            moved = move.top ..< move.end
            for row in moved {
                times[row] = shown[row + move.by]
            }
        } else if Self.isReplaced(screen, by: rows) {
            keep(screen.indices.filter { screenKeys[$0] != keys[$0] })
            head = nil
            startsPart = true
        }
        for row in rows.indices where keys[row] != screenKeys[row] && !moved.contains(row) {
            times[row] = time
        }
        screen = rows
        screenKeys = keys
        shown = times
    }

    /// The program left its screen (it quit, or went back to the shell's): keeps the view it
    /// showed last, and the next program's lines start a part of their own.
    public mutating func finish() {
        keep(Array(screen.indices))
        screen = []
        screenKeys = []
        shown = []
        head = nil
        startsPart = true
    }

    // MARK: Keeping

    private mutating func start(_ rows: [String], columns: Int, at time: Date) {
        screen = rows
        screenKeys = rows.map(Self.key)
        shown = Array(repeating: time, count: rows.count)
        self.columns = columns
        head = nil
    }

    /// The rows that left the top of the region `move` scrolled up.
    private mutating func keepScrolled(_ move: Move) {
        let leaving = move.top ..< move.top + move.by
        var position = head ?? align(screen[move.top ..< move.end + move.by]) ?? lines.count
        for row in leaving {
            if position < lines.count {
                if lines[position].text == screen[row] {
                    position += 1 // shown again after scrolling back: kept already
                    continue
                }
                position = lines.count // something else went: it goes at the end
            }
            append(screen[row], shown: shown[row])
            position = lines.count
        }
        head = position
    }

    /// The region `move` scrolled down: the rows that came in above it are the lines kept just
    /// before the view, when it's known where that is.
    private mutating func scrolledBack(_ move: Move, to rows: [String]) {
        let count = -move.by
        guard let current = head, current >= count,
              lines[current - count ..< current].map(\.text) == Array(rows[move.top - count ..< move.top]) else {
            head = nil
            return
        }
        head = current - count
    }

    /// Keeps the screen's `rows`, in order, leaving out any run of them kept already.
    private mutating func keep(_ rows: [Int]) {
        for row in rowsToKeep(rows) {
            append(screen[row], shown: shown[row])
        }
    }

    /// The screen's `rows` worth keeping, in order: any run of them kept already is left out, and
    /// blank rows stay only between rows kept here, never before or after them.
    private func rowsToKeep(_ rows: [Int]) -> [Int] {
        var index = 0
        var chosen: [Int] = []
        var pending: [Int] = []
        while index < rows.count {
            let row = rows[index]
            if !screen[row].isEmpty, let known = keptRun(rows[index...].map { screen[$0] }) {
                index += known
                pending = []
                continue
            }
            if screen[row].isEmpty {
                if !chosen.isEmpty {
                    pending.append(row)
                }
            } else {
                chosen += pending
                pending = []
                chosen.append(row)
            }
            index += 1
        }
        return chosen
    }

    /// What's on the program's screen now and isn't kept yet: the session page's last lines.
    public var screenLines: [Line] {
        var first = startsPart
        return rowsToKeep(Array(screen.indices)).map { row in
            let text = screen[row]
            let line = Line(text: text, shown: shown[row], startsPart: first && !text.isEmpty)
            if !text.isEmpty {
                first = false
            }
            return line
        }
    }

    private mutating func append(_ text: String, shown time: Date) {
        if !text.isEmpty {
            positions[text, default: []].append(dropped + lines.count)
        }
        lines.append(Line(text: text, shown: time, startsPart: startsPart && !text.isEmpty))
        if !text.isEmpty {
            startsPart = false
        }
        if lines.count > limit + limit / 10 {
            dropOldest()
        }
    }

    /// Drops what's over the limit in one go, a tenth of it at a time, so the index is made again
    /// rarely.
    private mutating func dropOldest() {
        let over = lines.count - limit
        lines.removeFirst(over)
        dropped += over
        head = head.map { $0 >= over ? $0 - over : 0 }
        positions = [:]
        for (index, line) in lines.enumerated() where !line.text.isEmpty {
            positions[line.text, default: []].append(dropped + index)
        }
    }

    // MARK: Finding what was kept

    /// How many of `rows`, from the first, are a run of kept lines with at least two that aren't
    /// blank; nil if none is (one line alike proves nothing).
    private func keptRun(_ rows: [String]) -> Int? {
        guard let first = rows.first, let starts = positions[first] else { return nil }
        var longest = 0
        // The latest first, and not every one: a line that came a thousand times is no help.
        for start in starts.suffix(64).reversed() {
            let index = start - dropped
            var length = 0
            var filled = 0
            while length < rows.count, index + length < lines.count, lines[index + length].text == rows[length] {
                filled += rows[length].isEmpty ? 0 : 1
                length += 1
            }
            if filled >= 2, length > longest {
                longest = length
            }
            if longest == rows.count {
                break
            }
        }
        return longest > 0 ? longest : nil
    }

    /// Where in `lines` the region's `rows` are, from its top row, when two or more of them are
    /// a kept run: the program's view came back to lines kept before.
    private func align(_ rows: ArraySlice<String>) -> Int? {
        guard let firstFilled = rows.firstIndex(where: { !$0.isEmpty }) else { return nil }
        let blanks = firstFilled - rows.startIndex
        let tail = Array(rows[firstFilled...])
        guard let first = tail.first, let starts = positions[first] else { return nil }
        for start in starts.suffix(64).reversed() {
            let index = start - dropped - blanks
            guard index >= 0, lines[index ..< index + blanks].allSatisfy(\.text.isEmpty) else { continue }
            var length = 0
            var filled = 0
            while length < tail.count, index + blanks + length < lines.count, lines[index + blanks + length].text == tail[length] {
                filled += tail[length].isEmpty ? 0 : 1
                length += 1
            }
            if filled >= 2 {
                return index
            }
        }
        return nil
    }

    // MARK: Comparing two screens

    /// Rows `top ..< end` of the new screen were rows `top + by ..< end + by` of the old one:
    /// a region moved up `by` rows (down, when negative).
    struct Move: Equatable {
        var top: Int
        var end: Int
        var by: Int
    }

    /// A run of rows that moved together (`run(from:by:old:new:)`).
    private struct Run {
        let move: Move
        /// How many of its rows moved and aren't blank.
        let score: Int
        /// The row after it, where looking goes on.
        let end: Int
    }

    /// A row as compared: 0 when blank, else its hash (never 0). Comparing hashes rather than
    /// text keeps a read cheap; two rows alike by chance are as good as never.
    static func key(_ row: String) -> Int {
        row.isEmpty ? 0 : row.hashValue | 1
    }

    /// The longest run of rows that moved together, with at least three that moved and aren't
    /// blank; rows the same in place at its ends are left out of it (a status bar, a blank line).
    /// Rows are their `key`s. Only the shifts the changed rows suggest are tried (where each one's
    /// text was before), not every one: a read is a few rows' work, not the screen's squared.
    static func move(from old: [Int], to new: [Int]) -> Move? {
        let count = min(old.count, new.count)
        var best: Move?
        var bestScore = 2
        // The shortest shift first, up before down, so a tie goes to the likelier one.
        for by in shifts(from: old, to: new).sorted(by: { (abs($0), -$0) < (abs($1), -$1) }) {
            var row = max(0, -by)
            while row < count, row + by < count {
                guard new[row] == old[row + by] else {
                    row += 1
                    continue
                }
                let run = run(from: row, by: by, old: old, new: new)
                if run.score > bestScore {
                    bestScore = run.score
                    best = run.move
                }
                row = run.end
            }
        }
        return best
    }

    /// The shifts worth trying: where each changed row's text was on the old screen.
    private static func shifts(from old: [Int], to new: [Int]) -> Set<Int> {
        let count = min(old.count, new.count)
        var rowsOf: [Int: [Int]] = [:]
        for row in 0 ..< count where old[row] != 0 {
            rowsOf[old[row], default: []].append(row)
        }
        var shifts: Set<Int> = []
        for row in 0 ..< count where new[row] != 0 && new[row] != old[row] {
            // A row the old screen had many times (a rule, a border) suggests nothing.
            guard let from = rowsOf[new[row]], from.count <= 4 else { continue }
            for source in from where source != row {
                shifts.insert(source - row)
            }
            if shifts.count >= 32 {
                break
            }
        }
        return shifts
    }

    /// The rows from `row` on that moved `by` together: the move without the rows at its ends that
    /// are the same in place, how many of them moved and aren't blank, and where the run ended.
    private static func run(from row: Int, by: Int, old: [Int], new: [Int]) -> Run {
        let count = min(old.count, new.count)
        var end = row
        var score = 0
        while end < count, end + by < count, new[end] == old[end + by] {
            if new[end] != 0, new[end] != old[end] {
                score += 1
            }
            end += 1
        }
        var top = row
        while top < end, new[top] == old[top] {
            top += 1
        }
        var bottom = end
        while bottom > top, new[bottom - 1] == old[bottom - 1] {
            bottom -= 1
        }
        return Run(move: Move(top: top, end: bottom, by: by), score: score, end: end)
    }

    /// Whether `new` replaced most of `old`'s view: at least three rows, and half the rows that
    /// had text, now hold something else. A row whose text stayed but for its digits (a timer, a
    /// count) changed in place.
    static func isReplaced(_ old: [String], by new: [String]) -> Bool {
        var filled = 0
        var replaced = 0
        for row in old.indices where !old[row].isEmpty {
            filled += 1
            if old[row] != new[row], !sameButDigits(old[row], new[row]) {
                replaced += 1
            }
        }
        return replaced >= 3 && replaced * 2 >= filled
    }

    /// Whether `a` and `b` hold the same text where digits are taken as alike, in at least four
    /// of five columns.
    static func sameButDigits(_ a: String, _ b: String) -> Bool {
        let a = Array(a.unicodeScalars)
        let b = Array(b.unicodeScalars)
        let length = max(a.count, b.count)
        guard length > 0 else { return true }
        var alike = 0
        let digits: ClosedRange<Unicode.Scalar> = "0" ... "9"
        for index in 0 ..< min(a.count, b.count) {
            let x = a[index]
            let y = b[index]
            if x == y || (digits.contains(x) && digits.contains(y)) {
                alike += 1
            }
        }
        return alike * 5 >= length * 4
    }

    static func trimmed(_ row: String) -> String {
        var row = Substring(row)
        while let last = row.last, last == " " || last == "\u{0}" {
            row.removeLast()
        }
        return String(row)
    }
}
