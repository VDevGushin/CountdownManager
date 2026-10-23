import AppKit
import SwiftUI

struct DesktopDividerGrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DesktopDividerGripView { DesktopDividerGripView() }

    func updateNSView(_ view: DesktopDividerGripView, context: Context) {
        view.refreshSplitView()
    }

    static func dismantleNSView(_ view: DesktopDividerGripView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class DesktopDividerGripView: NSView {
    private weak var splitView: NSSplitView?
    private var resizeObserver: NSObjectProtocol?
    private var dragOffset: CGFloat?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identifier = NSUserInterfaceItemIdentifier("desktop.divider-grip")
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
    }

    var gripRect: NSRect {
        guard let splitView, splitView.window === window, splitView.arrangedSubviews.count == 2 else { return .zero }
        let center = splitView.arrangedSubviews[0].frame.maxX + splitView.dividerThickness / 2
        let nativeRect = NSRect(x: center - 6, y: splitView.bounds.minY, width: 12, height: splitView.bounds.height)
        return convert(nativeRect, from: splitView).intersection(bounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { disconnect() }
        else { refreshSplitView() }
    }

    override func layout() {
        super.layout()
        refreshSplitView()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        refreshSplitView()
        let localPoint = convert(point, from: superview)
        return !isHidden && gripRect.contains(localPoint) ? self : nil
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        let rect = gripRect
        if !rect.isEmpty { addCursorRect(rect, cursor: .resizeLeftRight) }
    }

    override func mouseDown(with event: NSEvent) {
        refreshSplitView()
        guard let splitView, splitView.arrangedSubviews.count == 2,
              gripRect.contains(convert(event.locationInWindow, from: nil)) else { return }
        dragOffset = splitView.convert(event.locationInWindow, from: nil).x - splitView.arrangedSubviews[0].frame.maxX
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragOffset, let splitView, splitView.window === window else { return }
        let position = splitView.convert(event.locationInWindow, from: nil).x - dragOffset
        splitView.setPosition(position, ofDividerAt: 0)
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) { dragOffset = nil }

    func refreshSplitView() {
        guard window != nil else { return }
        if splitView?.window !== window {
            disconnect()
            var ancestor = superview
            while let candidate = ancestor {
                if let split = findSplit(in: candidate) {
                    splitView = split
                    resizeObserver = NotificationCenter.default.addObserver(
                        forName: NSSplitView.didResizeSubviewsNotification, object: split, queue: .main
                    ) { [weak self] _ in
                        MainActor.assumeIsolated {
                            guard let self else { return }
                            self.window?.invalidateCursorRects(for: self)
                        }
                    }
                    window?.invalidateCursorRects(for: self)
                    break
                }
                ancestor = candidate.superview
            }
        }
    }

    func disconnect() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        splitView = nil
        dragOffset = nil
    }

    private func findSplit(in view: NSView) -> NSSplitView? {
        if view === self { return nil }
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 2,
           convert(split.bounds, from: split).intersects(bounds) { return split }
        return view.subviews.lazy.compactMap { self.findSplit(in: $0) }.first
    }
}
