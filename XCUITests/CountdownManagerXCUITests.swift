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

    func testNewEventCancelDoesNotLeakDraft() throws {
        app.launch()
        let add = app.buttons["event.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.typeText("Новый черновик")
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "")
        XCTAssertEqual(try persistedItems().count, 1)
    }

    func testUtilityChromeAndKeyboardClose() {
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        replace(title, with: "Сохранённый черновик")
        XCTAssertTrue(root.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons[XCUIIdentifierCloseWindow].exists)
        // XCUITest resolves character keys through the selected input source.
        // The Russian fixture uses the physical W key's character in that layout.
        app.typeKey("ц", modifierFlags: .command)
        XCTAssertTrue(waitForAbsence(root))
    }

    func testLongListPositionSurvivesEditorCancel() throws {
        var items = try persistedItems()
        for number in 1...35 {
            items.append(["id": scrollFixtureID(number), "title": "Scroll fixture \(number)",
                          "date": ["year": 2099, "month": 12, "day": 31], "emoji": "📅", "subtasks": []])
        }
        try writeItems(items)
        app.launch()
        let list = app.scrollViews["event.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        let anchor = app.buttons["event.edit.\(scrollFixtureID(35))"]
        for _ in 0..<12 where !anchor.isHittable {
            list.swipeUp()
        }
        XCTAssertTrue(anchor.isHittable, "Known scroll fixture did not become hittable")
        let frame = anchor.frame
        anchor.click()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["event.add"].isHittable)
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(anchor.frame.minY, frame.minY, accuracy: 1)
    }

    private func scrollFixtureID(_ number: Int) -> String {
        String(format: "90000000-0000-0000-0000-%012d", number)
    }

    func testSubtaskEditCancelSaveAndCompletion() throws {
        app.launch()
        let disclosure = app.buttons["subtasks.disclosure.\(eventID)"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        disclosure.click()
        XCTAssertTrue(waitForLabel(disclosure, containing: "раскрыть"))
        disclosure.click()
        XCTAssertTrue(waitForLabel(disclosure, containing: "свернуть"))
        let toggle = app.checkBoxes["subtask.toggle.\(activeSubtaskID)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.click()
        openEditor()
        let field = app.textFields["editor.subtask.\(activeSubtaskID)"]
        let scroll = app.scrollViews["editor.scroll"]
        scroll.swipeUp()
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        replace(field, with: "Отменённая подзадача")
        app.buttons["editor.cancel"].click()
        openEditor()
        scroll.swipeUp()
        XCTAssertEqual(field.value as? String, "Active fixture subtask")
        replace(field, with: "Сохранённая подзадача")
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let tasks = try XCTUnwrap(try persistedItems().first?["subtasks"] as? [[String: Any]])
        let task = try XCTUnwrap(tasks.first { $0["id"] as? String == activeSubtaskID })
        XCTAssertEqual(task["text"] as? String, "Сохранённая подзадача")
        XCTAssertEqual(task["isCompleted"] as? Bool, true)
    }

    func testDeleteConfirmationCancelAndConfirm() throws {
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        replace(title, with: "Черновик перед удалением")
        app.buttons["event.delete"].click()
        XCTAssertTrue(app.buttons["event.delete.cancel"].waitForExistence(timeout: 2))
        app.buttons["event.delete.cancel"].click()
        XCTAssertEqual(title.value as? String, "Черновик перед удалением")
        app.buttons["event.delete"].click()
        app.buttons["event.delete.confirm"].click()
        XCTAssertTrue(app.buttons["event.add"].waitForExistence(timeout: 3))
        XCTAssertFalse(title.exists)
        XCTAssertTrue(try persistedItems().isEmpty)
    }

    private var root: XCUIElement {
        app.descendants(matching: .any)["root.window"]
    }

    private func openEditor() {
        let edit = app.buttons["event.edit.\(eventID)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        edit.click()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 3))
    }

    private func replace(_ field: XCUIElement, with value: String) {
        field.click()
        field.typeKey(.rightArrow, modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: .command)
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)], timeout: 3) == .completed
    }

    private func waitForAbsence(_ element: XCUIElement) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)], timeout: 3) == .completed
    }

    private var dataURL: URL {
        testHome.appendingPathComponent("Application Support/CountdownManager/countdowns.json")
    }

    private func persistedItems() throws -> [[String: Any]] {
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: dataURL)) as? [String: Any])
        return try XCTUnwrap(json["items"] as? [[String: Any]])
    }

    private func writeItems(_ items: [[String: Any]]) throws {
        try JSONSerialization.data(withJSONObject: ["primaryID": eventID, "items": items])
            .write(to: dataURL, options: .atomic)
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
