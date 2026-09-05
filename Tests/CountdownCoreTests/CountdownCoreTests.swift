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
    func testRejectTodayPastBlankAndInvalidEmoji() throws {
        var data = CountdownData()
        for date in [day(2026, 9, 4), day(2026, 9, 5)] {
            XCTAssertThrowsError(try data.save(Countdown(title: "Test", date: date, emoji: "🎉"), primary: false, today: day(2026, 9, 5)))
        }
        XCTAssertThrowsError(try data.save(Countdown(title: "  ", date: day(2026, 9, 6), emoji: "🎉"), primary: false, today: day(2026, 9, 5)))
        XCTAssertThrowsError(try data.save(Countdown(title: "Test", date: day(2026, 9, 6), emoji: "abc"), primary: false, today: day(2026, 9, 5)))
        XCTAssertThrowsError(try data.save(Countdown(title: "Test", note: String(repeating: "x", count: 281), date: day(2026, 9, 6), emoji: "🎉"), primary: false, today: day(2026, 9, 5)))
        XCTAssertTrue(data.items.isEmpty)
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

        let decoded = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
        XCTAssertEqual(decoded, data)
    }

    func testTodayLifecycleAndPrimaryReplacement() throws {
        let event = Countdown(title: "Today", note: "Visible all day", date: day(2026, 9, 6), emoji: "☀️")
        let later = Countdown(title: "Later", date: day(2026, 9, 8), emoji: "🚀")
        var data = CountdownData()
        try data.save(event, primary: true, today: day(2026, 9, 5))
        try data.save(later, primary: false, today: day(2026, 9, 5))

        data.normalize(today: day(2026, 9, 6))
        XCTAssertEqual(data.items.count, 2)
        XCTAssertEqual(data.primaryID, event.id)
        XCTAssertEqual(countdownLabel(event.date.days(from: day(2026, 9, 6), calendar: calendar)), "Сегодня")

        data.normalize(today: day(2026, 9, 7))
        XCTAssertEqual(data.items, [later])
        XCTAssertEqual(data.primaryID, later.id)
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

    func testRejectInvalidStoredDates() {
        let decoder = JSONDecoder()
        for json in [
            #"{"year":2026,"month":2,"day":31}"#,
            #"{"year":2026,"month":13,"day":1}"#,
            #"{"year":0,"month":1,"day":1}"#
        ] {
            XCTAssertThrowsError(try decoder.decode(Day.self, from: Data(json.utf8)))
        }
    }

    func testDecodeLegacyCountdownWithoutNote() throws {
        let json = #"{"id":"28B1DD31-4671-4BD1-AB0D-3F6232967299","title":"Legacy","date":{"year":2027,"month":5,"day":1},"emoji":"☀️"}"#
        let decoded = try JSONDecoder().decode(Countdown.self, from: Data(json.utf8))
        XCTAssertNil(decoded.note)
    }

    func testRepositoryRoundTripAndRevisionOrdering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountdownCoreChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CountdownRepository(fileURL: directory.appendingPathComponent("countdowns.json"))
        var newest = CountdownData()
        try newest.save(
            Countdown(title: "New", date: day(2026, 9, 7), emoji: "🎉"),
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
        try checks.testRejectTodayPastBlankAndInvalidEmoji()
        try checks.testCRUDPrimaryExpiryAndPersistence()
        try checks.testNoteBoundariesNormalizationAndRoundTrip()
        try checks.testTodayLifecycleAndPrimaryReplacement()
        checks.testCalendarDaysAcrossDSTAndYear()
        checks.testPluralAndEmoji()
        checks.testRejectInvalidStoredDates()
        try checks.testDecodeLegacyCountdownWithoutNote()
        try await checks.testRepositoryRoundTripAndRevisionOrdering()
        print("PASS unit: validation, note boundaries and normalization, legacy JSON, today lifecycle, CRUD, primary selection, expiry, invalid dates, repository revisions, DST, leap year, plural forms, emoji")
    }
}
