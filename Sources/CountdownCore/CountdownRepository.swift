import Foundation

/// Serializes all reads and writes so disk access never has to run on the UI actor.
public actor CountdownRepository {
    private let fileURL: URL
    private var highestWrittenRevision = 0
    private let attachmentFiles: AttachmentFiles
    private var durableAttachments: [UUID: EventAttachment]?
    private var attachmentDrafts: [UUID: [UUID: EventAttachment]] = [:]
    public private(set) var attachmentCleanupFailed = false

    public init(fileURL: URL) {
        self.fileURL = fileURL
        attachmentFiles = AttachmentFiles(repositoryURL: fileURL)
    }

    public func load() throws -> CountdownData {
        let data = try readData()
        durableAttachments = try data.attachmentMetadata()
        attemptAttachmentCleanup()
        return data
    }

    /// Returns false when a newer snapshot has already reached disk.
    @discardableResult
    public func save(_ data: CountdownData, revision: Int) throws -> Bool {
        guard revision >= highestWrittenRevision else { return false }
        try data.validateSubtasksForPersistence()
        let attachments = try data.attachmentMetadata()
        try ensureDurableAttachments()
        for attachment in attachments.values {
            // Missing historical copies stay visible and removable; a new reference must have a real copy.
            if durableAttachments?[attachment.id] != attachment {
                _ = try attachmentFiles.url(for: attachment)
            }
        }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
        highestWrittenRevision = revision
        durableAttachments = attachments
        attemptAttachmentCleanup()
        return true
    }

    public func beginAttachmentDraft(_ draftID: UUID) throws {
        try ensureDurableAttachments()
        if attachmentDrafts[draftID] == nil { attachmentDrafts[draftID] = [:] }
    }

    public func importAttachment(from source: URL, draftID: UUID) throws -> EventAttachment {
        guard attachmentDrafts[draftID] != nil else { throw EventAttachmentError.unknownDraft }
        let attachment = try attachmentFiles.copy(from: source)
        attachmentDrafts[draftID]?[attachment.id] = attachment
        return attachment
    }

    public func createTextAttachment(_ text: TextAttachment, draftID: UUID) throws -> EventAttachment {
        guard attachmentDrafts[draftID] != nil else { throw EventAttachmentError.unknownDraft }
        let attachment = try attachmentFiles.createText(text)
        attachmentDrafts[draftID]?[attachment.id] = attachment
        return attachment
    }

    public func discardAttachmentDraft(_ draftID: UUID) throws {
        attachmentDrafts.removeValue(forKey: draftID)
        try cleanupAttachments()
    }

    public func attachmentURL(for attachment: EventAttachment) throws -> URL {
        try ensureDurableAttachments()
        guard durableAttachments?[attachment.id] == attachment || attachmentDrafts.values.contains(where: {
            $0[attachment.id] == attachment
        }) else { throw EventAttachmentError.unavailableFile }
        return try attachmentFiles.url(for: attachment)
    }

    public func draftAttachmentURL(for attachment: EventAttachment, draftID: UUID) throws -> URL {
        guard attachmentDrafts[draftID]?[attachment.id] == attachment else {
            throw EventAttachmentError.unavailableFile
        }
        return try attachmentFiles.url(for: attachment)
    }

    /// Retryable maintenance. A cleanup error never reverses a successful atomic JSON write.
    public func cleanupAttachments() throws {
        try ensureDurableAttachments()
        var protectedIDs = Set(durableAttachments.map { Array($0.keys) } ?? [])
        for draft in attachmentDrafts.values { protectedIDs.formUnion(draft.keys) }
        do {
            try attachmentFiles.cleanup(protecting: protectedIDs)
            attachmentCleanupFailed = false
        } catch {
            attachmentCleanupFailed = true
            throw error
        }
    }

    private func readData() throws -> CountdownData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return CountdownData() }
        return try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fileURL))
    }

    private func ensureDurableAttachments() throws {
        if durableAttachments == nil { durableAttachments = try readData().attachmentMetadata() }
    }

    private func attemptAttachmentCleanup() {
        do { try cleanupAttachments() } catch { attachmentCleanupFailed = true }
    }
}
