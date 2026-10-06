import Foundation

/// How `calm hook` reads an agent's hook payload from stdin. A hook runs on every agent event
/// and holds the agent up while it runs, so the read ends at a deadline as well as at a size: a
/// hook runner that leaves stdin open, or a payload that never ends, reports nothing instead of
/// stalling the agent. The socket has a limit of its own (`ControlClient.send`'s timeout).
public enum HookInput {
    /// Far above any payload seen: Claude Code cuts tool output and replies long before this.
    public static let sizeLimit = 16 * 1024 * 1024
    public static let timeLimit: TimeInterval = 1

    /// The whole payload, up to the end of the input; nil when it didn't end within `timeLimit`,
    /// ran past `sizeLimit`, or couldn't be read.
    public static func read(
        from fd: Int32 = STDIN_FILENO,
        sizeLimit: Int = sizeLimit,
        timeLimit: TimeInterval = timeLimit,
    ) -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + timeLimit
        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return nil }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, Int32((remaining * 1000).rounded(.up)))
            if ready < 0, errno == EINTR {
                continue
            }
            guard ready > 0 else { return nil }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0, errno == EINTR || errno == EAGAIN {
                continue
            }
            guard count >= 0 else { return nil }
            if count == 0 {
                return payload
            }
            payload.append(contentsOf: buffer[0 ..< count])
            guard payload.count <= sizeLimit else { return nil }
        }
    }
}
