@testable import Calm
import CalmModel
import Foundation
import Testing

@MainActor
struct LinkOpenerTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "calm-links-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder.appending(path: "src"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "src/main.swift"))
        return folder
    }

    @Test func `a path the terminal ran on into the next words still opens`() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let text = "\(folder.path)/src and then some"
        #expect(LinkOpener.resolveExactly(text, directory: nil, projectDirectory: nil) == nil)
        #expect(LinkOpener.resolve(text, directory: nil, projectDirectory: nil) == .file(
            path: folder.path + "/src",
            line: nil,
            column: nil,
        ))
    }

    @Test func `a relative path is tried in the project when it isn't in the session's folder`() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let link = LinkOpener.resolve("src/main.swift:3", directory: folder.path + "/src", projectDirectory: folder.path)
        #expect(link == .file(path: folder.path + "/src/main.swift", line: 3, column: nil))
        #expect(LinkOpener.resolve("src/gone.swift", directory: folder.path, projectDirectory: nil) == nil)
    }

    @Test func `a relative path is found in the agent's worktree first`() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let worktree = folder.appending(path: "wt", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: worktree.appending(path: "design"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: worktree.appending(path: "design/a.html"))
        let link = LinkOpener.resolve("design/a.html", directory: folder.path, projectDirectory: folder.path, agentDirectory: worktree.path)
        #expect(link == .file(path: worktree.path + "/design/a.html", line: nil, column: nil))
        #expect(LinkOpener.resolve("design/a.html", directory: folder.path, projectDirectory: folder.path) == nil)
    }

    @Test func `the tag says what a click would do`() throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(LinkOpener.preview(of: nil, text: "e2e/missing.spec.ts").action == "Not found")
        #expect(LinkOpener.preview(of: .file(path: folder.path + "/src", line: nil, column: nil), text: "src").kind == .folder)
        #expect(try LinkOpener.preview(of: .url(#require(URL(string: "https://ghostty.org/docs"))), text: "").action == "Open in browser")
    }

    @Test func `a set editor that is gone is named and the file still goes somewhere`() {
        let gone = EditorLocator.choice(configured: "/Users/me/deleted/build/Gloss.app")
        #expect(gone.missing == "Gloss")
        #expect(gone.target?.name == EditorLocator.choice(configured: nil).target?.name)
        #expect(EditorLocator.choice(configured: "dev.calm.no-such-app.\(UUID().uuidString)").missing != nil)
        #expect(EditorLocator.choice(configured: "/no/such/bin/code").missing == "Visual Studio Code")
        #expect(EditorLocator.choice(configured: nil).missing == nil)
    }

    @Test func `an application is found by its bundle ID`() {
        // Finder is on every Mac, wherever macOS keeps it.
        let finder = EditorLocator.choice(configured: "com.apple.finder")
        #expect(finder.missing == nil)
        #expect(finder.target?.name == "Finder")
    }

    @Test func `a missing editor leads the tag`() {
        #expect(LinkOpener.editorDestination(.init(target: nil, missing: "Gloss")) == .missingEditor("Gloss", fallback: nil))
        #expect(LinkOpener.editorDestination(.init(target: nil, missing: nil)) == .defaultApp)
        #expect(EditorLocator.missingName("dev.gloss.Gloss") == "Gloss")
        #expect(EditorLocator.missingName("~/Applications/Nova.app") == "Nova")
        #expect(EditorLocator.missingName("cursor") == "Cursor")
    }
}
