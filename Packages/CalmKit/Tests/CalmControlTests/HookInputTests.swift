import CalmControl
import Foundation
import Testing

struct HookInputTests {
    private func makePipe() -> (reader: Int32, writer: Int32) {
        var ends: [Int32] = [0, 0]
        _ = pipe(&ends)
        return (ends[0], ends[1])
    }

    private func send(_ data: Data, to writer: Int32) {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = write(writer, buffer.baseAddress! + offset, buffer.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }

    @Test func `the whole payload, up to the end of the input`() {
        let (reader, writer) = makePipe()
        defer { close(reader) }
        let payload = Data(#"{"hook_event_name":"Stop","session_id":"abc"}"#.utf8)
        send(payload, to: writer)
        close(writer)

        #expect(HookInput.read(from: reader) == payload)
    }

    @Test func `an input that ends at once is an empty payload`() {
        let (reader, writer) = makePipe()
        defer { close(reader) }
        close(writer)

        #expect(HookInput.read(from: reader) == Data())
    }

    @Test func `an input left open gives up at the deadline instead of holding the agent`() {
        let (reader, writer) = makePipe()
        defer {
            close(reader)
            close(writer)
        }
        send(Data(#"{"hook_event_name":"#.utf8), to: writer)

        let start = ProcessInfo.processInfo.systemUptime
        #expect(HookInput.read(from: reader, timeLimit: 0.2) == nil)
        let waited = ProcessInfo.processInfo.systemUptime - start
        #expect(waited >= 0.2)
        #expect(waited < 1)
    }

    @Test func `a payload past the size limit is none`() {
        let (reader, writer) = makePipe()
        defer { close(reader) }
        send(Data(repeating: 0x41, count: 2000), to: writer)
        close(writer)

        #expect(HookInput.read(from: reader, sizeLimit: 1000) == nil)
    }

    /// Bigger than a pipe's buffer, written in pieces by another thread while the read runs, the
    /// way a hook runner writes a long payload.
    ///
    /// The writer is a thread of its own, not a task on GCD's global queue, and the read gets a
    /// long limit: this test is about reading the payload whole, and the 1-second deadline has
    /// its own test above. On a CI runner with a few cores, running the whole suite at once, this
    /// failed (the read gave up: nil) in both runs that had it, and never in 20 full-suite runs on
    /// a Mac, idle or with 36 busy loops. A writer waiting on a pool whose workers are all held by
    /// other tests fits that, but it wasn't proven.
    @Test func `a payload that arrives in pieces is read whole`() {
        let (reader, writer) = makePipe()
        defer { close(reader) }
        let payload = Data((0 ..< 1_000_000).map { UInt8(truncatingIfNeeded: $0) })
        let pieces = stride(from: 0, to: payload.count, by: 100_000).map { payload[$0 ..< min($0 + 100_000, payload.count)] }
        Thread.detachNewThread {
            for piece in pieces {
                piece.withUnsafeBytes { buffer in
                    var offset = 0
                    while offset < buffer.count {
                        let written = write(writer, buffer.baseAddress! + offset, buffer.count - offset)
                        guard written > 0 else { return }
                        offset += written
                    }
                }
                usleep(5000)
            }
            close(writer)
        }

        // How long the read took says which way it gave up, if it did: at the limit (the writer
        // stalled) or at once (an error, such as another test closing this test's descriptor).
        let start = ProcessInfo.processInfo.systemUptime
        let read = HookInput.read(from: reader, timeLimit: 30)
        let waited = ProcessInfo.processInfo.systemUptime - start
        #expect(read == payload, "read for \(String(format: "%.2f", waited)) s")
    }
}
