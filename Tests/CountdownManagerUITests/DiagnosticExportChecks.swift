import CountdownCore
import CountdownManagerUI
import Foundation

private final class DiagnosticTestGate: @unchecked Sendable {
    private let lock = NSLock()
    private let releaseSignal = DispatchSemaphore(value: 0)
    private var entered = false
    private var waiter: CheckedContinuation<Void, Never>?

    func blockOnce() {
        lock.lock()
        guard !entered else { lock.unlock(); return }
        entered = true
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume()
        releaseSignal.wait()
    }

    func waitUntilEntered() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if entered { lock.unlock(); continuation.resume() }
            else { waiter = continuation; lock.unlock() }
        }
    }

    func release() { releaseSignal.signal() }
}

private final class DiagnosticTestRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String] = []
    func append(_ text: String) { lock.lock(); records.append(text); lock.unlock() }
    var lines: [String] { lock.lock(); defer { lock.unlock() }; return records }
}

private let exportSecrets = ["PRIVATE_USER", "PRIVATE_EVENT", "PRIVATE_BODY", "private.example", "55.75", "37.62", "PRIVATE_DOMAIN"]

private func diagnosticExportContext() -> DiagnosticExportContext {
    DiagnosticExportContext(timerPhase: .running, updaterAvailable: true, updaterCanCheck: false,
                            updaterInstalling: false, updaterDeferred: true, updaterPresenting: false,
                            weatherSnapshot: "result=no_usable_data enabled=true mode=manual demanded=2 usable=0 city=PRIVATE_USER latitude=55.75 longitude=37.62")
}

private func diagnosticStoreState() -> DiagnosticStoreState {
    DiagnosticStoreState(loading: false, readFailed: false, eventCount: 2, subtaskCount: 3,
                         pendingWrites: 1, recovering: false, revision: 5, durableRevision: 4)
}

private func exportFixtureDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("countdown-export-checks-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    return url
}

private func requireNoExportSecrets(_ text: String) {
    for secret in exportSecrets { precondition(!text.contains(secret), "Private fixture escaped diagnostic redaction") }
    precondition(!text.contains("/Users/") && !text.contains("https://") && !text.contains("file://"))
}

private func requireDiagnosticTemporaryCleanup(_ fixture: URL) throws {
    let names = try FileManager.default.contentsOfDirectory(atPath: fixture.path)
    precondition(names.allSatisfy { !$0.contains("countdown-diagnostics-") })
}

private func unpackDiagnosticArchive(_ archive: URL, into directory: URL) throws -> [String: String] {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
    process.arguments = ["-x", "-k", archive.path, directory.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    precondition(process.terminationStatus == 0)
    let payload = directory.appendingPathComponent("Countdown-Diagnostics", isDirectory: true)
    let names = try FileManager.default.contentsOfDirectory(atPath: payload.path)
    return try Dictionary(uniqueKeysWithValues: names.map { name in
        (name, try String(contentsOf: payload.appendingPathComponent(name), encoding: .utf8))
    })
}

func testDiagnosticArchiveExport() async throws {
    let fixture = try exportFixtureDirectory()
    defer { try? FileManager.default.removeItem(at: fixture) }
    let logDirectory = fixture.appendingPathComponent("Logs", isDirectory: true)
    try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: false)
    let legacy = """
    2026-10-16T09:00:00.000Z data.save failure error=Ошибка /Users/PRIVATE_USER/PRIVATE_EVENT https://private.example/55.75,37.62 PRIVATE_BODY
    2026-10-16T09:00:00.001Z data.save failure error=http code=123456789
    PRIVATE_BODY arbitrary continuation
    2026-10-16T09:00:00.002Z shell.lifecycle event=hide source=application-deactivation appActive=false visible=false key=false onActiveSpace=true occlusion=0 requested=false username=PRIVATE_USER
    2026-10-16T09:00:00.003Z weather.location result=requested prompt=false
    2026-10-16T09:00:00.004Z weather.location result=permission_required
    2026-10-16T09:00:00.005Z weather.location result=requested prompt=true
    2026-10-16T09:00:00.006Z weather.location result=denied
    2026-10-16T09:00:00.007Z weather.location result=unavailable
    2026-10-16T09:00:01.000Z weather.request.end source=wttr request=\(UUID().uuidString) duration_ms=12000 status=none bytes=unknown decode=skipped days=0 usable_days=0 error=url url_code=-1001 url_kind=timeout url=https://private.example body=PRIVATE_BODY
    """
    try Data(legacy.utf8).write(to: logDirectory.appendingPathComponent("countdown.log"))
    try Data("2026-10-15T09:00:00Z data.load failure error=/Users/PRIVATE_USER/PRIVATE_BODY".utf8)
        .write(to: logDirectory.appendingPathComponent("countdown.previous.log"))
    // Nearby application data and preferences are traps, never export inputs.
    try Data("PRIVATE_EVENT PRIVATE_BODY".utf8).write(to: logDirectory.appendingPathComponent("countdowns.json"))
    try Data("PRIVATE_USER PRIVATE_BODY".utf8).write(to: logDirectory.appendingPathComponent("preferences.plist"))
    let snapshot = try await DiagnosticLog(directoryURL: logDirectory).snapshot()
    let archive = fixture.appendingPathComponent("result.zip")
    try await DiagnosticArchiveExporter().export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                                destination: archive, temporaryRoot: fixture, version: "1.11.0", build: "20")
    let contents = try unpackDiagnosticArchive(archive, into: fixture.appendingPathComponent("unpacked"))
    precondition(Set(contents.keys) == ["summary.txt", "countdown.log", "countdown.previous.log"])
    let summary = contents["summary.txt"]!
    precondition(summary.contains("version=1.11.0 build=20") && summary.contains("architecture=") && summary.contains("utc_offset_seconds="))
    precondition(summary.contains("events=2 subtasks=3 pending_writes=1") && summary.contains("timer phase=running"))
    precondition(summary.contains("updater available=true can_check=false") && summary.contains("result=no_usable_data"))
    precondition(contents["countdown.log"]!.contains("url_code=-1001 url_kind=timeout"))
    precondition(contents["countdown.log"]!.contains("data.save failure"))
    precondition(!contents["countdown.log"]!.contains("123456789"), "Legacy error tails are private even when the first word resembles a technical category")
    precondition(contents["countdown.log"]!.contains("shell.lifecycle event=hide source=application-deactivation appActive=false visible=false key=false onActiveSpace=true occlusion=0 requested=false"))
    for fields in ["result=requested prompt=false", "result=permission_required", "result=requested prompt=true", "result=denied", "result=unavailable"] {
        precondition(contents["countdown.log"]!.contains("weather.location \(fields)"), "Archive must preserve the cause and permission policy of native AUTO failures")
    }
    requireNoExportSecrets(contents.values.joined(separator: "\n"))
    try requireDiagnosticTemporaryCleanup(fixture)

    try FileManager.default.removeItem(at: logDirectory.appendingPathComponent("countdown.previous.log"))
    let single = try await DiagnosticLog(directoryURL: logDirectory).snapshot()
    precondition(single.previous == nil)
    let singleArchive = fixture.appendingPathComponent("single.zip")
    try await DiagnosticArchiveExporter().export(snapshot: single, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                                destination: singleArchive, temporaryRoot: fixture, version: "/Users/PRIVATE_USER", build: "PRIVATE_BODY")
    let singleContents = try unpackDiagnosticArchive(singleArchive, into: fixture.appendingPathComponent("single-unpacked"))
    precondition(Set(singleContents.keys) == ["summary.txt", "countdown.log"])
    precondition(singleContents["summary.txt"]!.contains("version=unknown build=unknown"))
    requireNoExportSecrets(singleContents.values.joined(separator: "\n"))

    let error = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError,
                        userInfo: [NSLocalizedDescriptionKey: legacy, NSFilePathErrorKey: "/Users/PRIVATE_USER/PRIVATE_EVENT",
                                   NSUnderlyingErrorKey: NSError(domain: "PRIVATE_DOMAIN", code: 1)])
    let fields = DiagnosticPrivacy.errorFields(error)
    precondition(fields == "category=cocoa code=\(NSFileWriteNoPermissionError)")
    requireNoExportSecrets(fields)
    try await testDiagnosticExportFailures(fixture: fixture, snapshot: snapshot, error: error)
    try await testDiagnosticExportCancellation(fixture: fixture, snapshot: snapshot)
    try await testDiagnosticMainActorProgress(fixture: fixture)
    try await testDiagnosticLogBoundaries(fixture: fixture)
    try await testDiagnosticStoreErrorPrivacy(fixture: fixture, error: error)
}

private func testDiagnosticLogBoundaries(fixture: URL) async throws {
    let directory = fixture.appendingPathComponent("bounded-logs", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    let current = directory.appendingPathComponent("countdown.log")
    var oversized = Data(repeating: 65, count: 600_000)
    oversized.append(Data("\nweather.publication demanded=1 usable=0\n".utf8))
    try oversized.write(to: current)
    let bounded = try await DiagnosticLog(directoryURL: directory).snapshot()
    precondition(bounded.current!.count <= 512 * 1_024)
    precondition(String(decoding: bounded.current!, as: UTF8.self) == "weather.publication demanded=1 usable=0\n")
    try FileManager.default.removeItem(at: current)
    let privateFile = fixture.appendingPathComponent("private-file.json")
    try Data("PRIVATE_EVENT PRIVATE_BODY".utf8).write(to: privateFile)
    try FileManager.default.createSymbolicLink(at: current, withDestinationURL: privateFile)
    do {
        _ = try await DiagnosticLog(directoryURL: directory).snapshot()
        preconditionFailure("A log symlink must not copy arbitrary application files")
    } catch DiagnosticArchiveError.invalidLog {}
    try FileManager.default.removeItem(at: current)

    let first = DiagnosticLog(directoryURL: directory)
    first.record("data.load success items=1")
    first.record("data.save success revision=1 items=1")
    let firstSnapshot = try await first.snapshot()
    let firstText = String(decoding: firstSnapshot.current!, as: UTF8.self)
    let firstIDs = firstText.split(separator: "\n").map { String($0.split(separator: " ").last!) }
    precondition(firstIDs.count == 2 && firstIDs[0] == firstIDs[1])
    precondition(UUID(uuidString: String(firstIDs[0].dropFirst("session=".count))) != nil)
    let second = DiagnosticLog(directoryURL: directory)
    second.record("data.load success items=1")
    let secondSnapshot = try await second.snapshot()
    let last = String(decoding: secondSnapshot.current!, as: UTF8.self).split(separator: "\n").last!
    precondition(String(last.split(separator: " ").last!) != firstIDs[0], "Separate application logger lifetimes need distinct session IDs")
    precondition(DiagnosticPrivacy.redactedLog(secondSnapshot.current!).range(of: Data(firstIDs[0].utf8)) != nil)
}

private func testDiagnosticExportFailures(fixture: URL, snapshot: DiagnosticLogSnapshot, error: NSError) async throws {
    let destination = fixture.appendingPathComponent("existing.zip")
    let original = Data("previous diagnostic archive".utf8)
    try original.write(to: destination)
    let exporter = DiagnosticArchiveExporter { _, _ in throw error }
    do {
        try await exporter.export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                  destination: destination, temporaryRoot: fixture)
        preconditionFailure("Archive failure must surface")
    } catch {
        let retained = try Data(contentsOf: destination)
        precondition(retained == original)
    }
    let cancelled = try await exporter.export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                              destination: nil, temporaryRoot: fixture)
    let afterCancel = try Data(contentsOf: destination)
    precondition(!cancelled && afterCancel == original)
    let directoryDestination = fixture.appendingPathComponent("existing-directory.zip", isDirectory: true)
    try FileManager.default.createDirectory(at: directoryDestination, withIntermediateDirectories: false)
    let retained = directoryDestination.appendingPathComponent("existing.txt")
    try original.write(to: retained)
    do {
        try await DiagnosticArchiveExporter().export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                                    destination: directoryDestination, temporaryRoot: fixture)
        preconditionFailure("Cannot replace a directory with a ZIP file")
    } catch {
        let data = try Data(contentsOf: retained)
        precondition(data == original)
    }
    try requireDiagnosticTemporaryCleanup(fixture)
}

@MainActor
private func testDiagnosticExportCancellation(fixture: URL, snapshot: DiagnosticLogSnapshot) async throws {
    let destination = fixture.appendingPathComponent("cancelled.zip")
    let original = Data("preserved original".utf8)
    try original.write(to: destination)
    let gate = DiagnosticTestGate()
    let exporter = DiagnosticArchiveExporter { payload, output in
        gate.blockOnce()
        try DiagnosticArchiveExporter.makeZIP(payload, output)
    }
    let task = Task {
        try await exporter.export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                  destination: destination, temporaryRoot: fixture)
    }
    await gate.waitUntilEntered()
    task.cancel()
    gate.release()
    do { _ = try await task.value; preconditionFailure("Cancelled export must not commit") }
    catch is CancellationError {}
    let retained = try Data(contentsOf: destination)
    precondition(retained == original)
    try requireDiagnosticTemporaryCleanup(fixture)
}

@MainActor
private func testDiagnosticMainActorProgress(fixture: URL) async throws {
    let writerGate = DiagnosticTestGate()
    let log = DiagnosticLog(directoryURL: fixture.appendingPathComponent("slow-logs"), beforeWrite: { writerGate.blockOnce() })
    log.record("data.load success items=1")
    await writerGate.waitUntilEntered()
    // All producers return while the writer is blocked. The finite admission budget discards the tail.
    for _ in 0..<600 { log.record("timer.start minutes=5") }
    var writerProgress = false
    Task { @MainActor in writerProgress = true; writerGate.release() }
    let snapshot = try await log.snapshot()
    precondition(writerProgress)
    let lines = String(decoding: snapshot.current!, as: UTF8.self).split(separator: "\n")
    precondition(lines.count <= 513 && lines.contains { $0.contains("diagnostics.dropped count=89") })

    let archiveGate = DiagnosticTestGate()
    let exporter = DiagnosticArchiveExporter { payload, output in
        archiveGate.blockOnce()
        try DiagnosticArchiveExporter.makeZIP(payload, output)
    }
    let task = Task {
        try await exporter.export(snapshot: snapshot, context: diagnosticExportContext(), store: diagnosticStoreState(),
                                  destination: fixture.appendingPathComponent("slow.zip"), temporaryRoot: fixture)
    }
    await archiveGate.waitUntilEntered()
    var archiveProgress = false
    Task { @MainActor in archiveProgress = true; archiveGate.release() }
    _ = try await task.value
    precondition(archiveProgress, "Archive work must leave MainActor available")
}

@MainActor
private func testDiagnosticStoreErrorPrivacy(fixture: URL, error: NSError) async throws {
    let suite = "local.countdownmanager.export-store-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = DiagnosticTestRecords()
    let store = Store(fileURL: fixture.appendingPathComponent("isolated-events.json"), disclosureDefaults: defaults,
                      persistenceSaveOverride: { _, _ in throw error }, loginItemManagementIsAvailable: false,
                      diagnosticRecord: { records.append($0) })
    for _ in 0..<1_000 { if !store.isLoading { break }; await Task.yield() }
    precondition(!store.isLoading)
    let event = Countdown(title: "PRIVATE_EVENT", date: Day(Date()), emoji: "")
    let saved = await store.save(event, primary: false)
    precondition(!saved)
    let lines = records.lines
    precondition(lines.contains { $0.hasPrefix("data.save failure category=cocoa code=") })
    requireNoExportSecrets(lines.joined(separator: "\n"))
}
