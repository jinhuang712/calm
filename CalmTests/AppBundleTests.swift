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
}
