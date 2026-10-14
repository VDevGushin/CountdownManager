import Combine
import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testCurrentDayHeaderDate() async throws {
    try testApplicationVersionLabel()
    let calendar = Day.calendar
    let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 23, minute: 59, second: 59))!
    let label = currentDayHeaderLabel(Day(date))
    precondition(label == "Ср, 14 октября" && !label.contains("2026"))
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
