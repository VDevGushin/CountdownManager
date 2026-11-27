import AppKit
import CountdownCore
import SwiftUI
import UniformTypeIdentifiers

package struct EventMaterials {
    package var files: [URL] = []
    package var links: [EventLink] = []
    package var text: String?
    package var textFile: TextAttachment?
    package var stagedFiles: [StagedMaterialFile] = []

    package init(files: [URL] = [], links: [EventLink] = [], text: String? = nil,
                 textFile: TextAttachment? = nil) {
        self.files = files; self.links = links; self.text = text; self.textFile = textFile
    }

    package var isEmpty: Bool { files.isEmpty && links.isEmpty && text == nil && textFile == nil }

    package func validateCapacity(for event: Countdown) throws {
        try validateCapacity(attachments: event.attachments, existingLinks: event.links)
    }

    func validateCapacity(attachments: [EventAttachment], existingLinks: [EventLink]) throws {
        let count = files.count + (textFile == nil ? 0 : 1)
        let remaining = max(0, EventAttachment.maximumCount - attachments.count)
        if count > remaining {
            throw MaterialIntakeError.message(AppText.string("material.mixedFileLimit", "\(count)", "\(remaining)"))
        }
        if !links.isEmpty { try EventLink.validate(existingLinks + links) }
        try textFile?.validate()
    }

    package static func classify(_ text: String) throws -> EventMaterials {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw MaterialIntakeError.message(AppText.string("material.emptyText")) }
        let link = EventLink(address: cleaned)
        if link.url != nil { return EventMaterials(links: [link.normalized()]) }
        if !cleaned.contains(where: \.isNewline),
           cleaned.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil {
            throw EventLinkError.address
        }
        return EventMaterials(text: text)
    }
}

package enum MaterialIntakeError: LocalizedError {
    case message(String)
    package var errorDescription: String? { switch self { case let .message(text): return text } }
}

private enum LoadedMaterial {
    case item(UTType, String, isNativeFile: Bool)
    case image(StagedMaterialFile)
    case webLinks([EventLink])
}

private func decodeWebLinks(_ data: Data) throws -> [EventLink] {
    guard let columns = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String]],
          columns.count == 2, !columns[0].isEmpty, columns[0].count == columns[1].count else {
        throw MaterialIntakeError.message(AppText.string("material.dropFailed"))
    }
    let links = zip(columns[0], columns[1]).map { address, title in
        EventLink(name: title, address: address).normalized()
    }
    try EventLink.validate(links)
    return links
}

/// Safari's Smart Search drag may reach SwiftUI as one provider without any registered types.
/// Read the corresponding Safari bookmark item while the native drag is still active.
@MainActor
package func safariBookmarkProvider(replacing providers: [NSItemProvider], from pasteboard: NSPasteboard) -> NSItemProvider? {
    let safariBookmarks = NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")
    guard providers.count == 1, providers[0].registeredTypeIdentifiers.isEmpty,
          let items = pasteboard.pasteboardItems, items.count == 1,
          let item = items.first, item.types.contains(safariBookmarks) else { return nil }
    if let type = webURLsWithTitlesType, let data = item.data(forType: NSPasteboard.PasteboardType(type.identifier)) {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { complete in
            complete(data, nil)
            return nil
        }
        return provider
    }
    guard let address = item.string(forType: .URL), let url = EventLink(address: address).url else { return nil }
    return NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
}

private func droppedFileURL(_ address: String) -> URL? {
    guard !address.contains(where: \.isWhitespace),
          !address.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
          let url = URL(string: address), url.absoluteString == address,
          EventAttachment.isLocalFileSource(url) else { return nil }
    return url
}

/// Finder may publish an AppKit file-reference URL while SwiftUI supplies the item’s
/// ordinary file URL as text. Keep native file provenance separate from that payload.
@MainActor
package func nativeFileDropIndices(providerCount: Int, from pasteboard: NSPasteboard) -> Set<Int> {
    guard let items = pasteboard.pasteboardItems, items.count == providerCount else { return [] }
    return Set(items.indices.filter { items[$0].types.contains(.fileURL) })
}

private struct MaterialLoad {
    private let stream: AsyncThrowingStream<LoadedMaterial, Error>
    let cancel: () -> Void

    @MainActor
    init(provider: NSItemProvider, type: UTType, isNativeFile: Bool = false) {
        let (stream, continuation) = AsyncThrowingStream<LoadedMaterial, Error>.makeStream()
        self.stream = stream
        let stop: (() -> Void)?
        if type.conforms(to: .image) {
            stop = startMaterialImageLoad(provider, type: type) { result in
                continuation.yield(with: result.map(LoadedMaterial.image))
                continuation.finish()
            }
        } else if type == webURLsWithTitlesType {
            let progress = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                guard let data, error == nil else {
                    continuation.finish(throwing: MaterialIntakeError.message(AppText.string("material.dropFailed")))
                    return
                }
                continuation.yield(with: Result { .webLinks(try decodeWebLinks(data)) })
                continuation.finish()
            }
            stop = progress.cancel
        } else {
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { value, error in
                guard let value, error == nil else {
                    continuation.finish(throwing: MaterialIntakeError.message(AppText.string("material.dropFailed")))
                    return
                }
                let string: String?
                if let url = value as? URL { string = url.absoluteString }
                else if let text = value as? String { string = text }
                else if let data = value as? Data { string = String(data: data, encoding: .utf8) }
                else { string = nil }
                guard let string else {
                    continuation.finish(throwing: MaterialIntakeError.message(AppText.string("material.allowedTypesWithoutImage")))
                    return
                }
                continuation.yield(.item(type, string, isNativeFile: isNativeFile))
                continuation.finish()
            }
            stop = nil
        }
        cancel = {
            continuation.finish(throwing: CancellationError())
            stop?()
        }
    }

    func value() async throws -> LoadedMaterial {
        var iterator = stream.makeAsyncIterator()
        let payload = try await iterator.next()
        try Task.checkCancellation()
        guard let payload else { throw MaterialIntakeError.message(AppText.string("material.dropFailed")) }
        return payload
    }
}

/// SwiftUI's drop permission requires starting every provider load before the callback returns.
@MainActor
private func startMaterialLoads(_ providers: [NSItemProvider], nativeFileIndices: Set<Int>) throws -> [MaterialLoad] {
    let types = try providers.enumerated().map { index, provider -> UTType in
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return .fileURL }
        if nativeFileIndices.contains(index) {
            for type in [UTType.url, .utf8PlainText, .plainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
                return type
            }
        }
        if let type = materialImageType(for: provider) { return type }
        if let webURLsWithTitlesType, provider.hasItemConformingToTypeIdentifier(webURLsWithTitlesType.identifier) {
            return webURLsWithTitlesType
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) { return .url }
        if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) { return .utf8PlainText }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) { return .plainText }
        throw MaterialIntakeError.message(AppText.string("material.allowedTypes"))
    }
    return providers.indices.map { index in
        MaterialLoad(provider: providers[index], type: types[index], isNativeFile: nativeFileIndices.contains(index))
    }
}

@MainActor
package func resolveEventMaterials(_ providers: [NSItemProvider], nativeFileIndices: Set<Int> = []) async throws -> EventMaterials {
    try Task.checkCancellation()
    return try await collectMaterials(startMaterialLoads(providers, nativeFileIndices: nativeFileIndices))
}

@MainActor
private func collectMaterials(_ loads: [MaterialLoad]) async throws -> EventMaterials {
    defer { loads.forEach { $0.cancel() } }
    var result = EventMaterials()
    for load in loads {
        switch try await load.value() {
        case let .image(file):
            result.files.append(file.url)
            result.stagedFiles.append(file)
        case let .webLinks(links):
            result.links += links
        case let .item(type, string, isNativeFile):
            if isNativeFile || type == .fileURL, let url = droppedFileURL(string) {
                result.files.append(url)
            } else {
                guard !isNativeFile, type != .fileURL else { throw EventAttachmentError.unsupportedFile }
                let item = try EventMaterials.classify(string)
                if type == .url, item.links.isEmpty { throw EventLinkError.address }
                result.links += item.links
                if let text = item.text {
                    guard result.text == nil else { throw MaterialIntakeError.message(AppText.string("material.singleText")) }
                    result.text = text
                }
            }
        }
    }
    if result.text != nil, !result.files.isEmpty || !result.links.isEmpty {
        throw MaterialIntakeError.message(AppText.string("material.separateText"))
    }
    guard !result.isEmpty else { throw MaterialIntakeError.message(AppText.string("material.empty")) }
    return result
}

/// Owns an accepted provider until delivery or cancellation, including its busy reservation.
@MainActor
package final class MaterialDropSession: ObservableObject {
    private var task: Task<Void, Never>?
    private var expiration: Task<Void, Never>?
    private let timeout: Duration
    private var identity: UUID?
    private var release: (() -> Void)?

    package init(timeout: Duration = .seconds(60)) {
        self.timeout = timeout
    }

    @discardableResult
    package func receive(_ providers: [NSItemProvider], nativeFileIndices: Set<Int> = [],
                         begin: () -> Bool, finish: @escaping () -> Void,
                         completion: @escaping (EventMaterials) -> Void, reportError: @escaping (String) -> Void) -> Bool {
        guard identity == nil, begin() else { return false }
        let loads: [MaterialLoad]
        do { loads = try startMaterialLoads(providers, nativeFileIndices: nativeFileIndices) }
        catch {
            finish()
            reportError(error.localizedDescription)
            return false
        }
        let token = UUID()
        identity = token
        release = finish
        expiration = Task { @MainActor [weak self, timeout] in
            do { try await Task.sleep(for: timeout) } catch { return }
            guard let self, self.identity == token, self.cancel() else { return }
            reportError(AppText.string("material.dropFailed"))
        }
        task = Task { @MainActor [weak self] in
            do {
                let materials = try await collectMaterials(loads)
                guard !Task.isCancelled, let self, self.identity == token else { return }
                // Release and hand off synchronously so Save/editor entry cannot overtake delivery.
                self.finish(token)
                completion(materials)
            } catch {
                guard let self, self.identity == token else { return }
                self.finish(token)
                if !(error is CancellationError) { reportError(error.localizedDescription) }
            }
        }
        return true
    }

    @discardableResult
    package func cancel() -> Bool {
        guard let identity else { return false }
        task?.cancel()
        finish(identity)
        return true
    }

    private func finish(_ token: UUID) {
        guard identity == token else { return }
        identity = nil
        task = nil
        expiration?.cancel()
        expiration = nil
        let cleanup = release
        release = nil
        cleanup?()
    }
}

struct MaterialDropZone: ViewModifier {
    let enabled: Bool
    var beginReceiving: () -> Bool = { true }
    var finishReceiving: () -> Void = {}
    let receive: (EventMaterials) -> Void
    let reportError: (String) -> Void
    var smokeDropID: String?
    var reportsInterruptedDrop = false
    @State private var targeted = false
    @StateObject private var session = MaterialDropSession()
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .onDrop(of: materialDropTypes, isTargeted: $targeted) { providers in
                receiveDrop(providers, from: NSPasteboard(name: .drag))
            }
            .background {
                if UISmokeConfiguration.wasRequested, let smokeDropID {
                    Color.clear.uiSmokeControl(id: smokeDropID, drop: { receiveDrop($0, from: nil) })
                        .disabled(!enabled)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if targeted, enabled {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(AuroraInstrument.accentSurface(for: colorScheme,
                                highContrast: accessibilitySettings.prefersHighContrast))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(AuroraInstrument.accent(for: colorScheme,
                                                highContrast: accessibilitySettings.prefersHighContrast), lineWidth: 2)
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onDisappear {
                if session.cancel(), reportsInterruptedDrop {
                    reportError(AppText.string("store.materialBecameUnavailable"))
                }
            }
    }

    private func receiveDrop(_ providers: [NSItemProvider], from pasteboard: NSPasteboard?) -> Bool {
        guard enabled, isEnabled else { return false }
        let recovered = pasteboard.flatMap { safariBookmarkProvider(replacing: providers, from: $0) }
        if recovered != nil, UISmokeConfiguration.visualPreviewWasRequested {
            DiagnosticLog.shared.record("materials.drop safariBookmarkRecovered=true")
        }
        let materials = recovered.map { [$0] } ?? providers
        let files: Set<Int>
        if let pasteboard, recovered == nil {
            files = nativeFileDropIndices(providerCount: providers.count, from: pasteboard)
        } else {
            files = []
        }
        return session.receive(materials, nativeFileIndices: files, begin: beginReceiving, finish: finishReceiving,
                               completion: receive, reportError: reportError)
    }
}

struct SavedMaterialTarget: ViewModifier {
    @ObservedObject var store: Store
    @ObservedObject var editorSession: EventEditorSession
    let ownerID: SavedMaterialOwnerID
    let enabled: Bool
    let targetSurface: String
    let showText: (String) -> Void

    private var available: Bool { enabled && !editorSession.hasActiveEditor && !store.hasPendingPersistence }
    private var smokeDropID: String {
        let collection = ownerID.collection == .events ? "events" : "records"
        return "materials.drop.\(targetSurface).\(collection).\(ownerID.id)"
    }

    func body(content: Content) -> some View {
        content
            .modifier(MaterialDropZone(enabled: available,
                                      beginReceiving: { available && store.beginMaterialResolution(for: ownerID) },
                                      finishReceiving: { store.endMaterialResolution() }, receive: { materials in
                guard available else {
                    store.error = AppText.string("store.materialAdmissionBlocked")
                    return
                }
                if let text = materials.text { showText(text) }
                else { store.scheduleMaterialAddition(materials, to: ownerID) }
            }, reportError: { store.error = $0 }, smokeDropID: smokeDropID, reportsInterruptedDrop: true))
            .contextMenu {
                Button(AppText.string("material.pasteText")) {
                    guard available else { return }
                    if let text = NSPasteboard.general.string(forType: .string),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { showText(text) }
                    else { store.error = AppText.string("material.pasteTextHint") }
                }
                .disabled(!available)
            }
    }
}
