import AppKit
import CountdownCore
import SwiftUI

private final class SubtaskTransferSmokePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private actor SubtaskTransferSmokeWriter {
    private let repository: CountdownRepository
    private var failNext = false

    init(fileURL: URL) { repository = CountdownRepository(fileURL: fileURL) }

    func failNextWrite() { failNext = true }

    func save(_ data: CountdownData, revision: Int) async throws -> Bool {
        if failNext {
            failNext = false
            throw CocoaError(.fileWriteNoPermission)
        }
        return try await repository.save(data, revision: revision)
    }
}

/// Exercises production checklist controls with synthetic data and an isolated native host.
@MainActor
final class SubtaskTransferSmokeScenario {
    private let configuration: UISmokeConfiguration
    private let timer: CountdownTimer
    private let keepAwake: KeepAwakeController
    private let weather: WeatherController
    private let accessibility: AuroraAccessibilitySettings
    private let visualEnvironment: UISmokeVisualEnvironment
    private let captureThemes: (String, NSWindow) async throws -> Void
    private let controls = UISmokeControlRegistry.shared
    private let desktopScope = "transfer-desktop."
    private let miniScope = "transfer-mini."

    init(configuration: UISmokeConfiguration, timer: CountdownTimer, keepAwake: KeepAwakeController,
         weather: WeatherController, accessibility: AuroraAccessibilitySettings,
         visualEnvironment: UISmokeVisualEnvironment,
         captureThemes: @escaping (String, NSWindow) async throws -> Void) {
        self.configuration = configuration
        self.timer = timer
        self.keepAwake = keepAwake
        self.weather = weather
        self.accessibility = accessibility
        self.visualEnvironment = visualEnvironment
        self.captureThemes = captureThemes
    }

    func run() async throws -> [String] {
        let directory = configuration.homeURL.appendingPathComponent("SubtaskTransfer", isDirectory: true)
        let fileURL = directory.appendingPathComponent("events.json")
        let suite = "CountdownSubtaskTransferSmoke.\(UUID().uuidString)"
        let defaults = try value(UserDefaults(suiteName: suite), "transfer preferences")
        let now = try value(Day.calendar.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 12)),
                            "transfer fixture clock")
        let today = Day(now)
        let tomorrow = Day(try value(Day.calendar.date(byAdding: .day, value: 1, to: now), "transfer tomorrow"))
        let emptyDate = Day(try value(Day.calendar.date(byAdding: .day, value: 2, to: now), "transfer empty day"))
        let tasks = [try Subtask(text: "Отправить документы"), try Subtask(text: "Записаться на сервис"),
                     try Subtask(text: "Разобрать фотографии"), try Subtask(text: "Заказать продукты", isCompleted: true)]
        let source = Countdown(title: "Понедельник", date: today, emoji: "", subtasks: tasks, keepsAfterDate: true)
        let receiver = Countdown(title: "Вторник", date: tomorrow, emoji: "",
                                 subtasks: [try Subtask(text: "Купить билеты")], keepsAfterDate: true)
        let full = Countdown(title: "Подготовка к поездке", date: tomorrow, emoji: "",
                             subtasks: try (1...10).map { try Subtask(text: "Пункт \($0)") }, keepsAfterDate: true)
        let writer = SubtaskTransferSmokeWriter(fileURL: fileURL)
        let fixture = Store(fileURL: fileURL, disclosureDefaults: defaults,
                            persistenceSaveOverride: { data, revision in try await writer.save(data, revision: revision) },
                            now: { now }, loginItemManagementIsAvailable: false)
        try await wait("transfer fixture loaded") { !fixture.hasPendingPersistence }
        for event in [source, receiver, full] {
            try require(await fixture.save(event, primary: false), "cannot seed transfer fixture")
        }
        fixture.setSubtasksExpanded(true, for: source.id)
        let session = EventEditorSession()
        let updates = ApplicationUpdates(info: [:], enabled: false) { nil }
        let appearance = ApplicationPreferences(defaults: defaults)
        let controller = DesktopWindowController(rootView: DesktopRootView(
            store: fixture, updates: updates, editorSession: session, keepAwake: keepAwake, weather: weather,
            accessibilitySettings: accessibility, visualEnvironment: visualEnvironment, appPreferences: appearance,
            showPanel: {}, switchToPanel: {},
            diagnosticsContext: { makeDiagnosticExportContext(timer: self.timer, updates: updates, weather: self.weather) },
            smokeControlScope: desktopScope
        ), editorSession: session)
        let window = try value(controller.window, "transfer desktop window")
        window.setContentSize(NSSize(width: 1200, height: 760))
        let mini = SubtaskTransferSmokePanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 600),
                                           styleMask: [.borderless], backing: .buffered, defer: false)
        mini.isReleasedWhenClosed = false
        mini.contentViewController = NSHostingController(rootView: CountdownManagerRootView(
            timer: timer, store: fixture, updates: updates, editorSession: session, keepAwake: keepAwake, weather: weather,
            accessibilitySettings: accessibility, visualEnvironment: visualEnvironment, appPreferences: appearance
        ).uiSmokeControlScope(miniScope))
        let previousScheme = visualEnvironment.colorSchemeOverride
        let previousContrast = accessibility.isolatedCaptureOverrideValue
        let previousMotion = accessibility.isolatedReduceMotionOverrideValue
        defer {
            session.endSubtaskTransfer()
            accessibility.setIsolatedCaptureOverrides(highContrast: previousContrast, reduceMotion: previousMotion)
            visualEnvironment.colorSchemeOverride = previousScheme
            mini.close()
            window.close()
            defaults.removePersistentDomain(forName: suite)
        }
        accessibility.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        controller.show()
        try await wait("transfer source selected") { self.controls.value(self.desktopScope + "desktop.inspector") == source.id.uuidString }
        mini.makeKeyAndOrderFront(nil)
        try await wait("transfer mini key") { mini.isKeyWindow }
        try await wait("incomplete mini transfer arrow") {
            self.controls.entries[self.miniScope + "subtask.transfer.open.\(tasks[0].id)"]?.isEnabled == true
        }
        try require(controls.entries[miniScope + "subtask.transfer.open.\(tasks[3].id)"] == nil,
                    "completed task exposes a transfer arrow")
        try await captureThemes("subtask-transfer-mini-list", mini)
        try await verifyMiniCancel(fixture: fixture, session: session, fileURL: fileURL,
                                   source: source, subtask: tasks[0], mini: mini)
        mini.orderOut(nil)
        controller.show()
        try await verifyDesktopMove(fixture: fixture, session: session, source: source,
                                   subtask: tasks[0], receiver: receiver, full: full, window: window)
        mini.makeKeyAndOrderFront(nil)
        try await verifyNewDayRetry(fixture: fixture, session: session, writer: writer, fileURL: fileURL,
                                   source: source, subtask: tasks[1], date: emptyDate)
        return [
            "native mini arrow opens an inline form; full editor excluded; Cancel and hide/show preserve saved bytes",
            "desktop arrow shares inline controls; full receiver blocks Save; one selected task retains identity on move",
            "empty date creates an ordinary day; failed native confirmation preserves both sides and retries once"
        ]
    }

    private func verifyMiniCancel(fixture: Store, session: EventEditorSession, fileURL: URL,
                                  source: Countdown, subtask: Subtask, mini: NSWindow) async throws {
        let initial = fixture.data
        let bytes = try Data(contentsOf: fileURL)
        try await press(miniScope + "subtask.transfer.open.\(subtask.id)")
        try await wait("mini inline transfer form") { self.controls.entries[self.miniScope + "subtask.transfer.form"] != nil }
        try await wait("mini transfer arrow exposes expanded state") {
            self.controls.value(self.miniScope + "subtask.transfer.open.\(subtask.id)") == "expanded"
        }
        try require(session.hasActiveEditor && !session.isPresented && !session.desktopIsPresented,
                    "inline transfer mounted a full event editor")
        try require(!session.beginPanelEditor() && !session.beginDesktopEditor(), "full editor replaced an inline transfer")
        try require(session.subtaskTransfer?.eventID == source.id, "mini transfer owns wrong event")
        try await wait("multiple targets need explicit selection") {
            self.controls.entries[self.miniScope + "subtask.transfer.confirm"]?.isEnabled == false
        }
        mini.orderOut(nil)
        mini.makeKeyAndOrderFront(nil)
        try require(session.subtaskTransfer?.subtaskID == subtask.id, "mini hide/show lost transfer choice")
        try await captureThemes("subtask-transfer-mini-inline", mini)
        accessibility.setIsolatedCaptureOverrides(highContrast: true, reduceMotion: true)
        try await captureThemes("subtask-transfer-mini-inline-contrast", mini)
        accessibility.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        try await press(miniScope + "subtask.transfer.cancel")
        try await wait("mini Cancel releases transfer") { !session.hasActiveEditor }
        try await wait("mini transfer arrow exposes collapsed state") {
            self.controls.value(self.miniScope + "subtask.transfer.open.\(subtask.id)") == "collapsed"
        }
        try require(fixture.data == initial && (try Data(contentsOf: fileURL)) == bytes,
                    "mini transfer Cancel changed saved data")
    }

    private func verifyDesktopMove(fixture: Store, session: EventEditorSession, source: Countdown,
                                   subtask: Subtask, receiver: Countdown, full: Countdown, window: NSWindow) async throws {
        try await press(desktopScope + "subtask.transfer.open.\(subtask.id)")
        try await wait("desktop inline form") { self.controls.entries[self.desktopScope + "subtask.transfer.form"] != nil }
        try require(window.attachedSheet == nil, "transfer added a desktop modal sheet")
        session.selectSubtaskTransferTarget(full.id)
        try await wait("full destination warning") {
            self.controls.value(self.desktopScope + "subtask.transfer.notice")?.contains("10") == true
                && self.controls.entries[self.desktopScope + "subtask.transfer.confirm"]?.isEnabled == false
        }
        session.selectSubtaskTransferTarget(receiver.id)
        try await wait("recipient selection updated") {
            self.controls.value(self.desktopScope + "subtask.transfer.target") == receiver.id.uuidString
                && self.controls.entries[self.desktopScope + "subtask.transfer.confirm"]?.isEnabled == true
        }
        try await captureThemes("subtask-transfer-desktop-inline", window)
        accessibility.setIsolatedCaptureOverrides(highContrast: true, reduceMotion: true)
        try await captureThemes("subtask-transfer-desktop-inline-contrast", window)
        accessibility.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        try await press(desktopScope + "subtask.transfer.confirm")
        try await wait("desktop transfer committed") { !fixture.hasPendingPersistence && !session.hasActiveEditor }
        let savedSource = try value(fixture.active.first { $0.id == source.id }, "saved transfer source")
        let savedReceiver = try value(fixture.active.first { $0.id == receiver.id }, "saved transfer receiver")
        try require(savedSource.subtasks == source.subtasks.filter { $0.id != subtask.id }, "source rows changed during move")
        try require(savedReceiver.subtasks == receiver.subtasks + [subtask], "receiver lost transferred identity or order")
        try require(fixture.active.first { $0.id == full.id } == full, "full unselected recipient changed")
    }

    private func verifyNewDayRetry(fixture: Store, session: EventEditorSession, writer: SubtaskTransferSmokeWriter,
                                   fileURL: URL, source: Countdown, subtask: Subtask, date: Day) async throws {
        try await press(miniScope + "subtask.transfer.open.\(subtask.id)")
        session.updateSubtaskTransfer(date: date)
        try await wait("empty date permits new day") {
            self.controls.entries[self.miniScope + "subtask.transfer.confirm"]?.isEnabled == true
        }
        let initial = fixture.data
        let bytes = try Data(contentsOf: fileURL)
        await writer.failNextWrite()
        try await press(miniScope + "subtask.transfer.confirm")
        try await wait("failed transfer remains available") {
            !fixture.hasPendingPersistence && fixture.error != nil
                && self.controls.entries[self.miniScope + "subtask.transfer.confirm"]?.isEnabled == true
        }
        try require(session.subtaskTransfer?.subtaskID == subtask.id && fixture.data == initial,
                    "failed transfer changed source or lost retry draft")
        try require(try Data(contentsOf: fileURL) == bytes, "failed transfer changed durable bytes")
        try await press(miniScope + "subtask.transfer.confirm")
        try await wait("new day transfer committed") { !fixture.hasPendingPersistence && !session.hasActiveEditor }
        let newDay = try value(fixture.active.first { $0.date == date }, "created transfer day")
        try require(newDay.isDay && newDay.usesAutomaticTitle && newDay.showsWeather && newDay.subtasks == [subtask],
                    "transfer did not use ordinary new-day defaults")
        try require(fixture.active.first { $0.id == source.id }?.subtasks.contains(subtask) == false,
                    "new-day transfer left a source duplicate")
    }

    private func press(_ id: String) async throws {
        try await wait("enabled \(id)") { self.controls.entries[id]?.isEnabled == true }
        try require(controls.press(id), "cannot activate \(id)")
    }

    private func wait(_ description: String, condition: @escaping () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("timeout: \(description)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }

    private func value<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { throw Failure("missing \(message)") }
        return value
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
