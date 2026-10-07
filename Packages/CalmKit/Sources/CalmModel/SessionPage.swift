import Foundation

/// The session page (FEATURES.md → F16, UIUX.md → Find): everything a session showed, in order.
/// The shell's output, with each full-screen program's lines, as Calm kept them (`ScreenKeeper`),
/// where the program started in it; while a program runs, what's on its screen now comes last.
/// A time mark goes before each part a program showed.
public struct SessionPage: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let text: String
        /// When the part it starts was shown: the page draws a hairline and the time above it.
        public let mark: Date?

        public init(text: String, mark: Date? = nil) {
            self.text = text
            self.mark = mark
        }
    }

    public let lines: [Line]
    /// How many of the lines are on the program's screen now: the rest is what the screen no
    /// longer shows.
    public let screenCount: Int

    /// When the first part a program showed was shown.
    public var since: Date? {
        lines.lazy.compactMap(\.mark).first
    }

    /// The lines the screen no longer shows: "This session showed 1,240 more lines".
    public var moreCount: Int {
        lines.count - screenCount
    }

    /// The lines of the shell's screen, as `ghostty_surface_read_primary_text` reads it, without
    /// trailing spaces or the blank rows below the last line.
    public static func shellLines(_ text: String) -> [String] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { ScreenKeeper.trimmed(String($0)) }
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }
        return lines
    }

    /// The page from the shell's screen text and what `keeper` kept; `running` while a program
    /// shows its screen, which then goes last.
    public init(shell: String?, keeper: ScreenKeeper, running: Bool) {
        let shell = shell.map(Self.shellLines) ?? []
        let kept = keeper.lines
        var programs = keeper.programs
        if programs.isEmpty, !kept.isEmpty || running {
            // Kept with no start known: after all of the shell's output.
            programs = [ScreenKeeper.Program(firstLine: keeper.dropped, shellLines: shell.count)]
        }
        var lines: [Line] = []
        var shellAt = 0
        for (index, program) in programs.enumerated() {
            // The shell's lines up to where the program started (a count that went down, as the
            // scrollback let go of its top, takes none back).
            let cut = min(max(program.shellLines, shellAt), shell.count)
            lines += shell[shellAt ..< cut].map { Line(text: $0) }
            shellAt = cut
            let from = min(max(program.firstLine - keeper.dropped, 0), kept.count)
            let next = index + 1 < programs.count ? programs[index + 1].firstLine - keeper.dropped : kept.count
            let to = min(max(next, from), kept.count)
            lines += kept[from ..< to].map(Self.line)
        }
        // After the last program, the shell's output since it quit.
        lines += shell[shellAt...].map { Line(text: $0) }
        let screen = running ? keeper.screenLines.map(Self.line) : []
        self.lines = lines + screen
        screenCount = screen.count
    }

    private static func line(_ kept: ScreenKeeper.Line) -> Line {
        Line(text: kept.text, mark: kept.startsPart ? kept.shown : nil)
    }
}
