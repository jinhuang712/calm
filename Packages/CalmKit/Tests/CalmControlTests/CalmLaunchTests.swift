import CalmControl
import Foundation
import Testing

struct CalmLaunchTests {
    private let standard = "/Users/me/Library/Application Support/Calm/calm.sock"

    @Test func `a CLI inside an app starts that app`() {
        let cli = URL(filePath: "/Volumes/Work/Calm Dev.app/Contents/Resources/bin/calm")

        #expect(CalmLaunch.openArguments(executable: cli, socketPath: standard, standardSocketPath: standard) == [
            "-g",
            "/Volumes/Work/Calm Dev.app",
        ])
    }

    @Test func `the link on PATH leads to the app it points into`() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "calm-launch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appending(path: "Calm.app/Contents/Resources/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appending(path: "calm").path, contents: Data())
        let link = root.appending(path: "local-bin/calm")
        try FileManager.default.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: bin.appending(path: "calm"))

        let app = try #require(CalmLaunch.app(containing: link))
        #expect(app.path == root.appending(path: "Calm.app").resolvingSymlinksInPath().path)
    }

    @Test func `a CLI outside an app starts Calm by its bundle id`() {
        let cli = URL(filePath: "/opt/calm/bin/calm")

        #expect(CalmLaunch.openArguments(executable: cli, socketPath: standard, standardSocketPath: standard) == [
            "-g",
            "-b",
            "com.jinhuang.calm",
        ])
    }

    /// A self-test's or Debug run's socket: a Calm started now would never answer there.
    @Test func `a socket of its own names a Calm the CLI can't start`() {
        let cli = URL(filePath: "/Applications/Calm.app/Contents/Resources/bin/calm")

        #expect(CalmLaunch.openArguments(executable: cli, socketPath: "/tmp/calm-selftest-x.sock", standardSocketPath: standard) == nil)
    }

    @Test func `other places in or near an app aren't taken for its CLI`() {
        #expect(CalmLaunch.app(containing: URL(filePath: "/Applications/Calm.app/Contents/MacOS/Calm")) == nil)
        #expect(CalmLaunch.app(containing: URL(filePath: "/work/Calm/Contents/Resources/bin/calm")) == nil)
    }
}
