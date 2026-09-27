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
    }

    public var v: Int
    public var cmd: Command
    public var path: String?
    public var session: String?
    public var state: String?
    public var message: String?

    public init(
        cmd: Command,
        path: String? = nil,
        session: String? = nil,
        state: String? = nil,
        message: String? = nil,
    ) {
        v = ControlProtocol.version
        self.cmd = cmd
        self.path = path
        self.session = session
        self.state = state
        self.message = message
    }
}

public struct ControlResponse: Codable, Sendable, Equatable {
    public struct SessionInfo: Codable, Sendable, Equatable {
        public var id: String
        public var title: String
        public var project: String
        public var directory: String
        public var state: String

        public init(id: String, title: String, project: String, directory: String, state: String) {
            self.id = id
            self.title = title
            self.project = project
            self.directory = directory
            self.state = state
        }
    }

    public var ok: Bool
    public var error: String?
    public var sessions: [SessionInfo]?

    public static func success(sessions: [SessionInfo]? = nil) -> ControlResponse {
        ControlResponse(ok: true, error: nil, sessions: sessions)
    }

    public static func failure(_ message: String) -> ControlResponse {
        ControlResponse(ok: false, error: message, sessions: nil)
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

    public static func send(_ request: ControlRequest, socketPath: String = ControlProtocol.defaultSocketPath) throws -> ControlResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.io("socket() failed") }
        defer { close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard socketPath.utf8.count < capacity else { throw ClientError.io("socket path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: socketPath.utf8)
            buffer[socketPath.utf8.count] = 0
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw ClientError.notRunning(socketPath) }

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
}
