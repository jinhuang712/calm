@testable import Calm
import Foundation
import Testing

@MainActor
struct ArrivalCardTests {
    let now = Date()

    @Test func `with the sidebar showing, arriving never shows the card on its own`() {
        #expect(!ArrivalCard.shouldShow(activity: now, leftAt: nil, sidebarShown: true))
        #expect(!ArrivalCard.shouldShow(activity: now, leftAt: now.addingTimeInterval(-60), sidebarShown: true))
    }

    @Test func `with the sidebar hidden, only news since the user left shows it`() {
        #expect(ArrivalCard.shouldShow(activity: now, leftAt: nil, sidebarShown: false)) // not seen since launch
        #expect(ArrivalCard.shouldShow(activity: now, leftAt: now.addingTimeInterval(-60), sidebarShown: false))
        #expect(!ArrivalCard.shouldShow(activity: now.addingTimeInterval(-120), leftAt: now.addingTimeInterval(-60), sidebarShown: false))
    }
}
