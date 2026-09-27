@testable import Calm
import Testing

struct CalmWindowTests {
    @Test func `a title bar double-click does what System Settings says, Zoom when unset`() {
        #expect(TitleBarDoubleClick(setting: nil) == .zoom)
        #expect(TitleBarDoubleClick(setting: "Maximize") == .zoom)
        #expect(TitleBarDoubleClick(setting: "Fill") == .fill)
        #expect(TitleBarDoubleClick(setting: "Minimize") == .minimize)
        #expect(TitleBarDoubleClick(setting: "None") == .nothing)
        #expect(TitleBarDoubleClick(setting: "something new") == .zoom)
    }
}
