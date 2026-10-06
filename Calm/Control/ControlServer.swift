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
    private(set) var socketPath: String
    /// The socket file this server bound, so `stop()` never removes another Calm's socket.
    private var boundFile: FileID?
    /// The file at the path that a live Calm was found to own, so a busy one isn't asked every time.
    private var rivalFile: FileID?
    private var watchdog: Timer?

    private struct FileID: Equatable {
        var device: dev_t
        var inode: ino_t
    }

    init(socketPath: String = ControlProtocol.defaultSocketPath) {
        self.socketPath = socketPath
    }

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
        boundFile = Self.fileID(at: path)

        source = Self.makeAcceptSource(fd: fd, queue: queue)
        watchdog = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.listenAgainIfLost() }
        }
        watchdog?.tolerance = 2
    }

    /// The path can stop leading to this server while it keeps running: another Calm unlinked and
    /// bound it, or the file was removed. Its listener then sits on a socket nobody can reach,
    /// every hook is refused, and sessions stop following their agents. When the path is free or
    /// holds what a Calm that died left, listen on it again. When a live Calm owns it, leave it:
    /// taking it back would cut that one off in turn.
    func listenAgainIfLost() {
        guard listenFD >= 0, let boundFile else { return }
        let current = Self.fileID(at: socketPath)
        if current == boundFile || (current != nil && current == rivalFile) {
            return
        }
        if ControlClient.isListening(socketPath: socketPath) {
            rivalFile = current
            Trace.note("control socket taken by another Calm; leaving it")
            return
        }
        Trace.note("control socket lost; listening again")
        closeListener()
        start()
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
        closeListener()
        // Only our own file: the unit-test host never starts a server but still quits through
        // here, and another Calm may have bound this path since; unlinking theirs would cut
        // every hook off from the Calm that is running.
        if let boundFile, let current = Self.fileID(at: socketPath), current == boundFile {
            unlink(socketPath)
        }
        boundFile = nil
    }

    private func closeListener() {
        watchdog?.invalidate()
        watchdog = nil
        source?.cancel()
        source = nil
        if listenFD >= 0 {
            close(listenFD)
        }
        listenFD = -1
        rivalFile = nil
    }

    private static func fileID(at path: String) -> FileID? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return FileID(device: info.st_dev, inode: info.st_ino)
    }

    /// Runs on the control queue: read one line, handle it on main, write the reply.
    private nonisolated static func serve(_ client: Int32) {
        defer { close(client) }
        // A caller that hangs up before the reply (a hook that timed out, a probe that only
        // connects) must not raise SIGPIPE here, which would end Calm.
        var noSignal: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
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

        let arrived = Trace.now
        let response: ControlResponse = if let request = try? JSONDecoder().decode(ControlRequest.self, from: line) {
            if request.cmd == .search {
                // The index has its own queue; searching needs nothing from the main thread.
                SearchService.respond(to: request)
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        Trace.stall(of: request.cmd.rawValue, since: arrived)
                        return ControlServer.shared.handle(request)
                    }
                }
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
                // Not a session's own agent (Claude Code's Bash tool running `pi -p`): quietly
                // nothing, since a hook must never fail its agent.
                let foreground = SessionProbe.shared.foregroundAgent(of: id)
                guard kind.speaksForSession(whileForeground: foreground) else {
                    Trace.reportIgnored(id, kind, foreground: foreground)
                    return .success()
                }
                manager.noteAgentSession(id, kind: kind, agentSessionID: request.agentSession, transcriptPath: request.transcript)
            }
            manager.report(id, StatusReport(state: state, message: request.message, source: .hook, backgroundShells: request.shells ?? 0))
            return .success()
        case .search:
            return SearchService.respond(to: request)
        case .notify:
            guard let id = session(request.session) else { return .failure("No such session.") }
            guard let message = request.message, !message.isEmpty else { return .failure("Give a message.") }
            AttentionCenter.shared.notify(message, for: id)
            return .success()
        case .info:
            // For `calm doctor`: which Calm answers (a second copy, an old build) and whether this
            // session's agent reports reach it.
            let report = session(request.session).flatMap { manager.workspace.session($0) }.map { session in
                ControlResponse.SessionReport(
                    state: session.state.reportName,
                    agent: session.agent?.kind.displayName,
                    reportSource: session.lastReport?.source.rawValue,
                    reportedAt: session.lastReport?.date.timeIntervalSince1970,
                )
            }
            return .success(info: ControlResponse.AppInfo(
                processID: ProcessInfo.processInfo.processIdentifier,
                bundlePath: Bundle.main.bundlePath,
                version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?",
                session: report,
            ))
        }
    }

    private func session(_ value: String?) -> Session.ID? {
        guard let id = value.flatMap(UUID.init(uuidString:)), SessionManager.shared.workspace.session(id) != nil else { return nil }
        return id
    }

    private func open(_ path: String?) -> ControlResponse {
        guard let path, !path.isEmpty else { return .failure("Give a folder or file to open.") }
        // `file:line` opens the file at that line.
        var target = path
        var line: Int?
        if case let .file(file, fileLine, _) = Link.parse(
            path,
            relativeTo: nil,
            home: FileManager.default.homeDirectoryForCurrentUser.path,
        ),
            !FileManager.default.fileExists(atPath: path) {
            target = file
            line = fileLine
        }
        let standardized = WorkspacePath.standardize(target)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDirectory) else {
            return .failure("No such file or folder: \(standardized)")
        }
        guard isDirectory.boolValue else {
            // A file: Calm's viewer if it can show it, else the user's editor or default app.
            let controller = TerminalWindowManager.shared.openMainWindow()
            if !controller.showFile(standardized, line: line) {
                LinkOpener.openInEditor(standardized, line: line, column: nil)
            }
            return .success()
        }
        let project = SessionManager.shared.addProject(path: standardized)
        let controller = TerminalWindowManager.shared.openMainWindow()
        let session = SessionManager.shared.newSession(in: standardized, placement: .project(project.id))
        controller.select(session.id)
        return .success()
    }
}
