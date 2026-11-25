import AppKit
import Combine
import CountdownCore
import QuartzCore
import SwiftUI

package let timerAttentionAnimationKey = "countdown.timer.attention"
package let timerRunningPulseKey = "countdown.timer.running-pulse"

private func footRockTransform(angle: CGFloat, size: CGSize, hop: CGFloat) -> CATransform3D {
    // The status button layer is geometry-flipped (origin top-left, y down):
    // the visual bottom edge is y == size.height and an upward hop is negative
    // y. Each tilt pivots on its own bottom corner — the foot the alarm rocks
    // onto — rather than on a shared midpoint.
    let pivotX = angle < 0 ? 0 : size.width
    var transform = CATransform3DTranslate(CATransform3DIdentity, pivotX, size.height, 0)
    transform = CATransform3DRotate(transform, angle, 0, 0, 1)
    transform = CATransform3DTranslate(transform, -pivotX, -size.height, 0)
    return CATransform3DTranslate(transform, 0, -hop, 0)
}

package func makeTimerAttentionAnimation(reduceMotion: Bool, wiggleSize: CGSize = .zero) -> CAAnimation {
    if reduceMotion {
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.65
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        return pulse
    }

    // Hops from foot to foot like a ringing mechanical alarm clock: corner
    // pivots with a small lift and a snappy asymmetric rhythm, not a smooth
    // pendulum sway.
    let angle: CGFloat = 0.22
    let hop: CGFloat = 1.5
    let rock = CAKeyframeAnimation(keyPath: "transform")
    rock.values = [
        CATransform3DIdentity,
        footRockTransform(angle: -angle, size: wiggleSize, hop: hop),
        CATransform3DIdentity,
        footRockTransform(angle: angle, size: wiggleSize, hop: hop),
        CATransform3DIdentity,
    ]
    rock.keyTimes = [0, 0.22, 0.5, 0.72, 1]
    rock.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
    ]
    rock.duration = 0.5
    rock.repeatCount = .greatestFiniteMagnitude
    return rock
}

package func makeTimerRunningPulseAnimation() -> CABasicAnimation {
    // A gentle breath of the whole status item; the remaining-time text stays
    // readable throughout.
    let pulse = CABasicAnimation(keyPath: "opacity")
    pulse.fromValue = 1
    pulse.toValue = 0.78
    pulse.duration = 1.1
    pulse.autoreverses = true
    pulse.repeatCount = .greatestFiniteMagnitude
    return pulse
}

public enum CountdownManagerApplication {
    @MainActor public static func run() {
        let configuration: UISmokeConfiguration?
        do {
            configuration = try UISmokeConfiguration.load()
        } catch {
            fputs("UISmoke refused to start: \(error.localizedDescription)\n", stderr)
            Darwin.exit(64)
        }
        AppText.prepareLaunch(defaults: configuration?.defaults ?? .standard)
        let app = NSApplication.shared
        let delegate = AppDelegate(uiSmokeConfiguration: configuration)
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

// canImport compares AppKit's framework version, not the macOS version.
// SDK 26 uses AppKit 26xx; the expanded-session declarations are in the 27xx series.
let supportsExpandedStatusItemSessions: Bool = {
    #if canImport(AppKit, _version: 2700.0) && compiler(>=6.2)
    if #available(macOS 27.0, *) { return true }
    #endif
    return false
}()

@MainActor
private final class CountdownStatusPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    func prepareOpening(fade: Bool) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            animator().alphaValue = fade ? 0 : 1
        }
    }

    func fadeIn() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func orderOutWithUtilityAnimation() {
        let previousBehavior = animationBehavior
        animationBehavior = .utilityWindow
        defer { animationBehavior = previousBehavior }
        orderOut(nil)
    }
}

@MainActor
private final class StatusItemAppearanceView: NSView {
    var appearanceDidChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        appearanceDidChange?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class StatusItemMarsGlyph: NSImageView {
    let placeholder = NSImage(size: StatusBarImages.iconSize, flipped: false) { _ in true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private let uiSmokeConfiguration: UISmokeConfiguration?
    private var statusItem: NSStatusItem!
    private var panel: CountdownStatusPanel!
    private var hostingController: NSHostingController<CountdownManagerRootView>!
    private var desktopController: DesktopWindowController?
    private var whatsNewController: WhatsNewWindowController!
    private var automaticWhatsNewIsEnabled = false
    private var store: Store!
    private var timer: CountdownTimer!
    private var updates: ApplicationUpdates!
    private var weather: WeatherController!
    private let editorSession = EventEditorSession()
    private var keepAwake: KeepAwakeController!
    private let accessibilitySettings = AuroraAccessibilitySettings()
    private let visualEnvironment = UISmokeVisualEnvironment()
    private let marsOpeningAnimation = MarsOpeningAnimation()
    private var regularStatusMarsGlyph: StatusItemMarsGlyph?
    private var appPreferences: ApplicationPreferences!
    private var appearanceSubscription: AnyCancellable?
    private var languageSubscription: AnyCancellable?
    private var subscription: AnyCancellable?
    private var timerCompletionSubscription: AnyCancellable?
    private var weatherSubscription: AnyCancellable?
    private var weatherEnvironmentSubscriptions = Set<AnyCancellable>()
    private lazy var timerCompletionAlert = TimerCompletionAlertPresenter(
        accessibilitySettings: accessibilitySettings, appearanceSource: panel
    )
    private var uiSmokeRuntime: UISmokeRuntime?
    private var desktopSmokeRuntime: DesktopSmokeRuntime?
    private var activeSpaceObserver: NSObjectProtocol?
    private var accessibilityDisplayObserver: NSObjectProtocol?
    private var panelPresentation = PanelPresentationState()
    private var tracksStatusItemInAppKit = false
    private var panelUsesNativeStatusSession = false
    private var isPanelRequestedVisible: Bool { panelPresentation.requestedVisible }

    init(uiSmokeConfiguration: UISmokeConfiguration?) {
        self.uiSmokeConfiguration = uiSmokeConfiguration
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        DiagnosticLog.shared.record("app.launch version=\(version) build=\(build) os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        MainThreadWatchdog.shared.start()
        let defaults = uiSmokeConfiguration?.defaults ?? .standard
        automaticWhatsNewIsEnabled = uiSmokeConfiguration == nil
            || ProcessInfo.processInfo.arguments.contains("--ui-smoke-whats-new")
        appPreferences = ApplicationPreferences(defaults: defaults)
        whatsNewController = WhatsNewWindowController(defaults: defaults, accessibilitySettings: accessibilitySettings,
                                                      appPreferences: appPreferences) { [weak self] in
            guard let self, NSApp.isActive, self.canShowWhatsNew,
                  self.desktopController?.window?.isVisible != true else { return }
            self.showPanel()
        }
        keepAwake = KeepAwakeController(defaults: defaults)
        if UISmokeConfiguration.captureWasRequested {
            defaults.set(Date().addingTimeInterval(-1).timeIntervalSince1970,
                         forKey: CountdownTimer.deadlineKey)
        }
        store = Store(
            fileURL: uiSmokeConfiguration?.dataURL,
            disclosureDefaults: defaults,
            loginItemManagementIsAvailable: uiSmokeConfiguration == nil
        )
        timer = CountdownTimer(defaults: defaults)
        if uiSmokeConfiguration != nil {
            weather = WeatherController(
                defaults: defaults,
                provider: { Self.isolatedWeatherForecasts($0) },
                allowLocationRequests: false,
                diagnostics: .journal
            )
        } else {
            weather = WeatherController(defaults: defaults, diagnostics: .journal)
        }
        updates = ApplicationUpdates(
            enabled: uiSmokeConfiguration == nil || UISmokeConfiguration.updateTestWasRequested,
            isolatedUpdateTest: UISmokeConfiguration.updateTestWasRequested,
            willPresentUpdateUI: { [weak self] in self?.preparePanelForUpdateUI() },
            didFinishUpdateUI: { [weak self] in
                // Sparkle calls its finish hook before closing its windows. Restore only
                // the level after that callback unwinds; never reopen the panel implicitly.
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.updates.isPresentingUpdateUI else { return }
                    self.panel.level = .popUpMenu
                }
            },
            returnToApplication: { [weak self] in self?.returnToActiveEditor() }
        ) { [weak self] in
            guard let self else { return AppText.string("app.lifecycle.terminating") }
            if self.store.isExportingDiagnostics { return AppText.string("app.lifecycle.waitForDiagnostics") }
            let timerIsRunning: Bool
            if case .running = self.timer.phase { timerIsRunning = true } else { timerIsRunning = false }
            return updateRestartBlockReason(
                editorIsPresented: self.editorSession.hasActiveEditor,
                persistenceIsBusy: self.store.hasPendingPersistence,
                timerIsRunning: timerIsRunning
            )
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.setAccessibilityLabel("Countdown Manager")
            let materialDragView = StatusItemMaterialDragView(frame: button.bounds)
            materialDragView.autoresizingMask = [.width, .height]
            materialDragView.revealPanel = { [weak self] in
                guard let self, !self.editorSession.desktopIsPresented else { return }
                self.showPanel(activate: false)
            }
            button.addSubview(materialDragView)
            // Inherit the status button's actual appearance, including its system window.
            let appearanceView = StatusItemAppearanceView(frame: .zero)
            appearanceView.setAccessibilityElement(false)
            button.addSubview(appearanceView)
            appearanceView.appearanceDidChange = { [weak self] in self?.updateTitle() }
        }
        hostingController = NSHostingController(
            rootView: CountdownManagerRootView(
                timer: timer,
                store: store,
                updates: updates,
                editorSession: editorSession,
                keepAwake: keepAwake,
                weather: weather,
                showDesktop: { [weak self] in self?.showDesktopWindow() },
                showWhatsNew: { [weak self] in self?.showWhatsNew() },
                accessibilitySettings: accessibilitySettings,
                visualEnvironment: visualEnvironment,
                appPreferences: appPreferences
            )
        )
        panel = CountdownStatusPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = AppText.string("app.name")
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
        if let button = statusItem.button { configureStatusButton(button) }
        store.dialogAppearanceSource = panel
        updates.dialogAppearanceSource = panel
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.cornerRadius = 12
        hostingController.view.layer?.masksToBounds = true
        appearanceSubscription = appPreferences.$selection.combineLatest(visualEnvironment.$colorSchemeOverride)
            .sink { [weak self] selection, captureOverride in
                let scheme = captureOverride ?? selection.colorScheme
                let appearance = scheme.flatMap { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) }
                NSApp.appearance = appearance
                self?.panel.appearance = appearance
                self?.desktopController?.window?.appearance = appearance
                self?.whatsNewController.window?.appearance = appearance
            }
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
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { self?.marsOpeningAnimation.stop() }
                self?.restartTimerAttentionAnimation()
            }
        }
        installApplicationMenu()
        languageSubscription = appPreferences.$language.dropFirst().sink { [weak self] _ in
            self?.installApplicationMenu()
            self?.updateTitle()
            self?.timerCompletionAlert.updateLanguage()
        }
        subscription = Publishers.Merge(store.objectWillChange, timer.objectWillChange)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updateTitle() }
            }
        weatherSubscription = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.weather.updateEvents(self.store.active)
            }
        }
        let weatherNotifications = [NSApplication.didBecomeActiveNotification,
            NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange,
            NSNotification.Name.NSCalendarDayChanged].map { NotificationCenter.default.publisher(for: $0) }
            + [NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)]
        for publisher in weatherNotifications {
            publisher.receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                self.store.refresh()
                self.weather.updateEvents(self.store.active)
            }.store(in: &weatherEnvironmentSubscriptions)
        }
        weather.updateEvents(store.active)
        weather.recordDiagnosticSnapshot(reason: .launch)
        timerCompletionSubscription = timer.completionPublisher
            .sink { [weak self] in
                self?.timerCompletionAlert.present()
            }
        updateTitle()
        if let uiSmokeConfiguration, UISmokeConfiguration.desktopWasRequested {
            desktopSmokeRuntime = DesktopSmokeRuntime(
                configuration: uiSmokeConfiguration,
                store: store,
                timer: timer,
                editorSession: editorSession,
                keepAwake: keepAwake,
                weather: weather,
                accessibilitySettings: accessibilitySettings,
                visualEnvironment: visualEnvironment,
                appPreferences: appPreferences,
                desktopWindow: { [weak self] in self?.desktopController?.window },
                panelWindow: { [weak self] in self?.panel },
                statusButton: { [weak self] in self?.statusItem.button },
                showDesktop: { [weak self] in self?.showDesktopWindow() },
                hideDesktop: { [weak self] in self?.desktopController?.hide() },
                showPanel: { [weak self] in self?.showPanel() },
                pressStatusItem: { [weak self] in self?.statusItem.button?.performClick(nil) },
                whatsNewWindow: { [weak self] in self?.whatsNewController.window },
                showWhatsNew: { [weak self] in self?.showWhatsNew() }
            )
            DispatchQueue.main.async { [weak self] in self?.desktopSmokeRuntime?.start() }
        } else if let uiSmokeConfiguration, UISmokeConfiguration.wasRequested {
            uiSmokeRuntime = UISmokeRuntime(
                configuration: uiSmokeConfiguration,
                store: store,
                window: { [weak self] in self?.panel },
                statusButton: { [weak self] in self?.statusItem.button },
                showDesktop: { [weak self] in self?.showDesktopWindow() },
                marsOpeningAnimation: { [weak self] in self?.marsOpeningAnimation },
                hideSurface: { [weak self] in self?.hidePanel(source: "ui-smoke") },
                showSurface: { [weak self] in self?.showPanel() },
                isSurfaceShown: { [weak self] in self?.panel.isVisible == true },
                pressStatusItem: { [weak self] in self?.statusItem.button?.performClick(nil) },
                timer: timer,
                updates: updates,
                weather: weather,
                accessibilitySettings: accessibilitySettings,
                visualEnvironment: visualEnvironment
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPanel()
                self?.uiSmokeRuntime?.start()
            }
        } else if uiSmokeConfiguration != nil, UISmokeConfiguration.xcuiTestWasRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.showPanel()
            }
        } else if uiSmokeConfiguration != nil,
                  UISmokeConfiguration.visualPreviewWasRequested || UISmokeConfiguration.updateTestWasRequested {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                if UISmokeConfiguration.visualPreviewWasRequested,
                   UISmokeConfiguration.desktopPreviewWasRequested,
                   !UISmokeConfiguration.updateTestWasRequested {
                    self?.showDesktopWindow()
                } else {
                    self?.showPanel()
                }
            }
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        regularStatusMarsGlyph?.isHidden = true
        if let timerTitle = timer.statusTitle {
            button.image = Self.timerStatusIcon
            button.imagePosition = timerTitle.isEmpty ? .imageOnly : .imageLeft
            button.title = timerTitle
        } else {
            let presentation = store.statusPresentation
            let image = presentation.icon.flatMap { StatusBarImages.image(for: $0, appearance: button.effectiveAppearance) }
            if presentation.icon == .mars, let glyph = regularStatusMarsGlyph, let image {
                glyph.image = image
                glyph.isHidden = false
                button.image = glyph.placeholder
            } else {
                button.image = image
            }
            button.imagePosition = presentation.icon == nil ? .noImage
                : (presentation.title.isEmpty ? .imageOnly : .imageLeft)
            button.title = presentation.title
        }
        let statusDescription = timer.statusToolTip ?? store.statusPresentation.toolTip
        button.toolTip = statusDescription
        button.setAccessibilityLabel("Countdown Manager")
        button.setAccessibilityValue(statusDescription)
        marsOpeningAnimation.updateEligibility(showsMars: timer.statusTitle == nil && store.statusPresentation.icon == .mars)
        updateTimerAttentionAnimation()
        if regularStatusMarsGlyph != nil { updateStatusItemHighlight() }
        if case .idle = timer.phase {
            timerCompletionAlert.dismiss()
        }
    }

    private static let timerStatusIcon: NSImage? = {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        return NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }()

    private func updateTimerAttentionAnimation() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        guard let layer = button.layer else { return }

        switch timer.phase {
        case .finished:
            stopStatusAnimation(layer, key: timerRunningPulseKey, stoppedLog: "timer.running-pulse stopped")
            guard layer.animation(forKey: timerAttentionAnimationKey) == nil else { return }
            let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            layer.add(
                makeTimerAttentionAnimation(reduceMotion: reduceMotion, wiggleSize: layer.bounds.size),
                forKey: timerAttentionAnimationKey
            )
            DiagnosticLog.shared.record(
                "timer.attention-animation started mode=\(reduceMotion ? "pulse" : "rock")"
            )
        case .running:
            stopStatusAnimation(layer, key: timerAttentionAnimationKey, stoppedLog: "timer.attention-animation stopped")
            guard layer.animation(forKey: timerRunningPulseKey) == nil else { return }
            layer.add(makeTimerRunningPulseAnimation(), forKey: timerRunningPulseKey)
            DiagnosticLog.shared.record("timer.running-pulse started")
        case .idle:
            stopStatusAnimation(layer, key: timerAttentionAnimationKey, stoppedLog: "timer.attention-animation stopped")
            stopStatusAnimation(layer, key: timerRunningPulseKey, stoppedLog: "timer.running-pulse stopped")
        }
    }

    private func stopStatusAnimation(_ layer: CALayer, key: String, stoppedLog: String) {
        guard layer.animation(forKey: key) != nil else { return }
        layer.removeAnimation(forKey: key)
        DiagnosticLog.shared.record(stoppedLog)
    }

    private func restartTimerAttentionAnimation() {
        if let layer = statusItem.button?.layer {
            layer.removeAnimation(forKey: timerAttentionAnimationKey)
            layer.removeAnimation(forKey: timerRunningPulseKey)
        }
        updateTimerAttentionAnimation()
    }

    private func configureStatusButton(_ button: NSStatusBarButton) {
        #if canImport(AppKit, _version: 2700.0) && compiler(>=6.2)
        if #available(macOS 27.0, *), !UISmokeConfiguration.wasRequested {
            tracksStatusItemInAppKit = NSApp.activationPolicy() == .accessory
            if tracksStatusItemInAppKit {
                statusItem.expandedInterfaceDelegate = self
                return
            }
            // A regular foreground app can miss the end of an expanded interface session.
            // Use the button's own action once the app has acquired its persistent Dock role.
            statusItem.expandedInterfaceDelegate = nil
            installRegularStatusMarsGlyph(in: button)
        }
        #endif
        button.target = self
        button.action = #selector(togglePanel)
        if supportsExpandedStatusItemSessions { button.sendAction(on: [.leftMouseDown]) }
    }

    private func installRegularStatusMarsGlyph(in button: NSStatusBarButton) {
        guard regularStatusMarsGlyph == nil else { return }
        let glyph = StatusItemMarsGlyph(frame: .zero)
        glyph.imageScaling = .scaleNone
        glyph.isHidden = true
        glyph.wantsLayer = true
        glyph.setAccessibilityElement(false)
        glyph.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(glyph)
        NSLayoutConstraint.activate([
            glyph.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor),
            glyph.widthAnchor.constraint(equalToConstant: StatusBarImages.iconSize.width),
            glyph.heightAnchor.constraint(equalToConstant: StatusBarImages.iconSize.height),
        ])
        regularStatusMarsGlyph = glyph
    }

    @objc private func togglePanel() {
        guard supportsExpandedStatusItemSessions else {
            let isPresentedHere = isPanelPresentedHere
            recordShellLifecycle("status-action intent=\(isPresentedHere ? "hide" : "show")")
            if isPresentedHere {
                hidePanel(source: "status-action")
            } else {
                showPanel()
            }
            return
        }
        let eventType = NSApp.currentEvent?.type
        let isMousePress = eventType == .leftMouseDown || eventType == .leftMouseUp
        let press = isMousePress ? currentLeftMousePress : nil
        let action = panelPresentation.statusAction(press: press, isOnActiveSpace: panel.isOnActiveSpace)
        recordShellLifecycle("status-action intent=\(action.rawValue)")
        switch action {
        case .hide:
            hidePanel(source: "status-action", fromStatusItem: true)
        case .show:
            showPanel(fromStatusItem: true)
        case .alreadyHidden:
            break
        }
        // The status button can clear its own tracking highlight after the target returns.
        RunLoop.main.perform(inModes: [.default]) { [weak self] in
            MainActor.assumeIsolated { self?.updateStatusItemHighlight() }
        }
    }

    private var isPanelPresentedHere: Bool {
        if supportsExpandedStatusItemSessions {
            return panelPresentation.hasShowRequestHere(isOnActiveSpace: panel.isOnActiveSpace)
        }
        return isPanelRequestedVisible && panel.isVisible && panel.isOnActiveSpace
    }

    private func showPanel(activate: Bool = true, fromStatusItem: Bool = false, usesNativeSession: Bool = false) {
        let nativeSession = usesNativeSession ? nativeStatusSessionID : nil
        guard let button = statusItem.button,
              !usesNativeSession || nativeSession != nil,
              !isPanelPresentedHere else { return }
        panelPresentation.requestHide()
        if panel.isVisible {
            panel.orderOut(nil)
        }
        guard positionPanel(relativeTo: button) else {
            updateStatusItemHighlight()
            return
        }
        panelPresentation.requestShow()
        panelUsesNativeStatusSession = usesNativeSession
        recordShellLifecycle("show-begin")
        store.refresh()
        weather.updateEvents(store.active)
        if activate {
            if !supportsExpandedStatusItemSessions || !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
            recordShellLifecycle("show-after-activate")
            // Activation may have ended the native session before AppKit can order the panel.
            guard !usesNativeSession || (panelUsesNativeStatusSession && nativeStatusSessionID == nativeSession) else { return }
            let fade = fromStatusItem && !accessibilitySettings.prefersReducedMotion
            if supportsExpandedStatusItemSessions { panel.prepareOpening(fade: fade) }
            panel.makeKeyAndOrderFront(nil)
            if fade, isPanelRequestedVisible, !usesNativeSession || nativeStatusSessionID == nativeSession {
                panel.fadeIn()
            }
        } else {
            // Activating the receiver while hovering can disturb the source application's drag.
            if supportsExpandedStatusItemSessions { panel.prepareOpening(fade: false) }
            panel.orderFrontRegardless()
        }
        recordShellLifecycle("show-after-panel")
        updateStatusItemHighlight()
        startMarsOpeningAnimation()
        if activate { offerWhatsNewIfNeeded() }
    }

    private var canShowWhatsNew: Bool {
        !editorSession.hasActiveEditor && !store.isLoading && !store.hasPendingPersistence
            && !store.isExportingDiagnostics && !updates.isPresentingUpdateUI
            && NSApp.modalWindow == nil
            && desktopController?.window?.attachedSheet == nil && panel.attachedSheet == nil
    }

    private func offerWhatsNewIfNeeded() {
        guard automaticWhatsNewIsEnabled, whatsNewController.hasUnseenRelease else { return }
        showWhatsNew()
    }

    @objc private func showWhatsNew() {
        guard canShowWhatsNew else {
            DiagnosticLog.shared.record("whats-new.blocked editor=\(editorSession.hasActiveEditor) "
                + "busy=\(store.hasPendingPersistence) export=\(store.isExportingDiagnostics) "
                + "updater=\(updates.isPresentingUpdateUI) modal=\(NSApp.modalWindow != nil) "
                + "desktopSheet=\(desktopController?.window?.attachedSheet != nil) panelSheet=\(panel.attachedSheet != nil)")
            return
        }
        DiagnosticLog.shared.record("whats-new.present")
        hidePanel(source: "whats-new")
        whatsNewController.present()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action != #selector(showWhatsNew) || canShowWhatsNew
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

    private func hidePanel(source: String, fromStatusItem: Bool = false) {
        guard isPanelRequestedVisible || panel.isVisible else { return }
        let nativeSession = nativeStatusSessionID
        panelPresentation.requestHide()
        panelUsesNativeStatusSession = false
        recordShellLifecycle("hide source=\(source)")
        if fromStatusItem && !accessibilitySettings.prefersReducedMotion {
            panel.orderOutWithUtilityAnimation()
        } else {
            panel.orderOut(nil)
        }
        cancelNativeStatusSession(nativeSession)
        updateStatusItemHighlight()
    }

    private func updateStatusItemHighlight() {
        guard supportsExpandedStatusItemSessions, !tracksStatusItemInAppKit, let button = statusItem.button else { return }
        let isPresented = isPanelRequestedVisible && panel.isVisible
        if UISmokeConfiguration.wasRequested {
            button.highlight(isPresented)
        } else if let layer = button.layer {
            // Keep the selection on the button's stable layer. Mars can rotate on its own layer.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.cornerRadius = button.bounds.height / 2
            button.effectiveAppearance.performAsCurrentDrawingAppearance {
                layer.backgroundColor = isPresented ? NSColor.labelColor.withAlphaComponent(0.16).cgColor : nil
            }
            CATransaction.commit()
        }
    }

    private var nativeStatusSessionID: ObjectIdentifier? {
        #if canImport(AppKit, _version: 2700.0) && compiler(>=6.2)
        if #available(macOS 27.0, *) { return statusItem?.expandedInterfaceSession.map(ObjectIdentifier.init) }
        #endif
        return nil
    }

    private func cancelNativeStatusSession(_ expected: ObjectIdentifier?) {
        #if canImport(AppKit, _version: 2700.0) && compiler(>=6.2)
        if #available(macOS 27.0, *), let session = statusItem?.expandedInterfaceSession,
           ObjectIdentifier(session) == expected {
            session.cancel()
        }
        #endif
    }

    private func preparePanelForUpdateUI() {
        guard let panel else { return }
        hidePanel(source: "update-ui")
        // Explicit reopening still reaches the retained draft/timer while downloading
        // or postponing. Its ordinary level lets subsequent native updater UI take focus.
        panel.level = .normal
    }

    @objc private func closeKeySurface() {
        guard let keyWindow = NSApp.keyWindow else { return }
        if keyWindow === panel {
            hidePanel(source: "command-w")
        } else if editorSession.desktopIsPresented,
                  keyWindow === desktopController?.window || keyWindow.sheetParent === desktopController?.window {
            return
        } else {
            keyWindow.performClose(nil)
        }
    }

    @objc private func showDesktopWindow() {
        hidePanel(source: "open-desktop")
        store.refresh()
        weather.updateEvents(store.active)
        if desktopController == nil {
            let sharedTimer: CountdownTimer = timer
            let sharedUpdates: ApplicationUpdates = updates
            let sharedWeather: WeatherController = weather
            let rootView = DesktopRootView(
                store: store, updates: updates, editorSession: editorSession,
                keepAwake: keepAwake, weather: weather, accessibilitySettings: accessibilitySettings,
                visualEnvironment: visualEnvironment,
                appPreferences: appPreferences,
                showPanel: { [weak self] in self?.showPanel() },
                switchToPanel: { [weak self] in self?.switchToPanel() },
                diagnosticsContext: {
                    makeDiagnosticExportContext(timer: sharedTimer, updates: sharedUpdates, weather: sharedWeather)
                },
                showWhatsNew: { [weak self] in self?.showWhatsNew() }
            )
            desktopController = DesktopWindowController(rootView: rootView, editorSession: editorSession)
            desktopController?.window?.appearance = appPreferences.nativeAppearance(
                overriding: visualEnvironment.colorSchemeOverride
            )
        }
        desktopController?.show()
        if tracksStatusItemInAppKit, NSApp.activationPolicy() == .regular, let button = statusItem.button {
            configureStatusButton(button)
        }
        if desktopController?.window?.isVisible == true { startMarsOpeningAnimation() }
        offerWhatsNewIfNeeded()
    }

    private func startMarsOpeningAnimation() {
        updateTitle()
        statusItem.button?.wantsLayer = true
        if regularStatusMarsGlyph != nil { statusItem.button?.layoutSubtreeIfNeeded() }
        marsOpeningAnimation.start(
            layer: regularStatusMarsGlyph?.layer ?? statusItem.button?.layer,
            statusShowsMars: timer.statusTitle == nil && store.statusPresentation.icon == .mars,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
    }

    private func switchToPanel() {
        guard desktopController?.hideForPanel() == true else { return }
        showPanel()
    }

    private func returnToActiveEditor() {
        if editorSession.desktopIsPresented || editorSession.subtaskTransfer?.surface == .desktop {
            showDesktopWindow()
        } else if editorSession.isPresented || editorSession.subtaskTransfer?.surface == .panel {
            showPanel()
        } else if desktopController?.window?.isVisible == true {
            showDesktopWindow()
        } else {
            showPanel()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDesktopWindow()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hidePanel(source: "window-close")
        return false
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        recordShellLifecycle("panel-occlusion-did-change")
        guard !UISmokeConfiguration.suppressesShellLifecycleCallbacks,
              let window = notification.object as? NSWindow, window === panel else { return }
        let isVisible = panel.occlusionState.contains(.visible)
        if panelPresentation.observeOcclusion(isVisible: isVisible) {
            hidePanel(source: "panel-occluded")
        } else if isPanelRequestedVisible, !isVisible {
            // A prior orderOut can finish before the new presentation is acknowledged.
            recordShellLifecycle("panel-occlusion-before-visible-acknowledgement")
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard !UISmokeConfiguration.suppressesShellLifecycleCallbacks,
              let window = notification.object as? NSWindow, window === panel else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPanelRequestedVisible, !self.panel.isKeyWindow,
                  let desktopWindow = self.desktopController?.window,
                  let keyWindow = NSApp.keyWindow,
                  keyWindow === desktopWindow || keyWindow.sheetParent === desktopWindow else { return }
            self.hidePanel(source: "desktop-focus")
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        recordShellLifecycle("application-did-resign-active")
        guard !UISmokeConfiguration.suppressesShellLifecycleCallbacks else { return }
        guard supportsExpandedStatusItemSessions else {
            hidePanel(source: "application-deactivation")
            return
        }
        let leftMouseDown = NSEvent.pressedMouseButtons & 1 != 0
        if isPointerOnStatusItem, panelPresentation.hasShowRequestHere(isOnActiveSpace: panel.isOnActiveSpace),
           panelPresentation.recordStatusPressDuringDeactivation(currentLeftMousePress, buttonIsDown: leftMouseDown,
                                                                 usesNativeSession: panelUsesNativeStatusSession) {
            // WindowServer can deliver deactivation before dispatching the status button's action.
            // The action from that same press must not undo this dismissal.
            hidePanel(source: "status-item-deactivation", fromStatusItem: true)
        } else {
            panelPresentation.clearStatusPressDuringDeactivation()
            hidePanel(source: "application-deactivation")
        }
    }

    private var isPointerOnStatusItem: Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(NSEvent.mouseLocation)
    }

    private var currentLeftMousePress: PanelPresentationState.StatusPress {
        .init(session: CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown),
              hardware: CGEventSource.counterForEventType(.hidSystemState, eventType: .leftMouseDown),
              keyboard: CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown))
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard updates?.shouldCancelUpdateTermination == true else { return .terminateNow }
        DiagnosticLog.shared.record("updates.termination cancelled-active-work")
        return .terminateCancel
    }

    private func activeSpaceDidChange() {
        recordShellLifecycle("active-space-did-change")
        guard !UISmokeConfiguration.suppressesShellLifecycleCallbacks else { return }
        panelPresentation.clearStatusPressDuringDeactivation()
        hidePanel(source: "active-space-change")
    }

    private func recordShellLifecycle(_ event: String) {
        let occlusion = panel?.occlusionState.rawValue ?? 0
        DiagnosticLog.shared.record(
            "shell.lifecycle event=\(event) appActive=\(NSApp.isActive) "
                + "visible=\(panel?.isVisible ?? false) key=\(panel?.isKeyWindow ?? false) "
                + "onActiveSpace=\(panel?.isOnActiveSpace ?? false) "
                + "occlusion=\(occlusion) requested=\(isPanelRequestedVisible) "
                + "visibleAcknowledged=\(panelPresentation.hasVisibleAcknowledgement)"
        )
    }

    // Standard responder-chain commands keep native text editing and Cmd-W available
    // in an accessory application without an automatically generated main menu.
    private func installApplicationMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        let whatsNewItem = appMenu.addItem(
            withTitle: AppText.string("app.menu.whatsNew"), action: #selector(showWhatsNew), keyEquivalent: ""
        )
        whatsNewItem.target = self
        appMenu.addItem(.separator())
        let checkItem = appMenu.addItem(
            withTitle: AppText.string("app.menu.checkForUpdates"), action: #selector(ApplicationUpdates.checkForUpdates(_:)), keyEquivalent: ""
        )
        checkItem.target = updates
        let automaticItem = appMenu.addItem(
            withTitle: AppText.string("app.menu.autoCheckUpdates"),
            action: #selector(ApplicationUpdates.toggleAutomaticChecks(_:)), keyEquivalent: ""
        )
        automaticItem.target = updates
        let installItem = appMenu.addItem(
            withTitle: AppText.string("app.menu.installUpdate"),
            action: #selector(ApplicationUpdates.installDeferredUpdate(_:)), keyEquivalent: ""
        )
        installItem.target = updates
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(
            withTitle: AppText.string("app.menu.quit"), action: #selector(ApplicationUpdates.quitApplication(_:)), keyEquivalent: "q"
        )
        quitItem.target = updates
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        menu.addItem(appItem)
        let editMenu = NSMenu(title: AppText.string("app.menu.edit"))
        for (title, action, key) in [
            (AppText.string("app.menu.undo"), Selector(("undo:")), "z"),
            (AppText.string("app.menu.cut"), #selector(NSText.cut(_:)), "x"),
            (AppText.string("app.menu.copy"), #selector(NSText.copy(_:)), "c"),
            (AppText.string("app.menu.paste"), #selector(NSText.paste(_:)), "v"),
            (AppText.string("app.menu.selectAll"), #selector(NSText.selectAll(_:)), "a")
        ] {
            editMenu.addItem(withTitle: title, action: action, keyEquivalent: key)
        }
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        menu.addItem(editItem)
        let windowMenu = NSMenu(title: AppText.string("app.menu.window"))
        let openItem = windowMenu.addItem(
            withTitle: AppText.string("app.menu.openMainWindow"), action: #selector(showDesktopWindow), keyEquivalent: "0"
        )
        openItem.target = self
        windowMenu.addItem(.separator())
        let closeItem = NSMenuItem(
            title: AppText.string("app.menu.close"),
            action: #selector(closeKeySurface),
            keyEquivalent: "w"
        )
        closeItem.target = self
        windowMenu.addItem(closeItem)
        let windowItem = NSMenuItem()
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        marsOpeningAnimation.stop()
        weather.shutdown()
        keepAwake?.releaseForTermination()
        statusItem.button?.layer?.removeAnimation(forKey: timerAttentionAnimationKey)
        statusItem.button?.layer?.removeAnimation(forKey: timerRunningPulseKey)
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
    }

    // Every explicitly isolated runtime uses demonstration data and never contacts a weather server.
    nonisolated private static func isolatedWeatherForecasts(_ coordinates: WeatherCoordinates) -> [String: DailyWeatherForecast] {
        let today = Day(Date())
        var result: [String: DailyWeatherForecast] = [:]
        for offset in 0..<16 {
            // The weather runtime checks the ordinary missing-forecast state at an eligible date.
            if offset == 2 && !UISmokeConfiguration.compactCaptureWasRequested { continue }
            guard let date = Day.calendar.date(byAdding: .day, value: offset, to: today.date()),
                  let forecast = DailyWeatherForecast(weatherCode: offset.isMultiple(of: 2) ? 2 : 3,
                  maximumTemperature: UISmokeConfiguration.compactCaptureWasRequested && offset == 1 ? -18 : 14) else { continue }
            result[weatherDayKey(Day(date))] = forecast
        }
        return result
    }

}

#if canImport(AppKit, _version: 2700.0) && compiler(>=6.2)
@available(macOS 27.0, *)
extension AppDelegate: @MainActor NSStatusItemExpandedInterfaceDelegate {
    func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        guard tracksStatusItemInAppKit else {
            cancelNativeStatusSession(ObjectIdentifier(session))
            return
        }
        recordShellLifecycle("native-status-session-begin")
        switch panelPresentation.statusAction(press: currentLeftMousePress, isOnActiveSpace: panel.isOnActiveSpace) {
        case .show:
            showPanel(fromStatusItem: true, usesNativeSession: true)
            if !panelUsesNativeStatusSession { cancelNativeStatusSession(ObjectIdentifier(session)) }
        case .hide:
            hidePanel(source: "native-status-while-open", fromStatusItem: true)
        case .alreadyHidden:
            cancelNativeStatusSession(ObjectIdentifier(session))
        }
    }

    func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        recordShellLifecycle("native-status-session-end animated=\(animated)")
        guard statusItem.expandedInterfaceSession == nil else { return }
        if panelUsesNativeStatusSession {
            hidePanel(source: "native-status-session", fromStatusItem: animated)
        }
    }
}
#endif
