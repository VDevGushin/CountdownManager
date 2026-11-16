import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testSubtaskTransferWorkflows(in directory: URL) async throws {
    let suiteName = "CountdownSubtaskTransfer.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    try await testTransferWriteFailureRetryAndReload(in: directory.appendingPathComponent("retry"), defaults: defaults)
    try await testTransferPendingSnapshot(in: directory.appendingPathComponent("pending"), defaults: defaults)
    try await testTransferRevalidatesCurrentDate(in: directory.appendingPathComponent("midnight"), defaults: defaults)
    try await testTransferDefersExpiryWhileSaving(in: directory.appendingPathComponent("pending-expiry"), defaults: defaults)
    try await testTransferKeepsOwnedFiles(in: directory.appendingPathComponent("files"), defaults: defaults)
    try await testTransferCanceledBeforeAdmission(in: directory.appendingPathComponent("cancelled"), defaults: defaults)
    try await testTransferRevalidatesEditedDestination(in: directory.appendingPathComponent("changed-target"), defaults: defaults)
    try await testFailedTransferDefersExpiryWithoutGhostDay(in: directory.appendingPathComponent("failed-expiry"), defaults: defaults)
    try await testTransferRejectsQueuedStaleEventSaves(in: directory.appendingPathComponent("queued-event-save"), defaults: defaults)
    print("PASS subtask transfer workflows: atomic failure/retry, durable restart, one in-flight snapshot, midnight revalidation and owned-file preservation")
}

@MainActor
private func testTransferWriteFailureRetryAndReload(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(fixture.data, revision: 0)
    let baselineBytes = try Data(contentsOf: fileURL)
    var rejectsWrites = true
    var snapshots: [CountdownData] = []
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        snapshots.append(data)
        if rejectsWrites { throw TransferWorkflowWriteFailure() }
        return try await repository.save(data, revision: revision)
    }, now: { fixture.today.date() }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    precondition(snapshots.isEmpty, "Opening a transfer form must not write event data")
    let failed = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                              to: nil, on: fixture.tomorrow)
    precondition(failed == nil && snapshots.count == 1 && store.data == fixture.data && store.error != nil)
    let bytesAfterFailure = try Data(contentsOf: fileURL)
    precondition(bytesAfterFailure == baselineBytes, "A failed new-day transfer must keep the original task and create no day")
    precondition(snapshots[0].items.count == 2 && snapshots[0].items[0].subtasks.isEmpty)
    precondition(snapshots[0].items[1].subtasks == [fixture.task], "The writer sees the complete transfer, never two separate saves")
    rejectsWrites = false
    guard let destination = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                         to: nil, on: fixture.tomorrow) else {
        preconditionFailure("Explicit retry must save a complete transfer: \(store.error ?? "no error")")
    }
    precondition(store.error == nil && snapshots.count == 2)
    precondition(destination.isDay && destination.usesAutomaticTitle && destination.showsWeather)
    precondition(destination.subtasks == [fixture.task] && store.data.items[0].subtasks.isEmpty)
    precondition(store.data.primaryID == fixture.source.id && store.data.items[0].title == fixture.source.title)
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(restored == store.data && restored.items.last == destination)
    let completed = store.data
    let repeated = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                to: destination.id, on: fixture.tomorrow)
    precondition(repeated == nil && store.data == completed && snapshots.count == 2)
}

@MainActor
private func testTransferPendingSnapshot(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    var baseline = fixture.data
    let target = Countdown(title: "Existing target", date: fixture.tomorrow, emoji: "",
                           subtasks: [try Subtask(text: "Keep target")])
    baseline.items.append(target)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(baseline, revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var pending: (CountdownData, Int, CheckedContinuation<Bool, Error>)?
    var requests = 0
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        requests += 1
        if requests > 1 { return try await repository.save(data, revision: revision) }
        return try await withCheckedThrowingContinuation { pending = (data, revision, $0) }
    }, now: { fixture.today.date() }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let operation = Task { await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: target.id, on: fixture.tomorrow) }
    await waitForTransferWorkflow { pending != nil }
    guard let (snapshot, revision, continuation) = pending else { preconditionFailure("Expected transfer write") }
    precondition(snapshot.items[0].subtasks.isEmpty && snapshot.items[1].subtasks == target.subtasks + [fixture.task])
    precondition(store.hasPendingPersistence && store.data == baseline,
                 "Keep the source row and transfer form mounted until the complete snapshot is durable")
    let pendingBytes = try Data(contentsOf: fileURL)
    precondition(pendingBytes == originalBytes, "Before the writer finishes the durable source remains untouched")
    let repeated = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                to: target.id, on: fixture.tomorrow)
    precondition(repeated == nil && requests == 1)
    var mutationStarted = false
    var mutationFinished = false
    let queuedMutation = Task {
        mutationStarted = true
        await store.clearPrimary()
        mutationFinished = true
    }
    await waitForTransferWorkflow { mutationStarted }
    precondition(!mutationFinished && requests == 1 && store.data == baseline,
                 "Concurrent mutations must wait for the unpublished transfer snapshot")
    let written = try await repository.save(snapshot, revision: revision)
    continuation.resume(returning: written)
    let result = await operation.value
    await queuedMutation.value
    precondition(result?.subtasks == target.subtasks + [fixture.task] && !store.hasPendingPersistence)
    var expected = snapshot
    expected.primaryID = nil
    let reloaded = try await CountdownRepository(fileURL: fileURL).load()
    precondition(reloaded == expected && store.data == expected && requests == 2,
                 "The queued favorite change must retain the transfer after durable publication")
}

@MainActor
private func testTransferRevalidatesCurrentDate(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(fixture.data, revision: 0)
    let originalBytes = try Data(contentsOf: fileURL)
    var clock = fixture.today.date()
    var writes = 0
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        writes += 1
        return try await repository.save(data, revision: revision)
    }, now: { clock }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    clock = fixture.tomorrow.date()
    let rejected = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                to: nil, on: fixture.tomorrow)
    precondition(rejected == nil && writes == 0,
                 "Confirmation must use the advanced clock and reject the now-expired source before writing")
    precondition(store.data == fixture.data && store.error != nil)
    let bytes = try Data(contentsOf: fileURL)
    precondition(bytes == originalBytes, "A source that expired after the form opened must not be recreated")
}

@MainActor
private func testTransferKeepsOwnedFiles(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let originalURL = directory.appendingPathComponent("original.txt")
    let fileBytes = Data("Keep the independent material".utf8)
    try fileBytes.write(to: originalURL)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    let draftID = UUID()
    try await repository.beginAttachmentDraft(draftID)
    let attachment = try await repository.importAttachment(from: originalURL, draftID: draftID)
    var baseline = fixture.data
    baseline.items[0].attachments = [attachment]
    baseline.items[0].links = [EventLink(name: "Material", address: "https://example.com/material")]
    _ = try await repository.save(baseline, revision: 0)
    try await repository.discardAttachmentDraft(draftID)
    let storedURL = try await repository.attachmentURL(for: attachment)
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { fixture.today.date() },
                      loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let destination = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                   to: nil, on: fixture.tomorrow)
    precondition(destination?.subtasks == [fixture.task] && destination?.attachments.isEmpty == true)
    var expectedSource = baseline.items[0]
    expectedSource.subtasks = []
    precondition(store.data.items[0] == expectedSource)
    let ownedBytes = try Data(contentsOf: storedURL)
    let externalBytes = try Data(contentsOf: originalURL)
    precondition(ownedBytes == fileBytes && externalBytes == fileBytes)
    let reloaded = try await CountdownRepository(fileURL: fileURL).load()
    precondition(reloaded == store.data, "Moving the final task must retain the source and its owned files/links")
}

@MainActor
private func testTransferDefersExpiryWhileSaving(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(fixture.data, revision: 0)
    var clock = fixture.today.date()
    var requests = 0
    var pending: (CountdownData, Int, CheckedContinuation<Bool, Error>)?
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        requests += 1
        if requests > 1 { return try await repository.save(data, revision: revision) }
        return try await withCheckedThrowingContinuation { pending = (data, revision, $0) }
    }, now: { clock }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let operation = Task { await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: nil, on: fixture.tomorrow) }
    await waitForTransferWorkflow { pending != nil }
    clock = fixture.tomorrow.date()
    store.refresh()
    precondition(requests == 1 && store.data == fixture.data,
                 "Midnight normalization must wait while the transfer candidate is unpublished")
    guard let (snapshot, revision, continuation) = pending else { preconditionFailure("Expected transfer write") }
    let written = try await repository.save(snapshot, revision: revision)
    continuation.resume(returning: written)
    let destination = await operation.value
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    precondition(destination?.subtasks == [fixture.task] && requests == 2)
    precondition(store.data.items.count == 1 && store.data.items.first == destination && store.data.primaryID == nil)
    let durable = try await CountdownRepository(fileURL: fileURL).load()
    precondition(durable == store.data, "Deferred expiry must keep the newly durable destination and moved task")
}

private func transferWorkflowFixture() throws -> (today: Day, tomorrow: Day, source: Countdown, task: Subtask, data: CountdownData) {
    let today = Day(Day.calendar.date(from: DateComponents(year: 2026, month: 11, day: 16))!)
    let tomorrow = Day(Day.calendar.date(byAdding: .day, value: 1, to: today.date())!)
    let task = try Subtask(text: "Carry this task")
    let source = Countdown(title: "Source day", note: "Keep source metadata", date: today, emoji: "", subtasks: [task])
    var data = CountdownData()
    data.items = [source]
    data.primaryID = source.id
    return (today, tomorrow, source, task, data)
}

@MainActor
private func waitForTransferWorkflow(_ condition: () -> Bool) async {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Transfer workflow did not reach its deterministic barrier")
        await Task.yield()
    }
}

private struct TransferWorkflowWriteFailure: Error {}

@MainActor
private func testTransferCanceledBeforeAdmission(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(fixture.data, revision: 0)
    let baselineBytes = try Data(contentsOf: fileURL)
    var writes = 0
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        writes += 1
        return try await repository.save(data, revision: revision)
    }, now: { fixture.today.date() }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    var start: CheckedContinuation<Void, Never>?
    let operation = Task {
        await withCheckedContinuation { start = $0 }
        return await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                           to: nil, on: fixture.tomorrow)
    }
    await waitForTransferWorkflow { start != nil }
    operation.cancel()
    start?.resume()
    let result = await operation.value
    let after = try Data(contentsOf: fileURL)
    precondition(result == nil && writes == 0 && store.data == fixture.data && after == baselineBytes)
    let session = EventEditorSession()
    for surface in [EventEditorSession.Surface.panel, .desktop] {
        precondition(session.beginSubtaskTransfer(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                  surface: surface, date: fixture.tomorrow))
        guard let draft = session.subtaskTransfer else { preconditionFailure("Expected transfer draft") }
        session.endSubtaskTransfer()
        precondition(!session.beginSubtaskTransferSave(draft),
                     "A canceled draft must never reserve a delayed confirmation")
        precondition(!session.hasActiveEditor && !session.subtaskTransferIsSaving)
    }
    print("PASS subtask transfer cancellation: canceled task performs no writes; canceled drafts reject delayed save on both surfaces")
}

@MainActor
private func testTransferRevalidatesEditedDestination(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let later = Day(Day.calendar.date(byAdding: .day, value: 1, to: fixture.tomorrow.date())!)
    let target = Countdown(title: "Selected recipient", date: fixture.tomorrow, emoji: "")
    var baseline = fixture.data
    baseline.items.append(target)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(baseline, revision: 0)
    var writes = 0
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        writes += 1
        return try await repository.save(data, revision: revision)
    }, now: { fixture.today.date() }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    var changed = target
    changed.date = later
    let savedDateEdit = await store.save(changed, primary: false, requireExisting: true)
    precondition(savedDateEdit)
    let afterDateEdit = store.data
    let dateRejected = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                    to: target.id, on: fixture.tomorrow)
    precondition(dateRejected == nil && writes == 1 && store.data == afterDateEdit)
    changed.date = fixture.tomorrow
    changed.subtasks = try (1...10).map { try Subtask(text: "Completed \($0)", isCompleted: true) }
    let savedCapacityEdit = await store.save(changed, primary: false, requireExisting: true)
    precondition(savedCapacityEdit)
    let afterCapacityEdit = store.data
    let capacityRejected = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: target.id, on: fixture.tomorrow)
    precondition(capacityRejected == nil && writes == 2 && store.data == afterCapacityEdit)
    changed.subtasks = [try Subtask(id: fixture.task.id, text: "Legacy colliding task")]
    let savedIdentityEdit = await store.save(changed, primary: false, requireExisting: true)
    precondition(savedIdentityEdit)
    let afterIdentityEdit = store.data
    let identityRejected = await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: target.id, on: fixture.tomorrow)
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(identityRejected == nil && writes == 3 && store.data == afterIdentityEdit && restored == afterIdentityEdit)
    print("PASS subtask transfer stale selection: recipient date/capacity/legacy identity changes reject before transfer writes")
}

@MainActor
private func testFailedTransferDefersExpiryWithoutGhostDay(in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(fixture.data, revision: 0)
    var clock = fixture.today.date()
    var requests = 0
    var pending: CheckedContinuation<Bool, Error>?
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        requests += 1
        if requests > 1 { return try await repository.save(data, revision: revision) }
        return try await withCheckedThrowingContinuation { pending = $0 }
    }, now: { clock }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let operation = Task { await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: nil, on: fixture.tomorrow) }
    await waitForTransferWorkflow { pending != nil }
    clock = fixture.tomorrow.date()
    store.refresh()
    precondition(requests == 1 && store.data == fixture.data)
    pending?.resume(throwing: TransferWorkflowWriteFailure())
    let result = await operation.value
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(result == nil && requests == 2 && restored.items.isEmpty && store.data == restored)
    precondition(restored.primaryID == nil && store.error != nil,
                 "Ordinary expiry follows failed transfer rollback and must not create its uncommitted destination")
    print("PASS subtask transfer failed midnight: rollback followed by ordinary expiry creates no ghost receiver")
}

private enum QueuedTransferEditScenario: String, CaseIterable {
    case source, target, unrelated, failedSource
}

@MainActor
private func testTransferRejectsQueuedStaleEventSaves(in directory: URL, defaults: UserDefaults) async throws {
    for scenario in QueuedTransferEditScenario.allCases {
        try await checkQueuedTransferEventSave(scenario, in: directory.appendingPathComponent(scenario.rawValue), defaults: defaults)
    }
    print("PASS subtask transfer queued event saves: stale source/target edits rejected, unrelated edits and unchanged failed-transfer source allowed, moved UUID exactly once")
}

@MainActor
private func checkQueuedTransferEventSave(_ scenario: QueuedTransferEditScenario,
                                          in directory: URL, defaults: UserDefaults) async throws {
    let fixture = try transferWorkflowFixture()
    let target = Countdown(title: "Target", date: fixture.tomorrow, emoji: "")
    let unrelated = Countdown(title: "Unrelated", date: fixture.tomorrow, emoji: "")
    var baseline = fixture.data
    baseline.items += [target, unrelated]
    let editedIndex: Int
    switch scenario {
    case .source, .failedSource: editedIndex = 0
    case .target: editedIndex = 1
    case .unrelated: editedIndex = 2
    }
    var edited = baseline.items[editedIndex]
    edited.note = "Whole-event edit queued during transfer"
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    _ = try await repository.save(baseline, revision: 0)
    var pending: (CountdownData, Int, CheckedContinuation<Bool, Error>)?
    var writes = 0
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: { data, revision in
        writes += 1
        if writes > 1 { return try await repository.save(data, revision: revision) }
        return try await withCheckedThrowingContinuation { pending = (data, revision, $0) }
    }, now: { fixture.today.date() }, loginItemManagementIsAvailable: false)
    await waitForTransferWorkflow { !store.hasPendingPersistence }
    let transfer = Task { await store.transferSubtask(eventID: fixture.source.id, subtaskID: fixture.task.id,
                                                        to: target.id, on: fixture.tomorrow) }
    await waitForTransferWorkflow { pending != nil }
    var saveStarted = false
    var saveFinished = false
    let queuedSave = Task {
        saveStarted = true
        let result = await store.save(edited, primary: edited.id == fixture.source.id, requireExisting: true)
        saveFinished = true
        return result
    }
    await waitForTransferWorkflow { saveStarted }
    precondition(!saveFinished && writes == 1 && store.data == baseline,
                 "The queued full-event save must use the existing transfer wait barrier")
    guard let (snapshot, revision, continuation) = pending else { preconditionFailure("Expected suspended transfer write") }
    if scenario == .failedSource {
        continuation.resume(throwing: TransferWorkflowWriteFailure())
    } else {
        let written = try await repository.save(snapshot, revision: revision)
        continuation.resume(returning: written)
    }
    let transferResult = await transfer.value
    let saveResult = await queuedSave.value
    let permitsSave = scenario == .unrelated || scenario == .failedSource
    precondition(saveResult == permitsSave && writes == (permitsSave ? 2 : 1))
    var expected = baseline
    if scenario == .failedSource {
        precondition(transferResult == nil)
    } else {
        precondition(transferResult?.subtasks == [fixture.task])
        expected.items[0].subtasks = []
        expected.items[1].subtasks = [fixture.task]
    }
    if permitsSave { expected.items[editedIndex] = edited }
    else {
        precondition(store.error?.contains("Событие изменилось во время переноса") == true,
                     "A rejected stale edit must explain that its event changed during transfer")
    }
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(store.data == expected && restored == expected)
    precondition(restored.items.flatMap(\.subtasks).filter { $0.id == fixture.task.id }.count == 1,
                 "Queued whole-event edits must neither restore the removed source task nor erase the target task")
}
