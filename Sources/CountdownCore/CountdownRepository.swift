import Foundation

package enum StoredAttachmentCollection: Hashable, Sendable {
    case events, records

    var directoryName: String {
        switch self {
        case .events: "Attachments"
        case .records: "RecordAttachments"
        }
    }
}

/// Serializes local data and file-copy operations outside the UI actor.
public actor CountdownRepository {
    private struct AttachmentDraft {
        let collection: StoredAttachmentCollection
        var metadata: [UUID: EventAttachment] = [:]
    }

    private let fileURL: URL
    private let recordsURL: URL
    private var highestWrittenRevision = 0
    private var hasReadOrWrittenRecordsFile = false
    private var durableAttachments: [StoredAttachmentCollection: [UUID: EventAttachment]] = [:]
    private var attachmentDrafts: [UUID: AttachmentDraft] = [:]
    private var cleanupFailures = Set<StoredAttachmentCollection>()
    public var attachmentCleanupFailed: Bool { attachmentCleanupFailed(in: .events) }

    public init(fileURL: URL) {
        self.fileURL = fileURL
        recordsURL = Self.recordsFileURL(beside: fileURL)
    }

    package static func recordsFileURL(beside fileURL: URL) -> URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("records.json")
    }

    public func load() throws -> CountdownData {
        let data = try read(CountdownData.self, at: fileURL, default: CountdownData())
        durableAttachments[.events] = try data.attachmentMetadata()
        attemptAttachmentCleanup(in: .events)
        return data
    }

    package func loadRecords() throws -> [UndatedRecord] {
        let records = try readRecords()
        durableAttachments[.records] = try recordAttachments(in: records)
        attemptAttachmentCleanup(in: .records)
        return records
    }

    /// Returns false when a newer event snapshot has already reached disk.
    @discardableResult
    public func save(_ data: CountdownData, revision: Int) throws -> Bool {
        guard revision >= highestWrittenRevision else { return false }
        try data.validateSubtasksForPersistence()
        try write(data, at: fileURL, attachments: data.attachmentMetadata(), in: .events)
        highestWrittenRevision = revision
        return true
    }

    package func saveRecords(_ records: [UndatedRecord]) throws {
        _ = try recordsFileExistsOrCollectionIsNew()
        try write(records, at: recordsURL, attachments: recordAttachments(in: records), in: .records)
    }

    public func beginAttachmentDraft(_ draftID: UUID) throws {
        try beginAttachmentDraft(draftID, in: .events)
    }

    package func beginAttachmentDraft(_ draftID: UUID, in collection: StoredAttachmentCollection) throws {
        try ensureDurableAttachments(in: collection)
        if let draft = attachmentDrafts[draftID] {
            guard draft.collection == collection else { throw EventAttachmentError.unknownDraft }
        } else {
            attachmentDrafts[draftID] = AttachmentDraft(collection: collection)
        }
    }

    public func importAttachment(from source: URL, draftID: UUID) throws -> EventAttachment {
        guard let draft = attachmentDrafts[draftID] else { throw EventAttachmentError.unknownDraft }
        try prepareSnapshotForRecordCopy(in: draft.collection)
        let attachment = try attachmentFiles(in: draft.collection).copy(from: source)
        attachmentDrafts[draftID]?.metadata[attachment.id] = attachment
        return attachment
    }

    public func createTextAttachment(_ text: TextAttachment, draftID: UUID) throws -> EventAttachment {
        guard let draft = attachmentDrafts[draftID] else { throw EventAttachmentError.unknownDraft }
        try prepareSnapshotForRecordCopy(in: draft.collection)
        let attachment = try attachmentFiles(in: draft.collection).createText(text)
        attachmentDrafts[draftID]?.metadata[attachment.id] = attachment
        return attachment
    }

    /// Pins independent inherited files for one Save attempt. The caller releases copyDraftID after commit or failure.
    public func copyEventAttachments(_ attachments: [EventAttachment], inheritedFrom source: [EventAttachment],
                                     editorDraftID: UUID, copyDraftID: UUID) throws -> [EventAttachment] {
        guard let draft = attachmentDrafts[editorDraftID], draft.collection == .events,
              attachmentDrafts[copyDraftID] == nil else {
            throw EventAttachmentError.unknownDraft
        }
        try ensureDurableAttachments(in: .events)
        attachmentDrafts[copyDraftID] = AttachmentDraft(collection: .events)
        let files = attachmentFiles(in: .events)
        var copies: [EventAttachment] = []
        for attachment in attachments {
            try Task.checkCancellation()
            if source.contains(attachment) {
                guard durableAttachments[.events]?[attachment.id] == attachment else {
                    throw EventAttachmentError.unavailableFile
                }
                let url = try files.url(for: attachment)
                let copy = try files.copy(from: url)
                attachmentDrafts[copyDraftID]?.metadata[copy.id] = copy
                copies.append(copy)
            } else {
                guard draft.metadata[attachment.id] == attachment else {
                    throw EventAttachmentError.unavailableFile
                }
                _ = try files.url(for: attachment)
                copies.append(attachment)
            }
        }
        return copies
    }

    public func discardAttachmentDraft(_ draftID: UUID) throws {
        let collection = attachmentDrafts.removeValue(forKey: draftID)?.collection ?? .events
        try cleanupAttachments(in: collection)
    }

    public func attachmentURL(for attachment: EventAttachment) throws -> URL {
        try attachmentURL(for: attachment, in: .events)
    }

    package func attachmentURL(for attachment: EventAttachment, in collection: StoredAttachmentCollection) throws -> URL {
        try ensureDurableAttachments(in: collection)
        guard durableAttachments[collection]?[attachment.id] == attachment || attachmentDrafts.values.contains(where: {
            $0.collection == collection && $0.metadata[attachment.id] == attachment
        }) else { throw EventAttachmentError.unavailableFile }
        return try attachmentFiles(in: collection).url(for: attachment)
    }

    public func draftAttachmentURL(for attachment: EventAttachment, draftID: UUID) throws -> URL {
        guard let draft = attachmentDrafts[draftID], draft.metadata[attachment.id] == attachment else {
            throw EventAttachmentError.unavailableFile
        }
        return try attachmentFiles(in: draft.collection).url(for: attachment)
    }

    /// Retryable maintenance. A cleanup error never reverses a successful atomic JSON write.
    public func cleanupAttachments() throws {
        try cleanupAttachments(in: .events)
    }

    package func attachmentCleanupFailed(in collection: StoredAttachmentCollection) -> Bool {
        cleanupFailures.contains(collection)
    }

    private func cleanupAttachments(in collection: StoredAttachmentCollection) throws {
        try ensureDurableAttachments(in: collection)
        var protectedIDs = Set(durableAttachments[collection].map { Array($0.keys) } ?? [])
        for draft in attachmentDrafts.values where draft.collection == collection {
            protectedIDs.formUnion(draft.metadata.keys)
        }
        do {
            if collection == .records { _ = try recordsFileExistsOrCollectionIsNew() }
            try attachmentFiles(in: collection).cleanup(protecting: protectedIDs)
            cleanupFailures.remove(collection)
        } catch {
            cleanupFailures.insert(collection)
            throw error
        }
    }

    private func recordAttachments(in records: [UndatedRecord]) throws -> [UUID: EventAttachment] {
        guard Set(records.map(\.id)).count == records.count else { throw UndatedRecordError.identity }
        for record in records { try record.validateStoredValue() }
        return try validatedAttachmentMetadata(records.map(\.attachments), allowsSharedReferences: false)
    }

    private func attachmentFiles(in collection: StoredAttachmentCollection) -> AttachmentFiles {
        AttachmentFiles(repositoryURL: fileURL, collection: collection)
    }

    private func read<Value: Decodable>(_ type: Value.Type, at url: URL, default empty: Value) throws -> Value {
        // A missing target behind a symlink is a read failure, not evidence of an empty collection.
        guard try attributesIfPresent(at: url) != nil else { return empty }
        return try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    private func attributesIfPresent(at url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return nil
        }
    }

    private func recordsFileExistsOrCollectionIsNew() throws -> Bool {
        if try attributesIfPresent(at: recordsURL) != nil { return true }

        let directory = attachmentFiles(in: .records).directory
        if !hasReadOrWrittenRecordsFile, try !hasPotentialRecordCopies(in: directory) { return false }
        throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: recordsURL.path])
    }

    private func hasPotentialRecordCopies(in directory: URL) throws -> Bool {
        guard let attributes = try attributesIfPresent(at: directory) else { return false }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            throw EventAttachmentError.unsafeStorage
        }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).contains {
            UUID(uuidString: $0) != nil
        }
    }

    private func readRecords() throws -> [UndatedRecord] {
        guard try recordsFileExistsOrCollectionIsNew() else { return [] }
        let records = try JSONDecoder().decode([UndatedRecord].self, from: Data(contentsOf: recordsURL))
        hasReadOrWrittenRecordsFile = true
        return records
    }

    private func prepareSnapshotForRecordCopy(in collection: StoredAttachmentCollection) throws {
        guard collection == .records, try !recordsFileExistsOrCollectionIsNew() else { return }
        // Make the empty snapshot intentional before an import can leave a draft-only copy on disk.
        try writeSnapshot([UndatedRecord](), at: recordsURL)
        hasReadOrWrittenRecordsFile = true
    }

    private func write<Value: Encodable>(
        _ data: Value,
        at url: URL,
        attachments: [UUID: EventAttachment],
        in collection: StoredAttachmentCollection
    ) throws {
        try ensureDurableAttachments(in: collection)
        let files = attachmentFiles(in: collection)
        for attachment in attachments.values {
            // Missing historical copies stay visible and removable; a new reference must have a real copy.
            if durableAttachments[collection]?[attachment.id] != attachment {
                _ = try files.url(for: attachment)
            }
        }
        try writeSnapshot(data, at: url)
        if collection == .records { hasReadOrWrittenRecordsFile = true }
        durableAttachments[collection] = attachments
        attemptAttachmentCleanup(in: collection)
    }

    private func writeSnapshot<Value: Encodable>(_ data: Value, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: url, options: .atomic)
    }

    private func ensureDurableAttachments(in collection: StoredAttachmentCollection) throws {
        guard durableAttachments[collection] == nil else { return }
        switch collection {
        case .events:
            let data = try read(CountdownData.self, at: fileURL, default: CountdownData())
            durableAttachments[collection] = try data.attachmentMetadata()
        case .records:
            durableAttachments[collection] = try recordAttachments(in: readRecords())
        }
    }

    private func attemptAttachmentCleanup(in collection: StoredAttachmentCollection) {
        do { try cleanupAttachments(in: collection) }
        catch { cleanupFailures.insert(collection) }
    }
}
