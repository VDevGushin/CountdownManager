import AppKit
import SwiftUI

/// Plain native text editing: limits are checked before a committed replacement, never by truncation.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    let maximumLength: Int
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
        editor.maximumLength = maximumLength
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
    var maximumLength = 150
    var onChange: ((String) -> Void)?
    private var marking = false
    private var composition: (replacedText: String, selection: NSRange)?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if string.isEmpty {
            (Self.placeholder as NSString).draw(
                at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height),
                withAttributes: [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
            )
        }
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if !marking, let replacementString {
            guard affectedCharRange.location <= (string as NSString).length,
                  NSMaxRange(affectedCharRange) <= (string as NSString).length else { return false }
            let candidate = (string as NSString).replacingCharacters(in: affectedCharRange, with: replacementString)
            guard candidate.count <= maximumLength else { return false }
        }
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        if !marking, !hasMarkedText() { onChange?(string) }
    }

    override func setMarkedText(_ value: Any, selectedRange: NSRange, replacementRange: NSRange) {
        if composition == nil {
            let range = replacementRange.location == NSNotFound ? self.selectedRange() : replacementRange
            composition = ((string as NSString).substring(with: range), self.selectedRange())
        }
        marking = true
        super.setMarkedText(value, selectedRange: selectedRange, replacementRange: replacementRange)
        marking = false
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let composition, hasMarkedText() {
            let value = (insertString as? NSAttributedString)?.string ?? (insertString as? String ?? "")
            let range = replacementRange.location == NSNotFound ? markedRange() : replacementRange
            let candidate = (string as NSString).replacingCharacters(in: range, with: value)
            if candidate.count > maximumLength {
                restoreComposition(composition)
                return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
        if !hasMarkedText() { composition = nil }
    }

    override func unmarkText() {
        if marking { super.unmarkText(); return }
        if let composition, string.count > maximumLength {
            restoreComposition(composition)
            return
        }
        super.unmarkText()
        composition = nil
        onChange?(string)
    }

    private func restoreComposition(_ original: (replacedText: String, selection: NSRange)) {
        marking = true
        composition = nil
        super.insertText(original.replacedText, replacementRange: markedRange())
        super.unmarkText()
        marking = false
        composition = nil
        setSelectedRange(original.selection)
        onChange?(string)
    }
}
