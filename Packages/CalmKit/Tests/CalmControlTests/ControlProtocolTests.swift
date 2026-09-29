@testable import CalmControl
import Foundation
import Testing

struct ControlProtocolTests {
    @Test func `requests encode with a version`() throws {
        let request = ControlRequest(cmd: .open, path: "/dev/apps/calm")
        let json = try #require(String(data: JSONEncoder().encode(request), encoding: .utf8))
        #expect(json.contains(#""v":1"#))
        #expect(json.contains(#""cmd":"open""#))
        #expect(try JSONDecoder().decode(ControlRequest.self, from: Data(json.utf8)) == request)
    }

    @Test func `a hook's shell count travels, and a caller that omits it means none`() throws {
        let request = ControlRequest(cmd: .status, state: "done", shells: 2)
        let data = try JSONEncoder().encode(request)
        #expect(try JSONDecoder().decode(ControlRequest.self, from: data).shells == 2)
        let older = Data(#"{"v":1,"cmd":"status","state":"done"}"#.utf8)
        #expect(try JSONDecoder().decode(ControlRequest.self, from: older).shells == nil)
    }

    @Test func `responses round-trip`() throws {
        let response = ControlResponse.success(sessions: [
            .init(id: "1", title: "zsh", project: "calm", directory: "/dev/apps/calm", state: "idle"),
        ])
        let data = try JSONEncoder().encode(response)
        #expect(try JSONDecoder().decode(ControlResponse.self, from: data) == response)
    }

    @Test func `a missing socket reports that Calm isn't running`() {
        let path = FileManager.default.temporaryDirectory.appending(path: "no-such-calm.sock").path
        #expect(throws: ControlClient.ClientError.self) {
            _ = try ControlClient.send(ControlRequest(cmd: .list), socketPath: path)
        }
    }

    // MARK: isListening

    /// Short: a Unix socket path must fit in `sun_path` (104 bytes).
    private func socketPath() -> String {
        "/tmp/calm-cpt-\(UUID().uuidString.prefix(8)).sock"
    }

    /// Binds a socket file at `path`; listening or not, the file stays until the test unlinks it.
    private func bindSocket(at path: String, listening: Bool) -> Int32 {
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
        if listening {
            listen(fd, 4)
        }
        return fd
    }

    @Test func `no socket file means nobody is listening`() {
        #expect(!ControlClient.isListening(socketPath: socketPath()))
    }

    @Test func `a listening socket counts, and the file a dead Calm left behind does not`() {
        let path = socketPath()
        defer { unlink(path) }
        let fd = bindSocket(at: path, listening: true)
        #expect(ControlClient.isListening(socketPath: path))

        // The process is gone but its socket file stays: connecting is refused.
        close(fd)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(!ControlClient.isListening(socketPath: path))
    }
}
