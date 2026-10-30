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
        let count = files.count + (textFile == nil ? 0 : 1)
        if count > 0, count > max(0, EventAttachment.maximumCount - event.attachments.count) {
            throw MaterialIntakeError.message("Выбрано файлов: \(count). Свободных мест: \(max(0, 15 - event.attachments.count)). Ничего не добавлено.")
        }
        if !links.isEmpty { try EventLink.validate(event.links + links) }
        try textFile?.validate()
    }

    package static func classify(_ text: String) throws -> EventMaterials {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw MaterialIntakeError.message("Нет текста для добавления.") }
        let link = EventLink(address: cleaned)
        if link.url != nil { return EventMaterials(links: [link.normalized()]) }
        if cleaned.range(of: #"^[a-zA-Z][a-zA-Z0-9+.-]*://"#, options: .regularExpression) != nil {
            throw EventLinkError.address
        }
        return EventMaterials(text: text)
    }
}

package enum MaterialIntakeError: LocalizedError {
    case message(String)
    package var errorDescription: String? { switch self { case let .message(text): return text } }
}

/// Resolves one preferred representation per item; a file must never also become a web link.
@MainActor
package func resolveEventMaterials(_ providers: [NSItemProvider]) async throws -> EventMaterials {
    var result = EventMaterials()
    for provider in providers {
        try Task.checkCancellation()
        let type: UTType
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { type = .fileURL }
        else if let imageType = materialImageType(for: provider) {
            let file: StagedMaterialFile
            do { file = try await loadMaterialImage(provider, type: imageType) }
            catch { try Task.checkCancellation(); throw error }
            try Task.checkCancellation()
            result.files.append(file.url)
            result.stagedFiles.append(file)
            continue
        }
        else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) { type = .url }
        else if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) { type = .utf8PlainText }
        else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) { type = .plainText }
        else { throw MaterialIntakeError.message("Перетащите обычный файл, изображение, HTTP/HTTPS-ссылку или текст.") }
        let value: NSSecureCoding = try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, error in
                if let error { continuation.resume(throwing: error) }
                else if let item { continuation.resume(returning: item) }
                else { continuation.resume(throwing: MaterialIntakeError.message("Не удалось получить перетаскиваемый материал.")) }
            }
        }
        try Task.checkCancellation()
        let string: String?
        if let url = value as? URL { string = url.absoluteString }
        else if let text = value as? String { string = text }
        else if let data = value as? Data { string = String(data: data, encoding: .utf8) }
        else { string = nil }
        guard let string else { throw MaterialIntakeError.message("Перетащите обычный файл, HTTP/HTTPS-ссылку или текст.") }
        if type == .fileURL {
            guard let url = URL(string: string), url.isFileURL else { throw EventAttachmentError.unsupportedFile }
            result.files.append(url)
        } else {
            let item = try EventMaterials.classify(string)
            if type == .url, item.links.isEmpty { throw EventLinkError.address }
            result.links += item.links
            if let text = item.text {
                guard result.text == nil else { throw MaterialIntakeError.message("Добавляйте один фрагмент текста за раз.") }
                result.text = text
            }
        }
    }
    if result.text != nil, !result.files.isEmpty || !result.links.isEmpty {
        throw MaterialIntakeError.message("Перетащите текст отдельно от файлов и ссылок.")
    }
    guard !result.isEmpty else { throw MaterialIntakeError.message("Нет материалов для добавления.") }
    return result
}

/// Owns an accepted provider until delivery or cancellation, including its busy reservation.
@MainActor
package final class MaterialDropSession: ObservableObject {
    private var task: Task<Void, Never>?
    private var identity: UUID?
    private var release: (() -> Void)?

    package init() {}

    @discardableResult
    package func receive(_ providers: [NSItemProvider], begin: () -> Bool, finish: @escaping () -> Void,
                         completion: @escaping (EventMaterials) -> Void, reportError: @escaping (String) -> Void) -> Bool {
        guard identity == nil, begin() else { return false }
        let token = UUID()
        identity = token
        release = finish
        task = Task { @MainActor [weak self] in
            do {
                let materials = try await resolveEventMaterials(providers)
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

    package func cancel() {
        task?.cancel()
        if let identity { finish(identity) }
    }

    private func finish(_ token: UUID) {
        guard identity == token else { return }
        identity = nil
        task = nil
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
    @State private var targeted = false
    @StateObject private var session = MaterialDropSession()
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .onDrop(of: materialDropTypes, isTargeted: $targeted) { providers in
                guard enabled else { return false }
                return session.receive(providers, begin: beginReceiving, finish: finishReceiving,
                                       completion: receive, reportError: reportError)
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
            .onDisappear { session.cancel() }
    }
}

struct EventMaterialTarget: ViewModifier {
    @ObservedObject var store: Store
    @ObservedObject var editorSession: EventEditorSession
    let eventID: UUID
    let enabled: Bool
    let showText: (String) -> Void

    private var available: Bool { enabled && !editorSession.hasActiveEditor && !store.hasPendingPersistence }

    func body(content: Content) -> some View {
        content
            .modifier(MaterialDropZone(enabled: available,
                                      beginReceiving: { available && store.beginMaterialResolution() },
                                      finishReceiving: { store.endMaterialResolution() }, receive: { materials in
                guard available else { return }
                if let text = materials.text { showText(text) }
                else { store.scheduleMaterialAddition(materials, to: eventID) }
            }, reportError: { store.error = $0 }))
            .contextMenu {
                Button("Вставить текст как вложение…") {
                    guard available else { return }
                    if let text = NSPasteboard.general.string(forType: .string),
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { showText(text) }
                    else { store.error = "Сначала скопируйте текст, который хотите сохранить во вложении." }
                }
                .disabled(!available)
            }
    }
}
