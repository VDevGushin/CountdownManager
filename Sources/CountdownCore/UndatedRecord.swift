import Foundation

public struct UndatedRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var note: String?
    public var subtasks: [Subtask]
    public var attachments: [EventAttachment]
    public var links: [EventLink]

    public init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        subtasks: [Subtask] = [],
        attachments: [EventAttachment] = [],
        links: [EventLink] = []
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.subtasks = subtasks
        self.attachments = attachments
        self.links = links
    }

    package func normalized() throws -> Self {
        guard CountdownNote.isAllowed(note ?? "") else { throw UndatedRecordError.note }
        var result = self
        result.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        result.note = cleanedNote?.isEmpty == false ? cleanedNote : nil
        for index in subtasks.indices {
            try result.subtasks[index].normalizeAndValidate()
        }
        result.links = links.map { $0.normalized() }
        try result.validateStoredValue()
        return result
    }

    func validateStoredValue() throws {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw UndatedRecordError.title }
        guard CountdownNote.isAllowed(note ?? "") else { throw UndatedRecordError.note }
        guard subtasks.count <= Subtask.maximumCount else { throw CountdownError.subtaskCount }
        guard Set(subtasks.map(\.id)).count == subtasks.count else { throw UndatedRecordError.identity }
        for subtask in subtasks { try subtask.validateStoredValue() }
        guard attachments.count <= EventAttachment.maximumCount else { throw EventAttachmentError.limitExceeded }
        try EventLink.validate(links)
    }
}

package enum UndatedRecordError: LocalizedError {
    case title, note, unavailable, identity

    package var errorDescription: String? {
        switch self {
        case .title: AppText.string("record.error.titleRequired")
        case .note: AppText.string("record.error.noteTooLong")
        case .unavailable: AppText.string("record.error.unavailable")
        case .identity: AppText.string("record.error.identity")
        }
    }
}
