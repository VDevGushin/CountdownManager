import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testAttachmentStoreLifecycle(in directory: URL) async throws {
    try await testAttachmentStoreSaveAndRemoval(in: directory.appendingPathComponent("save"))
    try await testAttachmentStoreCancelAndPins(in: directory.appendingPathComponent("cancel"))
    try await testAttachmentStoreFailedSaveRetry(in: directory.appendingPathComponent("retry"))
    try await testAttachmentStoreExpiryFailure(in: directory.appendingPathComponent("expiry"))
    try await testAttachmentBatchLimit(in: directory.appendingPathComponent("limit"))
    try await testHistoricalAttachmentList(in: directory.appendingPathComponent("historical-limit"))
    print("PASS attachment Store workflows: copy/Save/reload/removal, Cancel and active pins, failed Save retry, durable expiry cleanup, override refusal and fifteen-file batch limit")
}

@MainActor
private func testHistoricalAttachmentList(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appendingPathComponent("Historical source.txt")
    let bytes = Data("Existing files remain available".utf8)
    try bytes.write(to: source)
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: fileURL)
    let token = UUID()
    try await repository.beginAttachmentDraft(token)
    var files: [EventAttachment] = []
    for _ in 0..<17 { files.append(try await repository.importAttachment(from: source, draftID: token)) }
    var raw = CountdownData()
    var event = Countdown(title: "Historical seventeen", date: Day(Date()), emoji: "", attachments: files)
    raw.items = [event]
    raw.primaryID = event.id
    let seeded = try await repository.save(raw, revision: 1)
    precondition(seeded)
    try await repository.discardAttachmentDraft(token)
    let suite = "CountdownHistoricalAttachments.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, loginItemManagementIsAvailable: false)
    await waitForAttachmentStore(store)
    precondition(store.data.items[0].attachments == files)
    event.note = "An unrelated edit"
    let edited = await store.save(event, primary: true, requireExisting: true)
    precondition(edited && store.data.items[0].attachments == files)
    let restored = try await CountdownRepository(fileURL: fileURL).load()
    precondition(restored.items == [event] && restored.primaryID == event.id)
    for file in files {
        let copy = try await repository.attachmentURL(for: file)
        try requireAttachmentBytes(at: copy, expected: bytes)
    }
    try requireAttachmentBytes(at: source, expected: bytes)
    print("PASS historical attachment limit: seventeen real copies survive load, unrelated Save and repository reload")
}

@MainActor
private func testAttachmentBatchLimit(in directory: URL) async throws {
    let fixture = try AttachmentStoreFixture(directory: directory)
    defer { fixture.close() }
    let store = fixture.store
    await waitForAttachmentStore(store)
    let firstDraft = UUID()
    let began = await store.beginAttachmentDraft(firstDraft)
    precondition(began)
    let first = await store.importAttachments(from: Array(repeating: fixture.source, count: 14),
                                              draftID: firstDraft, currentAttachments: [])
    precondition(first.count == 14)
    var event = Countdown(title: "Fifteen-file limit", date: fixture.today, emoji: "", attachments: first)
    let saved = await store.save(event, primary: true)
    precondition(saved)
    await store.discardAttachmentDraft(firstDraft)

    let draft = UUID()
    let prepared = await store.beginAttachmentDraft(draft)
    precondition(prepared)
    let diskBefore = try Data(contentsOf: fixture.fileURL)
    let storage = directory.appendingPathComponent("Attachments")
    let foldersBefore = try FileManager.default.contentsOfDirectory(atPath: storage.path).sorted()
    let oversized = await store.importAttachments(from: [fixture.source, fixture.source], draftID: draft,
                                                  currentAttachments: event.attachments)
    precondition(oversized.isEmpty)
    let foldersAfter = try FileManager.default.contentsOfDirectory(atPath: storage.path).sorted()
    precondition(foldersAfter == foldersBefore,
                 "Over-limit batches must be rejected before even the first selected file is copied")
    try requireAttachmentBytes(at: fixture.fileURL, expected: diskBefore)
    let fitting = await store.importAttachments(from: [fixture.source], draftID: draft,
                                                currentAttachments: event.attachments)
    precondition(fitting.count == 1)
    event.attachments += fitting
    let savedFifteen = await store.save(event, primary: true, requireExisting: true)
    precondition(savedFifteen)
    await store.discardAttachmentDraft(draft)

    let replacementDraft = UUID()
    let replacing = await store.beginAttachmentDraft(replacementDraft)
    precondition(replacing)
    let blocked = await store.importAttachments(from: [fixture.source], draftID: replacementDraft,
                                                currentAttachments: event.attachments)
    precondition(blocked.isEmpty)
    let reduced = Array(event.attachments.prefix(14))
    let replacement = await store.importAttachments(from: [fixture.source], draftID: replacementDraft,
                                                    currentAttachments: reduced)
    precondition(replacement.count == 1, "Removing one draft row must free one place before Save")
    await store.discardAttachmentDraft(replacementDraft)
    precondition(!FileManager.default.fileExists(atPath: fixture.copyURL(replacement[0]).path))
    precondition(store.data.items[0].attachments == event.attachments,
                 "Cancel preserves all fifteen saved attachments after a draft replacement")
    for attachment in event.attachments { try requireAttachmentBytes(at: fixture.copyURL(attachment), expected: fixture.bytes) }
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)
}

@MainActor
private func testAttachmentStoreSaveAndRemoval(in directory: URL) async throws {
    let fixture = try AttachmentStoreFixture(directory: directory)
    defer { fixture.close() }
    let store = fixture.store
    await waitForAttachmentStore(store)
    let token = UUID()
    let began = await store.beginAttachmentDraft(token)
    precondition(began)
    let repeated = await store.beginAttachmentDraft(token)
    precondition(repeated)
    let attachment = await store.importAttachment(from: fixture.source, draftID: token)
    guard let attachment else { preconditionFailure("A regular source file must import") }
    let draftPreview = await store.editorAttachmentThumbnailURL(attachment, eventID: nil, draftID: token)
    precondition(draftPreview == fixture.copyURL(attachment), "Imported files must preview before their event is saved")
    precondition(attachment.name == fixture.source.lastPathComponent)
    precondition(attachment.byteCount == Int64(fixture.bytes.count))
    var event = Countdown(title: "Shared attachment", date: fixture.today, emoji: "", attachments: [attachment])
    let saved = await store.save(event, primary: true)
    precondition(saved)
    await store.discardAttachmentDraft(token)
    let copy = fixture.copyURL(attachment)
    let savedPreview = await store.editorAttachmentThumbnailURL(attachment, eventID: event.id, draftID: token)
    precondition(savedPreview == copy, "Saved files must preview in a newly opened editor without a live import token")
    try requireAttachmentBytes(at: copy, expected: fixture.bytes)
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)

    let reloaded = Store(fileURL: fixture.fileURL, disclosureDefaults: fixture.defaults, loginItemManagementIsAvailable: false)
    await waitForAttachmentStore(reloaded)
    precondition(reloaded.data == store.data && reloaded.data.items[0].attachments == [attachment])
    let editorDraft = EventEditorDraft(item: event)
    precondition(editorDraft.countdown(id: event.id, date: event.date).attachments == [attachment],
                 "Opening an editor must preserve attachments alongside the other fields")

    var overrideInvoked = false
    let overridden = Store(fileURL: fixture.fileURL, disclosureDefaults: fixture.defaults,
                           persistenceSaveOverride: { _, _ in overrideInvoked = true; return true },
                           loginItemManagementIsAvailable: false)
    await waitForAttachmentStore(overridden)
    event.attachments = []
    let refused = await overridden.save(event, primary: true, requireExisting: true)
    precondition(!refused && !overrideInvoked && overridden.data.items[0].attachments == [attachment],
                 "A fake writer must not report removal while bypassing the real attachment transaction")
    precondition(FileManager.default.fileExists(atPath: copy.path))

    let removed = await store.save(event, primary: true, requireExisting: true)
    precondition(removed && !FileManager.default.fileExists(atPath: copy.path))
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)
}

@MainActor
private func testAttachmentStoreCancelAndPins(in directory: URL) async throws {
    let fixture = try AttachmentStoreFixture(directory: directory)
    defer { fixture.close() }
    let store = fixture.store
    await waitForAttachmentStore(store)
    let token = UUID()
    let began = await store.beginAttachmentDraft(token)
    precondition(began)
    let imported = await store.importAttachment(from: fixture.source, draftID: token)
    guard let imported else { preconditionFailure("The active draft must accept a file") }
    let copy = fixture.copyURL(imported)
    let otherToken = UUID()
    let otherBegan = await store.beginAttachmentDraft(otherToken)
    precondition(otherBegan)
    let foreignPreview = await store.editorAttachmentThumbnailURL(imported, eventID: nil, draftID: otherToken)
    precondition(foreignPreview == nil, "A different editor token must not authorize this draft's copied file")
    await store.discardAttachmentDraft(otherToken)
    let rejectedFile = await store.importAttachment(from: directory.appendingPathComponent("missing-file"), draftID: token)
    precondition(rejectedFile == nil && FileManager.default.fileExists(atPath: copy.path),
                 "A later import failure must preserve the draft's earlier successful copy")
    let cancelledImport = Task { @MainActor in
        await Task.yield()
        return await store.importAttachment(from: fixture.source, draftID: token)
    }
    cancelledImport.cancel()
    let cancelledResult = await cancelledImport.value
    precondition(cancelledResult == nil)
    let neighbor = Countdown(title: "Unrelated save", date: fixture.today, emoji: "")
    let saved = await store.save(neighbor, primary: false)
    precondition(saved && FileManager.default.fileExists(atPath: copy.path),
                 "An unrelated durable save must preserve another active draft's imported copy")
    let diskBeforeCancel = try Data(contentsOf: fixture.fileURL)
    await store.discardAttachmentDraft(token)
    precondition(!FileManager.default.fileExists(atPath: copy.path))
    let cancelledPreview = await store.editorAttachmentThumbnailURL(imported, eventID: nil, draftID: token)
    precondition(cancelledPreview == nil, "Cancel must invalidate the imported preview URL")
    try requireAttachmentBytes(at: fixture.fileURL, expected: diskBeforeCancel)
    let staleImport = await store.importAttachment(from: fixture.source, draftID: token)
    precondition(staleImport == nil && !store.isImportingAttachments && !store.hasPendingPersistence)
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)

    var overrideInvoked = false
    let overridden = Store(fileURL: fixture.fileURL, disclosureDefaults: fixture.defaults,
                           persistenceSaveOverride: { _, _ in overrideInvoked = true; return true },
                           loginItemManagementIsAvailable: false)
    await waitForAttachmentStore(overridden)
    let overriddenToken = UUID()
    let overrideBegan = await overridden.beginAttachmentDraft(overriddenToken)
    precondition(overrideBegan)
    let staged = await overridden.importAttachment(from: fixture.source, draftID: overriddenToken)
    guard let staged else { preconditionFailure("The fake writer must still allow an isolated draft import") }
    var changed = neighbor
    changed.attachments = [staged]
    let refused = await overridden.save(changed, primary: false, requireExisting: true)
    precondition(!refused && !overrideInvoked && overridden.data.items == [neighbor],
                 "New attachments must not bypass the repository through a fake writer")
    await overridden.discardAttachmentDraft(overriddenToken)
    precondition(!FileManager.default.fileExists(atPath: fixture.copyURL(staged).path))
}

@MainActor
private func testAttachmentStoreFailedSaveRetry(in directory: URL) async throws {
    let fixture = try AttachmentStoreFixture(directory: directory)
    defer { fixture.close() }
    let store = fixture.store
    await waitForAttachmentStore(store)
    let token = UUID()
    let began = await store.beginAttachmentDraft(token)
    precondition(began)
    let imported = await store.importAttachment(from: fixture.source, draftID: token)
    guard let imported else { preconditionFailure("The retry draft must accept a file") }
    let event = Countdown(title: "Retry", date: fixture.today, emoji: "", attachments: [imported])
    try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)
    let failed = await store.save(event, primary: false)
    precondition(!failed && store.data.items.isEmpty)
    precondition(FileManager.default.fileExists(atPath: fixture.copyURL(imported).path),
                 "A failed JSON commit must preserve the active draft's copied files for retry")
    try FileManager.default.removeItem(at: fixture.fileURL)
    let retried = await store.save(event, primary: false)
    precondition(retried && store.data.items == [event])
    await store.discardAttachmentDraft(token)
    try requireAttachmentBytes(at: fixture.copyURL(imported), expected: fixture.bytes)
    var cleared = event
    cleared.attachments = []
    let removed = await store.save(cleared, primary: false, requireExisting: true)
    precondition(removed && !FileManager.default.fileExists(atPath: fixture.copyURL(imported).path))
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)
}

@MainActor
private func testAttachmentStoreExpiryFailure(in directory: URL) async throws {
    var now = Date()
    let fixture = try AttachmentStoreFixture(directory: directory, now: { now })
    defer { fixture.close() }
    let store = fixture.store
    await waitForAttachmentStore(store)
    let token = UUID()
    let began = await store.beginAttachmentDraft(token)
    precondition(began)
    let imported = await store.importAttachment(from: fixture.source, draftID: token)
    guard let imported else { preconditionFailure("The expiring event must accept a file") }
    let event = Countdown(title: "Expires today", date: fixture.today, emoji: "", attachments: [imported])
    let saved = await store.save(event, primary: false)
    precondition(saved)
    await store.discardAttachmentDraft(token)
    let backup = directory.appendingPathComponent("durable.json")
    try FileManager.default.moveItem(at: fixture.fileURL, to: backup)
    try FileManager.default.createDirectory(at: fixture.fileURL, withIntermediateDirectories: true)
    now = Day.calendar.date(byAdding: .day, value: 1, to: event.date.date())!
    store.refresh()
    await waitForAttachmentStore(store)
    precondition(store.data.items == [event] && FileManager.default.fileExists(atPath: fixture.copyURL(imported).path),
                 "Failed expiry persistence must retain both durable metadata and the owned file")
    try FileManager.default.removeItem(at: fixture.fileURL)
    try FileManager.default.moveItem(at: backup, to: fixture.fileURL)
    store.refresh()
    await waitForAttachmentStore(store)
    precondition(store.data.items.isEmpty && !FileManager.default.fileExists(atPath: fixture.copyURL(imported).path))
    try requireAttachmentBytes(at: fixture.source, expected: fixture.bytes)
}

@MainActor
private struct AttachmentStoreFixture {
    let store: Store
    let defaults: UserDefaults
    let suite = "CountdownAttachments.\(UUID().uuidString)"
    let fileURL: URL
    let source: URL
    let today: Day
    let bytes = Data("Synthetic saved conversation\nПример файла".utf8)

    init(directory: URL, now: @escaping () -> Date = Date.init) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("countdowns.json")
        source = directory.appendingPathComponent("Saved conversation.txt")
        try bytes.write(to: source)
        defaults = UserDefaults(suiteName: suite)!
        today = Day(now())
        store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: now, loginItemManagementIsAvailable: false)
    }

    func copyURL(_ attachment: EventAttachment) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Attachments")
            .appendingPathComponent(attachment.id.uuidString).appendingPathComponent(attachment.name)
    }

    func close() { defaults.removePersistentDomain(forName: suite) }
}

@MainActor
private func waitForAttachmentStore(_ store: Store) async {
    let timeout = ProcessInfo.processInfo.systemUptime + 5
    while store.hasPendingPersistence {
        precondition(ProcessInfo.processInfo.systemUptime < timeout, "Attachment Store work did not settle")
        await Task.yield()
    }
}

private func requireAttachmentBytes(at url: URL, expected: Data) throws {
    let bytes = try Data(contentsOf: url)
    precondition(bytes == expected, "Attachment and original file bytes must stay unchanged")
}
