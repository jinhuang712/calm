import Foundation

// The `calm` command-line tool. It will talk to the running app over a local
// socket (see DESIGNS.md → Control protocol); for now it only knows its version.

let version = "0.0.1"
let usage = """
calm \(version) — a minimal macOS terminal that keeps you calm and focused

Usage:
  calm --version    Print the version
  calm --help       Show this help
"""

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "--version", "-v":
    print("calm \(version)")
case nil, "--help", "-h":
    print(usage)
default:
    FileHandle.standardError.write(Data("calm: unknown command '\(arguments.first!)'\n\n\(usage)\n".utf8))
    exit(64)
}
