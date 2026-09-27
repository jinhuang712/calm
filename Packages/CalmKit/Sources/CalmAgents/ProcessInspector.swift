import Darwin
import Foundation

/// Reads what runs in a shell's foreground, with plain syscalls (no processes spawned).
public enum ProcessInspector {
    /// The process group that owns the shell's terminal right now, if it isn't the shell
    /// itself: the job the user started (`claude`, `vim`, …).
    public static func foregroundJob(ofShell shell: Int32) -> Int32? {
        guard let info = bsdInfo(shell) else { return nil }
        let foreground = Int32(bitPattern: info.e_tpgid)
        guard foreground > 0, foreground != Int32(bitPattern: info.pbi_pgid) else { return nil }
        return foreground
    }

    /// Executable path and arguments of a process (`KERN_PROCARGS2`).
    public static func snapshot(of pid: Int32) -> ProcessSnapshot? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseArguments(Array(buffer.prefix(size)), processID: pid)
    }

    /// `KERN_PROCARGS2` layout: argc (Int32), the executable path, NUL padding, then argc
    /// NUL-terminated arguments (the environment follows and is ignored).
    static func parseArguments(_ bytes: [UInt8], processID: Int32) -> ProcessSnapshot? {
        guard bytes.count > 4 else { return nil }
        let argc = bytes.prefix(4).withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var cursor = 4
        func nextString() -> String? {
            while cursor < bytes.count, bytes[cursor] == 0 {
                cursor += 1
            }
            guard cursor < bytes.count else { return nil }
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0 {
                cursor += 1
            }
            return String(bytes: bytes[start ..< cursor], encoding: .utf8)
        }
        guard let executable = nextString() else { return nil }
        var arguments: [String] = []
        for _ in 0 ..< max(argc, 0) {
            guard let argument = nextString() else { break }
            arguments.append(argument)
        }
        return ProcessSnapshot(processID: processID, executablePath: executable, arguments: arguments)
    }

    private static func bsdInfo(_ pid: Int32) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return info
    }
}
