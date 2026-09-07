import AppKit
import CountdownCore
import Darwin
import Foundation

struct UISmokeConfiguration {
    static let launchArgument = "--ui-smoke"
    static let collapseRegressionLaunchArgument = "--ui-smoke-collapse-regression"
    static let editorScrollRegressionLaunchArgument = "--ui-smoke-editor-scroll-regression"
    static let markerName = ".countdown-ui-smoke-environment"

    let homeURL: URL
    let resultURL: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    static var wasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
            || ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
            || ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
    }

    static var collapseRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(collapseRegressionLaunchArgument)
    }

    static var editorScrollRegressionWasRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(editorScrollRegressionLaunchArgument)
    }

    static func load() throws -> UISmokeConfiguration? {
        guard wasRequested else { return nil }
        let environment = ProcessInfo.processInfo.environment
        guard let rawHome = environment["COUNTDOWN_MANAGER_TEST_HOME"], !rawHome.isEmpty else {
            throw Failure("COUNTDOWN_MANAGER_TEST_HOME is required")
        }
        let homeURL = URL(fileURLWithPath: rawHome, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: homeURL.appendingPathComponent(markerName).path) else {
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
    private let closePopover: () -> Void
    private let openPopover: () -> Void
    private let isTransientPopoverReady: () -> Bool
    private let controls = UISmokeControlRegistry.shared
    private var passed: [String] = []
    private var responderToRegistryOffsets: [ObjectIdentifier: CGPoint] = [:]

    init(
        configuration: UISmokeConfiguration,
        store: Store,
        window: @escaping () -> NSWindow?,
        closePopover: @escaping () -> Void,
        openPopover: @escaping () -> Void,
        isTransientPopoverReady: @escaping () -> Bool
    ) {
        self.configuration = configuration
        self.store = store
        self.window = window
        self.closePopover = closePopover
        self.openPopover = openPopover
        self.isTransientPopoverReady = isTransientPopoverReady
    }

    func start() {
        Task { @MainActor in
            do {
                if UISmokeConfiguration.collapseRegressionWasRequested {
                    try await runCollapseRegression()
                } else if UISmokeConfiguration.editorScrollRegressionWasRequested {
                    try await runEditorScrollRegression()
                } else {
                    try await run()
                }
                finishSuccess()
            } catch {
                finishFailure(error)
            }
        }
    }

    private func runCollapseRegression() async throws {
        try await waitFor("empty root popup") {
            self.window() != nil && self.controls.entries["root.popup"] != nil
                && self.controls.entries["event.add"] != nil && !self.store.isLoading
        }
        try require(store.active.isEmpty, "initial isolated profile must be empty")

        try press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Collapse Regression One")
        for text in ["One A", "One B", "One C"] {
            let previous = Set(controls.ids(withPrefix: "editor.subtask."))
            try press("editor.subtask.add")
            try await waitFor("new regression subtask field") {
                Set(self.controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).count == 1
            }
            let id = try requireValue(
                Set(controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).first,
                "new regression subtask identifier"
            )
            try await waitForFirstResponder(id)
            try insertText(text)
            try await waitForValue(id, equals: text)
        }
        try press("editor.save")
        try await waitFor("saved regression event") {
            self.store.active.count == 1 && self.controls.entries["editor.new"] == nil
        }
        let first = try requireValue(store.active.first, "first saved regression event")
        try require(first.subtasks.count == 3, "first event subtasks were not saved")
        try await waitForElement("subtasks.disclosure.\(first.id.uuidString)")
        try await verifyDisclosureCycles(eventID: first.id, count: 4)
        pass("newly saved event remains responsive through repeated collapse and expand")

        for number in 2...7 {
            let event = Countdown(
                title: "Collapse Regression \(number)",
                date: Day(store.tomorrow),
                emoji: "📅",
                subtasks: try (1...5).map { try Subtask(text: "Event \(number) task \($0)") }
            )
            let didSave = await store.save(event, primary: false)
            try require(didSave, "event \(number) save failed")
        }
        try await waitFor("seven rendered events") {
            self.store.active.count == 7
                && self.controls.entries["subtasks.disclosure.\(first.id.uuidString)"] != nil
        }
        try await verifyDisclosureCycles(eventID: first.id, count: 4)
        pass("multiple events remain responsive through repeated collapse and expand")

        try await waitFor("persisted seven-event fixture") {
            guard let data = try? Data(contentsOf: self.configuration.dataURL),
                  let saved = try? JSONDecoder().decode(CountdownData.self, from: data) else { return false }
            return saved.items.count == 7
        }
        pass("regression fixture persisted in isolated profile")
    }

    private func runEditorScrollRegression() async throws {
        try await waitFor("empty root popup") {
            self.window() != nil && self.controls.entries["root.popup"] != nil
                && self.controls.entries["event.add"] != nil && !self.store.isLoading
        }
        try press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Editor Scroll Fixture")
        for text in ["Fixture one", "Fixture two"] {
            let previous = Set(controls.ids(withPrefix: "editor.subtask."))
            try press("editor.subtask.add")
            try await waitFor("fixture subtask") {
                Set(self.controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).count == 1
            }
            let id = try requireValue(
                Set(controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).first,
                "fixture subtask identifier"
            )
            try await waitForFirstResponder(id)
            try insertText(text)
            try await waitForValue(id, equals: text)
        }
        try press("editor.save")
        try await waitFor("saved editor-scroll fixture") { self.store.active.count == 1 }
        let eventID = try requireValue(store.active.first?.id, "editor-scroll event ID")

        var interactionEventID = eventID
        for number in 1...6 {
            let subtasks = number == 6 ? [try Subtask(text: "Scrollable interaction")] : []
            let event = Countdown(
                title: "Editor Scroll List \(number)",
                date: Day(store.tomorrow),
                emoji: "📅",
                subtasks: subtasks
            )
            let didSave = await store.save(event, primary: false)
            try require(didSave, "editor-scroll fixture \(number) save failed")
            if number == 6 { interactionEventID = event.id }
        }
        try await waitFor("scrollable root list") {
            self.store.active.count == 7 && self.rootListScrollView() != nil
        }
        let expectedCount = store.active.count
        let editedEventTitle = try requireValue(
            store.active.first(where: { $0.id == interactionEventID })?.title,
            "scrollable editor event title"
        )
        let memoryBaseline = physicalFootprint()

        for attempt in 1...3 {
            try press("event.add")
            try await waitForElement("editor.new")
            try await waitForFirstResponder("editor.title")
            try insertText("Unsaved new \(attempt)")
            try press("editor.cancel")
            try await waitForElement("event.list")
            try await dismissAndReopen()
            try await exerciseResponsiveRoot(eventID: interactionEventID, baselineFootprint: memoryBaseline)
            try require(store.active.count == expectedCount, "new draft changed root data")
        }
        pass("new editor cancel, popup reset, real root scroll and interaction remain responsive")

        for attempt in 1...3 {
            try await scrollRootList()
            try await pressEventAction("edit", eventID: interactionEventID)
            try await waitForElement("editor.edit")
            try await focusAndReplace("editor.title", with: "Unsaved edit \(attempt)")
            try await dismissAndReopen()
            try require(store.active.first(where: { $0.id == interactionEventID })?.title == editedEventTitle, "edit draft persisted")
            try await exerciseResponsiveRoot(eventID: interactionEventID, baselineFootprint: memoryBaseline)
            try require(store.active.count == expectedCount, "edit draft changed root data")
        }
        pass("existing editor dismissal, popup reset, real root scroll and interaction remain responsive")

        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(
            persisted.items.first(where: { $0.id == interactionEventID })?.title == editedEventTitle,
            "unsaved editor text reached JSON"
        )
        try requireNoUIStall()
        pass("unsaved data is absent from JSON, watchdog is clean and footprint stays bounded")
    }

    private func verifyDisclosureCycles(eventID: UUID, count: Int) async throws {
        let id = "subtasks.disclosure.\(eventID.uuidString)"
        let firstSubtaskID = try requireValue(
            store.active.first(where: { $0.id == eventID })?.subtasks.first?.id,
            "subtask for disclosure regression"
        )
        let renderedSubtaskID = "subtask.toggle.\(firstSubtaskID.uuidString)"
        try await waitForValue(id, equals: "expanded")
        try await waitForElement(renderedSubtaskID)
        for _ in 0..<count {
            try press(id)
            try await waitFor(id + " collapsed", timeout: 2) {
                self.controls.value(id) == "collapsed"
                    && self.controls.entries[renderedSubtaskID] == nil
            }
            try press(id)
            try await waitFor(id + " expanded", timeout: 2) {
                self.controls.value(id) == "expanded"
                    && self.controls.entries[renderedSubtaskID] != nil
            }
        }
    }

    private func run() async throws {
        try await waitFor("empty root popup") {
            self.window() != nil && self.controls.entries["root.popup"] != nil
                && self.controls.entries["event.add"] != nil && !self.store.isLoading
        }
        try require(store.active.isEmpty, "initial isolated profile must be empty")
        pass("existing empty state")
        try await dismissAndReopen()
        pass("popup lifecycle and root reset")

        try press("event.add")
        try await waitForElement("editor.new")
        try press("editor.cancel")
        try await waitForElement("event.add")
        try await waitForTransientPopoverReady()
        pass("new event Cancel restores transient popover interaction")

        try press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("Unsaved Smoke Draft")
        try await waitForValue("editor.title", equals: "Unsaved Smoke Draft")
        try await verifyCurrentFocusGeometry("editor.title")
        pass("new event initial title focus")
        try await focusAndReplace("editor.note", with: "Unsaved note")
        try await verifyCurrentFocusGeometry("editor.note")

        let subtaskTexts = ["Alpha", "Beta", "Gamma", "Delta", "Epsilon"]
        var subtaskIDs: [String] = []
        for text in subtaskTexts {
            let previous = Set(controls.ids(withPrefix: "editor.subtask."))
            try press("editor.subtask.add")
            try await waitFor("new subtask field") {
                Set(self.controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).count == 1
            }
            let newID = try requireValue(
                Set(controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).first,
                "new subtask identifier"
            )
            subtaskIDs.append(newID)
            try await waitForFirstResponder(newID)
            try insertText(text)
            try await waitForValue(newID, equals: text)
            try await verifyCurrentFocusGeometry(newID)
        }
        pass("new and sequential subtask autofocus")
        try require(controls.entries["editor.subtask.add"] == nil, "sixth subtask action must be absent")
        pass("fifth subtask autoscroll and focus-ring geometry")
        try require(controls.ids(withPrefix: "subtask.toggle.").isEmpty, "editor must not contain completion checkboxes")
        pass("editor has no editable completion checkbox")

        let unchangedTitle = try requireValue(controls.value("editor.title"), "draft title")
        let unchangedNote = try requireValue(controls.value("editor.note"), "draft note")
        let unchangedSubtasks = try subtaskIDs.map { try requireValue(controls.value($0), $0) }
        try press("editor.emoji.control")
        try await waitForElement("editor.emoji.picker")
        try press("editor.emoji.option.1f60e")
        try await waitFor("emoji selection") {
            self.controls.entries["editor.emoji.picker"] == nil
                && self.controls.value("editor.emoji.control") == "😎"
                && NSApp.keyWindow === self.window()
        }
        try require(controls.value("editor.title") == unchangedTitle, "emoji selection changed title")
        try require(controls.value("editor.note") == unchangedNote, "emoji selection changed note")
        let currentSubtasks = try subtaskIDs.map { try requireValue(controls.value($0), $0) }
        try require(currentSubtasks == unchangedSubtasks, "emoji selection changed subtasks")
        pass("local emoji picker selection")

        try press("editor.emoji.control")
        try await waitForElement("editor.emoji.picker")
        try press("editor.title")
        try await waitFor("emoji picker cancellation") {
            self.controls.entries["editor.emoji.picker"] == nil && NSApp.keyWindow === self.window()
        }
        try require(controls.value("editor.emoji.control") == "😎", "emoji changed on picker cancellation")
        pass("local emoji picker cancellation")
        try press("editor.emoji.preset.2708-fe0f")
        try await waitForValue("editor.emoji.control", equals: "✈️")
        pass("preset emoji replacement")

        try press("editor.emoji.control")
        try await waitForElement("editor.emoji.picker")
        try await dismissAndReopen()
        try require(store.active.isEmpty, "unsaved new event changed data")
        try require(!FileManager.default.fileExists(atPath: configuration.dataURL.path), "unsaved new event wrote JSON")
        try require(controls.entries["editor.emoji.picker"] == nil, "emoji picker survived popup dismissal")
        pass("popup close cancels new draft and emoji picker")

        try press("event.add")
        try await waitForElement("editor.new")
        try await waitForFirstResponder("editor.title")
        try insertText("UI Smoke Event")
        for text in ["First active", "Second active"] {
            let previous = Set(controls.ids(withPrefix: "editor.subtask."))
            try press("editor.subtask.add")
            try await waitFor("saved-event subtask field") {
                Set(self.controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).count == 1
            }
            let id = try requireValue(
                Set(controls.ids(withPrefix: "editor.subtask.")).subtracting(previous).first,
                "saved-event subtask identifier"
            )
            try await waitForFirstResponder(id)
            try insertText(text)
            try await waitForValue(id, equals: text)
        }
        try press("editor.emoji.preset.1f680")
        try await waitForValue("editor.emoji.control", equals: "🚀")
        try press("editor.save")
        try await waitFor("saved event root") {
            self.store.active.count == 1 && self.controls.entries["editor.new"] == nil
        }
        try await waitFor("persisted JSON") { FileManager.default.fileExists(atPath: self.configuration.dataURL.path) }
        let eventID = try requireValue(store.active.first?.id, "saved event ID")
        let originalTitle = try requireValue(store.active.first?.title, "saved event title")
        let originalSubtasks = try requireValue(store.active.first?.subtasks, "saved subtasks")
        try require(originalSubtasks.allSatisfy { !$0.isCompleted }, "new subtasks were not active")
        pass("explicit save persists event and active subtasks")

        try await dismissAndReopen()
        try require(store.active.first?.id == eventID, "saved event did not survive popup session")
        pass("saved data survives popup dismissal")

        let firstSubtaskID = originalSubtasks[0].id
        let secondSubtaskID = originalSubtasks[1].id
        try press("subtask.toggle.\(firstSubtaskID.uuidString)")
        try await waitFor("completion toggle") {
            self.store.active.first?.subtasks.first(where: { $0.id == firstSubtaskID })?.isCompleted == true
                && self.controls.value("subtask.toggle.\(firstSubtaskID.uuidString)") == "completed"
        }
        try await waitFor("completed subtask visual ordering") {
            guard let activeFrame = self.controls.frame("subtask.toggle.\(secondSubtaskID.uuidString)"),
                  let completedFrame = self.controls.frame("subtask.toggle.\(firstSubtaskID.uuidString)") else { return false }
            return activeFrame.midY < completedFrame.midY
        }
        pass("completion toggle moves completed subtask down")

        let disclosureID = "subtasks.disclosure.\(eventID.uuidString)"
        try press(disclosureID)
        try await waitForValue(disclosureID, equals: "collapsed")
        try press(disclosureID)
        try await waitForValue(disclosureID, equals: "expanded")
        pass("checklist collapse and expand")

        try await pressEventAction("edit", eventID: eventID)
        try await waitForElement("editor.edit")
        try require(controls.ids(withPrefix: "subtask.toggle.").isEmpty, "edit event exposed completion checkbox")
        try await focusAndReplace("editor.subtask.\(firstSubtaskID.uuidString)", with: "Completed edited")
        try await focusAndReplace("editor.subtask.\(secondSubtaskID.uuidString)", with: "Active edited")
        try press("editor.save")
        try await waitFor("completion preserved through edit") {
            guard let subtasks = self.store.active.first?.subtasks else { return false }
            return subtasks.first(where: { $0.id == firstSubtaskID })?.isCompleted == true
                && subtasks.first(where: { $0.id == secondSubtaskID })?.isCompleted == false
                && subtasks.first(where: { $0.id == firstSubtaskID })?.text == "Completed edited"
                && subtasks.first(where: { $0.id == secondSubtaskID })?.text == "Active edited"
        }
        pass("completion state preserved through text edit")

        try await pressEventAction("edit", eventID: eventID)
        try await waitForElement("editor.edit")
        try await focusAndReplace("editor.title", with: "Cancelled title")
        try press("editor.cancel")
        try await waitForElement("event.card.\(eventID.uuidString)")
        try await waitForTransientPopoverReady()
        try require(store.active.first?.title == originalTitle, "Cancel changed event")
        pass("edit event Cancel restores transient popover interaction")

        try await pressEventAction("edit", eventID: eventID)
        try await waitForElement("editor.edit")
        try await focusAndReplace("editor.title", with: "Dismissed title")
        try await dismissAndReopen()
        try require(store.active.first?.title == originalTitle, "popup dismissal saved event edit")
        pass("popup close cancels unsaved event edit")

        let originalCount = try requireValue(store.active.first?.subtasks.count, "subtask count")
        try press("event.quick-subtask.add.\(eventID.uuidString)")
        try await waitForElement("quick-subtask.editor")
        try press("quick-subtask.cancel")
        try await waitFor("quick subtask Cancel root") { self.controls.entries["quick-subtask.editor"] == nil }
        try await waitForTransientPopoverReady()
        try require(store.active.first?.subtasks.count == originalCount, "quick subtask Cancel changed data")
        pass("new subtask Cancel restores transient popover interaction")

        try press("event.quick-subtask.add.\(eventID.uuidString)")
        try await waitForElement("quick-subtask.editor")
        try await waitForFirstResponder("quick-subtask.field")
        try await verifyQuickSubtaskFocusGeometry()
        pass("quick subtask focus-ring geometry")
        try insertText("Unsaved quick task")
        try await waitForValue("quick-subtask.field", equals: "Unsaved quick task")
        try await dismissAndReopen()
        try require(store.active.first?.subtasks.count == originalCount, "quick add survived popup dismissal")
        pass("popup close cancels quick subtask add")

        try await pressSubtaskAction("edit", subtaskID: secondSubtaskID)
        try await waitForElement("quick-subtask.editor")
        try press("quick-subtask.cancel")
        try await waitFor("quick subtask edit Cancel root") { self.controls.entries["quick-subtask.editor"] == nil }
        try await waitForTransientPopoverReady()
        try require(
            store.active.first?.subtasks.first(where: { $0.id == secondSubtaskID })?.text == "Active edited",
            "quick subtask edit Cancel changed data"
        )
        pass("edit subtask Cancel restores transient popover interaction")

        try await pressSubtaskAction("edit", subtaskID: secondSubtaskID)
        try await waitForElement("quick-subtask.editor")
        try await focusAndReplace("quick-subtask.field", with: "Unsaved quick edit")
        try await dismissAndReopen()
        let activeText = store.active.first?.subtasks.first(where: { $0.id == secondSubtaskID })?.text
        try require(activeText == "Active edited", "quick edit survived popup dismissal")
        pass("popup close cancels quick subtask edit")

        try await pressEventAction("delete", eventID: eventID)
        try await waitForElement("event.delete.confirm")
        try await dismissAndReopen()
        try require(store.active.first?.id == eventID, "pending deletion removed event")
        pass("popup close cancels pending deletion")

        try await pressEventAction("delete", eventID: eventID)
        try await waitForElement("event.delete.cancel")
        try press("event.delete.cancel")
        try await waitFor("delete cancellation") { self.controls.entries["event.delete.cancel"] == nil }
        try require(store.active.first?.id == eventID, "delete Cancel removed event")
        pass("delete cancellation preserves event")

        try await pressEventAction("delete", eventID: eventID)
        try await waitForElement("event.delete.confirm")
        try press("event.delete.confirm")
        try await waitFor("explicit deletion") { self.store.active.isEmpty && self.controls.entries["event.add"] != nil }
        let persisted = try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: configuration.dataURL))
        try require(persisted.items.isEmpty, "explicit deletion did not reach JSON")
        pass("delete requires and honors explicit confirmation")

        try verifyDiagnosticsPrivacy(forbidden: [
            "Unsaved Smoke Draft", "Unsaved note", "Alpha", "Beta", "Gamma", "Delta", "Epsilon",
            "UI Smoke Event", "First active", "Second active", "Completed edited", "Active edited",
            "Cancelled title", "Dismissed title", "Unsaved quick task", "Unsaved quick edit", "🚀", "😎"
        ])
        pass("diagnostics privacy")
    }

    private func dismissAndReopen() async throws {
        closePopover()
        try await waitFor("popover dismissal") { self.window() == nil }
        openPopover()
        try await waitFor("root after popup reopen") {
            self.window() != nil && self.controls.entries["root.popup"] != nil
                && (self.store.active.isEmpty
                    ? self.controls.entries["event.add"] != nil
                    : self.controls.entries["event.list"] != nil)
                && self.controls.entries["editor.new"] == nil
                && self.controls.entries["editor.edit"] == nil
                && self.controls.entries["quick-subtask.editor"] == nil
                && self.controls.entries["event.delete.confirm"] == nil
        }
    }

    private func waitForTransientPopoverReady() async throws {
        try await waitFor("transient popover teardown") {
            self.isTransientPopoverReady()
        }
    }

    private func pressEventAction(_ action: String, eventID: UUID) async throws {
        let triggerID = "event.actions.\(eventID.uuidString)"
        let actionID = "event.action.\(action).\(eventID.uuidString)"
        try await waitForElement(triggerID)
        try press(triggerID)
        try await waitForElement(actionID)
        try press(actionID)
    }

    private func pressSubtaskAction(_ action: String, subtaskID: UUID) async throws {
        let triggerID = "subtask.actions.\(subtaskID.uuidString)"
        let actionID = "subtask.action.\(action).\(subtaskID.uuidString)"
        try await waitForElement(triggerID)
        try press(triggerID)
        try await waitForElement(actionID)
        try press(actionID)
    }

    private func exerciseResponsiveRoot(eventID: UUID, baselineFootprint: UInt64?) async throws {
        try await scrollRootList()
        let disclosureID = "subtasks.disclosure.\(eventID.uuidString)"
        try await waitForElement(disclosureID)
        try press(disclosureID)
        try await waitForValue(disclosureID, equals: "collapsed")
        try press(disclosureID)
        try await waitForValue(disclosureID, equals: "expanded")
        try requireNoUIStall()
        if let baselineFootprint, let currentFootprint = physicalFootprint() {
            let allowance = UInt64(512 * 1024 * 1024)
            let ceiling = max(baselineFootprint + allowance, baselineFootprint * 5)
            try require(
                currentFootprint <= ceiling,
                "physical footprint grew from \(baselineFootprint) to \(currentFootprint) during root interaction"
            )
        }
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

    private func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    private func focusAndReplace(_ id: String, with text: String) async throws {
        try press(id)
        try focusNativeField(id)
        try await waitForFirstResponder(id)
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else {
            throw Failure("\(id): focused editor is unavailable")
        }
        editor.selectAll(nil)
        editor.insertText(text, replacementRange: editor.selectedRange())
        try await waitForValue(id, equals: text)
    }

    private func focusNativeField(_ id: String) throws {
        guard let targetFrame = controls.frame(id),
              let targetWindow = NSApp.keyWindow ?? window(),
              let contentView = targetWindow.contentView else {
            throw Failure("\(id): native focus geometry is unavailable")
        }
        let textFields = allSubviews(of: contentView).compactMap { $0 as? NSTextField }
        let windowID = ObjectIdentifier(targetWindow)
        if responderToRegistryOffsets[windowID] == nil, textFields.count == 1, let field = textFields.first {
            let frame = field.convert(field.bounds, to: contentView)
            responderToRegistryOffsets[windowID] = CGPoint(
                x: targetFrame.minX - frame.minX,
                y: targetFrame.minY - frame.minY
            )
        }
        guard let offset = responderToRegistryOffsets[windowID] else {
            throw Failure("\(id): native focus offset is unavailable")
        }
        let match = textFields.min { lhs, rhs in
            nativeFieldDistance(lhs, target: targetFrame, offset: offset, contentView: contentView)
                < nativeFieldDistance(rhs, target: targetFrame, offset: offset, contentView: contentView)
        }
        guard let match,
              nativeFieldDistance(match, target: targetFrame, offset: offset, contentView: contentView) < 4,
              targetWindow.makeFirstResponder(match) else {
            throw Failure("\(id): matching native text field is unavailable")
        }
        controls.markFocused(id)
    }

    private func nativeFieldDistance(
        _ field: NSTextField,
        target: CGRect,
        offset: CGPoint,
        contentView: NSView
    ) -> CGFloat {
        let frame = field.convert(field.bounds, to: contentView)
        return abs((frame.minX + offset.x) - target.minX) + abs((frame.minY + offset.y) - target.minY)
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

    private func verifyCurrentFocusGeometry(_ id: String) async throws {
        try await waitFor("visible focus-ring geometry for \(id)") {
            guard let viewport = self.controls.frame("editor.scroll"),
                  let field = self.controls.frame(id) else { return false }
            let inset = EditorLayout.focusRingInset - 0.5
            return field.minX >= viewport.minX + inset
                && field.maxX <= viewport.maxX - inset
                && field.minY >= viewport.minY + inset
                && field.maxY <= viewport.maxY - inset
        }
    }

    private func verifyQuickSubtaskFocusGeometry() async throws {
        try await waitFor("visible quick-subtask focus-ring geometry") {
            guard let editor = self.controls.frame("quick-subtask.editor"),
                  let field = self.controls.frame("quick-subtask.field") else { return false }
            let inset = EditorLayout.focusRingInset - 0.5
            return field.minX >= editor.minX + inset
                && field.maxX <= editor.maxX - inset
                && field.minY >= editor.minY + inset
                && field.maxY <= editor.maxY - inset
        }
    }

    private func verifyDiagnosticsPrivacy(forbidden: [String]) throws {
        DiagnosticLog.shared.flush()
        let log = (try? String(contentsOf: DiagnosticLog.fileURL, encoding: .utf8)) ?? ""
        for value in forbidden {
            try require(!log.contains(value), "diagnostic log contains private fixture text")
        }
    }

    private func press(_ id: String) throws {
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
        let emoji = controls.value("editor.emoji.control") ?? "nil"
        let subtaskFrames = controls.ids(withPrefix: "subtask.toggle.")
            .map { "\($0)=\(String(describing: controls.frame($0)))" }
            .joined(separator: ", ")
        finish(
            "UISmoke\nFAIL after \(passed.count) scenarios: \(error.localizedDescription)\nActual: focus=\(controls.focusedID ?? "nil"), responder=\(responder), delegate=\(delegate), delegateFrame=\(String(describing: delegateFrame)), emoji=\(emoji), \(frames), \(subtaskFrames)",
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
