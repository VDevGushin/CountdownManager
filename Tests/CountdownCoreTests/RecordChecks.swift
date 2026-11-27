import CountdownCore
import Foundation

func testRecordRepositoryAndAttachmentIsolation() async throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("CountdownRecords-\(UUID().uuidString)")
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? manager.removeItem(at: directory) }
    let eventURL = directory.appendingPathComponent("countdowns.json")
    let recordURL = CountdownRepository.recordsFileURL(beside: eventURL)
    let source = directory.appendingPathComponent("Parts.txt")
    let sourceBytes = Data("Parts and order number".utf8)
    try sourceBytes.write(to: source)
    let repository = CountdownRepository(fileURL: eventURL)

    let empty = try await repository.loadRecords()
    precondition(empty.isEmpty && !manager.fileExists(atPath: recordURL.path))
    let eventDraft = UUID()
    let recordDraft = UUID()
    try await repository.beginAttachmentDraft(eventDraft)
    try await repository.beginAttachmentDraft(recordDraft, in: .records)
    let eventAttachment = try await repository.importAttachment(from: source, draftID: eventDraft)
    let recordAttachment = try await repository.importAttachment(from: source, draftID: recordDraft)
    let eventFile = try await repository.draftAttachmentURL(for: eventAttachment, draftID: eventDraft)
    let recordFile = try await repository.draftAttachmentURL(for: recordAttachment, draftID: recordDraft)
    precondition(eventFile.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Attachments")
    precondition(recordFile.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "RecordAttachments")

    let date = Day(Date())
    let event = Countdown(title: "An event", date: date, emoji: "", attachments: [eventAttachment])
    var eventData = CountdownData()
    try eventData.save(event, primary: true, today: date)
    let saved = try await repository.save(eventData, revision: 1)
    precondition(saved)
    try await repository.discardAttachmentDraft(eventDraft)
    let eventBytes = try Data(contentsOf: eventURL)
    let task = try Subtask(text: "Order part", isCompleted: true)
    let link = EventLink(name: "Catalog", address: "https://example.org/parts")
    let record = try UndatedRecord(
        title: "  Car  ", note: "  Reference notes  ", subtasks: [task], attachments: [recordAttachment], links: [link]
    ).normalized()
    precondition(record.title == "Car" && record.note == "Reference notes")
    try await repository.saveRecords([record])
    try await repository.discardAttachmentDraft(recordDraft)
    let recordBytes = try Data(contentsOf: recordURL)
    let retainedEventBytes = try Data(contentsOf: eventURL)
    precondition(retainedEventBytes == eventBytes, "The record writer must never rewrite event storage")

    // Older builds only exercise the event entry points and attachment root.
    let eventOnlyRepository = CountdownRepository(fileURL: eventURL)
    let reloadedEvents = try await eventOnlyRepository.load()
    precondition(reloadedEvents == eventData)
    let writtenByEventOnlyWriter = try await eventOnlyRepository.save(reloadedEvents, revision: 2)
    precondition(writtenByEventOnlyWriter)
    let retainedRecordBytes = try Data(contentsOf: recordURL)
    precondition(retainedRecordBytes == recordBytes && manager.fileExists(atPath: recordFile.path))

    var crossCollection = record
    crossCollection.attachments = [eventAttachment]
    do {
        try await repository.saveRecords([crossCollection])
        preconditionFailure("Event attachment metadata cannot claim an event's file in the record collection")
    } catch {
        let unchanged = try await repository.loadRecords()
        precondition(unchanged == [record])
    }

    try await testCorruptRecordStoragePreservesBothCollections(
        eventURL: eventURL, recordURL: recordURL, recordFile: recordFile, record: record, events: eventData
    )
    try await testMissingRecordStoragePreservesBothCollections(
        repository: repository, eventURL: eventURL, recordURL: recordURL, recordFile: recordFile,
        record: record, events: eventData
    )

    try await repository.saveRecords([])
    let restarted = CountdownRepository(fileURL: eventURL)
    let deletedRecords = try await restarted.loadRecords()
    precondition(deletedRecords.isEmpty)
    precondition(!manager.fileExists(atPath: recordFile.path) && manager.fileExists(atPath: eventFile.path))
    let remainingSourceBytes = try Data(contentsOf: source)
    precondition(remainingSourceBytes == sourceBytes, "Deleting a record only collects the copy the application owns")
    try await testAttachmentIDCollisionAcrossCollections(in: directory.appendingPathComponent("collision"))
    try await testAbandonedFirstRecordImport(in: directory.appendingPathComponent("first-import"))
    print("PASS record repository: own snapshot and attachment root, unaffected event writer, corrupt-data protection and owned cleanup")
}

private func testAttachmentIDCollisionAcrossCollections(in directory: URL) async throws {
    let manager = FileManager.default
    try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    let eventURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: eventURL)
    try await repository.saveRecords([])
    let recordRoot = directory.appendingPathComponent("RecordAttachments")
    let eventDraft = UUID()
    let source = directory.appendingPathComponent("Owner.txt")
    let eventBytes = Data("event".utf8)
    let recordBytes = Data("notes".utf8)
    try eventBytes.write(to: source)
    try await repository.beginAttachmentDraft(eventDraft)
    let metadata = try await repository.importAttachment(from: source, draftID: eventDraft)
    let eventCopy = try await repository.draftAttachmentURL(for: metadata, draftID: eventDraft)
    let recordFolder = recordRoot.appendingPathComponent(metadata.id.uuidString)
    try manager.createDirectory(at: recordRoot, withIntermediateDirectories: true)
    // Restore an owned copy carrying the same metadata in the other collection.
    try manager.copyItem(at: eventCopy.deletingLastPathComponent(), to: recordFolder)
    let recordCopy = recordFolder.appendingPathComponent(metadata.name)
    try recordBytes.write(to: recordCopy, options: .atomic)

    let day = Day(Date())
    let ownerID = UUID()
    var events = CountdownData()
    let event = Countdown(id: ownerID, title: "Dated", date: day, emoji: "", attachments: [metadata])
    try events.save(event, primary: true, today: day)
    let saved = try await repository.save(events, revision: 1)
    precondition(saved)
    let record = UndatedRecord(id: ownerID, title: "Undated", attachments: [metadata])
    try await repository.saveRecords([record])
    try await repository.discardAttachmentDraft(eventDraft)

    let reopened = CountdownRepository(fileURL: eventURL)
    let restoredEventURL = try await reopened.attachmentURL(for: metadata)
    let restoredRecordURL = try await reopened.attachmentURL(for: metadata, in: .records)
    let restoredEventBytes = try Data(contentsOf: restoredEventURL)
    let restoredRecordBytes = try Data(contentsOf: restoredRecordURL)
    precondition(restoredEventBytes == eventBytes && restoredRecordBytes == recordBytes,
                 "Equal event, record and attachment identities must still resolve their respective copies")
    try await reopened.saveRecords([])
    precondition(!manager.fileExists(atPath: recordCopy.path) && manager.fileExists(atPath: eventCopy.path),
                 "Deleting a record must collect only the record's copy when IDs collide")
}

private func testMissingRecordStoragePreservesBothCollections(
    repository: CountdownRepository,
    eventURL: URL,
    recordURL: URL,
    recordFile: URL,
    record: UndatedRecord,
    events: CountdownData
) async throws {
    let manager = FileManager.default
    let metadataBackup = recordURL.appendingPathExtension("test-restore")
    let intactFile = try Data(contentsOf: recordFile)
    try manager.moveItem(at: recordURL, to: metadataBackup)
    let fresh = CountdownRepository(fileURL: eventURL)
    do {
        _ = try await fresh.loadRecords()
        preconditionFailure("Missing records metadata must not interpret existing owned copies as abandoned drafts")
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
    for writer in [fresh, repository] {
        do {
            try await writer.saveRecords([])
            preconditionFailure("Neither a fresh reader nor a live writer may replace missing record metadata")
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
    }
    let reloadedEvents = try await fresh.load()
    let savedEvents = try await fresh.save(reloadedEvents, revision: 1)
    let retainedFile = try Data(contentsOf: recordFile)
    precondition(savedEvents && reloadedEvents == events, "A missing record snapshot may not block event writes")
    precondition(retainedFile == intactFile && !manager.fileExists(atPath: recordURL.path))
    try manager.moveItem(at: metadataBackup, to: recordURL)
    let restoredRecords = try await fresh.loadRecords()
    precondition(restoredRecords == [record])
}

private func testAbandonedFirstRecordImport(in directory: URL) async throws {
    let manager = FileManager.default
    let eventURL = directory.appendingPathComponent("countdowns.json")
    let recordURL = CountdownRepository.recordsFileURL(beside: eventURL)
    let repository = CountdownRepository(fileURL: eventURL)
    let draft = UUID()
    let empty = try await repository.loadRecords()
    try await repository.beginAttachmentDraft(draft, in: .records)
    precondition(empty.isEmpty && !manager.fileExists(atPath: recordURL.path),
                 "Launching and opening a draft alone do not initialize a record snapshot")

    let text = try await repository.createTextAttachment(TextAttachment(name: "Draft", text: "Temporary"), draftID: draft)
    let copy = try await repository.draftAttachmentURL(for: text, draftID: draft)
    let initialSnapshot = try JSONDecoder().decode([UndatedRecord].self, from: Data(contentsOf: recordURL))
    precondition(initialSnapshot.isEmpty && manager.fileExists(atPath: copy.path),
                 "First import must leave a known empty snapshot while the copy is pinned")

    let reopened = CountdownRepository(fileURL: eventURL)
    let restored = try await reopened.loadRecords()
    precondition(restored.isEmpty && !manager.fileExists(atPath: copy.path),
                 "Cold startup removes an abandoned draft only after reading the intentional empty snapshot")
    precondition(!manager.fileExists(atPath: eventURL.path))
}

private func testCorruptRecordStoragePreservesBothCollections(
    eventURL: URL,
    recordURL: URL,
    recordFile: URL,
    record: UndatedRecord,
    events: CountdownData
) async throws {
    let intactBytes = try Data(contentsOf: recordURL)
    let corruptBytes = Data("invalid local record data".utf8)
    try corruptBytes.write(to: recordURL, options: .atomic)
    defer { try? intactBytes.write(to: recordURL, options: .atomic) }
    let restarted = CountdownRepository(fileURL: eventURL)
    do {
        _ = try await restarted.loadRecords()
        preconditionFailure("Malformed record data must not establish a cleanup snapshot")
    } catch is DecodingError {}
    let reloadedEvents = try await restarted.load()
    precondition(reloadedEvents == events)
    do {
        try await restarted.saveRecords([record])
        preconditionFailure("A corrupted record file cannot be silently replaced")
    } catch is DecodingError {}
    let retainedCorruptBytes = try Data(contentsOf: recordURL)
    let manager = FileManager.default
    precondition(retainedCorruptBytes == corruptBytes && manager.fileExists(atPath: recordFile.path))

    try manager.removeItem(at: recordURL)
    let missingTarget = recordURL.appendingPathExtension("missing")
    try manager.createSymbolicLink(atPath: recordURL.path, withDestinationPath: missingTarget.path)
    let danglingRepository = CountdownRepository(fileURL: eventURL)
    do {
        _ = try await danglingRepository.loadRecords()
        preconditionFailure("A dangling metadata symlink must not authorize empty-collection cleanup")
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {}
    let attributes = try manager.attributesOfItem(atPath: recordURL.path)
    precondition(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
    precondition(manager.fileExists(atPath: recordFile.path))
    try manager.removeItem(at: recordURL)
}
