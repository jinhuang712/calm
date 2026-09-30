import CalmModel
import Foundation

/// Agents whose transcripts Calm can read for session cards (DESIGNS.md → Agents). Formats are
/// undocumented and change: anything unexpected reads as "nothing known", never an error.
public protocol TranscriptReading: AgentAdapter {
    /// The transcript of the agent running as `processID`, found without hooks. Declines
    /// (nil) rather than guess between two conversations: a card that shows another
    /// conversation's recap is worse than one that shows none.
    func transcript(forProcess processID: Int32, home: URL) -> (agentSessionID: String, url: URL)?
    /// Reads what the transcript says now. `agentSessionID` finds the agent's side files (todos).
    func readTail(of transcript: URL, agentSessionID: String?, home: URL) -> TranscriptTail?
    /// Files whose size or modification time changing means the transcript changed. A database
    /// in write-ahead mode grows its `-wal` file while the database file itself stays put.
    func changeMarkers(of transcript: URL) -> [URL]
}

public extension TranscriptReading {
    func changeMarkers(of transcript: URL) -> [URL] {
        [transcript]
    }
}

public extension Agents {
    static func transcriptReader(for kind: AgentKind) -> (any TranscriptReading)? {
        adapter(for: kind) as? any TranscriptReading
    }
}

/// Reads a JSONL file from its end, newest record first, one block at a time, so a reader that
/// needs only the last few records neither reads nor parses the rest.
///
/// Two limits keep it cheap. `limit` bounds the bytes of records handed out: it is what a
/// reader that never finds what it wants pays. A line longer than `maxLine` is a tool's output,
/// not a message (Codex's and pi's reach megabytes): it is passed over unparsed, up to
/// `skipLimit` bytes in all, so a huge newest record doesn't hide the messages before it.
/// A last line still being written (no newline yet) is left out.
struct JSONLTail: Sequence {
    let url: URL
    var limit = 512 * 1024
    var maxLine = 512 * 1024
    var skipLimit = 32 * 1024 * 1024

    init(_ url: URL) {
        self.url = url
    }

    func makeIterator() -> Iterator {
        Iterator(self)
    }

    final class Iterator: IteratorProtocol {
        private static let blockSize: UInt64 = 64 * 1024

        private let handle: FileHandle?
        private let limit: Int
        private let maxLine: Int
        private let skipLimit: Int
        /// Where the bytes not yet read end.
        private var position: UInt64
        /// The end of a line whose start is still unread, in file order: a line longer than a
        /// block arrives a block at a time, and its pieces are joined once, when its start is read.
        private var carry: [Data] = []
        /// Passing over a line that is too long (or unfinished): drop bytes until its newline.
        private var skipping: Bool
        /// Complete lines read but not handed out, oldest first.
        private var lines: [Data] = []
        private var handedOut = 0
        private var skipped = 0

        init(_ tail: JSONLTail) {
            limit = tail.limit
            maxLine = tail.maxLine
            skipLimit = tail.skipLimit
            handle = try? FileHandle(forReadingFrom: tail.url)
            let size = (try? handle?.seekToEnd()) ?? 0
            position = size
            skipping = false
            if size > 0, let last = Self.byte(at: size - 1, in: handle) {
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

        private static func byte(at offset: UInt64, in handle: FileHandle?) -> UInt8? {
            guard let handle, (try? handle.seek(toOffset: offset)) != nil else { return nil }
            return (try? handle.read(upToCount: 1))?.first
        }

        /// Reads the block before what was read last and queues the lines it completes.
        ///
        /// Only this block can hold newlines (what is carried is the rest of one line), so only
        /// it is searched, with `memchr`. Joining each block to the carried bytes and splitting
        /// the lot again made a long line quadratic, and Data's own searches go a byte at a time:
        /// a transcript with a few pasted screenshots near its end (lines of 0.5–0.7 MB, 2.9 MB
        /// of them) took 44 ms a read, read again every time the agent wrote (2026-09-30).
        private func fill() -> Bool {
            guard let handle, position > 0, skipped <= skipLimit else { return false }
            let size = Swift.min(Self.blockSize, position)
            position -= size
            guard (try? handle.seek(toOffset: position)) != nil,
                  let chunk = try? handle.read(upToCount: Int(size)), !chunk.isEmpty
            else { return false }

            var newlines = Self.newlines(in: chunk)
            var end = chunk.endIndex
            if skipping {
                // Everything after this block's last newline belongs to the line being dropped.
                guard let last = newlines.popLast() else {
                    skipped += chunk.count
                    return true
                }
                skipped += chunk.endIndex - last - 1
                skipping = false
                end = last
            }
            // The pieces between newlines, oldest first; the last one runs on into the carry.
            let starts = [chunk.startIndex] + newlines.map { $0 + 1 }
            let ends = newlines + [end]
            let pieces = zip(starts, ends).map { chunk[$0 ..< $1] }
            let carried = carry
            carry = []
            var completed: [Data] = []
            let first: [Data]
            if pieces.count == 1 {
                first = [pieces[0]] + carried
            } else {
                first = [pieces[0]]
                completed.append(contentsOf: pieces[1 ..< pieces.count - 1])
                completed.append(Self.joined([pieces[pieces.count - 1]] + carried))
            }
            if position > 0 {
                // The first piece is the end of a line that starts in an earlier block.
                let length = first.reduce(0) { $0 + $1.count }
                if length > maxLine {
                    skipped += length
                    skipping = true
                } else {
                    carry = first
                }
            } else {
                completed.insert(Self.joined(first), at: 0)
            }
            lines.append(contentsOf: completed.filter { !$0.isEmpty })
            return true
        }

        /// Where the newlines are in `data`, as its indices, in order.
        private static func newlines(in data: Data) -> [Int] {
            data.withUnsafeBytes { raw -> [Int] in
                guard let base = raw.baseAddress else { return [] }
                var found: [Int] = []
                var offset = 0
                while offset < raw.count, let hit = memchr(base + offset, 0x0A, raw.count - offset) {
                    let index = base.distance(to: UnsafeRawPointer(hit))
                    found.append(data.startIndex + index)
                    offset = index + 1
                }
                return found
            }
        }

        private static func joined(_ pieces: [Data]) -> Data {
            if pieces.count == 1 {
                return pieces[0]
            }
            var line = Data(capacity: pieces.reduce(0) { $0 + $1.count })
            for piece in pieces {
                line.append(piece)
            }
            return line
        }
    }
}
