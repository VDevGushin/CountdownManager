import Combine
import CountdownCore
import CountdownManagerUI
import Foundation

func testEnglishLocalization() throws {
    precondition(AppText.language == .english)
    precondition(AppText.string("app.menu.checkForUpdates") == "Check for Updates…")
    precondition(AppText.string("attachment.preview.position", "2", "5") == "2 of 5")
    precondition(attachmentSizeLabel(42) == "42 bytes")
    precondition(attachmentSizeLabel(123_456_789) == "123.5 MB")
    let forecast = DailyWeatherForecast(weatherCode: 0, maximumTemperature: 13.7)!
    precondition(forecast.temperatureLabel == "+14°")
    precondition(forecast.accessibilityDescription == "Clear. Daily high in Celsius: 14.")
    let oneDegree = DailyWeatherForecast(weatherCode: 0, maximumTemperature: 1)!
    precondition(oneDegree.accessibilityDescription == "Clear. Daily high in Celsius: 1.")
    for count in [0, 2, 11, 21, 101] {
        precondition(dayLabel(count) == "\(count) days")
        precondition(eventCountLabel(count) == "\(count) events")
    }
    precondition(dayLabel(1) == "1 day" && eventCountLabel(1) == "1 event")
    precondition(relativeCountdownLabel(-2) == "2 days ago")
    precondition(relativeCountdownLabel(0) == "Today" && relativeCountdownLabel(1) == "Tomorrow")
    precondition(relativeCountdownLabel(21) == "In 21 days")

    let day = Day(Day.calendar.date(from: DateComponents(year: 2026, month: 10, day: 16))!)
    precondition(currentDayHeaderLabel(day) == "Fri, October 16")
    precondition(humanDateLabel(day) == "October 16, 2026")
    precondition(humanDateLabel(day, includesYear: false) == "October 16")
    precondition(CalendarDateTilePresentation(day: day).monthLabel == "OCT")
    precondition(EventEditorDraft(day: day).title == "Friday")

    let legacyTitle = "Пятница"
    let automatic = Countdown(title: legacyTitle, date: day, emoji: "", usesAutomaticTitle: true)
    let custom = Countdown(title: legacyTitle, date: day, emoji: "")
    var data = CountdownData()
    try data.save(automatic, primary: false, today: day)
    try data.save(custom, primary: false, today: day)
    let reopened = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
    precondition(reopened.items.allSatisfy { $0.title == legacyTitle })
    let originals = reopened.items.filter { $0.usesAutomaticTitle }
    precondition(originals.map(\.displayTitle) == ["Friday"])
    precondition(EventEditorDraft(item: originals.first).title == "Friday")
    let collection = DesktopEventCollection(items: reopened.items, today: day, primaryID: nil, query: "friday")
    precondition(collection.events.map(\.id) == [automatic.id])
    precondition(collection.monthSections.first?.title == "October 2026")
    let customSearch = DesktopEventCollection(items: reopened.items, today: day, primaryID: nil, query: legacyTitle)
    precondition(customSearch.events.map(\.id) == [custom.id])
    try testEnglishAutomaticDayCreation(today: day)
    print("PASS English localization: dates, counts, sizes, automatic titles after Save/transfer/week, editor and search")
}

@MainActor
func testLocalizedStoreFailures() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownLocalizedErrors-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let suiteName = "local.countdownmanager.localized-errors.\(folder.lastPathComponent)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let unreadable = folder.appendingPathComponent("Unreadable.json")
    try FileManager.default.createDirectory(at: unreadable, withIntermediateDirectories: false)
    let cannotRead = Store(fileURL: unreadable, disclosureDefaults: defaults, loginItemManagementIsAvailable: false,
                          diagnosticRecord: { _ in })
    while cannotRead.isLoading { await Task.yield() }
    precondition(cannotRead.error == AppText.string("store.storageReadFailed", unreadable.path))

    let writeURL = folder.appendingPathComponent("Write.json")
    let now = Date()
    let writer = Store(fileURL: writeURL, disclosureDefaults: defaults,
                       persistenceSaveOverride: { _, _ in
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                      userInfo: [NSLocalizedDescriptionKey: "A system description in another language"])
    }, now: { now }, loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    while writer.isLoading { await Task.yield() }
    let event = Countdown(title: "Isolated event", date: Day(now), emoji: "")
    let saved = await writer.save(event, primary: false)
    precondition(!saved && writer.error == AppText.string("store.storageWriteFailed"))
    precondition(!FileManager.default.fileExists(atPath: writeURL.path))
    print("PASS localized storage failures: localized messages, failed read and write, no system error copy in banners")
}

private func testEnglishAutomaticDayCreation(today: Day) throws {
    let task = try Subtask(text: "Move to Saturday")
    let source = Countdown(title: "Source", date: today, emoji: "", subtasks: [task])
    let week = DayCreationWeek(today: today)!
    precondition(week.days.count == 2)

    var data = CountdownData()
    try data.save(source, primary: false, today: today)
    let destination = try data.transferSubtask(from: source.id, subtaskID: task.id,
                                               to: nil, on: week.days[0], today: today)
    precondition(destination.title == "Суббота" && destination.displayTitle == "Saturday")
    let created = try data.createMissingDays(in: week, today: today)
    precondition(created.map(\.title) == ["Воскресенье"] && created.map(\.displayTitle) == ["Sunday"])
    let reopened = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
    precondition(reopened.items == [data.items[0], destination] + created)
    precondition(reopened.items[0].subtasks.isEmpty && reopened.items[1].subtasks == [task])
}

@MainActor
func testCurrentDayHeaderDate() async throws {
    try testApplicationVersionLabel()
    precondition(attachmentSizeLabel(42) == "42 байта")
    let fileSize = attachmentSizeLabel(123_456_789)
    precondition(fileSize.hasPrefix("123,5") && fileSize.hasSuffix("МБ"))
    let countCases = [
        (0, "0 событий"), (1, "1 событие"), (2, "2 события"), (3, "3 события"),
        (4, "4 события"), (5, "5 событий"), (10, "10 событий"), (11, "11 событий"),
        (12, "12 событий"), (14, "14 событий"), (20, "20 событий"), (21, "21 событие"),
        (22, "22 события"), (25, "25 событий"), (101, "101 событие"), (111, "111 событий"),
        (114, "114 событий"), (121, "121 событие"),
    ]
    for (count, expected) in countCases { precondition(eventCountLabel(count) == expected) }
    let calendar = Day.calendar
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 59, second: 59))!
    let label = currentDayHeaderLabel(Day(date))
    precondition(label == "Ср, 14 октября" && !label.contains("2026"))
    precondition(humanDateLabel(Day(date), includesYear: false) == "14 октября")
    let next = currentDayHeaderLabel(Day(date.addingTimeInterval(2)))
    precondition(next == "Чт, 15 октября")
    let yearEnd = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31))!
    precondition(currentDayHeaderLabel(Day(yearEnd)) == "Чт, 31 декабря")
    precondition(currentDayHeaderLabel(Day(calendar.date(byAdding: .day, value: 1, to: yearEnd)!)) == "Пт, 1 января")
    let leapDay = calendar.date(from: DateComponents(year: 2024, month: 2, day: 29))!
    precondition(currentDayHeaderLabel(Day(leapDay)) == "Чт, 29 февраля")
    precondition(currentDayHeaderLabel(Day(calendar.date(byAdding: .day, value: 1, to: leapDay)!)) == "Пт, 1 марта")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownHeader-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let suite = "local.countdownmanager.header-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var clock = date
    let store = Store(fileURL: directory.appendingPathComponent("events.json"), disclosureDefaults: defaults,
                      now: { clock }, loginItemManagementIsAvailable: false)
    for _ in 0..<1_000 {
        if !store.isLoading { break }
        await Task.yield()
    }
    precondition(!store.isLoading)
    var publications = 0
    let observation = store.objectWillChange.sink { publications += 1 }
    defer { observation.cancel() }
    clock = clock.addingTimeInterval(2)
    store.refresh()
    precondition(publications > 0 && currentDayHeaderLabel(Day(clock)) == next)
}

private func testApplicationVersionLabel() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownVersion-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    for (index, version) in ["1.9.0", "1.10.0", ""].enumerated() {
        let path = root.appendingPathComponent("\(index).bundle")
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "local.countdownmanager.app", "CFBundleShortVersionString": version]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            .write(to: path.appendingPathComponent("Info.plist"))
        let bundle = Bundle(path: path.path)!
        precondition(applicationVersionLabel(bundle: bundle) == (version.isEmpty ? nil : "Версия \(version)"))
    }
}
