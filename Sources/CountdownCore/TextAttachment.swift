import Foundation

/// Plain UTF-8 text is stored by the repository like any other owned attachment.
public struct TextAttachment: Equatable {
    public var name: String
    public var text: String

    public init(name: String? = nil, text: String) {
        self.name = name ?? Self.suggestedName(for: text)
        self.text = text
    }

    public static func suggestedName(for text: String) -> String {
        let first = text.split(whereSeparator: \.isNewline).first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }).map(String.init) ?? "Текст"
        let clean = first.components(separatedBy: CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/\\:"))).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String((clean.isEmpty ? "Текст" : clean).prefix(50)) + ".txt"
    }

    public var filename: String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.lowercased().hasSuffix(".txt") ? clean : clean + ".txt"
    }

    public func validate() throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TextAttachmentError.emptyText
        }
        guard !clean.isEmpty, clean != ".", clean != "..",
              !clean.contains(":"), !clean.contains("/"), !clean.contains("\\"),
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw TextAttachmentError.invalidName
        }
        guard filename.utf8.count <= 240 else { throw TextAttachmentError.longName }
        _ = try EventAttachment(name: filename, byteCount: Int64(text.utf8.count))
    }
}

public enum TextAttachmentError: LocalizedError {
    case emptyText, invalidName, longName
    public var errorDescription: String? {
        switch self {
        case .emptyText: "Вставьте или введите текст вложения."
        case .invalidName: "Укажите имя файла без слешей, двоеточия и управляющих символов."
        case .longName: "Имя файла слишком длинное. Сократите его."
        }
    }
}
