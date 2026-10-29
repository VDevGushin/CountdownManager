import AppKit
import SwiftUI

/// Read-only sheets must let Sparkle's quit event reach the application's restart-safety guard.
struct DesktopSheetTerminationPolicy: NSViewRepresentable {
    let preventsTermination: Bool

    func makeNSView(context: Context) -> DesktopSheetTerminationView {
        let view = DesktopSheetTerminationView()
        view.preventsTermination = preventsTermination
        return view
    }

    func updateNSView(_ view: DesktopSheetTerminationView, context: Context) {
        view.preventsTermination = preventsTermination
    }
}

@MainActor
final class DesktopSheetTerminationView: NSView {
    var preventsTermination = true {
        didSet { applyPolicy() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPolicy()
    }

    private func applyPolicy() {
        window?.preventsApplicationTerminationWhenModal = preventsTermination
    }
}
