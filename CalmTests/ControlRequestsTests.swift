@testable import Calm
import CalmControl
import Testing

/// How the control server answers what the CLI sends, called directly: the unit-test host never
/// starts the server, and none of these requests reach a window or a shell.
@MainActor
struct ControlRequestsTests {
    private let server = ControlServer(socketPath: "/tmp/calm-crt-unused.sock")
    private let nobody = "00000000-0000-0000-0000-000000000000"

    @Test func `a request from a newer calm is refused with a note to update Calm`() {
        var request = ControlRequest(cmd: .list)
        request.v = ControlProtocol.version + 1

        #expect(server.handle(request) == .failure("This Calm is older than the calm command; update Calm."))
    }

    @Test func `a report for a session Calm doesn't know is refused`() {
        #expect(server.handle(ControlRequest(cmd: .status, session: nobody, state: "working")) == .failure("No such session."))
        #expect(server.handle(ControlRequest(cmd: .status, session: "not-an-id", state: "working")) == .failure("No such session."))
    }

    @Test func `a notice for a session Calm doesn't know is refused`() {
        #expect(server.handle(ControlRequest(cmd: .notify, session: nobody, message: "tests done")) == .failure("No such session."))
    }

    @Test func `open refuses no path, and a path that isn't there`() {
        #expect(server.handle(ControlRequest(cmd: .open)) == .failure("Give a folder or file to open."))
        #expect(server.handle(ControlRequest(cmd: .open, path: "/nonexistent/calm-test")) ==
            .failure("No such file or folder: /nonexistent/calm-test"))
    }

    @Test func `list answers with every session`() {
        let response = server.handle(ControlRequest(cmd: .list))

        #expect(response.ok)
        #expect(response.sessions?.count == SessionManager.shared.orderedSessions.count)
    }
}
