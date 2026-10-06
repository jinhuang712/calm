import CalmControl
import Foundation

/// `calm trace`: Calm's trace from the unified log, through `/usr/bin/log`, one line per event
/// (`TraceLog`). Works whether or not Calm is running.
enum TraceCommand {
    static func run(_ words: [String]) -> Never {
        var last = "5m"
        var session: String?
        var follow = false
        var iterator = words.makeIterator()
        while let word = iterator.next() {
            switch word {
            case "--last":
                guard let value = iterator.next(), TraceLog.isDuration(value) else {
                    fail("--last takes a time such as 30s, 10m, 2h or 1d", code: 64)
                }
                last = value
            case "--session":
                guard let value = iterator.next(), let id = TraceLog.shortID(value) else {
                    fail("--session takes a session id: its first 8 hex digits or more", code: 64)
                }
                session = id
            case "--follow", "-f":
                follow = true
            default:
                fail("unknown option '\(word)'", code: 64)
            }
        }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/log")
        process.arguments = TraceLog.arguments(last: last, session: session, appExecutable: appExecutable(), follow: follow)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        do {
            try process.run()
        } catch {
            fail("couldn't run /usr/bin/log: \(error.localizedDescription)")
        }

        // Line by line as `log` writes, so --follow shows each event when it happens.
        var printer = TraceLog.Printer()
        var pending = Data()
        var printed = 0
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            guard !chunk.isEmpty else { break }
            pending.append(chunk)
            while let newline = pending.firstIndex(of: 0x0A) {
                let record = String(bytes: pending[pending.startIndex ..< newline], encoding: .utf8)
                pending.removeSubrange(pending.startIndex ... newline)
                for line in record.map({ printer.lines(for: $0) }) ?? [] {
                    FileHandle.standardOutput.write(Data((line + "\n").utf8))
                    printed += 1
                }
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { exit(1) }
        if printed == 0, !follow {
            warn("nothing in Calm's trace in the last \(last)")
        }
        exit(0)
    }

    /// The executable of the Calm this CLI came with: the trace of that app only, every launch
    /// of it, without a Debug build's or a self-test's. Nil outside an app, which keeps every Calm's.
    private static func appExecutable() -> String? {
        let executable = Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0])
        guard let app = CalmLaunch.app(containing: executable) else { return nil }
        let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        let name = plist?["CFBundleExecutable"] as? String ?? "Calm"
        return realPath(app.appending(path: "Contents/MacOS/\(name)").path)
    }
}
