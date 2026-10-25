import Foundation

/// Used only by CountdownRepository's actor. Never removes a source URL.
struct AttachmentFiles {
    let directory: URL
    private let manager = FileManager.default

    init(repositoryURL: URL) {
        directory = repositoryURL.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
    }

    func copy(from source: URL) throws -> EventAttachment {
        guard source.isFileURL else { throw EventAttachmentError.unsupportedFile }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, values.isPackage != true else {
            throw EventAttachmentError.unsupportedFile
        }
        try Task.checkCancellation()
        var attachment = try EventAttachment(name: source.lastPathComponent, byteCount: 0)
        try ensureDirectory()
        let folder = directory.appendingPathComponent(attachment.id.uuidString, isDirectory: true)
        guard !manager.fileExists(atPath: folder.path) else { throw EventAttachmentError.unsafeStorage }
        try manager.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            // Write ownership before copying so an interrupted import can be collected at next load.
            try writeMarker(attachment, folder: folder)
            let destination = folder.appendingPathComponent(attachment.name)
            try manager.copyItem(at: source, to: destination)
            try Task.checkCancellation()
            let size = try regularFileSize(at: destination)
            attachment = try EventAttachment(id: attachment.id, name: attachment.name, byteCount: size)
            try writeMarker(attachment, folder: folder)
            return attachment
        } catch {
            // This directory was created by this exact operation and cannot hold durable data yet.
            do { try manager.removeItem(at: folder) } catch {
                // A valid ownership marker lets the repository retry cleanup independently.
            }
            throw error
        }
    }

    func url(for attachment: EventAttachment) throws -> URL {
        try validateDirectory(directory)
        let folder = directory.appendingPathComponent(attachment.id.uuidString, isDirectory: true)
        try validateDirectory(folder)
        let marker = folder.appendingPathComponent(EventAttachment.markerName(for: attachment.id))
        _ = try regularFileSize(at: marker)
        guard try JSONDecoder().decode(EventAttachment.self, from: Data(contentsOf: marker)) == attachment else {
            throw EventAttachmentError.unavailableFile
        }
        let url = folder.appendingPathComponent(attachment.name)
        // Opening in another app may change the owned copy; byteCount describes the original import.
        _ = try regularFileSize(at: url)
        return url
    }

    func cleanup(protecting protectedIDs: Set<UUID>) throws {
        guard manager.fileExists(atPath: directory.path) else { return }
        try validateDirectory(directory)
        var firstError: Error?
        for folder in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            guard let identity = UUID(uuidString: folder.lastPathComponent),
                  identity.uuidString == folder.lastPathComponent, !protectedIDs.contains(identity) else { continue }
            do { try removeOwnedFolder(folder, identity: identity) } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    private func removeOwnedFolder(_ folder: URL, identity: UUID) throws {
        try validateDirectory(folder)
        let marker = folder.appendingPathComponent(EventAttachment.markerName(for: identity))
        guard manager.fileExists(atPath: marker.path) else { return } // Unknown UUID directories stay untouched.
        _ = try regularFileSize(at: marker)
        let attachment = try JSONDecoder().decode(EventAttachment.self, from: Data(contentsOf: marker))
        guard attachment.id == identity else { throw EventAttachmentError.unsafeStorage }
        let contents = try manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        let ownedNames = Set([attachment.name, marker.lastPathComponent])
        guard contents.allSatisfy({ ownedNames.contains($0.lastPathComponent) }) else {
            throw EventAttachmentError.unsafeStorage
        }
        for url in contents { _ = try regularFileSize(at: url) }
        // Only a known metadata marker and its regular file may be removed, never arbitrary trees.
        for url in contents where url != marker { try manager.removeItem(at: url) }
        try manager.removeItem(at: marker)
        try manager.removeItem(at: folder)
    }

    private func writeMarker(_ attachment: EventAttachment, folder: URL) throws {
        try JSONEncoder().encode(attachment).write(
            to: folder.appendingPathComponent(EventAttachment.markerName(for: attachment.id)), options: .atomic
        )
    }

    private func ensureDirectory() throws {
        if manager.fileExists(atPath: directory.path) {
            try validateDirectory(directory)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            try validateDirectory(directory)
        }
    }

    private func validateDirectory(_ url: URL) throws {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw EventAttachmentError.unsafeStorage
        }
    }

    private func regularFileSize(at url: URL) throws -> Int64 {
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber else { throw EventAttachmentError.unsupportedFile }
        return size.int64Value
    }
}
