import Foundation

/// Serializes all reads and writes so disk access never has to run on the UI actor.
public actor CountdownRepository {
    private let fileURL: URL
    private var highestWrittenRevision = 0

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> CountdownData {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return CountdownData()
        }
        return try JSONDecoder().decode(CountdownData.self, from: Data(contentsOf: fileURL))
    }

    /// Returns false when a newer snapshot has already reached disk.
    @discardableResult
    public func save(_ data: CountdownData, revision: Int) throws -> Bool {
        guard revision >= highestWrittenRevision else { return false }
        try data.validateSubtasksForPersistence()
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(data).write(to: fileURL, options: .atomic)
        highestWrittenRevision = revision
        return true
    }
}
