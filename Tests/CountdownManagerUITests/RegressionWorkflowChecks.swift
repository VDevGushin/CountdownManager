import Foundation
import CountdownCore
import CountdownManagerUI

@MainActor
func testRegressionWorkflows(in directory: URL) async throws {
    let suite = "CountdownManagerRegressionWorkflows.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try await testEditedEventSurvivesReload(in: directory.appendingPathComponent("edit"), defaults: defaults)
    try await testRejectedAndFailedEditsCanBeRetried(in: directory.appendingPathComponent("retry"), defaults: defaults)
    try await testChecklistRemovalCleansOnlyDurablePreferences(
        in: directory.appendingPathComponent("checklist"), defaults: defaults
    )
    try await testExpiryCleanupRetriesAfterWriteFailure(in: directory.appendingPathComponent("expiry"), defaults: defaults)
    try await testRepeatedChecklistDraftEditsCancelAndSave(
        in: directory.appendingPathComponent("draft-cycles"), defaults: defaults
    )
    try testThursdayDayDraftDateChanges()
    print("PASS regression workflows: edited event reload/identity, rejected and failed edit retry, durable checklist preference cleanup, failed midnight normalization retry")
    print("PASS editor draft regression: repeated remove/add and neighbor edits, empty-row Save validation, discard/reopen and durable Save; Thursday/Friday boundary titles and manual override")
}

@MainActor
private func testEditedEventSurvivesReload(in directory: URL, defaults: UserDefaults) async throws {
    let today = Day(Date())
    let now = today.date()
    let date = workflowDay(2, after: today)
    let original = Countdown(
        title: "Original", note: "First line\nSecond line", date: date, emoji: "🚀",
        subtasks: [try Subtask(text: "Done", isCompleted: true), try Subtask(text: "Keep active")]
    )
    let neighbor = Countdown(title: "Neighbor", date: date, emoji: "☀️")
    var initial = CountdownData()
    try initial.save(original, primary: true, today: today)
    try initial.save(neighbor, primary: false, today: today)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(initial, revision: 0)
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(store)

    var draft = EventEditorDraft(item: original)
    draft.title = "Renamed"
    draft.note = "Edited first line\nEdited second line"
    draft.clearEmoji()
    draft.subtasks[0].text = "Done renamed"
    draft.subtasks.remove(at: 1)
    draft.addSubtask()
    draft.subtasks[1].text = "Replacement"
    let expected = draft.countdown(id: original.id, date: date)
    let didSave = await store.save(expected, primary: false, requireExisting: true)
    precondition(didSave, "An existing event must remain saveable after editing several fields")
    precondition(store.data.items == [expected, neighbor] && store.data.primaryID == nil)
    precondition(expected.subtasks[0].id == original.subtasks[0].id && expected.subtasks[0].isCompleted)
    precondition(expected.subtasks[1].id != original.subtasks[1].id && !expected.subtasks[1].isCompleted)
    let disk = try await repository.load()
    precondition(disk == store.data, "The persisted edit must match the visible event")

    let restored = Store(
        fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(restored)
    precondition(restored.data == disk)
    precondition(activeCountdowns(in: restored.data, today: today).map(\.id) == [original.id, neighbor.id])
    let row = CountdownRowPresentation(item: restored.data.items[0], today: today, primaryID: restored.data.primaryID)
    precondition(row.activeSubtasks.map(\.id) == [expected.subtasks[1].id])
    precondition(row.completedSubtasks.map(\.id) == [original.subtasks[0].id] && row.completionLabel == "1/2")
}

@MainActor
private func testRejectedAndFailedEditsCanBeRetried(in directory: URL, defaults: UserDefaults) async throws {
    let today = Day(Date())
    let now = today.date()
    let original = Countdown(
        title: "Original", note: "Keep this", date: workflowDay(1, after: today), emoji: "✈️",
        subtasks: [try Subtask(text: "Keep identity", isCompleted: true)]
    )
    var initial = CountdownData()
    try initial.save(original, primary: true, today: today)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(initial, revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var writes = 0
    var rejectWrite = true
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            writes += 1
            if rejectWrite { throw WorkflowWriteFailure() }
            return try await repository.save(data, revision: revision)
        }, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(store)
    var draft = EventEditorDraft(item: original)
    draft.title = "   "
    let rejected = await store.save(draft.countdown(id: original.id, date: original.date), primary: false, requireExisting: true)
    precondition(!rejected && writes == 0 && store.data == initial)
    let afterValidation = try Data(contentsOf: fileURL)
    precondition(afterValidation == originalBytes, "Validation failure must leave the file byte-for-byte intact")

    draft.title = "Retry me"
    draft.note = "The draft stays available"
    let edited = draft.countdown(id: original.id, date: original.date)
    let failed = await store.save(edited, primary: false, requireExisting: true)
    precondition(!failed && writes == 1 && store.data == initial)
    precondition(!store.hasPendingPersistence)
    let afterFailedWrite = try Data(contentsOf: fileURL)
    precondition(afterFailedWrite == originalBytes, "A failed write must preserve the durable original")

    rejectWrite = false
    let retried = await store.save(edited, primary: false, requireExisting: true)
    precondition(retried && writes == 2 && store.data.items == [edited] && store.data.primaryID == nil)
    let disk = try await repository.load()
    precondition(disk == store.data && disk.items[0].subtasks == original.subtasks)
}

@MainActor
private func testChecklistRemovalCleansOnlyDurablePreferences(in directory: URL, defaults: UserDefaults) async throws {
    let today = Day(Date())
    let now = today.date()
    let first = Countdown(
        title: "First", date: workflowDay(1, after: today), emoji: "",
        subtasks: [try Subtask(text: "Last task")]
    )
    let second = Countdown(
        title: "Second", date: workflowDay(2, after: today), emoji: "",
        subtasks: [try Subtask(text: "Other task")]
    )
    var initial = CountdownData()
    try initial.save(first, primary: false, today: today)
    try initial.save(second, primary: false, today: today)
    let preferences = SubtaskDisclosurePersistence(defaults: defaults)
    preferences.setExpanded(false, eventID: first.id)
    preferences.setExpanded(false, eventID: second.id)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(initial, revision: 0)
    var rejectWrite = true
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            if rejectWrite { throw WorkflowWriteFailure() }
            return try await repository.save(data, revision: revision)
        }, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(store)
    var withoutTasks = first
    withoutTasks.subtasks = []
    let failed = await store.save(withoutTasks, primary: false, requireExisting: true)
    precondition(!failed && store.data == initial)
    precondition(!preferences.isExpanded(eventID: first.id) && !preferences.isExpanded(eventID: second.id))

    rejectWrite = false
    let removed = await store.save(withoutTasks, primary: false, requireExisting: true)
    precondition(removed && preferences.isExpanded(eventID: first.id))
    precondition(!preferences.isExpanded(eventID: second.id), "Removing one checklist must preserve its neighbor's preference")
    let restoredTask = await store.save(first, primary: false, requireExisting: true)
    precondition(restoredTask)
    let disk = try await repository.load()
    precondition(disk == initial && preferences.isExpanded(eventID: first.id))
    precondition(!preferences.isExpanded(eventID: second.id))
}

@MainActor
private func testExpiryCleanupRetriesAfterWriteFailure(in directory: URL, defaults: UserDefaults) async throws {
    let initialDay = Day(Date())
    var now = initialDay.date()
    let expiring = Countdown(
        title: "Expires", date: initialDay, emoji: "⌛️", subtasks: [try Subtask(text: "Unfinished")]
    )
    let survivor = Countdown(
        title: "Survives", date: workflowDay(2, after: initialDay), emoji: "☀️",
        subtasks: [try Subtask(text: "Preserve")]
    )
    var initial = CountdownData()
    try initial.save(expiring, primary: true, today: initialDay)
    try initial.save(survivor, primary: false, today: initialDay)
    let preferences = SubtaskDisclosurePersistence(defaults: defaults)
    preferences.setExpanded(false, eventID: expiring.id)
    preferences.setExpanded(false, eventID: survivor.id)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(initial, revision: 0)
    var rejectWrite = true
    var writes = 0
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            writes += 1
            if rejectWrite { throw WorkflowWriteFailure() }
            return try await repository.save(data, revision: revision)
        }, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(store)
    now = workflowDay(1, after: initialDay).date()
    store.refresh()
    await waitForWorkflowStore(store)
    precondition(writes == 1 && store.data == initial)
    let failedDisk = try await repository.load()
    precondition(failedDisk == initial && !preferences.isExpanded(eventID: expiring.id))

    rejectWrite = false
    store.refresh()
    await waitForWorkflowStore(store)
    precondition(writes == 2 && store.data.items == [survivor] && store.data.primaryID == nil)
    let disk = try await repository.load()
    precondition(disk == store.data)
    await waitForWorkflowCondition { preferences.isExpanded(eventID: expiring.id) }
    precondition(!preferences.isExpanded(eventID: survivor.id), "Midnight must not reset a surviving checklist")
}

@MainActor
private func testRepeatedChecklistDraftEditsCancelAndSave(in directory: URL, defaults: UserDefaults) async throws {
    let today = Day(Date())
    let now = today.date()
    let original = Countdown(
        title: "Checklist editing", note: "Keep note", date: workflowDay(1, after: today), emoji: "🚀",
        subtasks: [try Subtask(text: "A"), try Subtask(text: "B", isCompleted: true),
                   try Subtask(text: "C"), try Subtask(text: "D", isCompleted: true)]
    )
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    var initial = CountdownData()
    try initial.save(original, primary: true, today: today)
    _ = try await repository.save(initial, revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForWorkflowStore(store)

    var draft = EventEditorDraft(item: original)
    let canSave = { (value: EventEditorDraft) in
        editorCanSave(title: value.title, note: value.note, date: original.date,
                      emoji: value.emoji, subtasks: value.subtasks, today: today)
    }
    draft.subtasks.remove(at: 0)
    draft.subtasks[0].text = "B after removing A"
    guard case let .subtask(firstNewID)? = draft.addSubtask() else {
        preconditionFailure("Replacement row must have its own focus target")
    }
    precondition(!canSave(draft), "An empty replacement must disable Save without dropping accepted neighbors")
    precondition(draft.subtasks.map(\.id) == [original.subtasks[1].id, original.subtasks[2].id,
                                           original.subtasks[3].id, firstNewID])
    draft.subtasks[3].text = "E"
    precondition(canSave(draft))

    draft.subtasks.remove(at: 2)
    draft.subtasks[1].text = "C after removing D"
    guard case let .subtask(removedNewID)? = draft.addSubtask() else {
        preconditionFailure("Second replacement row must receive focus")
    }
    draft.subtasks[3].text = " \n "
    precondition(!canSave(draft), "Whitespace-only replacement text must keep Save disabled")
    draft.subtasks[3].text = "F"
    precondition(canSave(draft))

    draft.subtasks.removeLast()
    draft.subtasks[2].text = "E after removing F"
    guard case let .subtask(lastNewID)? = draft.addSubtask() else {
        preconditionFailure("The final replacement row must receive focus")
    }
    precondition(lastNewID != removedNewID && lastNewID != firstNewID)
    precondition(!canSave(draft))
    draft.subtasks[3].text = "G"
    precondition(canSave(draft))
    precondition(draft.subtasks.map(\.id) == [original.subtasks[1].id, original.subtasks[2].id, firstNewID, lastNewID])
    precondition(draft.subtasks.map(\.text) == ["B after removing A", "C after removing D", "E after removing F", "G"])
    precondition(draft.subtasks.map(\.isCompleted) == [true, false, false, false])

    let afterDraftEdits = try Data(contentsOf: fileURL)
    precondition(afterDraftEdits == originalBytes && store.data == initial)
    // Discarding a value draft models Cancel below the native interaction boundary.
    let reopenedAfterDiscard = EventEditorDraft(item: store.data.items[0])
    precondition(reopenedAfterDiscard == EventEditorDraft(item: original))
    let edited = draft.countdown(id: original.id, date: original.date)
    let saved = await store.save(edited, primary: true, requireExisting: true)
    precondition(saved)
    let disk = try await repository.load()
    precondition(disk.items == [edited] && disk.primaryID == original.id)
    precondition(EventEditorDraft(item: disk.items[0]) == draft)
}

private func testThursdayDayDraftDateChanges() throws {
    for (year, month, day) in [(2026, 10, 22), (2026, 12, 31), (2024, 2, 29)] {
        let thursday = workflowCivilDay(year, month, day)
        let friday = workflowDay(1, after: thursday)
        var draft = EventEditorDraft(day: thursday)
        draft.note = "A note must follow the draft"
        draft.subtasks = [try Subtask(text: "Retain checklist", isCompleted: true)]
        let preservedTasks = draft.subtasks
        // Recommitting an unchanged native title must leave automatic date naming active.
        draft.setTitle("Четверг")
        for selectedDay in [friday, thursday, friday, thursday] {
            draft.updateDayTitle(for: selectedDay)
            let expectedTitle = selectedDay == thursday ? "Четверг" : "Пятница"
            precondition(draft.title == expectedTitle)
            let event = draft.countdown(id: UUID(), date: selectedDay)
            precondition(event.date == selectedDay && event.title == expectedTitle)
            precondition(event.note == "A note must follow the draft" && event.subtasks == preservedTasks)
        }
        draft.setTitle("Мой четверг")
        draft.setTitle("Четверг")
        draft.updateDayTitle(for: friday)
        precondition(draft.title == "Четверг", "A real title edit must permanently stop automatic weekday naming for that draft")

        var ordinary = EventEditorDraft(item: nil)
        ordinary.setTitle("Четверг")
        var existing = EventEditorDraft(item: Countdown(title: "Четверг", date: thursday, emoji: ""))
        for selectedDay in [friday, thursday, friday] {
            ordinary.updateDayTitle(for: selectedDay)
            existing.updateDayTitle(for: selectedDay)
            precondition(ordinary.title == "Четверг" && existing.title == "Четверг",
                         "Ordinary and saved event titles must not become automatic weekday names")
        }
    }
}

private func workflowCivilDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}

@MainActor
private func waitForWorkflowStore(_ store: Store) async {
    await waitForWorkflowCondition { !store.hasPendingPersistence }
}

@MainActor
private func waitForWorkflowCondition(_ condition: () -> Bool) async {
    let timeout = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        precondition(ProcessInfo.processInfo.systemUptime < timeout, "Store workflow did not settle within five seconds")
        await Task.yield()
    }
}

private func workflowDay(_ offset: Int, after today: Day) -> Day {
    Day(Day.calendar.date(byAdding: .day, value: offset, to: today.date())!)
}

private struct WorkflowWriteFailure: Error {}
