import AppKit
import Combine
import QuartzCore
import SwiftUI

package let timerAttentionAnimationKey = "countdown.timer.attention"

package func makeTimerAttentionAnimation(reduceMotion: Bool) -> CAAnimation {
    if reduceMotion {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.65
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        return pulse
    }

    let shake = CAKeyframeAnimation(keyPath: "transform.rotation.z")
    shake.values = [0, -0.16, 0.16, -0.12, 0.12, 0]
    shake.keyTimes = [0, 0.2, 0.4, 0.6, 0.8, 1]
    shake.duration = 0.72
    shake.repeatCount = .greatestFiniteMagnitude
    return shake
}

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
private final class CountdownStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var panel: CountdownStatusPanel!
    private var hostingController: NSHostingController<CountdownManagerRootView>!
    private var store: Store!
    private var timer: CountdownTimer!
    private var subscription: AnyCancellable?
    private var timerCompletionSubscription: AnyCancellable?
    private let timerCompletionAlert = TimerCompletionAlertPresenter()
    private var uiSmokeRuntime: UISmokeRuntime?
    private var activeSpaceObserver: NSObjectProtocol?
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var isPanelRequestedVisible = false

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
        let defaults = uiSmokeConfiguration?.defaults ?? .standard
        store = Store(
            fileURL: uiSmokeConfiguration?.dataURL,
            disclosureDefaults: defaults
        )
        timer = CountdownTimer(defaults: defaults)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePanel)
            button.setAccessibilityLabel("Countdown Manager")
        }
        hostingController = NSHostingController(
            rootView: CountdownManagerRootView(timer: timer, store: store)
        )
        panel = CountdownStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Countdown Manager"
        panel.identifier = NSUserInterfaceItemIdentifier("main.panel")
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .transient, .ignoresCycle, .fullScreenNone]
        panel.delegate = self
        panel.contentViewController = hostingController
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 12
        hostingController.view.layer?.masksToBounds = true
        recordShellLifecycle("launch-ready")
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.activeSpaceDidChange()
            }
        }
        accessibilityDisplayObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.restartTimerAttentionAnimation()
            }
        }
        installApplicationMenu()
        subscription = Publishers.Merge(store.objectWillChange, timer.objectWillChange)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateTitle() }
            }
        timerCompletionSubscription = timer.completionPublisher
            .sink { [weak self] in
                self?.timerCompletionAlert.present()
            }
        updateTitle()
        if let uiSmokeConfiguration, UISmokeConfiguration.wasRequested {
            uiSmokeRuntime = UISmokeRuntime(
                configuration: uiSmokeConfiguration,
                store: store,
                window: { [weak self] in self?.panel },
                hideSurface: { [weak self] in self?.hidePanel(source: "ui-smoke") },
                showSurface: { [weak self] in self?.showPanel() },
                isSurfaceShown: { [weak self] in self?.panel.isVisible == true },
                pressStatusItem: { [weak self] in self?.statusItem.button?.performClick(nil) }
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPanel()
                self?.uiSmokeRuntime?.start()
            }
        } else if uiSmokeConfiguration != nil, UISmokeConfiguration.xcuiTestWasRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPanel()
            }
        }
    }

    private func updateTitle() {
        let title = timer.statusTitle ?? store.statusTitle
        statusItem.button?.title = title
        statusItem.button?.toolTip = timer.statusToolTip
            ?? (store.primary == nil ? "Добавить событие" : store.statusTitle)
        updateTimerAttentionAnimation()
        if case .idle = timer.phase {
            timerCompletionAlert.dismiss()
        }
    }

    private func updateTimerAttentionAnimation() {
        guard let button = statusItem.button else { return }
        guard case .finished = timer.phase else {
            if button.layer?.animation(forKey: timerAttentionAnimationKey) != nil {
                button.layer?.removeAnimation(forKey: timerAttentionAnimationKey)
                DiagnosticLog.shared.record("timer.attention-animation stopped")
            }
            return
        }
        button.wantsLayer = true
        guard let layer = button.layer else { return }
        guard layer.animation(forKey: timerAttentionAnimationKey) == nil else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animation = makeTimerAttentionAnimation(reduceMotion: reduceMotion)
        layer.add(animation, forKey: timerAttentionAnimationKey)
        DiagnosticLog.shared.record(
            "timer.attention-animation started mode=\(reduceMotion ? "pulse" : "shake")"
        )
    }

    private func restartTimerAttentionAnimation() {
        statusItem.button?.layer?.removeAnimation(forKey: timerAttentionAnimationKey)
        updateTimerAttentionAnimation()
    }

    @objc private func togglePanel() {
        let isPresentedHere = isPanelRequestedVisible && panel.isVisible && panel.isOnActiveSpace
        let intent = isPresentedHere ? "hide" : "show"
        recordShellLifecycle("status-action intent=\(intent)")
        if isPresentedHere {
            hidePanel(source: "status-action")
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button,
              !(isPanelRequestedVisible && panel.isVisible && panel.isOnActiveSpace) else { return }
        isPanelRequestedVisible = false
        if panel.isVisible {
            panel.orderOut(nil)
        }
        guard positionPanel(relativeTo: button) else { return }
        isPanelRequestedVisible = true
        recordShellLifecycle("show-begin")
        store.refresh()
        NSApp.activate(ignoringOtherApps: true)
        recordShellLifecycle("show-after-activate")
        panel.makeKeyAndOrderFront(nil)
        recordShellLifecycle("show-after-panel")
    }

    private func positionPanel(relativeTo button: NSStatusBarButton) -> Bool {
        guard let buttonWindow = button.window,
              let screen = buttonWindow.screen else { return false }
        let anchorInWindow = button.convert(button.bounds, to: nil)
        let anchor = buttonWindow.convertToScreen(anchorInWindow)
        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size
        let margin: CGFloat = 8
        let gap: CGFloat = 4
        let minimumX = visibleFrame.minX + margin
        let maximumX = visibleFrame.maxX - panelSize.width - margin
        let x = min(max(anchor.midX - panelSize.width / 2, minimumX), maximumX)
        let top = min(anchor.minY - gap, visibleFrame.maxY)
        let y = max(visibleFrame.minY + margin, top - panelSize.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        return true
    }

    private func hidePanel(source: String) {
        guard isPanelRequestedVisible || panel.isVisible else { return }
        isPanelRequestedVisible = false
        recordShellLifecycle("hide source=\(source)")
        panel.orderOut(nil)
    }

    @objc private func hidePanelFromCommand() {
        hidePanel(source: "command-w")
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel(source: "window-close")
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        recordShellLifecycle("panel-occlusion-did-change")
        guard !UISmokeConfiguration.isolatedTestEnvironmentWasRequested,
              isPanelRequestedVisible,
              !panel.occlusionState.contains(.visible) else { return }
        hidePanel(source: "panel-occluded")
    }

    func applicationDidResignActive(_ notification: Notification) {
        recordShellLifecycle("application-did-resign-active")
        guard !UISmokeConfiguration.isolatedTestEnvironmentWasRequested else { return }
        hidePanel(source: "application-deactivation")
    }

    private func activeSpaceDidChange() {
        recordShellLifecycle("active-space-did-change")
        guard !UISmokeConfiguration.isolatedTestEnvironmentWasRequested else { return }
        hidePanel(source: "active-space-change")
    }

    private func recordShellLifecycle(_ event: String) {
        let occlusion = panel?.occlusionState.rawValue ?? 0
        DiagnosticLog.shared.record(
            "shell.lifecycle event=\(event) appActive=\(NSApp.isActive) "
                + "visible=\(panel?.isVisible ?? false) key=\(panel?.isKeyWindow ?? false) "
                + "onActiveSpace=\(panel?.isOnActiveSpace ?? false) "
                + "occlusion=\(occlusion) requested=\(isPanelRequestedVisible)"
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
            action: #selector(hidePanelFromCommand),
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
        statusItem.button?.layer?.removeAnimation(forKey: timerAttentionAnimationKey)
        timerCompletionAlert.dismiss()
        if let activeSpaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceObserver)
            self.activeSpaceObserver = nil
        }
        if let accessibilityDisplayObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityDisplayObserver)
            self.accessibilityDisplayObserver = nil
        }
        MainThreadWatchdog.shared.stop()
        DiagnosticLog.shared.record("app.terminate")
        DiagnosticLog.shared.flush()
    }

}
