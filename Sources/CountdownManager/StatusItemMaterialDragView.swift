import AppKit

/// The icon opens the chooser during a drag; only a concrete event accepts the drop.
@MainActor
final class StatusItemMaterialDragView: NSView {
    var revealPanel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes(materialDropTypes.map { NSPasteboard.PasteboardType($0.identifier) })
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        // Let the original NSButton own tracking, highlighting and its existing action.
        (superview as? NSStatusBarButton)?.mouseDown(with: event)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        revealPanel?()
        return []
    }
}
