import Darwin
import Foundation

package struct DiagnosticLogSnapshot: Sendable {
    package let current: Data?
    package let previous: Data?

    package init(current: Data?, previous: Data?) {
        self.current = current
        self.previous = previous
    }
}

package enum DiagnosticTimerPhase: String, Sendable { case idle, running, finished }

package struct DiagnosticExportContext: Sendable {
    let timerPhase: DiagnosticTimerPhase
    let updaterAvailable: Bool
    let updaterCanCheck: Bool
    let updaterInstalling: Bool
    let updaterDeferred: Bool
    let updaterPresenting: Bool
    let weatherSnapshot: String

    package init(
        timerPhase: DiagnosticTimerPhase, updaterAvailable: Bool, updaterCanCheck: Bool,
        updaterInstalling: Bool, updaterDeferred: Bool, updaterPresenting: Bool, weatherSnapshot: String
    ) {
        self.timerPhase = timerPhase
        self.updaterAvailable = updaterAvailable
        self.updaterCanCheck = updaterCanCheck
        self.updaterInstalling = updaterInstalling
        self.updaterDeferred = updaterDeferred
        self.updaterPresenting = updaterPresenting
        self.weatherSnapshot = String(weatherSnapshot.prefix(4_096))
    }
}

package struct DiagnosticStoreState: Sendable {
    package let loading: Bool
    package let readFailed: Bool
    package let eventCount: Int
    package let subtaskCount: Int
    package let pendingWrites: Int
    package let recovering: Bool
    package let revision: Int
    package let durableRevision: Int

    package init(loading: Bool, readFailed: Bool, eventCount: Int, subtaskCount: Int,
                 pendingWrites: Int, recovering: Bool, revision: Int, durableRevision: Int) {
        self.loading = loading
        self.readFailed = readFailed
        self.eventCount = eventCount
        self.subtaskCount = subtaskCount
        self.pendingWrites = pendingWrites
        self.recovering = recovering
        self.revision = revision
        self.durableRevision = durableRevision
    }
}

package enum DiagnosticArchiveError: Error { case invalidLog, archiveFailed, archiveTooLarge, commitFailed }

private final class DiagnosticExportCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func check() throws {
        lock.lock()
        defer { lock.unlock() }
        if cancelled { throw CancellationError() }
    }
}

/// One explicit export owns bounded temporary files. No filesystem or process work runs on the UI actor.
package struct DiagnosticArchiveExporter: Sendable {
    private static let queue = DispatchQueue(label: "local.countdownmanager.diagnostic-export", qos: .utility)
    private let makeArchive: @Sendable (URL, URL) throws -> Void

    package init(makeArchive: @escaping @Sendable (URL, URL) throws -> Void = { try DiagnosticArchiveExporter.makeZIP($0, $1) }) {
        self.makeArchive = makeArchive
    }

    @discardableResult
    package func export(
        snapshot: DiagnosticLogSnapshot, context: DiagnosticExportContext, store: DiagnosticStoreState,
        destination: URL?, temporaryRoot: URL = FileManager.default.temporaryDirectory,
        version: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
        build: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
        now: Date = Date()
    ) async throws -> Bool {
        guard let destination else { return false }
        let cancellation = DiagnosticExportCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Self.queue.async {
                    do {
                        try cancellation.check()
                        try write(snapshot: snapshot, context: context, store: store, destination: destination,
                                  temporaryRoot: temporaryRoot, version: version, build: build, now: now, cancellation: cancellation)
                        continuation.resume(returning: true)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }

    private func write(
        snapshot: DiagnosticLogSnapshot, context: DiagnosticExportContext, store: DiagnosticStoreState,
        destination: URL, temporaryRoot: URL, version: String?, build: String?, now: Date,
        cancellation: DiagnosticExportCancellation
    ) throws {
        let manager = FileManager.default
        let work = temporaryRoot.appendingPathComponent("countdown-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: work, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: work) }
        let payload = work.appendingPathComponent("Countdown-Diagnostics", isDirectory: true)
        try manager.createDirectory(at: payload, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try DiagnosticPrivacy.redactedLog(snapshot.current ?? Data()).write(to: payload.appendingPathComponent("countdown.log"))
        if let previous = snapshot.previous {
            try DiagnosticPrivacy.redactedLog(previous).write(to: payload.appendingPathComponent("countdown.previous.log"))
        }
        let summary = Self.summary(context: context, store: store, version: version, build: build, now: now)
        try Data(summary.utf8).write(to: payload.appendingPathComponent("summary.txt"))
        try cancellation.check()
        let archive = work.appendingPathComponent("diagnostics.zip")
        try makeArchive(payload, archive)
        try cancellation.check()
        let handle = try FileHandle(forReadingFrom: archive)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: 2 * 1_024 * 1_024 + 1) ?? Data()
        guard data.count <= 2 * 1_024 * 1_024, data.starts(with: [0x50, 0x4b, 0x03, 0x04]) else {
            throw DiagnosticArchiveError.archiveTooLarge
        }
        // A sibling staging file plus rename keeps a previously saved archive intact on every pre-commit failure.
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".countdown-diagnostics-\(UUID().uuidString).tmp")
        guard manager.createFile(atPath: staged.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw DiagnosticArchiveError.commitFailed
        }
        defer { try? manager.removeItem(at: staged) }
        let output = try FileHandle(forWritingTo: staged)
        do { try output.write(contentsOf: data); try output.close() }
        catch { try? output.close(); throw error }
        try cancellation.check()
        guard rename(staged.path, destination.path) == 0 else { throw DiagnosticArchiveError.commitFailed }
    }

    private static func summary(
        context: DiagnosticExportContext, store: DiagnosticStoreState, version: String?, build: String?, now: Date
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "other"
        #endif
        let weather = DiagnosticPrivacy.redactedLine("weather.snapshot \(context.weatherSnapshot)")
        return """
        Countdown Manager diagnostics
        app version=\(DiagnosticPrivacy.version(version)) build=\(DiagnosticPrivacy.version(build))
        system macOS=\(system.majorVersion).\(system.minorVersion).\(system.patchVersion) architecture=\(architecture)
        time utc=\(formatter.string(from: now)) utc_offset_seconds=\(TimeZone.current.secondsFromGMT(for: now))
        store loading=\(store.loading) read_failed=\(store.readFailed) events=\(store.eventCount) subtasks=\(store.subtaskCount) pending_writes=\(store.pendingWrites) recovering=\(store.recovering) revision=\(store.revision) durable_revision=\(store.durableRevision)
        timer phase=\(context.timerPhase.rawValue)
        updater available=\(context.updaterAvailable) can_check=\(context.updaterCanCheck) installing=\(context.updaterInstalling) deferred=\(context.updaterDeferred) presenting=\(context.updaterPresenting)
        \(weather)
        Privacy: only technical fields are included. Legacy free-form text is omitted. No event file or settings dump is attached.

        """
    }

    package static func makeZIP(_ directory: URL, _ output: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl", "--keepParent", directory.path, output.path]
        process.environment = ["PATH": "/usr/bin:/bin", "COPYFILE_DISABLE": "1"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        guard finished.wait(timeout: .now() + 20) == .success else {
            process.terminate()
            if finished.wait(timeout: .now() + 1) != .success {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            throw DiagnosticArchiveError.archiveFailed
        }
        guard process.terminationStatus == 0 else { throw DiagnosticArchiveError.archiveFailed }
    }
}
