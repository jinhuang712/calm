@testable import Calm
import CalmControl
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

    // MARK: A socket that stopped leading to the server

    /// What a Calm that died without cleaning up leaves: a socket file nothing listens on.
    private func leaveStaleSocket(at path: String) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        _ = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(fd)
    }

    @Test func `a server whose socket file was removed listens again`() {
        let path = socketPath()
        let server = ControlServer(socketPath: path)
        server.start()
        defer { server.stop() }
        unlink(path)
        #expect(!ControlClient.isListening(socketPath: path))

        server.listenAgainIfLost()

        #expect(ControlClient.isListening(socketPath: path))
    }

    @Test func `a server listens again when a dead Calm's socket file took its path`() {
        let path = socketPath()
        let server = ControlServer(socketPath: path)
        server.start()
        defer { server.stop() }
        // The incident: a second Calm replaced the file, then died and left it behind.
        unlink(path)
        leaveStaleSocket(at: path)
        #expect(!ControlClient.isListening(socketPath: path))

        server.listenAgainIfLost()

        #expect(ControlClient.isListening(socketPath: path))
    }

    @Test func `a server leaves a path a live Calm owns`() {
        let path = socketPath()
        let first = ControlServer(socketPath: path)
        first.start()
        defer { first.stop() }
        let second = ControlServer(socketPath: path)
        second.start()

        first.listenAgainIfLost()

        // Had the first taken the path back, the second would no longer own the file to remove.
        second.stop()
        #expect(!FileManager.default.fileExists(atPath: path))
    }

    @Test func `a caller that hangs up without a request leaves the server running`() async throws {
        let path = socketPath()
        let server = ControlServer(socketPath: path)
        server.start()
        defer { server.stop() }

        for _ in 0 ..< 3 {
            #expect(ControlClient.isListening(socketPath: path))
        }
        // The reply goes to a socket nobody reads; that must not end the process (SIGPIPE).
        try await Task.sleep(for: .milliseconds(200))

        #expect(ControlClient.isListening(socketPath: path))
    }
}
