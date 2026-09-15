import AppKit

package let timerCompletionAlertDisplayDuration: TimeInterval = 5

@MainActor
final class TimerCompletionAlertPresenter {
    private var panel: NSPanel?
    private var sound: NSSound?
    private var dismissWorkItem: DispatchWorkItem?

    func present() {
        let panel = panel ?? makePanel()
        self.panel = panel
        dismissWorkItem?.cancel()
        position(panel)
        playSound()

        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        panel.orderFrontRegardless()
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
        guard let panel, panel.isVisible else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel.animator().alphaValue = 0
        } completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
            }
        }
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
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]

        let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true

        let icon = NSTextField(labelWithString: "⏰")
        icon.font = .systemFont(ofSize: 34)
        icon.alignment = .center
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let title = NSTextField(labelWithString: "Время вышло")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.textColor = .labelColor
        title.identifier = NSUserInterfaceItemIdentifier("timer.completion.title")

        let detail = NSTextField(labelWithString: "Таймер Countdown Manager завершён")
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 4

        let content = NSStackView(views: [icon, labels])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(lessThanOrEqualTo: background.trailingAnchor, constant: -18),
            content.centerYAnchor.constraint(equalTo: background.centerYAnchor)
        ])
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
