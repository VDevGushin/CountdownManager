import XCTest
import Carbon

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
        if testRun?.hasSucceeded == false, let app {
            let snapshot = XCTAttachment(screenshot: app.screenshot())
            snapshot.name = "Failed user scenario"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
        app?.terminate()
        if testRun?.hasSucceeded == false, let testHome {
            let logURL = testHome.appendingPathComponent("Application Support/CountdownManager/Logs/countdown.log")
            if let log = try? String(contentsOf: logURL, encoding: .utf8) {
                let lifecycle = log.split(separator: "\n").filter {
                    $0.contains("shell.lifecycle") || $0.contains("desktop.")
                }.joined(separator: "\n")
                let trace = XCTAttachment(string: lifecycle)
                trace.name = "Failed scenario lifecycle"
                trace.lifetime = .keepAlways
                add(trace)
            }
        }
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
        try checkNewNoteLimit(titleText: "New limit")
    }

    func testCyrillicNewNoteHardLimitAndNativeFocus() throws {
        try checkNewNoteLimit(titleText: "Проверка лимита", noteTokens: ["а", "б", "в"],
                              titleSuffix: " заголовок", undoKey: "я")
    }

    private func checkNewNoteLimit(titleText: String, noteTokens: [String] = ["a", "b", "c"],
                                   titleSuffix: String = " title", undoKey: String = "z") throws {
        app.launch()
        let add = app.buttons["event.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        XCTAssertEqual(title.value as? String, "")
        title.typeText(titleText)
        XCTAssertEqual(title.value as? String, titleText)
        let note = app.textViews["editor.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        note.click()
        let initialNote = String(repeating: noteTokens[0], count: 149)
        note.typeText(initialNote)
        XCTAssertEqual((note.value as? String)?.count, 149)
        note.typeText(noteTokens[1])
        XCTAssertEqual((note.value as? String)?.count, 150)
        note.typeText(noteTokens[2])
        XCTAssertEqual(note.value as? String, initialNote + noteTokens[1])
        title.click()
        title.typeText(titleSuffix)
        XCTAssertEqual(title.value as? String, titleText + titleSuffix)
        note.click()
        note.typeKey(.delete, modifierFlags: [])
        XCTAssertEqual((note.value as? String)?.count, 149)
        note.typeKey(undoKey, modifierFlags: .command)
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
        revealInEditor(secondPageOption, fullyInViewport: true)
        XCTAssertTrue(secondPageOption.isEnabled)
        secondPageOption.click()
        XCTAssertTrue(waitForLabel(app.buttons["editor.emoji.toggle"], containing: "👶"))
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
        XCTAssertTrue(waitForAbsence(add))
        let item = try XCTUnwrap(try persistedItems().first)
        let savedID = try XCTUnwrap(item["id"] as? String)
        XCTAssertEqual(item["emoji"] as? String, "")
        XCTAssertTrue(waitForFavorite(nil))
        let star = app.buttons["event.primary.\(savedID)"]
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Не выбрано")
        let heading = app.staticTexts["event.featured.label.\(savedID)"]
        assertNoFeaturedHeading(heading)
        app.terminate()
        app.launch()
        XCTAssertTrue(star.waitForExistence(timeout: 3))
        XCTAssertEqual(star.value as? String, "Не выбрано")
        assertNoFeaturedHeading(heading)
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
        assertNoFeaturedHeading(heading)
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
        assertNoFeaturedHeading(heading)
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
        revealInEditor(option, fullyInViewport: true)
        XCTAssertTrue(option.isEnabled)
        option.click()
        XCTAssertTrue(waitForLabel(app.buttons["editor.emoji.toggle"], containing: "👶"))
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

    func testNewEventTypingAfterFocusedSubtaskDeletionCancelAndSave() throws {
        let originalBytes = try Data(contentsOf: dataURL)
        app.launch()
        openNewEditor()
        let title = app.textFields["editor.title"]
        replace(title, with: "Отменяемое событие")
        let removedID = try addEditorSubtask()
        let retainedID = try addEditorSubtask()
        let retained = app.textFields[retainedID]
        revealInEditor(retained, fullyInViewport: true)
        replace(retained, with: "Оставшаяся строка")
        let removed = app.textFields[removedID]
        revealInEditor(removed, fullyInViewport: true)
        replace(removed, with: "Фокус перед удалением")
        let delete = app.buttons["editor.subtask.delete.\(removedID.dropFirst("editor.subtask.".count))"]
        revealInEditor(delete, fullyInViewport: true)
        delete.click()
        XCTAssertTrue(waitForAbsence(removed))
        appendThroughKeyboard(retained, text: " после удаления", expecting: "Оставшаяся строка после удаления")
        appendThroughKeyboard(title, text: " изменено", expecting: "Отменяемое событие изменено")
        let note = app.textViews["editor.note"]
        revealInEditor(note, fullyInViewport: true)
        note.click()
        app.typeText("Первая строка\nВторая строка")
        XCTAssertTrue(waitForValue(note, equals: "Первая строка\nВторая строка"))
        XCTAssertTrue(waitForValue(retained, equals: "Оставшаяся строка после удаления"))
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.add"].waitForExistence(timeout: 3))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalBytes)

        openNewEditor()
        XCTAssertEqual(title.value as? String, "")
        XCTAssertEqual(note.value as? String, "")
        XCTAssertFalse(app.textFields[removedID].exists)
        XCTAssertFalse(retained.exists)
        let subtaskFields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.subtask."))
        XCTAssertEqual(subtaskFields.count, 0, "Cancel must discard every added subtask")
        replace(title, with: "Сохранённое новое событие")
        let savedFieldID = try addEditorSubtask()
        let savedField = app.textFields[savedFieldID]
        revealInEditor(savedField, fullyInViewport: true)
        replace(savedField, with: "Новая сохранённая строка")
        revealInEditor(note, fullyInViewport: true)
        note.click()
        app.typeText("Новая заметка")
        XCTAssertTrue(waitForValue(note, equals: "Новая заметка"))
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.add"].waitForExistence(timeout: 3))
        let items = try persistedItems()
        XCTAssertEqual(items.count, 2)
        let item = try XCTUnwrap(items.first { $0["id"] as? String != eventID })
        let savedID = try XCTUnwrap(item["id"] as? String)
        XCTAssertEqual(item["title"] as? String, "Сохранённое новое событие")
        XCTAssertEqual(item["note"] as? String, "Новая заметка")
        let tasks = try XCTUnwrap(item["subtasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0]["id"] as? String, String(savedFieldID.dropFirst("editor.subtask.".count)))
        XCTAssertEqual(tasks[0]["text"] as? String, "Новая сохранённая строка")
        XCTAssertEqual(tasks[0]["isCompleted"] as? Bool, false)
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor(savedID)
        XCTAssertEqual(title.value as? String, "Сохранённое новое событие")
        XCTAssertEqual(note.value as? String, "Новая заметка")
        revealInEditor(savedField, fullyInViewport: true)
        XCTAssertEqual(savedField.value as? String, "Новая сохранённая строка")
        app.buttons["editor.cancel"].click()
    }

    func testExistingEventTypingAfterFocusedRowDeletionSurvivesSaveAndReopen() throws {
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        replace(title, with: "Событие после удаления строки")
        let active = app.textFields["editor.subtask.\(activeSubtaskID)"]
        revealInEditor(active, fullyInViewport: true)
        replace(active, with: "Удаляется из фокуса")
        let delete = app.buttons["editor.subtask.delete.\(activeSubtaskID)"]
        revealInEditor(delete, fullyInViewport: true)
        delete.click()
        XCTAssertTrue(waitForAbsence(active))
        let completed = app.textFields["editor.subtask.\(completedSubtaskID)"]
        appendThroughKeyboard(completed, text: " дописано", expecting: "Completed fixture subtask дописано")
        let note = app.textViews["editor.note"]
        appendThroughKeyboard(note, text: " и новая заметка", expecting: "Isolated fixture и новая заметка")
        appendThroughKeyboard(title, text: " готово", expecting: "Событие после удаления строки готово")
        XCTAssertTrue(waitForValue(completed, equals: "Completed fixture subtask дописано"))
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let item = try XCTUnwrap(try persistedItems().first)
        XCTAssertEqual(item["title"] as? String, "Событие после удаления строки готово")
        XCTAssertEqual(item["note"] as? String, "Isolated fixture и новая заметка")
        let tasks = try XCTUnwrap(item["subtasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0]["id"] as? String, completedSubtaskID)
        XCTAssertEqual(tasks[0]["text"] as? String, "Completed fixture subtask дописано")
        XCTAssertEqual(tasks[0]["isCompleted"] as? Bool, true)
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor()
        XCTAssertEqual(title.value as? String, "Событие после удаления строки готово")
        XCTAssertEqual(note.value as? String, "Isolated fixture и новая заметка")
        revealInEditor(completed, fullyInViewport: true)
        XCTAssertEqual(completed.value as? String, "Completed fixture subtask дописано")
        XCTAssertFalse(active.exists)
        app.buttons["editor.cancel"].click()
    }

    func testCustomTitleDigitEditAndNativeUndo() throws {
        var fixture = try persistedItems()
        fixture[0]["title"] = "Четверг"
        try writeItems(fixture, primaryID: eventID)
        let originalBytes = try Data(contentsOf: dataURL)
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(waitForValue(title, equals: "Четверг"))
        XCTAssertTrue(app.buttons["editor.title.automatic"].exists, "An ordinary title edit must remain in custom mode")
        title.click()
        title.typeKey(.rightArrow, modifierFlags: .command)
        title.typeText("1")
        assertNativeTitleValue(title, expected: "Четверг1", context: "ordinary custom input")
        title.typeKey(try currentLayoutUndoKey(), modifierFlags: .command)
        assertNativeTitleValue(title, expected: "Четверг", context: "native Undo of ordinary custom input")
        XCTAssertTrue(app.buttons["editor.title.automatic"].exists, "Undoing custom text must keep custom mode")
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalBytes)
    }

    func testAutomaticTitleResetCancelSaveAndNativeUndo() throws {
        let originalBytes = try Data(contentsOf: dataURL)
        app.launch()
        openEditor()
        let title = app.textFields["editor.title"]
        let note = app.textViews["editor.note"]
        let automatic = app.buttons["editor.title.automatic"]
        activateAutomaticTitle()
        XCTAssertTrue(waitForValue(title, equals: "Четверг"))
        XCTAssertEqual(note.value as? String, "Isolated fixture")
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalBytes, "Reset followed by Cancel must preserve the legacy event")

        openEditor()
        XCTAssertEqual(title.value as? String, "XCUITest Event")
        activateAutomaticTitle()
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let saved = try XCTUnwrap(try persistedItems().first)
        XCTAssertEqual(saved["title"] as? String, "Четверг")
        XCTAssertEqual(saved["usesAutomaticTitle"] as? Bool, true)
        XCTAssertEqual(saved["note"] as? String, "Isolated fixture")
        let tasks = try XCTUnwrap(saved["subtasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.map { $0["id"] as? String }, [activeSubtaskID, completedSubtaskID])
        XCTAssertEqual(tasks.map { $0["isCompleted"] as? Bool }, [false, true])
        XCTAssertTrue(waitForFavorite(eventID))

        openEditor()
        XCTAssertTrue(waitForValue(title, equals: "Четверг"))
        XCTAssertFalse(automatic.exists, "Saved automatic mode must survive reopening")
        title.click()
        title.typeKey(.rightArrow, modifierFlags: .command)
        title.typeText("1")
        assertNativeTitleValue(title, expected: "Четверг1", context: "saved automatic mode")
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        title.typeKey(try currentLayoutUndoKey(), modifierFlags: .command)
        assertNativeTitleValue(title, expected: "Четверг", context: "native Undo after leaving automatic mode")
        XCTAssertTrue(automatic.exists, "Undoing text must not silently restore automatic mode")
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let afterUndo = try XCTUnwrap(try persistedItems().first)
        XCTAssertEqual(afterUndo["title"] as? String, "Четверг")
        XCTAssertFalse(afterUndo["usesAutomaticTitle"] as? Bool ?? false)
        XCTAssertEqual(afterUndo["note"] as? String, "Isolated fixture")
        let customBytes = try Data(contentsOf: dataURL)
        openEditor()
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        activateAutomaticTitle()
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try Data(contentsOf: dataURL), customBytes)
    }

    func testRepeatedAutomaticTitleCyclesPreserveNewDraftFields() throws {
        let originalBytes = try Data(contentsOf: dataURL)
        app.launch()
        openNewEditor()
        let title = app.textFields["editor.title"]
        let note = app.textViews["editor.note"]
        activateAutomaticTitle()
        let generatedTitle = try XCTUnwrap(title.value as? String)
        XCTAssertFalse(generatedTitle.isEmpty)
        revealInEditor(note, fullyInViewport: true)
        note.click()
        note.typeText("Заметка после смены названия")
        let taskID = try addEditorSubtask()
        let task = app.textFields[taskID]
        revealInEditor(task, fullyInViewport: true)
        replace(task, with: "Не потерять эту подзадачу")
        for index in 1...3 {
            revealInEditor(title, fullyInViewport: true)
            replace(title, with: "Своё название \(index)")
            activateAutomaticTitle()
            XCTAssertTrue(waitForValue(title, equals: generatedTitle))
            XCTAssertEqual(note.value as? String, "Заметка после смены названия")
            XCTAssertEqual(task.value as? String, "Не потерять эту подзадачу")
            XCTAssertEqual(try Data(contentsOf: dataURL), originalBytes, "Mode changes must remain draft-only")
        }
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.add"].waitForExistence(timeout: 3))
        let item = try XCTUnwrap(try persistedItems().first { $0["id"] as? String != eventID })
        let savedID = try XCTUnwrap(item["id"] as? String)
        XCTAssertEqual(item["usesAutomaticTitle"] as? Bool, true)
        XCTAssertEqual(item["title"] as? String, generatedTitle)
        XCTAssertEqual(item["note"] as? String, "Заметка после смены названия")
        let tasks = try XCTUnwrap(item["subtasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0]["id"] as? String, String(taskID.dropFirst("editor.subtask.".count)))
        XCTAssertEqual(tasks[0]["text"] as? String, "Не потерять эту подзадачу")
        XCTAssertEqual(tasks[0]["isCompleted"] as? Bool, false)
        XCTAssertTrue(waitForFavorite(eventID))
        openEditor(savedID)
        XCTAssertTrue(waitForValue(title, equals: generatedTitle))
        XCTAssertFalse(app.buttons["editor.title.automatic"].exists)
        XCTAssertEqual(note.value as? String, "Заметка после смены названия")
        revealInEditor(task, fullyInViewport: true)
        XCTAssertEqual(task.value as? String, "Не потерять эту подзадачу")
        app.buttons["editor.cancel"].click()
    }

    private func assertNativeTitleValue(
        _ title: XCUIElement, expected: String, context: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let appended = waitForValue(title, equals: expected)
        let actual = title.value as? String
        if !appended {
            let scalars = actual?.unicodeScalars.map { $0.value }
            let mode = app.staticTexts["editor.title.mode"]
            let automatic = app.buttons["editor.title.automatic"]
            let diagnostic = "Native title value failed (\(context)): expected=\(expected) actual=\(String(describing: actual)) "
                + "unicodeScalars=\(String(describing: scalars)) "
                + "mode=\(mode.exists ? String(describing: mode.value) : "missing") "
                + "automaticActionExists=\(automatic.exists)\n"
                + "Title attributes (including keyboard focus):\n\(title.debugDescription)\n"
                + "Application hierarchy:\n\(app.debugDescription)"
            print(diagnostic)
            let details = XCTAttachment(string: diagnostic)
            details.name = "Native title value and focus — \(context)"
            details.lifetime = .keepAlways
            add(details)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Native title value failure — \(context)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(appended, "Expected \(expected) after \(context); actual=\(String(describing: actual))", file: file, line: line)
    }

    private func currentLayoutUndoKey() throws -> String {
        try currentLayoutShortcutKey("z")
    }

    private func currentLayoutShortcutKey(_ asciiKey: String) throws -> String {
        func data(for source: TISInputSource) throws -> CFData {
            let pointer = try XCTUnwrap(TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData),
                                       "The keyboard layout must expose Unicode translation data for native shortcuts")
            return Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        }
        func character(for code: UInt16, layoutData: CFData) -> String? {
            guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
            let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
            var deadKeys: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 8)
            let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDown), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeys,
                                        characters.count, &length, &characters)
            guard status == noErr, length > 0 else { return nil }
            return String(utf16CodeUnits: characters, count: length)
        }
        let current = try XCTUnwrap(TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue())
        let currentData = try data(for: current)
        if (0..<128).contains(where: { character(for: UInt16($0), layoutData: currentData) == asciiKey }) {
            return asciiKey
        }
        let ascii = try XCTUnwrap(TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue())
        let asciiData = try data(for: ascii)
        let code = try XCTUnwrap((0..<128).first { character(for: UInt16($0), layoutData: asciiData) == asciiKey },
                                "The ASCII keyboard layout must supply the native shortcut key")
        let mapped = try XCTUnwrap(character(for: UInt16(code), layoutData: currentData),
                                  "The active keyboard layout must translate the native shortcut key")
        XCTAssertEqual(mapped.count, 1, "XCUI needs one current-layout character for the shortcut key")
        print("Native shortcut current-layout key=\(mapped), ASCII \(asciiKey) virtualKey=\(code)")
        return mapped
    }

    private func activateAutomaticTitle() {
        let automatic = app.buttons["editor.title.automatic"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        revealInEditor(automatic, fullyInViewport: true)
        automatic.click()
        XCTAssertTrue(waitForAbsence(automatic), "Explicit reset must immediately switch the draft into date mode")
    }

    private func openNewEditor() {
        let add = app.buttons["event.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.click()
        XCTAssertTrue(app.textFields["editor.title"].waitForExistence(timeout: 3))
    }

    private func appendThroughKeyboard(_ field: XCUIElement, text: String, expecting value: String) {
        revealInEditor(field, fullyInViewport: true)
        field.click()
        field.typeKey(.rightArrow, modifierFlags: .command)
        app.typeText(text)
        XCTAssertTrue(waitForValue(field, equals: value), "Keyboard input must reach the selected editor field")
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

    func testWeatherCityMenuSupportsNativeSelection() throws {
        app.launch()
        app.buttons["settings.open"].click()
        let enabled = app.checkBoxes["settings.weather.enabled"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 3))
        let picker = app.popUpButtons["settings.weather.location"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertFalse(picker.isEnabled)
        enabled.click()
        let available = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: picker)
        XCTAssertEqual(XCTWaiter.wait(for: [available], timeout: 3), .completed)
        picker.click()
        let cities = ["Автоматически", "Москва", "Санкт-Петербург", "Казань", "Грозный", "Нижний Новгород",
                      "Екатеринбург", "Новосибирск", "Самара", "Ростов-на-Дону", "Краснодар"]
        for city in cities {
            XCTAssertTrue(app.menuItems[city].waitForExistence(timeout: 3), "Native menu is missing \(city)")
        }
        app.menuItems["Москва"].click()
        XCTAssertTrue(waitForValue(picker, equals: "Москва"))
        enabled.click()
        XCTAssertFalse(picker.isEnabled)
        enabled.click()
        XCTAssertTrue(waitForValue(picker, equals: "Москва"))
    }

    func testDesktopChecklistGroupsIncompleteBeforeCompleted() throws {
        app.launch()
        let original = try XCTUnwrap(try persistedItems().first?["subtasks"] as? [[String: Any]])
        app.buttons["desktop.open"].click()
        let unfinished = app.checkBoxes["desktop.subtask.toggle.\(activeSubtaskID)"]
        let finished = app.checkBoxes["desktop.subtask.toggle.\(completedSubtaskID)"]
        XCTAssertTrue(unfinished.waitForExistence(timeout: 3))
        XCTAssertTrue(finished.waitForExistence(timeout: 3))
        XCTAssertLessThan(unfinished.frame.minY, finished.frame.minY)
        unfinished.click()
        XCTAssertTrue(waitForSubtaskCompletion(activeSubtaskID, equals: true))
        finished.click()
        XCTAssertTrue(waitForSubtaskCompletion(completedSubtaskID, equals: false))
        let regrouped = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            finished.frame.minY < unfinished.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [regrouped], timeout: 3), .completed)
        let saved = try XCTUnwrap(try persistedItems().first?["subtasks"] as? [[String: Any]])
        XCTAssertEqual(saved.compactMap { $0["id"] as? String }, original.compactMap { $0["id"] as? String })
        XCTAssertEqual(saved.first?["isCompleted"] as? Bool, true)
        XCTAssertEqual(saved.last?["isCompleted"] as? Bool, false)
    }

    func testDesktopGridListTransitionRetainsSelectionAndSplit() throws {
        let identifiers = try writeDesktopMotionFixture()
        let original = try Data(contentsOf: dataURL)
        app.launch()
        app.buttons["desktop.open"].click()
        let first = app.buttons["desktop.event.\(identifiers[0])"]
        let second = app.buttons["desktop.event.\(identifiers[1])"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(second.waitForExistence(timeout: 3))
        let detail = app.descendants(matching: .any).matching(identifier: "desktop.detail.\(identifiers[0])").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        let splitter = app.splitters.firstMatch
        XCTAssertTrue(splitter.exists)
        let origin = splitter.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        origin.press(forDuration: 0.1, thenDragTo: origin.withOffset(CGVector(dx: 55, dy: 0)))
        let inspectorX = detail.frame.minX
        let grid = app.radioButtons["Коллекция"]
        let list = app.radioButtons["Лента"]
        XCTAssertTrue(grid.exists)
        XCTAssertTrue(list.exists)
        XCTAssertTrue(waitForDesktopArrangement(first: first, second: second, grid: true))
        attachDesktopMotionSnapshot("Desktop grid before transition")

        list.click()
        XCTAssertTrue(waitForDesktopArrangement(first: first, second: second, grid: false))
        XCTAssertTrue(detail.exists)
        XCTAssertEqual(detail.frame.minX, inspectorX, accuracy: 2)
        attachDesktopMotionSnapshot("Desktop list after transition")
        grid.click()
        XCTAssertTrue(waitForDesktopArrangement(first: first, second: second, grid: true))
        XCTAssertTrue(detail.exists)
        XCTAssertEqual(detail.frame.minX, inspectorX, accuracy: 2)
        attachDesktopMotionSnapshot("Desktop grid after reverse transition")

        for _ in 0..<3 {
            list.click()
            grid.click()
        }
        list.click()
        XCTAssertTrue(waitForDesktopArrangement(first: first, second: second, grid: false))
        let ordered = identifiers.map { app.buttons["desktop.event.\($0)"] }
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertLessThan(pair.0.frame.minY, pair.1.frame.minY)
        }
        let november = app.staticTexts["desktop.month.25199"]
        let december = app.staticTexts["desktop.month.25200"]
        XCTAssertTrue(november.exists)
        XCTAssertTrue(december.exists)
        XCTAssertLessThan(november.frame.minY, december.frame.minY)
        let browser = app.scrollViews.containing(.button, identifier: "desktop.event.\(identifiers[0])").firstMatch
        XCTAssertTrue(browser.exists)
        let last = try XCTUnwrap(ordered.last)
        for _ in 0..<8 where !last.isHittable { browser.swipeUp() }
        XCTAssertTrue(last.isHittable)
        attachDesktopMotionSnapshot("Desktop final month at list end")
        XCTAssertTrue(detail.exists)
        XCTAssertEqual(detail.frame.minX, inspectorX, accuracy: 2)
        XCTAssertEqual(try Data(contentsOf: dataURL), original)
    }

    func testDesktopChecklistMiddleRowReordersAndReturnsWithoutChangingIdentities() throws {
        var items = try persistedItems()
        let identifiers = (1...8).map { "55555555-5555-5555-5555-" + String(format: "%012d", $0) }
        let labels = ["Подготовить документы", "Проверить маршрут",
                      "Собрать вещи и проверить необходимое снаряжение",
                      "Зарядить устройства", "Проверить время встречи",
                      "Купить билеты", "Подтвердить бронь", "Сохранить адрес"]
        let tasks: [[String: Any]] = identifiers.enumerated().map { index, identifier in
            ["id": identifier, "text": labels[index], "isCompleted": index >= 5]
        }
        items[0]["subtasks"] = tasks
        try writeItems(items, primaryID: eventID)
        app.launch()
        app.buttons["desktop.open"].click()
        let target = app.checkBoxes.matching(NSPredicate(format: "label == %@", labels[2])).firstMatch
        let following = app.checkBoxes.matching(NSPredicate(format: "label == %@", labels[3])).firstMatch
        let lastActive = app.checkBoxes.matching(NSPredicate(format: "label == %@", labels[4])).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        XCTAssertTrue(following.exists)
        XCTAssertLessThan(target.frame.maxY, following.frame.minY)
        attachDesktopMotionSnapshot("Checklist eight rows before completion")
        target.click()
        XCTAssertTrue(waitForSubtaskCompletion(identifiers[2], equals: true))
        let completedPosition = NSPredicate { _, _ in target.frame.minY > lastActive.frame.maxY }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: completedPosition, object: nil)], timeout: 3), .completed)
        attachDesktopMotionSnapshot("Checklist middle row completed below unfinished rows")
        target.click()
        XCTAssertTrue(waitForSubtaskCompletion(identifiers[2], equals: false))
        let restoredPosition = NSPredicate { _, _ in target.frame.maxY < following.frame.minY }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restoredPosition, object: nil)], timeout: 3), .completed)
        attachDesktopMotionSnapshot("Checklist reopened row restored to original position")
        let saved = try XCTUnwrap(try persistedItems().first?["subtasks"] as? [[String: Any]])
        XCTAssertEqual(saved.compactMap { $0["id"] as? String }, identifiers)
        XCTAssertEqual(saved.compactMap { $0["text"] as? String }, labels)
        XCTAssertEqual(saved.compactMap { $0["isCompleted"] as? Bool }, tasks.compactMap { $0["isCompleted"] as? Bool })
        XCTAssertTrue(waitForFavorite(eventID))
    }

    func testDesktopSettingsBackdropCloseAndEscapePreserveEventsAndEditor() throws {
        let identifiers = try writeDesktopMotionFixture()
        let original = try Data(contentsOf: dataURL)
        app.launch()
        app.buttons["desktop.open"].click()
        let main = app.windows["desktop.window"]
        XCTAssertTrue(main.waitForExistence(timeout: 3))
        let open = main.buttons.matching(NSPredicate(format: "label == %@", "Настройки")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        let selected = main.descendants(matching: .any).matching(identifier: "desktop.detail.\(identifiers[0])").firstMatch
        XCTAssertTrue(selected.exists)
        let inspectorX = selected.frame.minX
        let coveredPane = CGRect(x: main.frame.midX - 215, y: main.frame.midY - 280, width: 430, height: 560)
        let alternative = try XCTUnwrap(identifiers.dropFirst().compactMap { identifier -> (String, CGPoint)? in
            let event = main.buttons["desktop.event.\(identifier)"]
            guard event.exists && event.isHittable else { return nil }
            let center = CGPoint(x: event.frame.midX, y: event.frame.midY)
            return coveredPane.insetBy(dx: -12, dy: -12).contains(center) ? nil : (identifier, center)
        }.first, "A visible ordinary event outside the centered settings pane is required")
        let backgroundEvent = main.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: alternative.1.x - main.frame.minX, dy: alternative.1.y - main.frame.minY))
        open.click()
        let closeCandidates = main.buttons.matching(NSPredicate(format: "label == %@", "Закрыть настройки"))
        XCTAssertTrue(closeCandidates.firstMatch.waitForExistence(timeout: 3))
        let close = try XCTUnwrap(closeCandidates.allElementsBoundByIndex.first {
            $0.frame.width <= 44 && $0.frame.height <= 44
        }, "A compact close button must be present separately from the full-window backdrop")
        XCTAssertFalse(main.buttons.matching(NSPredicate(format: "label == %@", "Назад")).firstMatch.exists)
        XCTAssertFalse(app.windows["settings.window"].exists)
        XCTAssertEqual(main.sheets.count, 0)
        XCTAssertFalse(selected.exists, "Settings must hide underlying event controls from accessibility")
        let weather = main.checkBoxes.matching(NSPredicate(format: "label == %@", "Показывать погоду в днях")).firstMatch
        let initialWeather = try XCTUnwrap(checkboxValue(weather))
        XCTAssertTrue(["0", "1"].contains(initialWeather))
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -200, dy: 0)).click()
        XCTAssertTrue(close.exists, "Clicking blank settings header space must not dismiss the pane")
        close.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: -5, dy: 150)).click()
        XCTAssertTrue(close.exists, "Clicking blank settings body space must not dismiss the pane")
        weather.click()
        XCTAssertTrue(waitForCheckboxValue(weather, equals: initialWeather == "1" ? "0" : "1"))
        attachDesktopMotionSnapshot("Centered desktop settings overlay")
        backgroundEvent.click()
        XCTAssertTrue(waitForAbsence(close))
        XCTAssertTrue(selected.waitForExistence(timeout: 3))
        XCTAssertFalse(main.descendants(matching: .any).matching(identifier: "desktop.detail.\(alternative.0)").firstMatch.exists,
                       "The dismissal click must not select the event under the backdrop")
        XCTAssertEqual(selected.frame.minX, inspectorX, accuracy: 2)
        XCTAssertEqual(try Data(contentsOf: dataURL), original)
        open.click()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForCheckboxValue(weather, equals: initialWeather == "1" ? "0" : "1"))
        close.click()
        XCTAssertTrue(waitForAbsence(close))
        open.click()
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        activateForKeyboardInput()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(close))
        XCTAssertTrue(selected.waitForExistence(timeout: 3))
        XCTAssertEqual(selected.frame.minX, inspectorX, accuracy: 2)
        let edit = main.buttons.matching(NSPredicate(format: "label == %@", "Редактировать событие")).firstMatch
        XCTAssertTrue(edit.isEnabled)
        edit.click()
        let title = app.textFields["editor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        activateForKeyboardInput()
        replace(title, with: "Черновик после настроек")
        main.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.35)).click()
        XCTAssertEqual(title.value as? String, "Черновик после настроек",
                       "Clicking outside the editor sheet must not discard its draft")
        activateForKeyboardInput()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(title))
        XCTAssertEqual(try Data(contentsOf: dataURL), original)
        XCTAssertTrue(main.exists)
    }

    private func checkboxValue(_ checkbox: XCUIElement) -> String? {
        (checkbox.value as? NSNumber)?.stringValue ?? checkbox.value as? String
    }

    private func activateForKeyboardInput() {
        app.activate()
        let foreground = NSPredicate { _, _ in self.app.state == .runningForeground }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: foreground, object: nil)], timeout: 3), .completed)
    }

    private func waitForCheckboxValue(_ checkbox: XCUIElement, equals value: String) -> Bool {
        let predicate = NSPredicate { _, _ in self.checkboxValue(checkbox) == value }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3) == .completed
    }

    private func waitForDesktopArrangement(first: XCUIElement, second: XCUIElement, grid: Bool) -> Bool {
        let predicate = NSPredicate { _, _ in
            let firstFrame = first.frame
            let secondFrame = second.frame
            if grid {
                return abs(firstFrame.minY - secondFrame.minY) < 2 && secondFrame.minX > firstFrame.maxX
            }
            return abs(firstFrame.minX - secondFrame.minX) < 2 && secondFrame.minY > firstFrame.maxY
        }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 3) == .completed
    }

    private func attachDesktopMotionSnapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func writeDesktopMotionFixture() throws -> [String] {
        let identifiers = (1...9).map { "44444444-4444-4444-4444-" + String(format: "%012d", $0) }
        let items: [[String: Any]] = identifiers.enumerated().map { index, identifier in
            [
                "id": identifier,
                "title": index == 2 ? "Очень длинное название события для проверки переноса текста между сеткой и списком" : "Событие \(index + 1)",
                "note": "Изолированная проверка перехода",
                "date": ["year": 2099, "month": index < 7 ? 11 : 12, "day": index < 7 ? index + 1 : index - 6],
                "emoji": index == 2 ? "🎂" : "",
                "subtasks": index == 0 ? [
                    ["id": activeSubtaskID, "text": "Незавершённое дело", "isCompleted": false],
                    ["id": completedSubtaskID, "text": "Завершённое дело", "isCompleted": true]
                ] : []
            ]
        }
        try writeItems(items, primaryID: nil)
        return identifiers
    }

    func testAttachmentsNativePickerSaveCancelAndSharedSurfaces() throws {
        let source = testHome.appendingPathComponent("Attachment-fixture.txt")
        let bytes = Data("Isolated attachment contents\n".utf8)
        try bytes.write(to: source)
        let originalEvents = try Data(contentsOf: dataURL)
        app.launch()
        openEditor()
        let add = app.buttons["editor.attachments.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), "The editor must expose its attachment Add action separately from the section")
        revealInEditor(add, fullyInViewport: true)
        add.click()
        let picker = app.sheets["open-panel"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "A real native open sheet must appear")
        picker.buttons["CancelButton"].click()
        XCTAssertTrue(waitForAbsence(picker))
        XCTAssertTrue(app.textFields["editor.title"].exists, "Picker Cancel must retain the editor")
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)

        try selectNativeAttachment(source)
        let pendingRemove = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "editor.attachments.remove.")).firstMatch
        XCTAssertTrue(pendingRemove.waitForExistence(timeout: 3))
        let pendingID = String(pendingRemove.identifier.dropFirst("editor.attachments.remove.".count))
        let pendingCopy = attachmentCopyURL(id: pendingID, name: source.lastPathComponent)
        XCTAssertNotEqual(pendingCopy.standardizedFileURL, source.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: pendingCopy), bytes)
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents, "Import must remain draft-only")
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForAttachmentFile(pendingCopy, exists: false), "Cancelled imported copy must be cleaned up")
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)

        openEditor()
        try selectNativeAttachment(source)
        XCTAssertTrue(pendingRemove.waitForExistence(timeout: 3))
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        let metadata = try XCTUnwrap(try persistedItems().first?["attachments"] as? [[String: Any]])
        XCTAssertEqual(metadata.count, 1)
        let saved = try XCTUnwrap(metadata.first)
        let savedID = try XCTUnwrap(saved["id"] as? String)
        XCTAssertEqual(saved["name"] as? String, source.lastPathComponent)
        XCTAssertEqual((saved["byteCount"] as? NSNumber)?.int64Value, Int64(bytes.count))
        let savedCopy = attachmentCopyURL(id: savedID, name: source.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: savedCopy), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)

        app.buttons["desktop.open"].click()
        let desktopSection = app.descendants(matching: .any).matching(identifier: "desktop.attachments.\(eventID)").firstMatch
        XCTAssertTrue(desktopSection.waitForExistence(timeout: 3))
        XCTAssertTrue(desktopSection.staticTexts["Вложения"].exists)
        XCTAssertTrue(desktopSection.staticTexts["1"].exists)
        let openID = "attachments.open.\(eventID).\(savedID)"
        XCTAssertTrue(app.buttons[openID].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[openID].label.contains(source.lastPathComponent))
        app.buttons["desktop.panel"].click()
        let disclosure = app.buttons["panel.attachments.toggle.\(eventID)"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 3))
        XCTAssertTrue(disclosure.label.contains("1"))
        for _ in 0..<4 where !disclosure.isHittable { app.scrollViews["event.list"].swipeUp() }
        XCTAssertTrue(disclosure.isHittable)
        disclosure.click()
        XCTAssertTrue(app.buttons[openID].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons[openID].label.contains(source.lastPathComponent))

        openEditor()
        let remove = app.buttons["editor.attachments.remove.\(savedID)"]
        revealInEditor(remove, fullyInViewport: true)
        remove.click()
        XCTAssertTrue(waitForAbsence(remove))
        app.buttons["editor.cancel"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertEqual(try persistedItems().first?["attachments"] as? NSArray, metadata as NSArray)
        XCTAssertEqual(try Data(contentsOf: savedCopy), bytes, "Cancelled removal must retain the saved copy")

        openEditor()
        revealInEditor(remove, fullyInViewport: true)
        remove.click()
        app.buttons["editor.save"].click()
        XCTAssertTrue(app.buttons["event.edit.\(eventID)"].waitForExistence(timeout: 3))
        XCTAssertTrue((try persistedItems().first?["attachments"] as? [[String: Any]] ?? []).isEmpty)
        XCTAssertTrue(waitForAttachmentFile(savedCopy, exists: false), "Saved removal must delete the owned copy")
        XCTAssertEqual(try Data(contentsOf: source), bytes, "Every operation must preserve the original")
    }

    private func selectNativeAttachment(_ source: URL) throws {
        let add = app.buttons["editor.attachments.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        revealInEditor(add, fullyInViewport: true)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in add.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 3), .completed)
        add.click()
        let picker = app.sheets["open-panel"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "The native picker must reopen after Cancel")
        activateForKeyboardInput()
        app.typeKey(try currentLayoutShortcutKey("g"), modifierFlags: [.command, .shift])
        let goToFolder = app.sheets["GoToWindow"]
        XCTAssertTrue(goToFolder.waitForExistence(timeout: 3))
        let path = goToFolder.textFields["PathTextField"]
        XCTAssertTrue(path.waitForExistence(timeout: 3))
        path.click()
        path.typeKey(try currentLayoutShortcutKey("a"), modifierFlags: .command)
        path.typeKey(.delete, modifierFlags: [])
        path.typeText(source.path)
        XCTAssertEqual(path.value as? String, source.path)
        path.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(goToFolder))
        let choose = picker.buttons["OKButton"]
        let chooseEnabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in choose.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [chooseEnabled], timeout: 3), .completed)
        choose.click()
        XCTAssertTrue(waitForAbsence(picker))
    }

    private func attachmentCopyURL(id: String, name: String) -> URL {
        dataURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true).appendingPathComponent(name)
    }

    private func waitForAttachmentFile(_ url: URL, exists: Bool) -> Bool {
        let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: url.path) == exists }
        return XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 5) == .completed
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
        let panel = app.sheets["save-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3), "The native save sheet must be accessible")
        panel.buttons["CancelButton"].click()
        XCTAssertTrue(waitForAbsence(panel))
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        XCTAssertEqual(try Data(contentsOf: dataURL), originalEvents)
        let exportEnabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in export.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [exportEnabled], timeout: 3), .completed)

        export.click()
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        let filename = panel.textFields["saveAsNameTextField"]
        XCTAssertTrue(filename.waitForExistence(timeout: 3))
        XCTAssertTrue(["Countdown-Diagnostics.zip", "Countdown-Diagnostics"].contains(filename.value as? String ?? ""))
        filename.click()
        activateForKeyboardInput()
        app.typeKey(try currentLayoutShortcutKey("g"), modifierFlags: [.command, .shift])
        let goToFolder = app.sheets["GoToWindow"]
        XCTAssertTrue(goToFolder.waitForExistence(timeout: 3))
        let folder = goToFolder.textFields["PathTextField"]
        XCTAssertTrue(folder.waitForExistence(timeout: 3), "The native Go to Folder field must be accessible")
        replace(folder, with: testHome.path)
        folder.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(waitForAbsence(goToFolder))
        let save = panel.buttons["OKButton"]
        let saveEnabled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in save.isEnabled }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [saveEnabled], timeout: 3), .completed)
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
        let archiveEvidence = XCTAttachment(data: try Data(contentsOf: destination), uniformTypeIdentifier: "public.zip-archive")
        archiveEvidence.name = "Actual isolated native diagnostic export"
        archiveEvidence.lifetime = .keepAlways
        add(archiveEvidence)
    }

    private var root: XCUIElement {
        app.descendants(matching: .any)["root.window"]
    }

    private func openEditor(_ id: String? = nil) {
        let edit = app.buttons["event.edit.\(id ?? eventID)"]
        XCTAssertTrue(edit.waitForExistence(timeout: 3))
        for _ in 0..<4 where !edit.isHittable { app.scrollViews["event.list"].swipeUp() }
        XCTAssertTrue(edit.isHittable)
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

    private func assertNoFeaturedHeading(_ heading: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let absent = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: heading)
        XCTAssertEqual(XCTWaiter.wait(for: [absent], timeout: 3), .completed,
                       "An unfavorited event must not retain the large-card heading", file: file, line: line)
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
