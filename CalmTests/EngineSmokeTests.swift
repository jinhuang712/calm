@testable import Calm
import Foundation
import GhosttyKit
import Testing

/// Proves GhosttyKit links and initializes inside the app process.
@MainActor
struct EngineSmokeTests {
    @Test func `engine initializes`() {
        GhosttyRuntime.initializeProcess()
        #expect(GhosttyRuntime.isReady)
    }

    @Test func `engine reports a version`() {
        GhosttyRuntime.initializeProcess()
        #expect(!GhosttyRuntime.engineVersion.isEmpty)
        #expect(GhosttyRuntime.engineVersion != "unknown")
    }

    @Test func `config loads without crashing`() {
        GhosttyRuntime.initializeProcess()
        let config = ghostty_config_new()
        #expect(config != nil)
        ghostty_config_finalize(config)
        ghostty_config_free(config)
    }

    /// A misspelled key or value in Calm's defaults would only show up as a diagnostic.
    @Test func `the defaults Calm writes load without diagnostics`() throws {
        GhosttyRuntime.initializeProcess()
        let file = FileManager.default.temporaryDirectory.appending(path: "calm-defaults-\(UUID().uuidString).ghostty")
        defer { try? FileManager.default.removeItem(at: file) }
        let contents = CalmDefaults.contents(reduceMotion: false, cursorShader: nil, smoothScroll: true)
        #expect(contents.contains("window-padding-color = extend"))
        #expect(contents.contains("smooth-scroll = true"))
        #expect(contents.contains("keybind = super+shift+t=unbind")) // Ghostty's undo, in the way of Reopen Closed Session
        try contents.write(to: file, atomically: true, encoding: .utf8)
        let config = try #require(ghostty_config_new())
        defer { ghostty_config_free(config) }
        file.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)
        #expect(ghostty_config_diagnostics_count(config) == 0)
    }

    /// Fails when GhosttyKit was built without scripts/ghostty-patches: the scrolling would
    /// quietly fall back to whole rows.
    @Test func `the engine has the smooth-scrolling patch`() {
        GhosttyRuntime.initializeProcess()
        #expect(GhosttyRuntime.hasSmoothScroll)
    }

    @Test func `smooth scrolling needs full motion and the patched engine`() {
        let line = "smooth-scroll = true"
        #expect(CalmDefaults.contents(reduceMotion: false, cursorShader: nil, smoothScroll: true).contains(line))
        #expect(!CalmDefaults.contents(reduceMotion: true, cursorShader: nil, smoothScroll: true).contains(line))
        #expect(!CalmDefaults.contents(reduceMotion: false, cursorShader: nil, smoothScroll: false).contains(line))
    }

    /// The test host is a real Calm; it must never write the running Calm's support files.
    @Test func `unit tests keep out of the real support folder`() {
        let real = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "Calm")
        #expect(!CalmDefaults.directory.path.hasPrefix(real.path))
    }
}
