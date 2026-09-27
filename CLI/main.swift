import CalmControl
import Foundation

// The `calm` command-line tool: talks to the running app over its local socket
// (see DESIGNS.md → Control protocol).

let version = "0.0.1"
let usage = """
calm \(version) — a minimal macOS terminal that keeps you calm and focused

Usage:
  calm open <folder>    Add the folder as a project and open a session in it
  calm list             List sessions
  calm --version        Print the version
  calm --help           Show this help
"""

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("calm: \(message)\n".utf8))
    exit(code)
}

/// Sends a request, starting Calm first if it isn't running.
func send(_ request: ControlRequest) -> ControlResponse {
    do {
        return try ControlClient.send(request)
    } catch ControlClient.ClientError.notRunning {
        let launcher = Process()
        launcher.executableURL = URL(filePath: "/usr/bin/open")
        launcher.arguments = ["-g", "-b", "com.jinhuang.calm"]
        try? launcher.run()
        launcher.waitUntilExit()
        for _ in 0 ..< 50 {
            usleep(100_000)
            if let response = try? ControlClient.send(request) {
                return response
            }
        }
        fail("Calm didn't start.")
    } catch {
        fail("\(error)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "--version", "-v":
    print("calm \(version)")
case nil, "--help", "-h", "help":
    print(usage)
case "list", "ls":
    let response = send(ControlRequest(cmd: .list))
    guard response.ok else { fail(response.error ?? "failed") }
    for session in response.sessions ?? [] {
        print("\(session.project)\t\(session.title)\t\(session.state)\t\(session.directory)")
    }
case "open":
    let target = arguments.count > 1 ? arguments[1] : FileManager.default.currentDirectoryPath
    let absolute = target.hasPrefix("/") || target.hasPrefix("~")
        ? target
        : (FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(target)
    let response = send(ControlRequest(cmd: .open, path: absolute))
    guard response.ok else { fail(response.error ?? "failed") }
default:
    fail("unknown command '\(arguments[0])'\n\n\(usage)", code: 64)
}
