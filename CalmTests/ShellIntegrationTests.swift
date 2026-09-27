@testable import Calm
import Testing

struct ShellIntegrationTests {
    let resources = "/Calm.app/Contents/Resources/ghostty"

    @Test func `zsh points ZDOTDIR at the integration and keeps the user's own`() {
        let plain = ShellIntegration.environment(shell: "/bin/zsh", mode: "detect", resourcesDirectory: resources, inherited: [:])
        #expect(plain == ["ZDOTDIR": "\(resources)/shell-integration/zsh"])

        let custom = ShellIntegration.environment(
            shell: "/bin/zsh", mode: "detect", resourcesDirectory: resources, inherited: ["ZDOTDIR": "/Users/me/.config/zsh"],
        )
        #expect(custom["GHOSTTY_ZSH_ZDOTDIR"] == "/Users/me/.config/zsh")
    }

    @Test func `fish prepends the integration to XDG_DATA_DIRS`() {
        let environment = ShellIntegration.environment(
            shell: "/opt/homebrew/bin/fish", mode: nil, resourcesDirectory: resources, inherited: [:],
        )
        #expect(environment["XDG_DATA_DIRS"] == "\(resources)/shell-integration:/usr/local/share:/usr/share")
        #expect(environment["GHOSTTY_SHELL_INTEGRATION_XDG_DIR"] == "\(resources)/shell-integration")
    }

    @Test func `none turns it off, and a named shell wins over SHELL`() {
        #expect(ShellIntegration.environment(shell: "/bin/zsh", mode: "none", resourcesDirectory: resources, inherited: [:]).isEmpty)
        let forced = ShellIntegration.environment(shell: "/bin/zsh", mode: "fish", resourcesDirectory: resources, inherited: [:])
        #expect(forced["ZDOTDIR"] == nil)
        #expect(forced["XDG_DATA_DIRS"] != nil)
    }

    @Test func `bash and unknown shells get nothing`() {
        #expect(ShellIntegration.environment(shell: "/bin/bash", mode: nil, resourcesDirectory: resources, inherited: [:]).isEmpty)
        #expect(ShellIntegration.environment(shell: "/bin/zsh", mode: nil, resourcesDirectory: nil, inherited: [:]).isEmpty)
    }
}

struct ZmxListingTests {
    @Test func `shell processes are read from zmx list`() {
        let listing = """
          name=calm-383587ad56b6\tpid=10168\tclients=0\tcreated=1790517530\tcwd=file://host/Users/me
          name=calm-0123456789ab\tpid=10200\tclients=1
        broken line
        """
        #expect(PersistentShell.parseShellProcesses(listing) == ["calm-383587ad56b6": 10168, "calm-0123456789ab": 10200])
    }
}
