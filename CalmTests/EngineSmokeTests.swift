@testable import Calm
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
}
