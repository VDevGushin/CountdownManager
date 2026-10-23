import AppKit
import SwiftUI

@MainActor
final class DesktopWindowController: NSWindowController, NSWindowDelegate {
    private let hostingController: NSHostingController<DesktopRootView>
    private let editorSession: EventEditorSession

    init(rootView: DesktopRootView, editorSession: EventEditorSession) {
        self.editorSession = editorSession
        hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1140, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Countdown Manager"
        window.identifier = NSUserInterfaceItemIdentifier("desktop.window")
        window.contentMinSize = NSSize(width: 960, height: 640)
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        super.init(window: window)
        window.delegate = self
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        if NSApp.activationPolicy() != .regular {
            let changedPolicy = NSApp.setActivationPolicy(.regular)
            DiagnosticLog.shared.record("desktop.promote regular-policy=\(changedPolicy)")
        }
        DiagnosticLog.shared.record("desktop.show")
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        guard !editorSession.desktopIsPresented else { return }
        window?.close()
    }

    func hideForPanel() -> Bool {
        guard !editorSession.desktopIsPresented, let window, window.attachedSheet == nil else { return false }
        window.orderOut(nil)
        DiagnosticLog.shared.record("desktop.hide-for-panel")
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !editorSession.desktopIsPresented
    }

    func windowWillClose(_ notification: Notification) {
        DiagnosticLog.shared.record("desktop.close")
    }
}
