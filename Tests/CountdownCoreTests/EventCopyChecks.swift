import Foundation
import CountdownCore

func testEventCopyValidationAndInheritedAllowances() throws {
    let today = Day(Date(timeIntervalSince1970: 1_800_000_000))
    let attachments = try (0..<17).map { try EventAttachment(name: "File \($0).txt", byteCount: 1) }
    let source = Countdown(title: "Source", note: " \n" + String(repeating: "я", count: 180) + "\n ",
                           date: today, emoji: "🚀", subtasks: [try Subtask(text: "Done", isCompleted: true)],
                           showsWeather: true, keepsAfterDate: true, attachments: attachments,
                           links: [EventLink(name: "Route", address: "https://example.com/route")])
    var data = CountdownData()
    data.items = [source]
    data.primaryID = source.id
    var copy = Countdown(title: source.title, note: source.note, date: today, emoji: source.emoji,
                         subtasks: source.subtasks.map(Subtask.init(copying:)), showsWeather: source.showsWeather,
                         keepsAfterDate: source.keepsAfterDate, attachments: source.attachments,
                         links: source.links.map { EventLink(name: $0.name, address: $0.address) })
    try data.saveCopy(copy, sourceID: source.id, primary: false, today: today)
    precondition(data.items[0] == source && data.items[1] == copy && data.primaryID == source.id)
    precondition(copy.id != source.id && copy.subtasks[0].id != source.subtasks[0].id)
    precondition(!copy.subtasks[0].isCompleted && copy.links[0].id != source.links[0].id)

    let accepted = data
    do {
        try data.saveCopy(copy, sourceID: source.id, primary: true, today: today)
        preconditionFailure("Retrying a committed copy cannot create or overwrite another event")
    } catch CountdownError.copyIdentity {}
    precondition(data == accepted)

    var fresh = CountdownData()
    fresh.items = [source]
    fresh.primaryID = source.id
    copy = Countdown(title: source.title, note: source.note! + "x", date: today, emoji: "")
    do {
        try fresh.saveCopy(copy, sourceID: source.id, primary: true, today: today)
        preconditionFailure("An inherited long note cannot grow beyond its inherited allowance")
    } catch CountdownError.note {}
    precondition(fresh.items == [source] && fresh.primaryID == source.id)
    copy.note = source.note
    copy.attachments = attachments
    copy.attachments[0] = try EventAttachment(name: "New.txt", byteCount: 0)
    do {
        try fresh.saveCopy(copy, sourceID: source.id, primary: true, today: today)
        preconditionFailure("A legacy over-limit copy cannot gain a new file")
    } catch EventAttachmentError.limitExceeded {}
    precondition(fresh.items == [source] && fresh.primaryID == source.id)
    copy.attachments = Array(attachments.prefix(14)) + [try EventAttachment(name: "New.txt", byteCount: 0)]
    try fresh.saveCopy(copy, sourceID: source.id, primary: true, today: today)
    precondition(fresh.items[0] == source && fresh.items[1] == copy && fresh.primaryID == copy.id)
}

func testEventCopyRequiresAvailableSourceAndFutureDate() throws {
    let today = Day(Date(timeIntervalSince1970: 1_800_000_000))
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    var source = Countdown(title: "Expired", date: yesterday, emoji: "")
    let copy = Countdown(title: "Copy", date: today, emoji: "")
    var data = CountdownData()
    data.items = [source]
    do {
        try data.saveCopy(copy, sourceID: source.id, primary: false, today: today)
        preconditionFailure("An expired source must not be recreated through copying")
    } catch CountdownError.eventNotFound {}
    precondition(data.items == [source])
    source.keepsAfterDate = true
    data.items = [source]
    var pastCopy = copy
    pastCopy.date = yesterday
    pastCopy.keepsAfterDate = true
    do {
        try data.saveCopy(pastCopy, sourceID: source.id, primary: false, today: today)
        preconditionFailure("Retention does not permit a new copy on a past date")
    } catch CountdownError.date {}
    precondition(data.items == [source])
    try data.saveCopy(copy, sourceID: source.id, primary: false, today: today)
    precondition(data.items == [source, copy])
}

func testEventCopyRejectsReusedChildrenAndCompletedTasks() throws {
    let today = Day(Date(timeIntervalSince1970: 1_800_000_000))
    let source = Countdown(title: "Source", date: today, emoji: "",
                           subtasks: [try Subtask(text: "Source task")],
                           links: [EventLink(address: "https://example.com/source")])
    let neighbor = Countdown(title: "Neighbor", date: today, emoji: "",
                             subtasks: [try Subtask(text: "Neighbor task")],
                             links: [EventLink(address: "https://example.com/neighbor")])
    var original = CountdownData()
    original.items = [source, neighbor]
    original.primaryID = source.id
    let valid = Countdown(title: "Copy", date: today, emoji: "", subtasks: [try Subtask(text: "Fresh task")],
                          links: [EventLink(address: "https://example.com/fresh")])
    var completed = valid
    completed.subtasks[0].isCompleted = true
    var sourceTask = valid
    sourceTask.subtasks = source.subtasks
    var neighborTask = valid
    neighborTask.subtasks = neighbor.subtasks
    var sourceLink = valid
    sourceLink.links = source.links
    var neighborLink = valid
    neighborLink.links = neighbor.links
    for rejected in [completed, sourceTask, neighborTask, sourceLink, neighborLink] {
        var data = original
        do {
            try data.saveCopy(rejected, sourceID: source.id, primary: true, today: today)
            preconditionFailure("Copy mutation must enforce fresh children and incomplete tasks")
        } catch CountdownError.copyIdentity {}
        precondition(data == original)
    }
    var accepted = original
    try accepted.saveCopy(valid, sourceID: source.id, primary: false, today: today)
    precondition(accepted.items == original.items + [valid] && accepted.primaryID == source.id)
}

func testEventCopyRepositoryOwnsIndependentFiles() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("EventCopy-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("Original.txt")
    let bytes = Data("Unchanged original bytes".utf8)
    try bytes.write(to: file)
    let repository = CountdownRepository(fileURL: root.appendingPathComponent("data/countdowns.json"))
    let sourceDraft = UUID()
    try await repository.beginAttachmentDraft(sourceDraft)
    let attachment = try await repository.importAttachment(from: file, draftID: sourceDraft)
    let source = Countdown(title: "Source", date: Day(Date()), emoji: "", attachments: [attachment])
    var data = CountdownData()
    data.items = [source]
    _ = try await repository.save(data, revision: 1)
    try await repository.discardAttachmentDraft(sourceDraft)
    let sourceURL = try await repository.attachmentURL(for: attachment)
    let editorDraft = UUID()
    let saveAttempt = UUID()
    try await repository.beginAttachmentDraft(editorDraft)
    let copies = try await repository.copyEventAttachments([attachment], inheritedFrom: source.attachments,
                                                          editorDraftID: editorDraft, copyDraftID: saveAttempt)
    precondition(copies.count == 1 && copies[0].id != attachment.id && copies[0].name == attachment.name)
    let copyURL = try await repository.attachmentURL(for: copies[0])
    let copiedBytes = try Data(contentsOf: copyURL)
    precondition(copiedBytes == bytes)
    precondition(copyURL != sourceURL)
    try await repository.discardAttachmentDraft(saveAttempt)
    precondition(!FileManager.default.fileExists(atPath: copyURL.path))
    let sourceBytes = try Data(contentsOf: sourceURL)
    let originalBytes = try Data(contentsOf: file)
    precondition(sourceBytes == bytes && originalBytes == bytes)
    try await repository.discardAttachmentDraft(editorDraft)
}
