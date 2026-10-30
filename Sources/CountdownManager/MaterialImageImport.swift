import AppKit
import UniformTypeIdentifiers

// Concrete types also work when an external source advertises an encoded image without
// registering its broader image conformance with the item provider.
private let encodedMaterialImageTypes: [UTType] = [.png, .tiff, .jpeg, .heic, .heif, .gif, .bmp, .webP]
let materialDropTypes: [UTType] = [.fileURL, .url, .utf8PlainText, .plainText, .image] + encodedMaterialImageTypes

func materialImageType(for provider: NSItemProvider) -> UTType? {
    // Image objects may advertise a lossy JPEG preview before a lossless representation.
    if let type = encodedMaterialImageTypes.first(where: { provider.registeredTypeIdentifiers.contains($0.identifier) }) {
        return type
    }
    for identifier in provider.registeredTypeIdentifiers {
        if let type = UTType(identifier), type.conforms(to: .image), type.preferredFilenameExtension != nil { return type }
    }
    return nil
}

/// Keeps a provider's short-lived file alive until the consuming import has finished.
/// Every instance owns a newly created private directory, never an original source file.
package final class StagedMaterialFile: Sendable {
    package let url: URL

    private init(url: URL) { self.url = url }

    static func copy(from source: URL, suggestedName: String?, type: UTType) throws -> StagedMaterialFile {
        let manager = FileManager.default
        guard source.isFileURL else {
            throw MaterialIntakeError.message("Не удалось получить локальный файл изображения.")
        }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
        guard values.isRegularFile == true,
              values.isSymbolicLink != true, values.isPackage != true else {
            throw MaterialIntakeError.message("Не удалось получить обычный файл изображения.")
        }
        let folder = manager.temporaryDirectory.appendingPathComponent("CountdownMaterial-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            let destination = folder.appendingPathComponent(filename(source: source, suggestedName: suggestedName, type: type))
            try manager.copyItem(at: source, to: destination)
            return StagedMaterialFile(url: destination)
        } catch {
            remove(folder)
            throw error
        }
    }

    private static func filename(source: URL, suggestedName: String?, type: UTType) -> String {
        let suffix = type.preferredFilenameExtension ?? "png"
        let name = [suggestedName, source.lastPathComponent].compactMap { $0 }.first { candidate in
            !candidate.isEmpty && candidate != "." && candidate != ".." && candidate.utf8.count < 220 &&
                !candidate.contains("/") && !candidate.contains("\\") && !candidate.contains("\0")
        } ?? "Изображение"
        let ext = (name as NSString).pathExtension.lowercased()
        if UTType(filenameExtension: ext) == type || matchingExtension(ext, type: type) { return name }
        let stem = (name as NSString).deletingPathExtension
        return "\(stem).\(suffix)"
    }

    private static func matchingExtension(_ ext: String, type: UTType) -> Bool {
        switch type {
        case .png: return ext == "png"
        case .jpeg: return ["jpg", "jpeg", "jpe"].contains(ext)
        case .tiff: return ["tif", "tiff"].contains(ext)
        case .heic: return ext == "heic"
        case .heif: return ext == "heif"
        case .gif: return ext == "gif"
        case .bmp: return ["bmp", "dib"].contains(ext)
        case .webP: return ext == "webp"
        default: return false
        }
    }

    private static func remove(_ folder: URL) {
        do { try FileManager.default.removeItem(at: folder) }
        catch { DiagnosticLog.shared.record("materials.staging cleanup failure category=storage") }
    }

    deinit { Self.remove(url.deletingLastPathComponent()) }
}

@MainActor
func loadMaterialImage(_ provider: NSItemProvider, type: UTType) async throws -> StagedMaterialFile {
    let request = MaterialImageRequest()
    let suggestedName = provider.suggestedName
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let progress = provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { source, error in
                // Progress cancellation and a late source callback may both complete this load.
                guard request.claimCompletion() else { return }
                guard let source, error == nil else {
                    continuation.resume(throwing: MaterialIntakeError.message("Не удалось получить изображение. Повторите перетаскивание."))
                    return
                }
                do {
                    // The provider may delete source immediately after this callback returns.
                    let staged = try StagedMaterialFile.copy(from: source, suggestedName: suggestedName, type: type)
                    continuation.resume(returning: staged)
                } catch {
                    continuation.resume(throwing: MaterialIntakeError.message("Не удалось подготовить изображение. Проверьте доступ и свободное место на диске."))
                }
            }
            request.install(progress)
        }
    } onCancel: {
        request.cancel()
    }
}

/// Cancellation may race the synchronous return of loadFileRepresentation.
private final class MaterialImageRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var progress: Progress?
    private var isCancelled = false
    private var hasCompleted = false

    func install(_ progress: Progress) {
        lock.lock()
        if !hasCompleted { self.progress = progress }
        let cancelled = isCancelled && !hasCompleted
        lock.unlock()
        if cancelled { progress.cancel() }
    }

    func claimCompletion() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !hasCompleted else { return false }
        hasCompleted = true
        progress = nil
        return true
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let progress = progress
        lock.unlock()
        progress?.cancel()
    }
}
