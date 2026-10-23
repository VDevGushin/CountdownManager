import AppKit
import CountdownCore
import CryptoKit
import SwiftUI

private actor DesktopSmokeWriteGate {
    private let repository: CountdownRepository
    private var holdsNextWrite = false
    private var blockedWrite: CheckedContinuation<Void, Error>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    init(fileURL: URL) { repository = CountdownRepository(fileURL: fileURL) }

    func holdNextWrite() { holdsNextWrite = true }

    func save(_ data: CountdownData, revision: Int) async throws -> Bool {
        if holdsNextWrite {
            holdsNextWrite = false
            try await withCheckedThrowingContinuation { continuation in
                blockedWrite = continuation
                blockedWaiters.forEach { $0.resume() }
                blockedWaiters.removeAll()
            }
        }
        return try await repository.save(data, revision: revision)
    }

    func waitUntilBlocked() async {
        if blockedWrite != nil { return }
        await withCheckedContinuation { blockedWaiters.append($0) }
    }

    func release(failing: Bool = false) {
        let continuation = blockedWrite
        blockedWrite = nil
        if failing { continuation?.resume(throwing: CocoaError(.fileWriteNoPermission)) }
        else { continuation?.resume() }
    }
}

private actor DesktopSmokeForecastGate {
    private var response: [String: DailyWeatherForecast]?
    private var pending: [CheckedContinuation<[String: DailyWeatherForecast], Never>] = []

    func load() async -> [String: DailyWeatherForecast] {
        if let response { return response }
        return await withCheckedContinuation { pending.append($0) }
    }

    func hasRequest() -> Bool { !pending.isEmpty }

    func release(_ response: [String: DailyWeatherForecast]) {
        self.response = response
        pending.forEach { $0.resume(returning: response) }
        pending.removeAll()
    }
}

@MainActor
final class DesktopSmokeRuntime {
    private let configuration: UISmokeConfiguration
    private let store: Store
    private let timer: CountdownTimer
    private let editorSession: EventEditorSession
    private let keepAwake: KeepAwakeController
    private let weather: WeatherController
    private let accessibilitySettings: AuroraAccessibilitySettings
    private let visualEnvironment: UISmokeVisualEnvironment
    private let appearanceSettings: ApplicationAppearance
    private let desktopWindow: () -> NSWindow?
    private let panelWindow: () -> NSWindow?
    private let statusButton: () -> NSStatusBarButton?
    private let showDesktop: () -> Void
    private let hideDesktop: () -> Void
    private let showPanel: () -> Void
    private let pressStatusItem: () -> Void
    private var captures: [[String: Any]] = []
    private var passed: [String] = []
    private var controls: UISmokeControlRegistry { .shared }

    init(configuration: UISmokeConfiguration, store: Store, timer: CountdownTimer,
         editorSession: EventEditorSession, keepAwake: KeepAwakeController, weather: WeatherController,
         accessibilitySettings: AuroraAccessibilitySettings, visualEnvironment: UISmokeVisualEnvironment,
         appearanceSettings: ApplicationAppearance,
         desktopWindow: @escaping () -> NSWindow?, panelWindow: @escaping () -> NSWindow?,
         statusButton: @escaping () -> NSStatusBarButton?,
         showDesktop: @escaping () -> Void, hideDesktop: @escaping () -> Void, showPanel: @escaping () -> Void,
         pressStatusItem: @escaping () -> Void) {
        self.configuration = configuration
        self.store = store
        self.timer = timer
        self.editorSession = editorSession
        self.keepAwake = keepAwake
        self.weather = weather
        self.accessibilitySettings = accessibilitySettings
        self.visualEnvironment = visualEnvironment
        self.appearanceSettings = appearanceSettings
        self.desktopWindow = desktopWindow
        self.panelWindow = panelWindow
        self.statusButton = statusButton
        self.showDesktop = showDesktop
        self.hideDesktop = hideDesktop
        self.showPanel = showPanel
        self.pressStatusItem = pressStatusItem
    }

    func start() {
        let resultURL = configuration.resultURL
        DispatchQueue.global().asyncAfter(deadline: .now() + 65) {
            try? "DesktopSmoke\nFAIL: hard timeout".write(to: resultURL, atomically: true, encoding: .utf8)
            Darwin._exit(124)
        }
        Task { @MainActor in
            do {
                try await run()
                try writeManifest()
                finish("DesktopSmoke\n" + passed.map { "✓ " + $0 }.joined(separator: "\n")
                       + "\nPASS: \(passed.count)/\(passed.count)", status: 0)
            } catch {
                try? capture("failure-desktop")
                finish("DesktopSmoke\nFAIL after \(passed.count) scenarios: \(error.localizedDescription)", status: 1)
            }
        }
    }

    private func run() async throws {
        try await wait("loaded isolated store") { !self.store.isLoading }
        try require(store.active.isEmpty, "desktop fixture must start empty")
        try require(NSApp.activationPolicy() == .accessory, "menu-only startup unexpectedly appears in Dock")
        let tomorrow = Day(store.tomorrow)
        let later = Day(Day.calendar.date(byAdding: .day, value: 3, to: store.today.date())!)
        let remainingTask = try Subtask(text: "Подготовить документы")
        let today = Countdown(title: "Планы на сегодня", note: "Всё нужное для спокойного дня.",
                              date: store.today, emoji: "", subtasks: [try Subtask(text: "Проверить планы", isCompleted: true), remainingTask], showsWeather: true)
        let favorite = Countdown(title: "Поездка на выходные", note: "Маршрут, экипировка и немного свободного времени.",
                                 date: later, emoji: "🏍️", subtasks: [try Subtask(text: "Проверить маршрут"), try Subtask(text: "Подготовить экипировку")], showsWeather: true)
        let meeting = Countdown(title: "Встреча с друзьями и прогулка по городу", date: tomorrow, emoji: "☕️",
                                subtasks: [try Subtask(text: "Договориться о времени", isCompleted: true)])
        for item in [today, meeting, favorite] {
            let saved = await store.save(item, primary: item.id == favorite.id)
            try require(saved, "cannot save desktop synthetic fixture")
        }
        weather.selectLocation(.city(.moscow))
        weather.setEnabled(true)
        weather.updateEvents(store.active)
        showDesktop()
        try await wait("native desktop shown") {
            self.desktopWindow()?.isVisible == true && self.controls.entries["desktop.root"] != nil
        }
        let window = try value(desktopWindow(), "desktop window")
        let retainedContent = try value(window.contentView, "desktop content")
        try require(NSApp.activationPolicy() == .regular, "desktop did not use regular activation")
        try require(!window.collectionBehavior.contains(.moveToActiveSpace)
                    && !window.collectionBehavior.contains(.canJoinAllSpaces),
                    "desktop overrides the standard user-controlled Spaces behavior")
        try await wait("desktop default selection") { self.controls.entries["desktop.detail.\(favorite.id)"] != nil }
        try await expect("desktop.date.detail.\(favorite.id)", "\(favorite.emoji) \(humanDateLabel(favorite.date))")
        try await wait("shared weather available") { self.weather.forecast(for: self.store.today) != nil }
        let divider = try await positionDivider(in: window, fraction: 0.58)
        try await checkFavorite(favorite.id)
        try await requireCollectionFooters([today.id, meeting.id])
        try require(controls.entries["desktop.favorite-filter"] == nil, "redundant favorite-only filter remains visible")
        try await captureThemes("desktop-collection")
        try await press("desktop.mode")
        try await expect("desktop.mode", "feed")
        try await requireDivider(divider, in: window, after: "view mode switch")
        try await checkFavorite(favorite.id)
        try require(controls.entries["desktop.favorite-filter"] == nil, "feed still exposes a favorite-only filter")
        try await captureThemes("desktop-feed")
        passed.append("collection/feed retain one explicit favorite and use the same shared events/weather")

        try await press("desktop.event.\(today.id)")
        try await wait("today details") { self.controls.entries["desktop.detail.\(today.id)"] != nil }
        try await requireDivider(divider, in: window, after: "event selection")
        try await expect("desktop.date.detail.\(today.id)", humanDateLabel(today.date))
        let completedTask = try value(today.subtasks.first { $0.isCompleted }, "completed grouping fixture")
        try await requireTaskOrder(first: remainingTask.id, second: completedTask.id)
        try await press("desktop.mode")
        try await requireTaskOrder(first: remainingTask.id, second: completedTask.id)
        try await captureThemes("desktop-mixed-checklist")
        try await press("desktop.mode")
        let originalMotion = accessibilitySettings.isolatedReduceMotionOverrideValue
        let originalContrast = accessibilitySettings.isolatedCaptureOverrideValue
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: originalContrast, reduceMotion: false)
        try await captureChecklistToggle("desktop-checklist-complete-motion", item: today,
                                         taskID: remainingTask.id, window: window)
        try await wait("desktop checklist completed") {
            self.store.active.first { $0.id == today.id }?.subtasks.allSatisfy(\.isCompleted) == true
                && self.controls.entries["desktop.checklist.complete"] != nil
        }
        try await captureChecklistToggle("desktop-checklist-reopen-motion", item: today,
                                         taskID: remainingTask.id, window: window)
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "off")
        try await requireTaskOrder(first: remainingTask.id, second: completedTask.id)
        try require(store.active.first { $0.id == today.id }?.subtasks.map(\.id) == today.subtasks.map(\.id),
                    "display grouping reordered persisted subtask identities")
        try await press("desktop.subtask.toggle.\(remainingTask.id)")
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "on")
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: originalContrast, reduceMotion: true)
        try await captureChecklistToggle("desktop-checklist-reopen-reduced", item: today,
                                         taskID: remainingTask.id, window: window)
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "off")
        try await requireTaskOrder(first: remainingTask.id, second: completedTask.id)
        try await captureChecklistToggle("desktop-checklist-complete-reduced", item: today,
                                         taskID: remainingTask.id, window: window)
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "on")
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: originalContrast, reduceMotion: originalMotion)
        try await requireDivider(divider, in: window, after: "checklist changes")
        passed.append("mixed checklist groups active before completed in both views; reopening regroups without changing stored order")
        showPanel()
        try await expect("subtask.toggle.\(remainingTask.id)", "completed")
        try await expect("subtasks.progress.\(today.id)", "2/2")
        try await wait("panel renders completed checklist") {
            self.controls.entries["subtasks.complete.\(today.id)"] != nil
        }
        let linkedPanel = try value(panelWindow(), "linked menu panel")
        linkedPanel.appearance = NSAppearance(named: .aqua)
        try capture("desktop-linked-panel", window: linkedPanel)
        try await press("event.primary.\(favorite.id)")
        try await wait("panel clears shared favorite") { self.store.data.primaryID == nil }
        showDesktop()
        try await checkFavorite(nil)
        try await requireDivider(divider, in: window, after: "shared favorite change")
        try await captureThemes("desktop-unfavorited")
        passed.append("desktop checklist and panel favorite changes propagate without a second store or fallback featured card")

        for size in [NSSize(width: 960, height: 640), NSSize(width: 1200, height: 800)] {
            window.setContentSize(size)
            try await wait("split pane minimum thirds") {
                guard let split = self.controls.frame("desktop.split"),
                      let overview = self.controls.frame("desktop.overview"),
                      let inspector = self.controls.frame("desktop.inspector") else { return false }
                let minimum = desktopMinimumPaneWidth(contentWidth: split.width)
                return overview.width >= minimum - 1 && inspector.width >= minimum - 1
                    && overview.maxX <= inspector.minX + 2
            }
            try requireDetailHeaderBounds()
        }
        passed.append("native split panes retain a third of content width and 320pt floor at minimum/large window sizes")
        let resizedDivider = try await positionDivider(in: window, fraction: 0.42)
        passed.append("divider grip covers a 12pt band at native divider positions and passes pane content through")

        try await press("desktop.detail.edit")
        try await wait("desktop owns editor") { self.editorSession.desktopIsPresented && window.attachedSheet != nil }
        try await replaceFocusedText(control: "editor.title", text: "Черновик большого окна")
        let before = store.data
        try require(!controls.press("desktop.panel") && window.isVisible,
                    "compact-mode button hid an active desktop draft")
        window.performClose(nil)
        hideDesktop()
        try require(window.isVisible && editorSession.desktopIsPresented, "desktop close discarded an active editor")
        showPanel()
        try await wait("panel mutations blocked") { self.controls.entries["event.add"]?.isEnabled == false }
        try require(!controls.press("event.add") && store.data == before, "panel stole the desktop draft")
        showDesktop()
        try await expect("editor.title", "Черновик большого окна")
        try await press("editor.cancel")
        try await wait("desktop editor cancelled") { !self.editorSession.hasActiveEditor && window.attachedSheet == nil }
        try require(store.data == before, "desktop Cancel changed stored events")
        try await requireDivider(resizedDivider, in: window, after: "editor open and Cancel")
        try await press("desktop.detail.edit")
        try await replaceFocusedText(control: "editor.title", text: "Сегодня: всё готово")
        try await press("editor.save")
        try await wait("desktop Save is shared and durable") {
            !self.editorSession.hasActiveEditor
                && self.store.active.contains { $0.id == today.id && $0.title == "Сегодня: всё готово" }
                && !self.store.hasPendingPersistence
        }
        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(persisted == store.data, "desktop Save did not persist the shared state")
        try await requireDivider(resizedDivider, in: window, after: "editor Save")
        let savedToday = try value(store.active.first { $0.id == today.id }, "saved selected event")
        let previousToday = try value(before.items.first { $0.id == today.id }, "pre-edit selected event")
        try require(savedToday.subtasks == previousToday.subtasks && savedToday.note == previousToday.note
                    && savedToday.date == previousToday.date && savedToday.emoji == previousToday.emoji
                    && savedToday.showsWeather == previousToday.showsWeather
                    && store.data.primaryID == before.primaryID,
                    "title editing overwrote a newer shared checklist or another event field")
        passed.append("one editor owner protects drafts across surfaces; native close veto, Cancel and durable Save preserve identity")

        showPanel()
        try await press("event.edit.\(today.id)")
        try await wait("panel editor ownership") { self.editorSession.isPresented }
        showDesktop()
        try await wait("desktop blocked by panel editor") { self.controls.entries["desktop.editor-busy"] != nil }
        try require(controls.entries["desktop.create"]?.isEnabled == false, "desktop create remained enabled with a panel draft")
        showPanel()
        try await press("editor.cancel")
        try await wait("panel editor released") { !self.editorSession.hasActiveEditor }
        showDesktop()
        passed.append("reverse panel-to-desktop editor exclusion keeps the original draft owner")

        try await press("desktop.settings")
        try await wait("centered desktop settings pane") { self.controls.frame("desktop.settings.pane") != nil }
        let settingsPane = try value(controls.frame("desktop.settings.pane"), "settings pane frame")
        try require(abs(settingsPane.width - 430) < 1 && abs(settingsPane.height - 560) < 1,
                    "settings pane lost its usable 430 × 560-point size")
        try require(window.attachedSheet == nil, "settings still use a native sheet instead of a dismissible overlay")
        try require(!NSApp.windows.contains { $0.identifier?.rawValue == "settings.window" },
                    "desktop settings created a separate native window")
        try require(controls.entries["settings.close"] != nil && controls.entries["settings.back"] == nil,
                    "desktop settings lost their close button or retained panel-only Back navigation")
        try require(!controls.press("desktop.event.\(meeting.id)") && !controls.press("desktop.panel"),
                    "settings overlay left background events or compact navigation interactive")
        let settingsBeforeEdit = store.data
        try await checkSharedAppearance(window: window, divider: resizedDivider)
        try await press("desktop.settings.backdrop")
        try await wait("settings backdrop dismisses pane") { self.controls.entries["desktop.settings.pane"] == nil }
        try require(store.data == settingsBeforeEdit && controls.entries["desktop.detail.\(today.id)"] != nil,
                    "settings dismissal activated an underlying event or changed data")
        try await requireDivider(resizedDivider, in: window, after: "settings backdrop dismissal")
        try await press("desktop.detail.edit")
        try await wait("event editor remains a protected sheet") {
            self.editorSession.desktopIsPresented && window.attachedSheet != nil
        }
        try await replaceFocusedText(control: "editor.title", text: "Черновик после настроек")
        try await captureEditorThemes(window: window)
        try await press("editor.cancel")
        try await wait("editor Cancel after settings") { !self.editorSession.hasActiveEditor && window.attachedSheet == nil }
        try require(store.data == settingsBeforeEdit, "settings/editor Cancel changed events")
        try await press("desktop.settings")
        try await press("settings.diagnostics")
        try await wait("diagnostic Save dialog belongs to desktop host") { window.attachedSheet is NSSavePanel }
        let diagnosticPanel = try value(window.attachedSheet as? NSSavePanel, "settings diagnostic Save dialog")
        _ = controls.press("desktop.settings.backdrop")
        try require(controls.entries["desktop.settings.pane"] != nil && window.attachedSheet === diagnosticPanel,
                    "settings backdrop dismissed the host of an active diagnostic Save dialog")
        diagnosticPanel.cancel(nil)
        try await wait("diagnostic Cancel releases settings") {
            window.attachedSheet == nil && !self.store.isExportingDiagnostics
        }
        try require(store.data == settingsBeforeEdit, "diagnostic Cancel changed event data")
        try await press("settings.weather.enabled")
        try await wait("weather disabled in shared settings") { !self.weather.enabled }
        try await press("settings.close")
        try await wait("settings close button dismisses pane") { self.controls.entries["desktop.settings.pane"] == nil }
        try await requireDivider(resizedDivider, in: window, after: "settings open and close")
        try require(weather.forecast(for: store.today) == nil, "disabled shared weather still supplies a forecast")
        try capture("desktop-weather-off")
        passed.append("centered settings pane has a close button; backdrop dismisses without activating background events or moving divider, and diagnostic Cancel releases its guard")
        passed.append("desktop settings disable forecast supply through the shared weather owner")
        showPanel()
        try await press("settings.open")
        try await expect("settings.appearance", appearanceSettings.selection.rawValue)
        appearanceSettings.setSelection(.dark)
        try await expect("settings.appearance", "dark")
        try await press("settings.back")
        showDesktop()
        appearanceSettings.setSelection(.system)
        passed.append("system, light and dark preferences propagate through both native windows and both settings hosts")

        try await press("desktop.event.\(today.id)")
        try await wait("restore today selection after settings dismissal check") {
            self.controls.entries["desktop.detail.\(today.id)"] != nil
        }
        timer.start(minutes: 5)
        try require(timer.deadline != nil, "cannot start shared timer")
        try await wait("shared timer rendered in status item before panel interaction") {
            guard let button = self.statusButton(), let title = self.timer.statusTitle else { return false }
            return button.title == title && button.toolTip == self.timer.statusToolTip
                && self.controls.entries["timer.running"] != nil
        }
        try require(controls.ids(withPrefix: "desktop.timer.").isEmpty,
                    "desktop still exposes timer controls")
        try capture("desktop-no-timer-running")
        let savedDeadline = timer.deadline
        try await wait("previous panel dismissal reached WindowServer before status interaction") {
            guard let panel = self.panelWindow() else { return false }
            return !panel.isVisible && !panel.occlusionState.contains(.visible)
        }
        pressStatusItem()
        try await wait("status item opens panel without hiding desktop") {
            self.panelWindow()?.isVisible == true && self.panelWindow()?.isKeyWindow == true
                && window.isVisible && NSApp.isActive
        }
        try await requirePanelStaysVisible()
        try await requireTimerDeleteSpacing(prefix: "timer", label: "running", adjacent: false)
        pressStatusItem()
        try await wait("status item hides only panel") {
            self.panelWindow()?.isVisible == false && window.isVisible
        }
        try await press("desktop.panel")
        try await wait("explicit compact-mode transition") {
            !window.isVisible && self.panelWindow()?.isVisible == true
                && self.panelWindow()?.isKeyWindow == true && NSApp.isActive
        }
        try await requirePanelStaysVisible()
        try require(NSApp.activationPolicy() == .regular, "compact transition changed the desktop application role")
        try await press("desktop.open")
        try await wait("compact-mode return retains window and selection") {
            window.isVisible && window.contentView === retainedContent && self.panelWindow()?.isVisible == false
                && self.controls.entries["desktop.detail.\(today.id)"] != nil
                && self.controls.value("desktop.mode") == "feed"
        }
        try require(timer.deadline == savedDeadline, "compact-mode transition reset the shared timer")
        try await press("desktop.panel")
        try await wait("second compact-mode transition") {
            !window.isVisible && self.panelWindow()?.isKeyWindow == true
        }
        pressStatusItem()
        try await wait("compact panel dismissal preserves desktop application role") {
            self.panelWindow()?.isVisible == false && NSApp.activationPolicy() == .regular
        }
        showDesktop()
        try await wait("desktop returns after compact panel dismissal") { window.isVisible }
        passed.append("explicit compact-mode transition hides only desktop; status-item toggling preserves it and return retains selection/view/timer")
        hideDesktop()
        try await wait("desktop close retains application role") { !window.isVisible && NSApp.activationPolicy() == .regular }
        showPanel()
        try await press("desktop.open")
        try await wait("desktop reopened with retained content") { window.isVisible && window.contentView === retainedContent }
        try require(timer.deadline == savedDeadline, "desktop close/reopen replaced the shared timer")
        timer.delete()
        let deleted = await store.delete(today.id)
        try require(deleted, "cannot delete selected isolated event")
        try await wait("deleted selection reconciled") {
            self.controls.entries["desktop.detail.\(today.id)"] == nil
                && self.controls.entries["desktop.detail.\(meeting.id)"] != nil
        }
        passed.append("menu-only startup promotes once; close/reopen and compact dismissal retain desktop role, hierarchy and timer; selection reconciles")
        try await checkFilteredCreation(divider: resizedDivider, window: window)
        try await requireDivider(resizedDivider, in: window, after: "search empty state and creation")
        passed.append("nondefault native divider positions survive selection, mode, checklist, favorite, editor, settings and search-empty transitions")
        try await verifyPendingDesktopActions()
        try await verifyMonthlyBrowsing()
        try await verifyWeatherGeometry()
    }

    private func nativeSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 2 {
            return split
        }
        return view.subviews.lazy.compactMap { self.nativeSplit(in: $0) }.first
    }

    private func verifyWeatherGeometry() async throws {
        let retainedWindow = try value(desktopWindow(), "retained weather geometry window")
        let suite = configuration.defaultsSuiteName + ".weather-geometry"
        let defaults = try value(UserDefaults(suiteName: suite), "weather geometry defaults")
        let fixture = Store(fileURL: configuration.homeURL.appendingPathComponent("WeatherGeometry/events.json"),
                            disclosureDefaults: defaults, loginItemManagementIsAvailable: false)
        let gate = DesktopSmokeForecastGate()
        let fixtureWeather = WeatherController(defaults: defaults, provider: { _ in await gate.load() },
                                               allowLocationRequests: false)
        let session = EventEditorSession()
        let fixtureUpdates = ApplicationUpdates(info: [:], enabled: false) { nil }
        try await wait("weather geometry store loaded") { !fixture.isLoading }
        let favorite = Countdown(title: "Главная поездка", note: "Заметка остаётся на месте при загрузке погоды.",
                                 date: fixture.today, emoji: "", subtasks: [try Subtask(text: "Подготовить вещи")], showsWeather: true)
        let ordinary = Countdown(title: "Встреча с друзьями с длинным названием для узкой карточки",
                                 date: Day(fixture.tomorrow), emoji: "☕️", showsWeather: true)
        let missingDate = Day(try value(Day.calendar.date(byAdding: .day, value: 3, to: fixture.today.date()), "missing forecast day"))
        let missing = Countdown(title: "Событие без прогноза", date: missingDate, emoji: "", showsWeather: true)
        for event in [favorite, ordinary, missing] {
            let saved = await fixture.save(event, primary: event.id == favorite.id)
            try require(saved, "cannot seed weather geometry fixture")
        }
        fixtureWeather.selectLocation(.city(.moscow))
        fixtureWeather.updateEvents(fixture.active)
        let controller = DesktopWindowController(rootView: DesktopRootView(
            store: fixture, updates: fixtureUpdates, editorSession: session, keepAwake: keepAwake,
            weather: fixtureWeather, accessibilitySettings: accessibilitySettings, visualEnvironment: visualEnvironment,
            appearanceSettings: ApplicationAppearance(defaults: defaults), showPanel: {}, switchToPanel: {},
            diagnosticsContext: { makeDiagnosticExportContext(timer: self.timer, updates: fixtureUpdates, weather: fixtureWeather) }
        ), editorSession: session)
        let window = try value(controller.window, "weather geometry fixture window")
        window.setContentSize(NSSize(width: 960, height: 800))
        retainedWindow.orderOut(nil)
        controller.show()
        defer {
            fixtureWeather.shutdown()
            Task { await gate.release([:]) }
            window.close()
            retainedWindow.makeKeyAndOrderFront(nil)
            defaults.removePersistentDomain(forName: suite)
        }
        try await wait("weather geometry detail rendered") { self.controls.entries["desktop.detail.\(favorite.id)"] != nil }
        let identifiers = ["desktop.overview.header", "desktop.detail.identity", "desktop.detail.note", "desktop.detail.checklist"]
            + [favorite, ordinary, missing].map { "desktop.presentation.\($0.id)" }
        let baseline = try weatherGeometry(identifiers)
        fixtureWeather.setEnabled(true)
        let requestDeadline = ProcessInfo.processInfo.systemUptime + 6
        while !(await gate.hasRequest()) {
            try require(ProcessInfo.processInfo.systemUptime < requestDeadline, "synthetic weather request did not start")
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        try await expect("desktop.weather.detail.\(favorite.id)", "absent")
        try await requireWeatherGeometry(baseline, after: "pending forecast")
        try capture("desktop-weather-pending", window: window)
        let forecast = try value(DailyWeatherForecast(weatherCode: 1, maximumTemperature: 14), "synthetic daily forecast")
        await gate.release([weatherDayKey(favorite.date): forecast, weatherDayKey(ordinary.date): forecast])
        try await expect("desktop.weather.detail.\(favorite.id)", "available")
        try await expect("desktop.weather.browser.\(missing.id)", "absent")
        try await requireWeatherGeometry(baseline, after: "pending to available forecast")
        try capture("desktop-weather-loaded", window: window)
        for fraction in [CGFloat(0.34), 0.66] {
            let divider = try await positionDivider(in: window, fraction: fraction)
            for mode in ["collection", "feed"] {
                if controls.value("desktop.mode") != mode { try await press("desktop.mode") }
                try await expect("desktop.mode", mode)
                try await Task.sleep(nanoseconds: 180_000_000)
                let stable = try weatherGeometry(identifiers)
                fixtureWeather.setEnabled(false)
                try await expect("desktop.weather.overview", "absent")
                try await expect("desktop.weather.detail.\(favorite.id)", "absent")
                try await requireWeatherGeometry(stable, after: "global weather OFF in \(mode) at \(fraction)")
                fixtureWeather.setEnabled(true)
                try await expect("desktop.weather.detail.\(favorite.id)", "available")
                try await requireWeatherGeometry(stable, after: "global weather ON in \(mode) at \(fraction)")
                var hiddenWeather = favorite
                hiddenWeather.showsWeather = false
                let hiddenSaved = await fixture.save(hiddenWeather, primary: true)
                try require(hiddenSaved, "cannot disable isolated per-event weather")
                fixtureWeather.updateEvents(fixture.active)
                try await expect("desktop.weather.detail.\(favorite.id)", "absent")
                try await expect("desktop.weather.browser.\(favorite.id)", "absent")
                try await requireWeatherGeometry(stable, after: "per-event weather OFF in \(mode) at \(fraction)")
                let restored = await fixture.save(favorite, primary: true)
                try require(restored, "cannot restore isolated per-event weather")
                fixtureWeather.updateEvents(fixture.active)
                try await expect("desktop.weather.detail.\(favorite.id)", "available")
                try await requireWeatherGeometry(stable, after: "per-event weather ON in \(mode) at \(fraction)")
                try await requireDivider(divider, in: window, after: "weather visibility changes")
                try capture("desktop-weather-stable-\(mode)-\(Int(fraction * 100))", window: window)
            }
        }
        try require(fixture.data.items == [favorite, ordinary, missing] && fixture.data.primaryID == favorite.id,
                    "weather presentation checks altered event fields or identities")
        passed.append("synthetic pending/loaded, missing, global and per-event weather preserve overview/card/detail geometry in narrow/wide collection and feed")
    }

    private func weatherGeometry(_ identifiers: [String]) throws -> [String: CGRect] {
        try Dictionary(uniqueKeysWithValues: identifiers.map { identifier in
            (identifier, try value(controls.frame(identifier), "weather geometry \(identifier)"))
        })
    }

    private func requireWeatherGeometry(_ expected: [String: CGRect], after action: String) async throws {
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 20_000_000)
            for (identifier, frame) in expected {
                let current = try value(controls.frame(identifier), "retained weather geometry \(identifier)")
                try require(abs(current.minX - frame.minX) < 1 && abs(current.minY - frame.minY) < 1
                            && abs(current.width - frame.width) < 1 && abs(current.height - frame.height) < 1,
                            "weather changed \(identifier) geometry after \(action): expected \(frame), actual \(current)")
            }
        }
    }

    private func verifyMonthlyBrowsing() async throws {
        let retainedWindow = try value(desktopWindow(), "retained monthly window")
        let fixtureURL = configuration.homeURL.appendingPathComponent("MonthlyBrowsing/events.json")
        let suite = configuration.defaultsSuiteName + ".monthly-browsing"
        let defaults = try value(UserDefaults(suiteName: suite), "monthly browsing defaults")
        let fixture = Store(fileURL: fixtureURL, disclosureDefaults: defaults,
                            loginItemManagementIsAvailable: false)
        let session = EventEditorSession()
        let updates = ApplicationUpdates(info: [:], enabled: false) { nil }
        let originalMotion = accessibilitySettings.isolatedReduceMotionOverrideValue
        let originalContrast = accessibilitySettings.isolatedCaptureOverrideValue
        let originalScheme = visualEnvironment.colorSchemeOverride
        try await wait("monthly fixture loaded") { !fixture.isLoading }
        let anchor = try value(Day.calendar.date(from: DateComponents(year: fixture.today.year,
                                                                     month: fixture.today.month, day: 1)),
                               "monthly date anchor")
        let future = { (months: Int, day: Int) throws -> Day in
            let month = try self.value(Day.calendar.date(byAdding: .month, value: months, to: anchor),
                                       "monthly date")
            return Day(try self.value(Day.calendar.date(byAdding: .day, value: day - 1, to: month),
                                      "monthly day"))
        }
        let favorite = Countdown(title: "Главная поездка", note: "Отдельная карточка, не ещё одна группа месяца.",
                                 date: try future(1, 12), emoji: "🏍️")
        let sparse = [
            Countdown(title: "Планы на сегодня", date: fixture.today, emoji: ""),
            Countdown(title: "Вечер с друзьями", date: fixture.today, emoji: "☕️"),
            Countdown(title: "Зимняя прогулка", date: try future(2, 10), emoji: "❄️"),
            Countdown(title: "Путешествие в новом году", date: try future(14, 15), emoji: "✈️")
        ]
        for event in sparse + [favorite] {
            let saved = await fixture.save(event, primary: event.id == favorite.id)
            try require(saved, "cannot seed monthly fixture")
        }
        let controller = DesktopWindowController(rootView: DesktopRootView(
            store: fixture, updates: updates, editorSession: session, keepAwake: keepAwake,
            weather: weather, accessibilitySettings: accessibilitySettings, visualEnvironment: visualEnvironment,
            appearanceSettings: ApplicationAppearance(defaults: defaults), showPanel: {}, switchToPanel: {},
            diagnosticsContext: { makeDiagnosticExportContext(timer: self.timer, updates: updates, weather: self.weather) }
        ), editorSession: session)
        let window = try value(controller.window, "monthly browsing window")
        window.setContentSize(NSSize(width: 1200, height: 900))
        retainedWindow.orderOut(nil)
        controller.show()
        defer {
            window.close()
            retainedWindow.makeKeyAndOrderFront(nil)
            defaults.removePersistentDomain(forName: suite)
            accessibilitySettings.setIsolatedCaptureOverrides(highContrast: originalContrast, reduceMotion: originalMotion)
            visualEnvironment.colorSchemeOverride = originalScheme
        }
        try await wait("monthly fixture rendered") { self.controls.entries["desktop.detail.\(favorite.id)"] != nil }
        let divider = try await positionDivider(in: window, fraction: 0.61)
        let expected = DesktopEventCollection(items: fixture.active, today: fixture.today, primaryID: favorite.id, query: "")
        try require(expected.monthSections.count == 3, "sparse fixture does not cross three months and years")
        for section in expected.monthSections {
            try await expect("desktop.month.\(section.id)", section.title)
        }
        try await wait("favorite precedes chronologically ordered month headings") {
            let frames = expected.monthSections.compactMap { self.controls.frame("desktop.month.\($0.id)") }
            guard frames.count == expected.monthSections.count,
                  let first = frames.first,
                  let favoriteFrame = self.controls.frame("desktop.event.\(favorite.id)") else { return false }
            return favoriteFrame.maxY < first.minY && zip(frames, frames.dropFirst()).allSatisfy { pair in
                pair.0.maxY < pair.1.minY
            }
        }
        let favoriteMonth = favorite.date.year * 12 + favorite.date.month
        try require(controls.entries["desktop.month.\(favoriteMonth)"] == nil,
                    "favorite-only month leaves an empty ordinary section")
        try await expect("desktop.presentation.\(favorite.id)", "favorite")
        try await captureMonthlyThemes("desktop-monthly-collection", window: window)
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: false)
        try await captureModeSequence("desktop-mode-to-feed", window: window, events: sparse)
        passed.append("mode changes retain the same calendar, title, metadata and completion view owners instead of replacing card contents")
        try await captureMonthlyThemes("desktop-monthly-feed", window: window)
        for section in expected.monthSections {
            try await expect("desktop.month.\(section.id)", section.title)
        }
        try await requireDivider(divider, in: window, after: "monthly collection/feed transition")
        passed.append("ordinary native events have month/year headings in both views; favorite remains separate without an empty favorite-only month")

        try await captureModeSequence("desktop-mode-to-collection", window: window, events: sparse)
        for _ in 0..<7 {
            try require(controls.press("desktop.mode"), "rapid view switch rejected")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await requireBrowsingMode("feed", events: sparse)
        try await requireDivider(divider, in: window, after: "rapid alternating modes")
        try capture("desktop-mode-rapid-last-feed", window: window)
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        try require(accessibilitySettings.prefersReducedMotion, "monthly Reduce Motion override was not applied")
        try await captureModeSequence("desktop-mode-reduced", window: window, events: sparse)
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: false)
        try require(controls.press("desktop.mode"), "live motion mode switch rejected")
        try await Task.sleep(nanoseconds: 35_000_000)
        try capture("desktop-mode-live-before-reduced", window: window)
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        try capture("desktop-mode-live-after-reduced", window: window)
        try await Task.sleep(nanoseconds: 35_000_000)
        try capture("desktop-mode-live-reduced-35ms", window: window)
        try require(controls.press("desktop.mode"), "live Reduce Motion reverse switch rejected")
        try await requireBrowsingMode("collection", events: sparse)
        try capture("desktop-mode-live-reduced", window: window)
        try await requireDivider(divider, in: window, after: "live Reduce Motion reversal")
        passed.append("rapid alternating modes accept the final tap; reduced-motion and live mid-transition reversal retain event identities, favorite and native divider")

        let beforeSearch = fixture.data
        try await replaceFocusedText(control: "desktop.search", text: "Не существующая группа месяца")
        try await wait("monthly search removes fixture cards and headings") {
            (sparse + [favorite]).allSatisfy { self.controls.entries["desktop.event.\($0.id)"] == nil }
                && expected.monthSections.allSatisfy { self.controls.entries["desktop.month.\($0.id)"] == nil }
        }
        try await requireDivider(divider, in: window, after: "monthly search no results")
        try capture("desktop-monthly-search-empty", window: window)
        try await replaceFocusedText(control: "desktop.search", text: "")
        try await requireBrowsingMode("collection", events: sparse)
        try require(fixture.data == beforeSearch, "monthly browsing changed persisted events")
        passed.append("search no-results removes empty month headings and restoration preserves events, favorite and split position")

        for index in 0..<40 {
            let date = Day(try value(Day.calendar.date(byAdding: .day, value: index * 2,
                                                      to: try future(3, 1).date()), "long-list date"))
            let event = Countdown(title: "План \(index + 1): подготовить всё необходимое", date: date, emoji: "")
            let saved = await fixture.save(event, primary: false)
            try require(saved, "cannot seed long monthly fixture")
        }
        let ordinary = DesktopEventCollection(items: fixture.active, today: fixture.today,
                                              primaryID: favorite.id, query: "").ordinary
        try await requireBrowsingMode("collection", events: ordinary)
        let content = try value(window.contentView, "long-list content")
        let split = try value(nativeSplit(in: content), "long-list split")
        let scroll = try value(nativeScroll(in: split.arrangedSubviews[0]), "native browser scroll")
        try await wait("long-list scroll overflow") {
            (scroll.documentView?.bounds.height ?? 0) > scroll.contentView.bounds.height * 2
        }
        try scrollBrowser(scroll, toEnd: true)
        let last = try value(ordinary.last, "last monthly event")
        try await requireVisibleBrowserEvent(last.id)
        try await press("desktop.event.\(last.id)")
        try await wait("last long-list event selected") { self.controls.entries["desktop.detail.\(last.id)"] != nil }
        try capture("desktop-monthly-long-end-collection", window: window)
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: false)
        try await captureModeSequence("desktop-mode-long-to-feed", window: window, events: ordinary)
        try scrollBrowser(scroll, toEnd: true)
        try await requireVisibleBrowserEvent(last.id)
        try capture("desktop-monthly-long-end-feed", window: window)
        try await requireDivider(divider, in: window, after: "long-list scroll, selection and view change")
        for _ in 0..<7 {
            try require(controls.press("desktop.mode"), "rapid long-list switch rejected")
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await requireBrowsingMode("collection", events: ordinary)
        try await requireDivider(divider, in: window, after: "rapid long-list mode switching")
        try scrollBrowser(scroll, toEnd: false)
        try await expect("desktop.presentation.\(favorite.id)", "favorite")
        passed.append("forty additional events remain scrollable through the final month in grid/list, selectable at the end and retain favorite and divider")
    }

    private func captureMonthlyThemes(_ name: String, window: NSWindow) async throws {
        for scheme in [ColorScheme.dark, .light] {
            visualEnvironment.colorSchemeOverride = scheme
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            try await Task.sleep(nanoseconds: 300_000_000)
            try capture("\(name)-\(scheme == .dark ? "dark" : "light")", window: window)
        }
    }

    private func captureChecklistToggle(_ name: String, item: Countdown, taskID: UUID, window: NSWindow) async throws {
        let identifiers = item.subtasks.map { "desktop.subtask.toggle.\($0.id)" }
        let owners = try Dictionary(uniqueKeysWithValues: identifiers.map { identifier in
            (identifier, try value(controls.entries[identifier]?.ownerID, "checklist row owner \(identifier)"))
        })
        let started = ProcessInfo.processInfo.systemUptime
        try require(controls.press("desktop.subtask.toggle.\(taskID)"), "sampled checklist action rejected")
        let offsets = accessibilitySettings.prefersReducedMotion ? [0, 30] : [0, 40, 90, 180]
        for milliseconds in offsets {
            let delay = started + Double(milliseconds) / 1_000 - ProcessInfo.processInfo.systemUptime
            try await Task.sleep(nanoseconds: UInt64(max(0.001, delay) * 1_000_000_000))
            for identifier in identifiers {
                try require(controls.entries[identifier]?.ownerID == owners[identifier],
                            "checklist reorder replaced a stable row owner \(identifier)")
            }
            try capture("\(name)-\(milliseconds)ms", window: window)
            captures[captures.count - 1]["requestedOffsetMilliseconds"] = milliseconds
            captures[captures.count - 1]["elapsedMilliseconds"] = (ProcessInfo.processInfo.systemUptime - started) * 1_000
            captures[captures.count - 1]["checklistRowY"] = Dictionary(uniqueKeysWithValues: identifiers.map {
                ($0, controls.frame($0)?.minY ?? -1)
            })
        }
    }

    private func captureModeSequence(_ name: String, window: NSWindow, events: [Countdown]) async throws {
        let expected = controls.value("desktop.mode") == "collection" ? "feed" : "collection"
        let owners = try cardContentOwners(events)
        let started = ProcessInfo.processInfo.systemUptime
        try require(controls.press("desktop.mode"), "sampled mode switch rejected")
        for milliseconds in [0, 100, 240] {
            let delay = started + Double(milliseconds) / 1_000 - ProcessInfo.processInfo.systemUptime
            try await Task.sleep(nanoseconds: UInt64(max(0.001, delay) * 1_000_000_000))
            let currentOwners = try cardContentOwners(events)
            try require(currentOwners == owners, "view mode replaced a card's content hierarchy")
            try capture("\(name)-\(milliseconds)ms", window: window)
            captures[captures.count - 1]["requestedOffsetMilliseconds"] = milliseconds
            let capturedAt = captures[captures.count - 1]["observationUptime"] as? Double ?? started
            captures[captures.count - 1]["elapsedMilliseconds"] = (capturedAt - started) * 1_000
        }
        try await requireBrowsingMode(expected, events: events)
    }

    private func cardContentOwners(_ events: [Countdown]) throws -> [String: ObjectIdentifier] {
        let identifiers = events.flatMap { event in
            ["leaf", "title", "metadata", "completion"].map { "desktop.card.\($0).\(event.id)" }
                + ["desktop.collection.remaining.\(event.id)"]
        }
        return try Dictionary(uniqueKeysWithValues: identifiers.map { identifier in
            (identifier, try value(controls.entries[identifier]?.ownerID, "card content owner \(identifier)"))
        })
    }

    private func requireBrowsingMode(_ expected: String, events: [Countdown]) async throws {
        try await wait("monthly browser reaches \(expected) without losing event identities") {
            self.controls.value("desktop.mode") == expected && events.allSatisfy {
                self.controls.value("desktop.presentation.\($0.id)") == expected
                    && self.controls.entries["desktop.event.\($0.id)"]?.isEnabled == true
            }
        }
    }

    private func nativeScroll(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.nativeScroll(in: $0) }.first
    }

    private func requireVisibleBrowserEvent(_ id: UUID) async throws {
        try await wait("last monthly event is rendered inside browser viewport") {
            guard let viewport = self.controls.frame("desktop.browser"),
                  let event = self.controls.frame("desktop.event.\(id)") else { return false }
            return event.intersection(viewport).height >= min(event.height, viewport.height) - 2
        }
    }

    private func scrollBrowser(_ scroll: NSScrollView, toEnd: Bool) throws {
        let document = try value(scroll.documentView, "browser scroll document")
        document.layoutSubtreeIfNeeded()
        let maximum = max(0, document.bounds.height - scroll.contentView.bounds.height)
        let atMaximum = toEnd == document.isFlipped
        scroll.contentView.scroll(to: NSPoint(x: 0, y: atMaximum ? maximum : 0))
        scroll.reflectScrolledClipView(scroll.contentView)
        try require(abs(scroll.contentView.bounds.minY - (atMaximum ? maximum : 0)) < 2,
                    "native browser did not reach requested scroll endpoint")
    }

    private func checkSharedAppearance(window: NSWindow, divider: CGFloat) async throws {
        let originalOverride = visualEnvironment.colorSchemeOverride
        visualEnvironment.colorSchemeOverride = nil
        for selection in [ApplicationAppearanceSelection.dark, .light, .system] {
            appearanceSettings.setSelection(selection)
            try await expect("settings.appearance", selection.rawValue)
            try await wait("shared native appearance \(selection.rawValue)") {
                let expected = self.appearanceSettings.nativeAppearance(overriding: nil)?.name
                return window.appearance?.name == expected && self.panelWindow()?.appearance?.name == expected
            }
            try await requireDivider(divider, in: window, after: "appearance \(selection.rawValue)")
            try capture("desktop-settings-\(selection.rawValue)", window: window)
        }
        visualEnvironment.colorSchemeOverride = originalOverride
    }

    private func captureEditorThemes(window: NSWindow) async throws {
        let originalOverride = visualEnvironment.colorSchemeOverride
        let editor = try value(window.attachedSheet, "editor sheet for palette captures")
        for scheme in [ColorScheme.dark, .light] {
            visualEnvironment.colorSchemeOverride = scheme
            try await wait("editor theme propagated") {
                window.appearance?.name == (scheme == .dark ? NSAppearance.Name.darkAqua : .aqua)
            }
            try await Task.sleep(nanoseconds: 100_000_000)
            try capture("desktop-editor-\(scheme == .dark ? "dark" : "light")", window: editor)
        }
        visualEnvironment.colorSchemeOverride = originalOverride
    }

    private func positionDivider(in window: NSWindow, fraction: CGFloat) async throws -> CGFloat {
        let content = try value(window.contentView, "split content")
        content.layoutSubtreeIfNeeded()
        let split = try value(nativeSplit(in: content), "native horizontal split")
        let position = ((split.bounds.width - split.dividerThickness) * fraction).rounded()
        split.setPosition(position, ofDividerAt: 0)
        try await wait("native divider accepts nondefault position") {
            abs(split.arrangedSubviews[0].frame.maxX - position) < 2
        }
        try requireDividerGrip(in: window)
        return split.arrangedSubviews[0].frame.maxX
    }

    private func requireDivider(_ position: CGFloat, in window: NSWindow, after action: String) async throws {
        for _ in 0..<3 {
            try await Task.sleep(nanoseconds: 20_000_000)
            let content = try value(window.contentView, "retained split content")
            content.layoutSubtreeIfNeeded()
            let split = try value(nativeSplit(in: content), "retained native horizontal split")
            try require(abs(split.arrangedSubviews[0].frame.maxX - position) < 2,
                        "divider reset after \(action): expected \(position), actual \(split.arrangedSubviews[0].frame.maxX)")
            try requireDividerGrip(in: window, after: action)
        }
    }

    private func requireDividerGrip(in window: NSWindow, after action: String = "divider positioning") throws {
        let content = try value(window.contentView, "divider grip content")
        let grip = try value(dividerGrip(in: content), "desktop divider grip")
        grip.refreshSplitView()
        let rect = grip.gripRect
        let settingsBlocksBackground = controls.frame("desktop.settings.pane") != nil
        try require(abs(rect.width - 12) < 0.5 && rect.height > 200, "divider grip must span a 12pt full-height band")
        for height in [CGFloat(0.15), 0.5, 0.85] {
            for offset in [CGFloat(-5), 0, 5] {
                let localPoint = NSPoint(x: rect.midX + offset, y: rect.minY + rect.height * height)
                let point = grip.convert(localPoint, to: content.superview)
                let hit = content.hitTest(point)
                let routesAsExpected = settingsBlocksBackground ? (hit != nil && hit !== grip) : hit === grip
                try require(routesAsExpected, "unexpected expanded divider hit routing after \(action); "
                            + "expected=\(settingsBlocksBackground ? "blocked by settings" : "divider grip"), "
                            + "height=\(height), offset=\(offset), localPoint=\(localPoint), point=\(point), gripRect=\(rect), "
                            + "hit=\(dividerViewDescription(hit)), content=\(dividerViewDescription(content)), "
                            + "gripHierarchy=\(dividerHierarchyDescription(grip))")
            }
        }
        for offset in [CGFloat(-8), 8] {
            let point = grip.convert(NSPoint(x: rect.midX + offset, y: rect.midY), to: content.superview)
            try require(content.hitTest(point) !== grip, "divider grip intercepts pane content outside its band after \(action)")
        }
    }

    private func dividerViewDescription(_ view: NSView?) -> String {
        guard let view else { return "nil" }
        return "\(type(of: view))(frame=\(view.frame), bounds=\(view.bounds), hidden=\(view.isHidden))"
    }

    private func dividerHierarchyDescription(_ grip: NSView) -> String {
        var ancestor: NSView? = grip
        var hierarchy: [String] = []
        while let view = ancestor, hierarchy.count < 6 {
            hierarchy.append(dividerViewDescription(view))
            ancestor = view.superview
        }
        return hierarchy.joined(separator: " → ")
    }

    private func dividerGrip(in view: NSView) -> DesktopDividerGripView? {
        if let grip = view as? DesktopDividerGripView { return grip }
        return view.subviews.lazy.compactMap { self.dividerGrip(in: $0) }.first
    }

    private func requireCollectionFooters(_ ids: [UUID]) async throws {
        try await wait("collection cards align countdown footers despite weather and wrapped titles") {
            let cards = ids.compactMap { self.controls.frame("desktop.presentation.\($0)") }
            let footers = ids.compactMap { self.controls.frame("desktop.collection.remaining.\($0)") }
            guard cards.count == ids.count, footers.count == ids.count,
                  let rowTop = cards.first?.minY, let baseline = footers.first?.maxY else { return false }
            return cards.allSatisfy { abs($0.minY - rowTop) < 2 }
                && footers.allSatisfy { abs($0.maxY - baseline) < 2 }
        }
    }

    private func requireTimerDeleteSpacing(prefix: String, label: String, adjacent: Bool) async throws {
        try await wait("\(prefix) timer delete-button spacing") {
            guard let text = self.controls.frame("\(prefix).\(label)"),
                  let button = self.controls.frame("\(prefix).delete") else { return false }
            let gap = button.minX - text.maxX
            return abs(button.midY - text.midY) < 3 && (adjacent ? abs(gap - 8) < 2 : gap > 100)
        }
    }

    private func verifyPendingDesktopActions() async throws {
        let retainedWindow = try value(desktopWindow(), "pending-action desktop window")
        let fixtureURL = configuration.homeURL.appendingPathComponent("PendingActions/events.json")
        let gate = DesktopSmokeWriteGate(fileURL: fixtureURL)
        let suite = configuration.defaultsSuiteName + ".pending-actions"
        let defaults = try value(UserDefaults(suiteName: suite), "pending-action defaults")
        defaults.set(Date().addingTimeInterval(-1).timeIntervalSince1970, forKey: CountdownTimer.deadlineKey)
        let finishedTimer = CountdownTimer(defaults: defaults)
        let fixture = Store(fileURL: fixtureURL, disclosureDefaults: defaults,
                            persistenceSaveOverride: { data, revision in try await gate.save(data, revision: revision) },
                            loginItemManagementIsAvailable: false)
        let session = EventEditorSession()
        let fixtureUpdates = ApplicationUpdates(info: [:], enabled: false) { nil }
        try await wait("pending fixture loaded") { !fixture.isLoading }
        let first = try Subtask(text: "Первое действие")
        let second = try Subtask(text: "Второе действие")
        let event = Countdown(title: "Проверка быстрых действий", note: "Сохранённая заметка",
                              date: Day(store.tomorrow), emoji: "", subtasks: [first, second])
        let saved = await fixture.save(event, primary: false)
        try require(saved, "cannot seed pending fixture")
        let fixtureController = DesktopWindowController(rootView: DesktopRootView(
            store: fixture, updates: fixtureUpdates, editorSession: session,
            keepAwake: keepAwake, weather: weather, accessibilitySettings: accessibilitySettings,
            visualEnvironment: visualEnvironment, appearanceSettings: ApplicationAppearance(defaults: defaults),
            showPanel: {}, switchToPanel: {},
            diagnosticsContext: { makeDiagnosticExportContext(timer: finishedTimer, updates: fixtureUpdates, weather: self.weather) }
        ), editorSession: session)
        let window = try value(fixtureController.window, "controlled pending-action window")
        let fixtureHost = try value(window.contentViewController, "controlled pending-action host")
        retainedWindow.orderOut(nil)
        fixtureController.show()
        defer {
            window.close()
            retainedWindow.makeKeyAndOrderFront(nil)
            defaults.removePersistentDomain(forName: suite)
            Task { await gate.release() }
        }
        try await wait("pending fixture rendered") { self.controls.entries["desktop.detail.\(event.id)"] != nil }
        try require(controls.ids(withPrefix: "desktop.timer.").isEmpty,
                    "desktop exposes finished-timer controls")
        try require(finishedTimer.phase == .finished, "removing desktop timer UI lost its finished state")
        try capture("desktop-no-timer-finished", window: window)
        let firstControl = "desktop.subtask.toggle.\(first.id)"
        let secondControl = "desktop.subtask.toggle.\(second.id)"
        let stableIDs = ["desktop.create", "desktop.detail.edit", "desktop.checklist.edit",
                         "desktop.favorite.\(event.id)", firstControl, secondControl]
        let frames = try Dictionary(uniqueKeysWithValues: stableIDs.map { id in
            (id, try value(controls.frame(id), "stable control frame \(id)"))
        })
        try capture("desktop-checklist-before-write", window: window)
        await gate.holdNextWrite()
        try await press(firstControl)
        await gate.waitUntilBlocked()
        try await expect(firstControl, "on")
        try require(fixture.hasPendingPersistence, "write gate did not hold persistence")
        for _ in 0..<6 {
            for id in stableIDs {
                try require(controls.entries[id]?.isEnabled == true, "pending checklist write disabled unrelated control \(id)")
            }
            for id in ["desktop.create", "desktop.detail.edit", "desktop.checklist.edit"] {
                try require(controls.frame(id) == frames[id], "pending checklist write moved unrelated control \(id)")
            }
            fixtureHost.view.layoutSubtreeIfNeeded()
            fixtureHost.view.display()
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try capture("desktop-checklist-write-held", window: window)
        try require(controls.press(secondControl) && controls.press(firstControl), "rapid checklist input was rejected")
        try require(controls.press("desktop.detail.edit"), "editor intent was rejected during a local write")
        try require(session.desktopIsPresented && window.attachedSheet == nil,
                    "queued editor did not reserve ownership before persistence settled")
        try await wait("reserved editor disables compact switching") { self.controls.entries["desktop.panel"]?.isEnabled == false }
        try require(!controls.press("desktop.panel"), "compact switch accepted a reserved editor")
        window.performClose(nil)
        try require(window.isVisible && !fixtureController.hideForPanel(), "reserved editor allowed its parent window to hide")
        await gate.release()
        try await wait("queued editor after rapid writes") { window.attachedSheet != nil && !fixture.hasPendingPersistence }
        let expected = try value(fixture.active.first, "rapid-action result")
        try require(expected.subtasks.map(\.isCompleted) == [false, true], "rapid toggle intentions were lost or duplicated")
        try await press("editor.save")
        try await wait("queued fresh editor Save") { !session.hasActiveEditor && !fixture.hasPendingPersistence }
        try require(fixture.active.first?.subtasks == expected.subtasks, "queued editor overwrote newer checklist state")
        let durable = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fixtureURL))
        try require(durable == fixture.data, "rapid checklist actions were not durable")
        await gate.holdNextWrite()
        try await press(firstControl)
        await gate.waitUntilBlocked()
        try require(controls.press(secondControl), "second accepted action was rejected before owner handoff")
        try require(session.beginPanelEditor(), "cannot model external editor owner")
        await gate.release()
        try await wait("first write finishes behind external editor") { !fixture.hasPendingPersistence }
        try require(fixture.active.first?.subtasks.map(\.isCompleted) == [true, true],
                    "queued action mutated data while another surface owned an editor")
        try await wait("external editor disables desktop mutation") { self.controls.entries[firstControl]?.isEnabled == false }
        session.endPanelEditor()
        try await wait("queued action resumes after owner release") {
            !fixture.hasPendingPersistence && fixture.active.first?.subtasks.map(\.isCompleted) == [true, false]
        }
        let beforeFailure = fixture.data
        await gate.holdNextWrite()
        try await press(firstControl)
        await gate.waitUntilBlocked()
        try require(controls.press(secondControl) && controls.press("desktop.detail.edit"), "cannot queue failure follow-up intentions")
        await gate.release(failing: true)
        try await wait("failed write reports unapplied queued intentions") {
            !fixture.hasPendingPersistence && fixture.error?.contains("Оставшиеся действия не выполнены") == true
                && self.controls.entries["desktop.error"] != nil
        }
        try require(fixture.data == beforeFailure && !session.hasActiveEditor,
                    "failed write opened an editor or applied queued actions to rolled-back data")
        passed.append("held checklist writes keep rendered sibling controls enabled; rapid actions serialize, editor snapshots wait, external ownership pauses, failures report cancelled follow-ups")
        try await verifyDesktopDeletion(fixture: fixture, session: session, gate: gate, window: window,
                                        event: event, firstControl: firstControl)
    }

    private func requireDetailHeaderBounds() throws {
        let header = try value(controls.frame("desktop.detail.header"), "desktop detail header")
        let edit = try value(controls.frame("desktop.detail.edit"), "desktop edit action")
        let delete = try value(controls.frame("desktop.detail.delete"), "desktop delete action")
        let eventID = try value(controls.value("desktop.inspector"), "selected detail identity")
        let favorite = try value(controls.frame("desktop.favorite.\(eventID)"), "desktop favorite action")
        try require(header.contains(edit) && header.contains(delete) && !edit.intersects(delete),
                    "desktop edit/delete actions overlap or escape the narrow header")
        try require([favorite, edit, delete].allSatisfy {
            header.contains($0) && abs($0.width - 28) < 1 && abs($0.height - 28) < 1
                && abs($0.midY - edit.midY) < 1
        }, "desktop header actions do not retain equal icon-only targets")
        try require(abs(edit.minX - favorite.maxX - 8) < 1 && abs(delete.minX - edit.maxX - 8) < 1,
                    "desktop header icon spacing is not uniform")
    }

    private func verifyDesktopDeletion(
        fixture: Store, session: EventEditorSession, gate: DesktopSmokeWriteGate,
        window: NSWindow, event: Countdown, firstControl: String
    ) async throws {
        fixture.error = nil
        let replacement = Countdown(title: "Следующее событие", date: Day(store.tomorrow), emoji: "")
        let saved = await fixture.save(replacement, primary: false)
        try require(saved, "cannot seed deletion neighbor")
        await fixture.makePrimary(event.id)
        try await wait("deletion target selected") { self.controls.entries["desktop.detail.\(event.id)"] != nil }
        let divider = try await positionDivider(in: window, fraction: 0.61)
        let beforeCancel = fixture.data
        let fileURL = configuration.homeURL.appendingPathComponent("PendingActions/events.json")
        let beforeCancelFile = try Data(contentsOf: fileURL)
        try require(session.beginPanelEditor(), "cannot model external editor before delete")
        try await wait("external editor blocks direct deletion") { self.controls.entries["desktop.detail.delete"]?.isEnabled == false }
        try require(!controls.press("desktop.detail.delete") && fixture.data == beforeCancel,
                    "desktop deletion bypassed external editor ownership")
        session.endPanelEditor()
        try await press("desktop.detail.delete")
        try await expect("desktop.delete.confirmation", event.title)
        try require(!session.hasActiveEditor && window.attachedSheet == nil, "direct delete unnecessarily opened an editor or sheet")
        try await press("desktop.delete.cancel")
        try await wait("direct deletion cancelled") { self.controls.entries["desktop.delete.confirmation"] == nil }
        let afterCancelFile = try Data(contentsOf: fileURL)
        try require(fixture.data == beforeCancel && afterCancelFile == beforeCancelFile,
                    "delete cancellation changed saved data")
        try requireDetailHeaderBounds()
        try capture("desktop-delete-header", window: window)
        try await press("desktop.detail.delete")
        try await expect("desktop.delete.confirmation", event.title)
        for scheme in [ColorScheme.dark, .light] {
            visualEnvironment.colorSchemeOverride = scheme
            window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            try await Task.sleep(nanoseconds: 150_000_000)
            try capture("desktop-delete-confirmation-\(scheme == .dark ? "dark" : "light")", window: window)
        }
        try await press("desktop.event.\(replacement.id)")
        try await wait("selection switch drops old confirmation") {
            self.controls.entries["desktop.detail.\(replacement.id)"] != nil
                && self.controls.entries["desktop.delete.confirmation"] == nil
        }
        try require(fixture.data == beforeCancel, "switching delete target changed data")
        try await requireDivider(divider, in: window, after: "deletion confirmation selection switch")
        try await press("desktop.event.\(event.id)")
        await gate.holdNextWrite()
        try await press(firstControl)
        await gate.waitUntilBlocked()
        try await press("desktop.detail.delete")
        try await expect("desktop.delete.confirmation", event.title)
        let duplicateConfirm = try value(controls.entries["desktop.delete.confirm"]?.action, "captured confirm action")
        try await press("desktop.delete.confirm")
        duplicateConfirm()
        try require(fixture.active.contains { $0.id == event.id }, "delete ran before earlier held checklist write")
        await gate.release()
        try await wait("confirmed exact target deleted after write") {
            !fixture.hasPendingPersistence && !fixture.active.contains { $0.id == event.id }
                && self.controls.entries["desktop.detail.\(replacement.id)"] != nil
        }
        duplicateConfirm()
        try await requireDivider(divider, in: window, after: "confirmed deletion selects neighbor")
        try require(fixture.active.map(\.id) == [replacement.id] && fixture.data.primaryID == nil
                    && !session.hasActiveEditor && window.attachedSheet == nil,
                    "duplicate confirmation deleted the next event, retained favorite or opened an editor")
        let deletedSnapshot = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fileURL))
        try require(deletedSnapshot == fixture.data, "direct deletion was not durable")
        await gate.holdNextWrite()
        try await press("desktop.detail.delete")
        try await press("desktop.delete.confirm")
        await gate.waitUntilBlocked()
        try require(fixture.active.isEmpty, "last delete did not stage an empty collection")
        await gate.release(failing: true)
        try await wait("failed direct deletion rolls back") {
            !fixture.hasPendingPersistence && fixture.data == deletedSnapshot && fixture.error != nil
                && self.controls.entries["desktop.detail.\(replacement.id)"] != nil
        }
        let failedSnapshot = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fileURL))
        try await requireDivider(divider, in: window, after: "last deletion empty staging and rollback")
        try require(failedSnapshot == deletedSnapshot && !session.hasActiveEditor,
                    "failed deletion changed the durable file or retained an editor lock")
        fixture.error = nil
        try await press("desktop.detail.delete")
        try await press("desktop.delete.confirm")
        try await wait("last event deleted directly") {
            !fixture.hasPendingPersistence && fixture.active.isEmpty
                && self.controls.entries["desktop.event.\(event.id)"] == nil
                && self.controls.entries["desktop.event.\(replacement.id)"] == nil
                && self.controls.entries["desktop.detail.\(replacement.id)"] == nil
                && self.controls.frame("desktop.inspector") != nil
        }
        let emptySnapshot = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fileURL))
        try await requireDivider(divider, in: window, after: "last deletion leaves empty details")
        try require(emptySnapshot == fixture.data && emptySnapshot.items.isEmpty && emptySnapshot.primaryID == nil,
                    "last direct deletion did not persist the genuine empty state")
        passed.append("desktop inline deletion Cancel preserves data; selection changes dismiss confirmation; confirmed exact targets serialize after writes, clear favorites, survive duplicate delivery, roll back failures and reach durable empty state")
    }

    private func requireTaskOrder(first: UUID, second: UUID) async throws {
        try await wait("unfinished checklist row precedes completed row") {
            guard let firstFrame = self.controls.frame("desktop.subtask.toggle.\(first)"),
                  let secondFrame = self.controls.frame("desktop.subtask.toggle.\(second)") else { return false }
            return firstFrame.maxY <= secondFrame.minY
        }
    }

    private func checkFilteredCreation(divider: CGFloat, window: NSWindow) async throws {
        let original = store.data
        try await replaceFocusedText(control: "desktop.search", text: "Несуществующий поиск")
        try await wait("search hides nonmatching events") {
            self.controls.ids(withPrefix: "desktop.event.").isEmpty
        }
        try await requireDivider(divider, in: window, after: "search removes selected details")
        try await press("desktop.create")
        try await replaceFocusedText(control: "editor.title", text: "Отменённое новое событие")
        try await press("editor.cancel")
        try await wait("filtered creation Cancel releases editor") { !self.editorSession.hasActiveEditor }
        try require(store.data == original, "filtered creation Cancel persisted a draft")
        try await expect("desktop.search", "Несуществующий поиск")
        try await press("desktop.create")
        try await replaceFocusedText(control: "editor.title", text: "Создано из поиска")
        try await press("editor.save")
        try await wait("new event saved from search") {
            !self.editorSession.hasActiveEditor && !self.store.hasPendingPersistence
                && self.store.active.contains { $0.title == "Создано из поиска" }
        }
        let created = try value(store.active.first { $0.title == "Создано из поиска" }, "new filtered event")
        try await expect("desktop.search", "")
        try await wait("saved event selected outside old filters") {
            self.controls.entries["desktop.detail.\(created.id)"] != nil
        }
        try require(created.date == Day(store.tomorrow) && created.emoji.isEmpty && created.subtasks.isEmpty,
                    "desktop ordinary creation used unexpected field defaults")
        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(persisted == store.data && store.data.items.count == original.items.count + 1,
                    "new desktop event was not durably saved once")
        showPanel()
        try await wait("new desktop event visible in panel") {
            self.controls.entries["event.edit.\(created.id)"] != nil
        }
        showDesktop()
        passed.append("search creation Cancel preserves query/data; Save clears search and reveals one durable new event on both surfaces")
    }

    private func checkFavorite(_ expected: UUID?) async throws {
        try await wait("desktop presentation follows explicit favorite") {
            self.store.active.allSatisfy { item in
                let actual = self.controls.value("desktop.presentation.\(item.id)")
                return item.id == expected ? actual == "favorite" : ["collection", "feed"].contains(actual ?? "")
            }
        }
        for event in store.active {
            let prefix = eventListEmoji(event.emoji).map { $0 + " " } ?? ""
            try await expect("desktop.date.browser.\(event.id)", prefix + humanDateLabel(event.date))
        }
    }

    private func captureThemes(_ name: String) async throws {
        for scheme in [ColorScheme.dark, .light] {
            visualEnvironment.colorSchemeOverride = scheme
            desktopWindow()?.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            try await Task.sleep(nanoseconds: 300_000_000)
            if name == "desktop-collection" || name == "desktop-unfavorited" {
                try requireDetailActionPalette(scheme: scheme)
            }
            try capture("\(name)-\(scheme == .dark ? "dark" : "light")")
        }
    }

    private func requireDetailActionPalette(scheme: ColorScheme) throws {
        let content = try value(desktopWindow()?.contentView, "detail palette content")
        let split = try value(nativeSplit(in: content), "detail palette native split")
        let inspector = try value(split.arrangedSubviews.last, "detail palette inspector")
        let inspectorFrame = inspector.convert(inspector.bounds, to: content)
        let headerTop = content.isFlipped ? inspectorFrame.minY : content.bounds.maxY - inspectorFrame.maxY
        let selectedID = try value(controls.value("desktop.inspector"), "detail palette selected event")
        let isFavorite = store.data.primaryID?.uuidString == selectedID
        let ink = AuroraInstrument.ink(for: scheme)
        let favoriteColor = isFavorite
            ? AuroraInstrument.accent(for: scheme, highContrast: accessibilitySettings.prefersHighContrast) : ink
        content.layoutSubtreeIfNeeded()
        let bitmap = try value(content.bitmapImageRepForCachingDisplay(in: content.bounds), "detail palette bitmap")
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let scaleX = CGFloat(bitmap.pixelsWide) / content.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / content.bounds.height
        let actions = [("desktop.favorite.\(selectedID)", favoriteColor),
                       ("desktop.detail.edit", ink), ("desktop.detail.delete", ink)]
        for (index, action) in actions.enumerated() {
            let (identifier, color) = action
            let frame = CGRect(x: inspectorFrame.maxX - 24 - 28 - CGFloat(2 - index) * 36,
                               y: headerTop + (54 - 28) / 2, width: 28, height: 28)
            let expected = try value(NSColor(color).usingColorSpace(.sRGB), "expected detail action color")
            let minX = max(0, Int(floor(frame.minX * scaleX)))
            let maxX = min(bitmap.pixelsWide, Int(ceil(frame.maxX * scaleX)))
            let minY = max(0, Int(floor(frame.minY * scaleY)))
            let maxY = min(bitmap.pixelsHigh, Int(ceil(frame.maxY * scaleY)))
            try require(minX < maxX && minY < maxY, "detail action palette bounds are empty")
            var matchingPixels = 0
            for pixelY in minY..<maxY {
                for pixelX in minX..<maxX {
                    guard let actual = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.sRGB) else { continue }
                    let difference = max(abs(actual.redComponent - expected.redComponent),
                                         abs(actual.greenComponent - expected.greenComponent),
                                         abs(actual.blueComponent - expected.blueComponent))
                    if difference < 0.12 && actual.alphaComponent > 0.9 { matchingPixels += 1 }
                }
            }
            try require(matchingPixels >= 4,
                        "\(identifier) lacks its expected \(isFavorite ? "favorite" : "neutral") action palette in \(scheme); "
                            + "frame=\(frame), inspector=\(inspectorFrame), matchingPixels=\(matchingPixels)")
        }
    }

    private func capture(_ name: String, window requestedWindow: NSWindow? = nil) throws {
        let window = try value(requestedWindow ?? desktopWindow(), "capture window")
        let content = try value(window.contentView?.superview ?? window.contentView, "capture view")
        content.layoutSubtreeIfNeeded()
        content.display()
        guard let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            throw Failure("cannot allocate desktop capture")
        }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        let observedAt = ProcessInfo.processInfo.systemUptime
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure("cannot encode desktop PNG") }
        let destination = configuration.homeURL.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try png.write(to: destination.appendingPathComponent("\(name).png"), options: .atomic)
        captures.append([
            "file": "\(name).png", "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
            "scale": window.backingScaleFactor,
            "appearanceName": window.effectiveAppearance.name.rawValue,
            "colorSchemeOverride": visualEnvironment.colorSchemeOverride == .dark ? "dark" : "light",
            "highContrast": accessibilitySettings.prefersHighContrast,
            "reduceMotion": accessibilitySettings.prefersReducedMotion,
            "observationUptime": observedAt,
            "captureMethod": "NSView.cacheDisplay; in-process render, not compositor presentation capture"
        ])
    }

    private func writeManifest() throws {
        let executable = try value(Bundle.main.executableURL, "capture executable")
        let digest = SHA256.hash(data: try Data(contentsOf: executable)).map { String(format: "%02x", $0) }.joined()
        let manifest: [String: Any] = [
            "applicationVersion": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
            "applicationBuild": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            "executableSHA256": digest, "captures": captures, "syntheticData": true,
            "scope": "Unreleased native desktop implementation; retained AppKit window render, not external desktop capture"
        ]
        let destination = configuration.homeURL.appendingPathComponent("Captures/manifest.json")
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]).write(to: destination)
    }

    private func replaceFocusedText(control: String, text: String) async throws {
        try await press(control)
        try await wait("focused native text editor") { NSApp.keyWindow?.firstResponder is NSTextView }
        let textView = try value(NSApp.keyWindow?.firstResponder as? NSTextView, "native field editor")
        textView.selectAll(nil)
        textView.insertText(text, replacementRange: textView.selectedRange())
        try await expect(control, text)
    }

    private func press(_ id: String) async throws {
        try await wait("enabled \(id)") { self.controls.entries[id]?.isEnabled == true }
        try require(controls.press(id), "cannot activate \(id)")
    }

    private func expect(_ id: String, _ text: String) async throws {
        try await wait("\(id) = \(text)") { self.controls.value(id) == text }
    }

    private func wait(_ description: String, condition: @escaping () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 6
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw Failure("timeout: \(description)") }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func requirePanelStaysVisible() async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.5
        while ProcessInfo.processInfo.systemUptime < deadline {
            try require(panelWindow()?.isVisible == true && panelWindow()?.isKeyWindow == true && NSApp.isActive,
                        "panel disappeared after native activation handoff")
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message) }
    }

    private func value<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else { throw Failure("missing \(message)") }
        return value
    }

    private func finish(_ message: String, status: Int32) {
        try? message.write(to: configuration.resultURL, atomically: true, encoding: .utf8)
        fputs(message + "\n", stderr)
        DiagnosticLog.shared.flush()
        configuration.defaults.removePersistentDomain(forName: configuration.defaultsSuiteName)
        Darwin.exit(status)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
