import Foundation
import CountdownCore

func testDayIdentityCompatibilityAndEdits() throws {
    let legacy = """
    {"id":"AB5812C9-198A-426D-B770-9305E836C738","title":"Пятница","date":{"year":2026,"month":11,"day":6},"emoji":""}
    """
    let decoder = JSONDecoder()
    let legacyEvent = try decoder.decode(Countdown.self, from: Data(legacy.utf8))
    precondition(!legacyEvent.isDay, "A weekday title alone must never imply day identity")
    guard var object = try JSONSerialization.jsonObject(with: Data(legacy.utf8)) as? [String: Any] else {
        preconditionFailure("Expected a JSON event object")
    }
    object["usesAutomaticTitle"] = true
    let automaticLegacy = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(automaticLegacy.isDay, "Only explicit legacy automatic-title metadata supplies the missing day marker")

    for marker in [false, true] {
        object["isDay"] = marker
        let event = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
        precondition(event.isDay == marker, "An explicit marker takes precedence over automatic title mode")
        let encoded = try JSONEncoder().encode(event)
        let roundTrip = try decoder.decode(Countdown.self, from: encoded)
        precondition(roundTrip == event)
        let encodedObject = try JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        precondition(encodedObject?["isDay"] as? Bool == marker, "False must also be encoded to keep ordinary automatic titles ordinary")
    }
    for invalid: Any in ["true", 1, NSNull(), [], [:]] {
        object["isDay"] = invalid
        do {
            _ = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
            preconditionFailure("Present day-origin metadata must be a Boolean")
        } catch is DecodingError {}
    }

    var renamed = automaticLegacy
    renamed.title = "Планы на выходные"
    renamed.usesAutomaticTitle = false
    renamed.date = weekCheckDay(2026, 11, 7)
    var data = CountdownData()
    try data.save(renamed, primary: false, today: weekCheckDay(2026, 11, 5))
    let restored = try decoder.decode(CountdownData.self, from: JSONEncoder().encode(data))
    precondition(restored.items[0].isDay && !restored.items[0].usesAutomaticTitle)
    precondition(restored.items[0].title == renamed.title && restored.items[0].date == renamed.date)
    precondition(restored.items[0].id == automaticLegacy.id, "Day identity follows the event through rename, date editing and JSON")
}

func testDayCreationWeekCalendarBoundaries() {
    for timeZoneID in ["UTC", "America/New_York", "Europe/Moscow"] {
        for firstWeekday in [1, 2] {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timeZoneID)!
            calendar.firstWeekday = firstWeekday
            for (offset, expectedCount) in [6, 5, 4, 3, 2, 1, 7].enumerated() {
                let today = weekCheckDay(2026, 11, 2 + offset)
                let week = requiredWeek(today: today, calendar: calendar)
                let expected = (0..<expectedCount).map { weekCheckDay(2026, 11, 3 + offset + $0) }
                precondition(week.referenceDay == today && week.days == expected)
                precondition(week.isNextWeek == (offset == 6))
                precondition(week.days.allSatisfy { $0 > today }, "Today must never be included")
                precondition(Set(week.days.map { "\($0.year)-\($0.month)-\($0.day)" }).count == expectedCount)
            }
            let boundaries: [(Day, [Day])] = [
                (weekCheckDay(2026, 12, 31), [weekCheckDay(2027, 1, 1), weekCheckDay(2027, 1, 2), weekCheckDay(2027, 1, 3)]),
                (weekCheckDay(2026, 4, 30), [weekCheckDay(2026, 5, 1), weekCheckDay(2026, 5, 2), weekCheckDay(2026, 5, 3)]),
                (weekCheckDay(2028, 2, 28), [weekCheckDay(2028, 2, 29), weekCheckDay(2028, 3, 1), weekCheckDay(2028, 3, 2),
                                           weekCheckDay(2028, 3, 3), weekCheckDay(2028, 3, 4), weekCheckDay(2028, 3, 5)]),
                (weekCheckDay(2026, 3, 7), [weekCheckDay(2026, 3, 8)]),
                (weekCheckDay(2026, 3, 8), (9...15).map { weekCheckDay(2026, 3, $0) }),
                (weekCheckDay(2026, 11, 1), (2...8).map { weekCheckDay(2026, 11, $0) }),
            ]
            for (today, expected) in boundaries {
                precondition(requiredWeek(today: today, calendar: calendar).days == expected,
                             "Week creation must use civil dates across year, leap-day and DST boundaries")
            }
            precondition(DayCreationWeek(today: weekCheckDay(9999, 12, 31), calendar: calendar) == nil,
                         "A week outside the supported stored-date range must fail rather than return a partial batch")
        }
    }
}

func testDayCreationWeekDeduplicationAndDefaults() throws {
    let today = weekCheckDay(2026, 11, 5)
    let friday = weekCheckDay(2026, 11, 6)
    let saturday = weekCheckDay(2026, 11, 7)
    let sunday = weekCheckDay(2026, 11, 8)
    let ordinary = Countdown(title: "Стоматолог", note: "Не менять", date: friday, emoji: "", keepsAfterDate: true)
    let weekdayText = Countdown(title: "Пятница", date: friday, emoji: "")
    var renamedDay = Countdown(title: "Мои планы", date: saturday, emoji: "", subtasks: [try Subtask(text: "Сохранить задачу", isCompleted: true)])
    renamedDay.isDay = true
    var data = CountdownData()
    try data.save(ordinary, primary: true, today: today)
    try data.save(weekdayText, primary: false, today: today)
    try data.save(renamedDay, primary: false, today: today)
    let baseline = data
    let week = requiredWeek(today: today)
    let created = try data.createMissingDays(in: week, today: today)
    precondition(created.map(\.date) == [sunday], "Every occupied date must block batch creation, including ordinary events")
    precondition(created.map(\.title) == ["Воскресенье"])
    precondition(Array(data.items.prefix(3)) == baseline.items && data.primaryID == ordinary.id)
    precondition(data.items.count == 4 && Set(data.items.map(\.id)).count == 4)
    for day in created {
        precondition(day.isDay && day.usesAutomaticTitle && day.showsWeather)
        precondition(!day.keepsAfterDate && day.emoji.isEmpty && day.subtasks.isEmpty)
        precondition((day.note ?? "").isEmpty && day.attachments.isEmpty && day.links.isEmpty)
    }
    let completed = data
    let repeated = try data.createMissingDays(in: week, today: today)
    precondition(repeated.isEmpty)
    precondition(data == completed, "Repeating a completed batch must not change IDs, content, ordering or favorite")

    do {
        _ = try data.createMissingDays(in: week, today: friday)
        preconditionFailure("A preview from another civil day must be reviewed again")
    } catch CountdownError.date {}
    precondition(data == completed, "Rejecting a stale preview must preserve the entire existing snapshot")
}

func testWeekCreationSkipsExistingAutomaticTitle() throws {
    let today = weekCheckDay(2026, 11, 8)
    let monday = weekCheckDay(2026, 11, 9)
    let friday = weekCheckDay(2026, 11, 13)
    let automatic = Countdown(
        title: "Понедельник", note: "Сохранить планы", date: monday, emoji: "",
        subtasks: [try Subtask(text: "Первая задача", isCompleted: true),
                   try Subtask(text: "Вторая задача"), try Subtask(text: "Третья задача")],
        usesAutomaticTitle: true, isDay: false
    )
    let ordinary = Countdown(title: "Встреча", date: monday, emoji: "")
    let existingFriday = Countdown(title: "Планы на пятницу", date: friday, emoji: "", isDay: true)
    let ordinarySunday = Countdown(title: "Поездка", date: weekCheckDay(2026, 11, 15), emoji: "")
    var data = CountdownData()
    data.items = [ordinary, automatic, existingFriday, ordinarySunday]
    data.primaryID = automatic.id
    let baseline = data
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let baselineBytes = try encoder.encode(data)
    data = try JSONDecoder().decode(CountdownData.self, from: baselineBytes)
    precondition(data.items[1].usesAutomaticTitle && !data.items[1].isDay,
                 "The saved automatic-title event must retain its explicit false origin marker")

    let created = try data.createMissingDays(in: requiredWeek(today: today), today: today)
    precondition(created.map(\.date) == [10, 11, 12, 14].map { weekCheckDay(2026, 11, $0) },
                 "Sunday creation must skip the existing Monday, Friday and ordinary Sunday")
    precondition(Array(data.items.prefix(4)) == baseline.items && data.primaryID == automatic.id,
                 "Skipping the existing Monday must preserve its tasks, note, flags, identity and favorite")
    precondition(data.items.filter { $0.date == monday }.count == 2,
                 "The existing ordinary meeting and automatic Monday must not gain a duplicate day")
    let completedBytes = try encoder.encode(data)
    var restored = try JSONDecoder().decode(CountdownData.self, from: completedBytes)
    let repeated = try restored.createMissingDays(in: requiredWeek(today: today), today: today)
    precondition(repeated.isEmpty && restored == data)
    let repeatedBytes = try encoder.encode(restored)
    precondition(repeatedBytes == completedBytes)

    var otherDates = CountdownData()
    otherDates.items = [Countdown(title: "Другой месяц", date: weekCheckDay(2026, 12, 9), emoji: ""),
                        Countdown(title: "Другой год", date: weekCheckDay(2027, 11, 9), emoji: "")]
    let retained = otherDates.items
    let fullWeek = try otherDates.createMissingDays(in: requiredWeek(today: today), today: today)
    precondition(fullWeek.map(\.date) == requiredWeek(today: today).days && Array(otherDates.items.prefix(2)) == retained,
                 "Date matching must compare year, month and day together")
    print("PASS week date deduplication: existing ordinary and automatic events, three preserved tasks, four missing dates and zero-change repeat")
}

func testDayCreationWeekRepositoryRestart() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownWeekCore-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let today = weekCheckDay(2026, 11, 8)
    let week = requiredWeek(today: today)
    var data = CountdownData()
    let created = try data.createMissingDays(in: week, today: today)
    precondition(created.count == 7 && data.primaryID == nil)
    let repository = CountdownRepository(fileURL: fileURL)
    let didSave = try await repository.save(data, revision: 1)
    precondition(didSave)
    var restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(restored == data && restored.items.allSatisfy(\.isDay))
    let repeated = try restored.createMissingDays(in: week, today: today)
    precondition(repeated.isEmpty)
    precondition(restored == data, "A fresh repository must preserve duplicate protection")
    print("PASS week core: explicit day identity/legacy metadata, seven weekday ranges, Sunday next week, locale/time-zone/DST/year boundaries, defaults, same-date ordinary events, stable renamed days and repository restart")
}

private func requiredWeek(today: Day, calendar: Calendar = Day.calendar) -> DayCreationWeek {
    guard let week = DayCreationWeek(today: today, calendar: calendar) else {
        preconditionFailure("Expected a supported civil week in the fixture")
    }
    return week
}

private func weekCheckDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return Day(calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar)
}
