import AppKit
import SwiftUI

@MainActor
package final class WhatsNewHistory {
    private let defaults: UserDefaults
    private let releaseID: String
    private static let preferenceKey = "whatsNew.lastPresentedRelease"

    package init(defaults: UserDefaults, releaseID: String) {
        self.defaults = defaults
        self.releaseID = releaseID
    }

    package var hasUnseenRelease: Bool {
        defaults.string(forKey: Self.preferenceKey) != releaseID
    }

    package func markPresented() {
        defaults.set(releaseID, forKey: Self.preferenceKey)
    }
}

struct WhatsNewView: View {
    static let releaseID = "1.20.1"
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Text("Что нового")
                .font(.custom("Georgia", size: 21))
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                .padding(.horizontal, 16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Countdown Manager \(Self.releaseID)")
                        .font(.system(size: 11))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    feature("Обновление из большого окна", symbol: "arrow.triangle.2.circlepath",
                            text: "Исправлена кнопка «Установить и перезапустить» при обновлении из настроек основного окна. Установка завершается без перехода в мини-панель и ручного закрытия настроек.")
                    feature("Защита работы сохранена", symbol: "lock",
                            text: "Открытый редактор, сохранение данных, работающий таймер и экспорт диагностики по-прежнему откладывают перезапуск. Сначала завершите работу, затем явно продолжите установку.")
                    Text("Сохранение событий после даты, ссылки, файлы и текстовые вложения работают как в 1.20.")
                        .font(.system(size: 11))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            Divider()
            HStack {
                Spacer()
                Button("Понятно", action: dismiss)
                    .auroraPrimaryAction()
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("whatsnew.dismiss")
                    .uiSmokeControl(id: "whatsnew.dismiss", action: dismiss)
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
        }
        .frame(width: 430, height: 560)
        .background(AuroraPanelCanvas())
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .accessibilityIdentifier("whatsnew.content")
        .uiSmokeControl(id: "whatsnew.content", value: { Self.releaseID })
    }

    private func feature(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .semibold))
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
private final class WhatsNewWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        // This read-only window handles its own unmodified Escape before the hosting view.
        if event.type == .keyDown, event.keyCode == 0x35,
           event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            performClose(nil)
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class WhatsNewWindowController: NSWindowController, NSWindowDelegate {
    private let history: WhatsNewHistory
    private let didClose: () -> Void

    init(defaults: UserDefaults, accessibilitySettings: AuroraAccessibilitySettings, didClose: @escaping () -> Void) {
        history = WhatsNewHistory(defaults: defaults, releaseID: WhatsNewView.releaseID)
        self.didClose = didClose
        let window = WhatsNewWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 560),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Countdown Manager"
        window.identifier = NSUserInterfaceItemIdentifier("whatsnew.window")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        window.contentViewController = NSHostingController(rootView:
            WhatsNewView(dismiss: { [weak self] in self?.close() }).environmentObject(accessibilitySettings))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    var hasUnseenRelease: Bool { history.hasUnseenRelease }

    func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if window.isVisible { history.markPresented() }
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.didClose() }
    }
}
