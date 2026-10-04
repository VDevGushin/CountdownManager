import AppKit
import CountdownCore
import Darwin
import Foundation
import QuartzCore
import SwiftUI

@MainActor
final class UISmokeVisualEnvironment: ObservableObject {
    @Published var colorSchemeOverride: ColorScheme?
}

struct UISmokeConfiguration {
    static let launchArgument = "--ui-smoke"
    static let collapseRegressionLaunchArgument = "--ui-smoke-collapse-regression"
    static let editorScrollRegressionLaunchArgument = "--ui-smoke-editor-scroll-regression"
    static let captureLaunchArgument = "--ui-smoke-captures"
    static let markerName = ".countdown-ui-smoke-environment"
    static let xcuiTestLaunchArgument = "--xcui-testing"
    static let xcuiTestMarkerName = ".countdown-xcui-test-environment"
    static let visualPreviewLaunchArgument = "--visual-preview"
    static let visualPreviewMarkerName = ".countdown-visual-preview-environment"

    let homeURL: URL
    let resultURL: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    static var wasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains(captureLaunchArgument)
    }

    static var xcuiTestWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(xcuiTestLaunchArgument)
    }

    static var visualPreviewWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(visualPreviewLaunchArgument)
    }

    static var requiresIsolatedTestHome: Bool {
        wasRequested || xcuiTestWasRequested || visualPreviewWasRequested
    }

    // Visual preview isolates data but deliberately keeps production shell lifecycle callbacks.
    static var isolatedTestEnvironmentWasRequested: Bool {
        wasRequested || xcuiTestWasRequested
    }

    static var collapseRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
    }

    static var editorScrollRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
    }

    static var captureWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(captureLaunchArgument)
    }

    static func load() throws -> UISmokeConfiguration? {
        guard requiresIsolatedTestHome else { return nil }
        let smokeArguments = [
            launchArgument,
            collapseRegressionLaunchArgument,
            editorScrollRegressionLaunchArgument,
            captureLaunchArgument,
        ]
        .filter { ProcessInfo.processInfo.arguments.contains($0) }
        guard smokeArguments.count <= 1 else {
            throw Failure("only one UI smoke mode can be requested")
        }
        guard !(visualPreviewWasRequested && (wasRequested || xcuiTestWasRequested)) else {
            throw Failure("visual preview cannot be combined with UI smoke or XCUITest arguments")
        }
        let environment = ProcessInfo.processInfo.environment
        guard let rawHome = environment["COUNTDOWN_MANAGER_TEST_HOME"], !rawHome.isEmpty else {
            throw Failure("COUNTDOWN_MANAGER_TEST_HOME is required")
        }
        let homeURL = URL(fileURLWithPath: rawHome, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let requiredMarker: String
        if visualPreviewWasRequested {
            requiredMarker = visualPreviewMarkerName
        } else if xcuiTestWasRequested {
            requiredMarker = xcuiTestMarkerName
        } else {
            requiredMarker = markerName
        }
        guard FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(requiredMarker).path) else {
            throw Failure("test-home marker is missing")
        }
        let productionSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("CountdownManager", isDirectory: true)
        .standardizedFileURL.resolvingSymlinksInPath()
        guard homeURL.path != productionSupport.path,
              !homeURL.path.hasPrefix(productionSupport.path + "/"),
              !productionSupport.path.hasPrefix(homeURL.path + "/") else {
            throw Failure("test home overlaps production Application Support")
        }
        let resultURL = homeURL.appendingPathComponent("ui-smoke-result.txt")
        let suiteName = "local.countdownmanager.ui-smoke.\(homeURL.deletingLastPathComponent().lastPathComponent).\(homeURL.lastPathComponent)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure("cannot create isolated UserDefaults")
        }
        let configuration = UISmokeConfiguration(
            homeURL: homeURL,
            resultURL: resultURL,
            defaults: defaults,
            defaultsSuiteName: suiteName
        )
        if captureWasRequested {
            try configuration.seedTodayCaptureFixture()
        }
        return configuration
    }

    var dataURL: URL {
        homeURL.appendingPathComponent("Application Support/CountdownManager/countdowns.json")
    }

    private func seedTodayCaptureFixture() throws {
        guard !FileManager.default.fileExists(atPath: dataURL.path) else {
            throw Failure("capture fixture must start without saved event data")
        }
        let today = Day(Date())
        let primary = Countdown(title: "Сегодня: важная встреча", date: today, emoji: "📅")
        let secondary = Countdown(title: "Короткое событие", date: today, emoji: "✨")
        var data = CountdownData()
        data.items = [primary, secondary]
        data.primaryID = primary.id
        try FileManager.default.createDirectory(
            at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try JSONEncoder().encode(data).write(to: dataURL, options: .atomic)
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@MainActor
final class UISmokeRuntime {
    private struct CaptureRecord: Codable {
        let name: String
        let file: String
        let width: Int
        let height: Int
        let scale: Double
        let opaqueCorners: Bool
        let colorSchemeOverride: String?
        let highContrastOverride: Bool?
        let reduceMotionOverride: Bool?
    }

    private struct CaptureManifest: Codable {
        let version: Int
        let captures: [CaptureRecord]
    }

    private let configuration: UISmokeConfiguration
    private let store: Store
    private let window: () -> NSWindow?
    private let hideSurface: () -> Void
    private let showSurface: () -> Void
    private let isSurfaceShown: () -> Bool
    private let pressStatusItem: () -> Void
    private let timer: CountdownTimer
    private let accessibilitySettings: AuroraAccessibilitySettings
    private let visualEnvironment: UISmokeVisualEnvironment
    private let controls = UISmokeControlRegistry.shared
    private var passed: [String] = []
    private var responderToRegistryOffsets: [ObjectIdentifier: CGPoint] = [:]
    private var captures: [CaptureRecord] = []

    init(configuration: UISmokeConfiguration, store: Store, window: @escaping () -> NSWindow?,
         hideSurface: @escaping () -> Void,
         showSurface: @escaping () -> Void,
         isSurfaceShown: @escaping () -> Bool,
         pressStatusItem: @escaping () -> Void,
         timer: CountdownTimer,
         accessibilitySettings: AuroraAccessibilitySettings,
         visualEnvironment: UISmokeVisualEnvironment) {
        self.configuration = configuration
        self.store = store
        self.window = window
        self.hideSurface = hideSurface
        self.showSurface = showSurface
        self.isSurfaceShown = isSurfaceShown
        self.pressStatusItem = pressStatusItem
        self.timer = timer
        self.accessibilitySettings = accessibilitySettings
        self.visualEnvironment = visualEnvironment
    }

    func start() {
        scheduleHardTimeout()
        Task { @MainActor in
            do {
                try await waitFor("loaded root window") {
                    self.window()?.isVisible == true && !self.store.isLoading
                        && self.controls.value("root.window") != nil
                        && self.controls.entries["event.add"]?.isEnabled == true
                }
                if UISmokeConfiguration.captureWasRequested {
                    try await runVisualCaptures()
                } else if UISmokeConfiguration.collapseRegressionWasRequested {
                    try await runCollapseRegression()
                } else if UISmokeConfiguration.editorScrollRegressionWasRequested {
                    try await runSessionContinuity()
                } else {
                    try await run()
                }
                try requireNoUIStall()
                finishSuccess()
            } catch { finishFailure(error) }
        }
    }

    // `open -W` waits for the LaunchServices-launched process, but terminating
    // the waiting launcher does not reliably terminate that separate process.
    // Keep the existing shell timeout as a final guard, and let this isolated
    // runtime report and exit on its own if the AppKit main thread stops making
    // progress before a scenario timeout can run.
    private func scheduleHardTimeout() {
        let resultURL = configuration.resultURL
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 43) {
            let output = "UISmoke\nFAIL after hard timeout: 43s"
            try? output.write(to: resultURL, atomically: true, encoding: .utf8)
            fputs(output + "\n", stderr)
            Darwin._exit(124)
        }
    }

    // Calls in this runtime exercise AppKit/SwiftUI integration, not external clicks.
    private func hideAndShow(usingStatusItem: Bool = false) async throws {
        let original = try requireValue(window(), "window")
        let host = original.contentViewController
        let content = original.contentView
        let token = controls.value("root.window")
        if usingStatusItem { pressStatusItem() } else { hideSurface() }
        try await waitFor("panel hidden") { !self.isSurfaceShown() }
        if usingStatusItem { pressStatusItem() } else { showSurface() }
        try await waitFor("panel visible and key") {
            self.window()?.isVisible == true && self.window()?.isKeyWindow == true
        }
        let shown = try requireValue(window(), "shown window")
        try require(shown.isOnActiveSpace, "shown panel is not on the active Space")
        try require(shown.contentViewController === host && shown.contentView === content,
                    "hosting hierarchy was reconstructed")
        try require(controls.value("root.window") == token, "root State identity changed")
    }

    private func runSessionContinuity() async throws {
        let shell = try requireValue(window(), "window")
        let shellHost = shell.contentViewController
        let shellContent = shell.contentView
        let rootToken = controls.value("root.window")
        try require(shell.canBecomeKey, "panel cannot accept normal focus")
        pass("panel accepts key focus")

        for number in 1...30 {
            let event = Countdown(title: "Session fixture \(number)", date: Day(store.tomorrow), emoji: "📅")
            let saved = await store.save(event, primary: false)
            try require(saved, "fixture save failed")
        }
        try await waitFor("long list") { self.rootListScrollView() != nil }
        let list = try requireValue(rootListScrollView(), "list")
        try await scrollRootList()
        let position = list.contentView.bounds.origin
        for _ in 0..<3 {
            try await hideAndShow()
            try require(rootListScrollView() === list, "list was replaced")
            try require(abs(list.contentView.bounds.origin.y - position.y) < 1, "list position reset")
        }
        pass("host, root State and long-list scroll survive direct hide/show")

        try require(shell.isKeyWindow, "main-list window is not key before lifecycle check")
        hideSurface()
        try await waitFor("main-list panel hide") { !self.isSurfaceShown() }
        showSurface()
        try await waitFor("main-list panel reopen") {
            self.window()?.isVisible == true && self.window()?.isKeyWindow == true
        }
        let reopenedListWindow = try requireValue(window(), "reopened list window")
        try require(reopenedListWindow.contentViewController === shellHost
                    && reopenedListWindow.contentView === shellContent,
                    "main-list hide reconstructed the hosting hierarchy")
        try require(controls.value("root.window") == rootToken && rootListScrollView() === list,
                    "main-list hide changed root or list identity")
        try require(abs(list.contentView.bounds.origin.y - position.y) < 1,
                    "main-list hide reset list position")
        pass("main-list panel hide preserves the UI session")

        try await press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Session draft")
        try await waitForValue("editor.title", equals: "Session draft")
        let editorOwner = controls.entries["editor.new"]?.ownerID
        hideSurface()
        try await waitFor("editor panel hide") { !self.isSurfaceShown() }
        try require(controls.value("root.window") == rootToken
                    && controls.entries["editor.new"]?.ownerID == editorOwner
                    && controls.value("editor.title") == "Session draft",
                    "panel hide changed root, editor or draft state")
        showSurface()
        try await waitFor("editor panel reopen") {
            self.window()?.isVisible == true && self.window()?.isKeyWindow == true
        }
        let reopenedEditorWindow = try requireValue(window(), "reopened editor window")
        try require(reopenedEditorWindow.contentViewController === shellHost
                    && reopenedEditorWindow.contentView === shellContent,
                    "editor hide reconstructed the hosting hierarchy")
        try insertText("a")
        try await waitForValue("editor.title", equals: "Session drafta")
        pass("editor panel hide preserves the UI session")
        for attempt in 1...3 {
            try await hideAndShow(usingStatusItem: true)
            try require(controls.entries["editor.new"]?.ownerID == editorOwner, "editor identity changed")
            // Do not refocus or assign a responder: continue in the existing field editor.
            try insertText("x")
            try await waitForValue("editor.title", equals: "Session drafta" + String(repeating: "x", count: attempt))
            try require(abs(list.contentView.bounds.origin.y - position.y) < 1, "underlying list scrolled")
        }
        try await press("editor.save")
        try await waitFor("saved after reopen") {
            self.controls.entries["editor.new"] == nil && self.store.active.count == 31
        }
        pass("status-item handler preserves editor identity/draft and input; Save after reopen persists")

        let item = try requireValue(store.active.last, "saved item")
        try await press("event.edit.\(item.id.uuidString)")
        try await waitForElement("editor.edit")
        try await focusAndReplace("editor.title", with: "Discard this draft")
        try await hideAndShow()
        try await press("editor.cancel")
        try await waitFor("Cancel returns to list") { self.controls.entries["editor.edit"] == nil }
        try require(abs(list.contentView.bounds.origin.y - position.y) < 1, "Cancel reset list position")
        try await press("event.edit.\(item.id.uuidString)")
        try await waitForValue("editor.title", equals: item.title)
        try await press("editor.cancel")
        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(!persisted.items.contains { $0.title == "Discard this draft" }, "Cancel persisted draft")
        pass("Cancel after reopen destroys draft and retains list position")
    }

    private func runCollapseRegression() async throws {
        for number in 1...7 {
            let event = Countdown(title: "Collapse fixture \(number)", date: Day(store.tomorrow), emoji: "📅",
                                  subtasks: try (1...5).map {
                                      try Subtask(text: "Task \($0)", isCompleted: $0 == 2 || $0 == 4)
                                  })
            let saved = await store.save(event, primary: false)
            try require(saved, "fixture save failed")
        }
        let event = try requireValue(store.active.first, "collapse fixture")
        let sibling = try requireValue(store.active.dropFirst().first, "independent collapse fixture")
        let disclosure = "subtasks.disclosure.\(event.id.uuidString)"
        try await waitForValue(disclosure, equals: "expanded")
        try await settleLayout()
        try requireChecklistOrder(event)
        let expandedHeight = try requireValue(controls.frame("event.card.\(event.id.uuidString)"), "expanded card").height
        let savedJSON = try Data(contentsOf: configuration.dataURL)
        for _ in 0..<8 {
            try await press(disclosure)
            try await waitForValue(disclosure, equals: "collapsed")
            try await press(disclosure)
            try await waitForValue(disclosure, equals: "expanded")
        }
        // Interrupt before the 200 ms transition ends; assert the eventual state,
        // not a timing-dependent midpoint of SwiftUI's rendered presentation.
        for _ in 0..<3 {
            try require(controls.press(disclosure), "rapid disclosure request was rejected")
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await waitForValue(disclosure, equals: "collapsed")
        try await requireChecklistControls(event, expanded: false)
        try await settleLayout()
        let collapsedHeight = try requireValue(controls.frame("event.card.\(event.id.uuidString)"), "collapsed card").height
        try require(collapsedHeight < expandedHeight - 20, "collapsed checklist still occupies its expanded height")
        try await requireChecklistControls(sibling, expanded: true)
        try require(store.subtasksAreExpanded(for: sibling.id), "collapse changed another event's preference")
        let preferences = SubtaskDisclosurePersistence(defaults: configuration.defaults)
        try require(!preferences.isExpanded(eventID: event.id) && preferences.isExpanded(eventID: sibling.id),
                    "independent disclosure preferences were not persisted")
        try await hideAndShow()
        try require(!store.subtasksAreExpanded(for: event.id), "hide/show reset the collapsed preference")
        try require(try Data(contentsOf: configuration.dataURL) == savedJSON,
                    "disclosure changed persisted event content")
        pass("interrupted checklist transitions honor the last request, reject hidden controls and preserve independent preferences/data")

        try await press(disclosure)
        try await requireChecklistControls(event, expanded: true)
        try await settleLayout()
        try requireChecklistOrder(event)
        let reopened = try requireValue(event.subtasks.first(where: \.isCompleted), "completed fixture task")
        try await press("subtask.toggle.\(reopened.id.uuidString)")
        try await waitForValue("subtask.toggle.\(reopened.id.uuidString)", equals: "active")
        let updated = try requireValue(store.active.first(where: { $0.id == event.id }), "updated collapse fixture")
        try await settleLayout()
        try requireChecklistOrder(updated)
        try await waitFor("reopened task persisted") {
            guard let bytes = try? Data(contentsOf: self.configuration.dataURL),
                  let data = try? JSONDecoder().decode(CountdownData.self, from: bytes) else { return false }
            return data.items.first(where: { $0.id == event.id }) == updated
        }
        let updatedJSON = try Data(contentsOf: configuration.dataURL)
        try await press(disclosure)
        try await requireChecklistControls(updated, expanded: false)
        try await press(disclosure)
        try await requireChecklistControls(updated, expanded: true)
        try await settleLayout()
        try requireChecklistOrder(updated)
        try require(try Data(contentsOf: configuration.dataURL) == updatedJSON,
                    "reopening checklist changed completion data")
        pass("completed tasks survive disclosure and reopen in stable active/completed order")
    }

    private func requireChecklistControls(_ event: Countdown, expanded: Bool) async throws {
        let ids = event.subtasks.map { "subtask.toggle.\($0.id.uuidString)" }
        try await waitFor("checklist controls \(expanded ? "expanded" : "hidden")") {
            ids.allSatisfy { self.controls.entries[$0]?.isEnabled == expanded }
        }
        if !expanded {
            for id in ids {
                try require(!controls.press(id), "collapsed checklist still accepts task changes")
            }
        }
    }

    private func requireChecklistOrder(_ event: Countdown) throws {
        let ordered = event.subtasks.filter { !$0.isCompleted } + event.subtasks.filter(\.isCompleted)
        let frames = try ordered.map { subtask in
            let id = "subtask.toggle.\(subtask.id.uuidString)"
            try require(controls.value(id) == (subtask.isCompleted ? "completed" : "active"),
                        "rendered checklist lost completion state")
            return try requireValue(controls.frame(id), "ordered checklist control")
        }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            try require(upper.maxY <= lower.minY + 0.5, "checklist does not preserve active/completed group order")
        }
    }

    private func runVisualCaptures() async throws {
        try require(store.active.count == 2, "today capture fixture did not load")
        visualEnvironment.colorSchemeOverride = .dark
        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: false)

        let todayPrimary = try requireValue(store.primary, "today capture primary")
        try require(todayPrimary.title == "Сегодня: важная встреча", "today capture title is incorrect")
        try require(todayPrimary.date == store.today, "today capture date is incorrect")
        try require(store.active.contains { $0.title == "Короткое событие" },
                    "today capture secondary event is missing")
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 2)
        try capture(name: "12-today-badge")
        for item in store.active {
            let removed = await store.delete(item.id)
            try require(removed, "today capture fixture removal failed")
        }
        try await waitFor("empty capture fixture after today capture") { self.store.active.isEmpty }

        try require(timer.phase == .finished, "finished timer capture fixture was not restored")
        try await settleLayout()
        try capture(name: "05-timer-finished")

        timer.delete()
        try await waitFor("idle timer for empty capture") { self.timer.phase == .idle }
        try await settleLayout()
        try capture(name: "06-empty")

        let primary = Countdown(
            title: "Переезд в новую квартиру",
            note: "Длинная карточка с заметкой и чек-листом для визуальной проверки.",
            date: Day(store.tomorrow),
            emoji: "📦",
            subtasks: try [
                Subtask(text: "Подтвердить время доставки"),
                Subtask(text: "Собрать документы", isCompleted: true),
                Subtask(text: "Проверить адрес"),
            ]
        )
        let secondary = [
            Countdown(title: "Короткое событие", date: Day(store.tomorrow), emoji: "✨"),
            Countdown(
                title: "День рождения Маши",
                note: "Выбрать подарок и заказать торт.",
                date: Day(store.tomorrow),
                emoji: "🎂",
                subtasks: try [Subtask(text: "Позвонить"), Subtask(text: "Купить свечи")]
            ),
            Countdown(title: "Понедельник", date: Day(store.tomorrow), emoji: "🗓️"),
            Countdown(title: "Билеты", date: Day(store.tomorrow), emoji: "✈️"),
            Countdown(
                title: "Нижнее короткое событие",
                date: Day(store.tomorrow),
                emoji: "⭐️"
            ),
        ]
        let savedPrimary = await store.save(primary, primary: true)
        try require(savedPrimary, "primary capture fixture save failed")
        for item in secondary {
            let savedSecondary = await store.save(item, primary: false)
            try require(savedSecondary, "secondary capture fixture save failed")
        }
        try await waitFor("varied-height capture list") { self.store.active.count == secondary.count + 1 }
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 4)
        try capture(name: "01-idle-list")

        try await scrollRootList()
        let promoted = try requireValue(secondary.last, "below-fold capture fixture")
        await store.makePrimary(promoted.id)
        try await waitFor("promoted primary") { self.store.data.primaryID == promoted.id }
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 4)
        try capture(name: "02-promoted-settled")

        timer.start(minutes: 5)
        try await waitFor("running timer") {
            if case .running = self.timer.phase { return true }
            return false
        }
        try await settleLayout()
        try capture(name: "03-timer-running")

        timer.delete()

        try await press("event.edit.\(promoted.id.uuidString)")
        try await waitForElement("editor.edit")
        try await settleLayout()
        try capture(name: "04-editor")

        try await press("editor.cancel")
        try await waitFor("list restored after editor capture") {
            self.controls.entries["editor.edit"] == nil
        }
        try await scrollRootListToTop()
        try await press("day.add")
        try await waitForElement("creation.day.chooseDate")
        try await settleLayout()
        try capture(name: "13-day-choices")
        try await press("creation.day.tomorrow")
        try await waitForValue("editor.title", equals: russianWeekdayTitle(Day(store.tomorrow)))
        try await settleLayout()
        try capture(name: "14-day-editor")
        try await press("editor.cancel")
        try await waitFor("list restored after day capture") { self.controls.entries["editor.new"] == nil }
        visualEnvironment.colorSchemeOverride = .light
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 4)
        try capture(name: "07-light-list")

        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: true, reduceMotion: false)
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 4)
        try capture(name: "08-light-high-contrast")

        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: false)
        visualEnvironment.colorSchemeOverride = .dark
        try await settleLayout()
        try await press("timer.duration.120")
        try await waitForValue("timer.duration", equals: "120")
        try await settleLayout()
        try requireTimerPresetLayout()
        try capture(name: "10-timer-preset-120-static")

        accessibilitySettings.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        try await settleLayout()
        try await press("timer.duration.5")
        try await waitForValue("timer.duration", equals: "5")
        try await settleLayout()
        try requireTimerPresetLayout()
        try capture(name: "11-timer-preset-reduced-motion-5-static")

        try await runReducedMotionDisclosureCapture(primary)

        timer.start(minutes: 5)
        try await waitFor("running timer with Reduce Motion override") {
            if case .running = self.timer.phase { return true }
            return false
        }
        try await settleLayout()
        try capture(name: "09-reduce-motion-running")
        try writeCaptureManifest()
        pass("real panel capture set records baseline and isolated accessibility states")
    }

    private func runReducedMotionDisclosureCapture(_ event: Countdown) async throws {
        try require(accessibilitySettings.prefersReducedMotion, "reduced-motion capture override was not applied")
        let disclosure = "subtasks.disclosure.\(event.id.uuidString)"
        let savedJSON = try Data(contentsOf: configuration.dataURL)
        try await requireChecklistControls(event, expanded: true)
        try await press(disclosure)
        try await requireChecklistControls(event, expanded: false)
        try await settleLayout()
        try requireNonOverlappingCardFrames(minimumCount: 4)
        try capture(name: "15-subtasks-reduced-motion-collapsed")
        try await press(disclosure)
        try await requireChecklistControls(event, expanded: true)
        try await settleLayout()
        try requireChecklistOrder(event)
        try require(try Data(contentsOf: configuration.dataURL) == savedJSON,
                    "reduced-motion disclosure changed persisted event content")
        pass("reduced-motion checklist closes noninteractive and reopens with completion groups intact")
    }

    private func settleLayout() async throws {
        try await Task.sleep(nanoseconds: 250_000_000)
        window()?.contentView?.layoutSubtreeIfNeeded()
        window()?.contentView?.display()
        CATransaction.flush()
        await Task.yield()
    }

    private func requireNonOverlappingCardFrames(minimumCount: Int) throws {
        let frames = controls.ids(withPrefix: "event.card.")
            .compactMap { controls.frame($0) }
            .sorted { $0.minY < $1.minY }
        try require(frames.count >= minimumCount, "capture fixture did not render enough card frames")
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            try require(upper.maxY <= lower.minY + 0.5, "event card frames overlap")
        }
    }

    private func capture(name: String) throws {
        guard UISmokeConfiguration.captureWasRequested else {
            throw Failure("capture requested outside isolated capture mode")
        }
        let panel = try requireValue(window(), "capture panel")
        let contentView = try requireValue(panel.contentView, "capture content view")
        let bounds = contentView.bounds.integral
        contentView.layoutSubtreeIfNeeded()
        contentView.display()
        CATransaction.flush()
        guard let sourceBitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds) else {
            throw Failure("cannot allocate AppKit capture bitmap")
        }
        contentView.cacheDisplay(in: bounds, to: sourceBitmap)
        let width = sourceBitmap.pixelsWide
        let height = sourceBitmap.pixelsHigh
        let scale = Double(width) / Double(bounds.width)

        // A borderless panel has transparent rounded outer pixels.  Preserve the
        // retained SwiftUI hierarchy above its real Aurora canvas, rather than
        // exporting those pixels against whatever happens to be behind the panel.
        let isDark = visualEnvironment.colorSchemeOverride == .dark
            || (visualEnvironment.colorSchemeOverride == nil
                && panel.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let canvas = NSColor(AuroraInstrument.canvas(for: isDark ? .dark : .light))
        try requireRetainedPanelCoverage(
            bitmap: sourceBitmap,
            canvas: canvas,
            captureName: name
        )
        guard let sourceImage = sourceBitmap.cgImage,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else {
            throw Failure("cannot create opaque capture bitmap")
        }
        context.setFillColor(canvas.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let compositeImage = context.makeImage() else {
            throw Failure("cannot finalize opaque capture bitmap")
        }
        let bitmap = NSBitmapImageRep(cgImage: compositeImage)
        bitmap.size = bounds.size
        let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
        let opaqueCorners = corners.allSatisfy { point in
            (bitmap.colorAt(x: point.0, y: point.1)?.alphaComponent ?? 0) >= 0.99
        }
        try require(opaqueCorners, "capture did not composite against the panel canvas")
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure("cannot encode PNG capture")
        }
        let directory = configuration.homeURL.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = "\(name).png"
        try png.write(to: directory.appendingPathComponent(file), options: .atomic)
        captures.append(CaptureRecord(
            name: name,
            file: file,
            width: width,
            height: height,
            scale: scale,
            opaqueCorners: opaqueCorners,
            colorSchemeOverride: visualEnvironment.colorSchemeOverride.map {
                $0 == .dark ? "dark" : "light"
            },
            highContrastOverride: accessibilitySettings.isolatedCaptureOverrideValue,
            reduceMotionOverride: accessibilitySettings.isolatedReduceMotionOverrideValue
        ))
    }

    private func requireRetainedPanelCoverage(
        bitmap: NSBitmapImageRep,
        canvas: NSColor,
        captureName: String
    ) throws {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let regions = [
            (name: "footer", y: Int(Double(height) * 0.02)..<Int(Double(height) * 0.16)),
            (name: "body", y: Int(Double(height) * 0.20)..<Int(Double(height) * 0.78)),
            (name: "header", y: Int(Double(height) * 0.84)..<Int(Double(height) * 0.98)),
        ]
        let xRange = Int(Double(width) * 0.05)..<Int(Double(width) * 0.95)
        let step = max(2, width / 160)
        guard let canvasRGB = canvas.usingColorSpace(.deviceRGB) else {
            throw Failure("cannot resolve capture canvas color")
        }

        for region in regions {
            var samples = 0
            var opaqueSamples = 0
            var nonCanvasSamples = 0
            for y in stride(from: region.y.lowerBound, to: region.y.upperBound, by: step) {
                for x in stride(from: xRange.lowerBound, to: xRange.upperBound, by: step) {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    samples += 1
                    if color.alphaComponent >= 0.9 {
                        opaqueSamples += 1
                    }
                    let distance = abs(color.redComponent - canvasRGB.redComponent)
                        + abs(color.greenComponent - canvasRGB.greenComponent)
                        + abs(color.blueComponent - canvasRGB.blueComponent)
                    if color.alphaComponent >= 0.1 && distance >= 0.08 {
                        nonCanvasSamples += 1
                    }
                }
            }
            try require(samples > 0, "capture \(captureName) has no \(region.name) samples")
            try require(
                Double(opaqueSamples) / Double(samples) >= 0.9,
                "capture \(captureName) retained \(region.name) is incomplete"
            )
            try require(
                nonCanvasSamples >= max(8, samples / 1_000),
                "capture \(captureName) retained \(region.name) has no visible content"
            )
        }
    }

    private func writeCaptureManifest() throws {
        try require(captures.count == 15, "capture set is incomplete")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifest = CaptureManifest(version: 2, captures: captures.sorted { $0.name < $1.name })
        let directory = configuration.homeURL.appendingPathComponent("Captures", isDirectory: true)
        try encoder.encode(manifest).write(
            to: directory.appendingPathComponent("manifest.json"),
            options: .atomic
        )
    }

    private func run() async throws {
        try require(store.active.isEmpty, "fixture must be isolated and empty")
        try await waitForValue("timer.duration", equals: "30")
        try await settleLayout()
        try requireTimerPresetLayout()
        try await press("timer.duration.120")
        try await waitForValue("timer.duration", equals: "120")
        try await press("timer.duration.5")
        try await waitForValue("timer.duration", equals: "5")
        for minutes in [40, 10, 60, 15, 120, 5] {
            try require(controls.press("timer.duration.\(minutes)"), "rapid timer preset tap failed")
        }
        try await waitForValue("timer.duration", equals: "5")
        try await press("timer.start")
        try await waitFor("Play uses final five-minute preset") {
            guard case let .running(remainingSeconds) = self.timer.phase else { return false }
            return (295...300).contains(remainingSeconds)
        }
        timer.delete()
        try await waitFor("timer returns to idle after preset smoke") { self.timer.phase == .idle }
        pass("timer preset selection reaches both ends, is last-tap-wins and drives Play")
        try await verifyCompletionAlertDismissal()

        try await press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Window smoke event")
        try await focusAndReplace("editor.note", with: "Private synthetic note")
        for text in [
            "Alpha", "Beta", "Gamma", "Delta", "Epsilon",
            "Zeta", "Eta", "Theta", "Iota", "Kappa",
        ] {
            let before = Set(controls.ids(withPrefix: "editor.subtask."))
            try await press("editor.subtask.add")
            try await waitFor("new subtask") {
                Set(self.controls.ids(withPrefix: "editor.subtask.")).subtracting(before).count == 1
            }
            let field = try requireValue(Set(controls.ids(withPrefix: "editor.subtask.")).subtracting(before).first, "subtask field")
            try await waitForFirstResponder(field)
            try insertText(text)
            try await waitForValue(field, equals: text)
        }
        try require(controls.entries["editor.subtask.add"] == nil, "eleventh subtask must not be available")
        try await press("editor.emoji.more")
        try await waitForValue("editor.emoji.category", equals: "Общие")
        try await waitFor("unique expanded emoji controls") {
            self.controls.ids(withPrefix: "editor.emoji.option.").count == 232
        }
        try await press("editor.emoji.page.dot.2")
        try await waitForValue("editor.emoji.category", equals: "Дети")
        try await press("editor.emoji.option.page.2.row.1.column.1.1f476")
        try await waitForValue("editor.emoji", equals: "👶")
        try await waitForValue("editor.emoji.more", equals: "collapsed")
        try await press("editor.emoji.preset.1f680")
        try await waitForValue("editor.emoji", equals: "🚀")
        try await hideAndShow()
        try require(controls.value("editor.title") == "Window smoke event", "draft lost on close")
        try require(!FileManager.default.fileExists(atPath: configuration.dataURL.path), "unsaved draft wrote JSON")
        try await press("editor.save")
        try await waitFor("save") { self.store.active.count == 1 && self.controls.entries["editor.new"] == nil }
        let item = try requireValue(store.active.first, "saved event")
        try require(item.subtasks.count == 10 && item.emoji == "🚀" && item.note == "Private synthetic note", "editor fields not saved")
        try require(store.data.primaryID == item.id, "first event must be primary")
        pass("single editor persists note, emoji and ten subtasks only on Save")
        let task = item.subtasks[0]
        let toggle = "subtask.toggle.\(task.id.uuidString)"
        try await waitForElement(toggle)
        try await press(toggle)
        try await waitForValue(toggle, equals: "completed")
        try await press(toggle)
        try await waitForValue(toggle, equals: "active")
        pass("completion can be toggled and reopened")

        try await press("event.edit.\(item.id.uuidString)")
        try await waitForElement("editor.edit")
        try await focusAndReplace("editor.title", with: "Keep unavailable draft")
        // Force a write failure only within this explicitly isolated fixture.
        let backup = configuration.dataURL.appendingPathExtension("backup")
        try FileManager.default.moveItem(at: configuration.dataURL, to: backup)
        try FileManager.default.createDirectory(at: configuration.dataURL, withIntermediateDirectories: false)
        defer {
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.removeItem(at: configuration.dataURL)
                try? FileManager.default.moveItem(at: backup, to: configuration.dataURL)
            }
        }
        try await press("editor.save")
        try await waitFor("write failure retains editor") {
            self.store.error != nil && self.controls.entries["editor.save"]?.isEnabled == true
        }
        try require(controls.value("editor.title") == "Keep unavailable draft", "write failure discarded draft")
        try require(store.data.items.first?.title == item.title, "write failure did not roll back stored state")
        try FileManager.default.removeItem(at: configuration.dataURL)
        try FileManager.default.moveItem(at: backup, to: configuration.dataURL)
        store.error = nil
        pass("write failure retains draft and rolls back event data")
        // Simulates domain removal while editing; no production data is involved.
        let removed = await store.delete(item.id)
        try require(removed, "fixture removal failed")
        try await waitForElement("editor.unavailable")
        try require(controls.value("editor.title") == "Keep unavailable draft", "removed event discarded draft")
        try await waitFor("unavailable Save disabled") { self.controls.entries["editor.save"]?.isEnabled == false }
        try await hideAndShow()
        try require(controls.entries["editor.edit"] != nil, "unavailable editor lost on hide")
        try await press("editor.cancel")
        try await waitFor("unavailable Cancel") { self.controls.entries["editor.edit"] == nil }
        pass("removed event retains draft and disables Save without resurrection")

        let restored = await store.save(item, primary: true)
        try require(restored, "test fixture restoration failed")
        try await waitForElement("event.edit.\(item.id.uuidString)")
        try await press("event.edit.\(item.id.uuidString)")
        try await waitForElement("editor.edit")
        try await press("event.delete")
        try await waitForElement("event.delete.cancel")
        try await press("event.delete.cancel")
        try require(store.active.count == 1, "deletion Cancel removed event")
        try await press("event.delete")
        try await waitForElement("event.delete.confirm")
        try await press("event.delete.confirm")
        try await waitFor("confirmed delete") { self.store.active.isEmpty && self.controls.entries["editor.edit"] == nil }
        pass("inline deletion confirmation preserves cancellation and persists explicit deletion")
        try verifyDiagnosticsPrivacy(forbidden: ["Window smoke event", "Private synthetic note", "Keep unavailable draft", "Alpha", "😎"])
        pass("diagnostics remain free of private editor input")
        try await verifyDayCreation()
    }

    private func verifyDayCreation() async throws {
        let initialData = store.data
        let initialJSON = try Data(contentsOf: configuration.dataURL)
        let tomorrow = Day(store.tomorrow)
        try await press("day.add")
        try await press("creation.day.tomorrow")
        try await waitForElement("editor.new")
        try await waitForValue("editor.title", equals: russianWeekdayTitle(tomorrow))
        try await waitForValue("editor.emoji", equals: "📅")
        try require(controls.value("editor.note")?.isEmpty == true, "new day has a nonempty note")
        try require(editorSubtaskFieldIDs().isEmpty, "new day inherited subtasks")
        try require(controls.value("editor.date") == dateValue(tomorrow), "new day is not tomorrow")
        try require(store.data == initialData, "opening day editor created event data")
        try require(Data(contentsOf: configuration.dataURL) == initialJSON, "opening day editor wrote JSON")

        let chosenDay = Day(Day.calendar.date(byAdding: .day, value: 2, to: store.today.date())!)
        try await selectEditorDate(chosenDay)
        try await waitForValue("editor.title", equals: russianWeekdayTitle(chosenDay))
        try await focusAndReplace("editor.title", with: "Personal day plan")
        let finalDay = Day(Day.calendar.date(byAdding: .day, value: 3, to: store.today.date())!)
        try await selectEditorDate(finalDay)
        try require(controls.value("editor.title") == "Personal day plan", "date overwrote a manual day title")
        try await focusAndReplace("editor.note", with: "Synthetic day note")
        try await press("editor.subtask.add")
        try await waitFor("one day subtask") { self.editorSubtaskFieldIDs().count == 1 }
        let field = try requireValue(editorSubtaskFieldIDs().first, "day subtask field")
        try await waitForFirstResponder(field)
        try insertText("Sport")
        try await waitForValue(field, equals: "Sport")
        let owner = controls.entries["editor.new"]?.ownerID
        try require(!controls.press("day.add"), "inactive day creation action accepted input while editing")
        try await hideAndShow(usingStatusItem: true)
        try require(controls.entries["editor.new"]?.ownerID == owner, "day editor identity changed on reopen")
        try require(controls.value("editor.title") == "Personal day plan"
                    && controls.value("editor.note") == "Synthetic day note"
                    && controls.value(field) == "Sport"
                    && controls.value("editor.date") == dateValue(finalDay),
                    "day editor draft changed on reopen or repeated creation")
        try require(store.data == initialData, "unsaved day changed event data")
        try require(Data(contentsOf: configuration.dataURL) == initialJSON, "unsaved day wrote JSON")
        try await press("editor.save")
        try await waitFor("day saved") { self.controls.entries["editor.new"] == nil && self.store.active.count == 1 }
        let saved = try requireValue(store.active.first, "saved day")
        try require(saved.title == "Personal day plan" && saved.date == finalDay && saved.emoji == "📅"
                    && saved.note == "Synthetic day note" && saved.subtasks.count == 1
                    && saved.subtasks[0].text == "Sport" && !saved.subtasks[0].isCompleted,
                    "day Save did not persist the editor fields")
        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(persisted == store.data, "day Save is not durable")
        pass("tomorrow day defaults, native date/title changes and manual override persist only on Save; draft survives hide/show")

        let savedJSON = try Data(contentsOf: configuration.dataURL)
        let savedData = store.data
        try await press("day.add")
        try await press("creation.day.chooseDate")
        try await waitForElement("editor.new")
        try await waitForValue("editor.title", equals: russianWeekdayTitle(tomorrow))
        try require(controls.value("editor.note")?.isEmpty == true && controls.value("editor.emoji") == "📅"
                    && editorSubtaskFieldIDs().isEmpty,
                    "choose-date day inherited the previously saved plan")
        let selectedDay = Day(Day.calendar.date(byAdding: .day, value: 4, to: store.today.date())!)
        try await selectEditorDate(selectedDay)
        try await waitForValue("editor.title", equals: russianWeekdayTitle(selectedDay))
        try await hideAndShow()
        try await press("editor.cancel")
        try await waitFor("day cancelled") { self.controls.entries["editor.new"] == nil }
        try require(store.data == savedData, "day Cancel changed event data")
        try require(Data(contentsOf: configuration.dataURL) == savedJSON, "day Cancel wrote JSON")
        pass("choose-date day starts blank, follows its chosen date and Cancel leaves durable data unchanged")
        try verifyDiagnosticsPrivacy(forbidden: ["Personal day plan", "Synthetic day note", "Sport"])
    }

    private func dateValue(_ day: Day) -> String {
        "\(day.year)-\(day.month)-\(day.day)"
    }

    private func editorSubtaskFieldIDs() -> [String] {
        controls.ids(withPrefix: "editor.subtask.").filter { $0 != "editor.subtask.add" }
    }

    private func selectEditorDate(_ day: Day) async throws {
        let content = try requireValue(window()?.contentView, "editor content")
        let picker = try requireValue(allSubviews(of: content).compactMap { $0 as? NSDatePicker }.first,
                                     "native editor date picker")
        picker.dateValue = day.date()
        try require(picker.sendAction(picker.action, to: picker.target), "native date picker did not deliver its action")
        try await waitForValue("editor.date", equals: dateValue(day))
    }

    private func scrollRootList() async throws {
        guard let scrollView = rootListScrollView() else {
            throw Failure("root event list is not scrollable")
        }
        let clipView = scrollView.contentView
        let visible = clipView.documentVisibleRect
        let maximumY = max(0, (scrollView.documentView?.bounds.height ?? 0) - visible.height)
        let targetY = min(maximumY, max(visible.origin.y + visible.height / 2, 1))
        guard targetY > visible.origin.y else {
            throw Failure("root event list did not expose a scroll range")
        }
        clipView.scroll(to: CGPoint(x: visible.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clipView)
        try await waitFor("real root list scroll") {
            guard let current = self.rootListScrollView()?.contentView.documentVisibleRect else { return false }
            return current.origin.y > visible.origin.y
        }
    }

    private func requireTimerPresetLayout() throws {
        let timerFrame = try requireValue(controls.frame("timer"), "timer strip frame")
        let selectorFrame = try requireValue(controls.frame("timer.duration"), "timer preset selector frame")
        try require(abs(timerFrame.height - 59) < 1, "timer strip height changed")
        let segmentFrames = countdownTimerPresetMinutes.compactMap {
            controls.frame("timer.duration.\($0)")
        }
        try require(segmentFrames.count == countdownTimerPresetMinutes.count, "timer preset segments are incomplete")
        for frame in segmentFrames {
            try require(frame.width >= 30 && frame.height >= 26, "timer preset hit area is too small")
            try require(frame.minX >= selectorFrame.minX - 1 && frame.maxX <= selectorFrame.maxX + 1,
                        "timer preset segment escaped selector bounds")
        }
    }

    private func scrollRootListToTop() async throws {
        guard let scrollView = rootListScrollView() else {
            throw Failure("root event list is not scrollable")
        }
        let clipView = scrollView.contentView
        clipView.scroll(to: CGPoint(x: clipView.bounds.origin.x, y: 0))
        scrollView.reflectScrolledClipView(clipView)
        try await waitFor("root list returned to top") {
            guard let current = self.rootListScrollView()?.contentView.documentVisibleRect else { return false }
            return abs(current.origin.y) < 1
        }
    }

    private func rootListScrollView() -> NSScrollView? {
        guard let contentView = window()?.contentView else { return nil }
        return allSubviews(of: contentView)
            .compactMap { $0 as? NSScrollView }
            .first {
                guard let documentView = $0.documentView else { return false }
                return documentView.bounds.height > $0.contentView.bounds.height
            }
    }

    private func requireNoUIStall() throws {
        DiagnosticLog.shared.flush()
        let log = (try? String(contentsOf: DiagnosticLog.fileURL, encoding: .utf8)) ?? ""
        try require(!log.contains("ui.stall detected"), "watchdog observed a UI stall")
    }

    private func focusAndReplace(_ id: String, with text: String) async throws {
        try await press(id)
        try await waitForFirstResponder(id)
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            throw Failure("\(id): focused editor is unavailable")
        }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        try await waitForValue(id, equals: text)
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allSubviews(of: $0) }
    }

    private func verifyCompletionAlertDismissal() async throws {
        let suite = "timer-alert-smoke-\(UUID().uuidString)"
        let defaults = try requireValue(UserDefaults(suiteName: suite), "isolated timer defaults")
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Date().addingTimeInterval(-1).timeIntervalSince1970,
                     forKey: CountdownTimer.deadlineKey)
        let finishedTimer = CountdownTimer(defaults: defaults)
        try require(finishedTimer.phase == .finished, "timer fixture is not finished")

        let presenter = TimerCompletionAlertPresenter()
        let originalKeyWindow = NSApp.keyWindow
        let originalActiveState = NSApp.isActive
        presenter.present()
        let panel = try requireValue(
            NSApp.windows.first { $0.identifier?.rawValue == "timer.completion.alert" },
            "completion alert panel"
        )
        try require(panel.isVisible && !panel.ignoresMouseEvents, "completion alert cannot receive a click")
        try require(NSApp.keyWindow === originalKeyWindow && NSApp.isActive == originalActiveState,
                    "presenting completion alert changed app focus")

        let content = try requireValue(panel.contentView, "completion alert content")
        let title = try requireValue(
            allSubviews(of: content).first { $0.identifier?.rawValue == "timer.completion.title" },
            "completion alert title"
        )
        let titlePoint = title.convert(NSPoint(x: title.bounds.midX, y: title.bounds.midY), to: nil)
        try require(content.hitTest(titlePoint) === content, "title click does not hit alert background")
        try postAlertClick(at: titlePoint, in: panel)
        try require(!panel.isVisible, "click on completion alert title did not hide panel immediately")
        try require(finishedTimer.phase == .finished, "dismissing alert deleted the timer")
        try require(NSApp.keyWindow === originalKeyWindow && NSApp.isActive == originalActiveState,
                    "clicking completion alert changed app focus")

        presenter.present()
        try require(panel.isVisible, "completion alert did not reappear")
        try postAlertClick(at: NSPoint(x: 8, y: 8), in: panel)
        try require(!panel.isVisible, "click on completion alert background did not hide panel immediately")
        try require(finishedTimer.phase == .finished, "background click deleted the timer")

        presenter.present()
        try require(panel.isVisible, "completion alert did not reappear for timeout check")
        let presentedAt = ProcessInfo.processInfo.systemUptime
        try await waitFor("completion alert auto dismisses", timeout: 6) { !panel.isVisible }
        try require(ProcessInfo.processInfo.systemUptime - presentedAt >= timerCompletionAlertDisplayDuration,
                    "completion alert auto dismissed too early")
        try require(finishedTimer.phase == .finished, "auto dismissal deleted the timer")
        pass("completion alert closes on its first click or after five seconds without changing timer state")
    }

    private func postAlertClick(at point: NSPoint, in panel: NSWindow) throws {
        for (type, eventNumber) in [(NSEvent.EventType.leftMouseDown, 1), (.leftMouseUp, 2)] {
            let event = try requireValue(
                NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: panel.windowNumber, context: nil,
                                   eventNumber: eventNumber, clickCount: 1, pressure: 1),
                "completion alert mouse event"
            )
            panel.sendEvent(event)
        }
    }

    private func insertText(_ text: String) throws {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            throw Failure("keyboard input has no NSTextView first responder")
        }
        editor.insertText(text, replacementRange: editor.selectedRange())
    }

    private func verifyDiagnosticsPrivacy(forbidden: [String]) throws {
        DiagnosticLog.shared.flush()
        let log = (try? String(contentsOf: DiagnosticLog.fileURL, encoding: .utf8)) ?? ""
        for value in forbidden {
            try require(!log.contains(value), "diagnostic log contains private fixture text")
        }
    }

    private func press(_ id: String) async throws {
        try await waitFor("enabled control \(id)") { self.controls.entries[id]?.isEnabled == true }
        try require(controls.press(id), "semantic control is missing or disabled: \(id)")
    }

    private func waitForElement(_ id: String) async throws {
        try await waitFor(id) { self.controls.entries[id] != nil }
    }

    private func waitForValue(_ id: String, equals expected: String) async throws {
        try await waitFor("\(id) = \(expected)") { self.controls.value(id) == expected }
    }

    private func waitForFirstResponder(_ description: String) async throws {
        try await waitFor("first responder for \(description)") {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView,
                  self.controls.focusedID == description,
                  let fieldFrame = self.controls.frame(description),
                  let delegateView = editor.delegate as? NSView,
                  let responderWindow = delegateView.window,
                  let contentView = responderWindow.contentView else { return false }
            let responderFrame = delegateView.convert(delegateView.bounds, to: contentView)
            let windowID = ObjectIdentifier(responderWindow)
            if self.responderToRegistryOffsets[windowID] == nil {
                self.responderToRegistryOffsets[windowID] = CGPoint(
                    x: fieldFrame.minX - responderFrame.minX,
                    y: fieldFrame.minY - responderFrame.minY
                )
            }
            guard let offset = self.responderToRegistryOffsets[windowID] else { return false }
            return abs((responderFrame.minX + offset.x) - fieldFrame.minX) < 2
                && abs((responderFrame.minY + offset.y) - fieldFrame.minY) < 2
        }
    }

    private func waitFor(
        _ description: String,
        timeout: TimeInterval = 5,
        condition: @escaping () -> Bool
    ) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw Failure("timeout waiting for \(description)")
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw Failure(message) }
    }

    private func requireValue<T>(_ value: T?, _ description: String) throws -> T {
        guard let value else { throw Failure("missing \(description)") }
        return value
    }

    private func pass(_ name: String) {
        passed.append(name)
    }

    private func finishSuccess() {
        let lines = ["UISmoke"] + passed.map { "✓ \($0)" } + ["PASS: \(passed.count)/\(passed.count)"]
        finish(lines.joined(separator: "\n"), exitCode: 0)
    }

    private func finishFailure(_ error: Error) {
        let frames = ["editor.scroll", "editor.title", "editor.note"]
            .map { "\($0)=\(String(describing: controls.frame($0)))" }
            .joined(separator: ", ")
        let responder = NSApp.keyWindow?.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
        let delegate = (NSApp.keyWindow?.firstResponder as? NSTextView)?.delegate
            .map { String(describing: type(of: $0)) } ?? "nil"
        let delegateFrame: CGRect? = {
            guard let view = (NSApp.keyWindow?.firstResponder as? NSTextView)?.delegate as? NSView,
                  let contentView = view.window?.contentView else { return nil }
            return view.convert(view.bounds, to: contentView)
        }()
        let emoji = controls.value("editor.emoji") ?? "nil"
        let title = controls.value("editor.title") ?? "nil"
        let date = controls.value("editor.date") ?? "nil"
        let subtaskFrames = controls.ids(withPrefix: "subtask.toggle.")
            .map { "\($0)=\(String(describing: controls.frame($0)))" }
            .joined(separator: ", ")
        finish(
            "UISmoke\nWindow visible=\(window()?.isVisible == true), key=\(window()?.isKeyWindow == true), loading=\(store.isLoading), saveEnabled=\(controls.entries["editor.save"]?.isEnabled == true)\nFAIL after \(passed.count) scenarios: \(error.localizedDescription)\nActual: focus=\(controls.focusedID ?? "nil"), responder=\(responder), delegate=\(delegate), delegateFrame=\(String(describing: delegateFrame)), title=\(title), date=\(date), emoji=\(emoji), \(frames), \(subtaskFrames)",
            exitCode: 1
        )
    }

    private func finish(_ output: String, exitCode: Int32) {
        try? output.write(to: configuration.resultURL, atomically: true, encoding: .utf8)
        fputs(output + "\n", stderr)
        DiagnosticLog.shared.flush()
        configuration.defaults.removePersistentDomain(forName: configuration.defaultsSuiteName)
        Darwin.exit(exitCode)
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
