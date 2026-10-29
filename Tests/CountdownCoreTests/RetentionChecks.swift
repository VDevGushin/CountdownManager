import CountdownCore
import Foundation

func testRetentionMetadataCompatibility() throws {
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()
    let ordinary = Countdown(title: "Legacy", date: retentionDay(2026, 10, 29), emoji: "")
    guard var object = try JSONSerialization.jsonObject(with: encoder.encode(ordinary)) as? [String: Any] else {
        preconditionFailure("A countdown must encode as an object")
    }
    precondition(object["keepsAfterDate"] == nil)
    let legacy = try decoder.decode(Countdown.self, from: encoder.encode(ordinary))
    precondition(!legacy.keepsAfterDate && legacy == ordinary)
    object["keepsAfterDate"] = false
    let explicitFalse = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
    precondition(!explicitFalse.keepsAfterDate)
    for invalid: Any in [NSNull(), "true", 1, [], [:]] {
        object["keepsAfterDate"] = invalid
        do {
            _ = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: object))
            preconditionFailure("Retention metadata must be a Boolean when present")
        } catch is DecodingError {}
    }
    var kept = ordinary
    kept.keepsAfterDate = true
    let roundTrip = try decoder.decode(Countdown.self, from: encoder.encode(kept))
    precondition(roundTrip == kept)
    let encoded = try JSONSerialization.jsonObject(with: encoder.encode(kept)) as? [String: Any]
    precondition(encoded?["keepsAfterDate"] as? Bool == true)
}

func testRetainedCivilDayLifecycleAndValidation() throws {
    let boundaries = [
        (retentionDay(2026, 10, 29), retentionDay(2026, 10, 30)),
        (retentionDay(2026, 12, 31), retentionDay(2027, 1, 1)),
        (retentionDay(2028, 2, 28), retentionDay(2028, 2, 29)),
        (retentionDay(2028, 2, 29), retentionDay(2028, 3, 1))
    ]
    for (today, tomorrow) in boundaries {
        let task = try Subtask(text: "Still available")
        var retained = Countdown(title: "Retained", note: "Keep note", date: today, emoji: "",
                                 subtasks: [task], keepsAfterDate: true)
        let ordinary = Countdown(title: "Ordinary", date: today, emoji: "")
        var data = CountdownData()
        try data.save(retained, primary: true, today: today)
        try data.save(ordinary, primary: false, today: today)
        data.normalize(today: today)
        precondition(data.items == [retained, ordinary])
        data.normalize(today: tomorrow)
        precondition(data.items == [retained] && data.primaryID == retained.id)
        retained.title = "Edited after date"
        try data.save(retained, primary: true, today: tomorrow)
        try data.toggleSubtask(eventID: retained.id, subtaskID: task.id, today: tomorrow)
        precondition(data.items[0].subtasks[0].isCompleted)
        retained = data.items[0]
        let snapshot = data
        for candidate in [
            Countdown(title: "Backdated", date: today, emoji: "", keepsAfterDate: true),
            replacingRetention(retained, keeps: false),
            replacingRetention(retained, date: retentionDay(2026, 1, 1))
        ] {
            do {
                try data.save(candidate, primary: false, today: tomorrow)
                preconditionFailure("A new, unretained or changed past date must not save")
            } catch CountdownError.date {}
            precondition(data == snapshot, "Rejected edits must preserve the complete snapshot")
        }
        retained.date = tomorrow
        retained.keepsAfterDate = false
        try data.save(retained, primary: true, today: tomorrow)
        precondition(data.items == [retained], "A past event may move to today and stop retention")

        var expired = CountdownData()
        expired.items = [ordinary]
        var staleDraft = ordinary
        staleDraft.keepsAfterDate = true
        do {
            try expired.save(staleDraft, primary: true, today: tomorrow)
            preconditionFailure("An unsaved retention choice must not resurrect an expired event")
        } catch CountdownError.date {}
        precondition(expired.items == [ordinary] && expired.primaryID == nil)
    }
    print("PASS retained core lifecycle: ordinary expiry, primary preservation, post-date edits/tasks, four civil boundaries, rejected backdating and stale drafts")
}

func testRetainedLegacyAllowances() throws {
    let eventDate = retentionDay(2026, 10, 27)
    let today = retentionDay(2026, 10, 29)
    let files = try (1...17).map { try EventAttachment(name: "Existing \($0).txt", byteCount: 1) }
    var legacy = Countdown(title: "Legacy retained", note: String(repeating: "я", count: 180), date: eventDate,
                           emoji: "", keepsAfterDate: true, attachments: files)
    var data = CountdownData()
    data.items = [legacy]
    data.primaryID = legacy.id
    data = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
    legacy.title = "Edited with original files"
    try data.save(legacy, primary: true, today: today)
    precondition(data.items == [legacy])
    let snapshot = data
    var oversized = legacy
    oversized.note = String(repeating: "я", count: 181)
    do {
        try data.save(oversized, primary: false, today: today)
        preconditionFailure("Retained legacy notes may not grow")
    } catch CountdownError.note {}
    precondition(data == snapshot)
    oversized = legacy
    oversized.attachments[0] = try EventAttachment(name: "New.txt", byteCount: 1)
    do {
        try data.save(oversized, primary: false, today: today)
        preconditionFailure("Retained over-limit collections may not gain new identities")
    } catch EventAttachmentError.limitExceeded {}
    precondition(data == snapshot)
    legacy.note = String(repeating: "я", count: 160)
    legacy.attachments.removeLast()
    try data.save(legacy, primary: true, today: today)
    precondition(data.items == [legacy])
    oversized = legacy
    oversized.note = String(repeating: "я", count: 161)
    do {
        try data.save(oversized, primary: false, today: today)
        preconditionFailure("Shortening a retained note must reduce its allowance")
    } catch CountdownError.note {}
}

func testRetainedAttachmentDurabilityAndDeleteFailure() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("CountdownRetention-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("Original.txt")
    let bytes = Data("Retained original and copied bytes".utf8)
    try bytes.write(to: source)
    let json = root.appendingPathComponent("countdowns.json")
    let repository = CountdownRepository(fileURL: json)
    let draft = UUID()
    try await repository.beginAttachmentDraft(draft)
    let retainedFile = try await repository.importAttachment(from: source, draftID: draft)
    let expiredFile = try await repository.importAttachment(from: source, draftID: draft)
    let retainedCopy = try await repository.attachmentURL(for: retainedFile)
    let expiredCopy = try await repository.attachmentURL(for: expiredFile)
    let day = retentionDay(2026, 10, 29)
    let tomorrow = retentionDay(2026, 10, 30)
    let retained = Countdown(title: "Keep files", date: day, emoji: "", keepsAfterDate: true, attachments: [retainedFile])
    let ordinary = Countdown(title: "Expire files", date: day, emoji: "", attachments: [expiredFile])
    var data = CountdownData()
    try data.save(retained, primary: true, today: day)
    try data.save(ordinary, primary: false, today: day)
    _ = try await repository.save(data, revision: 1)
    try await repository.discardAttachmentDraft(draft)
    data.normalize(today: tomorrow)
    _ = try await repository.save(data, revision: 2)
    let fresh = CountdownRepository(fileURL: json)
    let restored = try await fresh.load()
    precondition(restored == data && restored.items == [retained] && restored.primaryID == retained.id)
    let resolved = try await fresh.attachmentURL(for: retainedFile)
    precondition(resolved == retainedCopy && !FileManager.default.fileExists(atPath: expiredCopy.path))
    let disk = try Data(contentsOf: json)
    let backup = root.appendingPathComponent("Backup.json")
    try FileManager.default.moveItem(at: json, to: backup)
    try FileManager.default.createDirectory(at: json, withIntermediateDirectories: true)
    var deleted = data
    deleted.delete(retained.id, today: tomorrow)
    do {
        _ = try await fresh.save(deleted, revision: 3)
        preconditionFailure("Directory at JSON destination must reject the delete write")
    } catch {}
    let keptBytes = try Data(contentsOf: retainedCopy)
    precondition(keptBytes == bytes, "Failed deletion must retain the owned copy")
    try FileManager.default.removeItem(at: json)
    try FileManager.default.moveItem(at: backup, to: json)
    let restoredDisk = try Data(contentsOf: json)
    precondition(restoredDisk == disk)
    _ = try await fresh.save(deleted, revision: 3)
    precondition(!FileManager.default.fileExists(atPath: retainedCopy.path))
    let originalBytes = try Data(contentsOf: source)
    precondition(originalBytes == bytes)
    print("PASS retained attachments: restart and midnight keep identity/bytes; ordinary expiry cleanup; failed delete retains copy; successful delete cleans only owned copy")
}

private func replacingRetention(_ item: Countdown, keeps: Bool? = nil, date: Day? = nil) -> Countdown {
    var copy = item
    if let keeps { copy.keepsAfterDate = keeps }
    if let date { copy.date = date }
    return copy
}

private func retentionDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}
