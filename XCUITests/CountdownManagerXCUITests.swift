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
        if name.contains("testProductionShell") {
            // Keep production window lifecycle enabled. HOME isolation keeps
            // this gate away from the user's Countdown Manager data.
            app.launchEnvironment = [
                "HOME": testHome.path,
                "CFFIXED_USER_HOME": testHome.path
            ]
        } else {
            app.launchArguments = ["--xcui-testing"]
            app.launchEnvironment = ["COUNTDOWN_MANAGER_TEST_HOME": testHome.path]
        }
    }

    func testProductionShellFreshLaunchStatusToggleReopens() {
        app.launch()
        let item = statusItem
        let statusFrame = item.frame

        guard requireProductionShell(
            waitForAbsence(root),
            "fresh production shell did not start hidden"
        ) else { return }

        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        let firstStatusActionCount = statusActionCount()
        guard clickStatusItemExternally(frame: statusFrame, from: finder) else { return }
        guard requireStatusActionDelivery(after: firstStatusActionCount) else { return }
        guard requireProductionShell(
            root.waitForExistence(timeout: 3) && root.isHittable,
            "fresh launch -> external status click at \(statusFrame) did not show the primary window"
        ) else { return }
        XCTAssertNotEqual(app.state, .notRunning, "status show ended the application session")

        // Use the product's explicit keyboard close path. The status-item event
        // remains external for both show operations under test.
        app.typeKey("ц", modifierFlags: .command)
        guard requireProductionShell(
            waitForAbsence(root),
            "Command-W did not observably hide the primary window"
        ) else { return }

        finder.activate()
        let secondStatusActionCount = statusActionCount()
        guard clickStatusItemExternally(frame: statusFrame, from: finder) else { return }
        guard requireStatusActionDelivery(after: secondStatusActionCount) else { return }
        guard requireProductionShell(
            root.waitForExistence(timeout: 3) && root.isHittable,
            "external status click at \(statusFrame) did not observably reopen the primary window"
        ) else { return }
        XCTAssertNotEqual(app.state, .notRunning, "status reopen ended the application session")
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
            items.append(["id": UUID().uuidString, "title": "Scroll fixture \(number)",
                          "date": ["year": 2099, "month": 12, "day": 31], "emoji": "📅", "subtasks": []])
        }
        try writeItems(items)
        app.launch()
        let list = app.scrollViews["event.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        list.swipeUp()
        list.swipeUp()
        let visible = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "event.edit."))
            .allElementsBoundByIndex.first { $0.isHittable && list.frame.contains($0.frame) }
        let anchor = try XCTUnwrap(visible, "No fully visible scrolled row")
        XCTAssertNotEqual(anchor.identifier, "event.edit.\(eventID)")
        let frame = anchor.frame
        anchor.click()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["event.add"].isHittable)
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(list.waitForExistence(timeout: 3))
        XCTAssertEqual(anchor.frame.minY, frame.minY, accuracy: 1)
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

    private var statusItem: XCUIElement {
        let item = app.statusItems["Countdown Manager"]
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        return item
    }

    private var root: XCUIElement {
        app.descendants(matching: .any)["root.window"]
    }

    private func clickStatusItemExternally(frame: CGRect, from finder: XCUIApplication) -> Bool {
        let anchor = finder.menuBars.firstMatch
        guard anchor.waitForExistence(timeout: 3) else {
            XCTFail("PRODUCTION SHELL DRIVER: Finder menu bar was not available")
            return false
        }
        let anchorFrame = anchor.frame
        guard anchorFrame.width > 0, anchorFrame.height > 0 else {
            XCTFail("PRODUCTION SHELL DRIVER: Finder menu bar has invalid frame \(anchorFrame)")
            return false
        }
        let offset = CGVector(
            dx: (frame.midX - anchorFrame.minX) / anchorFrame.width,
            dy: (frame.midY - anchorFrame.minY) / anchorFrame.height
        )
        anchor.coordinate(withNormalizedOffset: offset).click()
        return true
    }

    private func requireStatusActionDelivery(after previousCount: Int) -> Bool {
        let delivered = XCTNSPredicateExpectation(
            predicate: NSPredicate { [weak self] _, _ in
                (self?.statusActionCount() ?? 0) > previousCount
            },
            object: nil
        )
        guard XCTWaiter.wait(for: [delivered], timeout: 1) == .completed else {
            XCTFail(
                "PRODUCTION SHELL DRIVER: external XCU coordinate click did not deliver the status action. "
                    + "Lifecycle: \(productionShellLifecycleTrace())"
            )
            return false
        }
        return true
    }

    private func statusActionCount() -> Int {
        productionShellLifecycleTrace().components(separatedBy: "status-action").count - 1
    }

    private func requireProductionShell(_ condition: @autoclosure () -> Bool, _ failure: String) -> Bool {
        guard condition() else {
            Thread.sleep(forTimeInterval: 0.25)
            XCTFail("PRODUCTION SHELL STOP: \(failure). Lifecycle: \(productionShellLifecycleTrace())")
            return false
        }
        return true
    }

    private func productionShellLifecycleTrace() -> String {
        let candidates = [
            testHome.appendingPathComponent("Library/Application Support/CountdownManager/Logs/countdown.log"),
            testHome.appendingPathComponent("Application Support/CountdownManager/Logs/countdown.log")
        ]
        guard let logURL = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let contents = try? String(contentsOf: logURL, encoding: .utf8) else {
            return "log unavailable; checked \(candidates.map(\.path).joined(separator: ", "))"
        }
        let events = contents.split(separator: "\n").filter { $0.contains("shell.lifecycle") }
        return events.isEmpty ? "no shell lifecycle events" : events.joined(separator: " | ")
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
