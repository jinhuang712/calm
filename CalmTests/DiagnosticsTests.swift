@testable import Calm
import CalmModel
import Foundation
import Testing

/// Dump Logs writes what can be attached to a bug report: states, ids and counts, nothing the
/// user or an agent wrote (Diagnostics.swift).
@MainActor
struct DiagnosticsTests {
    @Test func `a session line names the state and the agent but not the folder or the title`() {
        var session = Session(projectID: UUID(), workingDirectory: "/Users/me/secret-project", state: .working)
        session.title = "the launch plan"
        session.customName = "Acquisition notes"
        session.agent = AgentRun(kind: .claudeCode, processID: 42)
        let line = DiagnosticsReport.sessionLine(session, hasPane: true, splitOf: 2)
        #expect(line.hasPrefix(session.id.uuidString.lowercased().prefix(8)))
        #expect(line.contains("working"))
        #expect(line.contains("claudeCode"))
        #expect(line.contains("pane yes"))
        #expect(line.contains("in a split of 2"))
        for secret in ["secret-project", "/Users/me", "launch plan", "Acquisition"] {
            #expect(!line.contains(secret))
        }
    }

    @Test func `a scratch session is marked as one and a bare shell has no agent`() {
        var session = Session(projectID: UUID(), workingDirectory: "/tmp/scratch")
        session.scratchFolder = "/tmp/scratch"
        let line = DiagnosticsReport.sessionLine(session, hasPane: false, splitOf: 1)
        #expect(line.contains("scratch"))
        #expect(line.contains("agent none"))
        #expect(line.contains("pane no"))
    }

    @Test func `the file holds the facts, the sessions and the trace`() {
        let report = DiagnosticsReport(facts: ["Calm: Calm 1.0 (1)", "macOS: 26"], sessions: ["abcd1234  idle"])
        let text = report.text(trace: "  12.3 session abcd1234 idle\n", date: Date(timeIntervalSince1970: 0))
        #expect(text.hasPrefix("Calm diagnostics"))
        #expect(text.contains("  Calm: Calm 1.0 (1)"))
        #expect(text.contains("Sessions (1)"))
        #expect(text.contains("  abcd1234  idle"))
        #expect(text.contains("12.3 session abcd1234 idle"))
    }

    @Test func `an empty trace or no sessions say so instead of leaving a gap`() {
        let text = DiagnosticsReport(facts: [], sessions: []).text(trace: " \n")
        #expect(text.contains("  none"))
        #expect(text.contains("(nothing written in that time)"))
    }

    @Test func `the file is written in the folder under a name with the time`() throws {
        // A temporary folder: the real one is in the user's home.
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-diagnostics-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let url = try #require(Diagnostics.write("hello", date: date, in: folder))
        #expect(url.deletingLastPathComponent().path == folder.path)
        #expect(url.lastPathComponent.hasPrefix("calm-diagnostics-"))
        #expect(url.pathExtension == "txt")
        #expect(try String(contentsOf: url, encoding: .utf8) == "hello")
    }
}
