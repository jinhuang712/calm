@testable import Calm
import Foundation
import Testing

struct ViewerImagesTests {
    private func picture(_ string: String) -> (path: String, mimeType: String)? {
        URL(string: string).flatMap(ViewerImages.picture(at:))
    }

    @Test func `a picture beside the file is served with its type`() {
        #expect(picture("calm-image://file/Users/me/repo/docs/pipeline.png")?.path == "/Users/me/repo/docs/pipeline.png")
        #expect(picture("calm-image://file/Users/me/repo/docs/pipeline.png")?.mimeType == "image/png")
        #expect(picture("calm-image://file/Users/me/a/diagram.svg")?.mimeType == "image/svg+xml")
        #expect(picture("calm-image://file/Users/me/a/shot.JPG")?.mimeType == "image/jpeg")
    }

    @Test func `escaped names come back as they are on disk`() {
        #expect(picture("calm-image://file/Users/me/my%20repo/%E5%9B%BE.png")?.path == "/Users/me/my repo/图.png")
    }

    @Test func `a file that isn't a picture is refused`() {
        #expect(picture("calm-image://file/Users/me/repo/.env") == nil)
        #expect(picture("calm-image://file/Users/me/repo/notes.md") == nil)
        #expect(picture("calm-image://file/Users/me/.ssh/id_ed25519") == nil)
        #expect(picture("calm-image://file/Users/me/repo/page.html") == nil)
    }

    @Test func `another scheme is refused`() {
        #expect(picture("file:///Users/me/repo/pipeline.png") == nil)
    }
}
