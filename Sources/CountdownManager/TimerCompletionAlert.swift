import AppKit
import Combine
import QuartzCore
import SwiftUI

package let timerCompletionAlertDisplayDuration: TimeInterval = 5

package let timerCompletionIconAnimationKey = "countdown.timer.completion-icon"

package func makeTimerCompletionIconAnimation(
    reduceMotion: Bool,
    isGeometryFlipped: Bool
) -> CAKeyframeAnimation? {
    guard !reduceMotion else { return nil }
    let upwardSign: CGFloat = isGeometryFlipped ? -1 : 1
    func pose(angle: CGFloat, hop: CGFloat) -> CATransform3D {
        var transform = CATransform3DMakeRotation(angle, 0, 0, 1)
        transform.m42 = upwardSign * hop
        return transform
    }
    let animation = CAKeyframeAnimation(keyPath: "transform")
    animation.values = [
        CATransform3DIdentity,
        pose(angle: -.pi * 8 / 180, hop: 1.5),
        pose(angle: .pi * 8 / 180, hop: 1.5),
        pose(angle: -.pi * 5 / 180, hop: 1),
        CATransform3DIdentity,
        CATransform3DIdentity,
    ]
    animation.keyTimes = [0, 0.06, 0.12, 0.2, 0.28, 1]
    animation.timingFunctions = [
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeInEaseOut),
        CAMediaTimingFunction(name: .easeOut),
        CAMediaTimingFunction(name: .linear),
    ]
    animation.duration = 1.6
    animation.repeatCount = .greatestFiniteMagnitude
    return animation
}

@MainActor
private final class TimerCompletionAlertView: NSView {
    var onClick: (() -> Void)?
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "Время вышло")
    private let detail = NSTextField(labelWithString: "Таймер Countdown Manager завершён")
    private let accessibilitySettings: AuroraAccessibilitySettings
    private var highContrastSubscription: AnyCancellable?
    private var reduceMotionSubscription: AnyCancellable?
    private var attentionRequested = false

    init(frame frameRect: NSRect, accessibilitySettings: AuroraAccessibilitySettings) {
        self.accessibilitySettings = accessibilitySettings
        super.init(frame: frameRect)
        configure()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }

    private func configure() {
        identifier = NSUserInterfaceItemIdentifier("timer.completion.background")
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.masksToBounds = true

        icon.wantsLayer = true
        icon.image = NSImage(systemSymbolName: "alarm.fill", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.identifier = NSUserInterfaceItemIdentifier("timer.completion.icon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)
        icon.widthAnchor.constraint(equalToConstant: 34).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 34).isActive = true

        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.identifier = NSUserInterfaceItemIdentifier("timer.completion.title")
        detail.font = .systemFont(ofSize: 13)
        detail.identifier = NSUserInterfaceItemIdentifier("timer.completion.detail")

        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4
        let content = NSStackView(views: [icon, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            content.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        highContrastSubscription = accessibilitySettings.$prefersHighContrast
            .receive(on: DispatchQueue.main)
            .sink { [weak self] highContrast in
                MainActor.assumeIsolated {
                    self?.updatePalette(highContrast: highContrast)
                }
            }
        reduceMotionSubscription = accessibilitySettings.$prefersReducedMotion
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] reduceMotion in
                MainActor.assumeIsolated {
                    self?.updateIconAttention(reduceMotion: reduceMotion)
                }
            }
        updatePalette()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updatePalette()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePalette()
    }

    func updatePalette() {
        updatePalette(highContrast: accessibilitySettings.prefersHighContrast)
    }

    private func updatePalette(highContrast: Bool) {
        let scheme: ColorScheme = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        layer?.backgroundColor = NSColor(AuroraInstrument.canvas(for: scheme)).cgColor
        layer?.borderColor = NSColor(AuroraInstrument.stroke(for: scheme, highContrast: highContrast)).cgColor
        layer?.borderWidth = highContrast ? 1 : 0
        title.textColor = NSColor(AuroraInstrument.ink(for: scheme))
        detail.textColor = NSColor(highContrast
            ? AuroraInstrument.ink(for: scheme) : AuroraInstrument.secondaryInk(for: scheme))
        icon.contentTintColor = NSColor(AuroraInstrument.accent(for: scheme, highContrast: highContrast))
    }

    func startIconAttention() {
        attentionRequested = true
        removeIconAnimation()
        layoutSubtreeIfNeeded()
        updateIconAttention(reduceMotion: accessibilitySettings.prefersReducedMotion)
    }

    func stopIconAttention() {
        attentionRequested = false
        removeIconAnimation()
    }

    private func updateIconAttention(reduceMotion: Bool) {
        guard attentionRequested, window?.isVisible == true, !reduceMotion else {
            removeIconAnimation()
            return
        }
        guard let iconLayer = icon.layer,
              iconLayer.animation(forKey: timerCompletionIconAnimationKey) == nil else { return }
        // Translation follows the parent coordinates; AppKit owns the view-backed layer's flip.
        let flipped = iconLayer.superlayer?.isGeometryFlipped ?? icon.isFlipped
        guard let animation = makeTimerCompletionIconAnimation(
            reduceMotion: reduceMotion,
            isGeometryFlipped: flipped
        ) else { return }
        animation.beginTime = iconLayer.convertTime(CACurrentMediaTime(), from: nil)
        iconLayer.add(animation, forKey: timerCompletionIconAnimationKey)
    }

    private func removeIconAnimation() {
        guard let iconLayer = icon.layer else { return }
        iconLayer.removeAnimation(forKey: timerCompletionIconAnimationKey)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.transform = CATransform3DIdentity
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let localPoint = convert(point, from: superview)
        return bounds.contains(localPoint) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

@MainActor
final class TimerCompletionAlertPresenter {
    private let accessibilitySettings: AuroraAccessibilitySettings
    private var panel: NSPanel?
    private var sound: NSSound?
    private var dismissWorkItem: DispatchWorkItem?
    private var presentationGeneration = 0

    init(accessibilitySettings: AuroraAccessibilitySettings) {
        self.accessibilitySettings = accessibilitySettings
    }

    func present() {
        let panel = panel ?? makePanel()
        self.panel = panel
        presentationGeneration += 1
        dismissWorkItem?.cancel()
        position(panel)
        (panel.contentView as? TimerCompletionAlertView)?.updatePalette()
        playSound()

        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
        (panel.contentView as? TimerCompletionAlertView)?.startIconAttention()
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().alphaValue = 1
            }
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.dismiss()
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + timerCompletionAlertDisplayDuration,
            execute: workItem
        )
        DiagnosticLog.shared.record("timer.completion-alert presented")
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        (panel?.contentView as? TimerCompletionAlertView)?.stopIconAttention()
        guard let panel, panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        let generation = presentationGeneration
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.presentationGeneration == generation else { return }
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
    }

    private func dismissImmediately() {
        presentationGeneration += 1
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        (panel?.contentView as? TimerCompletionAlertView)?.stopIconAttention()
        panel?.orderOut(nil)
        panel?.alphaValue = 1
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 340, height: 92)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("timer.completion.alert")
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let background = TimerCompletionAlertView(
            frame: NSRect(origin: .zero, size: size),
            accessibilitySettings: accessibilitySettings
        )
        background.onClick = { [weak self] in self?.dismissImmediately() }
        panel.contentView = background
        return panel
    }

    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.visibleFrame
        let margin: CGFloat = 18
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panel.frame.width - margin,
            y: frame.maxY - panel.frame.height - margin
        ))
    }

    private func playSound() {
        let bundledSound = Bundle.main.url(forResource: "TimerFinished", withExtension: "mp3")
            .flatMap { NSSound(contentsOf: $0, byReference: true) }
        if let sound = bundledSound ?? NSSound(named: NSSound.Name("Glass")) {
            self.sound = sound
            sound.stop()
            sound.play()
        } else {
            NSSound.beep()
        }
    }
}
