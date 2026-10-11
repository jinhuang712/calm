@testable import Calm
import Foundation
import Testing

struct RestartTests {
    let app = URL(fileURLWithPath: "/Applications/Calm.app")

    @MainActor
    @Test func `the Restart item sits just above Quit, with no shortcut to hit by mistake`() throws {
        let appMenu = try #require(MainMenu.make().items.first?.submenu)
        let name = BuildVariant.appName
        let index = try #require(appMenu.items.firstIndex { $0.title == "Restart \(name)" })
        #expect(appMenu.items[index + 1].title == "Quit \(name)")
        #expect(appMenu.items[index].keyEquivalent.isEmpty)
        #expect(appMenu.items[index].target === TerminalMenuTarget.shared)
    }

    @Test func `the new Calm opens from the same path`() {
        #expect(Restart.openCommand(app: app, background: false) == ["/usr/bin/open", "/Applications/Calm.app"])
        // A headless self-test stays in the background.
        #expect(Restart.openCommand(app: app, background: true) == ["/usr/bin/open", "-g", "/Applications/Calm.app"])
    }

    @Test func `the new Calm keeps the environment, but a self-test doesn't run again`() {
        let environment = [
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "CALM_STATE_FILE": "/tmp/test state.json",
            "CALM_ZMX_DIR": "/tmp/calm-zmx-test",
            "CALM_HEADLESS": "1",
            "CALM_SELFTEST_AFTER": "calm.restart",
            "CALM_SELFTEST_TYPE": "echo hi",
            "CALM_SNAPSHOT": "/tmp/shot.png",
            "CALM_SNAPSHOT_QUIT": "1",
        ]
        #expect(Restart.relaunchEnvironment(environment) == [
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
            "CALM_STATE_FILE": "/tmp/test state.json",
            "CALM_ZMX_DIR": "/tmp/calm-zmx-test",
            "CALM_HEADLESS": "1",
        ])
    }

    @Test func `the helper opens Calm only once the old one has exited`() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        // A path with a space: arguments reach the command untouched.
        let opened = folder.appending(path: "opened marker")

        let oldCalm = try Process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["1"])
        let helper = try Process.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: Restart.helperArguments(waitingFor: oldCalm.processIdentifier, removing: nil, then: ["/usr/bin/touch", opened.path]),
        )
        defer { helper.terminate() }

        try await Task.sleep(for: .milliseconds(500))
        #expect(oldCalm.isRunning)
        #expect(!FileManager.default.fileExists(atPath: opened.path))

        try await waitForExit(helper)
        #expect(!oldCalm.isRunning)
        #expect(FileManager.default.fileExists(atPath: opened.path))
        #expect(helper.terminationStatus == 0)
    }

    @Test func `a copy an installer moved aside is the one deleted`() {
        let launched = URL(fileURLWithPath: "/Applications/Calm.app", isDirectory: true)
        let moved = "/Applications/.Calm.app.previous-20261012-001951-98124"
        #expect(Restart.movedCopy(launchedFrom: launched, runningFrom: moved + "/Contents/MacOS/Calm")?.path == moved)
        // Running from where it started.
        #expect(Restart.movedCopy(launchedFrom: launched, runningFrom: "/Applications/Calm.app/Contents/MacOS/Calm") == nil)
        // Moved by someone, under another name or into another folder: never deleted.
        #expect(Restart.movedCopy(launchedFrom: launched, runningFrom: "/Applications/Calm 2.app/Contents/MacOS/Calm") == nil)
        #expect(Restart.movedCopy(
            launchedFrom: launched,
            runningFrom: "/Users/me/Old/.Calm.app.previous-20261012-001951-98124/Contents/MacOS/Calm",
        ) == nil)
        #expect(Restart.movedCopy(launchedFrom: launched, runningFrom: moved + "/Calm") == nil)
        #expect(Restart.movedCopy(launchedFrom: launched, runningFrom: nil) == nil)
    }

    @Test func `the moved copy goes once the old Calm has exited, before Calm opens again`() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let moved = folder.appending(path: ".Calm.app.previous-20261012-001951-98124")
        try FileManager.default.createDirectory(at: moved.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
        let opened = folder.appending(path: "opened marker")

        let oldCalm = try Process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["1"])
        // The command stands in for `open`: it leaves its marker only if the moved copy is gone.
        let helper = try Process.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: Restart.helperArguments(
                waitingFor: oldCalm.processIdentifier,
                removing: moved,
                then: ["/bin/sh", "-c", #"[ ! -e "$0" ] && /usr/bin/touch "$1""#, moved.path, opened.path],
            ),
        )
        defer { helper.terminate() }

        try await Task.sleep(for: .milliseconds(500))
        #expect(FileManager.default.fileExists(atPath: moved.path))

        try await waitForExit(helper)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(FileManager.default.fileExists(atPath: opened.path))
        #expect(helper.terminationStatus == 0)
    }

    @Test func `after a plain quit the moved copy goes and nothing opens`() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let moved = folder.appending(path: ".Calm.app.previous-20261012-001951-98124")
        try FileManager.default.createDirectory(at: moved, withIntermediateDirectories: true)

        let oldCalm = try Process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["0.2"])
        let helper = try Process.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: Restart.helperArguments(waitingFor: oldCalm.processIdentifier, removing: moved, then: []),
        )
        defer { helper.terminate() }

        try await waitForExit(helper)
        #expect(!FileManager.default.fileExists(atPath: moved.path))
        #expect(helper.terminationStatus == 0)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func waitForExit(_ process: Process) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while process.isRunning, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
