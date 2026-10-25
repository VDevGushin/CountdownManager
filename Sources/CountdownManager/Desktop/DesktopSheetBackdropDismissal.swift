import AppKit
import SwiftUI

struct DesktopSheetBackdropDismissal: NSViewRepresentable {
    let isEnabled: Bool
    let dismiss: () -> Void

    func makeNSView(context: Context) -> DesktopSheetBackdropView {
        let view = DesktopSheetBackdropView()
        view.isEnabled = isEnabled
        view.dismiss = dismiss
        return view
    }

    func updateNSView(_ view: DesktopSheetBackdropView, context: Context) {
        view.isEnabled = isEnabled
        view.dismiss = dismiss
    }

    static func dismantleNSView(_ view: DesktopSheetBackdropView, coordinator: ()) {
        view.disconnect()
    }
}

@MainActor
final class DesktopSheetBackdropView: NSView {
    var isEnabled = false
    var dismiss: (() -> Void)?
    private var eventMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    convenience init() { self.init(frame: .zero) }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        disconnect()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                self?.consume(event) ?? false
            }
            return consumed ? nil : event
        }
    }

    func disconnect() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func consume(_ event: NSEvent) -> Bool {
        guard isEnabled, let sheet = window, let parent = sheet.sheetParent,
              parent.attachedSheet === sheet, sheet.attachedSheet == nil,
              event.window === parent, let contentView = parent.contentView,
              contentView.bounds.contains(contentView.convert(event.locationInWindow, from: nil)) else { return false }
        isEnabled = false
        dismiss?()
        return true
    }
}
