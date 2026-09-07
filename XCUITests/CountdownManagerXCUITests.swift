import XCTest

final class CountdownManagerXCUITests: XCTestCase {
    private let eventID = "11111111-1111-1111-1111-111111111111"
    private let activeSubtaskID = "22222222-2222-2222-2222-222222222222"
    private let completedSubtaskID = "33333333-3333-3333-3333-333333333333"
    private var app: XCUIApplication!
    private var testHome: URL!
    private var defaultsSuiteName: String!

    override func setUpWithError() throws {
        continueAfterFailure = false
        testHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("countdown-xcui-\(UUID().uuidString)", isDirectory: true)
        defaultsSuiteName = [
            "local.countdownmanager.ui-smoke",
            testHome.deletingLastPathComponent().lastPathComponent,
            testHome.lastPathComponent
        ].joined(separator: ".")
        UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        try FileManager.default.createDirectory(at: testHome, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: testHome.appendingPathComponent(".countdown-xcui-test-environment").path,
            contents: Data()
        )
        try writeFixture()

        app = XCUIApplication()
        app.launchArguments = ["--xcui-testing"]
        app.launchEnvironment = ["COUNTDOWN_MANAGER_TEST_HOME": testHome.path]
    }

    override func tearDownWithError() throws {
        app?.terminate()
        if let defaultsSuiteName {
            UserDefaults().removePersistentDomain(forName: defaultsSuiteName)
        }
        if let testHome {
            try? FileManager.default.removeItem(at: testHome)
        }
        app = nil
        testHome = nil
        defaultsSuiteName = nil
    }

    func testLaunchOpensRootAndNewEventCanBeCancelled() {
        app.launch()

        let root = app.descendants(matching: .any)["root.popup"]
        XCTAssertTrue(root.waitForExistence(timeout: 5), "The menu-bar popup did not expose its root accessibility element")

        let addEvent = app.buttons["event.add"].firstMatch
        XCTAssertTrue(addEvent.waitForExistence(timeout: 2))
        addEvent.click()

        let cancel = app.buttons["editor.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()

        XCTAssertTrue(root.waitForExistence(timeout: 2))
        XCTAssertFalse(cancel.exists)
    }

    func testSaveEventUsesRealControls() {
        app.launch()

        openEventAction("event.action.edit.\(eventID)")
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 2))
        title.click()
        title.typeKey(.delete, modifierFlags: .command)
        title.typeText("Сохранено тестом")
        title.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(title.value as? String, "Сохранено тестом")
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.isEnabled)
        save.click()

        XCTAssertTrue(app.buttons["event.actions.\(eventID)"].waitForExistence(timeout: 3))
        openEventAction("event.action.edit.\(eventID)")
        XCTAssertEqual(app.textFields["editor.title"].value as? String, "Сохранено тестом")
    }

    func testEditEventCanBeCancelled() {
        app.launch()

        openEventAction("event.action.edit.\(eventID)")
        let cancel = app.buttons["editor.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()
        XCTAssertTrue(app.staticTexts["XCUITest Event"].waitForExistence(timeout: 2))
    }

    func testQuickSubtaskCancelAndSave() {
        app.launch()

        openEventAction("event.action.add-subtask.\(eventID)")
        let quickField = app.textFields["quick-subtask.field"]
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        quickField.typeText("Черновик")
        app.buttons["quick-subtask.cancel"].click()
        XCTAssertTrue(app.buttons["event.actions.\(eventID)"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["Черновик"].exists)

        openEventAction("event.action.add-subtask.\(eventID)")
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        quickField.typeText("Добавлено тестом")
        quickField.typeKey(.tab, modifierFlags: [])
        XCTAssertEqual(quickField.value as? String, "Добавлено тестом")
        let quickSave = app.buttons["quick-subtask.save"]
        XCTAssertTrue(quickSave.isEnabled)
        quickSave.click()
        XCTAssertFalse(quickField.waitForExistence(timeout: 2))

        openEventAction("event.action.edit.\(eventID)")
        let savedSubtask = app.textFields.matching(
            NSPredicate(format: "value == %@", "Добавлено тестом")
        ).firstMatch
        XCTAssertTrue(savedSubtask.waitForExistence(timeout: 2))
    }

    func testCollapseExpandAndEditSubtaskCancelAndSave() {
        app.launch()

        let disclosure = app.buttons["subtasks.disclosure.\(eventID)"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel(disclosure, containing: "свернуть"))
        let eventList = app.scrollViews["event.list"]
        XCTAssertTrue(eventList.waitForExistence(timeout: 2))
        eventList.swipeUp()
        let expandedAdd = app.buttons["event.quick-subtask.add.\(eventID)"]
        XCTAssertTrue(expandedAdd.waitForExistence(timeout: 2))

        let activeActions = app.buttons.matching(
            NSPredicate(format: "label == %@", "Действия подзадачи")
        ).firstMatch
        XCTAssertTrue(activeActions.waitForExistence(timeout: 2))
        activeActions.click()
        let editAction = app.buttons["subtask.action.edit.\(activeSubtaskID)"]
        XCTAssertTrue(editAction.waitForExistence(timeout: 2))
        editAction.click()
        let quickField = app.textFields["quick-subtask.field"]
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        app.buttons["quick-subtask.cancel"].click()

        XCTAssertTrue(activeActions.waitForExistence(timeout: 2))
        activeActions.click()
        XCTAssertTrue(editAction.waitForExistence(timeout: 2))
        editAction.click()
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        quickField.click()
        quickField.typeKey(.delete, modifierFlags: .command)
        quickField.typeText("Изменено тестом")
        quickField.typeKey(.tab, modifierFlags: [])
        app.buttons["quick-subtask.save"].click()

        disclosure.press(forDuration: 0.1)
        XCTAssertTrue(waitForLabel(disclosure, containing: "раскрыть"))
        XCTAssertFalse(expandedAdd.waitForExistence(timeout: 1))
        disclosure.press(forDuration: 0.1)
        XCTAssertTrue(waitForLabel(disclosure, containing: "свернуть"))
        XCTAssertTrue(expandedAdd.waitForExistence(timeout: 2))

        eventList.swipeDown()
        openEventAction("event.action.edit.\(eventID)")
        let editedSubtask = app.textFields.matching(
            NSPredicate(format: "value == %@", "Изменено тестом")
        ).firstMatch
        XCTAssertTrue(editedSubtask.waitForExistence(timeout: 2))
    }

    func testDeleteConfirmationCancelAndConfirm() {
        app.launch()

        openEventAction("event.action.delete.\(eventID)")
        let cancel = app.buttons["event.delete.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 2))
        cancel.click()
        XCTAssertTrue(app.staticTexts["XCUITest Event"].waitForExistence(timeout: 2))

        openEventAction("event.action.delete.\(eventID)")
        let confirm = app.buttons["event.delete.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.click()
        XCTAssertFalse(app.staticTexts["XCUITest Event"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["event.add"].firstMatch.exists)
    }

    func testStatusItemCanClosePopupFromEventEditor() {
        app.launch()

        app.buttons["event.add"].firstMatch.click()
        XCTAssertTrue(app.buttons["editor.cancel"].waitForExistence(timeout: 2))

        let statusItem = app.statusItems["Countdown Manager"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 2))
        statusItem.click()
        XCTAssertTrue(waitForAbsence(app.descendants(matching: .any)["root.popup"]))
    }

    func testStatusItemClosesNewSubtaskSheetAndReopensCleanRoot() {
        app.launch()

        openEventAction("event.action.add-subtask.\(eventID)")
        let quickField = app.textFields["quick-subtask.field"]
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        quickField.typeText("Несохранённый черновик")

        closeAndReopenWithStatusItem()

        XCTAssertFalse(quickField.exists)
        openEventAction("event.action.edit.\(eventID)")
        let unsavedDraft = app.textFields.matching(
            NSPredicate(format: "value == %@", "Несохранённый черновик")
        ).firstMatch
        XCTAssertFalse(unsavedDraft.exists)
    }

    func testStatusItemClosesEditSubtaskSheetAndReopensCleanRoot() {
        app.launch()

        let eventList = app.scrollViews["event.list"]
        XCTAssertTrue(eventList.waitForExistence(timeout: 2))
        eventList.swipeUp()
        let activeActions = app.buttons.matching(
            NSPredicate(format: "label == %@", "Действия подзадачи")
        ).firstMatch
        XCTAssertTrue(activeActions.waitForExistence(timeout: 2))
        activeActions.click()
        let editAction = app.buttons["subtask.action.edit.\(activeSubtaskID)"]
        XCTAssertTrue(editAction.waitForExistence(timeout: 2))
        editAction.click()
        let quickField = app.textFields["quick-subtask.field"]
        XCTAssertTrue(quickField.waitForExistence(timeout: 2))
        quickField.click()
        quickField.typeKey(.delete, modifierFlags: .command)
        quickField.typeText("Несохранённое изменение")

        closeAndReopenWithStatusItem()

        XCTAssertFalse(quickField.exists)
        openEventAction("event.action.edit.\(eventID)")
        let originalSubtask = app.textFields.matching(
            NSPredicate(format: "value == %@", "Active fixture subtask")
        ).firstMatch
        XCTAssertTrue(originalSubtask.waitForExistence(timeout: 2))
        let unsavedDraft = app.textFields.matching(
            NSPredicate(format: "value == %@", "Несохранённое изменение")
        ).firstMatch
        XCTAssertFalse(unsavedDraft.exists)
    }

    private func openEventAction(_ actionIdentifier: String) {
        let actions = app.buttons["event.actions.\(eventID)"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        actions.click()
        XCTAssertTrue(app.buttons[actionIdentifier].waitForExistence(timeout: 2))
        app.buttons[actionIdentifier].click()
    }

    private func closeAndReopenWithStatusItem() {
        let root = app.descendants(matching: .any)["root.popup"]
        let statusItem = app.statusItems["Countdown Manager"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 2))
        statusItem.click()
        XCTAssertTrue(waitForAbsence(root), "Status-item click did not close the popup")
        statusItem.click()
        XCTAssertTrue(root.waitForExistence(timeout: 3), "The next status-item click did not open a clean root")
        XCTAssertFalse(app.textFields["quick-subtask.field"].exists)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 2) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func writeFixture() throws {
        let support = testHome.appendingPathComponent("Application Support/CountdownManager", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let fixture: [String: Any] = [
            "primaryID": eventID,
            "items": [[
                "id": eventID,
                "title": "XCUITest Event",
                "note": "Isolated fixture",
                "date": ["year": 2099, "month": 12, "day": 31],
                "emoji": "🎉",
                "subtasks": [
                    ["id": activeSubtaskID, "text": "Active fixture subtask", "isCompleted": false],
                    ["id": completedSubtaskID, "text": "Completed fixture subtask", "isCompleted": true]
                ]
            ]]
        ]
        let data = try JSONSerialization.data(withJSONObject: fixture, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: support.appendingPathComponent("countdowns.json"), options: .atomic)
    }
}
