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
    try await testImageMaterialIntake(in: directory.appendingPathComponent("images"))
    let first = Countdown(title: "Первое", date: Day(Date()), emoji: "")
    let second = Countdown(title: "Получатель", date: Day(Date()), emoji: "")
    let savedFirst = await store.save(first, primary: true)
    let savedSecond = await store.save(second, primary: false)
    precondition(savedFirst && savedSecond)
    let source = directory.appendingPathComponent("Оригинал.txt")
    let original = Data("Исходный файл\n".utf8)
    try original.write(to: source)
    let provider = NSItemProvider(item: source as NSURL, typeIdentifier: UTType.fileURL.identifier)
    let resolved = try await resolveEventMaterials([provider])
    precondition(resolved.files == [source] && resolved.links.isEmpty && resolved.text == nil)
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
    let added = await store.appendMaterials(EventMaterials(files: resolved.files, links: link.links), to: second.id)
    precondition(added && store.data.items.first(where: { $0.id == first.id }) == scheduled)
    precondition(store.data.primaryID == first.id)
    let repository = CountdownRepository(fileURL: fileURL)
    let durable = try await repository.load()
    let target = durable.items.first(where: { $0.id == second.id })!
    precondition(target.attachments.count == 1 && target.links.count == 1)
    let owned = try await repository.attachmentURL(for: target.attachments[0])
    let ownedBytes = try Data(contentsOf: owned)
    precondition(ownedBytes == original)
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
    print("PASS materials: provider priority, exact target, local copies, durable additions across edits, Unicode text, Cancel, caps, failed batch, stale owner")
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
    session.cancel()
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
    print("PASS materials delayed providers: admission lock, duplicate rejection, cancellation, late delivery, reservation handoff")
}
