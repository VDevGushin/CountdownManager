import Foundation
import OSLog

/// A small, dependency-free diagnostic journal that survives app restarts.
/// User-entered titles and emoji are deliberately not recorded.
package final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    static var directoryURL: URL {
        if UISmokeConfiguration.requiresIsolatedTestHome,
           let testHome = UISmokeConfiguration.requestedTestHome {
            return URL(fileURLWithPath: testHome, isDirectory: true)
                .appendingPathComponent("Application Support/CountdownManager/Logs", isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CountdownManager/Logs", isDirectory: true)
    }

    static var fileURL: URL { directoryURL.appendingPathComponent("countdown.log") }

    private let systemLog = Logger(subsystem: "local.countdownmanager.app", category: "diagnostics")
    private let queue = DispatchQueue(label: "local.countdownmanager.diagnostics", qos: .utility)
    private let formatter = ISO8601DateFormatter()
    private let maximumFileSize = 512 * 1024
    private let sessionID = UUID().uuidString
    private let admission = DiagnosticLogAdmission()
    private let overrideDirectory: URL?
    private let writesSystemLog: Bool
    private let beforeWrite: @Sendable () -> Void
    private var storageDirectory: URL { overrideDirectory ?? Self.directoryURL }
    private var storageFile: URL { storageDirectory.appendingPathComponent("countdown.log") }

    private init() {
        overrideDirectory = nil
        writesSystemLog = true
        beforeWrite = {}
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    package init(directoryURL: URL, beforeWrite: @escaping @Sendable () -> Void = {}) {
        overrideDirectory = directoryURL
        writesSystemLog = false
        self.beforeWrite = beforeWrite
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    package func record(_ message: String) {
        guard admission.accept() else { return }
        let bounded = String(decoding: message.utf8.prefix(4_096), as: UTF8.self)
        queue.async { [self] in
            beforeWrite()
            write(bounded)
            let dropped = admission.finish()
            if dropped > 0 { write("diagnostics.dropped count=\(dropped)") }
        }
    }

    private func write(_ message: String) {
        if writesSystemLog { systemLog.info("\(message, privacy: .public)") }
        let line = "\(formatter.string(from: Date())) \(message) session=\(sessionID)\n"
        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try rotateIfNeeded(adding: line.utf8.count)
            if !FileManager.default.fileExists(atPath: storageFile.path) {
                FileManager.default.createFile(atPath: storageFile.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: storageFile)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
            try handle.close()
        } catch {
            if writesSystemLog {
                let fields = DiagnosticPrivacy.errorFields(error)
                systemLog.error("diagnostics.write failure \(fields, privacy: .public)")
            }
        }
    }

    /// Isolated runtime-test helper only. Production UI paths use asynchronous queue operations.
    func flush() {
        queue.sync {}
    }

    func flushAsync() async {
        await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
    }

    func directoryForViewing() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true,
                                                            attributes: [.posixPermissions: 0o700])
                    continuation.resume(returning: FileManager.default.fileExists(atPath: storageFile.path) ? storageFile : storageDirectory)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// A single queue operation reads both generations, ordered after all admitted writes.
    package func snapshot() async throws -> DiagnosticLogSnapshot {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    continuation.resume(returning: try DiagnosticLogSnapshot(
                        current: readBounded(storageFile),
                        previous: readBounded(storageDirectory.appendingPathComponent("countdown.previous.log"))
                    ))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func readBounded(_ url: URL) throws -> Data? {
        let values: URLResourceValues
        do { values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) }
        catch {
            let native = error as NSError
            if native.domain == NSCocoaErrorDomain, [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(native.code) { return nil }
            throw error
        }
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiagnosticArchiveError.invalidLog }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        let offset = size > maximumFileSize ? size - UInt64(maximumFileSize) : 0
        try handle.seek(toOffset: offset)
        var data = try handle.read(upToCount: maximumFileSize) ?? Data()
        if offset > 0 {
            if let newline = data.firstIndex(of: 10) { data = Data(data.suffix(from: data.index(after: newline))) }
            else { data = Data() }
        }
        return data
    }

    private func rotateIfNeeded(adding bytes: Int) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: storageFile.path)
        let currentSize = attributes?[.size] as? Int ?? 0
        guard currentSize + bytes > maximumFileSize else { return }

        let archiveURL = storageDirectory.appendingPathComponent("countdown.previous.log")
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }
        if FileManager.default.fileExists(atPath: storageFile.path) {
            try FileManager.default.moveItem(at: storageFile, to: archiveURL)
        }
    }
}

private final class DiagnosticLogAdmission: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = 0
    private var dropped = 0

    func accept() -> Bool {
        // UI callers never wait for the writer, or even for another admission operation.
        guard lock.try() else { return false }
        defer { lock.unlock() }
        guard pending < 512 else { dropped = min(dropped + 1, Int.max / 2); return false }
        pending += 1
        return true
    }

    func finish() -> Int {
        lock.lock()
        defer { lock.unlock() }
        pending -= 1
        let count = dropped
        dropped = 0
        return count
    }
}

/// Records a breadcrumb when the AppKit main thread stops processing events.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let queue = DispatchQueue(label: "local.countdownmanager.watchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var awaitingSince: TimeInterval?
    private var stallReported = false
    private let stallThreshold: TimeInterval = 5

    private init() {}

    func start() {
        queue.async { [self] in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(250))
            source.setEventHandler { [weak self] in self?.checkMainThread() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            awaitingSince = nil
            stallReported = false
        }
    }

    private func checkMainThread() {
        let now = ProcessInfo.processInfo.systemUptime
        if let awaitingSince {
            let duration = now - awaitingSince
            if duration >= stallThreshold && !stallReported {
                stallReported = true
                DiagnosticLog.shared.record("ui.stall detected duration=\(Int(duration.rounded()))s")
            }
            return
        }

        awaitingSince = now
        DispatchQueue.main.async { [weak self] in self?.acknowledgeMainThread() }
    }

    private func acknowledgeMainThread() {
        let now = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            guard let awaitingSince else { return }
            let duration = now - awaitingSince
            if stallReported {
                DiagnosticLog.shared.record("ui.stall recovered duration=\(Int(duration.rounded()))s")
            }
            self.awaitingSince = nil
            stallReported = false
        }
    }
}
