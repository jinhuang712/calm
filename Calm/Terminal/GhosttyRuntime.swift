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

        cleanInheritedEnvironment()

        // libghostty finds themes, shell integration and terminfo here. Calm always uses its
        // own bundled copy (see project.yml); `CALM_GHOSTTY_RESOURCES_DIR` overrides it for development.
        let override = ProcessInfo.processInfo.environment["CALM_GHOSTTY_RESOURCES_DIR"]
        if let resources = override ?? Bundle.main.resourceURL?.appendingPathComponent("ghostty").path,
           FileManager.default.fileExists(atPath: resources) {
            setenv("GHOSTTY_RESOURCES_DIR", resources, 1)
        }

        initResult = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
    }

    /// When Calm is launched from another terminal, that terminal's variables would leak into
    /// every shell Calm starts (and point libghostty at the other app's resources). Drop them.
    static let inheritedVariablesToDrop = [
        "GHOSTTY_RESOURCES_DIR", "GHOSTTY_BIN_DIR", "GHOSTTY_SHELL_FEATURES", "GHOSTTY_SHELL_INTEGRATION_NO_SUDO",
        "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TERM_SESSION_ID", "ITERM_SESSION_ID",
        "WARP_IS_LOCAL_SHELL_SESSION", "CMUX_SESSION_ID", "TMUX", "TMUX_PANE", "ZELLIJ", "STY", "ZMX_SESSION", "ZMX_DIR",
    ]

    private static func cleanInheritedEnvironment() {
        for name in inheritedVariablesToDrop {
            unsetenv(name)
        }
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
