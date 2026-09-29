@testable import CalmAgents
import CalmModel
import Foundation
import Testing

struct PiTranscriptTests {
    private let pi = PiAdapter()
    private let piID = "01a0ebb4-ae71-752e-869e-db3c981da03c"
    private let piRecap = "Added a retry with backoff to the fetcher. It retries three times."

    private func fixtureText(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "jsonl", subdirectory: "Fixtures/pi"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func write(_ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-pi-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return url
    }

    private func tail(_ text: String) throws -> TranscriptTail {
        let url = try write(text)
        defer { try? FileManager.default.removeItem(at: url) }
        return try #require(pi.readTail(of: url, agentSessionID: nil, home: url))
    }

    /// A `message` record to append after the fixtures' last one.
    private func message(_ message: [String: Any]) -> String {
        let record: [String: Any] = [
            "type": "message", "id": "a9", "parentId": "a5", "timestamp": "2026-09-29T05:49:00.000Z", "message": message,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])) ?? Data()
        return (String(bytes: data, encoding: .utf8) ?? "") + "\n"
    }

    @Test func `a finished turn's message is the recap and the session's name the title`() throws {
        let tail = try tail(fixtureText("session-done"))
        #expect(tail.lastMessage == piRecap)
        #expect(tail.title == "Retry in fetcher")
        #expect(tail.interrupted == false)
        // pi keeps no todo list.
        #expect(tail.step == nil)
        #expect(tail.progress == nil)
    }

    @Test func `an aborted turn is an interruption, and the recap is the last words before it`() throws {
        let tail = try tail(fixtureText("session-aborted"))
        #expect(tail.interrupted)
        #expect(tail.lastMessage == "Starting with the tokenizer.")
    }

    @Test func `a new prompt after an abort clears it`() throws {
        let prompt = message(["role": "user", "content": [["type": "text", "text": "Try again"]], "timestamp": 1_790_660_940_000])
        let tail = try tail(fixtureText("session-aborted") + prompt)
        #expect(tail.interrupted == false)
    }

    @Test func `tool results between an abort and the end don't hide it`() throws {
        let result = message([
            "role": "toolResult", "toolCallId": "call1", "toolName": "bash", "content": [], "isError": true,
            "timestamp": 1_790_660_906_000,
        ])
        let tail = try tail(fixtureText("session-aborted") + result)
        #expect(tail.interrupted)
    }

    @Test func `a huge tool result as the newest record doesn't hide the messages before it`() throws {
        let output = String(repeating: "x", count: 3_000_000)
        let big = message([
            "role": "toolResult", "toolCallId": "call2", "toolName": "read", "isError": false,
            "content": [["type": "text", "text": output]], "timestamp": 1_790_660_920_000,
        ])
        let tail = try tail(fixtureText("session-done") + big)
        #expect(tail.lastMessage == piRecap)
    }

    @Test func `missing or broken files read as nothing`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).jsonl")
        #expect(pi.readTail(of: missing, agentSessionID: nil, home: missing) == nil)
        let broken = try write("not json\n{also not")
        defer { try? FileManager.default.removeItem(at: broken) }
        #expect(pi.readTail(of: broken, agentSessionID: nil, home: broken) == nil)
    }

    // MARK: Finding the transcript

    @Test func `the header gives the id and folder`() throws {
        let url = try write(fixtureText("session-done"))
        defer { try? FileManager.default.removeItem(at: url) }
        let head = try #require(PiTranscript.head(of: url))
        #expect(head.id == piID)
        #expect(head.directory == "/Users/me/src/app")
    }

    /// A temporary home with pi sessions: `(file name, text)` in one project folder.
    private func makeHome(_ sessions: [(name: String, text: String)]) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appending(path: "calm-pi-home-\(UUID().uuidString)")
        let folder = home.appending(path: ".pi/agent/sessions/--Users-me-src-app--")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for session in sessions {
            try Data(session.text.utf8).write(to: folder.appending(path: session.name))
        }
        return home
    }

    private var facts: ProcessFacts {
        ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(-60))
    }

    @Test func `the only session for the folder since it started is found`() throws {
        let home = try makeHome([("a_\(piID).jsonl", fixtureText("session-done"))])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(PiAdapter.transcript(facts: facts, home: home)?.agentSessionID == piID)
    }

    @Test func `two sessions for the folder are ambiguous, so none is chosen`() throws {
        let text = try fixtureText("session-done")
        let other = text.replacingOccurrences(of: piID, with: "01a0ebb4-0000-7000-8000-000000000002")
        let home = try makeHome([("a_\(piID).jsonl", text), ("b_other.jsonl", other)])
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(PiAdapter.transcript(facts: facts, home: home) == nil)
    }

    @Test func `another folder, or a session older than the process, is not chosen`() throws {
        let home = try makeHome([("a_\(piID).jsonl", fixtureText("session-done"))])
        defer { try? FileManager.default.removeItem(at: home) }
        let elsewhere = ProcessFacts(directory: "/Users/me/src/other", started: Date().addingTimeInterval(-60))
        #expect(PiAdapter.transcript(facts: elsewhere, home: home) == nil)
        let later = ProcessFacts(directory: "/Users/me/src/app", started: Date().addingTimeInterval(3600))
        #expect(PiAdapter.transcript(facts: later, home: home) == nil)
    }

    /// Opt-in survey of every real pi session (CALM_REAL_PI_SESSIONS=<folder>): counts only.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CALM_REAL_PI_SESSIONS"] != nil))
    func `reads every real pi session`() throws {
        let folder = try #require(ProcessInfo.processInfo.environment["CALM_REAL_PI_SESSIONS"])
        let files = TranscriptDiscovery.files(inFoldersOf: URL(filePath: folder), extension: "jsonl", since: nil)
        var headers = 0, recaps = 0, interrupted = 0, titles = 0, unreadable = 0
        var slowest = Duration.zero
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for url in files {
                headers += PiTranscript.head(of: url) != nil ? 1 : 0
                var tail: TranscriptTail?
                slowest = max(slowest, clock.measure { tail = pi.readTail(of: url, agentSessionID: nil, home: url) })
                guard let tail else {
                    unreadable += 1
                    continue
                }
                recaps += tail.lastMessage != nil ? 1 : 0
                interrupted += tail.interrupted ? 1 : 0
                titles += tail.title != nil ? 1 : 0
            }
        }
        print("real pi sessions: \(files.count) files, \(headers) headers, \(recaps) with a recap, \(titles) titled")
        print("real pi sessions: \(interrupted) interrupted, \(unreadable) unreadable, \(elapsed) in all, slowest \(slowest)")
        #expect(headers == files.count)
        #expect(unreadable == 0)
    }
}
