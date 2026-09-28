import Foundation

/// libghostty queues a "child exited" report by surface address; after a free, the next
/// surface can sit at that address and receive a report meant for the one before it.
extension TerminalSurfaceView {
    /// Whether a "child exited" report can belong to this pane: its process can't have run
    /// longer than the pane has existed. One that did was meant for an earlier surface.
    func ownsChildExit(runtime milliseconds: UInt64) -> Bool {
        Self.childExit(runtime: milliseconds, fitsPaneAged: Date().timeIntervalSince(createdAt))
    }

    /// A second of slack: the process starts a moment after the pane, never before it.
    static func childExit(runtime milliseconds: UInt64, fitsPaneAged age: TimeInterval) -> Bool {
        Double(milliseconds) / 1000 <= age + 1
    }
}
