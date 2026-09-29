@testable import CalmModel
import Foundation
import Testing

struct AttentionQueueTests {
    private let start = Date(timeIntervalSince1970: 1000)
    private let session = UUID()

    private func at(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    @Test func `delivered at once when the user isn't typing`() {
        var queue = AttentionQueue()
        queue.enqueue(session, message: "Allow edit?", at: at(0))
        #expect(queue.takeDue(at: at(0)).map(\.message) == ["Allow edit?"])
        #expect(queue.pending.isEmpty)
    }

    @Test func `held while typing, delivered at the pause`() {
        var queue = AttentionQueue()
        queue.noteTyping(at: at(0))
        queue.enqueue(session, message: "Allow edit?", at: at(0.5))
        queue.noteTyping(at: at(1))
        #expect(queue.takeDue(at: at(2)).isEmpty)
        queue.noteTyping(at: at(2.5))
        #expect(queue.takeDue(at: at(4)).isEmpty)
        #expect(queue.takeDue(at: at(5.5)).count == 1)
    }

    @Test func `a focus change is a pause`() {
        var queue = AttentionQueue()
        queue.noteTyping(at: at(0))
        queue.enqueue(session, message: "Allow edit?", at: at(0.5))
        queue.noteTyping(at: at(1))
        queue.noteFocusChange(at: at(1.2))
        #expect(queue.takeDue(at: at(1.3)).count == 1)
    }

    @Test func `never held longer than the maximum wait`() {
        var queue = AttentionQueue()
        queue.enqueue(session, message: "Allow edit?", at: at(0))
        for second in stride(from: 0.0, through: 59, by: 1) {
            queue.noteTyping(at: at(second))
            #expect(queue.takeDue(at: at(second)).isEmpty)
        }
        queue.noteTyping(at: at(60))
        #expect(queue.takeDue(at: at(60)).count == 1)
    }

    @Test func `the state waits in the queue with its message`() {
        var queue = AttentionQueue()
        queue.enqueue(session, message: nil, state: .failed, at: at(0))
        queue.enqueue(UUID(), message: "Hello", at: at(0))
        let items = queue.takeDue(at: at(0))
        #expect(items.map(\.state) == [.failed, nil])
        #expect(items.map(\.message) == [nil, "Hello"])
    }

    @Test func `withdrawn when visited, and one per session`() {
        var queue = AttentionQueue()
        queue.noteTyping(at: at(0))
        queue.enqueue(session, message: "Allow edit?", at: at(0))
        queue.enqueue(session, message: "Allow bash?", at: at(1))
        #expect(queue.pending.map(\.message) == ["Allow bash?"])
        queue.withdraw(session)
        #expect(queue.takeDue(at: at(100)).isEmpty)
    }
}
