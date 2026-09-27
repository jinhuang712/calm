import CalmControl
import CalmModel
import Foundation

/// Serves the local control socket used by the `calm` CLI and agent hooks.
/// One request per connection: read a JSON line, answer on the main actor, reply, close.
@MainActor
final class ControlServer {
    static let shared = ControlServer()

    private var listenFD: Int32 = -1
    private var source: DispatchSourceRead?
    private let queue = DispatchQueue(label: "calm.control")
    private(set) var socketPath = ControlProtocol.defaultSocketPath

    func start() {
        guard listenFD < 0 else { return }
        let path = socketPath
        try? FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
        )
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        guard path.utf8.count < MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: path.utf8)
            buffer[path.utf8.count] = 0
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            FileHandle.standardError.write(Data("calm: could not listen on \(path)\n".utf8))
            return
        }
        chmod(path, 0o600) // only this user may talk to Calm
        listenFD = fd

        source = Self.makeAcceptSource(fd: fd, queue: queue)
    }

    /// Built outside the main actor: its handler runs on the control queue, and a closure
    /// written inside a `@MainActor` method would inherit main-actor isolation and trap there.
    private nonisolated static func makeAcceptSource(fd: Int32, queue: DispatchQueue) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            let client = accept(fd, nil, nil)
            guard client >= 0 else { return }
            serve(client)
        }
        source.resume()
        return source
    }

    func stop() {
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            close(listenFD)
        }
        listenFD = -1
        unlink(socketPath)
    }

    /// Runs on the control queue: read one line, handle it on main, write the reply.
    private nonisolated static func serve(_ client: Int32) {
        defer { close(client) }
        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !received.contains(0x0A), received.count < 1_000_000 {
            let count = read(client, &buffer, buffer.count)
            if count <= 0 {
                break
            }
            received.append(contentsOf: buffer[0 ..< count])
        }
        let line = received.split(separator: 0x0A, maxSplits: 1).first ?? Data()

        let response: ControlResponse = if let request = try? JSONDecoder().decode(ControlRequest.self, from: line) {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated { ControlServer.shared.handle(request) }
            }
        } else {
            .failure("Couldn't read the request.")
        }
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)
        _ = data.withUnsafeBytes { write(client, $0.baseAddress, $0.count) }
    }

    // MARK: Commands

    func handle(_ request: ControlRequest) -> ControlResponse {
        guard request.v <= ControlProtocol.version else { return .failure("This Calm is older than the calm command; update Calm.") }
        let manager = SessionManager.shared
        switch request.cmd {
        case .list:
            let sessions = manager.orderedSessions.map { session in
                ControlResponse.SessionInfo(
                    id: session.id.uuidString,
                    title: session.displayTitle,
                    project: manager.workspace.project(session.projectID)?.name ?? "",
                    directory: session.workingDirectory,
                    state: session.state.reportName,
                    agent: session.agent?.kind.displayName,
                )
            }
            return .success(sessions: sessions)
        case .open:
            return open(request.path)
        case .status:
            guard let id = session(request.session) else { return .failure("No such session.") }
            guard let state = request.state.flatMap(SessionState.init(reportName:)) else {
                return .failure("Unknown state '\(request.state ?? "")'; use working, needs-you, done, failed or idle.")
            }
            if let kind = request.agent.flatMap(AgentKind.init(rawValue:)) {
                manager.noteAgentSession(id, kind: kind, agentSessionID: request.agentSession, transcriptPath: request.transcript)
            }
            manager.report(id, StatusReport(state: state, message: request.message, source: .hook))
            return .success()
        case .notify:
            guard let id = session(request.session) else { return .failure("No such session.") }
            guard let message = request.message, !message.isEmpty else { return .failure("Give a message.") }
            AttentionCenter.shared.notify(message, for: id)
            return .success()
        }
    }

    private func session(_ value: String?) -> Session.ID? {
        guard let id = value.flatMap(UUID.init(uuidString:)), SessionManager.shared.workspace.session(id) != nil else { return nil }
        return id
    }

    private func open(_ path: String?) -> ControlResponse {
        guard let path, !path.isEmpty else { return .failure("Give a folder to open.") }
        let standardized = WorkspacePath.standardize(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            return .failure("No such file or folder: \(standardized)")
        }
        guard isDirectory.boolValue else { return .failure("Viewing files arrives in a later version; give a folder.") }
        SessionManager.shared.addProject(path: standardized)
        let controller = TerminalWindowManager.shared.openMainWindow()
        let session = SessionManager.shared.newSession(in: standardized)
        controller.select(session.id)
        return .success()
    }
}
