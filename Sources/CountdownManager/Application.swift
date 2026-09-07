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
private final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var store: Store!
    private var subscription: AnyCancellable?
    private var uiSmokeRuntime: UISmokeRuntime?
    private var sheetEndObserver: NSObjectProtocol?
    private var isAwaitingQuickSubtaskSheetEnd = false
    private var quickSubtaskSheetRestorationRevision = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        let uiSmokeConfiguration: UISmokeConfiguration?
        do {
            uiSmokeConfiguration = try UISmokeConfiguration.load()
        } catch {
            fputs("UISmoke refused to start: \(error.localizedDescription)\n", stderr)
            Darwin.exit(64)
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        DiagnosticLog.shared.record("app.launch version=\(version) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        MainThreadWatchdog.shared.start()
        store = Store(
            fileURL: uiSmokeConfiguration?.dataURL,
            disclosureDefaults: uiSmokeConfiguration?.defaults ?? .standard
        )
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Countdown Manager")
        }
        popover = NSPopover()
        popover.delegate = self
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 390, height: 540)
        sheetEndObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEndSheetNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.quickSubtaskSheetDidEnd(parentWindow: notification.object as? NSWindow)
            }
        }
        resetTransientSession()
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        updateTitle()
        if let uiSmokeConfiguration {
            uiSmokeRuntime = UISmokeRuntime(
                configuration: uiSmokeConfiguration,
                store: store,
                window: { [weak self] in self?.popover.contentViewController?.view.window },
                closePopover: { [weak self] in self?.closePopover() },
                openPopover: { [weak self] in self?.showPopover() },
                pressStatusItem: { [weak self] in self?.statusItem.button?.performClick(nil) },
                isTransientPopoverReady: { [weak self] in self?.isTransientPopoverReady() ?? false },
                quickSubtaskSheetRestorationRevision: { [weak self] in
                    self?.quickSubtaskSheetRestorationRevision ?? 0
                }
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPopover()
                self?.uiSmokeRuntime?.start()
            }
        }
    }

    private func updateTitle() {
        statusItem.button?.title = store.statusTitle
        statusItem.button?.toolTip = store.primary == nil ? "Добавить событие" : store.statusTitle
    }

    @objc private func togglePopover() {
        if popover.isShown {
            DiagnosticLog.shared.record("popover.close")
            closePopover()
            return
        }
        DiagnosticLog.shared.record("popover.open")
        store.refresh()
        showPopover()
    }

    private func showPopover() {
        guard !popover.isShown else { return }
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let window = popover.contentViewController?.view.window {
            window.makeKey()
            window.makeFirstResponder(window.contentView)
        }
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.close()
    }

    func popoverDidClose(_ notification: Notification) {
        DiagnosticLog.shared.record("popover.closed session=reset")
        isAwaitingQuickSubtaskSheetEnd = false
        resetTransientSession()
    }

    private func resetTransientSession() {
        if UISmokeConfiguration.wasRequested {
            UISmokeControlRegistry.shared.reset()
        }
        popover.contentViewController = NSHostingController(
            rootView: ManagerView(
                store: store,
                transientDidDismiss: { [weak self] in
                    self?.restoreTransientPopoverInteraction()
                },
                quickSubtaskWillPresent: { [weak self] in
                    self?.isAwaitingQuickSubtaskSheetEnd = true
                }
            )
        )
    }

    private func quickSubtaskSheetDidEnd(parentWindow: NSWindow?) {
        guard isAwaitingQuickSubtaskSheetEnd,
              parentWindow === popover.contentViewController?.view.window else { return }
        isAwaitingQuickSubtaskSheetEnd = false
        restoreTransientPopoverInteraction { [weak self] in
            self?.quickSubtaskSheetRestorationRevision += 1
        }
    }

    private func restoreTransientPopoverInteraction(completion: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown,
                  let window = self.popover.contentViewController?.view.window else { return }
            self.popover.behavior = .transient
            window.makeKey()
            window.makeFirstResponder(window.contentView)
            completion?()
        }
    }

    private func isTransientPopoverReady() -> Bool {
        guard popover.isShown,
              popover.behavior == .transient,
              NSApp.modalWindow == nil,
              let window = popover.contentViewController?.view.window,
              window.attachedSheet == nil else { return false }
        return window.firstResponder === window.contentView
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
