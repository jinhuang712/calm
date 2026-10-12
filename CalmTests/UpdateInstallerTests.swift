@testable import Calm
import CalmModel
import Foundation
import Testing

/// Update and Restart (FEATURES.md → Updates), with a fake script run and a fake restart: no test
/// installs anything or restarts Calm.
@MainActor
struct UpdateInstallerTests {
    private let release = CalmRelease(version: ReleaseVersion("0.2.0")!, page: "https://example.test/v0.2.0")

    private final class Record: @unchecked Sendable {
        var arguments: [String] = []
        var restarts = 0
        var failures: [String] = []
    }

    private func installer(_ record: Record, status: Int32, output: String = "") -> UpdateInstaller {
        UpdateInstaller(
            run: { arguments in
                record.arguments = arguments
                return UpdateInstaller.Result(status: status, output: output)
            },
            restart: { record.restarts += 1 },
            fail: { record.failures.append($0) },
            folder: "/Applications",
        )
    }

    @Test func `a good install restarts Calm`() async {
        let record = Record()
        let installer = installer(record, status: 0)
        await installer.install(release)?.value
        #expect(record.restarts == 1)
        #expect(record.failures.isEmpty)
        #expect(!installer.isInstalling)
        #expect(record.arguments.suffix(2) == ["0.2.0", "/Applications"])
    }

    @Test func `a failed install says why and doesn't restart`() async {
        let record = Record()
        let installer = installer(record, status: 1, output: "get.sh: no release")
        await installer.install(release)?.value
        #expect(record.restarts == 0)
        #expect(record.failures == ["get.sh: no release"])
        #expect(!installer.isInstalling)
    }

    @Test func `a second click while one runs does nothing`() async {
        let record = Record()
        let installer = installer(record, status: 0)
        let first = installer.install(release)
        #expect(installer.isInstalling)
        #expect(installer.install(release) == nil)
        await first?.value
        #expect(record.restarts == 1)
    }

    @Test func `the printed tail drops curl's progress bar`() {
        let output = "==> Downloading Calm 0.2.0\n######## 12.0%\r######## 100.0%\n==> Installing to /Applications/Calm.app\n"
        #expect(UpdateInstaller.tail(of: output) == "==> Downloading Calm 0.2.0\n==> Installing to /Applications/Calm.app")
    }
}
