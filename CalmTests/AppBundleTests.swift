@testable import Calm
import Foundation
import Testing

/// What the built app holds beside its code (project.yml's post-build script); the tests run
/// inside it.
struct AppBundleTests {
    /// `calm` looks for CalmKit's resource bundles beside itself, and `Bundle.module` stops it when
    /// one isn't there (`calm doctor` did, 2026-10-07): each has a link in `bin`.
    @Test func `the calm tool finds CalmKit's resource bundles beside it`() throws {
        let resources = try #require(Bundle.main.resourceURL)
        let bin = resources.appending(path: "bin")
        #expect(FileManager.default.isExecutableFile(atPath: bin.appending(path: "calm").path))
        let bundles = try FileManager.default.contentsOfDirectory(atPath: resources.path)
            .filter { $0.hasPrefix("CalmKit_") && $0.hasSuffix(".bundle") }
        #expect(!bundles.isEmpty)
        for name in bundles {
            #expect(Bundle(url: bin.appending(path: name)) != nil, "\(name) isn't reachable from bin")
        }
    }

    /// The download carries the license of everything it bundles (scripts/licenses.sh), and NOTICE
    /// says what each is for, so a text NOTICE doesn't name, or a name with no text, is a gap.
    @Test func `NOTICE names every license text the app carries, and each one it names is there`() throws {
        let resources = try #require(Bundle.main.resourceURL)
        let notice = try String(contentsOf: resources.appending(path: "NOTICE"), encoding: .utf8)
        let texts = try FileManager.default.contentsOfDirectory(atPath: resources.appending(path: "Licenses").path)
            .filter { $0.hasSuffix(".txt") }
        #expect(texts.count > 30)
        for text in texts {
            #expect(notice.contains(text), "NOTICE doesn't name Licenses/\(text)")
        }
        let named = try Regex(#"[A-Za-z0-9._-]+\.txt"#)
        for match in notice.matches(of: named) {
            #expect(texts.contains(String(notice[match.range])), "NOTICE names \(notice[match.range]), which isn't in Licenses")
        }
    }
}
