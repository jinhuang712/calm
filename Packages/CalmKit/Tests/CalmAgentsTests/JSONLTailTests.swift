@testable import CalmAgents
import Foundation
import Testing

struct JSONLTailTests {
    /// Writes `lines` to a temporary file; `finished: false` leaves the last one without its newline.
    private func file(_ lines: [String], finished: Bool = true) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-tail-\(UUID().uuidString).jsonl")
        var text = lines.joined(separator: "\n")
        if finished, !lines.isEmpty {
            text += "\n"
        }
        try Data(text.utf8).write(to: url)
        return url
    }

    private func record(_ number: Int, padding: Int = 0) -> String {
        #"{"n":\#(number),"pad":"\#(String(repeating: "x", count: padding))"}"#
    }

    private func numbers(_ url: URL, _ tail: (URL) -> JSONLTail = { JSONLTail($0) }) -> [Int] {
        tail(url).compactMap { $0["n"] as? Int }
    }

    @Test func `records come newest first`() throws {
        let url = try file((1 ... 5).map { record($0) })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [5, 4, 3, 2, 1])
    }

    @Test func `a line still being written is left out`() throws {
        let url = try file([record(1), record(2), #"{"n":3,"pad":"half"#], finished: false)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [2, 1])
    }

    @Test func `records longer than a block are read whole`() throws {
        // 150 KB each: they span several 64 KB blocks, and together stay within the limit.
        let url = try file((1 ... 3).map { record($0, padding: 150_000) })
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [3, 2, 1])
    }

    @Test func `a huge newest line doesn't hide the records before it`() throws {
        // A tool's output of 3 MB between two messages, and another as the very last line.
        let url = try file([record(1), record(2), record(3, padding: 3_000_000), record(4), record(5, padding: 3_000_000)])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [4, 2, 1])
    }

    @Test func `an unfinished huge line is skipped too`() throws {
        let url = try file([record(1), record(2), record(3, padding: 3_000_000)], finished: false)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [2, 1])
    }

    @Test func `skipping stops after the skip limit`() throws {
        let url = try file([record(1), record(2, padding: 3_000_000), record(3, padding: 3_000_000)])
        defer { try? FileManager.default.removeItem(at: url) }
        let found = numbers(url) { url in
            var tail = JSONLTail(url)
            tail.skipLimit = 4_000_000
            return tail
        }
        #expect(found.isEmpty) // never got past the second huge line
    }

    @Test func `the limit bounds how much is handed out`() throws {
        let url = try file((1 ... 100).map { record($0, padding: 1000) })
        defer { try? FileManager.default.removeItem(at: url) }
        let found = numbers(url) { url in
            var tail = JSONLTail(url)
            tail.limit = 10 * 1000
            return tail
        }
        #expect(found.first == 100)
        #expect(found.count > 5 && found.count < 20)
    }

    @Test func `lines that aren't JSON objects are passed over`() throws {
        let url = try file([record(1), "not json", "[1,2]", record(2), ""])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(numbers(url) == [2, 1])
    }

    @Test func `missing and empty files give nothing`() throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "no-such-\(UUID().uuidString).jsonl")
        #expect(numbers(missing).isEmpty)
        let empty = try file([])
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(numbers(empty).isEmpty)
    }
}
