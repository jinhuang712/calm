import CalmControl
import Foundation
import Testing

struct ScreenshotFileTests {
    @Test func `no name makes a timestamped file in the current folder`() {
        let path = ScreenshotFile.path(argument: nil, directory: "/work", now: Date(timeIntervalSince1970: 0))
        #expect(path.hasPrefix("/work/calm-19"))
        #expect(path.hasSuffix(".png"))
        #expect(ScreenshotFile.path(argument: "", directory: "/work").hasPrefix("/work/calm-"))
    }

    @Test func `a relative name starts from the current folder`() {
        #expect(ScreenshotFile.path(argument: "shots/a.png", directory: "/work") == "/work/shots/a.png")
    }

    @Test func `an absolute name stays and a tilde is the home folder`() {
        #expect(ScreenshotFile.path(argument: "/tmp/a.png", directory: "/work") == "/tmp/a.png")
        #expect(ScreenshotFile.path(argument: "~/a.png", directory: "/work", home: "/Users/me") == "/Users/me/a.png")
    }

    @Test func `only a PNG is accepted from the reply`() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        #expect(ScreenshotFile.png(fromBase64: png.base64EncodedString()) == png)
        #expect(ScreenshotFile.png(fromBase64: Data("hello".utf8).base64EncodedString()) == nil)
        #expect(ScreenshotFile.png(fromBase64: "not base64!") == nil)
        #expect(ScreenshotFile.png(fromBase64: nil) == nil)
    }

    @Test func `a screenshot reply carries the picture and survives the wire`() throws {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        let reply = try JSONEncoder().encode(ControlResponse.screenshot(png: png))
        #expect(try ScreenshotFile.png(fromBase64: JSONDecoder().decode(ControlResponse.self, from: reply).image) == png)
        let request = try JSONEncoder().encode(ControlRequest(cmd: .screenshot))
        #expect(try JSONDecoder().decode(ControlRequest.self, from: request).cmd == .screenshot)
    }
}
