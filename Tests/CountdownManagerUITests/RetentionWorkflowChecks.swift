import CountdownCore
import CountdownManagerUI
import Foundation

@MainActor
func testRetentionWorkflows(in directory: URL) async throws {
    testRetainedPresentationAndEditorDrafts()
    try await testRetainedStoreMidnightAndAttachments(in: directory)
    try await testRetainedLinksAndMaterialIntake(in: directory.appendingPathComponent("materials"))
    print("PASS retained UI state: desktop/month/past grouping and mini order; primary/no duplicates/search; Russian labels; draft Save/Cancel; midnight failure/retry, post-date edits, attachment access and failed-edit rollback/retry")
}

@MainActor
private func testRetainedLinksAndMaterialIntake(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "CountdownRetainedMaterials.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let today = retentionUIDay(2026, 10, 29)
    var now = today.date()
    var opened: [URL] = []
    let json = directory.appendingPathComponent("countdowns.json")
    let store = Store(fileURL: json, disclosureDefaults: defaults, now: { now },
                      loginItemManagementIsAvailable: false, openWebURL: { opened.append($0); return true })
    await waitForRetentionStore(store)
    let link = EventLink(name: "Saved route", address: "https://example.com/route")
    let kept = Countdown(title: "Retained materials", date: today, emoji: "", keepsAfterDate: true, links: [link])
    let expired = Countdown(title: "Expired materials", date: today, emoji: "", links: [link])
    let savedKept = await store.save(kept, primary: true)
    let savedExpired = await store.save(expired, primary: false)
    precondition(savedKept && savedExpired)
    now = retentionUIDay(2026, 10, 30).date()
    store.refresh()
    await waitForRetentionStore(store)
    precondition(store.data.items == [kept])
    store.openLink(link, eventID: kept.id)
    store.openLink(link, eventID: expired.id)
    precondition(opened == [link.url!], "Only the retained event may still open its saved link")
    let source = directory.appendingPathComponent("Original.txt")
    let originalBytes = Data("Original material\n".utf8)
    try originalBytes.write(to: source)
    let addedLink = EventLink(name: " Booking ", address: " https://example.com/booking ")
    let text = TextAttachment(name: "Notes.txt", text: "Paragraph one\n\nParagraph two 👋\n")
    let added = await store.appendMaterials(EventMaterials(files: [source], links: [addedLink], textFile: text), to: kept.id)
    precondition(added)
    let result = store.data.items[0]
    precondition(result.keepsAfterDate && result.date == kept.date && result.id == kept.id)
    precondition(result.links == [link, addedLink.normalized()] && result.attachments.count == 2)
    precondition(store.data.primaryID == kept.id)
    for (attachment, expected) in zip(result.attachments, [originalBytes, Data(text.text.utf8)]) {
        let copy = directory.appendingPathComponent("Attachments").appendingPathComponent(attachment.id.uuidString)
            .appendingPathComponent(attachment.name)
        let bytes = try Data(contentsOf: copy)
        precondition(bytes == expected)
    }
    let draft = EventEditorDraft(item: result)
    precondition(draft.countdown(id: result.id, date: result.date) == result,
                 "Editor reopening must preserve both retention and all links/materials")
    let before = try Data(contentsOf: json)
    let invalid = await store.appendMaterials(EventMaterials(links: [EventLink(address: "file:///tmp/invalid")]), to: kept.id)
    let stale = await store.appendMaterials(EventMaterials(files: [source]), to: expired.id)
    precondition(!invalid && !stale && store.data.items == [result])
    let after = try Data(contentsOf: json)
    precondition(after == before)
    let reloaded = try await CountdownRepository(fileURL: json).load()
    precondition(reloaded == store.data)
    let sourceAfter = try Data(contentsOf: source)
    precondition(sourceAfter == originalBytes)
    print("PASS retained materials: saved links open after midnight; copied files, web links and exact text append durably; editor/reload retain all fields; invalid and expired targets preserve bytes")
}

private func testRetainedPresentationAndEditorDrafts() {
    let today = retentionUIDay(2026, 10, 29)
    let yesterday = retentionUIDay(2026, 10, 28)
    let old = Countdown(title: "Oldest", date: retentionUIDay(2026, 9, 1), emoji: "", keepsAfterDate: true)
    let recent = Countdown(title: "Recent", note: "Find retained note", date: yesterday, emoji: "", keepsAfterDate: true)
    let equal = Countdown(title: "Same past date", date: yesterday, emoji: "", keepsAfterDate: true)
    let ordinaryExpired = Countdown(title: "Expired", date: yesterday, emoji: "")
    let current = Countdown(title: "Today", date: today, emoji: "")
    let future = Countdown(title: "Next month", date: retentionUIDay(2026, 11, 2), emoji: "")
    var data = CountdownData()
    data.items = [old, future, recent, ordinaryExpired, current, equal]
    let expected = [current, future, recent, equal, old]
    precondition(activeCountdowns(in: data, today: today) == expected)
    let all = DesktopEventCollection(items: data.items, today: today, primaryID: nil, query: "")
    precondition(all.events == expected && all.favorite == nil)
    precondition(all.monthSections.map(\.title) == ["Октябрь 2026", "Ноябрь 2026"])
    precondition(all.monthSections.flatMap(\.items) == [current, future])
    precondition(all.pastItems == [recent, equal, old])
    data.primaryID = old.id
    precondition(activeCountdowns(in: data, today: today) == [old, current, future, recent, equal])
    let selected = DesktopEventCollection(items: data.items, today: today, primaryID: old.id, query: "")
    precondition(selected.favorite == old && selected.pastItems == [recent, equal])
    precondition(selected.events.filter { $0.id == old.id }.count == 1)
    let searched = DesktopEventCollection(items: data.items, today: today, primaryID: old.id, query: "RETAINED NOTE")
    precondition(searched.events == [recent] && searched.monthSections.isEmpty && searched.pastItems == [recent])
    precondition(desktopSelection(current: recent.id, available: selected.events) == recent.id)
    let labels = [(-1, "Вчера"), (-2, "2 дня назад"), (-5, "5 дней назад"), (-11, "11 дней назад"),
                  (-21, "21 день назад"), (-22, "22 дня назад"), (0, "Сегодня"), (1, "Завтра"), (2, "Через 2 дня")]
    for (offset, label) in labels {
        let date = Day(Day.calendar.date(byAdding: .day, value: offset, to: today.date())!)
        let item = Countdown(title: "Label", date: date, emoji: "", keepsAfterDate: offset < 0)
        let row = CountdownRowPresentation(item: item, today: today, primaryID: nil)
        precondition(row.remainingLabel == label && row.isPast == (offset < 0) && row.isToday == (offset == 0))
        var favorite = CountdownData()
        favorite.items = [item]
        favorite.primaryID = item.id
        let expectedMenu = offset > 1 ? dayLabel(offset) : label
        precondition(statusBarPresentation(data: favorite, today: today).title == expectedMenu)
    }
    data.primaryID = recent.id
    precondition(statusBarPresentation(data: data, today: today).title == "Вчера")
    data.primaryID = nil
    precondition(statusBarPresentation(data: data, today: today).title.isEmpty)
    precondition(statusBarPresentation(data: data, today: today).toolTip.contains("нет избранного"))

    precondition(!EventEditorDraft(item: nil).keepsAfterDate && !EventEditorDraft(day: today).keepsAfterDate)
    var draft = EventEditorDraft(item: recent)
    precondition(draft.keepsAfterDate && draft.countdown(id: recent.id, date: recent.date) == recent)
    draft.keepsAfterDate = false
    precondition(recent.keepsAfterDate, "Draft changes do not mutate stored event values")
    let reopened = EventEditorDraft(item: recent)
    precondition(reopened.keepsAfterDate, "Discarded drafts restore the saved retention choice")
    precondition(editorCanSave(title: draft.title, note: draft.note, date: recent.date,
                              emoji: draft.emoji, today: today, savedDate: recent.date),
                 "Unchecking retention must leave Save enabled to reach explicit deletion confirmation")
    precondition(!editorCanSave(title: draft.title, note: draft.note, date: recent.date,
                               emoji: draft.emoji, today: today))
    precondition(!editorCanSave(title: draft.title, note: draft.note, date: old.date,
                               emoji: draft.emoji, today: today, savedDate: recent.date))
}

@MainActor
private func testRetainedStoreMidnightAndAttachments(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "CountdownRetentionWorkflow.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let today = retentionUIDay(2026, 10, 29)
    var now = today.date()
    let json = directory.appendingPathComponent("countdowns.json")
    let source = directory.appendingPathComponent("Original.txt")
    let bytes = Data("Retained fixture bytes".utf8)
    try bytes.write(to: source)
    let store = Store(fileURL: json, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForRetentionStore(store)
    let draftID = UUID()
    let prepared = await store.beginAttachmentDraft(draftID)
    precondition(prepared)
    guard let file = await store.importAttachment(from: source, draftID: draftID) else {
        preconditionFailure("Fixture file must import")
    }
    let task = try Subtask(text: "Retained task")
    var retained = Countdown(title: "Retained", note: "Original note", date: today, emoji: "",
                             subtasks: [task], keepsAfterDate: true, attachments: [file])
    let ordinary = Countdown(title: "Expired", date: today, emoji: "")
    let saved = await store.save(retained, primary: true)
    let ordinarySaved = await store.save(ordinary, primary: false)
    precondition(saved && ordinarySaved)
    await store.discardAttachmentDraft(draftID)
    let disclosure = SubtaskDisclosurePersistence(defaults: defaults)
    disclosure.setExpanded(false, eventID: retained.id)
    let copy = directory.appendingPathComponent("Attachments").appendingPathComponent(file.id.uuidString).appendingPathComponent(file.name)
    let durableBefore = store.data
    let backup = directory.appendingPathComponent("Backup.json")
    try FileManager.default.moveItem(at: json, to: backup)
    try FileManager.default.createDirectory(at: json, withIntermediateDirectories: true)
    now = retentionUIDay(2026, 10, 30).date()
    store.refresh()
    await waitForRetentionStore(store)
    precondition(store.data == durableBefore, "Failed midnight cleanup must roll back the complete saved collection")
    let bytesAfterFailure = try Data(contentsOf: copy)
    precondition(bytesAfterFailure == bytes)
    try FileManager.default.removeItem(at: json)
    try FileManager.default.moveItem(at: backup, to: json)
    store.refresh()
    await waitForRetentionStore(store)
    precondition(store.data.items == [retained] && store.data.primaryID == retained.id)
    precondition(activeCountdowns(in: store.data, today: Day(now)) == [retained])
    precondition(statusBarTitle(data: store.data, today: Day(now)) == "Вчера")
    precondition(!disclosure.isExpanded(eventID: retained.id))
    let originalPreview = await store.editorAttachmentThumbnailURL(file, eventID: retained.id, draftID: UUID())
    precondition(originalPreview == copy, "Saved past attachments remain available across await boundaries")
    retained.note = "Edited after date"
    let edited = await store.save(retained, primary: true, requireExisting: true)
    precondition(edited && store.data.items == [retained])
    retained.subtasks[0].isCompleted = true
    let toggled = await store.save(retained, primary: true, requireExisting: true)
    precondition(toggled && store.data.items[0].subtasks[0].isCompleted)
    retained = store.data.items[0]
    var unchecked = retained
    unchecked.keepsAfterDate = false
    let rejected = await store.save(unchecked, primary: false, requireExisting: true)
    precondition(!rejected && store.data.items == [retained], "Generic Save must not silently delete an unchecked past event")
    var resurrected = ordinary
    resurrected.keepsAfterDate = true
    let staleSave = await store.save(resurrected, primary: false, requireExisting: true)
    precondition(!staleSave && store.data.items == [retained])
    let fresh = Store(fileURL: json, disclosureDefaults: defaults, now: { now }, loginItemManagementIsAvailable: false)
    await waitForRetentionStore(fresh)
    precondition(fresh.data == store.data && statusBarTitle(data: fresh.data, today: Day(now)) == "Вчера")
    await fresh.clearPrimary()
    precondition(statusBarTitle(data: fresh.data, today: Day(now)).isEmpty)
    precondition(activeCountdowns(in: fresh.data, today: Day(now)) == [retained])
    let primarySaved = await fresh.save(retained, primary: true, requireExisting: true)
    precondition(primarySaved && fresh.data.primaryID == retained.id)
    try FileManager.default.moveItem(at: json, to: backup)
    try FileManager.default.createDirectory(at: json, withIntermediateDirectories: true)
    var retry = retained
    retry.title = "Retry post-date edit"
    let failedEdit = await fresh.save(retry, primary: false, requireExisting: true)
    precondition(!failedEdit && fresh.data.items == [retained] && fresh.data.primaryID == retained.id)
    let copyAfterEditFailure = try Data(contentsOf: copy)
    precondition(copyAfterEditFailure == bytes)
    try FileManager.default.removeItem(at: json)
    try FileManager.default.moveItem(at: backup, to: json)
    let retried = await fresh.save(retry, primary: false, requireExisting: true)
    precondition(retried && fresh.data.items == [retry] && fresh.data.primaryID == nil)
    let retryPreview = await fresh.editorAttachmentThumbnailURL(file, eventID: retry.id, draftID: UUID())
    precondition(retryPreview == copy)
    let originalBytes = try Data(contentsOf: source)
    precondition(originalBytes == bytes)
}

@MainActor
private func waitForRetentionStore(_ store: Store) async {
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while store.hasPendingPersistence {
        precondition(ProcessInfo.processInfo.systemUptime < deadline, "Retention Store did not settle")
        await Task.yield()
    }
}

private func retentionUIDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}
