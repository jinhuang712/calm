import CalmControl
import Foundation

/// `calm screenshot [<file>]`: saves a PNG of Calm's window and prints where it went (CLI.md).
/// Calm renders the window itself and sends the PNG back, so the file is written with this shell's
/// own permissions and nothing needs Screen Recording. It never starts Calm: with Calm not
/// running there is no window to capture.
enum ScreenshotCommand {
    static let usage = "calm screenshot [<file>]"

    static func run(_ words: [String]) -> Never {
        guard words.count <= 1, !(words.first?.hasPrefix("--") ?? false) else { fail(usage, code: 64) }
        let target = ScreenshotFile.path(argument: words.first, directory: FileManager.default.currentDirectoryPath)
        let response: ControlResponse
        do {
            // Drawing and encoding a large window takes a moment, and the reply is megabytes.
            response = try ControlClient.send(ControlRequest(cmd: .screenshot), timeout: 10)
        } catch {
            fail("\(error)")
        }
        guard response.ok else {
            // A Calm from before `screenshot` can't read the request at all.
            fail(response.error == "Couldn't read the request."
                ? "This Calm is older than the calm command and can't take screenshots: Calm → Restart Calm."
                : response.error ?? "Calm didn't take it")
        }
        guard let png = ScreenshotFile.png(fromBase64: response.image) else { fail("Calm sent no picture") }
        do {
            try png.write(to: URL(fileURLWithPath: target))
        } catch {
            fail("couldn't write \(target): \(error.localizedDescription)")
        }
        print(target)
        exit(0)
    }
}
