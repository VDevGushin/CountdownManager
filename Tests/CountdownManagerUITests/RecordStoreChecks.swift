import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testRecordStore(in directory: URL) async throws {
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let recordsURL = CountdownRepository.recordsFileURL(beside: fileURL)
    let suite = "CountdownRecordChecks.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suite) else { preconditionFailure("isolated defaults required") }
    defer { defaults.removePersistentDomain(forName: suite) }

    let firstDay = Day(Date())
    var now = firstDay.date()
    var openedLinks: [URL] = []
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now },
                      loginItemManagementIsAvailable: false, openWebURL: { openedLinks.append($0); return true })
    while store.isLoading || store.isLoadingRecords { await Task.yield() }
    precondition(store.showsEmptyRecordList && store.showsEmptyEventList)

    let id = UUID()
    let event = Countdown(id: id, title: "Event", date: firstDay, emoji: "")
    let savedEvent = await store.save(event, primary: true)
    precondition(savedEvent && store.showsEmptyRecordList)

    let firstTask = try Subtask(text: "First")
    let secondTask = try Subtask(text: "Second")
    let link = EventLink(name: "Parts", address: "https://example.org")
    let draftID = UUID()
    let source = directory.appendingPathComponent("Parts.txt")
    try Data("Record file bytes".utf8).write(to: source)
    let draftBegan = await store.beginRecordAttachmentDraft(draftID)
    let crossDraftBegan = await store.beginAttachmentDraft(draftID)
    precondition(draftBegan && !crossDraftBegan)
    guard let attachment = await store.importAttachment(from: source, draftID: draftID),
          let copy = await store.editorAttachmentThumbnailURL(attachment, recordID: nil, draftID: draftID) else {
        preconditionFailure("Record draft files must preview before Save")
    }
    let crossDraftPreview = await store.editorAttachmentThumbnailURL(attachment, eventID: nil, draftID: draftID)
    precondition(crossDraftPreview == nil)
    var first = UndatedRecord(id: id, title: "First record", subtasks: [firstTask, secondTask],
                              attachments: [attachment], links: [link])
    let second = UndatedRecord(title: "Newest record")
    let savedFirst = await store.saveRecord(first)
    await store.discardAttachmentDraft(draftID)
    let savedPreview = await store.attachmentThumbnailURL(attachment, recordID: id)
    precondition(savedPreview == copy)
    let savedSecond = await store.saveRecord(second)
    precondition(savedFirst && savedSecond && store.records == [second, first])
    first.title = "Edited older title"
    let edited = await store.saveRecord(first, requireExisting: true)
    precondition(edited && store.records == [second, first], "Edits must preserve insertion order")

    let toggle = await store.toggleRecordSubtask(recordID: id, subtaskID: firstTask.id)
    first.subtasks[0].isCompleted = true
    precondition(toggle && store.records == [second, first])
    let reopened = await store.toggleRecordSubtask(recordID: id, subtaskID: firstTask.id)
    first.subtasks[0].isCompleted = false
    precondition(reopened)
    guard let move = SubtaskReorder(subtasks: first.subtasks, subtaskID: secondTask.id) else {
        preconditionFailure("The record checklist must be reorderable")
    }
    let reordered = await store.reorderRecordSubtask(recordID: id, move: move, to: 0)
    first.subtasks = [secondTask, firstTask]
    precondition(reordered && store.records == [second, first])

    store.recordDisclosureState(for: id).setExpanded(false)
    let unrelatedLink = EventLink(id: link.id, name: link.name, address: "https://example.net")
    store.openLink(unrelatedLink, recordID: id)
    store.openLink(link, eventID: id)
    store.openLink(link, recordID: id)
    precondition(openedLinks.count == 1 && openedLinks.last == link.url, "Only the exact saved record link may open")

    try await testRecordWriteFailureAndRetry(store: store, recordsURL: recordsURL, original: second)
    try await testMiniRecordToggleQueue(store: store, recordsURL: recordsURL, original: first)

    guard let nextDay = Day.calendar.date(byAdding: .day, value: 1, to: now) else {
        preconditionFailure("Civil day fixture is invalid")
    }
    now = nextDay
    store.refresh()
    while store.hasPendingPersistence { await Task.yield() }
    precondition(store.data.items.isEmpty && store.data.primaryID == nil)
    precondition(store.records.map(\.id) == [second.id, first.id] && !store.recordDisclosureState(for: id).isExpanded)

    let restored = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    while restored.isLoading || restored.isLoadingRecords { await Task.yield() }
    precondition(restored.records == store.records && !restored.recordDisclosureState(for: id).isExpanded)
    let removed = await restored.deleteRecord(id)
    let stale = await restored.saveRecord(first, requireExisting: true)
    precondition(removed && !stale && restored.records.map(\.id) == [second.id])
    precondition(!manager.fileExists(atPath: copy.path) && manager.fileExists(atPath: source.path))
    precondition(restored.recordDisclosureState(for: id).isExpanded, "Deleted records clear their own disclosure preference")
    let invalidEventBytes = Data("invalid events".utf8)
    try invalidEventBytes.write(to: fileURL)
    let recordsOnly = Store(fileURL: fileURL, disclosureDefaults: defaults, loginItemManagementIsAvailable: false)
    while recordsOnly.isLoading || recordsOnly.isLoadingRecords { await Task.yield() }
    precondition(!recordsOnly.eventCreationIsAvailable && recordsOnly.recordCreationIsAvailable)
    let extra = UndatedRecord(title: "Can still save")
    let savedBesideCorruptEvents = await recordsOnly.saveRecord(extra)
    let untouchedEvents = try Data(contentsOf: fileURL)
    precondition(savedBesideCorruptEvents && recordsOnly.records.first == extra && untouchedEvents == invalidEventBytes)
    print("PASS record workflows: separate lifetime, stable order, checklist, links, persistence failure/retry, reload and delete")

    let seeds: [UInt64] = [1, 0xC0FFEE, UInt64.max]
    var checked = 0
    for seed in seeds {
        checked += try await testRecordMutationSequence(
            in: directory.appendingPathComponent("seed-\(seed)"), defaults: defaults, seed: seed
        )
    }
    print("PASS record monkey storage: \(checked) checked actions across 3 seeds × 48 draws")
}

@MainActor
private func testMiniRecordToggleQueue(store: Store, recordsURL: URL, original: UndatedRecord) async throws {
    let tasks = original.subtasks
    precondition(tasks.count == 2 && tasks.allSatisfy { !$0.isCompleted })
    let before = try Data(contentsOf: recordsURL)
    let manager = FileManager.default
    let backup = recordsURL.appendingPathExtension("queue-test-backup")

    func enqueueBoth() async {
        store.enqueuePanelRecordSubtaskToggle(recordID: original.id, subtaskID: tasks[0].id)
        precondition(store.hasPendingPersistence && store.canEnqueuePanelRecordSubtaskToggle,
                     "The second checkbox must remain available during a mini record toggle write")
        store.enqueuePanelRecordSubtaskToggle(recordID: original.id, subtaskID: tasks[1].id)
        while store.hasPendingPersistence { await Task.yield() }
    }

    try manager.moveItem(at: recordsURL, to: backup)
    defer {
        if manager.fileExists(atPath: backup.path) {
            try? manager.removeItem(at: recordsURL)
            try? manager.moveItem(at: backup, to: recordsURL)
        }
    }
    try manager.createDirectory(at: recordsURL, withIntermediateDirectories: false)
    await enqueueBoth()
    let savedBytes = try Data(contentsOf: backup)
    precondition(savedBytes == before && store.records.first { $0.id == original.id } == original)
    precondition(store.error == AppText.string("record.storageWriteFailed") + AppText.string("store.queuedActionsSkipped"),
                 "The user must be told when the queued checkbox change was skipped")
    try manager.removeItem(at: recordsURL)
    try manager.moveItem(at: backup, to: recordsURL)

    await enqueueBoth()
    let repository = CountdownRepository(fileURL: recordsURL.deletingLastPathComponent().appendingPathComponent("countdowns.json"))
    let persisted = try await repository.loadRecords().first { $0.id == original.id }
    precondition(persisted?.subtasks.map(\.isCompleted) == [true, true] && store.error == nil)
    await enqueueBoth()
    let restored = try await repository.loadRecords().first { $0.id == original.id }
    precondition(restored == original)
}

@MainActor
private func testRecordWriteFailureAndRetry(store: Store, recordsURL: URL, original: UndatedRecord) async throws {
    let manager = FileManager.default
    let backupURL = recordsURL.appendingPathExtension("test-backup")
    try manager.moveItem(at: recordsURL, to: backupURL)
    try manager.createDirectory(at: recordsURL, withIntermediateDirectories: false)
    var attempted = original
    attempted.title = "Retried title"
    let saved = await store.saveRecord(attempted, requireExisting: true)
    precondition(!saved && store.records.first == original, "Failed writes may not publish a candidate snapshot")
    precondition(store.error == AppText.string("record.storageWriteFailed"))
    try manager.removeItem(at: recordsURL)
    try manager.moveItem(at: backupURL, to: recordsURL)
    let retried = await store.saveRecord(attempted, requireExisting: true)
    precondition(retried && store.records.first == attempted && store.error == nil)
}

private enum RecordMutation: CaseIterable {
    case create, edit, delete, overlap, reorder, attach, removeAttachment, reloadWithAbandonedDraft
}

private struct RecordMutationRandom {
    var state: UInt64

    mutating func next(upperBound: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state ^ (state >> 29)) % UInt64(upperBound))
    }
}

@MainActor
private func testRecordMutationSequence(in directory: URL, defaults: UserDefaults, seed: UInt64) async throws -> Int {
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventURL = directory.appendingPathComponent("countdowns.json")
    let source = directory.appendingPathComponent("Unowned.txt")
    let sourceBytes = Data("original bytes".utf8)
    try sourceBytes.write(to: source)
    let day = Day(Date())
    let sharedID = UUID()
    let event = Countdown(id: sharedID, title: "Protected dated event", date: day, emoji: "")
    var store = await loadedRecordStore(fileURL: eventURL, defaults: defaults, day: day)
    let savedEvent = await store.save(event, primary: true)
    precondition(savedEvent)
    let eventBytes = try Data(contentsOf: eventURL)

    let ids = [sharedID, UUID(), UUID(), UUID()]
    var expected: [UndatedRecord] = []
    var knownCopies: [UUID: URL] = [:]
    var random = RecordMutationRandom(state: seed)
    var checked = 0
    for step in 0..<48 {
        let choice = step == 0 ? RecordMutation.create : RecordMutation.allCases[random.next(upperBound: RecordMutation.allCases.count)]
        let id = ids[step == 0 ? 0 : random.next(upperBound: ids.count)]
        let index = expected.firstIndex { $0.id == id }
        let context = "seed=\(seed), step=\(step), action=\(choice)"
        switch choice {
        case .create:
            let tasks = try (0..<3).map { try Subtask(text: "Task \($0)") }
            let record = UndatedRecord(id: id, title: "Record \(step)", subtasks: tasks)
            let saved = await store.saveRecord(record)
            precondition(saved == (index == nil), "Duplicate record creation changed ownership: \(context)")
            if saved { expected.insert(record, at: 0) }
        case .edit:
            guard let index else { continue }
            var updated = expected[index]
            updated.title = "Edited \(step) 🪐"
            updated.note = String(repeating: "👩🏽‍🔧", count: 150)
            let saved = await store.saveRecord(updated, requireExisting: true)
            precondition(saved, "Valid Unicode edit rejected: \(context)")
            expected[index] = updated
            updated.note = (updated.note ?? "") + "🪐"
            let invalid = await store.saveRecord(updated, requireExisting: true)
            precondition(!invalid, "Overlong description saved: \(context)")
        case .delete:
            guard let index else { continue }
            let deleted = await store.deleteRecord(id)
            precondition(deleted, "Delete rejected: \(context)")
            let stale = await store.saveRecord(expected.remove(at: index), requireExisting: true)
            precondition(!stale, "A stale edit resurrected a deleted record: \(context)")
        case .overlap:
            guard let index else { continue }
            await toggleOverlappingRecordTasks(store: store, record: &expected[index], context: context)
        case .reorder:
            guard let index else { continue }
            let tasks = expected[index].subtasks
            let moving = tasks[0]
            let sibling = tasks.lastIndex { $0.id != moving.id && $0.isCompleted == moving.isCompleted }
            guard let sibling, let move = SubtaskReorder(subtasks: tasks, subtaskID: moving.id) else { continue }
            let reordered = await store.reorderRecordSubtask(recordID: id, move: move, to: move.group.count - 1)
            precondition(reordered, "Valid same-group reorder rejected: \(context)")
            let groupIndices = tasks.indices.filter { tasks[$0].isCompleted == moving.isCompleted }
            var group = groupIndices.map { tasks[$0] }
            group.removeFirst()
            group.append(moving)
            for (position, task) in zip(groupIndices, group) {
                expected[index].subtasks[position] = task
            }
            precondition(expected[index].subtasks[sibling] == moving, "Reorder oracle failed: \(context)")
            let stale = await store.reorderRecordSubtask(recordID: id, move: move, to: move.group.count - 1)
            precondition(!stale, "A stale reorder replaced a newer ordering: \(context)")
        case .attach:
            guard let index, expected[index].attachments.count < EventAttachment.maximumCount else { continue }
            let draftID = UUID()
            let (attachment, copy) = await stageRecordMonkeyAttachment(store: store, draftID: draftID, source: source, context: context)
            knownCopies[attachment.id] = copy
            expected[index].attachments.append(attachment)
            let saved = await store.saveRecord(expected[index], requireExisting: true)
            precondition(saved, "Valid record file could not be committed: \(context)")
            await store.discardAttachmentDraft(draftID)
        case .removeAttachment:
            guard let index, !expected[index].attachments.isEmpty else { continue }
            let removed = expected[index].attachments.removeFirst()
            let saved = await store.saveRecord(expected[index], requireExisting: true)
            let stalePreview = await store.attachmentThumbnailURL(removed, recordID: id)
            precondition(saved && stalePreview == nil, "Removed file still accepts a stale preview: \(context)")
        case .reloadWithAbandonedDraft:
            let (attachment, copy) = await stageRecordMonkeyAttachment(store: store, draftID: UUID(), source: source, context: context)
            knownCopies[attachment.id] = copy
            store = await loadedRecordStore(fileURL: eventURL, defaults: defaults, day: day)
        }

        checked += 1
        let repository = CountdownRepository(fileURL: eventURL)
        let reopened = try await repository.loadRecords()
        precondition(store.records == expected && reopened == expected, "Disk or Store disagreed with ordered model: \(context)")
        let currentEventBytes = try Data(contentsOf: eventURL)
        let currentSourceBytes = try Data(contentsOf: source)
        precondition(currentEventBytes == eventBytes && currentSourceBytes == sourceBytes, "Record action touched a sibling or original: \(context)")
        let liveIDs = Set(expected.flatMap(\.attachments).map(\.id))
        for (attachmentID, copy) in knownCopies {
            precondition(manager.fileExists(atPath: copy.path) == liveIDs.contains(attachmentID),
                         "Owned copy lifetime disagreed with persisted references: \(context)")
        }
    }
    return checked
}

@MainActor
private func loadedRecordStore(fileURL: URL, defaults: UserDefaults, day: Day) async -> Store {
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: { day.date() },
                      loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while store.isLoading || store.isLoadingRecords {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Isolated record Store did not load")
        await Task.yield()
    }
    return store
}

@MainActor
private func stageRecordMonkeyAttachment(
    store: Store, draftID: UUID, source: URL, context: String
) async -> (EventAttachment, URL) {
    let started = await store.beginRecordAttachmentDraft(draftID)
    guard started, let file = await store.importAttachment(from: source, draftID: draftID),
          let url = await store.editorAttachmentThumbnailURL(file, recordID: nil, draftID: draftID) else {
        preconditionFailure("Record draft could not stage an owned attachment: \(context)")
    }
    return (file, url)
}

@MainActor
private func toggleOverlappingRecordTasks(store: Store, record: inout UndatedRecord, context: String) async {
    let id = record.id
    let first = record.subtasks[0].id
    let second = record.subtasks[1].id
    let firstWrite = Task { await store.toggleRecordSubtask(recordID: id, subtaskID: first) }
    let secondWrite = Task { await store.toggleRecordSubtask(recordID: id, subtaskID: second) }
    let accepted = await [firstWrite.value, secondWrite.value]
    precondition(accepted.contains(true), "Overlapping writes both rejected: \(context)")
    for (index, didToggle) in accepted.enumerated() {
        if !didToggle {
            let retried = await store.toggleRecordSubtask(recordID: id, subtaskID: record.subtasks[index].id)
            precondition(retried, "A rejected overlapping write could not retry: \(context)")
        }
        record.subtasks[index].isCompleted.toggle()
    }
}
