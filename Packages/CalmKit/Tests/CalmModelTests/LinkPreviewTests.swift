@testable import CalmModel
import Foundation
import Testing

struct LinkPreviewTests {
    private let home = "/Users/me"

    @Test func `a file shows its name and line, its folder, and where it opens`() {
        let preview = LinkPreview.file(
            path: "/Users/me/dev/vibe-billing/e2e/workbench.spec.ts", line: 283, isImage: false, destination: .viewer, home: home,
        )
        #expect(preview == LinkPreview(
            kind: .file,
            title: "workbench.spec.ts:283",
            detail: "~/dev/vibe-billing/e2e",
            action: "Open in viewer",
        ))
        #expect(LinkPreview.file(path: "/etc/hosts", line: nil, isImage: false, destination: .editor("Cursor"), home: home)
            == LinkPreview(kind: .file, title: "hosts", detail: "/etc", action: "Open in Cursor"))
        #expect(LinkPreview.file(path: "/Users/me/shot.png", line: nil, isImage: true, destination: .defaultApp, home: home)
            == LinkPreview(kind: .image, title: "shot.png", detail: "~", action: "Open"))
    }

    @Test func `a web link shows its site and path`() throws {
        #expect(try LinkPreview.url(#require(URL(string: "https://playwright.dev/docs/test-assertions")))
            == LinkPreview(kind: .web, title: "playwright.dev", detail: "/docs/test-assertions", action: "Open in browser"))
        #expect(try LinkPreview.url(#require(URL(string: "https://example.com/?q=1"))).detail == "/?q=1")
        #expect(try LinkPreview.url(#require(URL(string: "https://zmx.sh"))).detail == nil)
        #expect(try LinkPreview.url(#require(URL(string: "mailto:me@example.com")))
            == LinkPreview(kind: .web, title: "me@example.com", detail: nil, action: "Open"))
    }

    @Test func `folders and missing files`() {
        #expect(LinkPreview.folder(path: "/Users/me/dev/apps", home: home)
            == LinkPreview(kind: .folder, title: "apps", detail: "~/dev", action: "Open in Finder"))
        #expect(LinkPreview.folder(path: home, home: home).title == "~")
        #expect(LinkPreview.missing("e2e/missing.spec.ts")
            == LinkPreview(kind: .missing, title: "missing.spec.ts", detail: "e2e", action: "Not found"))
        #expect(LinkPreview.missing("gone.txt").detail == nil)
    }

    @Test func `home is shown as a tilde, and only a whole folder name counts`() {
        #expect(LinkPreview.abbreviated("/Users/me", home: home) == "~")
        #expect(LinkPreview.abbreviated("/Users/me/dev", home: home) == "~/dev")
        #expect(LinkPreview.abbreviated("/Users/meg/dev", home: home) == "/Users/meg/dev")
    }
}
