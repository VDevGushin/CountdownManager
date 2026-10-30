import AppKit
import SwiftUI

/// Native draft editing preserves complete input; length validation belongs to Save.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let focusRequest: Int
    @Environment(\.isEnabled) private var isEnabled

    final class Coordinator {
        var lastFocusRequest = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 70))
        scroll.borderType = .bezelBorder
        scroll.focusRingType = .exterior
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        let editor = NoteTextView(frame: NSRect(origin: .zero, size: scroll.contentSize))
        editor.font = .systemFont(ofSize: 13)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 4, height: 6)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityIdentifier("editor.note")
        editor.setAccessibilityLabel("Заметка · необязательно")
        editor.setAccessibilityPlaceholderValue(NoteTextView.placeholder)
        scroll.documentView = editor
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? NoteTextView else { return }
        editor.isEditable = isEnabled
        editor.isSelectable = isEnabled
        editor.onChange = { text = $0 }
        // Do not rewrite native storage during typing/composition: selection and undo belong to AppKit.
        if !editor.hasMarkedText(), editor.string != text {
            editor.string = text
            editor.needsDisplay = true
        }
        let requestFocus = focusRequest != context.coordinator.lastFocusRequest
        context.coordinator.lastFocusRequest = focusRequest
        if requestFocus, isEnabled, let window = editor.window, window.firstResponder !== editor {
            window.makeFirstResponder(editor)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        let width = proposal.width ?? 320
        let font = NSFont.systemFont(ofSize: 13)
        let line = ceil(font.ascender - font.descender + font.leading)
        let content = text.isEmpty || text.hasSuffix("\n") ? text + " " : text
        let measured = (content as NSString).boundingRect(
            with: NSSize(width: max(1, width - 22), height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]
        ).height
        return CGSize(width: width, height: ceil(min(line * 6, max(line * 3, measured))) + 16)
    }
}

final class NoteTextView: NSTextView {
    static let placeholder = "Пара слов о событии"
    var onChange: ((String) -> Void)?
    private var marking = false

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (Self.placeholder as NSString).draw(
                at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
            )
        }
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        if !marking, !hasMarkedText() { onChange?(string) }
    }

    override func setMarkedText(_ value: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marking = true
        super.setMarkedText(value, selectedRange: selectedRange, replacementRange: replacementRange)
        marking = false
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        super.insertText(insertString, replacementRange: replacementRange)
        if !marking, !hasMarkedText() { onChange?(string) }
    }

    override func unmarkText() {
        super.unmarkText()
        if !marking { onChange?(string) }
    }
}
