import Foundation

/// What `calm list` and `calm search` print: one record per line, fields separated by tabs, and
/// styling only on a terminal (CLI.md → Conventions).
public enum CLIOutput {
    /// Project, title, state, agent (`-` for none) and folder.
    public static func line(for session: ControlResponse.SessionInfo) -> String {
        [session.project, session.title, session.state, session.agent ?? "-", session.directory].joined(separator: "\t")
    }

    /// How long ago, in the largest whole unit: `30m`, `5h`, `3d`. A time ahead of this clock is `0m`.
    public static func age(seconds: Double) -> String {
        if seconds < 3600 {
            return "\(max(Int(seconds / 60), 0))m"
        }
        if seconds < 86400 {
            return "\(Int(seconds / 3600))h"
        }
        return "\(Int(seconds / 86400))d"
    }

    /// A search result: when, agent, project and title (dim, then bold), then the matching text on
    /// a line of its own, indented, with the matches (between U+0002 and U+0003) in bold.
    public static func lines(for hit: ControlResponse.SearchHit, now: Date, styled: Bool) -> [String] {
        let bold = styled ? "\u{1B}[1m" : ""
        let dim = styled ? "\u{1B}[2m" : ""
        let reset = styled ? "\u{1B}[0m" : ""
        let when = age(seconds: now.timeIntervalSince1970 - hit.lastActive)
        let project = hit.directory.map { ($0 as NSString).lastPathComponent } ?? "-"
        // The conversation's id last, for `calm show <id>`.
        let id = hit.conversation.map { "\t\(dim)\($0)\(reset)" } ?? ""
        var lines = ["\(dim)\(when)\t\(hit.agent)\t\(project)\(reset)\t\(bold)\(hit.title)\(reset)\(id)"]
        let snippet = hit.snippet
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\u{2}", with: bold)
            .replacingOccurrences(of: "\u{3}", with: reset)
        if !snippet.isEmpty {
            lines.append("    \(snippet)")
        }
        return lines
    }
}
