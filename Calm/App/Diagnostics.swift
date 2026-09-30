import AppKit
import CalmModel
import Foundation

/// Dump Logs (FEATURES.md → Command palette): a text file to attach to a bug report, written and
/// shown in Finder. What it holds is what Calm's own trace holds (Trace.swift): ids, states, agent
/// names, counts and settings. Never a folder, a title or a word the user or an agent wrote.
struct DiagnosticsReport {
    /// "Label: value" lines about the app and the machine.
    var facts: [String]
    /// One line per session (`sessionLine`).
    var sessions: [String]

    func text(trace: String, date: Date = Date()) -> String {
        var lines = ["Calm diagnostics", "Written \(date.formatted(.iso8601))", "", "App"]
        lines += facts.map { "  " + $0 }
        lines += ["", "Sessions (\(sessions.count)), ids as in the trace"]
        lines += sessions.isEmpty ? ["  none"] : sessions.map { "  " + $0 }
        let trimmed = trace.trimmingCharacters(in: .whitespacesAndNewlines)
        let events = trimmed.isEmpty ? "  (nothing written in that time)" : trimmed
        lines += ["", "Trace, the last \(Diagnostics.traceMinutes) minutes", events, ""]
        return lines.joined(separator: "\n")
    }

    /// A session as the trace names it: the first eight hex digits of its id, the state, the agent
    /// and who reported the state. Its folder and its title stay out.
    static func sessionLine(_ session: Session, hasPane: Bool, splitOf: Int) -> String {
        let id = session.id.uuidString.lowercased().prefix(8)
        let agent = session.agent?.kind.rawValue ?? "none"
        let source = session.lastReport.map { String($0.source.rawValue) } ?? "none"
        let kind = session.isScratch ? "scratch" : "folder"
        return "\(id)  \(session.state.rawValue)  agent \(agent)  reported by \(source)  \(kind)  "
            + "pane \(hasPane ? "yes" : "no")  in a split of \(splitOf)"
    }

    @MainActor
    static func current(manager: SessionManager) -> DiagnosticsReport {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let workspace = manager.workspace
        let settings = manager.settings
        let facts = [
            "Calm: \(BuildVariant.appName) \(version) (\(build))",
            "Engine: \(GhosttyRuntime.engineVersion)",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Groups: \(workspace.projects.count), sessions: \(workspace.sessions.count), layouts: \(workspace.layouts.count)",
            "Theme: \(settings.themeName ?? "default"), interface size: \(settings.interfaceSize.rawValue), "
                + "session cards: \(settings.sessionCardSize.rawValue), motion: \(settings.motion.rawValue)",
        ]
        let sessions = workspace.sessions.map { session in
            sessionLine(
                session, hasPane: manager.panes[session.id] != nil,
                splitOf: workspace.layout(containing: session.id)?.tree.leaves.count ?? 1,
            )
        }
        return DiagnosticsReport(facts: facts, sessions: sessions)
    }
}

enum Diagnostics {
    static let traceMinutes = 30

    /// `~/Library/Logs/Calm`, where macOS keeps an app's logs. A headless self-test writes in the
    /// temporary folder instead, so a test leaves nothing in the real home.
    static var folder: URL {
        if Headless.isOn {
            return FileManager.default.temporaryDirectory.appending(path: "calm-selftest-logs")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/Calm")
    }

    /// The trace from the unified log, as `/usr/bin/log show` prints it (what `calm trace` will),
    /// for this Calm only: another instance (a second Calm, a test) would fill it with lines that
    /// aren't about this one. Run off the main thread: a busy log takes a few seconds. Empty when
    /// `log` can't run.
    static func recentTrace(minutes: Int = traceMinutes) async -> String {
        let processID = ProcessInfo.processInfo.processIdentifier
        return await Task.detached {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/log")
            process.arguments = [
                "show", "--last", "\(minutes)m", "--style", "compact",
                "--predicate", "subsystem == \"com.jinhuang.calm\" AND category == \"trace\" AND processID == \(processID)",
            ]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            // Read before waiting: a full pipe would stop `log` and never let it exit.
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(bytes: data, encoding: .utf8) ?? ""
        }.value
    }

    /// Writes the report into `folder` under a name with the time in it. Nil when it can't.
    static func write(_ text: String, date: Date = Date(), in folder: URL = Diagnostics.folder) -> URL? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let url = folder.appending(path: "calm-diagnostics-\(formatter.string(from: date)).txt")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Opens Finder on the folder with the file selected. Headless self-tests log it instead.
    @MainActor
    static func show(_ file: URL) {
        if Headless.isOn {
            FileHandle.standardError.write(Data("calm-selftest: would show \(file.path) in Finder\n".utf8))
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }
}
