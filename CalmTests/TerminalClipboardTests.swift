import AppKit
@testable import Calm
import Foundation
import Testing

@MainActor
struct TerminalClipboardTests {
    /// A private pasteboard, so tests never touch the user's clipboard.
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: NSPasteboard.Name("calm-tests-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    private func folder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("calm-tests-\(UUID().uuidString)")
    }

    private func tinyImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()
        return image
    }

    @Test func `text pastes as text`() {
        let board = pasteboard()
        board.setString("hello", forType: .string)
        #expect(TerminalClipboard.plainText(from: board, imageFolder: folder()) == "hello")
    }

    @Test func `an image alone pastes as the path of a saved png`() throws {
        let board = pasteboard()
        board.writeObjects([tinyImage()]) // TIFF, as many apps copy images
        let dir = folder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let path = try #require(TerminalClipboard.plainText(from: board, imageFolder: dir))
        #expect(path.hasPrefix(dir.path))
        #expect(path.hasSuffix(".png"))
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47])) // PNG signature
    }

    @Test func `text next to an image wins`() {
        let board = pasteboard()
        board.writeObjects([tinyImage()])
        board.setString("caption", forType: .string)
        let dir = folder()
        #expect(TerminalClipboard.plainText(from: board, imageFolder: dir) == "caption")
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func `an empty clipboard pastes nothing`() {
        #expect(TerminalClipboard.plainText(from: pasteboard(), imageFolder: folder()) == nil)
    }
}
