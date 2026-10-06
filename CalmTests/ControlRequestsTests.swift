@testable import Calm
import CalmControl
import Foundation
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

    /// `calm doctor` asks which Calm answers; a session it doesn't know comes back as none.
    @Test func `info says which Calm answers`() throws {
        let response = server.handle(ControlRequest(cmd: .info, session: nobody))
        let info = try #require(response.info)

        #expect(response.ok)
        #expect(info.processID == ProcessInfo.processInfo.processIdentifier)
        #expect(info.bundlePath == Bundle.main.bundlePath)
        #expect(info.version == Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
        #expect(info.session == nil)
    }

    /// `calm config` asks for it after a change; the unit-test host only re-reads (agents' files
    /// are never written under XCTest).
    @Test func `reload re-reads the settings`() {
        #expect(server.handle(ControlRequest(cmd: .reload)) == .success())
    }

    @Test func `a fork of a session Calm doesn't know is refused`() {
        #expect(server.handle(ControlRequest(cmd: .fork, session: nobody, message: "try B")) == .failure("No such session."))
    }

    @Test func `list answers with every session`() {
        let response = server.handle(ControlRequest(cmd: .list))

        #expect(response.ok)
        #expect(response.sessions?.count == SessionManager.shared.orderedSessions.count)
    }
}
