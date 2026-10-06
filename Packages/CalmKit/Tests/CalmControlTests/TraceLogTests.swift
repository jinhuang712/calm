import CalmControl
import Foundation
import Testing

struct TraceLogTests {
    /// Records from the installed Calm's real trace (`log show --style ndjson`), trimmed to the
    /// fields `calm trace` reads, and the count `log` closes with. 2026-10-06.
    private func fixture() throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: "trace", withExtension: "ndjson", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    @Test func `each event is its time and the trace's own words, under a heading for the day and the process`() throws {
        var printer = TraceLog.Printer()
        let lines = try fixture().flatMap { printer.lines(for: $0) }

        #expect(lines.first == "— 2026-10-06, Calm, process 14094 —")
        #expect(lines.dropFirst().first == "22:37:30.270  +220.10 transcript f34c587a read: title, recap; working")
        #expect(lines.contains("22:38:13.364  +263.20 report 43e23209 from hook says working: done → working"))
        // Six events and one heading; the closing count prints nothing.
        #expect(lines.count == 7)
    }

    @Test func `a restart starts a new heading`() throws {
        var printer = TraceLog.Printer()
        let records = try fixture()
        let restarted = records[1].replacingOccurrences(of: "\"processID\": 14094", with: "\"processID\": 15210")

        _ = printer.lines(for: records[0])
        #expect(printer.lines(for: restarted).first == "— 2026-10-06, Calm, process 15210 —")
    }

    @Test func `what isn't an event prints nothing`() {
        var printer = TraceLog.Printer()
        #expect(printer.lines(for: #"{"count":205,"finished":1}"#).isEmpty)
        #expect(printer.lines(for: "Filtering the log data using …").isEmpty)
        #expect(printer.lines(for: "").isEmpty)
    }

    @Test func `the trace of the Calm the CLI came with, for a time or followed`() {
        let app = "/Applications/Calm.app/Contents/MacOS/Calm"
        let trace = #"subsystem == "com.jinhuang.calm" AND category == "trace""#
        #expect(TraceLog.arguments(last: "10m", session: nil, appExecutable: app, follow: false) == [
            "show", "--last", "10m", "--style", "ndjson", "--predicate",
            trace + #" AND processImagePath == "/Applications/Calm.app/Contents/MacOS/Calm""#,
        ])
        #expect(TraceLog.arguments(last: "5m", session: "43e23209", appExecutable: nil, follow: true) == [
            "stream", "--style", "ndjson", "--predicate",
            #"subsystem == "com.jinhuang.calm" AND category == "trace" AND eventMessage CONTAINS "43e23209""#,
        ])
    }

    @Test func `a quote in a path can't end the predicate early`() {
        let arguments = TraceLog.arguments(last: "5m", session: nil, appExecutable: #"/Apps/My "Calm".app/Calm"#, follow: false)
        #expect(arguments.last?.hasSuffix(#"processImagePath == "/Apps/My \"Calm\".app/Calm""#) == true)
    }

    @Test func `--last takes a whole number of seconds, minutes, hours or days`() {
        for good in ["30s", "5m", "2h", "1d", "90m"] {
            #expect(TraceLog.isDuration(good))
        }
        for bad in ["", "5", "m", "0m", "-5m", "5 m", "1.5h", "5w", "5m; rm"] {
            #expect(!TraceLog.isDuration(bad))
        }
    }

    @Test func `a session is named as the trace names it`() {
        #expect(TraceLog.shortID("43E23209-0E03-4B1C-9C8F-C856FE7FAAAA") == "43e23209")
        #expect(TraceLog.shortID("43e23209") == "43e23209")
        #expect(TraceLog.shortID("43e2") == nil)
        #expect(TraceLog.shortID("not-an-id") == nil)
        #expect(TraceLog.shortID("43e23209\" OR 1") == nil)
    }
}
