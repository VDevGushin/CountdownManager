import Foundation
import CountdownCore
import CountdownManagerUI

@MainActor
func testAutomaticTitleWorkflows(in directory: URL) async throws {
    let suite = "CountdownAutomaticTitleChecks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try testAutomaticTitleDraftRoutesAndEdits()
    try testAutomaticTitleResetRepairsInvalidTitle()
    for initialAutomatic in [false, true] {
        try await testAutomaticTitleDurability(
            in: directory.appendingPathComponent("durability-\(initialAutomatic)"),
            defaults: defaults, initiallyAutomatic: initialAutomatic
        )
    }
    try await testUnavailableAutomaticTitleCannotResurrect(in: directory.appendingPathComponent("unavailable"), defaults: defaults)
    try await testDeletedAutomaticTitleDraftCannotResurrectAfterReload(
        in: directory.appendingPathComponent("deleted-reload"), defaults: defaults
    )
    try await testOverlappingAutomaticTitleWrites(in: directory.appendingPathComponent("overlap"), defaults: defaults)
    let seeds: [UInt64] = [1, 0xC0FFEE, 20261022, .max]
    for seed in seeds {
        try await testSeededAutomaticTitleActions(in: directory.appendingPathComponent("seed-\(seed)"), defaults: defaults, seed: seed)
    }
    print("PASS automatic titles: draft entry routes, identical/Unicode/manual/reset edits, two-way failed Save retry, Cancel and durable reload, expired/missing identity rejection; 8 overlapping-write outcomes; 4 reproducible seeds × 192 actions")
}

private func testAutomaticTitleDraftRoutesAndEdits() throws {
    let thursday = automaticTitleDay(0)
    let friday = automaticTitleDay(1)
    var ordinary = EventEditorDraft(item: nil)
    precondition(!ordinary.usesAutomaticTitle && ordinary.title.isEmpty)
    ordinary.useAutomaticTitle(for: thursday)
    precondition(ordinary.usesAutomaticTitle && ordinary.title == "Четверг" && !ordinary.showsWeather)

    for day in [thursday, friday, automaticTitleDay(7)] {
        let draft = EventEditorDraft(day: day)
        precondition(draft.usesAutomaticTitle && draft.showsWeather)
        precondition(draft.countdown(id: UUID(), date: day).usesAutomaticTitle)
    }
    let legacy = Countdown(title: "Четверг", note: "Keep legacy note", date: thursday, emoji: "📅")
    let encodedLegacy = try JSONEncoder().encode(legacy)
    guard let legacyJSON = try JSONSerialization.jsonObject(with: encodedLegacy) as? [String: Any] else {
        preconditionFailure("A legacy event must encode as a JSON object")
    }
    precondition(legacyJSON["usesAutomaticTitle"] == nil)
    let restoredLegacy = try JSONDecoder().decode(Countdown.self, from: encodedLegacy)
    var legacyDraft = EventEditorDraft(item: restoredLegacy)
    legacyDraft.updateDayTitle(for: friday)
    precondition(!legacyDraft.usesAutomaticTitle && legacyDraft.title == "Четверг")

    for typedText in ["", " \n ", "Поездка 🏍️", "e\u{301}", "Четверг ", "ЧЕТВЕРГ"] {
        var draft = EventEditorDraft(day: thursday)
        draft.note = "Untouched note"
        draft.emoji = "☀️"
        draft.subtasks = [try Subtask(text: "Untouched task", isCompleted: true)]
        let untouched = draft.countdown(id: UUID(), date: thursday)
        draft.setTitle(draft.title)
        precondition(draft.usesAutomaticTitle, "Copying/committing unchanged text must not disable automatic mode")
        draft.updateDayTitle(for: friday)
        precondition(draft.title == "Пятница")
        draft.setTitle(typedText)
        precondition(!draft.usesAutomaticTitle && draft.title == typedText)
        draft.updateDayTitle(for: thursday)
        precondition(draft.title == typedText)
        let valid = editorCanSave(title: draft.title, note: draft.note, date: thursday,
                                  emoji: draft.emoji, subtasks: draft.subtasks, today: thursday)
        precondition(valid == !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        // Restoring the old title through typing/Undo does not undo the user's naming choice.
        draft.setTitle("Четверг")
        draft.updateDayTitle(for: friday)
        precondition(draft.title == "Четверг" && !draft.usesAutomaticTitle)
        draft.useAutomaticTitle(for: friday)
        draft.updateDayTitle(for: thursday)
        precondition(draft.title == "Четверг" && draft.usesAutomaticTitle)
        let final = draft.countdown(id: untouched.id, date: thursday)
        precondition(final.note == untouched.note && final.emoji == untouched.emoji
                     && final.subtasks == untouched.subtasks && final.showsWeather == untouched.showsWeather)
    }
}

private func testAutomaticTitleResetRepairsInvalidTitle() throws {
    let selectedDay = automaticTitleDay(1)
    let task = try Subtask(text: "Keep completed task", isCompleted: true)
    let existing = Countdown(
        title: "Saved custom", note: "Preserve exact note", date: selectedDay, emoji: "🏍️",
        subtasks: [task], showsWeather: true
    )
    for entry in 0..<3 {
        var draft: EventEditorDraft
        switch entry {
        case 0:
            draft = EventEditorDraft(item: nil)
        case 1:
            draft = EventEditorDraft(item: existing)
            draft.setTitle(" \n\t ")
        default:
            draft = EventEditorDraft(day: selectedDay)
            draft.setTitle("")
        }
        precondition(!draft.usesAutomaticTitle)
        let before = draft.countdown(id: existing.id, date: selectedDay)
        precondition(!editorCanSave(title: draft.title, note: draft.note, date: selectedDay,
                                   emoji: draft.emoji, subtasks: draft.subtasks, today: automaticTitleDay(0)))
        draft.useAutomaticTitle(for: selectedDay)
        precondition(draft.usesAutomaticTitle && draft.title == "Пятница")
        precondition(editorCanSave(title: draft.title, note: draft.note, date: selectedDay,
                                  emoji: draft.emoji, subtasks: draft.subtasks, today: automaticTitleDay(0)),
                     "Explicit reset must make an empty/whitespace custom title saveable")
        let after = draft.countdown(id: existing.id, date: selectedDay)
        precondition(after.note == before.note && after.emoji == before.emoji && after.subtasks == before.subtasks
                     && after.showsWeather == before.showsWeather && after.id == before.id && after.date == before.date)
        // The reset is idempotent and copying its generated text keeps automatic naming.
        draft.useAutomaticTitle(for: selectedDay)
        draft.setTitle("Пятница")
        draft.updateDayTitle(for: automaticTitleDay(2))
        precondition(draft.usesAutomaticTitle && draft.title == "Суббота")
    }
    for invalidNote in [false, true] {
        var draft = EventEditorDraft(item: existing)
        draft.setTitle("")
        if invalidNote {
            draft.note = String(repeating: "я", count: 151)
        } else {
            draft.addSubtask()
        }
        let rejectedSiblingFields = draft.countdown(id: existing.id, date: selectedDay)
        draft.useAutomaticTitle(for: selectedDay)
        precondition(draft.usesAutomaticTitle && draft.title == "Пятница")
        precondition(draft.note == rejectedSiblingFields.note && draft.subtasks == rejectedSiblingFields.subtasks)
        precondition(!editorCanSave(title: draft.title, note: draft.note, date: selectedDay,
                                   emoji: draft.emoji, subtasks: draft.subtasks, today: automaticTitleDay(0)),
                     "Resetting the title must not bypass invalid note or empty subtask validation")
    }
}

@MainActor
private func testAutomaticTitleDurability(in directory: URL, defaults: UserDefaults, initiallyAutomatic: Bool) async throws {
    let today = automaticTitleDay(0)
    let now = today.date()
    let original = Countdown(
        title: initiallyAutomatic ? "Четверг" : "Custom title", note: "Preserve\nwhole note", date: today,
        emoji: "🏍️", subtasks: [try Subtask(text: "Finished", isCompleted: true), try Subtask(text: "Pending")],
        showsWeather: true, usesAutomaticTitle: initiallyAutomatic
    )
    let neighbor = Countdown(title: "Neighbor", date: automaticTitleDay(3), emoji: "", showsWeather: false)
    var initial = CountdownData()
    try initial.save(original, primary: true, today: today)
    try initial.save(neighbor, primary: false, today: today)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(initial, revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var rejectsWrites = true
    var attempts = 0
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            attempts += 1
            if rejectsWrites { throw AutomaticTitleWriteFailure() }
            return try await repository.save(data, revision: revision)
        }, now: { now }, loginItemManagementIsAvailable: false
    )
    await waitForAutomaticTitleStore(store)
    var draft = EventEditorDraft(item: store.data.items[0])
    if initiallyAutomatic { draft.setTitle("Custom after editing") }
    else { draft.useAutomaticTitle(for: today) }
    draft.updateDayTitle(for: automaticTitleDay(1))
    let proposed = draft.countdown(id: original.id, date: automaticTitleDay(1))
    precondition(proposed.usesAutomaticTitle != original.usesAutomaticTitle)

    let cancelled = EventEditorDraft(item: store.data.items[0])
    precondition(cancelled.title == original.title && cancelled.usesAutomaticTitle == initiallyAutomatic)
    let afterCancel = try Data(contentsOf: fileURL)
    precondition(afterCancel == originalBytes && attempts == 0)

    let failed = await store.save(proposed, primary: true, requireExisting: true)
    precondition(!failed && store.data == initial && attempts == 1)
    let afterFailure = try Data(contentsOf: fileURL)
    precondition(afterFailure == originalBytes)
    let reopenedAfterFailure = EventEditorDraft(item: store.data.items[0])
    precondition(reopenedAfterFailure.usesAutomaticTitle == initiallyAutomatic)
    rejectsWrites = false
    let saved = await store.save(proposed, primary: true, requireExisting: true)
    precondition(saved && attempts == 2)
    let disk = try await CountdownRepository(fileURL: fileURL).load()
    precondition(disk.items == [proposed, neighbor] && disk.primaryID == original.id)
    precondition(disk.items[0].subtasks == original.subtasks && disk.items[0].note == original.note
                 && disk.items[0].emoji == original.emoji && disk.items[0].showsWeather == original.showsWeather)
    let restored = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForAutomaticTitleStore(restored)
    precondition(restored.data == disk)
    var reopened = EventEditorDraft(item: restored.data.items[0])
    reopened.updateDayTitle(for: automaticTitleDay(2))
    precondition(reopened.usesAutomaticTitle == !initiallyAutomatic)
    precondition(reopened.title == (initiallyAutomatic ? "Custom after editing" : "Суббота"))
    let moved = reopened.countdown(id: original.id, date: automaticTitleDay(2))
    let movedSaved = await restored.save(moved, primary: true, requireExisting: true)
    precondition(movedSaved)
    let movedDisk = try await CountdownRepository(fileURL: fileURL).load()
    precondition(movedDisk.items == [moved, neighbor] && movedDisk.primaryID == original.id)
}

@MainActor
private func testUnavailableAutomaticTitleCannotResurrect(in directory: URL, defaults: UserDefaults) async throws {
    let today = automaticTitleDay(0)
    var now = today.date()
    let original = EventEditorDraft(day: today).countdown(id: UUID(), date: today)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForAutomaticTitleStore(store)
    let created = await store.save(original, primary: true)
    precondition(created)
    let savedBytes = try Data(contentsOf: fileURL)
    var draft = EventEditorDraft(item: original)
    now = automaticTitleDay(1).date()
    draft.useAutomaticTitle(for: automaticTitleDay(2))
    let stale = await store.save(draft.countdown(id: original.id, date: automaticTitleDay(2)), primary: true, requireExisting: true)
    precondition(!stale)
    let missing = await store.save(draft.countdown(id: UUID(), date: automaticTitleDay(2)), primary: true, requireExisting: true)
    precondition(!missing)
    let afterRejections = try Data(contentsOf: fileURL)
    precondition(afterRejections == savedBytes)
    store.refresh()
    await waitForAutomaticTitleStore(store)
    let disk = try await CountdownRepository(fileURL: fileURL).load()
    precondition(disk.items.isEmpty && disk.primaryID == nil)
}

@MainActor
private func testDeletedAutomaticTitleDraftCannotResurrectAfterReload(in directory: URL, defaults: UserDefaults) async throws {
    let today = automaticTitleDay(0)
    let now = today.date()
    let original = Countdown(
        title: "Held original", note: "Retain unsaved context", date: automaticTitleDay(1), emoji: "🏍️",
        subtasks: [try Subtask(text: "Held checklist", isCompleted: true)], showsWeather: true
    )
    var data = CountdownData()
    try data.save(original, primary: true, today: today)
    var staleDraft = EventEditorDraft(item: original)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(data, revision: 0)

    data.delete(original.id, today: today)
    precondition(data.items.isEmpty && data.primaryID == nil)
    _ = try await repository.save(data, revision: 1)
    let deletedBytes = try Data(contentsOf: fileURL)
    let restored = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForAutomaticTitleStore(restored)
    precondition(restored.data == data)

    staleDraft.useAutomaticTitle(for: automaticTitleDay(4))
    let staleProposal = staleDraft.countdown(id: original.id, date: automaticTitleDay(4))
    precondition(staleProposal.id == original.id && staleProposal.usesAutomaticTitle)
    let saved = await restored.save(staleProposal, primary: true, requireExisting: true)
    precondition(!saved && restored.data == data && !restored.hasPendingPersistence,
                 "A stale edit must not recreate its deleted UUID after title reset and reload")
    let afterRejection = try Data(contentsOf: fileURL)
    precondition(afterRejection == deletedBytes)
    let disk = try await CountdownRepository(fileURL: fileURL).load()
    precondition(disk == data && disk.items.isEmpty && disk.primaryID == nil)
}

@MainActor
private func testOverlappingAutomaticTitleWrites(in directory: URL, defaults: UserDefaults) async throws {
    for firstSucceeds in [false, true] {
        for secondSucceeds in [false, true] {
            for reversed in [false, true] {
                let scenario = "first=\(firstSucceeds),second=\(secondSucceeds),reversed=\(reversed)"
                let fileURL = directory.appendingPathComponent(scenario).appendingPathComponent("countdowns.json")
                let repository = CountdownRepository(fileURL: fileURL)
                let now = automaticTitleDay(0).date()
                let original = EventEditorDraft(day: automaticTitleDay(0)).countdown(id: UUID(), date: automaticTitleDay(0))
                var baseline = CountdownData()
                try baseline.save(original, primary: true, today: automaticTitleDay(0))
                _ = try await repository.save(baseline, revision: 0)
                var requests: [Int: (CountdownData, CheckedContinuation<Bool, Error>)] = [:]
                let store = Store(
                    fileURL: fileURL, disclosureDefaults: defaults,
                    persistenceSaveOverride: { data, revision in
                        try await withCheckedThrowingContinuation { continuation in
                            requests[revision] = (data, continuation)
                        }
                    }, now: { now }, loginItemManagementIsAvailable: false
                )
                await waitForAutomaticTitleStore(store)
                var customDraft = EventEditorDraft(item: original)
                customDraft.setTitle("Manual pending write")
                let custom = customDraft.countdown(id: original.id, date: automaticTitleDay(1))
                let firstSave = Task { @MainActor in await store.save(custom, primary: false, requireExisting: true) }
                await waitForAutomaticTitleCondition { requests[1] != nil }
                let firstSnapshot = store.data
                var automaticDraft = EventEditorDraft(item: store.data.items[0])
                automaticDraft.useAutomaticTitle(for: automaticTitleDay(2))
                let automatic = automaticDraft.countdown(id: original.id, date: automaticTitleDay(2))
                let secondSave = Task { @MainActor in await store.save(automatic, primary: true, requireExisting: true) }
                await waitForAutomaticTitleCondition { requests[2] != nil }
                let secondSnapshot = store.data
                precondition(store.hasPendingPersistence)
                for revision in reversed ? [2, 1] : [1, 2] {
                    guard let (snapshot, continuation) = requests.removeValue(forKey: revision) else {
                        preconditionFailure("Missing automatic title write: \(scenario), revision=\(revision)")
                    }
                    if revision == 1 ? firstSucceeds : secondSucceeds {
                        let written = try await repository.save(snapshot, revision: revision)
                        continuation.resume(returning: written)
                    } else {
                        continuation.resume(throwing: AutomaticTitleWriteFailure())
                    }
                }
                let firstResult = await firstSave.value
                let secondResult = await secondSave.value
                precondition(firstResult == firstSucceeds && secondResult == secondSucceeds, scenario)
                precondition(!store.hasPendingPersistence)
                let expected = secondSucceeds ? secondSnapshot : (firstSucceeds ? firstSnapshot : baseline)
                let disk = try await CountdownRepository(fileURL: fileURL).load()
                precondition(disk == expected && store.data == expected,
                             "Automatic title/text/date/favorite must come from one durable snapshot: \(scenario)")
            }
        }
    }
}

@MainActor
private func testSeededAutomaticTitleActions(in directory: URL, defaults: UserDefaults, seed: UInt64) async throws {
    let now = automaticTitleDay(0).date()
    let event = Countdown(
        title: "Четверг", note: "Seed note\nunchanged", date: automaticTitleDay(0), emoji: "☀️",
        subtasks: [try Subtask(text: "Keep task", isCompleted: true)], showsWeather: true, usesAutomaticTitle: true
    )
    let sibling = Countdown(title: "Sibling", date: automaticTitleDay(20), emoji: "", showsWeather: false)
    var initial = CountdownData()
    try initial.save(event, primary: true, today: automaticTitleDay(0))
    try initial.save(sibling, primary: false, today: automaticTitleDay(0))
    let fileURL = directory.appendingPathComponent("countdowns.json")
    _ = try await CountdownRepository(fileURL: fileURL).save(initial, revision: 0)
    var store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForAutomaticTitleStore(store)
    var draft = EventEditorDraft(item: event)
    var dateOffset = 0
    // An optional user-supplied name is the oracle's entire naming state.
    // Otherwise expected names come from a fixed independent weekday table.
    var customName: String?
    var savedCustomName: String?
    var savedOffset = 0
    var savedTitle = "Четверг"
    var random = AutomaticTitleRandom(state: seed)
    var trace: [String] = []
    let names = ["Четверг", "Пятница", "Суббота", "Воскресенье", "Понедельник", "Вторник", "Среда"]
    let manualNames = ["", " \n ", "Мой день", "Четверг", "Поездка 🏍️", "e\u{301}", "Пятница "]
    for step in 0..<192 {
        let action = Int(random.next() % 8)
        let expectedBefore = customName ?? names[dateOffset % 7]
        switch action {
        case 0:
            dateOffset = Int(random.next() % 15)
            draft.updateDayTitle(for: automaticTitleDay(dateOffset))
            trace.append("date=\(dateOffset)")
        case 1:
            let text = manualNames[Int(random.next() % UInt64(manualNames.count))]
            if text != expectedBefore { customName = text }
            draft.setTitle(text)
            trace.append("text=\(text.debugDescription)")
        case 2:
            draft.setTitle(expectedBefore)
            trace.append("identical")
        case 3:
            customName = nil
            draft.useAutomaticTitle(for: automaticTitleDay(dateOffset))
            trace.append("automatic")
        case 4:
            customName = savedCustomName
            dateOffset = savedOffset
            draft = EventEditorDraft(item: store.data.items[0])
            trace.append("cancel")
        case 5, 6:
            let expectedTitle = customName ?? names[dateOffset % 7]
            let cleaned = expectedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let proposal = draft.countdown(id: event.id, date: automaticTitleDay(dateOffset))
            let saved = await store.save(proposal, primary: true, requireExisting: true)
            assertAutomaticTitle(saved == !cleaned.isEmpty, seed: seed, step: step, trace: trace, "Save validity")
            if saved {
                savedTitle = cleaned
                savedOffset = dateOffset
                savedCustomName = customName == nil ? nil : cleaned
                if action == 6 {
                    customName = savedCustomName
                    draft = EventEditorDraft(item: store.data.items[0])
                }
            }
            trace.append(saved ? "saved\(action == 6 ? "+reopen" : "")" : "rejected")
        default:
            store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
            await waitForAutomaticTitleStore(store)
            customName = savedCustomName
            dateOffset = savedOffset
            draft = EventEditorDraft(item: store.data.items[0])
            trace.append("restart")
        }
        let expected = customName ?? names[dateOffset % 7]
        assertAutomaticTitle(draft.title == expected && draft.usesAutomaticTitle == (customName == nil),
                             seed: seed, step: step, trace: trace, "Draft title/mode")
        let canSave = editorCanSave(title: draft.title, note: draft.note, date: automaticTitleDay(dateOffset),
                                    emoji: draft.emoji, subtasks: draft.subtasks, today: automaticTitleDay(0))
        assertAutomaticTitle(canSave == !expected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                             seed: seed, step: step, trace: trace, "Editor Save availability")
        let durable = try await CountdownRepository(fileURL: fileURL).load()
        assertAutomaticTitle(durable == store.data && durable.items.count == 2,
                             seed: seed, step: step, trace: trace, "Memory/disk agreement")
        let savedEvent = durable.items[0]
        assertAutomaticTitle(savedEvent.title == savedTitle && savedEvent.date == automaticTitleDay(savedOffset)
                             && savedEvent.usesAutomaticTitle == (savedCustomName == nil),
                             seed: seed, step: step, trace: trace, "Durable title/date/mode")
        assertAutomaticTitle(savedEvent.note == event.note && savedEvent.emoji == event.emoji
                             && savedEvent.subtasks == event.subtasks && savedEvent.showsWeather == event.showsWeather
                             && durable.items[1] == sibling && durable.primaryID == event.id,
                             seed: seed, step: step, trace: trace, "Unrelated content/favorite isolation")
    }
}

private func assertAutomaticTitle(_ condition: Bool, seed: UInt64, step: Int, trace: [String], _ invariant: String) {
    precondition(condition, "Automatic title \(invariant); seed=\(seed) step=\(step) trace=\(trace.joined(separator: " → "))")
}

@MainActor
private func waitForAutomaticTitleStore(_ store: Store) async {
    await waitForAutomaticTitleCondition { !store.hasPendingPersistence }
}

@MainActor
private func waitForAutomaticTitleCondition(_ condition: () -> Bool) async {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Automatic title Store did not settle")
        await Task.yield()
    }
}

private func automaticTitleDay(_ offset: Int) -> Day {
    let start = Day.calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!
    return Day(Day.calendar.date(byAdding: .day, value: offset, to: start)!)
}

private struct AutomaticTitleRandom {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state ^ (state >> 29)
    }
}

private struct AutomaticTitleWriteFailure: Error {}
