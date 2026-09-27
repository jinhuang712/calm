import Foundation
import GhosttyKit

/// Process-wide libghostty setup. `Terminal` is the only module that talks to GhosttyKit.
@MainActor
enum GhosttyRuntime {
    /// Result of `ghostty_init`, kept for diagnostics and the placeholder window.
    private(set) static var initResult: Int32?

    /// Must run once, before any other libghostty call.
    static func initializeProcess() {
        guard initResult == nil else { return }

        // libghostty looks for themes and shell integration here. Resources are copied
        // into the app bundle at build time (see project.yml); respect an explicit override.
        if ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] == nil,
           let resources = Bundle.main.resourceURL?.appendingPathComponent("ghostty"),
           FileManager.default.fileExists(atPath: resources.path) {
            setenv("GHOSTTY_RESOURCES_DIR", resources.path, 1)
        }

        initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    }

    static var isReady: Bool {
        initResult == GHOSTTY_SUCCESS
    }

    /// Version of the embedded engine, for About and diagnostics.
    static var engineVersion: String {
        let info = ghostty_info()
        guard let pointer = info.version else { return "unknown" }
        let bytes = UnsafeRawBufferPointer(start: pointer, count: Int(info.version_len))
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }

    static var statusLine: String {
        isReady ? "Engine ready · libghostty \(engineVersion)" : "Engine failed to start (code \(initResult ?? -1))"
    }
}
