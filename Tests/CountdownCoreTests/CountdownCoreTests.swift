import Foundation
import CountdownCore

final class CountdownCoreTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }

    func day(_ y: Int = 2026, _ m: Int = 9, _ d: Int) -> Day {
        Day(calendar.date(from: DateComponents(year: y, month: m, day: d))!, calendar: calendar)
    }

    func testCreationAndFieldValidation() throws {
        var data = CountdownData()
        for date in [day(2026, 9, 4), day(2026, 9, 5)] {
            XCTAssertThrowsError(try data.save(
                Countdown(title: "Test", date: date, emoji: "🎉"),
                primary: false,
                today: day(2026, 9, 5)
            ))
        }
        XCTAssertThrowsError(try data.save(Countdown(title: "  ", date: day(2026, 9, 6), emoji: "🎉"), primary: false, today: day(2026, 9, 5)))
        XCTAssertThrowsError(try data.save(Countdown(title: "Test", date: day(2026, 9, 6), emoji: "abc"), primary: false, today: day(2026, 9, 5)))
        XCTAssertThrowsError(try data.save(Countdown(title: "Test", note: String(repeating: "x", count: 281), date: day(2026, 9, 6), emoji: "🎉"), primary: false, today: day(2026, 9, 5)))
        XCTAssertTrue(data.items.isEmpty)
    }

    func testSubtaskLimitsNormalizationCompletionAndOrder() throws {
        let today = day(2026, 9, 5)
        var data = CountdownData()
        let event = Countdown(title: "Event", date: day(2026, 9, 7), emoji: "🎉")
        try data.save(event, primary: true, today: today)
        XCTAssertTrue(data.items[0].subtasks.isEmpty)

        XCTAssertThrowsError(try data.addSubtask(to: event.id, text: " \n\t ", today: today))
        XCTAssertThrowsError(try data.addSubtask(to: event.id, text: String(repeating: "я", count: 51), today: today))

        let firstID = try data.addSubtask(
            to: event.id,
            text: "  \(String(repeating: "я", count: 50))  ",
            today: today
        )
        XCTAssertEqual(data.items[0].subtasks.count, 1)
        XCTAssertEqual(data.items[0].subtasks[0].text.count, 50)

        let secondID = try data.addSubtask(to: event.id, text: "Second", today: today)
        _ = try data.addSubtask(to: event.id, text: "Third", today: today)
        _ = try data.addSubtask(to: event.id, text: "Fourth", today: today)
        _ = try data.addSubtask(to: event.id, text: "Fifth", today: today)
        XCTAssertEqual(data.items[0].subtasks.count, 5)
        XCTAssertThrowsError(try data.addSubtask(to: event.id, text: "Sixth", today: today))

        let originalIDs = data.items[0].subtasks.map(\.id)
        try data.toggleSubtask(eventID: event.id, subtaskID: firstID, today: today)
        XCTAssertTrue(data.items[0].subtasks[0].isCompleted)
        XCTAssertEqual(data.items[0].subtasks.map(\.id), originalIDs)
        let grouped = data.items[0].subtasks.filter { !$0.isCompleted } + data.items[0].subtasks.filter(\.isCompleted)
        XCTAssertEqual(grouped.map(\.id), Array(originalIDs.dropFirst()) + [firstID])

        try data.toggleSubtask(eventID: event.id, subtaskID: firstID, today: today)
        XCTAssertFalse(data.items[0].subtasks[0].isCompleted)
        XCTAssertEqual(data.items[0].subtasks.map(\.id), originalIDs)

        try data.editSubtask(eventID: event.id, subtaskID: secondID, text: "  Edited  ", today: today)
        XCTAssertEqual(data.items[0].subtasks[1].text, "Edited")
        XCTAssertThrowsError(try data.editSubtask(eventID: event.id, subtaskID: secondID, text: " ", today: today))
        XCTAssertEqual(data.items[0].subtasks[1].text, "Edited")

        try data.deleteSubtask(eventID: event.id, subtaskID: secondID, today: today)
        XCTAssertEqual(data.items[0].subtasks.count, 4)
    }

    func testAllSubtasksCompletedDoesNotFinishEvent() throws {
        let today = day(2026, 9, 5)
        let event = Countdown(
            title: "Event",
            date: day(2026, 9, 8),
            emoji: "🎉",
            subtasks: try (1...5).map { try Subtask(text: "Task \($0)", isCompleted: true) }
        )
        var data = CountdownData()
        try data.save(event, primary: true, today: today)
        data.normalize(today: day(2026, 9, 7))
        XCTAssertEqual(data.items.count, 1)
        XCTAssertEqual(data.items[0].subtasks.filter(\.isCompleted).count, 5)
    }

    func testCRUDPrimaryExpiryAndPersistence() throws {
        var data = CountdownData()
        let today = day(2026, 9, 5)
        var first = Countdown(title: "First", note: "  Small note  ", date: day(2026, 9, 6), emoji: "☀️")
        let second = Countdown(title: "Second", date: day(2026, 9, 8), emoji: "✈️")
        try data.save(first, primary: false, today: today)
        XCTAssertEqual(data.primaryID, first.id)
        XCTAssertEqual(data.items[0].note, "Small note")
        try data.save(second, primary: true, today: today)
        XCTAssertEqual(data.primaryID, second.id)
        first.title = "Edited"
        try data.save(first, primary: true, today: today)
        XCTAssertEqual(data.items.count, 2)
        XCTAssertEqual(data.items[0].title, "Edited")
        let decoded = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded, data)
        data.normalize(today: day(2026, 9, 6))
        XCTAssertEqual(data.items.count, 2)
        XCTAssertEqual(data.primaryID, first.id)
        data.normalize(today: day(2026, 9, 7))
        XCTAssertEqual(data.items.count, 1)
        XCTAssertEqual(data.primaryID, second.id)
        data.delete(second.id, today: today)
        XCTAssertNil(data.primaryID)
        XCTAssertTrue(data.items.isEmpty)
    }

    func testNoteBoundariesNormalizationAndRoundTrip() throws {
        let today = day(2026, 9, 5)
        var data = CountdownData()
        let accepted = Countdown(
            title: "Exact limit",
            note: "  \(String(repeating: "я", count: 280))  ",
            date: day(2026, 9, 6),
            emoji: "📝"
        )
        try data.save(accepted, primary: false, today: today)
        XCTAssertEqual(data.items[0].note?.count, 280)

        var blankNote = Countdown(title: "Blank", note: " \n\t ", date: day(2026, 9, 7), emoji: "🎉")
        try data.save(blankNote, primary: false, today: today)
        XCTAssertNil(data.items.first(where: { $0.id == blankNote.id })?.note)

        blankNote.note = String(repeating: "🙂", count: 281)
        XCTAssertThrowsError(try data.save(blankNote, primary: false, today: today))
    }

    func testTodayEditingAndLifecycleRegardlessOfSubtasks() throws {
        let event = Countdown(
            title: "Today",
            note: "Visible all day",
            date: day(2026, 9, 6),
            emoji: "☀️",
            subtasks: [try Subtask(text: "Unfinished")]
        )
        let later = Countdown(title: "Later", date: day(2026, 9, 8), emoji: "🚀")
        var data = CountdownData()
        try data.save(event, primary: true, today: day(2026, 9, 5))
        try data.save(later, primary: false, today: day(2026, 9, 5))

        data.normalize(today: day(2026, 9, 6))
        XCTAssertEqual(data.items.count, 2)
        XCTAssertEqual(data.primaryID, event.id)
        XCTAssertEqual(countdownLabel(event.date.days(from: day(2026, 9, 6), calendar: calendar)), "Сегодня")

        var editedToday = event
        editedToday.title = "Edited today"
        editedToday.note = "Changed"
        editedToday.emoji = "🎂"
        editedToday.subtasks.append(try Subtask(text: "Added today"))
        try data.save(editedToday, primary: true, today: day(2026, 9, 6))
        XCTAssertEqual(data.items[0].title, "Edited today")
        try data.toggleSubtask(eventID: event.id, subtaskID: editedToday.subtasks[0].id, today: day(2026, 9, 6))
        XCTAssertTrue(data.items[0].subtasks[0].isCompleted)
        let quickTodayID = try data.addSubtask(to: event.id, text: "Quick today", today: day(2026, 9, 6))
        try data.editSubtask(eventID: event.id, subtaskID: quickTodayID, text: "Edited quick today", today: day(2026, 9, 6))
        try data.toggleSubtask(eventID: event.id, subtaskID: quickTodayID, today: day(2026, 9, 6))
        try data.deleteSubtask(eventID: event.id, subtaskID: quickTodayID, today: day(2026, 9, 6))
        XCTAssertFalse(data.items[0].subtasks.contains { $0.id == quickTodayID })

        var movedToPast = editedToday
        movedToPast.date = day(2026, 9, 5)
        XCTAssertThrowsError(try data.save(movedToPast, primary: true, today: day(2026, 9, 6)))
        var movedToFuture = editedToday
        movedToFuture.date = day(2026, 9, 9)
        try data.save(movedToFuture, primary: true, today: day(2026, 9, 6))
        XCTAssertEqual(data.items[0].date, day(2026, 9, 9))
        var futureMovedBackToToday = movedToFuture
        futureMovedBackToToday.date = day(2026, 9, 6)
        XCTAssertThrowsError(try data.save(futureMovedBackToToday, primary: true, today: day(2026, 9, 6)))

        // Restore today's date to verify expiry with an unfinished subtask.
        var lifecycle = CountdownData()
        try lifecycle.save(event, primary: true, today: day(2026, 9, 5))
        try lifecycle.save(later, primary: false, today: day(2026, 9, 5))
        lifecycle.normalize(today: day(2026, 9, 7))
        XCTAssertEqual(lifecycle.items, [later])
        XCTAssertEqual(lifecycle.primaryID, later.id)
    }

    func testStableOrderForSameDateAndPrimaryReplacement() throws {
        let today = day(2026, 9, 5)
        var data = CountdownData()
        var first = Countdown(title: "Zulu", date: day(2026, 9, 7), emoji: "1️⃣")
        let second = Countdown(title: "Alpha", date: day(2026, 9, 7), emoji: "2️⃣")
        let primary = Countdown(title: "Primary", date: day(2026, 9, 6), emoji: "3️⃣")
        try data.save(first, primary: false, today: today)
        try data.save(second, primary: false, today: today)
        try data.save(primary, primary: true, today: today)
        first.title = "Aardvark"
        try data.save(first, primary: false, today: today)
        XCTAssertEqual(data.items.map(\.id), [first.id, second.id, primary.id])
        data.normalize(today: day(2026, 9, 7))
        XCTAssertEqual(data.primaryID, first.id)
    }

    func testCalendarDaysAcrossDSTAndYear() {
        XCTAssertEqual(day(2026, 3, 9).days(from: day(2026, 3, 7), calendar: calendar), 2)
        XCTAssertEqual(day(2026, 11, 2).days(from: day(2026, 10, 31), calendar: calendar), 2)
        XCTAssertEqual(day(2027, 1, 1).days(from: day(2026, 12, 31), calendar: calendar), 1)
        XCTAssertEqual(day(2028, 3, 1).days(from: day(2028, 2, 28), calendar: calendar), 2)
    }

    func testPluralAndEmoji() {
        XCTAssertEqual([1, 2, 5, 11, 14, 21, 22, 111].map(dayLabel), ["1 день", "2 дня", "5 дней", "11 дней", "14 дней", "21 день", "22 дня", "111 дней"])
        XCTAssertEqual(countdownLabel(0), "Сегодня")
        XCTAssertEqual(countdownLabel(1), "1 день")
        for emoji in ["☀️", "🎉", "👨‍👩‍👧‍👦", "🇷🇺", "👍🏽", "1️⃣"] { XCTAssertTrue(CountdownData.isEmoji(emoji)) }
        for invalid in ["", "1", "ab", "🎉🎉"] { XCTAssertFalse(CountdownData.isEmoji(invalid)) }
    }

    func testRejectInvalidStoredDatesAndSubtasks() throws {
        let decoder = JSONDecoder()
        for json in [
            #"{"year":2026,"month":2,"day":31}"#,
            #"{"year":2026,"month":13,"day":1}"#,
            #"{"year":0,"month":1,"day":1}"#
        ] {
            XCTAssertThrowsError(try decoder.decode(Day.self, from: Data(json.utf8)))
        }

        let prefix = #"{"id":"28B1DD31-4671-4BD1-AB0D-3F6232967299","title":"Stored","date":{"year":2027,"month":5,"day":1},"emoji":"☀️","subtasks":"#
        let empty = #"[{"id":"18B1DD31-4671-4BD1-AB0D-3F6232967299","text":"   ","isCompleted":false}]}"#
        let tooLong = "[{\"id\":\"18B1DD31-4671-4BD1-AB0D-3F6232967299\",\"text\":\"\(String(repeating: "x", count: 51))\",\"isCompleted\":false}]}"
        let six = "[" + (1...6).map {
            #"{"id":"00000000-0000-0000-0000-00000000000\#($0)","text":"Task","isCompleted":false}"#
        }.joined(separator: ",") + "]}"
        for suffix in [empty, tooLong, six] {
            XCTAssertThrowsError(try decoder.decode(Countdown.self, from: Data((prefix + suffix).utf8)))
        }

        let tooMany = Countdown(
            title: "Too many",
            date: day(2027, 5, 1),
            emoji: "🎉",
            subtasks: try (1...6).map { try Subtask(text: "Task \($0)") }
        )
        XCTAssertThrowsError(try decoder.decode(Countdown.self, from: JSONEncoder().encode(tooMany)))
    }

    func testLegacyJSONMigrationAndNewModelRoundTrip() async throws {
        let eventID = "28B1DD31-4671-4BD1-AB0D-3F6232967299"
        let legacy = """
        {"items":[{"id":"\(eventID)","title":"Legacy","note":"Existing note","date":{"year":2027,"month":5,"day":1},"emoji":"☀️"}],"primaryID":"\(eventID)"}
        """
        let decoded = try JSONDecoder().decode(CountdownData.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.items[0].title, "Legacy")
        XCTAssertEqual(decoded.items[0].note, "Existing note")
        XCTAssertEqual(decoded.items[0].date, day(2027, 5, 1))
        XCTAssertEqual(decoded.items[0].emoji, "☀️")
        XCTAssertTrue(decoded.items[0].subtasks.isEmpty)
        XCTAssertEqual(decoded.primaryID, UUID(uuidString: eventID))

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountdownLegacyChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CountdownRepository(fileURL: directory.appendingPathComponent("countdowns.json"))
        XCTAssertTrue(try await repository.save(decoded, revision: 1))
        XCTAssertEqual(try await repository.load(), decoded)

        var modern = decoded
        modern.items[0].subtasks = [
            try Subtask(text: "Active"),
            try Subtask(text: "Completed", isCompleted: true)
        ]
        let roundTrip = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(modern))
        XCTAssertEqual(roundTrip, modern)

        let invalidURL = directory.appendingPathComponent("invalid-countdowns.json")
        var invalidData = CountdownData()
        invalidData.items = [Countdown(
            title: "Invalid stored model",
            date: day(2027, 5, 1),
            emoji: "🎉",
            subtasks: try (1...6).map { try Subtask(text: "Task \($0)") }
        )]
        let invalidBytes = try JSONEncoder().encode(invalidData)
        try invalidBytes.write(to: invalidURL)
        let invalidRepository = CountdownRepository(fileURL: invalidURL)
        do {
            _ = try await invalidRepository.load()
            fatalError("Invalid stored subtasks must fail to load")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: invalidURL), invalidBytes)

        let rejectedURL = directory.appendingPathComponent("rejected-save.json")
        let rejectingRepository = CountdownRepository(fileURL: rejectedURL)
        do {
            _ = try await rejectingRepository.save(invalidData, revision: 1)
            fatalError("Invalid subtasks must never enter persistence")
        } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: rejectedURL.path))
    }

    func testRepositoryRoundTripAndRevisionOrdering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountdownCoreChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CountdownRepository(fileURL: directory.appendingPathComponent("countdowns.json"))
        var newest = CountdownData()
        try newest.save(
            Countdown(title: "New", date: day(2026, 9, 7), emoji: "🎉", subtasks: [try Subtask(text: "Task")]),
            primary: true,
            today: day(2026, 9, 5)
        )
        let empty = CountdownData()

        XCTAssertTrue(try await repository.save(newest, revision: 2))
        XCTAssertFalse(try await repository.save(empty, revision: 1))
        XCTAssertEqual(try await repository.load(), newest)
    }
}

private func XCTAssertTrue(_ value: Bool) { precondition(value) }
private func XCTAssertFalse(_ value: Bool) { precondition(!value) }
private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "Unexpected: \(a) != \(b)") }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression(); fatalError("Expected validation error") } catch {}
}

@main enum CoreChecks {
    static func main() async throws {
        let checks = CountdownCoreTests()
        try checks.testCreationAndFieldValidation()
        try checks.testSubtaskLimitsNormalizationCompletionAndOrder()
        try checks.testAllSubtasksCompletedDoesNotFinishEvent()
        try checks.testCRUDPrimaryExpiryAndPersistence()
        try checks.testNoteBoundariesNormalizationAndRoundTrip()
        try checks.testTodayEditingAndLifecycleRegardlessOfSubtasks()
        try checks.testStableOrderForSameDateAndPrimaryReplacement()
        checks.testCalendarDaysAcrossDSTAndYear()
        checks.testPluralAndEmoji()
        try checks.testRejectInvalidStoredDatesAndSubtasks()
        try await checks.testLegacyJSONMigrationAndNewModelRoundTrip()
        try await checks.testRepositoryRoundTripAndRevisionOrdering()
        print("PASS unit: event validation, subtasks 0/1/5/6 and 50/51, trim, completion order, Today editing, expiry, stable event order, legacy/new JSON, repository revisions, calendar and emoji")
    }
}
