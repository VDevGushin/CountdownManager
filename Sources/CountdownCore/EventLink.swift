import Foundation

/// A user-entered web address. Drafts may be incomplete; persistence validates the collection.
public struct EventLink: Identifiable, Codable, Equatable {
    public static let maximumCount = 10
    public let id: UUID
    public var name: String
    public var address: String

    public init(id: UUID = UUID(), name: String = "", address: String = "") {
        self.id = id
        self.name = name
        self.address = address
    }

    public var url: URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
              let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              let url = components.url else { return nil }
        return url
    }

    public var domain: String { url?.host ?? "" }
    public var displayName: String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? domain : cleaned
    }

    public func normalized() -> EventLink {
        EventLink(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                  address: address.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func validate(_ links: [EventLink]) throws {
        guard links.count <= maximumCount else { throw EventLinkError.limit }
        guard Set(links.map(\.id)).count == links.count else { throw EventLinkError.duplicateIdentity }
        guard links.allSatisfy({ $0.url != nil }) else { throw EventLinkError.address }
    }
}

public enum EventLinkError: LocalizedError {
    case limit, address, duplicateIdentity

    public var errorDescription: String? {
        switch self {
        case .limit: "У события может быть не больше десяти ссылок."
        case .address: "Укажите полный адрес с http:// или https:// без пробелов и данных входа."
        case .duplicateIdentity: "Список ссылок содержит повторяющиеся идентификаторы."
        }
    }
}
