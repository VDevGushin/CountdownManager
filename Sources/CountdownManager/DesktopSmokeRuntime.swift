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
        self.showDesktop = showDesktop
        self.hideDesktop = hideDesktop
        self.showPanel = showPanel
        self.pressStatusItem = pressStatusItem
    }

    func start() {
        let resultURL = configuration.resultURL
        DispatchQueue.global().asyncAfter(deadline: .now() + 43) {
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
        try await press("desktop.subtask.toggle.\(remainingTask.id)")
        try await wait("desktop checklist completed") {
            self.store.active.first { $0.id == today.id }?.subtasks.allSatisfy(\.isCompleted) == true
                && self.controls.entries["desktop.checklist.complete"] != nil
        }
        try await press("desktop.subtask.toggle.\(remainingTask.id)")
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "off")
        try await requireTaskOrder(first: remainingTask.id, second: completedTask.id)
        try require(store.active.first { $0.id == today.id }?.subtasks.map(\.id) == today.subtasks.map(\.id),
                    "display grouping reordered persisted subtask identities")
        try await press("desktop.subtask.toggle.\(remainingTask.id)")
        try await expect("desktop.subtask.toggle.\(remainingTask.id)", "on")
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
        try await wait("desktop settings sheet") { self.controls.entries["settings.weather.enabled"] != nil }
        try await checkSharedAppearance(window: window, divider: resizedDivider)
        try require(!controls.press("desktop.panel") && window.isVisible && window.attachedSheet != nil,
                    "compact-mode button hid an active settings sheet")
        try await press("settings.weather.enabled")
        try await wait("weather disabled in shared settings") { !self.weather.enabled }
        try await press("settings.back")
        try await wait("settings dismissed") { window.attachedSheet == nil }
        try await requireDivider(resizedDivider, in: window, after: "settings open and close")
        try require(weather.forecast(for: store.today) == nil, "disabled shared weather still supplies a forecast")
        try capture("desktop-weather-off")
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

        timer.start(minutes: 5)
        try require(timer.deadline != nil, "cannot start shared timer")
        try await requireTimerDeleteSpacing(prefix: "desktop.timer", label: "running", adjacent: true)
        try capture("desktop-timer-running")
        let savedDeadline = timer.deadline
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
    }

    private func nativeSplit(in view: NSView) -> NSSplitView? {
        if let split = view as? NSSplitView, split.isVertical, split.arrangedSubviews.count == 2 {
            return split
        }
        return view.subviews.lazy.compactMap { self.nativeSplit(in: $0) }.first
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
            try capture("desktop-settings-\(selection.rawValue)", window: window.attachedSheet ?? window)
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
            try requireDividerGrip(in: window)
        }
    }

    private func requireDividerGrip(in window: NSWindow) throws {
        let content = try value(window.contentView, "divider grip content")
        let grip = try value(dividerGrip(in: content), "desktop divider grip")
        grip.refreshSplitView()
        let rect = grip.gripRect
        try require(abs(rect.width - 12) < 0.5 && rect.height > 200, "divider grip must span a 12pt full-height band")
        for height in [CGFloat(0.15), 0.5, 0.85] {
            for offset in [CGFloat(-5), 0, 5] {
                let localPoint = NSPoint(x: rect.midX + offset, y: rect.minY + rect.height * height)
                let point = grip.convert(localPoint, to: content.superview)
                try require(content.hitTest(point) === grip, "desktop hierarchy does not route the expanded divider band to grip")
            }
        }
        for offset in [CGFloat(-8), 8] {
            let point = grip.convert(NSPoint(x: rect.midX + offset, y: rect.midY), to: content.superview)
            try require(content.hitTest(point) !== grip, "divider grip intercepts pane content outside its band")
        }
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
            store: fixture, timer: finishedTimer, updates: fixtureUpdates, editorSession: session,
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
        try await requireTimerDeleteSpacing(prefix: "desktop.timer", label: "finished", adjacent: true)
        try capture("desktop-timer-finished", window: window)
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
            try capture("\(name)-\(scheme == .dark ? "dark" : "light")")
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
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw Failure("cannot encode desktop PNG") }
        let destination = configuration.homeURL.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try png.write(to: destination.appendingPathComponent("\(name).png"), options: .atomic)
        captures.append([
            "file": "\(name).png", "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh,
            "scale": window.backingScaleFactor,
            "appearanceName": window.effectiveAppearance.name.rawValue,
            "colorSchemeOverride": visualEnvironment.colorSchemeOverride == .dark ? "dark" : "light",
            "highContrast": accessibilitySettings.prefersHighContrast
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
