@testable import Calm
import Foundation
import Testing

struct RestartTests {
    let app = URL(fileURLWithPath: "/Applications/Calm.app")

    @MainActor
    @Test func `the Restart item sits just above Quit, with no shortcut to hit by mistake`() throws {
        let appMenu = try #require(MainMenu.make().items.first?.submenu)
        let index = try #require(appMenu.items.firstIndex { $0.title == "Restart Calm" })
        #expect(appMenu.items[index + 1].title == "Quit Calm")
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
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // A path with a space: arguments reach the command untouched.
        let opened = folder.appending(path: "opened marker")

        let oldCalm = try Process.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["1"])
        let helper = try Process.run(
            URL(fileURLWithPath: "/bin/sh"),
            arguments: Restart.helperArguments(waitingFor: oldCalm.processIdentifier, then: ["/usr/bin/touch", opened.path]),
        )
        defer { helper.terminate() }

        try await Task.sleep(for: .milliseconds(500))
        #expect(oldCalm.isRunning)
        #expect(!FileManager.default.fileExists(atPath: opened.path))

        let deadline = Date.now.addingTimeInterval(5)
        while helper.isRunning, Date.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(!oldCalm.isRunning)
        #expect(FileManager.default.fileExists(atPath: opened.path))
        #expect(helper.terminationStatus == 0)
    }
}
