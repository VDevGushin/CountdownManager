import Foundation
import CountdownCore

func testAutomaticTitleLegacyAndJSONCompatibility() throws {
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let legacyJSON = """
    {"items":[{"id":"28B1DD31-4671-4BD1-AB0D-3F6232967299","title":"Понедельник","date":{"year":2026,"month":10,"day":20},"emoji":""}]}
    """
    let legacy = try decoder.decode(CountdownData.self, from: Data(legacyJSON.utf8))
    precondition(!legacy.items[0].usesAutomaticTitle, "Legacy weekday text must never imply an automatic title")
    precondition(legacy.items[0].title == "Понедельник")
    let legacyEncoded = try JSONSerialization.jsonObject(with: encoder.encode(legacy.items[0])) as? [String: Any]
    precondition(legacyEncoded?["usesAutomaticTitle"] == nil, "Manual titles retain the legacy JSON shape")
    precondition(legacyEncoded?["title"] as? String == "Понедельник", "The plain title remains backward compatible")

    var automatic = legacy.items[0]
    automatic.usesAutomaticTitle = true
    let encoded = try encoder.encode(automatic)
    let decoded = try decoder.decode(Countdown.self, from: encoded)
    precondition(decoded == automatic && decoded.usesAutomaticTitle)
    guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        preconditionFailure("Expected the encoded event object")
    }
    precondition(object["usesAutomaticTitle"] as? Bool == true)
    precondition(object["title"] as? String == automatic.title)
    for value: Any in ["true", 1, NSNull(), [], [:]] {
        object["usesAutomaticTitle"] = value
        do {
            _ = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
            preconditionFailure("Present automatic-title metadata must be a Boolean")
        } catch is DecodingError {}
    }
    object["usesAutomaticTitle"] = false
    let explicitManual = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(!explicitManual.usesAutomaticTitle && explicitManual.title == automatic.title)
    let manualEncoded = try JSONSerialization.jsonObject(with: encoder.encode(explicitManual)) as? [String: Any]
    precondition(manualEncoded?["usesAutomaticTitle"] == nil)
}

func testAutomaticTitleCanonicalSaveAndDateBoundaries() throws {
    let calendarDays: [(Int, Int, Int, String)] = [
        (2026, 10, 19, "Понедельник"), (2026, 10, 20, "Вторник"), (2026, 10, 21, "Среда"),
        (2026, 10, 22, "Четверг"), (2026, 10, 23, "Пятница"), (2026, 10, 24, "Суббота"),
        (2026, 10, 25, "Воскресенье"), (2027, 1, 1, "Пятница"),
        (2027, 3, 14, "Воскресенье"), (2027, 11, 7, "Воскресенье"), (2028, 2, 29, "Вторник")
    ]
    let today = automaticTitleDay(2026, 10, 19)
    let task = try Subtask(text: "Keep identity", isCompleted: true)
    var candidate = Countdown(
        title: "", note: "Keep note", date: today, emoji: "🎉", subtasks: [task],
        showsWeather: true, usesAutomaticTitle: true
    )
    let neighbor = Countdown(title: "Neighbor", date: automaticTitleDay(2028, 3, 1), emoji: "")
    var data = CountdownData()
    try data.save(neighbor, primary: false, today: today)
    for (year, month, day, title) in calendarDays {
        candidate.date = automaticTitleDay(year, month, day)
        candidate.title = "Stale text from the previous date"
        try data.save(candidate, primary: true, today: today)
        let saved = data.items[1]
        precondition(automaticEventTitle(for: candidate.date) == title)
        precondition(saved.title == title && saved.usesAutomaticTitle && saved.id == candidate.id)
        precondition(saved.date == candidate.date && saved.note == candidate.note && saved.emoji == candidate.emoji)
        precondition(saved.subtasks == [task] && saved.showsWeather && data.primaryID == candidate.id)
        precondition(data.items[0] == neighbor, "Automatic renaming must not reorder or edit neighboring events")
    }

    let beforeRejectedSave = data
    candidate.date = automaticTitleDay(2026, 10, 18)
    do {
        try data.save(candidate, primary: false, today: today)
        preconditionFailure("Automatic titles must not bypass the past-date guard")
    } catch CountdownError.date {}
    precondition(data == beforeRejectedSave)

    candidate = data.items[1]
    candidate.usesAutomaticTitle = false
    candidate.title = "  Понедельник  "
    candidate.date = automaticTitleDay(2028, 3, 1)
    try data.save(candidate, primary: false, today: today)
    precondition(data.items[1].title == "Понедельник" && !data.items[1].usesAutomaticTitle)
    precondition(data.primaryID == nil, "Switching to a manual title still follows the explicit favorite choice")
    data.normalize(today: automaticTitleDay(2028, 3, 1))
    precondition(data.items[1].title == "Понедельник", "Midnight and normalization never rename a manual title")
    try verifyAutomaticTitleValidationAndExpiry()
}

private func verifyAutomaticTitleValidationAndExpiry() throws {
    let today = automaticTitleDay(2026, 10, 19)
    let eventDay = automaticTitleDay(2026, 10, 22)
    let event = Countdown(
        title: "", note: "Keep note", date: eventDay, emoji: "", subtasks: [try Subtask(text: "Unfinished")],
        usesAutomaticTitle: true
    )
    let survivor = Countdown(title: "Survivor", date: automaticTitleDay(2026, 10, 23), emoji: "")
    var data = CountdownData()
    try data.save(event, primary: true, today: today)
    try data.save(survivor, primary: false, today: today)
    let baseline = data
    precondition(baseline.items[0].title == "Четверг" && !baseline.items[0].showsWeather)

    var invalidCandidates: [Countdown] = []
    var invalid = event
    invalid.note = String(repeating: "🙂", count: 151)
    invalidCandidates.append(invalid)
    invalid = event
    invalid.emoji = "not an emoji"
    invalidCandidates.append(invalid)
    invalid = event
    invalid.subtasks[0].text = " \n "
    invalidCandidates.append(invalid)
    invalid = event
    invalid.subtasks[0].text = String(repeating: "я", count: 51)
    invalidCandidates.append(invalid)
    invalid = event
    invalid.subtasks = try (1...11).map { try Subtask(text: "Task \($0)") }
    invalidCandidates.append(invalid)
    for candidate in invalidCandidates {
        do {
            try data.save(candidate, primary: false, today: today)
            preconditionFailure("Canonical automatic titles must not bypass other event validation")
        } catch is CountdownError {}
        precondition(data == baseline, "A rejected automatic edit must preserve content, mode, date and favorite")
    }

    data.normalize(today: automaticTitleDay(2026, 10, 21))
    precondition(data == baseline, "Advancing the current day must not rename or reschedule a future automatic event")
    data.normalize(today: eventDay)
    precondition(data == baseline, "Today's automatic event remains unchanged, including unfinished subtasks")
    data.normalize(today: automaticTitleDay(2026, 10, 23))
    precondition(data.items == [survivor] && data.primaryID == nil,
                 "An automatic event expires by its own civil date without rolling forward")
    data.normalize(today: today)
    precondition(data.items == [survivor] && data.primaryID == nil,
                 "Moving the current day backward must not resurrect an expired automatic event")
}

func testAutomaticTitleRepositorySnapshotsAndRestart() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CountdownAutomaticTitleChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    let today = automaticTitleDay(2026, 10, 19)
    let automatic = Countdown(title: "", date: today, emoji: "", usesAutomaticTitle: true)
    var first = CountdownData()
    try first.save(automatic, primary: false, today: today)
    expectAutomaticTitle(try await repository.save(first, revision: 1))

    var latest = first
    var moved = latest.items[0]
    moved.date = automaticTitleDay(2026, 10, 20)
    try latest.save(moved, primary: true, today: today)
    expectAutomaticTitle(try await repository.save(latest, revision: 2))
    expectAutomaticTitle(!(try await repository.save(first, revision: 1)))
    let restarted = CountdownRepository(fileURL: fileURL)
    let restored = try await restarted.load()
    precondition(restored == latest && restored.items[0].usesAutomaticTitle && restored.items[0].title == "Вторник")

    moved = restored.items[0]
    moved.usesAutomaticTitle = false
    moved.title = "Мой вторник"
    moved.date = automaticTitleDay(2026, 10, 21)
    try latest.save(moved, primary: true, today: today)
    expectAutomaticTitle(try await repository.save(latest, revision: 3))
    expectAutomaticTitle(!(try await repository.save(restored, revision: 2)))
    let final = try await CountdownRepository(fileURL: fileURL).load()
    precondition(final == latest && !final.items[0].usesAutomaticTitle && final.items[0].title == "Мой вторник")
    let encoded = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
    let items = encoded?["items"] as? [[String: Any]]
    precondition(items?.first?["usesAutomaticTitle"] == nil)
    print("PASS automatic titles: legacy compatibility, strict metadata, canonical date boundaries, validation guards, expiry without rollover, revision snapshots and restart")
}

private func automaticTitleDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return Day(calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar)
}

private func expectAutomaticTitle(_ value: Bool) { precondition(value) }
