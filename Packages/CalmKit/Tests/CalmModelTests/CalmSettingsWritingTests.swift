@testable import CalmModel
import Foundation
import Testing

struct CalmSettingsWritingTests {
    @Test func `replaces a key in its section and keeps everything else`() {
        let text = """
        # my settings
        auto-grouping = false

        [agents]
        notify = "needs-you" # only when blocked
        sound = false
        """
        let updated = CalmSettings.setting("agents.notify", to: "all", in: text)
        #expect(updated == """
        # my settings
        auto-grouping = false

        [agents]
        notify = "all"
        sound = false
        """)
        #expect(CalmSettings(text: updated).notifyStates == .all)
    }

    @Test func `adds a key to an existing section, before the next one`() {
        let text = "[agents]\nsound = false\n\n[other]\nkeep = 1\n"
        let updated = CalmSettings.setting("agents.notify", to: "all", in: text)
        #expect(updated == "[agents]\nsound = false\nnotify = \"all\"\n\n[other]\nkeep = 1\n")
        #expect(CalmSettings(text: updated).string("other.keep") == "1")
    }

    @Test func `adds a missing section at the end`() {
        let updated = CalmSettings.setting("agents.sound", to: "true", in: "auto-grouping = false\n")
        #expect(updated == "auto-grouping = false\n\n[agents]\nsound = true\n")
        #expect(CalmSettings(text: updated).notificationSound)
    }

    @Test func `top-level keys go before the first section`() {
        let updated = CalmSettings.setting("motion", to: "reduced", in: "[agents]\nsound = true\n")
        #expect(updated == "motion = \"reduced\"\n[agents]\nsound = true\n")
        #expect(CalmSettings(text: updated).motion == .reduced)
    }

    @Test func `writing to an empty file`() {
        #expect(CalmSettings.setting("agents.notify", to: "all", in: "") == "[agents]\nnotify = \"all\"\n")
    }

    @Test func `defaults for notifications`() {
        #expect(CalmSettings(text: "").notifyStates == .needsYou)
        #expect(CalmSettings(text: "").notificationSound == false)
    }

    @Test func `save writes the file`() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "calm-\(UUID().uuidString)/config.toml")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let saved = try CalmSettings.save("agents.sound", "true", to: url)
        #expect(saved.notificationSound)
        #expect(CalmSettings.load(from: url).notificationSound)
    }
}
