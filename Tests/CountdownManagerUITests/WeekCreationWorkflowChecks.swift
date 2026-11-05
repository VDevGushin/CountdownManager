import Foundation
import CountdownCore
import CountdownManagerUI

@MainActor
func testWeekCreationWorkflows(in directory: URL) async throws {
    try testWeekDayDraftIdentity()
    let suiteName = "CountdownWeekWorkflow.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try await testWeekBatchFailureRetryAndReload(in: directory.appendingPathComponent("retry"), defaults: defaults)
    try await testWeekBatchPendingSnapshot(in: directory.appendingPathComponent("pending"), defaults: defaults)
    try await testWeekBatchMidnightRevalidation(in: directory.appendingPathComponent("midnight"), defaults: defaults)
    print("PASS week workflows: stable day origin through draft edits, preview without writes, failed batch rollback/retry, single complete snapshot, durable restart/idempotence and stale-midnight re-review")
}

private func testWeekDayDraftIdentity() throws {
    let thursday = weekWorkflowDay(2026, 11, 5)
    let friday = weekWorkflowDay(2026, 11, 6)
    var ordinary = EventEditorDraft(item: nil)
    precondition(!ordinary.countdown(id: UUID(), date: thursday).isDay)
    ordinary.useAutomaticTitle(for: friday)
    precondition(ordinary.usesAutomaticTitle && !ordinary.countdown(id: UUID(), date: friday).isDay,
                 "Changing an ordinary event's title mode must not invent day origin")

    var draft = EventEditorDraft(day: thursday)
    let dayID = UUID()
    let original = draft.countdown(id: dayID, date: thursday)
    precondition(original.isDay && original.usesAutomaticTitle && original.showsWeather)
    draft.setTitle("Планы на пятницу")
    draft.updateDayTitle(for: friday)
    let renamed = draft.countdown(id: dayID, date: friday)
    precondition(renamed.isDay && !renamed.usesAutomaticTitle && renamed.title == "Планы на пятницу")
    precondition(renamed.date == friday && renamed.id == dayID)
    let restored = try JSONDecoder().decode(Countdown.self, from: JSONEncoder().encode(renamed))
    var reopened = EventEditorDraft(item: restored)
    reopened.useAutomaticTitle(for: friday)
    precondition(reopened.countdown(id: dayID, date: friday).isDay,
                 "Reopening and toggling automatic naming must preserve the original day identity")
}

@MainActor
private func testWeekBatchFailureRetryAndReload(in directory: URL, defaults: UserDefaults) async throws {
    let today = weekWorkflowDay(2026, 11, 5)
    let friday = weekWorkflowDay(2026, 11, 6)
    let saturday = weekWorkflowDay(2026, 11, 7)
    let ordinary = Countdown(title: "Стоматолог", note: "Keep ordinary event", date: friday, emoji: "", keepsAfterDate: true)
    var renamedDay = EventEditorDraft(day: saturday)
    renamedDay.setTitle("Подготовиться к поездке")
    renamedDay.note = "Keep day note"
    renamedDay.subtasks = [try Subtask(text: "Keep completed task", isCompleted: true)]
    let existingDay = renamedDay.countdown(id: UUID(), date: saturday)
    var baseline = CountdownData()
    try baseline.save(ordinary, primary: true, today: today)
    try baseline.save(existingDay, primary: false, today: today)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(baseline, revision: 0)
    let baselineBytes = try Data(contentsOf: fileURL)
    var rejectsWrites = true
    var snapshots: [(CountdownData, Int)] = []
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            snapshots.append((data, revision))
            if rejectsWrites { throw WeekWorkflowWriteFailure() }
            return try await repository.save(data, revision: revision)
        }, now: { today.date() }, loginItemManagementIsAvailable: false
    )
    await waitForWeekWorkflow { !store.hasPendingPersistence }
    let week = requiredWorkflowWeek(today)
    precondition(snapshots.isEmpty && store.data == baseline)
    let afterPreview = try Data(contentsOf: fileURL)
    precondition(afterPreview == baselineBytes, "Building or abandoning a preview must not write event data")

    let failed = await store.createWeekDays(week)
    precondition(failed == nil && snapshots.count == 1)
    precondition(store.data == baseline && !store.hasPendingPersistence && store.error != nil)
    let afterFailure = try Data(contentsOf: fileURL)
    precondition(afterFailure == baselineBytes, "A failed batch must preserve the existing JSON bytes")
    precondition(snapshots[0].0.items.count == baseline.items.count + 2,
                 "One persistence attempt must contain the entire missing-day batch")

    rejectsWrites = false
    guard let created = await store.createWeekDays(week) else {
        preconditionFailure("An explicit retry must save the complete batch")
    }
    precondition(created.map(\.date) == [friday, weekWorkflowDay(2026, 11, 8)])
    precondition(created.allSatisfy { $0.isDay && $0.usesAutomaticTitle && $0.showsWeather && !$0.keepsAfterDate })
    precondition(snapshots.count == 2 && snapshots[1].1 > snapshots[0].1)
    precondition(Array(store.data.items.prefix(baseline.items.count)) == baseline.items)
    precondition(store.data.primaryID == ordinary.id && !store.hasPendingPersistence)
    let durable = try await CountdownRepository(fileURL: fileURL).load()
    precondition(durable == store.data && durable.items.count == 4)
    let durableBytes = try Data(contentsOf: fileURL)

    let restored = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { today.date() }, loginItemManagementIsAvailable: false)
    await waitForWeekWorkflow { !restored.hasPendingPersistence }
    precondition(restored.data == durable)
    let repeated = await store.createWeekDays(week)
    precondition(repeated?.isEmpty == true && snapshots.count == 2 && store.data == durable,
                 "An already-created week is a no-op, including renamed days and ordinary same-date events")
    let restoredRepeat = await restored.createWeekDays(week)
    precondition(restoredRepeat?.isEmpty == true && restored.data == durable)
    let finalBytes = try Data(contentsOf: fileURL)
    precondition(finalBytes == durableBytes, "A no-op repeat must retain the durable event snapshot")
}

@MainActor
private func testWeekBatchPendingSnapshot(in directory: URL, defaults: UserDefaults) async throws {
    let today = weekWorkflowDay(2026, 11, 8)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(CountdownData(), revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var pending: (CountdownData, Int, CheckedContinuation<Bool, Error>)?
    var requests = 0
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            requests += 1
            return try await withCheckedThrowingContinuation { continuation in
                pending = (data, revision, continuation)
            }
        }, now: { today.date() }, loginItemManagementIsAvailable: false
    )
    await waitForWeekWorkflow { !store.hasPendingPersistence }
    let task = Task { @MainActor in await store.createWeekDays(requiredWorkflowWeek(today)) }
    await waitForWeekWorkflow { pending != nil }
    guard let (snapshot, revision, continuation) = pending else {
        preconditionFailure("The batch must reach the controlled persistence boundary")
    }
    precondition(requests == 1 && store.hasPendingPersistence)
    precondition(snapshot.items.count == 7 && snapshot.items.map(\.date) == requiredWorkflowWeek(today).days)
    precondition(snapshot.items.allSatisfy(\.isDay) && snapshot.primaryID == nil)
    precondition(store.data.items.isEmpty || store.data.items == snapshot.items,
                 "Publishing a batch must expose either the old snapshot or all seven days, never a partial week")
    let bytesWhilePending = try Data(contentsOf: fileURL)
    precondition(bytesWhilePending == originalBytes)
    let repeatedWhilePending = await store.createWeekDays(requiredWorkflowWeek(today))
    precondition(repeatedWhilePending == nil && requests == 1,
                 "A second confirmation during a pending batch must not start another write")
    let didWrite = try await repository.save(snapshot, revision: revision)
    continuation.resume(returning: didWrite)
    let result = await task.value
    precondition(result?.count == 7 && requests == 1 && !store.hasPendingPersistence)
    let durable = try await CountdownRepository(fileURL: fileURL).load()
    precondition(durable == snapshot && store.data == snapshot)
}

@MainActor
private func testWeekBatchMidnightRevalidation(in directory: URL, defaults: UserDefaults) async throws {
    let sunday = weekWorkflowDay(2026, 11, 8)
    let monday = weekWorkflowDay(2026, 11, 9)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(CountdownData(), revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var clock = sunday.date()
    var writes = 0
    let store = Store(
        fileURL: fileURL, disclosureDefaults: defaults,
        persistenceSaveOverride: { data, revision in
            writes += 1
            return try await repository.save(data, revision: revision)
        }, now: { clock }, loginItemManagementIsAvailable: false
    )
    await waitForWeekWorkflow { !store.hasPendingPersistence }
    let sundayPreview = requiredWorkflowWeek(sunday)
    precondition(sundayPreview.days.first == monday && sundayPreview.days.count == 7)
    clock = monday.date()
    let rejected = await store.createWeekDays(sundayPreview)
    precondition(rejected == nil && writes == 0 && store.data.items.isEmpty && store.error != nil)
    let afterRejection = try Data(contentsOf: fileURL)
    precondition(afterRejection == originalBytes,
                 "A Sunday preview used after midnight must not silently switch or save stale dates")
    let mondayPreview = requiredWorkflowWeek(monday)
    let created = await store.createWeekDays(mondayPreview)
    precondition(created?.count == 6 && writes == 1)
    precondition(created?.first?.date == weekWorkflowDay(2026, 11, 10))
    precondition(created?.last?.date == weekWorkflowDay(2026, 11, 15))
}

private func requiredWorkflowWeek(_ today: Day) -> DayCreationWeek {
    guard let week = DayCreationWeek(today: today) else {
        preconditionFailure("Expected a supported civil week in the fixture")
    }
    return week
}

private func weekWorkflowDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}

@MainActor
private func waitForWeekWorkflow(_ condition: () -> Bool) async {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Week workflow did not reach its deterministic barrier")
        await Task.yield()
    }
}

private struct WeekWorkflowWriteFailure: Error {}
