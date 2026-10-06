import Foundation

/// Which Calm `calm open` and `calm list` start when nobody answers on the socket.
public enum CalmLaunch {
    public static let bundleID = "com.jinhuang.calm"

    /// The arguments for `/usr/bin/open`, or nil when there is no Calm the CLI can start.
    ///
    /// Only the standard socket gets a Calm started for it. Another one (a self-test's, a Debug
    /// run's) belongs to a Calm started with its own environment: one started now would listen
    /// on the standard socket, perhaps on the real state, and never answer where the CLI asks.
    /// The Calm started is the app the CLI came with, so a copy installed elsewhere, or a Debug
    /// build, starts itself rather than the one LaunchServices finds for the bundle id; the bundle
    /// id only when the CLI isn't inside an app.
    public static func openArguments(
        executable: URL,
        socketPath: String,
        standardSocketPath: String = ControlProtocol.standardSocketPath,
    ) -> [String]? {
        guard socketPath == standardSocketPath else { return nil }
        if let app = app(containing: executable) {
            return ["-g", app.path]
        }
        return ["-g", "-b", bundleID]
    }

    /// `Calm.app` for `Calm.app/Contents/Resources/bin/calm`, also when reached through a link
    /// (the one `install.sh` puts on `PATH`).
    public static func app(containing executable: URL) -> URL? {
        let bin = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        let resources = bin.deletingLastPathComponent()
        let contents = resources.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard bin.lastPathComponent == "bin", resources.lastPathComponent == "Resources",
              contents.lastPathComponent == "Contents", app.pathExtension == "app"
        else { return nil }
        return app
    }
}
