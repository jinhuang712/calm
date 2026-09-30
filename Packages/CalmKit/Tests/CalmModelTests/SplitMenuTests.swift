@testable import CalmModel
import Testing

struct SplitMenuTests {
    @Test func `with two panes the menu has no Unsplit All, which would do what Take Out does`() {
        #expect(SplitMenu.rows(paneCount: 2, zoomed: false) == [.takeOut, .separator, .zoom(zoomed: false), .equalize])
    }

    @Test func `with three or more it offers Unsplit All after Take Out`() {
        for count in [3, 4, 6] {
            #expect(SplitMenu.rows(paneCount: count, zoomed: false) == [
                .takeOut, .unsplitAll, .separator, .zoom(zoomed: false), .equalize,
            ])
        }
    }

    @Test func `a zoomed pane offers the way back`() {
        #expect(SplitMenu.rows(paneCount: 3, zoomed: true).contains(.zoom(zoomed: true)))
        #expect(!SplitMenu.rows(paneCount: 3, zoomed: true).contains(.zoom(zoomed: false)))
    }

    @Test func `leaving comes first`() {
        #expect(SplitMenu.rows(paneCount: 5, zoomed: false).first == .takeOut)
    }
}
