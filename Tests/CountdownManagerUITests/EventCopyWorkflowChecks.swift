import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testEventCopyWorkflows(in directory: URL) async throws {
    try testEventCopyDrafts()
    try await testEventCopySaveAndFileOwnership(in: directory.appendingPathComponent("ownership"))
    try await testEventCopyCancelAndMissingFile(in: directory.appendingPathComponent("cancel-missing"))
    try await testEventCopyWriteFailureAndRetry(in: directory.appendingPathComponent("write-retry"))
    try await testEventCopyPendingSave(in: directory.appendingPathComponent("pending"))
    try await testEventCopySourceAndDateRevalidation(in: directory.appendingPathComponent("availability"))
    try await testEventCopyLegacyContent(in: directory.appendingPathComponent("legacy"))
    print("PASS event copy workflows: independent identities/files, source preservation, draft cancellation, atomic file/write failures and retry, duplicate admission, source/date revalidation and inherited legacy content")
}

private func testEventCopyDrafts() throws {
    let date = eventCopyDay(2044, 9, 15)
    let tasks = [try Subtask(text: "First", isCompleted: true), try Subtask(text: "Second")]
    let links = [EventLink(name: "Route", address: "https://example.com/route")]
    let source = Countdown(title: "September trip", note: "Prepared note", date: date, emoji: "🏍️",
                           subtasks: tasks, showsWeather: true, keepsAfterDate: true, links: links)
    let draft = EventEditorDraft(copying: source, date: date)
    let copy = draft.countdown(id: UUID(), date: date)
    precondition(copy.id != source.id && copy.date == date && copy.title == source.title)
    precondition(copy.note == source.note && copy.emoji == source.emoji)
    precondition(copy.showsWeather && copy.keepsAfterDate && !copy.usesAutomaticTitle && !copy.isDay)
    precondition(copy.subtasks.map(\.text) == source.subtasks.map(\.text))
    precondition(copy.subtasks.allSatisfy { !$0.isCompleted })
    precondition(Set(copy.subtasks.map(\.id)).isDisjoint(with: source.subtasks.map(\.id)))
    precondition(copy.links.map(\.name) == source.links.map(\.name))
    precondition(copy.links.map(\.address) == source.links.map(\.address))
    precondition(Set(copy.links.map(\.id)).isDisjoint(with: source.links.map(\.id)))
    precondition(source.subtasks[0].isCompleted && source.title == "September trip")

    var automatic = source
    automatic.usesAutomaticTitle = true
    automatic.isDay = true
    var dayCopy = EventEditorDraft(copying: automatic, date: eventCopyDay(2026, 11, 9))
    precondition(dayCopy.title == "Понедельник" && dayCopy.usesAutomaticTitle && dayCopy.isDay)
    dayCopy.updateDayTitle(for: eventCopyDay(2026, 11, 10))
    precondition(dayCopy.title == "Вторник")
    dayCopy.setTitle("Custom copied day")
    dayCopy.updateDayTitle(for: eventCopyDay(2026, 11, 11))
    precondition(dayCopy.title == "Custom copied day" && !dayCopy.usesAutomaticTitle && dayCopy.isDay)
}

@MainActor
private func testEventCopySaveAndFileOwnership(in directory: URL) async throws {
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 1)
    defer { fixture.close() }
    let store = fixture.store
    let draftID = UUID()
    let prepared = await store.beginAttachmentDraft(draftID)
    precondition(prepared)
    let sourceBytes = try Data(contentsOf: fixture.fileURL)
    let draft = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
    let candidate = draft.countdown(id: UUID(), date: fixture.source.date)
    precondition(draft.attachments == fixture.source.attachments,
                 "Opening the copy draft keeps inherited references without copying file bytes")
    try fixture.requireFolderCount(1)
    let beforeSave = try Data(contentsOf: fixture.fileURL)
    precondition(beforeSave == sourceBytes)
    guard let copy = await store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: false) else {
        preconditionFailure("A valid copy must save: \(store.error ?? "no error")")
    }
    await store.discardAttachmentDraft(draftID)
    precondition(copy.id == candidate.id && copy.id != fixture.source.id)
    precondition(copy.attachments.count == 1 && copy.attachments[0].id != fixture.source.attachments[0].id)
    precondition(copy.attachments[0].name == fixture.source.attachments[0].name)
    precondition(copy.attachments[0].byteCount == fixture.source.attachments[0].byteCount)
    precondition(store.data.items.first { $0.id == fixture.source.id } == fixture.source)
    precondition(store.data.primaryID == fixture.source.id && store.data.items.count == 2)
    precondition(copy.subtasks.allSatisfy { !$0.isCompleted })
    try fixture.requireBytes(for: copy.attachments)
    try fixture.requireBytes(for: fixture.source.attachments)
    let reloaded = try await CountdownRepository(fileURL: fixture.fileURL).load()
    precondition(reloaded == store.data && reloaded.items.last == copy)

    let cleanupRepository = CountdownRepository(fileURL: fixture.fileURL)
    var afterSourceDeletion = try await cleanupRepository.load()
    afterSourceDeletion.delete(fixture.source.id, today: fixture.source.date)
    let deletedSource = try await cleanupRepository.save(afterSourceDeletion, revision: 1)
    precondition(deletedSource && afterSourceDeletion.items == [copy])
    precondition(!FileManager.default.fileExists(atPath: fixture.copyURL(fixture.source.attachments[0]).path))
    try fixture.requireBytes(for: copy.attachments)
    var afterCopyDeletion = afterSourceDeletion
    afterCopyDeletion.delete(copy.id, today: fixture.source.date)
    let deletedCopy = try await cleanupRepository.save(afterCopyDeletion, revision: 2)
    let emptied = try await CountdownRepository(fileURL: fixture.fileURL).load()
    precondition(deletedCopy && emptied.items.isEmpty)
    try fixture.requireFolderCount(0)
    let originalBytes = try Data(contentsOf: fixture.originalURL)
    precondition(originalBytes == fixture.bytes, "Deleting either event must preserve the external original")
}

@MainActor
private func testEventCopyCancelAndMissingFile(in directory: URL) async throws {
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 2)
    defer { fixture.close() }
    let store = fixture.store
    let baseline = store.data
    let baselineBytes = try Data(contentsOf: fixture.fileURL)
    let baselineFolders = try fixture.folders()
    let cancelledDraftID = UUID()
    let prepared = await store.beginAttachmentDraft(cancelledDraftID)
    precondition(prepared)
    var cancelled = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
    cancelled.title = "Discarded copy"
    cancelled.subtasks.removeAll()
    cancelled.attachments.removeAll()
    cancelled.links.removeAll()
    await store.discardAttachmentDraft(cancelledDraftID)
    let bytesAfterCancel = try Data(contentsOf: fixture.fileURL)
    precondition(bytesAfterCancel == baselineBytes && store.data == baseline)
    try fixture.requireFolders(baselineFolders)
    let stale = await store.saveCopy(cancelled.countdown(id: UUID(), date: fixture.source.date),
                                     sourceID: fixture.source.id, draftID: cancelledDraftID, primary: false)
    precondition(stale == nil && store.data == baseline)

    try FileManager.default.removeItem(at: fixture.copyURL(fixture.source.attachments[1]))
    let draftID = UUID()
    let began = await store.beginAttachmentDraft(draftID)
    precondition(began)
    var draft = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
    let copyID = UUID()
    let failed = await store.saveCopy(draft.countdown(id: copyID, date: fixture.source.date),
                                      sourceID: fixture.source.id, draftID: draftID, primary: false)
    precondition(failed == nil && store.data == baseline && store.error != nil)
    try fixture.requireFolders(baselineFolders)
    let bytesAfterFailure = try Data(contentsOf: fixture.fileURL)
    precondition(bytesAfterFailure == baselineBytes)
    try fixture.requireBytes(for: [fixture.source.attachments[0]])
    draft.attachments.removeLast()
    guard let copy = await store.saveCopy(draft.countdown(id: copyID, date: fixture.source.date),
                                         sourceID: fixture.source.id, draftID: draftID, primary: false) else {
        preconditionFailure("Removing an unavailable file must permit an explicit retry")
    }
    precondition(store.error == nil, "A successful corrected retry must clear the previous missing-file error")
    await store.discardAttachmentDraft(draftID)
    precondition(copy.id == copyID && copy.attachments.count == 1 && store.data.items.count == 2)
    precondition(store.data.items.first { $0.id == fixture.source.id } == fixture.source)
    try fixture.requireFolderCount(baselineFolders.count + 1)
}

@MainActor
private func testEventCopyWriteFailureAndRetry(in directory: URL) async throws {
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 1)
    defer { fixture.close() }
    let store = fixture.store
    let draftID = UUID()
    let prepared = await store.beginAttachmentDraft(draftID)
    precondition(prepared)
    guard let added = await store.importAttachment(from: fixture.originalURL, draftID: draftID) else {
        preconditionFailure("A copy draft must accept an additional independent import")
    }
    var draft = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
    draft.attachments.append(added)
    let candidate = draft.countdown(id: UUID(), date: fixture.source.date)
    let baseline = store.data
    let baselineFolders = try fixture.folders()
    let baselineBytes = try Data(contentsOf: fixture.fileURL)
    let backup = directory.appendingPathComponent("saved.json")
    try FileManager.default.moveItem(at: fixture.fileURL, to: backup)
    try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: false)
    let failed = await store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: true)
    precondition(failed == nil && store.data == baseline && store.data.primaryID == fixture.source.id)
    precondition(store.error != nil)
    try fixture.requireFolders(baselineFolders)
    try fixture.requireBytes(for: [added])
    try FileManager.default.removeItem(at: fixture.fileURL)
    try FileManager.default.moveItem(at: backup, to: fixture.fileURL)
    let restoredBytes = try Data(contentsOf: fixture.fileURL)
    precondition(restoredBytes == baselineBytes)
    guard let copy = await store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: true) else {
        preconditionFailure("Explicit copy retry must recover after a JSON write failure")
    }
    precondition(store.error == nil, "A successful explicit retry must clear the previous persistence error")
    precondition(copy.id == candidate.id && copy.attachments.count == 2 && copy.attachments[1] == added)
    precondition(store.data.primaryID == copy.id && store.data.items.count == 2)
    await store.discardAttachmentDraft(draftID)
    try fixture.requireFolderCount(3)
    try fixture.requireBytes(for: copy.attachments + fixture.source.attachments)
    let beforeRepeat = store.data
    let repeatedDraft = UUID()
    let repeatedPrepared = await store.beginAttachmentDraft(repeatedDraft)
    precondition(repeatedPrepared)
    _ = await store.saveCopy(candidate, sourceID: fixture.source.id, draftID: repeatedDraft, primary: true)
    await store.discardAttachmentDraft(repeatedDraft)
    precondition(store.data == beforeRepeat,
                 "A repeated successful identity must not create a second event")
    try fixture.requireFolderCount(3)
    let restored = try await CountdownRepository(fileURL: fixture.fileURL).load()
    precondition(restored == beforeRepeat)
}

@MainActor
private func testEventCopyPendingSave(in directory: URL) async throws {
    var pending: (CountdownData, Int, CheckedContinuation<Bool, Error>)?
    var writes = 0
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let writer = CountdownRepository(fileURL: fileURL)
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 0, saveOverride: { data, revision in
        writes += 1
        return try await withCheckedThrowingContinuation { pending = (data, revision, $0) }
    })
    defer { fixture.close() }
    let draftID = UUID()
    let prepared = await fixture.store.beginAttachmentDraft(draftID)
    precondition(prepared)
    let candidate = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
        .countdown(id: UUID(), date: fixture.source.date)
    let task = Task { @MainActor in
        await fixture.store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: false)
    }
    await waitForEventCopy { pending != nil }
    let repeated = await fixture.store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: false)
    precondition(repeated == nil && writes == 1, "Repeated Save during the same draft's write must be ignored")
    guard let (snapshot, revision, continuation) = pending else {
        preconditionFailure("The copy must reach the controlled writer")
    }
    let didWrite = try await writer.save(snapshot, revision: revision)
    continuation.resume(returning: didWrite)
    let copy = await task.value
    await fixture.store.discardAttachmentDraft(draftID)
    precondition(copy?.id == candidate.id && writes == 1 && fixture.store.data.items.count == 2)
}

@MainActor
private func testEventCopySourceAndDateRevalidation(in directory: URL) async throws {
    let today = eventCopyDay(2026, 11, 9)
    var now = today.date()
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 0, now: { now })
    defer { fixture.close() }
    let draftID = UUID()
    let prepared = await fixture.store.beginAttachmentDraft(draftID)
    precondition(prepared)
    let draft = EventEditorDraft(copying: fixture.source, date: today)
    let candidate = draft.countdown(id: UUID(), date: today)
    let baselineBytes = try Data(contentsOf: fixture.fileURL)
    now = eventCopyDay(2026, 11, 10).date()
    let backdated = await fixture.store.saveCopy(candidate, sourceID: fixture.source.id, draftID: draftID, primary: false)
    precondition(backdated == nil && fixture.store.data.items == [fixture.source],
                 "A retained source cannot permit a new copy to keep yesterday after midnight")
    let afterMidnight = try Data(contentsOf: fixture.fileURL)
    precondition(afterMidnight == baselineBytes)
    var expiringSource = fixture.source
    expiringSource.date = Day(now)
    expiringSource.keepsAfterDate = false
    let expiringSaved = await fixture.store.save(expiringSource, primary: true, requireExisting: true)
    precondition(expiringSaved)
    now = eventCopyDay(2026, 11, 11).date()
    fixture.store.refresh()
    await waitForEventCopy { !fixture.store.hasPendingPersistence }
    precondition(fixture.store.data.items.isEmpty)
    let afterExpiry = try Data(contentsOf: fixture.fileURL)
    var freshDate = candidate
    freshDate.date = Day(now)
    let missingSource = await fixture.store.saveCopy(freshDate, sourceID: fixture.source.id, draftID: draftID, primary: false)
    precondition(missingSource == nil && fixture.store.data.items.isEmpty)
    await fixture.store.discardAttachmentDraft(draftID)
    let finalBytes = try Data(contentsOf: fixture.fileURL)
    precondition(finalBytes == afterExpiry, "An expired source must not be resurrected by Save")
}

@MainActor
private func testEventCopyLegacyContent(in directory: URL) async throws {
    let note = " \n" + String(repeating: "👨‍👩‍👧‍👦", count: 180) + "\n "
    let fixture = try await EventCopyFixture(directory: directory, fileCount: 17, note: note)
    defer { fixture.close() }
    let draftID = UUID()
    let prepared = await fixture.store.beginAttachmentDraft(draftID)
    precondition(prepared)
    var draft = EventEditorDraft(copying: fixture.source, date: fixture.source.date)
    let copyID = UUID()
    let foldersBefore = try fixture.folders()
    draft.note += "x"
    let tooLong = await fixture.store.saveCopy(draft.countdown(id: copyID, date: fixture.source.date),
                                             sourceID: fixture.source.id, draftID: draftID, primary: false)
    precondition(tooLong == nil && fixture.store.data.items == [fixture.source])
    try fixture.requireFolders(foldersBefore)
    draft.note = note
    guard let copy = await fixture.store.saveCopy(draft.countdown(id: copyID, date: fixture.source.date),
                                                sourceID: fixture.source.id, draftID: draftID, primary: false) else {
        preconditionFailure("A copy must preserve the full inherited note and historical attachment set")
    }
    await fixture.store.discardAttachmentDraft(draftID)
    precondition(copy.note == note && copy.attachments.count == 17)
    precondition(Set(copy.attachments.map(\.id)).isDisjoint(with: fixture.source.attachments.map(\.id)))
    precondition(fixture.store.data.items.first { $0.id == fixture.source.id } == fixture.source)
    try fixture.requireBytes(for: copy.attachments + fixture.source.attachments)
    let restored = try await CountdownRepository(fileURL: fixture.fileURL).load()
    precondition(restored == fixture.store.data && restored.items.last?.note == note)
    var shortened = copy
    shortened.note = String(repeating: "я", count: 151)
    let shortenedSaved = await fixture.store.save(shortened, primary: false, requireExisting: true)
    precondition(shortenedSaved)
    shortened.note = String(repeating: "я", count: 152)
    let expandedAgain = await fixture.store.save(shortened, primary: false, requireExisting: true)
    precondition(!expandedAgain && fixture.store.data.items.last?.note?.count == 151,
                 "A copied legacy note's allowance must shrink after a successful shorter Save")
}

@MainActor
private struct EventCopyFixture {
    let store: Store
    let source: Countdown
    let fileURL: URL
    let originalURL: URL
    let defaults: UserDefaults
    let suite = "CountdownEventCopy.\(UUID().uuidString)"
    let bytes = Data("Synthetic copied document\n\0Пример 👋\n".utf8)

    init(directory: URL, fileCount: Int, note: String = "Prepared copy note",
         now: @escaping () -> Date = { eventCopyDay(2026, 11, 9).date() },
         saveOverride: ((CountdownData, Int) async throws -> Bool)? = nil) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("countdowns.json")
        originalURL = directory.appendingPathComponent("Original document.txt")
        try bytes.write(to: originalURL)
        defaults = UserDefaults(suiteName: suite)!
        let repository = CountdownRepository(fileURL: fileURL)
        let sourceDraft = UUID()
        try await repository.beginAttachmentDraft(sourceDraft)
        var attachments: [EventAttachment] = []
        for _ in 0..<fileCount {
            attachments.append(try await repository.importAttachment(from: originalURL, draftID: sourceDraft))
        }
        source = Countdown(title: "Prepared source", note: note, date: Day(now()), emoji: "🏍️",
                           subtasks: [try Subtask(text: "Completed preparation", isCompleted: true),
                                      try Subtask(text: "Remaining preparation")],
                           showsWeather: true, keepsAfterDate: true, attachments: attachments,
                           links: [EventLink(name: "Route", address: "https://example.com/route")])
        var data = CountdownData()
        data.items = [source]
        data.primaryID = source.id
        _ = try await repository.save(data, revision: 0)
        try await repository.discardAttachmentDraft(sourceDraft)
        store = Store(fileURL: fileURL, disclosureDefaults: defaults, persistenceSaveOverride: saveOverride,
                      now: now, loginItemManagementIsAvailable: false)
        await waitForEventCopy { !store.hasPendingPersistence }
        precondition(store.data == data)
    }

    func copyURL(_ attachment: EventAttachment) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Attachments")
            .appendingPathComponent(attachment.id.uuidString).appendingPathComponent(attachment.name)
    }

    func folders() throws -> [String] {
        let storage = fileURL.deletingLastPathComponent().appendingPathComponent("Attachments")
        guard FileManager.default.fileExists(atPath: storage.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: storage.path).sorted()
    }

    func requireBytes(for attachments: [EventAttachment]) throws {
        for attachment in attachments {
            let actual = try Data(contentsOf: copyURL(attachment))
            precondition(actual == bytes, "Every owned copy must retain the complete original bytes")
        }
    }

    func requireFolders(_ expected: [String]) throws {
        let actual = try folders()
        precondition(actual == expected, "A rejected or cancelled copy must not leave new owned folders")
    }

    func requireFolderCount(_ expected: Int) throws {
        let actual = try folders()
        precondition(actual.count == expected, "Owned folder count must match durable events and active editor imports")
    }

    func close() { defaults.removePersistentDomain(forName: suite) }
}

private func eventCopyDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}

@MainActor
private func waitForEventCopy(_ condition: () -> Bool) async {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while !condition() {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Event copy workflow did not reach its boundary")
        await Task.yield()
    }
}
