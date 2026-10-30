import AppKit
import CountdownCore
import CountdownManagerUI
import UniformTypeIdentifiers

private let materialPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=")!

@MainActor
func testImageMaterialIntake(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try await testImageRepresentationBytes(in: directory)
    try await testImageRepresentationPriority(in: directory)
    try await testImageRepresentationNames()
    try await testLosslessImageRepresentationPriority()
    try await testUnsupportedMaterialRepresentation()
    try await testCancelledImageMaterial(providerError: nil)
    try await testCancelledImageMaterial(providerError: CocoaError(.fileReadNoPermission))
    try await testImageMaterialPersistence(in: directory.appendingPathComponent("persistence"))
    print("PASS image materials: data/file bytes, source names and aliases, lossless/file URL priority, staging cleanup, unsupported formats, durable copy, draft Cancel, late success/error cancellation and capacity cleanup")
}

private func materialImageProvider() -> NSItemProvider {
    let provider = NSItemProvider()
    provider.suggestedName = "Скриншот.png"
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { callback in
        callback(materialPNG, nil)
        return nil
    }
    return provider
}

@MainActor
private func releasedImageSource(_ provider: NSItemProvider) async throws -> URL {
    let materials = try await resolveEventMaterials([provider])
    defer { withExtendedLifetime(materials.stagedFiles) {} }
    precondition(materials.files.count == 1 && materials.links.isEmpty && materials.text == nil)
    let url = materials.files[0]
    precondition(url.pathExtension.lowercased() == "png")
    let bytes = try Data(contentsOf: url)
    precondition(bytes == materialPNG, "Image drop must preserve original encoded bytes")
    return url
}

@MainActor
private func testImageRepresentationBytes(in directory: URL) async throws {
    let dataURL = try await releasedImageSource(materialImageProvider())
    precondition(!FileManager.default.fileExists(atPath: dataURL.path), "Releasing resolved materials must clean staging")
    let source = directory.appendingPathComponent("Source screenshot.png")
    try materialPNG.write(to: source)
    let fileProvider = NSItemProvider()
    fileProvider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier,
                                            fileOptions: [], visibility: .all) { callback in
        callback(source, false, nil)
        return nil
    }
    let stagedURL = try await releasedImageSource(fileProvider)
    precondition(!FileManager.default.fileExists(atPath: stagedURL.path))
    precondition(stagedURL.lastPathComponent == source.lastPathComponent, "A provider without a suggested name must preserve its source filename")
    let original = try Data(contentsOf: source)
    precondition(original == materialPNG, "Cleaning staged files must preserve the provider source")
}

@MainActor
private func testImageRepresentationPriority(in directory: URL) async throws {
    let source = directory.appendingPathComponent("Preferred file.png")
    let fileBytes = materialPNG + Data("file-priority".utf8)
    try fileBytes.write(to: source)
    let provider = materialImageProvider()
    provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier, loadHandler: { callback, _, _ in
        callback?(source as NSURL, nil)
    })
    let result = try await resolveEventMaterials([provider])
    precondition(result.files == [source] && result.links.isEmpty && result.text == nil,
                 "A file plus image representation must produce only the preferred original file")
    let bytes = try Data(contentsOf: result.files[0])
    precondition(bytes == fileBytes)
}


@MainActor
private func testImageRepresentationNames() async throws {
    for (type, name) in [(UTType.jpeg, "capture.jpg"), (.tiff, "capture.tif")] {
        let provider = NSItemProvider()
        provider.suggestedName = name
        // These opaque provider bytes test naming without introducing image decoding into intake.
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { callback in
            callback(Data([0x01, 0x02, 0x03]), nil)
            return nil
        }
        let materials = try await resolveEventMaterials([provider])
        defer { withExtendedLifetime(materials.stagedFiles) {} }
        precondition(materials.files.count == 1 && materials.files[0].lastPathComponent == name,
                     "A matching filename alias must survive import without becoming jpeg/tiff")
    }
}

@MainActor
private func testLosslessImageRepresentationPriority() async throws {
    let provider = NSItemProvider()
    provider.suggestedName = "Screen capture"
    provider.registerDataRepresentation(forTypeIdentifier: UTType.jpeg.identifier, visibility: .all) { callback in
        callback(Data([0xff, 0xd8, 0xff, 0xd9]), nil)
        return nil
    }
    provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { callback in
        callback(materialPNG, nil)
        return nil
    }
    precondition(provider.registeredTypeIdentifiers.first == UTType.jpeg.identifier)
    let materials = try await resolveEventMaterials([provider])
    defer { withExtendedLifetime(materials.stagedFiles) {} }
    precondition(materials.files.count == 1 && materials.links.isEmpty && materials.text == nil)
    precondition(materials.files[0].pathExtension == "png", "A lossless PNG must outrank an earlier JPEG preview")
    let bytes = try Data(contentsOf: materials.files[0])
    precondition(bytes == materialPNG, "Representation selection must preserve the exact PNG bytes")
}

@MainActor
private func testUnsupportedMaterialRepresentation() async throws {
    let provider = NSItemProvider()
    provider.registerDataRepresentation(forTypeIdentifier: "com.countdown.tests.unsupported", visibility: .all) { callback in
        callback(Data([0, 1, 2]), nil)
        return nil
    }
    do {
        _ = try await resolveEventMaterials([provider])
        preconditionFailure("Unsupported data must be rejected")
    } catch is MaterialIntakeError {
        // The old fallback requested public.plain-text and leaked NSItemProvider's loading error instead.
    }
}

@MainActor
private func testImageMaterialPersistence(in directory: URL) async throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let suite = "CountdownImageMaterials.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let fileURL = directory.appendingPathComponent("countdowns.json")
    let store = Store(fileURL: fileURL, disclosureDefaults: defaults, loginItemManagementIsAvailable: false)
    for _ in 0..<2_000 where store.isLoading { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(!store.isLoading)
    let event = Countdown(title: "Получатель скриншота", date: Day(Date()), emoji: "")
    let saved = await store.save(event, primary: false)
    precondition(saved)
    var materials: EventMaterials? = try await resolveEventMaterials([materialImageProvider()])
    let stagedURL = materials!.files[0]
    let added = await store.appendMaterials(materials!, to: event.id)
    precondition(added)
    materials = nil
    precondition(!FileManager.default.fileExists(atPath: stagedURL.path))
    let repository = CountdownRepository(fileURL: fileURL)
    let reopened = try await repository.load()
    precondition(reopened.items[0].attachments.count == 1)
    let attachmentURL = try await repository.attachmentURL(for: reopened.items[0].attachments[0])
    let bytes = try Data(contentsOf: attachmentURL)
    precondition(bytes == materialPNG, "Durable attachment must survive deletion of its staged source")
    let beforeCancel = try Data(contentsOf: fileURL)
    let draftID = UUID()
    let began = await store.beginAttachmentDraft(draftID)
    precondition(began)
    var draftMaterials: EventMaterials? = try await resolveEventMaterials([materialImageProvider()])
    let draftSource = draftMaterials!.files[0]
    let draftAttachment = await store.importAttachment(from: draftSource, draftID: draftID)
    withExtendedLifetime(draftMaterials) {}
    precondition(draftAttachment != nil)
    draftMaterials = nil
    precondition(!FileManager.default.fileExists(atPath: draftSource.path))
    await store.discardAttachmentDraft(draftID)
    let afterCancel = try Data(contentsOf: fileURL)
    precondition(beforeCancel == afterCancel, "Cancelling an image draft must not change saved event data")
    let ownedFolders = try FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent("Attachments").path)
    precondition(ownedFolders.count == 1, "Only the committed screenshot should remain after draft Cancel")
    let filled = await store.appendMaterials(EventMaterials(files: Array(repeating: attachmentURL, count: 13)), to: event.id)
    precondition(filled && store.data.items[0].attachments.count == 14)
    let beforeOverflow = try Data(contentsOf: fileURL)
    var overflow: EventMaterials? = try await resolveEventMaterials([materialImageProvider(), materialImageProvider()])
    let overflowSources = overflow!.files
    let rejected = await store.appendMaterials(overflow!, to: event.id)
    precondition(!rejected && store.data.items[0].attachments.count == 14)
    overflow = nil
    precondition(overflowSources.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    let afterOverflow = try Data(contentsOf: fileURL)
    precondition(beforeOverflow == afterOverflow, "An overflowing image batch must commit nothing")
}


private final class DeferredImageMaterial: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: ((Data?, Error?) -> Void)?

    var isWaiting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completion != nil
    }

    func provider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { callback in
            self.lock.lock()
            self.completion = callback
            self.lock.unlock()
            return nil
        }
        return provider
    }

    func resolve(error: Error?) {
        lock.lock()
        let callback = completion
        completion = nil
        lock.unlock()
        callback?(error == nil ? materialPNG : nil, error)
    }
}

@MainActor
private func testCancelledImageMaterial(providerError: Error?) async throws {
    let deferred = DeferredImageMaterial()
    let task = Task { try await resolveEventMaterials([deferred.provider()]) }
    for _ in 0..<2_000 where !deferred.isWaiting { try await Task.sleep(nanoseconds: 1_000_000) }
    precondition(deferred.isWaiting)
    task.cancel()
    deferred.resolve(error: providerError)
    do {
        _ = try await task.value
        preconditionFailure("A late screenshot result must not escape cancellation")
    } catch is CancellationError {
        // Resolve the real provider callback after cancellation, rather than relying on callback timing.
    }
}
