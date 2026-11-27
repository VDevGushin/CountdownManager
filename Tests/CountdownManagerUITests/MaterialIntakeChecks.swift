import AppKit
import CountdownCore
import CountdownManagerUI
import UniformTypeIdentifiers

@MainActor
func testMaterialIntake(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "CountdownMaterials.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, loginItemManagementIsAvailable: false)
    for _ in 0..<2_000 where store.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!store.isLoading)
    try await testDelayedMaterialProvider(store: store)
    try await testBrowserBookmarkProvider()
    try await testImageMaterialIntake(in: directory.appendingPathComponent("images"))
    try await testMaterialResolutionSpansMidnight(in: directory.appendingPathComponent("midnight"), defaults: defaults)
    let first = Countdown(title: "Первое", date: Day(Date()), emoji: "")
    let second = Countdown(title: "Получатель", date: Day(Date()), emoji: "")
    let savedFirst = await store.save(first, primary: true)
    let savedSecond = await store.save(second, primary: false)
    precondition(savedFirst && savedSecond)
    let source = directory.appendingPathComponent("Оригинал из Finder.txt")
    let original = Data("Исходный файл\n".utf8)
    try original.write(to: source)
    let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
    let resolved = try await resolveEventMaterials([provider])
    precondition(resolved.files == [source] && resolved.links.isEmpty && resolved.text == nil)
    let genericURL = NSItemProvider(item: source.absoluteString as NSString, typeIdentifier: UTType.url.identifier)
    precondition(!genericURL.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    do {
        _ = try await resolveEventMaterials([genericURL])
        preconditionFailure("A generic URL provider without file provenance must not import a local file")
    } catch is EventLinkError { }
    let finderText = NSItemProvider(item: source.absoluteString as NSString, typeIdentifier: UTType.plainText.identifier)
    precondition(finderText.registeredTypeIdentifiers == [UTType.plainText.identifier])
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let textOnly = NSPasteboardItem()
    precondition(textOnly.setString(source.absoluteString, forType: .string))
    precondition(pasteboard.writeObjects([textOnly]))
    do {
        _ = try await resolveEventMaterials([finderText], nativeFileIndices: nativeFileDropIndices(providerCount: 1, from: pasteboard))
        preconditionFailure("A local URL in ordinary dragged text must not read the file")
    } catch is EventLinkError { }
    let finderItem = NSPasteboardItem()
    precondition(finderItem.setString("file:///.file/id=123.456", forType: .fileURL))
    pasteboard.clearContents()
    precondition(pasteboard.writeObjects([finderItem]))
    let nativeFileIndices = nativeFileDropIndices(providerCount: 1, from: pasteboard)
    precondition(nativeFileIndices == [0] && nativeFileDropIndices(providerCount: 2, from: pasteboard).isEmpty)
    let resolvedFinderText = try await resolveEventMaterials([finderText], nativeFileIndices: nativeFileIndices)
    precondition(resolvedFinderText.files == [source] && resolvedFinderText.links.isEmpty && resolvedFinderText.text == nil)
    for suffix in [" commentary", "%note", "%00suffix", "%2Fother", "?comment", "#anchor"] {
        let provider = NSItemProvider(item: (source.absoluteString + suffix) as NSString,
                                      typeIdentifier: UTType.plainText.identifier)
        do {
            _ = try await resolveEventMaterials([provider])
            preconditionFailure("Text must contain one standalone file URL to import its file")
        } catch is EventLinkError { }
    }
    for firstLine in ["https://example.com/reference", source.absoluteString] {
        let fragment = firstLine + "\n\nCompare both versions.\n"
        let provider = NSItemProvider(item: fragment as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
        let materials = try await resolveEventMaterials([provider])
        precondition(materials.text == fragment && materials.links.isEmpty && materials.files.isEmpty)
    }
    let link = try EventMaterials.classify(" https://example.com/path ")
    precondition(link.links.count == 1 && link.text == nil)
    do { _ = try EventMaterials.classify("file:///tmp/secret"); preconditionFailure("File URI is not a web link") }
    catch is EventLinkError { }
    store.scheduleMaterialAddition(link, to: first.id)
    precondition(store.isReceivingMaterials && store.hasPendingPersistence)
    precondition(!store.beginMaterialResolution())
    for _ in 0..<2_000 where store.isReceivingMaterials { try await Task.sleep(nanoseconds: 1_000_000) }
    let scheduled = store.data.items.first(where: { $0.id == first.id })!
    precondition(scheduled.links == link.links && scheduled.attachments.isEmpty)
    let added = await store.appendMaterials(EventMaterials(files: resolvedFinderText.files, links: link.links), to: second.id)
    precondition(added && store.data.items.first(where: { $0.id == first.id }) == scheduled)
    precondition(store.data.primaryID == first.id)
    let repository = CountdownRepository(fileURL: fileURL)
    let durable = try await repository.load()
    let target = durable.items.first(where: { $0.id == second.id })!
    precondition(target.attachments.count == 1 && target.links.count == 1)
    let owned = try await repository.attachmentURL(for: target.attachments[0])
    let ownedBytes = try Data(contentsOf: owned)
    precondition(ownedBytes == original)
    var fileAuthority = URLComponents(url: source, resolvingAgainstBaseURL: false)!
    fileAuthority.host = "localhost"
    fileAuthority.user = "fixture"
    fileAuthority.password = "fixture"
    let userInfo = fileAuthority.url!
    fileAuthority.user = nil
    fileAuthority.password = nil
    fileAuthority.port = 4321
    let filePath = fileAuthority.percentEncodedPath
    let authoritySnapshot = try Data(contentsOf: fileURL)
    let invalidSources = [
        userInfo, fileAuthority.url!,
        URL(string: "file://localhost:\(filePath)")!,
        URL(string: "file://localhost:999999999999999999999999\(filePath)")!,
        URL(string: "file://nonlocal.invalid\(filePath)")!,
    ]
    for invalid in invalidSources {
        let provider = NSItemProvider(item: invalid as NSURL, typeIdentifier: UTType.fileURL.identifier)
        do {
            _ = try await resolveEventMaterials([provider])
            preconditionFailure("A native file URL must be local and have no credentials or port")
        } catch is EventAttachmentError { }
        let imported = await store.appendMaterials(EventMaterials(files: [invalid]), to: second.id)
        let after = try Data(contentsOf: fileURL)
        precondition(!imported && after == authoritySnapshot)
    }
    store.error = nil
    let sourceBytes1 = try Data(contentsOf: source)
    precondition(sourceBytes1 == original)
    // Ordinary edits and favorite changes keep immediately added materials durable.
    var changed = target
    changed.title = "Новое название"
    changed.subtasks = [try Subtask(text: "Не потерять изменение")]
    let changedSaved = await store.save(changed, primary: true)
    precondition(changedSaved)
    let afterEdit = store.data.items.first(where: { $0.id == second.id })!
    precondition(afterEdit.title == changed.title && afterEdit.subtasks == changed.subtasks)
    precondition(afterEdit.attachments == target.attachments && afterEdit.links == target.links)
    precondition(store.data.primaryID == second.id && FileManager.default.fileExists(atPath: owned.path))
    let sourceBytes2 = try Data(contentsOf: source)
    precondition(sourceBytes2 == original)
    // Preserve a large Unicode fragment byte-for-byte, including blank lines and trailing newline.
    let text = "Инструкция 🏍️\n\n" + String(repeating: "Строка с кириллицей и emoji 🧳\n", count: 1_000) + "\nКонец\n"
    let textFile = TextAttachment(text: text)
    try textFile.validate()
    let textAdded = await store.appendMaterials(EventMaterials(textFile: textFile), to: second.id)
    precondition(textAdded)
    let textEvent = store.data.items.first(where: { $0.id == second.id })!
    let reopenedRepository = CountdownRepository(fileURL: fileURL)
    _ = try await reopenedRepository.load()
    let textURL = try await reopenedRepository.attachmentURL(for: textEvent.attachments.last!)
    let textBytes = try Data(contentsOf: textURL)
    precondition(textBytes == Data(text.utf8))
    precondition(textEvent.attachments.last!.byteCount == Int64(text.utf8.count))
    do { try TextAttachment(name: "../escape", text: text).validate(); preconditionFailure("Unsafe name") }
    catch { }
    // A staged text file is discarded on Cancel and never reaches persisted JSON.
    let draftID = UUID()
    let began = await store.beginAttachmentDraft(draftID)
    precondition(began)
    let draftFile = await store.createTextAttachment(TextAttachment(text: "Только черновик"), draftID: draftID)
    precondition(draftFile != nil)
    let beforeCancel = try Data(contentsOf: fileURL)
    await store.discardAttachmentDraft(draftID)
    let afterCancel = try Data(contentsOf: fileURL)
    precondition(afterCancel == beforeCancel)
    let late = await store.createTextAttachment(textFile, draftID: draftID)
    precondition(late == nil)
    // Both caps reject a whole batch before importing. Legacy file overflow is not pruned.
    let over = EventMaterials(files: Array(repeating: source, count: 15))
    let rejected = await store.appendMaterials(over, to: second.id)
    let afterReject = try Data(contentsOf: fileURL)
    precondition(!rejected && afterReject == beforeCancel)
    let eleven = EventMaterials(links: (0..<11).map { EventLink(address: "https://example.com/\($0)") })
    let rejectedLinks = await store.appendMaterials(eleven, to: second.id)
    precondition(!rejectedLinks)
    // A failed mixed import does not commit its successfully copied prefix or link.
    let missing = directory.appendingPathComponent("missing.pdf")
    let failed = await store.appendMaterials(EventMaterials(files: [source, missing], links: link.links), to: second.id)
    let afterFailed = try Data(contentsOf: fileURL)
    precondition(!failed && afterFailed == beforeCancel)
    let stale = await store.appendMaterials(link, to: UUID())
    precondition(!stale && !store.isReceivingMaterials)
    let failingURL = directory.appendingPathComponent("failure/countdowns.json")
    let failureRepository = CountdownRepository(fileURL: failingURL)
    var fixture = CountdownData()
    fixture.items = [first]
    try await failureRepository.save(fixture, revision: 1)
    let failing = Store(fileURL: failingURL, disclosureDefaults: defaults,
                        persistenceSaveOverride: { _, _ in throw CocoaError(.fileWriteNoPermission) },
                        loginItemManagementIsAvailable: false)
    for _ in 0..<2_000 where failing.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    let failureBefore = try Data(contentsOf: failingURL)
    let failedWrite = await failing.appendMaterials(EventMaterials(files: [source]), to: first.id)
    let failureAfter = try Data(contentsOf: failingURL)
    precondition(!failedWrite && failureBefore == failureAfter)
    precondition(failing.data.items[0].attachments.isEmpty && !failing.isReceivingMaterials)
    let ownedDirectory = failingURL.deletingLastPathComponent().appendingPathComponent("Attachments")
    let abandoned = try FileManager.default.contentsOfDirectory(atPath: ownedDirectory.path)
    precondition(abandoned.isEmpty)
    var clock = Date()
    let expired = Store(fileURL: failingURL, disclosureDefaults: defaults, now: { clock },
                        loginItemManagementIsAvailable: false)
    for _ in 0..<2_000 where expired.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    clock = Day.calendar.date(byAdding: .day, value: 1, to: clock)!
    let expiredAdd = await expired.appendMaterials(link, to: first.id)
    precondition(!expiredAdd)
    try await testRecordMaterialWriteFailure(store: store, eventID: first.id, source: source, eventURL: fileURL)
    print("PASS materials: provider priority, exact target, local copies, durable additions across edits, Unicode text, Cancel, caps, failed batch, stale owner")
}

@MainActor
private func testBrowserBookmarkProvider() async throws {
    let type = "dyn.ah62d4rv4gu8zs3pcnzme2641rf4guzdmsv0gn64uqm10c6xenv61a3k"
    func provider(_ columns: [[String]]) throws -> NSItemProvider {
        let data = try PropertyListSerialization.data(fromPropertyList: columns, format: .binary, options: 0)
        let item = NSItemProvider()
        item.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { complete in
            complete(data, nil)
            return nil
        }
        return item
    }
    let expected = ["https://example.com/bookmark", "http://example.com/second?q=1"]
    let bookmark = try provider([expected, [" Example ", "Second"]])
    precondition(!bookmark.hasItemConformingToTypeIdentifier(UTType.url.identifier))
    let materials = try await resolveEventMaterials([bookmark])
    precondition(materials.links.map(\.address) == expected && materials.links.map(\.name) == ["Example", "Second"])
    precondition(materials.files.isEmpty && materials.stagedFiles.isEmpty && materials.text == nil)
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let item = NSPasteboardItem()
    precondition(item.setPropertyList([expected, ["Example", "Second"]], forType: NSPasteboard.PasteboardType(type)))
    let emptyProvider = NSItemProvider()
    precondition(pasteboard.writeObjects([item]))
    precondition(safariBookmarkProvider(replacing: [emptyProvider], from: pasteboard) == nil,
                 "Only a Safari bookmark item can recover an empty provider")
    let safari = NSPasteboardItem()
    precondition(safari.setPropertyList([expected, ["Example", "Second"]], forType: NSPasteboard.PasteboardType(type)))
    precondition(safari.setData(Data([0]), forType: NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")))
    pasteboard.clearContents()
    precondition(pasteboard.writeObjects([safari]))
    precondition(safariBookmarkProvider(replacing: [bookmark], from: pasteboard) == nil)
    precondition(safariBookmarkProvider(replacing: [bookmark, emptyProvider], from: pasteboard) == nil)
    let recovered = safariBookmarkProvider(replacing: [emptyProvider], from: pasteboard)
    precondition(recovered != nil, "Recover Safari's real pasteboard payload when SwiftUI supplies an empty provider")
    let recoveredMaterials = try await resolveEventMaterials([recovered!])
    precondition(recoveredMaterials.links.map(\.address) == expected && recoveredMaterials.links.map(\.name) == ["Example", "Second"])
    precondition(recoveredMaterials.files.isEmpty && recoveredMaterials.text == nil)
    do {
        _ = try await resolveEventMaterials([provider([expected, ["Only one title"]])])
        preconditionFailure("A bookmark list with a missing title must fail atomically")
    } catch is MaterialIntakeError { }
    do {
        _ = try await resolveEventMaterials([provider([[expected[0], "file:///tmp/local"], ["Good", "Bad"]])])
        preconditionFailure("A browser bookmark payload must not import a local file")
    } catch is EventLinkError { }
}

@MainActor
private func testMaterialResolutionSpansMidnight(in directory: URL, defaults: UserDefaults) async throws {
    let fileURL = directory.appendingPathComponent("countdowns.json")
    var clock = Date()
    var advanceAfterLookup = false
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, now: {
        let instant = clock
        if advanceAfterLookup {
            clock = Calendar.current.date(byAdding: .day, value: 1, to: clock)!
            advanceAfterLookup = false
        }
        return instant
    }, loginItemManagementIsAvailable: false)
    for _ in 0..<2_000 where store.isLoading || store.isLoadingRecords { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!store.isLoading && !store.isLoadingRecords)
    let event = Countdown(title: "Expiring event", date: Day(clock), emoji: "")
    let record = UndatedRecord(title: "Incoming material")
    let eventSaved = await store.save(event, primary: true)
    let recordSaved = await store.saveRecord(record)
    precondition(eventSaved && recordSaved)
    let eventBytes = try Data(contentsOf: fileURL)
    precondition(store.beginMaterialResolution())
    await store.clearPrimary()
    precondition(store.data.primaryID == event.id, "A favorite action cannot overtake the accepted drop")
    clock = Calendar.current.date(byAdding: .day, value: 1, to: clock)!
    store.refresh()
    let duringDrop = try Data(contentsOf: fileURL)
    let visibleEvents = activeCountdowns(in: store.data, today: Day(clock))
    precondition(duringDrop == eventBytes && visibleEvents.isEmpty && store.data.items.map(\.id) == [event.id])

    store.endMaterialResolution()
    let link = EventLink(address: "https://example.com/material-after-midnight")
    let added = await store.appendMaterials(EventMaterials(links: [link]), to: .record(record.id))
    precondition(added, "Unrelated expiry must not consume an accepted record material")
    for _ in 0..<2_000 where store.hasPendingPersistence { try await Task.sleep(nanoseconds: 1_000_000) }
    let repository = CountdownRepository(fileURL: fileURL)
    let durableEvents = try await repository.load()
    let durableRecords = try await repository.loadRecords()
    precondition(durableEvents.items.isEmpty && durableEvents.primaryID == nil)
    precondition(durableRecords.map(\.id) == [record.id] && durableRecords.first?.links == [link])

    let receiver = Countdown(title: "Expires while copying", date: Day(clock), emoji: "")
    let receiverSaved = await store.save(receiver, primary: false)
    precondition(receiverSaved)
    let source = directory.appendingPathComponent("Late file.txt")
    try Data("Kept original\n".utf8).write(to: source)
    let beforeCopy = try Data(contentsOf: fileURL)
    store.error = "An unrelated warning"
    advanceAfterLookup = true
    let copied = await store.appendMaterials(EventMaterials(files: [source]), to: receiver.id)
    let afterCopy = try Data(contentsOf: fileURL)
    let owned = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Attachments").path)
    precondition(!copied && store.error == AppText.string("store.materialBecameUnavailable"))
    precondition(beforeCopy == afterCopy && owned.isEmpty && FileManager.default.fileExists(atPath: source.path))
}

@MainActor
private func testRecordMaterialWriteFailure(store: Store, eventID: UUID, source: URL, eventURL: URL) async throws {
    for _ in 0..<2_000 where store.isLoadingRecords { try await Task.sleep(nanoseconds: 1_000_000) }
    let record = UndatedRecord(id: eventID, title: "Different owner with the same UUID")
    let saved = await store.saveRecord(record)
    precondition(saved)
    let recordsURL = CountdownRepository.recordsFileURL(beside: eventURL)
    let recordsBytes = try Data(contentsOf: recordsURL)
    let eventBytes = try Data(contentsOf: eventURL)
    let backup = recordsURL.appendingPathExtension("material-test-backup")
    let manager = FileManager.default
    try manager.moveItem(at: recordsURL, to: backup)
    defer {
        if manager.fileExists(atPath: backup.path) {
            try? manager.removeItem(at: recordsURL)
            try? manager.moveItem(at: backup, to: recordsURL)
        }
    }
    try manager.createDirectory(at: recordsURL, withIntermediateDirectories: false)
    let items = EventMaterials(files: [source], links: [EventLink(address: "https://example.com/record-drop")])
    let added = await store.appendMaterials(items, to: .record(record.id))
    precondition(!added && store.records == [record] && !store.hasPendingPersistence)
    let untouchedEvents = try Data(contentsOf: eventURL)
    let preservedRecords = try Data(contentsOf: backup)
    let attachmentDirectory = eventURL.deletingLastPathComponent().appendingPathComponent("RecordAttachments")
    let abandonedCopies = try manager.contentsOfDirectory(atPath: attachmentDirectory.path)
    precondition(untouchedEvents == eventBytes && preservedRecords == recordsBytes && abandonedCopies.isEmpty)
}


private final class DeferredMaterialProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Data?, Error?) -> Void)?
    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completion != nil
    }
    func install(_ value: @escaping (Data?, Error?) -> Void) {
        lock.lock()
        completion = value
        lock.unlock()
    }
    func resolve(_ text: String) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(Data(text.utf8), nil)
    }
    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { callback in
            self.install(callback)
            return nil
        }
        return provider
    }
}

@MainActor
private func testDelayedMaterialProvider(store: Store) async throws {
    let session = MaterialDropSession()
    let first = DeferredMaterialProvider()
    let second = DeferredMaterialProvider()
    var delivered: [String] = []
    let start: ([NSItemProvider]) -> Bool = { providers in
        session.receive(providers, begin: { store.beginMaterialResolution() },
                        finish: { store.endMaterialResolution() },
                        completion: { delivered.append($0.text ?? "") }, reportError: { _ in
            preconditionFailure("Unexpected provider failure")
        })
    }
    precondition(start([first.provider()]))
    precondition(store.hasPendingPersistence && store.isResolvingMaterials)
    precondition(!start([second.provider()]))
    for _ in 0..<2_000 where !first.isWaiting { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(first.isWaiting)
    precondition(session.cancel(), "A disappearing target must detect that it interrupted an accepted drop")
    precondition(!session.cancel(), "An already released drop must not report a second cancellation")
    precondition(!store.hasPendingPersistence)
    precondition(start([second.provider()]))
    for _ in 0..<2_000 where !second.isWaiting { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(second.isWaiting)
    first.resolve("Late cancelled fragment")
    try await Task.sleep(nanoseconds: 10_000_000)
    precondition(delivered.isEmpty && store.isResolvingMaterials)
    second.resolve("Current fragment")
    for _ in 0..<2_000 where delivered.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(delivered == ["Current fragment"] && !store.hasPendingPersistence)
    let earlier = DeferredMaterialProvider()
    let later = DeferredMaterialProvider()
    var links: [EventLink] = []
    let accepted = session.receive([earlier.provider(), later.provider()],
        begin: { store.beginMaterialResolution() }, finish: { store.endMaterialResolution() },
        completion: { links = $0.links }, reportError: { _ in preconditionFailure("Unexpected batch failure") })
    precondition(accepted)
    for _ in 0..<2_000 where !earlier.isWaiting || !later.isWaiting { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(earlier.isWaiting && later.isWaiting, "All providers must start before any payload has finished")
    later.resolve("https://example.com/later")
    earlier.resolve("https://example.com/earlier")
    for _ in 0..<2_000 where links.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(links.map(\.address) == ["https://example.com/earlier", "https://example.com/later"])
    precondition(!store.hasPendingPersistence)
    let stalled = DeferredMaterialProvider()
    let bounded = MaterialDropSession(timeout: .milliseconds(200))
    var failure: String?
    let acceptedStalled = bounded.receive([stalled.provider()],
        begin: { store.beginMaterialResolution() }, finish: { store.endMaterialResolution() },
        completion: { _ in preconditionFailure("A timed-out drop must never reach storage") },
        reportError: { failure = $0 })
    precondition(acceptedStalled && store.isResolvingMaterials)
    for _ in 0..<2_000 where failure == nil { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(failure == AppText.string("material.dropFailed") && !store.hasPendingPersistence)
    stalled.resolve("Late timed-out fragment")
    try await Task.sleep(nanoseconds: 10_000_000)
    precondition(!bounded.cancel())
    print("PASS materials delayed providers: all loads start together, drop order, reservation handoff and cancellation")
}
