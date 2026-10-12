import AppKit
import CalmModel
import Foundation

/// Update and Restart: installs a newer release over this Calm, then restarts it (FEATURES.md →
/// Updates, DESIGNS.md → Updates). It runs the same get.sh as the one-line install, so the swap
/// that keeps a running Calm working, the checksum and macOS's download mark are one piece of code,
/// not two. Restart Calm does the rest: shells keep running through it.
@MainActor @Observable
final class UpdateInstaller {
    static let shared = UpdateInstaller()

    /// What a run of the script came to: its exit status and the end of what it printed.
    struct Result: Equatable {
        let status: Int32
        let output: String
    }

    typealias Run = @Sendable ([String]) async -> Result

    /// get.sh is running; the notice says so.
    private(set) var isInstalling = false

    private let run: Run
    private let restart: @MainActor () -> Void
    private let fail: @MainActor (String) -> Void
    private let folder: String

    init(
        run: @escaping Run = UpdateInstaller.runBash,
        restart: @escaping @MainActor () -> Void = { Restart.request() },
        fail: @escaping @MainActor (String) -> Void = UpdateInstaller.showFailure,
        folder: String = Bundle.main.bundleURL.deletingLastPathComponent().path,
    ) {
        self.run = run
        self.restart = restart
        self.fail = fail
        self.folder = folder
    }

    /// Whether this Calm can replace itself: not a Debug build (its folder isn't where Calm lives),
    /// and not one Homebrew installed (get.sh refuses it, as Homebrew keeps a record of the app).
    static var isAvailable: Bool {
        !BuildVariant.isDev && !UpdateChecker.installedByHomebrew()
    }

    /// Installs `release`, and restarts when that worked. A failure leaves this Calm as it was
    /// (get.sh swaps the app in last) and says why.
    @discardableResult
    func install(_ release: CalmRelease) -> Task<Void, Never>? {
        guard !isInstalling else { return nil }
        isInstalling = true
        return Task {
            let result = await run(CalmUpdates.installArguments(version: release.version, into: folder))
            isInstalling = false
            if result.status == 0 {
                restart()
            } else {
                fail(result.output)
            }
        }
    }

    // MARK: The real run

    /// `/bin/bash` with these arguments, off the main thread. Its output goes to a file, not a pipe:
    /// curl's progress would fill a pipe nobody reads until the end.
    private nonisolated static func runBash(_ arguments: [String]) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBashNow(arguments))
            }
        }
    }

    private nonisolated static func runBashNow(_ arguments: [String]) -> Result {
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("calm-update-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: log) }
        guard let sink = try? FileHandle(forWritingTo: log) else { return Result(status: -1, output: "Couldn't start the installer.") }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = sink
        process.standardError = sink
        do {
            try process.run()
        } catch {
            return Result(status: -1, output: "Couldn't start the installer: \(error.localizedDescription)")
        }
        // A download that hangs on a bad network would leave "installing" up forever.
        let timedOut = TimedOutFlag()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 180) {
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        process.waitUntilExit()
        try? sink.close()
        if timedOut.value {
            return Result(status: -1, output: "The download took too long. Check your connection and try again.")
        }
        return Result(status: process.terminationStatus, output: tail(of: (try? String(contentsOf: log, encoding: .utf8)) ?? ""))
    }

    /// The last few lines, without curl's progress bar (it redraws one line with carriage returns).
    nonisolated static func tail(of output: String) -> String {
        let lines = output.replacingOccurrences(of: "\r", with: "\n").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return lines.suffix(4).joined(separator: "\n")
    }

    private static func showFailure(_ output: String) {
        let alert = NSAlert()
        alert.messageText = "Couldn't update \(BuildVariant.appName)"
        alert.informativeText = (output.isEmpty ? "The installer failed." : output) + "\n\nYou can update from a terminal instead."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Copy Update Command")
        if alert.runModal() == .alertSecondButtonReturn {
            UpdateChecker.copyUpdateCommand()
        }
    }
}

/// Set by the timer that ends a stuck installer, read once the process has exited.
private final class TimedOutFlag: @unchecked Sendable { // guarded by `lock`
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.withLock { flag }
    }

    func set() {
        lock.withLock { flag = true }
    }
}
