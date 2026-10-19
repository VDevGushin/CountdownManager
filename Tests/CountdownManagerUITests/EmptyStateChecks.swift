import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testEmptyEventList(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "local.countdownmanager.empty-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var clock = Day.calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 23, minute: 59, second: 59))!
    let file = directory.appendingPathComponent("events.json")
    let store = Store(fileURL: file, disclosureDefaults: defaults, now: { clock },
                      loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    precondition(!store.showsEmptyEventList && !store.eventCreationIsAvailable, "Loading is not a successful empty list")
    while store.isLoading { await Task.yield() }
    precondition(store.showsEmptyEventList && store.eventCreationIsAvailable)
    precondition(!FileManager.default.fileExists(atPath: file.path))
    let today = Day(clock)
    let draft = EventEditorDraft(item: nil)
    precondition(draft.title.isEmpty && draft.note.isEmpty && draft.emoji.isEmpty && draft.subtasks.isEmpty && !draft.showsWeather)
    precondition(!editorCanSave(title: draft.title, note: draft.note, date: today, emoji: draft.emoji, today: today))
    let event = Countdown(title: "First ordinary event", date: today, emoji: "")
    let saved = await store.save(event, primary: false)
    precondition(saved && !store.showsEmptyEventList && store.data.primaryID == nil)
    clock = clock.addingTimeInterval(2)
    store.refresh()
    precondition(store.showsEmptyEventList, "Expiring the last event restores empty state")
    let staleSaved = await store.save(event, primary: false)
    precondition(!staleSaved && store.showsEmptyEventList, "Midnight cannot save a stale today draft")

    let corruptFile = directory.appendingPathComponent("corrupt.json")
    let bytes = Data("invalid JSON: preserve me".utf8)
    try bytes.write(to: corruptFile)
    let failed = Store(fileURL: corruptFile, disclosureDefaults: defaults,
                       loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    while failed.isLoading { await Task.yield() }
    precondition(!failed.eventCreationIsAvailable && !failed.showsEmptyEventList,
                 "A failed read must not expose empty-state creation")
    let preserved = try Data(contentsOf: corruptFile)
    precondition(preserved == bytes)
}
