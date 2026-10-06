import Foundation

/// What `calm trace` runs and prints: Calm's trace (DESIGNS.md → Trace) from the unified log,
/// through `/usr/bin/log`, one line per event (CLI.md → `calm trace`).
public enum TraceLog {
    /// `--last`: a whole number of seconds, minutes, hours or days, as `log show` takes it.
    public static func isDuration(_ text: String) -> Bool {
        text.wholeMatch(of: /[1-9][0-9]{0,5}[smhd]/) != nil
    }

    /// The trace's name for a session: the first eight hex digits of its id, lowercased. Takes
    /// a full id or the short one; nil for anything else.
    public static func shortID(_ text: String) -> String? {
        let hex = text.lowercased().filter { $0 != "-" }
        guard hex.count >= 8, hex.allSatisfy(\.isHexDigit) else { return nil }
        return String(hex.prefix(8))
    }

    /// The arguments for `/usr/bin/log`. `appExecutable` keeps the lines of the Calm the CLI came
    /// with: every launch of it, so both sides of a restart and any second copy, but not a Debug
    /// build's or a self-test's, which run from a build folder. Nil keeps every Calm's.
    public static func arguments(last: String, session: String?, appExecutable: String?, follow: Bool) -> [String] {
        var predicate = #"subsystem == "com.jinhuang.calm" AND category == "trace""#
        if let appExecutable {
            predicate += " AND processImagePath == \"\(quoted(appExecutable))\""
        }
        if let session {
            predicate += " AND eventMessage CONTAINS \"\(quoted(session))\""
        }
        return follow
            ? ["stream", "--style", "ndjson", "--predicate", predicate]
            : ["show", "--last", last, "--style", "ndjson", "--predicate", predicate]
    }

    private static func quoted(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Turns `log`'s records into lines: the time and the trace's own text, with a heading
    /// whenever the day or the Calm process changes (a restart starts a new one).
    public struct Printer {
        private var heading: String?

        public init() {}

        /// The lines for one ndjson record; none for what isn't an event (the closing count).
        public mutating func lines(for record: String) -> [String] {
            guard let data = record.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let message = object["eventMessage"] as? String,
                  let timestamp = object["timestamp"] as? String
            else { return [] }
            // "2026-10-06 22:46:44.275069+0800": the day, then the time to the millisecond.
            let parts = timestamp.split(separator: " ")
            let day = parts.first.map(String.init) ?? ""
            let time = parts.count > 1 ? String(parts[1].prefix(12)) : timestamp
            var lines: [String] = []
            let process = (object["processID"] as? Int).map { "Calm, process \($0)" } ?? "Calm"
            let next = "\(day), \(process)"
            if next != heading {
                heading = next
                lines.append("— \(next) —")
            }
            lines.append("\(time)  \(message)")
            return lines
        }
    }
}
