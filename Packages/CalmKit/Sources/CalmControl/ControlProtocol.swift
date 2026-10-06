import Foundation

/// The local control protocol between the `calm` CLI (and agent hooks) and the app:
/// one JSON object per line over a Unix socket (see DESIGNS.md → Control protocol).
public enum ControlProtocol {
    public static let version = 1

    /// `~/Library/Application Support/Calm/calm.sock`, overridable with `CALM_SOCKET`.
    public static var defaultSocketPath: String {
        if let override = ProcessInfo.processInfo.environment["CALM_SOCKET"], !override.isEmpty {
            return override
        }
        return standardSocketPath
    }

    /// Where a Calm started without `CALM_SOCKET` listens.
    public static var standardSocketPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "Calm/calm.sock").path
    }
}

public struct ControlRequest: Codable, Sendable, Equatable {
    public enum Command: String, Codable, Sendable {
        case list
        case open
        case status
        case notify
        case search
        /// What `calm doctor` asks: which Calm answers, and what it knows of `session`.
        case info
        /// Re-read config.toml and the Ghostty config, as Reload Configuration does (`calm config`).
        case reload
        /// Fork `session`'s conversation into a new session (`calm fork`): `message` is the fork's
        /// first prompt, `path` its folder, `background` keeps the user where they are.
        case fork
    }

    public var v: Int
    public var cmd: Command
    public var path: String?
    public var session: String?
    public var state: String?
    public var message: String?
    /// From agents' hooks (`calm hook`): which agent, its own session id and transcript file.
    public var agent: String?
    public var agentSession: String?
    public var transcript: String?
    /// From a hook that ended a turn: shells still running (nil for none; older callers omit it).
    public var shells: Int?
    /// From a hook about a compaction: "start:manual", "end:auto" (`CompactionReport`; nil for none).
    public var compaction: String?
    /// For `search`.
    public var query: String?
    /// For `fork`: stay where you are, the fork waiting in the sidebar.
    public var background: Bool?

    public init(
        cmd: Command,
        path: String? = nil,
        session: String? = nil,
        state: String? = nil,
        message: String? = nil,
        agent: String? = nil,
        agentSession: String? = nil,
        transcript: String? = nil,
        shells: Int? = nil,
        compaction: String? = nil,
        query: String? = nil,
        background: Bool? = nil,
    ) {
        v = ControlProtocol.version
        self.cmd = cmd
        self.path = path
        self.session = session
        self.state = state
        self.message = message
        self.agent = agent
        self.agentSession = agentSession
        self.transcript = transcript
        self.shells = shells
        self.compaction = compaction
        self.query = query
        self.background = background
    }
}

public struct ControlResponse: Codable, Sendable, Equatable {
    public struct SessionInfo: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var project: String
        public var directory: String
        public var state: String
        /// The agent in the foreground, if any (added after v1 shipped; optional for older apps).
        public var agent: String?
        /// The agent's id for the conversation running or last run here (`calm show` matches it).
        public var conversation: String?

        public init(
            id: String, title: String, project: String, directory: String, state: String, agent: String? = nil,
            conversation: String? = nil,
        ) {
            self.id = id
            self.title = title
            self.project = project
            self.directory = directory
            self.state = state
            self.agent = agent
            self.conversation = conversation
        }
    }

    /// A session found by `search`.
    public struct SearchHit: Codable, Sendable, Equatable {
        public var title: String
        public var agent: String
        public var directory: String?
        /// Seconds since 1970.
        public var lastActive: Double
        /// The best match, with matches between U+0002 and U+0003.
        public var snippet: String
        public var transcript: String
        /// The agent's id for the conversation, for `calm show` (nil from an older Calm).
        public var conversation: String?

        public init(
            title: String, agent: String, directory: String?, lastActive: Double, snippet: String, transcript: String,
            conversation: String? = nil,
        ) {
            self.title = title
            self.agent = agent
            self.directory = directory
            self.lastActive = lastActive
            self.snippet = snippet
            self.transcript = transcript
            self.conversation = conversation
        }
    }

    /// The Calm that answered `info`.
    public struct AppInfo: Codable, Sendable, Equatable {
        public var processID: Int32
        /// The app bundle it runs from.
        public var bundlePath: String
        public var version: String
        /// What it knows of the session the request named; nil when it doesn't know it.
        public var session: SessionReport?

        public init(processID: Int32, bundlePath: String, version: String, session: SessionReport? = nil) {
            self.processID = processID
            self.bundlePath = bundlePath
            self.version = version
            self.session = session
        }
    }

    /// A session's state and who last reported it: enough to tell hooks that never arrive.
    public struct SessionReport: Codable, Sendable, Equatable {
        public var state: String
        public var agent: String?
        /// `hook` or `terminal`; nil before anything reported.
        public var reportSource: String?
        /// Seconds since 1970.
        public var reportedAt: Double?

        public init(state: String, agent: String? = nil, reportSource: String? = nil, reportedAt: Double? = nil) {
            self.state = state
            self.agent = agent
            self.reportSource = reportSource
            self.reportedAt = reportedAt
        }
    }

    public var ok: Bool
    public var error: String?
    public var sessions: [SessionInfo]?
    public var results: [SearchHit]?
    public var info: AppInfo?

    public static func success(sessions: [SessionInfo]? = nil, results: [SearchHit]? = nil, info: AppInfo? = nil) -> ControlResponse {
        ControlResponse(ok: true, error: nil, sessions: sessions, results: results, info: info)
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message, sessions: nil, results: nil, info: nil)
    }
}

/// A blocking client, for the CLI and hooks.
public enum ControlClient {
    public enum ClientError: Error, CustomStringConvertible {
        case notRunning(String)
        case io(String)

        public var description: String {
            switch self {
            case let .notRunning(path): "Calm isn't running (no socket at \(path))."
            case let .io(message): message
            }
        }
    }

    /// Hooks call this on every agent turn, so a Calm that is busy or stuck must not hold
    /// the agent up: reads and writes give up after `timeout` seconds.
    public static func send(
        _ request: ControlRequest,
        socketPath: String = ControlProtocol.defaultSocketPath,
        timeout: TimeInterval = 2,
    ) throws -> ControlResponse {
        let fd = try connectedSocket(to: socketPath, timeout: timeout)
        defer { close(fd) }

        var line = try JSONEncoder().encode(request)
        line.append(0x0A)
        let written = line.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard written == line.count else { throw ClientError.io("could not send the request") }

        var received = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while !received.contains(0x0A) {
            let count = read(fd, &buffer, buffer.count)
            if count <= 0 {
                break
            }
            received.append(contentsOf: buffer[0 ..< count])
        }
        guard let end = received.firstIndex(of: 0x0A) else { throw ClientError.io("no response from Calm") }
        return try JSONDecoder().decode(ControlResponse.self, from: received[..<end])
    }

    /// Whether a Calm is listening at `socketPath`. The socket file a Calm that died left behind
    /// refuses the connection, so it counts as nobody. Connects and hangs up without a request.
    public static func isListening(socketPath: String = ControlProtocol.defaultSocketPath) -> Bool {
        guard let fd = try? connectedSocket(to: socketPath, timeout: 1) else { return false }
        close(fd)
        return true
    }

    private static func connectedSocket(to socketPath: String, timeout: TimeInterval) throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.io("socket() failed") }
        var limit = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < capacity else {
            close(fd)
            throw ClientError.io("socket path too long")
        }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: socketPath.utf8)
            buffer[socketPath.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            throw ClientError.notRunning(socketPath)
        }
        return fd
    }
}
