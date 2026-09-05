import AppKit
import Combine
import CountdownCore
import ServiceManagement

@MainActor
final class Store: ObservableObject {
    @Published private(set) var data = CountdownData()
    @Published private(set) var today = Day(Date())
    @Published private(set) var isLoading = true
    @Published var error: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    private let fileURL: URL
    private let repository: CountdownRepository
    private var readFailed = false
    private var revision = 0
    private var subscriptions = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    init(fileURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedURL = fileURL ?? support.appendingPathComponent("CountdownManager/countdowns.json")
        self.fileURL = resolvedURL
        repository = CountdownRepository(fileURL: resolvedURL)
        Task { await load() }
        rescheduleMidnightTimer()
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        for name in [NSApplication.didBecomeActiveNotification, NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSSystemTimeZoneDidChange, NSNotification.Name.NSCalendarDayChanged] {
            NotificationCenter.default.publisher(for: name)
                .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
        }
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }.store(in: &subscriptions)
    }

    private func load() async {
        do {
            data = try await repository.load()
            isLoading = false
            DiagnosticLog.shared.record("data.load success items=\(data.items.count)")
            refresh()
        } catch {
            readFailed = true
            isLoading = false
            DiagnosticLog.shared.record("data.load failure error=\(error.localizedDescription)")
            self.error = "Не удалось прочитать сохранённые счётчики. Файл оставлен без изменений: \(fileURL.path)\n\(error.localizedDescription)"
        }
    }

    var active: [Countdown] {
        data.items.filter { $0.date > today }.sorted {
            if ($0.id == data.primaryID) != ($1.id == data.primaryID) { return $0.id == data.primaryID }
            return $0.date == $1.date ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : $0.date < $1.date
        }
    }
    var primary: Countdown? { active.first { $0.id == data.primaryID } ?? active.first }
    var statusTitle: String { primary.map { "\($0.emoji) \(dayLabel($0.date.days(from: today)))" } ?? "◷ Countdown" }
    var tomorrow: Date { Day.calendar.date(byAdding: .day, value: 1, to: today.date())! }

    func refresh() {
        let currentDay = Day(Date())
        if currentDay != today { today = currentDay }
        if !isLoading && !readFailed {
            var updated = data
            updated.normalize(today: today)
            if updated != data {
                DiagnosticLog.shared.record("data.normalize removed=\(data.items.count - updated.items.count)")
                stagePersistence(updated, reason: "normalize")
            }
        }
        let currentLoginStatus = SMAppService.mainApp.status
        if currentLoginStatus != loginStatus { loginStatus = currentLoginStatus }
        rescheduleMidnightTimer()
    }

    private func rescheduleMidnightTimer() {
        midnightTimer?.invalidate()
        midnightTimer = Timer(fire: tomorrow, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let midnightTimer { RunLoop.main.add(midnightTimer, forMode: .common) }
    }

    private func stagePersistence(_ updated: CountdownData, reason: String) {
        let previous = data
        revision += 1
        let writeRevision = revision
        data = updated
        Task { [weak self] in
            _ = await self?.finishPersistence(
                updated,
                previous: previous,
                revision: writeRevision,
                reason: reason
            )
        }
    }

    private func commit(_ updated: CountdownData, reason: String) async -> Bool {
        guard !isLoading, !readFailed else {
            error = "Сохранение недоступно: сначала восстановите файл \(fileURL.path) и перезапустите приложение."
            return false
        }
        if updated == data { return true }
        let previous = data
        revision += 1
        let writeRevision = revision
        data = updated
        return await finishPersistence(
            updated,
            previous: previous,
            revision: writeRevision,
            reason: reason
        )
    }

    private func finishPersistence(
        _ updated: CountdownData,
        previous: CountdownData,
        revision writeRevision: Int,
        reason: String
    ) async -> Bool {
        do {
            let didWrite = try await repository.save(updated, revision: writeRevision)
            DiagnosticLog.shared.record(
                didWrite
                    ? "data.save success reason=\(reason) revision=\(writeRevision) items=\(updated.items.count) primary=\(updated.primaryID?.uuidString ?? "none")"
                    : "data.save superseded reason=\(reason) revision=\(writeRevision)"
            )
            return true
        } catch {
            if revision == writeRevision { data = previous }
            DiagnosticLog.shared.record("data.save failure error=\(error.localizedDescription)")
            self.error = "Не удалось сохранить изменения: \(error.localizedDescription)"
            return false
        }
    }

    func save(_ countdown: Countdown, primary: Bool) async -> Bool {
        DiagnosticLog.shared.record("countdown.save begin id=\(countdown.id.uuidString) primary=\(primary)")
        let currentDay = Day(Date())
        if currentDay != today { today = currentDay }
        var updated = data
        do { try updated.save(countdown, primary: primary, today: today) }
        catch {
            DiagnosticLog.shared.record("countdown.save rejected id=\(countdown.id.uuidString) error=\(error.localizedDescription)")
            self.error = error.localizedDescription
            return false
        }
        return await commit(updated, reason: "countdown.save")
    }

    func makePrimary(_ id: UUID) async {
        let currentDay = Day(Date())
        if currentDay != today { today = currentDay }
        var updated = data
        updated.normalize(today: today)
        guard updated.items.contains(where: { $0.id == id }) else { return }
        DiagnosticLog.shared.record("countdown.primary id=\(id.uuidString)")
        updated.primaryID = id
        _ = await commit(updated, reason: "countdown.primary")
    }

    func delete(_ id: UUID) async {
        DiagnosticLog.shared.record("countdown.delete id=\(id.uuidString)")
        var updated = data
        updated.delete(id, today: Day(Date()))
        _ = await commit(updated, reason: "countdown.delete")
    }

    func setLogin(_ enabled: Bool) {
        DiagnosticLog.shared.record("login-item.change requested=\(enabled)")
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            DiagnosticLog.shared.record("login-item.change failure error=\(error.localizedDescription)")
            self.error = "Не удалось изменить автозапуск: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
        DiagnosticLog.shared.record("login-item.status value=\(loginStatus.rawValue)")
    }

    func restart() {
        DiagnosticLog.shared.record("app.restart requested")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Positional arguments preserve spaces and shell metacharacters in the app path.
        process.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open -n \"$2\"", "restart", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        do { try process.run(); NSApp.terminate(nil) }
        catch {
            DiagnosticLog.shared.record("app.restart failure error=\(error.localizedDescription)")
            self.error = "Не удалось перезапустить приложение: \(error.localizedDescription)"
        }
    }

    func openDiagnostics() {
        DiagnosticLog.shared.record("diagnostics.open-folder")
        do {
            try FileManager.default.createDirectory(
                at: DiagnosticLog.directoryURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.activateFileViewerSelecting([DiagnosticLog.fileURL])
        } catch {
            DiagnosticLog.shared.record("diagnostics.open-folder failure error=\(error.localizedDescription)")
            self.error = "Не удалось открыть папку диагностики: \(error.localizedDescription)"
        }
    }
}
