@testable import Calm
import Foundation
import Testing

@MainActor
struct ControlServerTests {
    /// Short: a Unix socket path must fit in `sun_path` (104 bytes).
    private func socketPath() -> String {
        "/tmp/calm-cst-\(UUID().uuidString.prefix(8)).sock"
    }

    @Test func `a server that never started leaves the socket alone`() {
        let path = socketPath()
        FileManager.default.createFile(atPath: path, contents: Data())
        defer { unlink(path) }

        // The unit-test host quits through `stop()` without ever starting.
        ControlServer(socketPath: path).stop()

        #expect(FileManager.default.fileExists(atPath: path))
    }

    @Test func `stopping removes the socket it made`() {
        let path = socketPath()
        let server = ControlServer(socketPath: path)
        server.start()
        #expect(FileManager.default.fileExists(atPath: path))

        server.stop()

        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func `stopping keeps a socket another Calm has since bound`() {
        let path = socketPath()
        let first = ControlServer(socketPath: path)
        first.start()
        let second = ControlServer(socketPath: path)
        second.start()
        defer { second.stop() }

        first.stop()

        #expect(FileManager.default.fileExists(atPath: path))
    }
}
