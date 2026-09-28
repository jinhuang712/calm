// The link pattern below is adapted from Ghostty's src/config/url.zig
// (https://github.com/ghostty-org/ghostty), MIT License,
// Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors. See NOTICE.

import Foundation

/// Some cells of one row of the screen.
public struct CellRun: Hashable, Sendable {
    public let row: Int
    public let columns: Range<Int>

    public init(row: Int, columns: Range<Int>) {
        self.row = row
        self.columns = columns
    }
}

/// A link in the terminal's visible text: what it says, and the cells it covers.
public struct LinkMatch: Hashable, Sendable {
    public let text: String
    /// One run per row: a link the terminal wrapped onto the next row has two.
    public let runs: [CellRun]
    /// Where each character starts, and how wide it is, for `prefix`.
    private let characters: [Cell]

    struct Cell: Hashable, Sendable {
        let row: Int
        let column: Int
        let width: Int
    }

    init(text: String, characters: [Cell]) {
        self.text = text
        self.characters = characters
        var runs: [CellRun] = []
        for cell in characters {
            if let last = runs.last, last.row == cell.row {
                runs[runs.count - 1] = CellRun(row: cell.row, columns: last.columns.lowerBound ..< cell.column + cell.width)
            } else {
                runs.append(CellRun(row: cell.row, columns: cell.column ..< cell.column + cell.width))
            }
        }
        self.runs = runs
    }

    /// The same link cut to its first `count` characters (a path with its trailing words dropped).
    public func prefix(_ count: Int) -> LinkMatch {
        LinkMatch(text: String(text.prefix(count)), characters: Array(characters.prefix(count)))
    }

    public func covers(row: Int, column: Int) -> Bool {
        runs.contains { $0.row == row && $0.columns.contains(column) }
    }

    public func overlaps(row: Int, columns: Range<Int>) -> Bool {
        runs.contains { $0.row == row && $0.columns.overlaps(columns) }
    }
}

/// Finds URLs and file paths in terminal text with libghostty's own pattern (FEATURES.md → F8),
/// so the links Calm marks at rest are the ones ⌘-click opens. libghostty only marks a link while
/// ⌘ is held, and its link setting can't be changed yet, so Calm finds them itself.
///
/// Ghostty's pattern is written for Oniguruma; this is the same pattern for ICU
/// (NSRegularExpression), which needs two changes: a lookbehind needs a bound (`\$\d*` becomes
/// `\$\d{0,9}`), and a set can't start with `[:`, which ICU reads as a property class.
public enum LinkMatcher {
    private static let schemes = #"https?://|mailto:|ftp://|file:|ssh:|git://|ssh://|tel:|magnet:|"#
        + #"ipfs://|ipns://|gemini://|gopher://|news:"#
    private static let ipv6 = #"(?:\[[\:0-9a-fA-F]+(?:[\:0-9a-fA-F]*)+\](?::[0-9]+)?)"#
    private static let schemeCharacters = #"[\w\-.~:/?#@!$&*+,;=%]"#
    private static let pathCharacters = #"[\w\-.~:\/?#@!$&*+;=%]"#
    private static let bracketedSuffix = #"(?:[\(\[]\w*[\)\]])?"#
    private static let noTrailingPunctuation = #"(?<![,.])"#
    private static let noTrailingColon = #"(?<!:)"#
    private static let dotted = #"(?=[\w\-.~:\/?#@!$&*+;=%]*\.)"#
    private static let undotted = #"(?![\w\-.~:\/?#@!$&*+;=%]*\.)"#
    /// Paths may run across single spaces (folders with spaces in their names).
    private static let dottedSpaces = #"(?:(?<!:) (?!\w+:\/\/)(?!\.{0,2}\/)(?!~\/)[\w\-.~:\/?#@!$&*+;=%]*[\/.])*"#
    private static let anySpaces = #"(?:(?<!:) (?!\w+:\/\/)(?!\.{0,2}\/)(?!~\/)[\w\-.~:\/?#@!$&*+;=%]+)*"#

    /// URLs with a scheme (http, mailto, ftp…).
    private static let schemeURL = "(?:\(schemes))(?:\(ipv6)|\(schemeCharacters)+\(bracketedSuffix))+\(noTrailingPunctuation)"

    /// Absolute and dot-relative paths (`/`, `./`, `../`, `~/`, `$VAR/`, `.config/`).
    private static let rootedPath = #"(?:\.\.\/|\.\/|(?<!\w)~\/|(?:[\w][\w\-.]*\/)*(?<!\w)\$[A-Za-z_]\w*\/|"#
        + #"\.[\w][\w\-.]*\/|(?<![\w~\/])\/(?!\/))"#
        + "(?:\(dotted)\(pathCharacters)+\(dottedSpaces)\(noTrailingColon)|\(undotted)\(pathCharacters)+\(anySpaces)\(noTrailingColon))"

    /// Bare relative paths such as `src/config/url.zig`: only with a dot somewhere, so `and/or` isn't one.
    private static let barePath = dotted + #"(?<!\$\d{0,9})(?<!\w)[\w][\w\-.]*\/"# + pathCharacters + "+" + noTrailingColon

    private static let expression = try? NSRegularExpression(
        pattern: [schemeURL, rootedPath, barePath].joined(separator: "|"),
    )

    /// The links in one line, left to right, as libghostty would match them.
    public static func links(in line: String) -> [String] {
        ranges(in: line).map { (line as NSString).substring(with: $0) }
    }

    /// The links in one line of the screen: `rows`, which the terminal wrapped from one line (a
    /// single row when it didn't wrap), with the cells each covers.
    public static func matches(in grid: TextGrid, rows: Range<Int>) -> [LinkMatch] {
        var line = ""
        // Where each character is, by its UTF-16 offset (what NSRegularExpression counts).
        var cells: [Int: LinkMatch.Cell] = [:]
        var offsets: [Int] = []
        var offset = 0
        for row in rows where grid.cells.indices.contains(row) {
            for (column, cell) in grid.cells[row].enumerated() {
                guard let cell else { continue } // the second half of a wide character
                cells[offset] = LinkMatch.Cell(row: row, column: column, width: max(CellWidth.of(cell), 1))
                offsets.append(offset)
                line.append(cell)
                offset += cell.utf16.count
            }
        }
        return ranges(in: line).compactMap { range in
            let characters = offsets.filter { $0 >= range.location && $0 < range.location + range.length }.compactMap { cells[$0] }
            guard !characters.isEmpty, cells[range.location] != nil else { return nil }
            return LinkMatch(text: (line as NSString).substring(with: range), characters: characters)
        }
    }

    public static func matches(in grid: TextGrid, row: Int) -> [LinkMatch] {
        matches(in: grid, rows: row ..< row + 1)
    }

    private static func ranges(in line: String) -> [NSRange] {
        // Every kind of link has a slash or a colon; most rows have neither.
        guard let expression, line.contains(where: { $0 == "/" || $0 == ":" }) else { return [] }
        return expression.matches(in: line, range: NSRange(location: 0, length: (line as NSString).length)).map(\.range)
    }
}
