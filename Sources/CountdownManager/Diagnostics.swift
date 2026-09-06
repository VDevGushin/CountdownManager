import Foundation
import OSLog

/// A small, dependency-free diagnostic journal that survives app restarts.
/// User-entered titles and emoji are deliberately not recorded.
final class DiagnosticLog: @unchecked Sendable {
    static let shared = DiagnosticLog()

    static var directoryURL: URL {
        if UISmokeConfiguration.wasRequested,
           let testHome = ProcessInfo.processInfo.environment["COUNTDOWN_MANAGER_TEST_HOME"] {
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

    private init() {
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func record(_ message: String) {
        systemLog.info("\(message, privacy: .public)")
        queue.async { [self] in
            let line = "\(formatter.string(from: Date())) \(message)\n"
            do {
                try FileManager.default.createDirectory(
                    at: Self.directoryURL,
                    withIntermediateDirectories: true
                )
                try rotateIfNeeded(adding: line.utf8.count)
                if !FileManager.default.fileExists(atPath: Self.fileURL.path) {
                    FileManager.default.createFile(atPath: Self.fileURL.path, contents: nil)
                }
                let handle = try FileHandle(forWritingTo: Self.fileURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
                try handle.close()
            } catch {
                systemLog.error("Cannot write diagnostic log: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Waits until all already-enqueued records have reached disk.
    func flush() {
        queue.sync {}
    }

    private func rotateIfNeeded(adding bytes: Int) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: Self.fileURL.path)
        let currentSize = attributes?[.size] as? Int ?? 0
        guard currentSize + bytes > maximumFileSize else { return }

        let archiveURL = Self.directoryURL.appendingPathComponent("countdown.previous.log")
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            try FileManager.default.removeItem(at: archiveURL)
        }
        if FileManager.default.fileExists(atPath: Self.fileURL.path) {
            try FileManager.default.moveItem(at: Self.fileURL, to: archiveURL)
        }
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
        queue.sync { [self] in
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
