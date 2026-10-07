import Darwin
import Foundation

/// Copies of /bin/sleep for tests that need a program file of their own (a path that names a
/// version, an inode that isn't /bin/sleep's). Each is made once, in a folder no test removes,
/// and kept.
///
/// Never delete a program a test has just run. macOS checks a new executable's signature as it
/// starts (syspolicyd), and a copy removed during that check crashed syspolicyd: 31 times on
/// 2026-10-06 and 07, in `MachORep::signingData`, while these tests removed their temporary
/// folders. launchd then held syspolicyd back, every privacy check waited for it (WindowServer's
/// too), and after 40 s macOS stopped WindowServer: the Mac froze, then logged out. The copies a
/// test started also died of it now and then (SIGKILL, code signing).
enum StandInPrograms {
    static let folder = FileManager.default.temporaryDirectory
        .appending(path: "calm-test-programs").resolvingSymlinksInPath()

    /// The copy at `name` in the folder ("bin/tool", "versions/1.0.0"), made the first time.
    static func sleep(at name: String) throws -> URL {
        let program = folder.appending(path: name)
        if FileManager.default.fileExists(atPath: program.path) {
            return program
        }
        let directory = program.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let draft = directory.appending(path: ".\(program.lastPathComponent)-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/sleep"), to: draft)
        // Exclusive: a test run beside this one may have put its copy there first, and may be
        // running it, so it is never replaced. This draft never ran, so removing it is safe.
        if renamex_np(draft.path, program.path, UInt32(RENAME_EXCL)) != 0 {
            let failure = errno
            try? FileManager.default.removeItem(at: draft)
            guard failure == EEXIST else {
                throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
            }
        }
        return program
    }
}
