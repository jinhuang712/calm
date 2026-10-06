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

    /// The file the process runs, links resolved (`…/claude/versions/2.1.291`, where its argv
    /// says `~/.local/bin/claude`). Nil once that file was deleted, as an update does to the
    /// version it replaces, or when the process is gone.
    public static func executableFile(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
        return path?.isEmpty == false ? path : nil
    }

    /// The process's current directory.
    public static func workingDirectory(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        return path(from: info.pvi_cdir.vip_path)
    }

    /// When the process started.
    public static func startDate(of pid: Int32) -> Date? {
        guard let info = bsdInfo(pid), info.pbi_start_tvsec > 0 else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    /// Every process running `executable` (as `proc_pidpath` gives it: links resolved), such as
    /// each copy of Calm started from one app.
    public static func processes(running executable: String) -> [Int32] {
        // A count of processes (libproc divides by the size of a pid), plus room for those
        // started between the two calls.
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(estimate) + 64)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.stride)))
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(max(count, 0)).filter { pid in
            guard pid > 0 else { return false }
            let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
            guard length > 0 else { return false }
            return String(bytes: buffer.prefix(length).map { UInt8(bitPattern: $0) }, encoding: .utf8) == executable
        }
    }

    /// The files the process has open (regular files and directories, not sockets or pipes).
    public static func openFiles(of pid: Int32) -> [String] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / MemoryLayout<proc_fdinfo>.stride)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, bytes)
        guard filled > 0 else { return [] }
        var paths: [String] = []
        for descriptor in descriptors.prefix(Int(filled) / MemoryLayout<proc_fdinfo>.stride)
            where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
            var info = vnode_fdinfowithpath()
            let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
            guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size,
                  let file = path(from: info.pvip.vip_path)
            else { continue }
            paths.append(file)
        }
        return paths
    }

    /// The process's children, their children and so on (a launcher such as node runs the agent
    /// as a child). Bounded, so a fork bomb can't make this slow.
    public static func descendants(of pid: Int32, limit: Int = 64) -> [Int32] {
        var found: [Int32] = []
        var queue = [pid]
        while let next = queue.popLast(), found.count < limit {
            let bytes = proc_listchildpids(next, nil, 0)
            guard bytes > 0 else { continue }
            var children = [Int32](repeating: 0, count: Int(bytes) / MemoryLayout<Int32>.stride + 8)
            let count = Int(proc_listchildpids(next, &children, Int32(children.count * MemoryLayout<Int32>.stride)))
            for child in children.prefix(max(count, 0)) where child > 0 {
                found.append(child)
                queue.append(child)
            }
        }
        return found
    }

    private static func path(from tuple: some Any) -> String? {
        let text = withUnsafeBytes(of: tuple) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }
        return text?.isEmpty == false ? text : nil
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
