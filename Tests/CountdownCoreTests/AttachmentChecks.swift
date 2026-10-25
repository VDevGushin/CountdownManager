import Foundation
import CountdownCore

func testAttachmentCountLimitAndLegacyPreservation() throws {
    let today = Day(Date(timeIntervalSince1970: 1_800_000_000))
    let files = try (1...17).map { try EventAttachment(name: "File \($0).txt", byteCount: Int64($0)) }
    for count in [0, 14, 15] {
        var data = CountdownData()
        let event = Countdown(title: "Within limit", date: today, emoji: "", attachments: Array(files.prefix(count)))
        try data.save(event, primary: false, today: today)
        try attachmentCheck(data.items == [event])
    }
    var empty = CountdownData()
    do {
        try empty.save(Countdown(title: "Too many", date: today, emoji: "", attachments: Array(files.prefix(16))),
                       primary: false, today: today)
        preconditionFailure("A new event must not exceed fifteen attachments")
    } catch EventAttachmentError.limitExceeded {}
    try attachmentCheck(empty.items.isEmpty && empty.primaryID == nil)

    var legacy = Countdown(title: "Historical files", date: today, emoji: "", attachments: files)
    var data = CountdownData()
    data.items = [legacy]
    data.primaryID = legacy.id
    let encoded = try JSONEncoder().encode(data)
    data = try JSONDecoder().decode(CountdownData.self, from: encoded)
    try attachmentCheck(data.items[0].attachments == files, "Loading must never truncate historical files")
    legacy.note = "An unrelated edit remains available"
    try data.save(legacy, primary: true, today: today)
    try attachmentCheck(data.items[0] == legacy)

    let additional = try EventAttachment(name: "New file.txt", byteCount: 1)
    let beforeRejection = data
    var replaced = legacy
    replaced.attachments[0] = additional
    do {
        try data.save(replaced, primary: false, today: today)
        preconditionFailure("Replacing an identity above the limit is still a new attachment")
    } catch EventAttachmentError.limitExceeded {}
    try attachmentCheck(data == beforeRejection, "Rejected edits preserve data and favorite")
    legacy.attachments.removeLast()
    try data.save(legacy, primary: true, today: today)
    try attachmentCheck(data.items[0].attachments.count == 16, "Legacy files can be reduced without a forced batch removal")
    legacy.attachments = Array(legacy.attachments.prefix(14)) + [additional]
    try data.save(legacy, primary: true, today: today)
    try attachmentCheck(data.items[0].attachments.count == 15 && data.items[0].attachments.last == additional)

    var expired = beforeRejection
    expired.items[0].date = Day(today.date().addingTimeInterval(-86_400))
    let untouchedExpired = expired
    do {
        try expired.save(beforeRejection.items[0], primary: false, today: today)
        preconditionFailure("An expired identity cannot grant a historical over-limit allowance")
    } catch EventAttachmentError.limitExceeded {}
    try attachmentCheck(expired == untouchedExpired)
}

func testAttachmentMetadataCompatibilityAndValidation() throws {
    let legacy = """
    {"id":"28B1DD31-4671-4BD1-AB0D-3F6232967299","title":"Legacy","date":{"year":2027,"month":5,"day":1},"emoji":""}
    """
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    var event = try decoder.decode(Countdown.self, from: Data(legacy.utf8))
    try attachmentCheck(event.attachments.isEmpty)
    let object = try JSONSerialization.jsonObject(with: encoder.encode(event)) as? [String: Any]
    try attachmentCheck(object?["attachments"] == nil, "Empty attachments preserve the legacy representation")
    let attachment = try EventAttachment(name: "Переписка.txt", byteCount: 420)
    event.attachments = [attachment]
    let encoded = try encoder.encode(event)
    try attachmentCheck(try decoder.decode(Countdown.self, from: encoded) == event)
    let attachmentObject = try JSONSerialization.jsonObject(with: encoder.encode(attachment)) as? [String: Any]
    try attachmentCheck(Set(attachmentObject.map { Array($0.keys) } ?? []) == Set(["id", "name", "byteCount"]))
    for name in ["", ".", "..", "../outside", "a/b", "a\\b", "nul\0name"] {
        do {
            _ = try EventAttachment(name: name, byteCount: 0)
            preconditionFailure("Attachment names cannot address paths")
        } catch EventAttachmentError.invalidMetadata {}
        let invalid: [String: Any] = ["id": UUID().uuidString, "name": name, "byteCount": 0]
        do {
            _ = try decoder.decode(EventAttachment.self, from: JSONSerialization.data(withJSONObject: invalid))
            preconditionFailure("Persisted traversal metadata must also fail")
        } catch EventAttachmentError.invalidMetadata {}
    }
    do {
        _ = try EventAttachment(name: "file.txt", byteCount: -1)
        preconditionFailure("Negative file sizes are invalid metadata")
    } catch EventAttachmentError.invalidMetadata {}
    event.attachments = [attachment, attachment]
    do {
        _ = try decoder.decode(Countdown.self, from: encoder.encode(event))
        preconditionFailure("Duplicate attachment identities cannot enter a rendered event")
    } catch EventAttachmentError.invalidMetadata {}
}

func testAttachmentCopySaveCancelAndRestart() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("Снимок.jpg", contents: "original photo bytes")
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    try await repository.beginAttachmentDraft(draft)
    let first = try await repository.importAttachment(from: source, draftID: draft)
    let firstURL = try await repository.attachmentURL(for: first)
    let previewURL = try await repository.draftAttachmentURL(for: first, draftID: draft)
    try attachmentCheck(previewURL == firstURL, "The active draft must preview its copied file before Save")
    let foreignDraft = UUID()
    try await repository.beginAttachmentDraft(foreignDraft)
    do {
        _ = try await repository.draftAttachmentURL(for: first, draftID: foreignDraft)
        preconditionFailure("Another draft must not authorize this copied file")
    } catch EventAttachmentError.unavailableFile {}
    try await repository.discardAttachmentDraft(foreignDraft)
    try attachmentCheck(firstURL.lastPathComponent == source.lastPathComponent)
    try attachmentCheck(firstURL != source && first.byteCount == 20)
    try attachmentCheck(try Data(contentsOf: firstURL) == Data(contentsOf: source))
    var data = fixture.data(attachments: [first])
    let saved = try await repository.save(data, revision: 1)
    try attachmentCheck(saved)
    try await repository.discardAttachmentDraft(draft)
    do {
        _ = try await repository.draftAttachmentURL(for: first, draftID: draft)
        preconditionFailure("An ended draft must not authorize previews, even when its file was saved")
    } catch EventAttachmentError.unavailableFile {}
    try attachmentCheck(FileManager.default.fileExists(atPath: firstURL.path), "Ending a saved draft retains durable copies")

    let cancelledDraft = UUID()
    try await repository.beginAttachmentDraft(cancelledDraft)
    let cancelled = try await repository.importAttachment(from: source, draftID: cancelledDraft)
    let cancelledURL = try await repository.attachmentURL(for: cancelled)
    try attachmentCheck(cancelled.id != first.id)
    try await repository.discardAttachmentDraft(cancelledDraft)
    try attachmentCheck(!FileManager.default.fileExists(atPath: cancelledURL.path))
    try attachmentCheck(FileManager.default.fileExists(atPath: firstURL.path))
    try attachmentCheck(try String(contentsOf: source) == "original photo bytes")

    let freshRepository = CountdownRepository(fileURL: fixture.json)
    let restored = try await freshRepository.load()
    try attachmentCheck(restored == data)
    let restoredURL = try await freshRepository.attachmentURL(for: restored.items[0].attachments[0])
    try attachmentCheck(try String(contentsOf: restoredURL) == "original photo bytes")
    try Data("external editor changed the owned copy length".utf8).write(to: restoredURL)
    let externallyEdited = try await freshRepository.attachmentURL(for: first)
    try attachmentCheck(try String(contentsOf: externallyEdited) == "external editor changed the owned copy length")
    try attachmentCheck(try String(contentsOf: source) == "original photo bytes")
    data.items.removeAll()
    let deleted = try await freshRepository.save(data, revision: 1)
    try attachmentCheck(deleted && !FileManager.default.fileExists(atPath: firstURL.path))
    try attachmentCheck(try String(contentsOf: source) == "original photo bytes", "Event deletion must never delete originals")
}

func testAttachmentFailedAndSupersededPersistence() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("document.pdf", contents: "PDF original")
    let repository = CountdownRepository(fileURL: fixture.json)
    let firstDraft = UUID()
    try await repository.beginAttachmentDraft(firstDraft)
    let first = try await repository.importAttachment(from: source, draftID: firstDraft)
    let firstURL = try await repository.attachmentURL(for: first)
    let original = fixture.data(attachments: [first])
    _ = try await repository.save(original, revision: 1)
    try await repository.discardAttachmentDraft(firstDraft)
    let originalBytes = try Data(contentsOf: fixture.json)

    let secondDraft = UUID()
    try await repository.beginAttachmentDraft(secondDraft)
    let second = try await repository.importAttachment(from: source, draftID: secondDraft)
    let secondURL = try await repository.attachmentURL(for: second)
    var replacement = original
    replacement.items[0].attachments = [second]
    try FileManager.default.removeItem(at: fixture.json)
    try FileManager.default.createDirectory(at: fixture.json, withIntermediateDirectories: false)
    do {
        _ = try await repository.save(replacement, revision: 2)
        preconditionFailure("Atomic JSON replacement must fail against a directory")
    } catch {}
    try attachmentCheck(FileManager.default.fileExists(atPath: firstURL.path), "Failure preserves the last durable copy")
    try attachmentCheck(FileManager.default.fileExists(atPath: secondURL.path), "Failure preserves staged copies for retry")
    try FileManager.default.removeItem(at: fixture.json)
    try originalBytes.write(to: fixture.json, options: .atomic)
    let reloaded = try await repository.load()
    try attachmentCheck(reloaded == original && FileManager.default.fileExists(atPath: secondURL.path))
    let retried = try await repository.save(replacement, revision: 2)
    try attachmentCheck(retried && !FileManager.default.fileExists(atPath: firstURL.path))
    try await repository.discardAttachmentDraft(secondDraft)
    let superseded = try await repository.save(original, revision: 1)
    try attachmentCheck(!superseded && FileManager.default.fileExists(atPath: secondURL.path))
    try attachmentCheck(try String(contentsOf: source) == "PDF original")
    let durable = try await repository.load()
    try attachmentCheck(durable == replacement)
}

func testAttachmentExpiryAndAbandonedDraftCleanup() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("export.txt", contents: "chat export")
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    let expiring = try await repository.importAttachment(from: source, draftID: draft)
    let surviving = try await repository.importAttachment(from: source, draftID: draft)
    let expiringURL = try await repository.attachmentURL(for: expiring)
    let survivingURL = try await repository.attachmentURL(for: surviving)
    var data = fixture.data(attachments: [expiring])
    let neighbor = Countdown(title: "Future", date: Day(Date(timeIntervalSince1970: 2_000_000_000)), emoji: "",
                             attachments: [surviving])
    data.items.append(neighbor)
    _ = try await repository.save(data, revision: 1)
    try await repository.discardAttachmentDraft(draft)
    data.normalize(today: neighbor.date)
    _ = try await repository.save(data, revision: 2)
    try attachmentCheck(!FileManager.default.fileExists(atPath: expiringURL.path))
    try attachmentCheck(FileManager.default.fileExists(atPath: survivingURL.path))
    let abandoned = try await abandonedAttachment(fixture: fixture, source: source)
    try attachmentCheck(FileManager.default.fileExists(atPath: abandoned.path))
    let restarted = CountdownRepository(fileURL: fixture.json)
    _ = try await restarted.load()
    try attachmentCheck(!FileManager.default.fileExists(atPath: abandoned.path), "Restart collects abandoned imports")
    try attachmentCheck(FileManager.default.fileExists(atPath: survivingURL.path))
    try attachmentCheck(try String(contentsOf: source) == "chat export")
}

private func abandonedAttachment(fixture: AttachmentFixture, source: URL) async throws -> URL {
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    let attachment = try await repository.importAttachment(from: source, draftID: draft)
    return try await repository.attachmentURL(for: attachment)
}

func testAttachmentFilesystemAndCorruptJSONSafety() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("original.txt", contents: "keep original")
    let alias = fixture.root.appendingPathComponent("alias.txt")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: source)
    let package = fixture.root.appendingPathComponent("Example.app", isDirectory: true)
    try FileManager.default.createDirectory(at: package, withIntermediateDirectories: false)
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    for invalid in [alias, package, fixture.root, URL(string: "https://example.invalid/file.pdf")!] {
        do {
            _ = try await repository.importAttachment(from: invalid, draftID: draft)
            preconditionFailure("Only regular local files are supported")
        } catch {}
    }
    let attachment = try await repository.importAttachment(from: source, draftID: draft)
    let attachmentURL = try await repository.attachmentURL(for: attachment)
    let unknown = attachmentURL.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: unknown, withIntermediateDirectories: false)
    let unknownFile = unknown.appendingPathComponent("user-file.txt")
    try Data("unknown data".utf8).write(to: unknownFile)
    try Data("{corrupt".utf8).write(to: fixture.json)
    let fresh = CountdownRepository(fileURL: fixture.json)
    do {
        _ = try await fresh.load()
        preconditionFailure("Corrupt event JSON cannot authorize cleanup")
    } catch {}
    try attachmentCheck(FileManager.default.fileExists(atPath: attachmentURL.path))
    try attachmentCheck(try String(contentsOf: fixture.json) == "{corrupt")
    try FileManager.default.removeItem(at: fixture.json)
    try await repository.discardAttachmentDraft(draft)
    try attachmentCheck(!FileManager.default.fileExists(atPath: attachmentURL.path))
    try attachmentCheck(try String(contentsOf: unknownFile) == "unknown data")
    try attachmentCheck(try String(contentsOf: source) == "keep original")
}

func testAttachmentCleanupFailureDoesNotUndoJSONSave() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("original.txt", contents: "keep original")
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    let attachment = try await repository.importAttachment(from: source, draftID: draft)
    let copy = try await repository.attachmentURL(for: attachment)
    _ = try await repository.save(fixture.data(attachments: [attachment]), revision: 1)
    try await repository.discardAttachmentDraft(draft)
    try FileManager.default.removeItem(at: copy)
    try FileManager.default.createSymbolicLink(at: copy, withDestinationURL: source)
    let saved = try await repository.save(CountdownData(), revision: 2)
    let cleanupFailed = await repository.attachmentCleanupFailed
    try attachmentCheck(saved && cleanupFailed, "Cleanup trouble must never report a committed JSON write as failed")
    try attachmentCheck(try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fixture.json)).items.isEmpty)
    try attachmentCheck(try String(contentsOf: source) == "keep original")
    try FileManager.default.removeItem(at: copy)
    try await repository.cleanupAttachments()
    let recovered = await repository.attachmentCleanupFailed
    try attachmentCheck(!recovered && !FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
}

func testAttachmentRootSymlinkAndSourceIndependence() async throws {
    let fixture = try AttachmentFixture()
    defer { fixture.remove() }
    let source = try fixture.source("source.txt", contents: "before")
    let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    let sentinel = outside.appendingPathComponent("untouched.txt")
    try Data("outside original".utf8).write(to: sentinel)
    let storage = fixture.json.deletingLastPathComponent().appendingPathComponent("Attachments")
    try FileManager.default.createDirectory(at: storage.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: storage, withDestinationURL: outside)
    let repository = CountdownRepository(fileURL: fixture.json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    do {
        _ = try await repository.importAttachment(from: source, draftID: draft)
        preconditionFailure("The attachment root must never follow a symlink")
    } catch EventAttachmentError.unsafeStorage {}
    let saved = try await repository.save(CountdownData(), revision: 1)
    let cleanupFailed = await repository.attachmentCleanupFailed
    try attachmentCheck(saved && cleanupFailed)
    try attachmentCheck(try String(contentsOf: sentinel) == "outside original")
    try FileManager.default.removeItem(at: storage)
    let attachment = try await repository.importAttachment(from: source, draftID: draft)
    let copy = try await repository.attachmentURL(for: attachment)
    try Data("after source changed".utf8).write(to: source)
    try attachmentCheck(try String(contentsOf: copy) == "before", "Imports are copies, never source links")
    try await repository.discardAttachmentDraft(draft)
    try attachmentCheck(try String(contentsOf: source) == "after source changed")
    try attachmentCheck(try String(contentsOf: sentinel) == "outside original")
}

private struct AttachmentFixture {
    let root: URL
    let json: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownAttachments-\(UUID().uuidString)")
        json = root.appendingPathComponent("data/countdowns.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func source(_ name: String, contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    func data(attachments: [EventAttachment]) -> CountdownData {
        var data = CountdownData()
        data.items = [Countdown(title: "Files", date: Day(Date(timeIntervalSince1970: 1_800_000_000)),
                                emoji: "", attachments: attachments)]
        return data
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func attachmentCheck(_ condition: @autoclosure () throws -> Bool, _ message: String = "") throws {
    let passed = try condition()
    precondition(passed, message)
}
