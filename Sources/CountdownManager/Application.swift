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
private final class CountdownUtilityWindow: NSWindow {
    // AppKit's default for a borderless window is false. This retained utility
    // window must still accept normal SwiftUI controls and text input.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var window: NSWindow!
    private var hostingController: NSHostingController<ManagerView>!
    private var store: Store!
    private var subscription: AnyCancellable?
    private var uiSmokeRuntime: UISmokeRuntime?
    private var activeSpaceObserver: NSObjectProtocol?
    private var isPresentingWindow = false

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
            button.action = #selector(toggleWindow)
            button.setAccessibilityLabel("Countdown Manager")
        }
        hostingController = NSHostingController(rootView: ManagerView(store: store))
        window = CountdownUtilityWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 540),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Countdown Manager"
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenNone])
        window.identifier = NSUserInterfaceItemIdentifier("main.window")
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        // Visibility is owned by application and Space lifecycle callbacks.
        // Native automatic hiding here can race the status item's explicit Show.
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.delegate = self
        window.contentViewController = hostingController
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 12
        hostingController.view.layer?.masksToBounds = true
        window.center()
        recordShellLifecycle("launch-ready")
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activeSpaceDidChange()
            }
        }
        installApplicationMenu()
        subscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateTitle() }
        }
        updateTitle()
        if let uiSmokeConfiguration, UISmokeConfiguration.wasRequested {
            uiSmokeRuntime = UISmokeRuntime(
                configuration: uiSmokeConfiguration,
                store: store,
                window: { [weak self] in self?.window },
                showWindow: { [weak self] in self?.showWindow() },
                pressStatusItem: { [weak self] in self?.statusItem.button?.performClick(nil) }
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showWindow()
                self?.uiSmokeRuntime?.start()
            }
        } else if uiSmokeConfiguration != nil, UISmokeConfiguration.xcuiTestWasRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showWindow()
            }
        }
    }

    private func updateTitle() {
        statusItem.button?.title = store.statusTitle
        statusItem.button?.toolTip = store.primary == nil ? "Добавить событие" : store.statusTitle
    }

    @objc private func toggleWindow() {
        let intent = window.isVisible ? "hide" : "show"
        recordShellLifecycle("status-action intent=\(intent)")
        if window.isVisible {
            hideWindow(source: "status-action")
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        recordShellLifecycle("show-begin")
        store.refresh()
        // If the retained window is still visible on another Space, hide it
        // before application activation. Otherwise activation can switch to the
        // window's old Space before moveToActiveSpace gets a chance to apply.
        if window.isVisible && !window.isOnActiveSpace {
            recordShellLifecycle("order-out source=pre-show-active-space")
            window.orderOut(nil)
        }
        isPresentingWindow = true
        NSApp.activate(ignoringOtherApps: true)
        recordShellLifecycle("show-after-activate")
        window.makeKeyAndOrderFront(nil)
        recordShellLifecycle("show-after-order-front")
        completeWindowPresentationIfReady()
    }

    private func hideWindow(source: String) {
        isPresentingWindow = false
        recordShellLifecycle("order-out source=\(source)")
        window.orderOut(nil)
    }

    @objc private func hideWindowFromCommand() {
        hideWindow(source: "command-w")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hideWindow(source: "window-close")
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        recordShellLifecycle("occlusion-change")
    }

    func windowDidBecomeKey(_ notification: Notification) {
        recordShellLifecycle("window-did-become-key")
        completeWindowPresentationIfReady()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        recordShellLifecycle("application-did-become-active")
        completeWindowPresentationIfReady()
    }

    func applicationDidResignActive(_ notification: Notification) {
        recordShellLifecycle("application-did-resign-active")
        guard !UISmokeConfiguration.isolatedTestEnvironmentWasRequested,
              !isPresentingWindow,
              window.isVisible else { return }
        hideWindow(source: "application-deactivation")
    }

    private func activeSpaceDidChange() {
        recordShellLifecycle("active-space-did-change")
        guard !UISmokeConfiguration.isolatedTestEnvironmentWasRequested,
              !isPresentingWindow,
              window.isVisible else { return }
        hideWindow(source: "active-space-change")
    }

    private func completeWindowPresentationIfReady() {
        guard isPresentingWindow,
              NSApp.isActive,
              window.isVisible,
              window.isKeyWindow else { return }
        isPresentingWindow = false
        recordShellLifecycle("show-presentation-ended")
    }

    private func recordShellLifecycle(_ event: String) {
        let occlusion = window?.occlusionState.rawValue ?? 0
        DiagnosticLog.shared.record(
            "shell.lifecycle event=\(event) appActive=\(NSApp.isActive) "
                + "visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false) "
                + "onActiveSpace=\(window?.isOnActiveSpace ?? false) "
                + "occlusion=\(occlusion) presenting=\(isPresentingWindow)"
        )
    }

    // Standard responder-chain commands keep native text editing and Cmd-W available
    // in an accessory application without an automatically generated main menu.
    private func installApplicationMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Выйти из Countdown Manager", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editMenu = NSMenu(title: "Правка")
        for (title, action, key) in [
            ("Отменить", Selector(("undo:")), "z"),
            ("Вырезать", #selector(NSText.cut(_:)), "x"),
            ("Копировать", #selector(NSText.copy(_:)), "c"),
            ("Вставить", #selector(NSText.paste(_:)), "v"),
            ("Выбрать всё", #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowMenu = NSMenu(title: "Окно")
        let closeItem = NSMenuItem(
            title: "Закрыть",
            action: #selector(hideWindowFromCommand),
            keyEquivalent: "w"
        )
        closeItem.target = self
        windowMenu.addItem(closeItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
        MainThreadWatchdog.shared.stop()
        DiagnosticLog.shared.record("app.terminate")
        DiagnosticLog.shared.flush()
    }

}
