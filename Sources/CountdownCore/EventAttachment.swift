import CoreFoundation
import Foundation

/// Metadata only; the repository owns the separate local file copy.
public struct EventAttachment: Identifiable, Codable, Equatable {
    public static let maximumCount = 15
    public let id: UUID
    public let name: String
    public let byteCount: Int64

    public init(id: UUID = UUID(), name: String, byteCount: Int64) throws {
        guard !name.isEmpty, name != ".", name != "..",
              !name.contains("/"), !name.contains("\\"), !name.contains("\0"),
              name != Self.markerName(for: id), byteCount >= 0 else {
            throw EventAttachmentError.invalidMetadata
        }
        self.id = id
        self.name = name
        self.byteCount = byteCount
    }

    private enum CodingKeys: String, CodingKey { case id, name, byteCount }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: values.decode(UUID.self, forKey: .id),
            name: values.decode(String.self, forKey: .name),
            byteCount: values.decode(Int64.self, forKey: .byteCount)
        )
    }

    static func markerName(for id: UUID) -> String { ".countdown-attachment-" + id.uuidString }

    package static func isLocalFileSource(_ url: URL) -> Bool {
        guard url.isFileURL, url.path.hasPrefix("/"),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath.removingPercentEncoding == url.path else { return false }
        return hasLocalFileAuthority(components)
    }

    package static func localFileSource(from address: String) -> URL? {
        guard !address.contains(where: \.isWhitespace),
              !address.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let components = URLComponents(string: address), components.string == address,
              hasLocalFileAuthority(components), let raw = NSURL(string: address) else { return nil }
        if !raw.isFileReferenceURL() {
            guard let source = URL(string: address), source.absoluteString == address,
                  isLocalFileSource(source) else { return nil }
            return source
        }

        // Foundation can also normalize malformed references. Match the file's own native ID.
        guard let path = CFURLCreateFilePathURL(nil, raw as CFURL, nil)?.takeRetainedValue(),
              isLocalFileSource(path as URL),
              let reference = CFURLCreateFileReferenceURL(nil, path, nil)?.takeRetainedValue(),
              let referenceAddress = CFURLGetString(reference) as String?,
              let native = URLComponents(string: referenceAddress),
              native.percentEncodedPath == components.percentEncodedPath else { return nil }
        return path as URL
    }

    private static func hasLocalFileAuthority(_ components: URLComponents) -> Bool {
        guard components.scheme?.lowercased() == "file", components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { return false }
        let host = components.host?.lowercased() ?? ""
        guard host.isEmpty || host == "localhost" else { return false }
        // Reject any port syntax, including an empty port or one that cannot be read as an Int.
        guard let hostRange = components.rangeOfHost else { return true }
        return hostRange.upperBound == components.rangeOfPath?.lowerBound
    }
}

public enum EventAttachmentError: LocalizedError {
    case invalidMetadata, unsupportedFile, unknownDraft, unavailableFile, unsafeStorage, limitExceeded

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: return AppText.string("attachment.error.invalidMetadata")
        case .unsupportedFile: return AppText.string("attachment.error.unsupportedFile")
        case .unknownDraft: return AppText.string("attachment.error.editorClosed")
        case .unavailableFile: return AppText.string("attachment.error.missingCopy")
        case .unsafeStorage: return AppText.string("attachment.error.unsafeStorage")
        case .limitExceeded: return AppText.string("attachment.error.limit", "\(EventAttachment.maximumCount)")
        }
    }
}

extension CountdownData {
    func attachmentMetadata() throws -> [UUID: EventAttachment] {
        try validatedAttachmentMetadata(items.map(\.attachments), allowsSharedReferences: true)
    }
}

func validatedAttachmentMetadata(
    _ groups: [[EventAttachment]],
    allowsSharedReferences: Bool
) throws -> [UUID: EventAttachment] {
    var metadata: [UUID: EventAttachment] = [:]
    for group in groups {
        var localIDs = Set<UUID>()
        for attachment in group {
            guard localIDs.insert(attachment.id).inserted else { throw EventAttachmentError.invalidMetadata }
            if let existing = metadata[attachment.id], !allowsSharedReferences || existing != attachment {
                throw EventAttachmentError.invalidMetadata
            }
            metadata[attachment.id] = attachment
        }
    }
    return metadata
}
