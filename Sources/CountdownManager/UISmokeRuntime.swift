import AppKit
import CountdownCore
import Darwin
import Foundation

struct UISmokeConfiguration {
    static let launchArgument = "--ui-smoke"
    static let collapseRegressionLaunchArgument = "--ui-smoke-collapse-regression"
    static let editorScrollRegressionLaunchArgument = "--ui-smoke-editor-scroll-regression"
    static let markerName = ".countdown-ui-smoke-environment"
    static let xcuiTestLaunchArgument = "--xcui-testing"
    static let xcuiTestMarkerName = ".countdown-xcui-test-environment"

    let homeURL: URL
    let resultURL: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    static var wasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
    }

    static var xcuiTestWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(xcuiTestLaunchArgument)
    }

    static var isolatedTestEnvironmentWasRequested: Bool {
        wasRequested || xcuiTestWasRequested
    }

    static var collapseRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
    }

    static var editorScrollRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
    }

    static func load() throws -> UISmokeConfiguration? {
        guard isolatedTestEnvironmentWasRequested else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let rawHome = environment["COUNTDOWN_MANAGER_TEST_HOME"], !rawHome.isEmpty else {
            throw Failure("COUNTDOWN_MANAGER_TEST_HOME is required")
        }
        let homeURL = URL(fileURLWithPath: rawHome, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        let requiredMarker = xcuiTestWasRequested ? xcuiTestMarkerName : markerName
        guard FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(requiredMarker).path) else {
            throw Failure("test-home marker is missing")
        }
        if let accountHome = environment["HOME"] {
            let productionSupport = URL(fileURLWithPath: accountHome, isDirectory: true)
                .appendingPathComponent("Library/Application Support/CountdownManager", isDirectory: true)
                .standardizedFileURL.resolvingSymlinksInPath()
            guard homeURL.path != productionSupport.path,
                  !homeURL.path.hasPrefix(productionSupport.path + "/"),
                  !productionSupport.path.hasPrefix(homeURL.path + "/") else {
                throw Failure("test home overlaps production Application Support")
            }
        }
        let resultURL = homeURL.appendingPathComponent("ui-smoke-result.txt")
        let suiteName = "local.countdownmanager.ui-smoke.\(homeURL.deletingLastPathComponent().lastPathComponent).\(homeURL.lastPathComponent)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw Failure("cannot create isolated UserDefaults")
        }
        return UISmokeConfiguration(
            homeURL: homeURL,
            resultURL: resultURL,
            defaults: defaults,
            defaultsSuiteName: suiteName
        )
    }

    var dataURL: URL {
        homeURL.appendingPathComponent("Application Support/CountdownManager/countdowns.json")
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@MainActor
final class UISmokeRuntime {
    private let configuration: UISmokeConfiguration
    private let store: Store
    private let window: () -> NSWindow?
    private let showWindow: () -> Void
    private let pressStatusItem: () -> Void
    private let controls = UISmokeControlRegistry.shared
    private var passed: [String] = []
    private var responderToRegistryOffsets: [ObjectIdentifier: CGPoint] = [:]

    init(configuration: UISmokeConfiguration, store: Store, window: @escaping () -> NSWindow?,
         showWindow: @escaping () -> Void,
         pressStatusItem: @escaping () -> Void) {
        self.configuration = configuration
        self.store = store
        self.window = window
        self.showWindow = showWindow
        self.pressStatusItem = pressStatusItem
    }

    func start() {
        Task { @MainActor in
            do {
                try await waitFor("loaded root window") {
                    self.window()?.isVisible == true && !self.store.isLoading
                        && self.controls.value("root.window") != nil
                        && self.controls.entries["event.add"]?.isEnabled == true
                }
                if UISmokeConfiguration.collapseRegressionWasRequested {
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

    // Calls in this runtime exercise AppKit/SwiftUI integration, not external clicks.
    private func hideAndShow(usingStatusItem: Bool = false) async throws {
        let original = try requireValue(window(), "window")
        let host = original.contentViewController
        let content = original.contentView
        let token = controls.value("root.window")
        if usingStatusItem { pressStatusItem() } else { original.orderOut(nil) }
        try await waitFor("window hidden") { !original.isVisible }
        try require(window() === original, "hidden window was replaced")
        if usingStatusItem { pressStatusItem() } else { showWindow() }
        try await waitFor("same window visible and key") { original.isVisible && original.isKeyWindow }
        try require(original.isOnActiveSpace, "shown window is not on the active Space")
        try require(window() === original && original.contentViewController === host && original.contentView === content,
                    "window or hosting hierarchy was reconstructed")
        try require(controls.value("root.window") == token, "root State identity changed")
    }

    private func runSessionContinuity() async throws {
        let shell = try requireValue(window(), "window")
        let shellHost = shell.contentViewController
        let shellContent = shell.contentView
        let rootToken = controls.value("root.window")
        try require(shell.styleMask == .borderless, "window is not using a borderless frame")
        try require(shell.standardWindowButton(.closeButton) == nil
                    && shell.standardWindowButton(.miniaturizeButton) == nil
                    && shell.standardWindowButton(.zoomButton) == nil,
                    "borderless window unexpectedly exposes title-bar controls")
        try require(shell.canBecomeKey && shell.canBecomeMain,
                    "borderless window cannot accept normal focus")
        pass("borderless window has no title-bar controls and can accept key focus")

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
        pass("window, host, root State and long-list scroll survive direct hide/show")

        try require(shell.isKeyWindow, "main-list window is not key before lifecycle check")
        shell.orderOut(nil)
        try await waitFor("main-list shell hide hides window") { !shell.isVisible }
        showWindow()
        try await waitFor("auto-hidden main list reopens key") { shell.isVisible && shell.isKeyWindow }
        try require(window() === shell && shell.contentViewController === shellHost && shell.contentView === shellContent,
                    "main-list auto-hide reconstructed the window or hosting hierarchy")
        try require(controls.value("root.window") == rootToken && rootListScrollView() === list,
                    "main-list auto-hide changed root or list identity")
        try require(abs(list.contentView.bounds.origin.y - position.y) < 1,
                    "main-list auto-hide reset list position")
        pass("main-list shell hide preserves the UI session")

        try await press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Session draft")
        try await waitForValue("editor.title", equals: "Session draft")
        let editorOwner = controls.entries["editor.new"]?.ownerID
        shell.orderOut(nil)
        try await waitFor("editor shell hide hides window") { !shell.isVisible }
        try require(window() === shell && shell.contentViewController === shellHost && shell.contentView === shellContent,
                    "auto-hide reconstructed the window or hosting hierarchy")
        try require(controls.value("root.window") == rootToken
                    && controls.entries["editor.new"]?.ownerID == editorOwner
                    && controls.value("editor.title") == "Session draft",
                    "auto-hide changed root, editor or draft state")
        showWindow()
        try await waitFor("auto-hidden window reopens key") { shell.isVisible && shell.isKeyWindow }
        try insertText("a")
        try await waitForValue("editor.title", equals: "Session drafta")
        pass("editor shell hide preserves the UI session")
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
                                  subtasks: try (1...5).map { try Subtask(text: "Task \($0)") })
            let saved = await store.save(event, primary: false)
            try require(saved, "fixture save failed")
        }
        let event = try requireValue(store.active.first, "collapse fixture")
        let disclosure = "subtasks.disclosure.\(event.id.uuidString)"
        try await waitForValue(disclosure, equals: "expanded")
        for _ in 0..<8 {
            try await press(disclosure)
            try await waitForValue(disclosure, equals: "collapsed")
            try await press(disclosure)
            try await waitForValue(disclosure, equals: "expanded")
        }
        pass("repeated checklist collapse/expand remains responsive with multiple events")
    }

    private func run() async throws {
        try require(store.active.isEmpty, "fixture must be isolated and empty")
        try await press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Window smoke event")
        try await focusAndReplace("editor.note", with: "Private synthetic note")
        for text in ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"] {
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
        try require(controls.entries["editor.subtask.add"] == nil, "sixth subtask must not be available")
        try await press("editor.emoji.option.1f60e")
        try await waitForValue("editor.emoji", equals: "😎")
        try await hideAndShow()
        try require(controls.value("editor.title") == "Window smoke event", "draft lost on close")
        try require(!FileManager.default.fileExists(atPath: configuration.dataURL.path), "unsaved draft wrote JSON")
        try await press("editor.save")
        try await waitFor("save") { self.store.active.count == 1 && self.controls.entries["editor.new"] == nil }
        let item = try requireValue(store.active.first, "saved event")
        try require(item.subtasks.count == 5 && item.emoji == "😎" && item.note == "Private synthetic note", "editor fields not saved")
        try require(store.data.primaryID == item.id, "first event must be primary")
        pass("single editor persists note, emoji and five subtasks only on Save")
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
        let subtaskFrames = controls.ids(withPrefix: "subtask.toggle.")
            .map { "\($0)=\(String(describing: controls.frame($0)))" }
            .joined(separator: ", ")
        finish(
            "UISmoke\nWindow visible=\(window()?.isVisible == true), key=\(window()?.isKeyWindow == true), loading=\(store.isLoading), saveEnabled=\(controls.entries["editor.save"]?.isEnabled == true)\nFAIL after \(passed.count) scenarios: \(error.localizedDescription)\nActual: focus=\(controls.focusedID ?? "nil"), responder=\(responder), delegate=\(delegate), delegateFrame=\(String(describing: delegateFrame)), emoji=\(emoji), \(frames), \(subtaskFrames)",
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
