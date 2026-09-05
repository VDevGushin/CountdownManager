import AppKit
import SwiftUI
import Combine

public enum CountdownManagerApplication {
    @MainActor public static func run() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: Store!
    private var subscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        DiagnosticLog.shared.record("app.launch version=\(version) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        MainThreadWatchdog.shared.start()
        store = Store()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Countdown Manager")
        }
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 460)
        popover.contentViewController = NSHostingController(rootView: ManagerView(store: store))
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        updateTitle()
    }

    private func updateTitle() {
        statusItem.button?.title = store.statusTitle
        statusItem.button?.toolTip = store.primary.map { "\($0.title) — \(store.statusTitle)" } ?? "Добавить первый счётчик"
    }

    @objc private func togglePopover() {
        if popover.isShown {
            DiagnosticLog.shared.record("popover.close")
            popover.performClose(nil)
            return
        }
        DiagnosticLog.shared.record("popover.open")
        store.refresh()
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainThreadWatchdog.shared.stop()
        DiagnosticLog.shared.record("app.terminate")
        DiagnosticLog.shared.flush()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !popover.isShown { togglePopover() }
        return true
    }
}
