@testable import CalmModel
import Foundation
import Testing

struct WrittenTimeTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func ago(_ seconds: TimeInterval) -> String {
        WrittenTime.text(since: now.addingTimeInterval(-seconds), now: now)
    }

    @Test func `times are written out`() {
        #expect(ago(20) == "just now")
        #expect(ago(-5) == "just now") // a clock a little ahead
        #expect(ago(60) == "1 minute ago")
        #expect(ago(4 * 60) == "4 minutes ago")
        #expect(ago(3600) == "1 hour ago")
        #expect(ago(5 * 3600 + 59) == "5 hours ago")
        #expect(ago(30 * 3600) == "yesterday")
        #expect(ago(3 * 86400) == "3 days ago")
        // Past a week, the date.
        let date = now.addingTimeInterval(-20 * 86400)
        #expect(ago(20 * 86400) == date.formatted(.dateTime.month(.abbreviated).day()))
    }

    @Test func `figures are runs of their own`() {
        #expect(WrittenTime.runs("4 minutes ago") == [
            WrittenTime.Run(text: "4", isNumber: true), WrittenTime.Run(text: " minutes ago", isNumber: false),
        ])
        #expect(WrittenTime.runs("yesterday") == [WrittenTime.Run(text: "yesterday", isNumber: false)])
        #expect(WrittenTime.runs("Sep 16").map(\.isNumber) == [false, true])
    }
}
