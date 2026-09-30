@testable import CalmAgents
import Foundation
import Testing

/// JSONLTail's block scan was rewritten for speed (2026-09-30); these hold it to what the old one
/// handed out, record for record, on files made to hit its edges: lines longer than a block and
/// than `maxLine`, lines ending exactly at block edges, empty lines, lines that don't parse, a last
/// line without its newline, and the byte limits.
struct JSONLTailEquivalenceTests {
    struct Limits: Sendable, CustomStringConvertible {
        let limit: Int
        let maxLine: Int
        let skipLimit: Int

        var description: String {
            "limit \(limit), maxLine \(maxLine), skipLimit \(skipLimit)"
        }
    }

    /// The scan as it was before, kept to compare with.
    private struct OldTail: Sequence {
        let url: URL
        var limit: Int
        var maxLine: Int
        var skipLimit: Int

        func makeIterator() -> Iterator {
            Iterator(self)
        }

        final class Iterator: IteratorProtocol {
            private static let blockSize: UInt64 = 64 * 1024
            private let handle: FileHandle?
            private let limit: Int
            private let maxLine: Int
            private let skipLimit: Int
            private var position: UInt64
            private var carry = Data()
            private var skipping: Bool
            private var lines: [Data] = []
            private var handedOut = 0
            private var skipped = 0

            init(_ tail: OldTail) {
                limit = tail.limit
                maxLine = tail.maxLine
                skipLimit = tail.skipLimit
                handle = try? FileHandle(forReadingFrom: tail.url)
                let size = (try? handle?.seekToEnd()) ?? 0
                position = size
                skipping = false
                if size > 0, let handle, (try? handle.seek(toOffset: size - 1)) != nil,
                   let last = (try? handle.read(upToCount: 1))?.first {
                    skipping = last != 0x0A
                }
            }

            deinit {
                try? handle?.close()
            }

            func next() -> [String: Any]? {
                while true {
                    guard handedOut <= limit else { return nil }
                    if let line = lines.popLast() {
                        guard line.count <= maxLine else {
                            skipped += line.count
                            continue
                        }
                        handedOut += line.count
                        if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
                            return object
                        }
                        continue
                    }
                    guard fill() else { return nil }
                }
            }

            private func fill() -> Bool {
                guard let handle, position > 0, skipped <= skipLimit else { return false }
                let size = Swift.min(Self.blockSize, position)
                position -= size
                guard (try? handle.seek(toOffset: position)) != nil,
                      let chunk = try? handle.read(upToCount: Int(size)), !chunk.isEmpty
                else { return false }
                var data: Data
                if skipping {
                    guard let newline = chunk.lastIndex(of: 0x0A) else {
                        skipped += chunk.count
                        return true
                    }
                    skipped += chunk.endIndex - newline - 1
                    skipping = false
                    data = chunk[chunk.startIndex ..< newline]
                } else {
                    data = chunk + carry
                }
                var segments = data.split(separator: 0x0A, omittingEmptySubsequences: false)
                if position > 0, !segments.isEmpty {
                    let first = segments.removeFirst()
                    if first.count > maxLine {
                        skipped += first.count
                        skipping = true
                        carry = Data()
                    } else {
                        carry = Data(first)
                    }
                } else {
                    carry = Data()
                }
                lines.append(contentsOf: segments.filter { !$0.isEmpty })
                return true
            }
        }
    }

    /// A deterministic generator, so a failure repeats.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func record(_ number: Int, length: Int) -> String {
        let pad = max(0, length - 20)
        return #"{"n":\#(number),"p":"\#(String(repeating: "x", count: pad))"}"#
    }

    /// A file of `count` lines whose lengths mix short records, block-sized ones and megabytes.
    private func file(seed: UInt64, count: Int, finished: Bool) throws -> URL {
        var random = Generator(state: seed)
        var text = ""
        for number in 0 ..< count {
            switch Int.random(in: 0 ..< 20, using: &random) {
            case 0: text += "" // an empty line
            case 1: text += "not json"
            case 2: text += record(number, length: Int.random(in: 60000 ... 70000, using: &random)) // about a block
            case 3: text += record(number, length: Int.random(in: 200_000 ... 900_000, using: &random)) // a screenshot
            case 4: text += record(number, length: 64 * 1024 - 1) // ends at a block edge, with its newline
            default: text += record(number, length: Int.random(in: 20 ... 3000, using: &random))
            }
            if number < count - 1 || finished {
                text += "\n"
            }
        }
        // Its own name: the argument cases run at once and would overwrite each other's files.
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-tail-eq-\(seed)-\(UUID().uuidString).jsonl")
        try Data(text.utf8).write(to: url)
        return url
    }

    @Test(arguments: [
        Limits(limit: 512 * 1024, maxLine: 512 * 1024, skipLimit: 32 * 1024 * 1024),
        Limits(limit: 100_000, maxLine: 64 * 1024, skipLimit: 1_000_000),
        Limits(limit: 2_000_000, maxLine: 1000, skipLimit: 300_000),
        Limits(limit: 10_000_000, maxLine: 1_000_000, skipLimit: 0),
    ])
    func `hands out what the old scan did`(limits: Limits) throws {
        for seed in UInt64(1) ... 12 {
            let url = try file(seed: seed, count: 60 + Int(seed) * 7, finished: seed % 3 != 0)
            defer { try? FileManager.default.removeItem(at: url) }
            var new = JSONLTail(url)
            new.limit = limits.limit
            new.maxLine = limits.maxLine
            new.skipLimit = limits.skipLimit
            let old = OldTail(url: url, limit: limits.limit, maxLine: limits.maxLine, skipLimit: limits.skipLimit)
            let got = new.map { $0["n"] as? Int ?? -1 }
            let want = old.map { $0["n"] as? Int ?? -1 }
            #expect(got == want, "seed \(seed), limits \(limits): \(got.count) records against \(want.count)")
        }
    }
}
