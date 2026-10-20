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

    func testNewNoteHardLimitAndNativeFocus() throws {
        app.launch()
        let add = app.buttons["event.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replace(title, with: "New limit")
        let note = app.textViews["editor.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        note.typeText(String(repeating: "a", count: 149))
        XCTAssertEqual((note.value as? String)?.count, 149)
        note.typeText("b")
        XCTAssertEqual((note.value as? String)?.count, 150)
        note.typeText("c")
        XCTAssertEqual(note.value as? String, String(repeating: "a", count: 149) + "b")
        title.click()
        title.typeText(" title")
        XCTAssertEqual(title.value as? String, "New limit title")
        note.click()
        note.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual((note.value as? String)?.count, 149)
        note.typeKey("z", modifierFlags: .command)
        XCTAssertEqual((note.value as? String)?.count, 150)
        app.buttons["editor.cancel"].click()
        XCTAssertEqual(try persistedItems().count, 1)
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

    func testAccessibilityDescribesPrimaryAndCurrentEmoji() throws {
        app.launch()
        let primary = app.buttons["event.primary.\(eventID)"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        XCTAssertEqual(primary.label, "Снять основное событие: XCUITest Event")
        XCTAssertEqual(primary.value as? String, "Выбрано")

        openEditor()
        let currentEmoji = app.buttons["editor.emoji.toggle"]
        let toggleButtonExists = currentEmoji.waitForExistence(timeout: 3)
        if !toggleButtonExists {
            print("Missing emoji toggle Button. Full accessibility hierarchy:\n\(app.debugDescription)")
            let anyToggle = app.descendants(matching: .any).matching(identifier: "editor.emoji.toggle").firstMatch
            if anyToggle.exists {
                print("Emoji toggle exact identifier: role=\(anyToggle.elementType), label=\(anyToggle.label), "
                      + "value=\(String(describing: anyToggle.value)), frame=\(anyToggle.frame), "
                      + "hittable=\(anyToggle.isHittable)")
            } else {
                print("Emoji toggle exact identifier is absent from all accessibility roles.")
            }
        }
        XCTAssertTrue(toggleButtonExists)
        XCTAssertEqual(currentEmoji.label, "Изменить значок: 🎉")

        openEmojiPresets()
        let selectedPreset = app.buttons["editor.emoji.preset.1f389"]
        XCTAssertTrue(selectedPreset.waitForExistence(timeout: 3))
        XCTAssertEqual(selectedPreset.label, "Emoji: 🎉")
        XCTAssertEqual(selectedPreset.value as? String, "Выбрано")

        app.buttons["editor.emoji.more"].click()
        app.scrollViews["editor.scroll"].swipeUp()
        let secondPageDot = app.buttons["editor.emoji.page.dot.2"]
        XCTAssertTrue(secondPageDot.waitForExistence(timeout: 3))
        XCTAssertTrue(secondPageDot.isHittable)
        let secondPageOption = app.buttons["editor.emoji.option.page.2.row.1.column.1.1f476"]
        let inactivePageOptionIsAbsent = waitForAbsence(secondPageOption)
        if !inactivePageOptionIsAbsent {
            print("Inactive emoji page remains accessible before selecting page 2:\n\(app.debugDescription)")
            let category = app.descendants(matching: .any).matching(identifier: "editor.emoji.category").firstMatch
            if category.exists {
                print("Emoji category: role=\(category.elementType), label=\(category.label), "
                      + "value=\(String(describing: category.value)), frame=\(category.frame)")
            } else {
                print("Emoji category identifier is absent from all accessibility roles.")
            }
            print("Page 2 selector: label=\(secondPageDot.label), value=\(String(describing: secondPageDot.value))")
            let offPage = app.descendants(matching: .any)
                .matching(identifier: "editor.emoji.option.page.2.row.1.column.1.1f476").firstMatch
            if offPage.exists {
                print("Page 2 option: role=\(offPage.elementType), label=\(offPage.label), "
                      + "value=\(String(describing: offPage.value)), frame=\(offPage.frame), "
                      + "hittable=\(offPage.isHittable), enabled=\(offPage.isEnabled)")
            }
        }
        XCTAssertTrue(inactivePageOptionIsAbsent)
        secondPageDot.click()
        XCTAssertTrue(secondPageOption.waitForExistence(timeout: 3))
        secondPageOption.click()
        XCTAssertTrue(waitForAbsence(secondPageOption))
        XCTAssertTrue(waitForAbsence(selectedPreset))
        XCTAssertTrue(waitForAbsence(app.buttons["editor.emoji.more"]))
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

    func testFirstEventWithoutIconOrFavoriteRemainsNearestAfterRelaunch() throws {
        try writeItems([], primaryID: nil)
        app.launch()
        let add = app.buttons["event.empty.tomorrow"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        replace(title, with: "Без значка и звезды")
        app.scrollViews["editor.scroll"].swipeUp()
        let noIcon = app.buttons["editor.emoji.none"]
        XCTAssertFalse(noIcon.exists)
        XCTAssertFalse(app.buttons["editor.emoji.preset.1f389"].exists)
        XCTAssertTrue(app.buttons["editor.emoji.toggle"].exists)
        XCTAssertTrue(app.checkBoxes["editor.primary"].isEnabled)
        app.buttons["editor.save"].click()
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        let item = try XCTUnwrap(try persistedItems().first)
        let savedID = try XCTUnwrap(item["id"] as? String)
        XCTAssertEqual(item["emoji"] as? String, "")
        XCTAssertTrue(waitForFavorite(nil))
        let star = app.buttons["event.primary.\(savedID)"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Не выбрано")
        let heading = app.staticTexts["event.featured.label.\(savedID)"]
        assertNearestHeading(heading)
        app.terminate()
        app.launch()
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Не выбрано")
        assertNearestHeading(heading)
        XCTAssertTrue(waitForFavorite(nil))
    }

    func testOptionalIconClearCancelAndSavePreserveStoredChoice() throws {
        app.launch()
        openEditor()
        let scroll = app.scrollViews["editor.scroll"]
        scroll.swipeUp()
        app.buttons["editor.emoji.none"].click()
        XCTAssertEqual(app.buttons["editor.emoji.toggle"].label, "Выбрать значок")
        XCTAssertTrue(waitForAbsence(app.buttons["editor.emoji.none"]))
        openEmojiPresets()
        app.buttons["editor.emoji.preset.1f680"].click()
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try persistedItems().first?["emoji"] as? String, "🎉")
        openEditor()
        scroll.swipeUp()
        XCTAssertEqual(app.buttons["editor.emoji.toggle"].label, "Изменить значок: 🎉")
        app.buttons["editor.emoji.none"].click()
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try persistedItems().first?["emoji"] as? String, "")
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor()
        scroll.swipeUp()
        openEmojiPresets()
        app.buttons["editor.emoji.preset.1f680"].click()
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try persistedItems().first?["emoji"] as? String, "🚀")
    }

    func testFavoriteCanBeClearedFromListAndEditor() throws {
        app.launch()
        let star = app.buttons["event.primary.\(eventID)"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        star.click()
        XCTAssertTrue(waitForValue(star, equals: "Не выбрано"))
        XCTAssertTrue(waitForFavorite(nil))
        let heading = app.staticTexts["event.featured.label.\(eventID)"]
        assertNearestHeading(heading)
        star.click()
        XCTAssertTrue(waitForValue(star, equals: "Выбрано"))
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor()
        app.scrollViews["editor.scroll"].swipeUp()
        let editorPrimary = app.checkBoxes["editor.primary"]
        XCTAssertTrue(editorPrimary.waitForExistence(timeout: 3))
        XCTAssertTrue(editorPrimary.isEnabled)
        editorPrimary.click()
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Выбрано")
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor()
        app.scrollViews["editor.scroll"].swipeUp()
        editorPrimary.click()
        app.buttons["editor.save"].click()
        XCTAssertTrue(waitForValue(star, equals: "Не выбрано"))
        XCTAssertTrue(waitForFavorite(nil))
        assertNearestHeading(heading)
        app.terminate()
        app.launch()
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Не выбрано")
        XCTAssertTrue(waitForFavorite(nil))
    }

    func testEmojiDisclosurePreservesDraftAndHidesInactiveControls() throws {
        let originalJSON = try Data(contentsOf: dataURL)
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        let note = app.textViews["editor.note"]
        replace(title, with: "Черновик со значком")
        replace(note, with: "Заметка остаётся")
        let task = app.textFields["editor.subtask.\(activeSubtaskID)"]
        revealInEditor(task)
        replace(task, with: "Подзадача остаётся")
        let primary = app.checkBoxes["editor.primary"]
        revealInEditor(primary)
        primary.click()
        let favoriteValue = primary.value as? String

        let preset = app.buttons["editor.emoji.preset.1f680"]
        let more = app.buttons["editor.emoji.more"]
        XCTAssertFalse(preset.exists)
        XCTAssertFalse(more.exists)
        openEmojiPresets()
        XCTAssertTrue(more.waitForExistence(timeout: 3))
        more.click()
        let option = app.buttons["editor.emoji.option.page.2.row.1.column.1.1f476"]
        XCTAssertTrue(waitForAbsence(option), "Inactive catalogue pages must stay outside accessibility")
        let secondPage = app.buttons["editor.emoji.page.dot.2"]
        revealInEditor(secondPage)
        secondPage.click()
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        revealInEditor(option)
        option.click()
        XCTAssertTrue(waitForAbsence(option))
        XCTAssertTrue(waitForAbsence(preset))
        XCTAssertTrue(waitForAbsence(more))
        let clear = app.buttons["editor.emoji.none"]
        revealInEditor(clear)
        clear.click()
        XCTAssertTrue(waitForAbsence(app.buttons["editor.emoji.none"]))
        XCTAssertEqual(app.buttons["editor.emoji.toggle"].label, "Выбрать значок")
        XCTAssertEqual(title.value as? String, "Черновик со значком")
        XCTAssertEqual(note.value as? String, "Заметка остаётся")
        XCTAssertEqual(task.value as? String, "Подзадача остаётся")
        XCTAssertEqual(primary.value as? String, favoriteValue)
        XCTAssertEqual(try Data(contentsOf: dataURL), originalJSON)
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalJSON)
    }

    func testLongListPositionSurvivesEditorCancel() throws {
        var items = try persistedItems()
        // A Debug-config XCU launch materializes the whole non-lazy list in the
        // accessibility tree; a long-but-modest fixture keeps that affordable.
        let lastScrollFixture = 18
        for number in 1...lastScrollFixture {
            items.append(["id": scrollFixtureID(number), "title": "Scroll fixture \(number)",
                          "date": ["year": 2099, "month": 12, "day": 31], "emoji": "📅", "subtasks": []])
        }
        try writeItems(items, primaryID: eventID)
        app.launch()
        let list = app.scrollViews["event.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 15))
        let anchor = app.buttons["event.edit.\(scrollFixtureID(lastScrollFixture))"]
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

    func testWholeSubtaskRowHitAreasAndDisclosureIsolation() throws {
        app.launch()
        let toggle = app.checkBoxes["subtask.toggle.\(activeSubtaskID)"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        var completed = false
        for x in [0.02, 0.25, 0.95, 0.95, 0.25, 0.02] {
            XCTAssertGreaterThan(toggle.frame.width, 260, "Checkbox accessibility/hit area must include the full row")
            toggle.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).click()
            completed.toggle()
            XCTAssertTrue(waitForSubtaskCompletion(activeSubtaskID, equals: completed),
                          "Row click at \(x) did not persist exactly one completion change")
            let tasks = try XCTUnwrap(try persistedItems().first?["subtasks"] as? [[String: Any]])
            XCTAssertEqual(tasks.first { $0["id"] as? String == completedSubtaskID }?["isCompleted"] as? Bool, true)
        }
        let beforeDisclosure = try Data(contentsOf: dataURL)
        let disclosure = app.buttons["subtasks.disclosure.\(eventID)"]
        disclosure.click()
        XCTAssertTrue(waitForLabel(disclosure, containing: "раскрыть"))
        XCTAssertFalse(toggle.isHittable)
        XCTAssertEqual(try Data(contentsOf: dataURL), beforeDisclosure)
        disclosure.click()
        XCTAssertTrue(waitForLabel(disclosure, containing: "свернуть"))
        XCTAssertEqual(try Data(contentsOf: dataURL), beforeDisclosure)
    }

    private func waitForSubtaskCompletion(_ id: String, equals completed: Bool) -> Bool {
        let condition = NSPredicate { _, _ in
            guard let tasks = try? self.persistedItems().first?["subtasks"] as? [[String: Any]] else { return false }
            return tasks.first { $0["id"] as? String == id }?["isCompleted"] as? Bool == completed
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: condition, object: nil)], timeout: 3) == .completed
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

    func testAddedSubtaskDeletePreservesNeighborTextOnSave() throws {
        app.launch()
        openEditor()
        let active = app.textFields["editor.subtask.\(activeSubtaskID)"]
        revealInEditor(active, fullyInViewport: true)
        replace(active, with: "Сохранённая исходная строка")
        let temporaryID = try addEditorSubtask()
        let retainedID = try addEditorSubtask()
        let retained = app.textFields[retainedID]
        revealInEditor(retained, fullyInViewport: true)
        replace(retained, with: "Новая строка остаётся")
        XCTAssertFalse(app.buttons["editor.save"].isEnabled, "An empty temporary subtask must keep Save unavailable")
        let temporary = app.textFields[temporaryID]
        let suffix = temporaryID.dropFirst("editor.subtask.".count)
        let delete = app.buttons["editor.subtask.delete.\(suffix)"]
        revealInEditor(delete, fullyInViewport: true)
        delete.click()
        XCTAssertTrue(waitForAbsence(temporary), "A deleted row must leave the interactive accessibility tree")
        XCTAssertEqual(retained.value as? String, "Новая строка остаётся")
        XCTAssertEqual(active.value as? String, "Сохранённая исходная строка")
        XCTAssertTrue(app.buttons["editor.save"].isEnabled)
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let item = try XCTUnwrap(try persistedItems().first)
        let tasks = try XCTUnwrap(item["subtasks"] as? [[String: Any]])
        let retainedUUID = String(retainedID.dropFirst("editor.subtask.".count))
        XCTAssertEqual(tasks.compactMap { $0["id"] as? String }, [activeSubtaskID, completedSubtaskID, retainedUUID])
        XCTAssertEqual(tasks[0]["text"] as? String, "Сохранённая исходная строка")
        XCTAssertEqual(tasks[0]["isCompleted"] as? Bool, false)
        XCTAssertEqual(tasks[1]["text"] as? String, "Completed fixture subtask")
        XCTAssertEqual(tasks[1]["isCompleted"] as? Bool, true)
        XCTAssertEqual(tasks[2]["text"] as? String, "Новая строка остаётся")
        XCTAssertEqual(tasks[2]["isCompleted"] as? Bool, false)
        XCTAssertEqual(item["note"] as? String, "Isolated fixture")
        XCTAssertTrue(waitForFavorite(eventID))
    }

    private func addEditorSubtask() throws -> String {
        let prefix = "editor.subtask."
        let query = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        let previous = Set(query.allElementsBoundByIndex.map(\.identifier))
        let add = app.buttons["editor.subtask.add"]
        revealInEditor(add, fullyInViewport: true)
        add.click()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            Set(query.allElementsBoundByIndex.map(\.identifier)).subtracting(previous).count == 1
        }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 3)
        if result != .completed {
            print("Subtask Add failed to expose exactly one new text field. Initial IDs=\(previous.sorted())")
            let fresh = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
            print("Fresh text field IDs=\(fresh.allElementsBoundByIndex.map(\.identifier))")
            for (name, element) in [("Add", add), ("Scroll", app.scrollViews["editor.scroll"]),
                                    ("Save", app.buttons["editor.save"])] {
                if element.exists {
                    print("\(name): frame=\(element.frame), hittable=\(element.isHittable), enabled=\(element.isEnabled)")
                } else {
                    print("\(name): absent")
                }
            }
            print("Subtask Add accessibility hierarchy:\n\(String(app.debugDescription.prefix(20_000)))")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Subtask Add failure"
            screenshot.lifetime = .keepAlways
            self.add(screenshot)
        }
        XCTAssertEqual(result, .completed)
        return try XCTUnwrap(Set(query.allElementsBoundByIndex.map(\.identifier)).subtracting(previous).first)
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
        XCTAssertTrue(app.buttons["event.empty.today"].waitForExistence(timeout: 3))
        XCTAssertFalse(title.exists)
        XCTAssertTrue(try persistedItems().isEmpty)
    }

    func testSettingsDiagnosticArchiveCancelAndSave() throws {
        let originalEvents = try Data(contentsOf: dataURL)
        let destination = testHome.appendingPathComponent("Countdown-Diagnostics.zip")
        app.launch()
        let settings = app.buttons["settings.open"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
        settings.click()
        let export = app.buttons["settings.diagnostics"]
        XCTAssertTrue(export.waitForExistence(timeout: 3))
        export.click()
        let panel = app.sheets.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "The native save sheet must be accessible")
        let cancel = panel.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Отменить", "Отмена"] as NSArray)).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.click()
        XCTAssertTrue(waitForAbsence(panel))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)
        let exportEnabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in export.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exportEnabled], timeout: 3), .completed)

        export.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        let filename = panel.textFields.matching(NSPredicate(format: "value == %@", "Countdown-Diagnostics.zip")).firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 3))
        filename.click()
        // Slash invokes the standard Go to Folder sheet without a keyboard-layout-specific letter shortcut.
        filename.typeText("/")
        let folder = app.sheets.comboBoxes.firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 3), "The native Go to Folder field must be accessible")
        replace(folder, with: testHome.path)
        folder.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(folder))
        let save = panel.buttons.matching(NSPredicate(format: "label IN %@", ["Save", "Сохранить"] as NSArray)).firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isEnabled)
        save.click()
        XCTAssertTrue(waitForAbsence(panel))
        let archiveWritten = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: destination.path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [archiveWritten], timeout: 15), .completed)
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)

        let unpacked = testHome.appendingPathComponent("Exported-Diagnostics", isDirectory: true)
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", destination.path, unpacked.path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        unzip.terminationHandler = { _ in finished.signal() }
        try unzip.run()
        guard finished.wait(timeout: .now() + 5) == .success else {
            unzip.terminate()
            XCTFail("Diagnostic archive extraction exceeded its bounded wait")
            return
        }
        XCTAssertEqual(unzip.terminationStatus, 0)
        let payload = unpacked.appendingPathComponent("Countdown-Diagnostics", isDirectory: true)
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: payload.path))
        XCTAssertTrue(names.isSuperset(of: ["summary.txt", "countdown.log"]))
        XCTAssertTrue(names.isSubset(of: ["summary.txt", "countdown.log", "countdown.previous.log"]))
        for name in names {
            let text = try String(contentsOf: payload.appendingPathComponent(name), encoding: .utf8)
            for secret in ["XCUITest Event", "Isolated fixture", "Active fixture subtask", "Completed fixture subtask", testHome.path] {
                XCTAssertFalse(text.contains(secret), "Private fixture content escaped into \(name)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)
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

    private func openEmojiPresets() {
        let toggle = app.buttons["editor.emoji.toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 3))
        revealInEditor(toggle)
        toggle.click()
        XCTAssertTrue(app.buttons["editor.emoji.preset.1f389"].waitForExistence(timeout: 3))
    }

    private func revealInEditor(_ element: XCUIElement, fullyInViewport: Bool = false) {
        let scroll = app.scrollViews["editor.scroll"]
        if fullyInViewport {
            for _ in 0..<4 {
                let viewport = scroll.frame
                let target = element.frame
                if viewport.contains(target) && element.isHittable { break }
                if target.minY < viewport.minY {
                    scroll.swipeDown()
                } else {
                    scroll.swipeUp()
                }
            }
            XCTAssertTrue(scroll.frame.contains(element.frame), "Editor target must be fully inside the scroll viewport before interaction")
            XCTAssertTrue(element.isHittable)
            return
        }
        for _ in 0..<3 where !element.isHittable { scroll.swipeDown() }
        for _ in 0..<4 where !element.isHittable { scroll.swipeUp() }
        XCTAssertTrue(element.isHittable)
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

    private func assertNearestHeading(_ heading: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(heading.waitForExistence(timeout: 3), file: file, line: line)
        let value = heading.value as? String
        let content = value.flatMap { $0.isEmpty ? nil : $0 } ?? heading.label
        XCTAssertEqual(content, "Ближайшее событие",
                       "Native heading label=\(heading.label), value=\(String(describing: heading.value))",
                       file: file, line: line)
    }

    private func waitForValue(_ element: XCUIElement, equals value: String) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element
        )], timeout: 3) == .completed
    }

    private func waitForFavorite(_ expected: String?) -> Bool {
        let predicate = NSPredicate { _, _ in
            guard let bytes = try? Data(contentsOf: self.dataURL),
                  let json = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
            return json["primaryID"] as? String == expected
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3) == .completed
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

    private func writeItems(_ items: [[String: Any]], primaryID: String?) throws {
        var json: [String: Any] = ["items": items]
        if let primaryID { json["primaryID"] = primaryID }
        try JSONSerialization.data(withJSONObject: json)
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
