import AppKit
import SwiftUI

/// A scroll view's numbers, in points: how far it has scrolled, how tall its window and its content are.
struct ScrollMetrics: Equatable, Sendable {
    var offset: CGFloat
    var viewport: CGFloat
    var content: CGFloat
}

@available(macOS 15, *)
extension ScrollMetrics {
    init(_ geometry: ScrollGeometry) {
        self.init(offset: geometry.contentOffset.y, viewport: geometry.containerSize.height, content: geometry.contentSize.height)
    }
}

/// Scrolls a list from code. SwiftUI's `ScrollPosition` and `onScrollGeometryChange` need macOS 15,
/// so on macOS 14 these two modifiers read and move the list's own `NSScrollView` instead. From
/// macOS 15 on they are the SwiftUI calls themselves, so the newer systems behave as they always did.
@MainActor
final class ScrollDriver {
    fileprivate var toY: ((CGFloat) -> Void)?
    fileprivate var toTop: (() -> Void)?

    func scroll(toY y: CGFloat) {
        toY?(y)
    }

    func scrollToTop() {
        toTop?()
    }
}

extension View {
    /// Calls `perform` when `transform` of the scroll view's numbers changes (not on every scroll
    /// step, unless the transform keeps the offset). Apply it to the `ScrollView` itself.
    func onScrollChange<Value: Equatable & Sendable>(
        of transform: @escaping @Sendable (ScrollMetrics) -> Value, perform: @escaping (Value) -> Void,
    ) -> some View {
        modifier(ScrollChange(transform: transform, perform: perform))
    }

    /// Lets `driver` scroll this `ScrollView`.
    func scrollDriver(_ driver: ScrollDriver) -> some View {
        modifier(ScrollDriving(driver: driver))
    }
}

private struct ScrollChange<Value: Equatable & Sendable>: ViewModifier {
    let transform: @Sendable (ScrollMetrics) -> Value
    let perform: (Value) -> Void
    @State private var last = Last()

    private final class Last {
        var value: Value?
    }

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Value.self) { transform(ScrollMetrics($0)) } action: { _, new in
                perform(new)
            }
        } else {
            content.background(ScrollProbe(driver: nil) { metrics in
                let value = transform(metrics)
                guard last.value != value else { return }
                last.value = value
                perform(value)
            })
        }
    }
}

private struct ScrollDriving: ViewModifier {
    let driver: ScrollDriver

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.modifier(ModernScrollDriving(driver: driver))
        } else {
            content.background(ScrollProbe(driver: driver, report: nil))
        }
    }
}

@available(macOS 15, *)
private struct ModernScrollDriving: ViewModifier {
    let driver: ScrollDriver
    @State private var position = ScrollPosition()

    func body(content: Content) -> some View {
        content
            .scrollPosition($position)
            .onAppear {
                let position = $position
                driver.toY = { position.wrappedValue.scrollTo(y: $0) }
                driver.toTop = { position.wrappedValue.scrollTo(edge: .top) }
            }
    }
}

/// An invisible view beside a `ScrollView` (macOS 14): it finds the `NSScrollView` next to it, and
/// reports its numbers or scrolls it.
private struct ScrollProbe: NSViewRepresentable {
    let driver: ScrollDriver?
    let report: ((ScrollMetrics) -> Void)?

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.driver = driver
        view.report = report
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        // The closure captures the view's current state, so take the newest each time.
        view.report = report
    }
}

private final class ProbeView: NSView {
    var driver: ScrollDriver?
    var report: ((ScrollMetrics) -> Void)?
    private weak var scrollView: NSScrollView?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            detach()
        } else {
            needsLayout = true
        }
    }

    /// SwiftUI may add the `NSScrollView` after this view, so look again at each layout until found.
    override func layout() {
        super.layout()
        if scrollView == nil, window != nil {
            attach()
        }
    }

    private func attach() {
        guard let found = findScrollView(), let document = found.documentView else { return }
        scrollView = found
        let clip = found.contentView
        // Both are off by default: they are what tells us the list moved or its content grew.
        clip.postsBoundsChangedNotifications = true
        document.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        for (name, object) in [(NSView.boundsDidChangeNotification, clip), (NSView.frameDidChangeNotification, document)] {
            observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportMetrics() }
            })
        }
        driver?.toY = { [weak self] in self?.scroll(toY: $0) }
        driver?.toTop = { [weak self] in self?.scroll(toY: 0) }
        reportMetrics()
    }

    private func detach() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scrollView = nil
    }

    /// The nearest `NSScrollView` beside this view: the shallowest one under the closest ancestor that has any.
    private func findScrollView() -> NSScrollView? {
        var ancestor = superview
        while let current = ancestor {
            var queue = current.subviews.filter { $0 !== self }
            while !queue.isEmpty {
                let view = queue.removeFirst()
                if let scroll = view as? NSScrollView {
                    return scroll
                }
                queue.append(contentsOf: view.subviews)
            }
            ancestor = current.superview
        }
        return nil
    }

    private func reportMetrics() {
        guard let report, let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let content = document.frame.height
        let viewport = clip.bounds.height
        // SwiftUI's document view is flipped (origin at the top); count from the top either way.
        let offset = document.isFlipped ? clip.bounds.origin.y : content - viewport - clip.bounds.origin.y
        report(ScrollMetrics(offset: offset, viewport: viewport, content: content))
    }

    private func scroll(toY y: CGFloat) {
        guard let scrollView, let document = scrollView.documentView else { return }
        let clip = scrollView.contentView
        let furthest = max(document.frame.height - clip.bounds.height, 0)
        let clamped = min(max(y, 0), furthest)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: document.isFlipped ? clamped : furthest - clamped))
        scrollView.reflectScrolledClipView(clip)
    }
}
