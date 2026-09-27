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
}
