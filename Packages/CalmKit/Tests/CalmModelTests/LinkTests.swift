@testable import CalmModel
import Foundation
import Testing

struct LinkTests {
    private func parse(_ text: String, in directory: String? = "/Users/me/src/app") -> Link? {
        Link.parse(text, relativeTo: directory, home: "/Users/me")
    }

    @Test func `urls stay urls`() throws {
        #expect(try parse("https://example.com/a?b=1") == .url(#require(URL(string: "https://example.com/a?b=1"))))
        #expect(try parse("mailto:me@example.com") == .url(#require(URL(string: "mailto:me@example.com"))))
        #expect(parse("file:///Users/me/notes.md") == .file(path: "/Users/me/notes.md", line: nil, column: nil))
    }

    @Test func `paths with lines and columns`() {
        #expect(parse("Sources/main.swift:42:7") == .file(path: "/Users/me/src/app/Sources/main.swift", line: 42, column: 7))
        #expect(parse("main.swift:42") == .file(path: "/Users/me/src/app/main.swift", line: 42, column: nil))
        #expect(parse("/etc/hosts") == .file(path: "/etc/hosts", line: nil, column: nil))
        #expect(parse("../lib/util.ts:3") == .file(path: "/Users/me/src/lib/util.ts", line: 3, column: nil))
        #expect(parse("~/notes.md") == .file(path: "/Users/me/notes.md", line: nil, column: nil))
        #expect(parse("`README.md`") == .file(path: "/Users/me/src/app/README.md", line: nil, column: nil))
    }

    @Test func `a bare name with a colon is a path, not a scheme`() {
        #expect(parse("Package.swift:12") == .file(path: "/Users/me/src/app/Package.swift", line: 12, column: nil))
    }

    @Test func `relative paths need a folder`() {
        #expect(parse("main.swift", in: nil) == nil)
        #expect(parse("/abs/main.swift", in: nil) == .file(path: "/abs/main.swift", line: nil, column: nil))
        #expect(parse("  ") == nil)
    }

    @Test func `editor arguments put the cursor at the line`() {
        #expect(Editor.vscode.arguments(file: "/a.swift", line: 42, column: 7) == ["-g", "/a.swift:42:7"])
        #expect(Editor.cursor.arguments(file: "/a.swift", line: nil, column: nil) == ["-g", "/a.swift"])
        #expect(Editor.zed.arguments(file: "/a.swift", line: 42, column: nil) == ["/a.swift:42"])
        #expect(Editor.xcode.arguments(file: "/a.swift", line: 42, column: 7) == ["-l", "42", "/a.swift"])
        #expect(Editor.idea.arguments(file: "/a.swift", line: nil, column: nil) == ["/a.swift"])
        #expect(Editor.trae.arguments(file: "/a.swift", line: 3, column: 1) == ["-g", "/a.swift:3:1"])
        #expect(Editor.allCases.last == .xcode) // detected last
    }
}
