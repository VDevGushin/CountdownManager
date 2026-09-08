import AppKit
import Combine
import CountdownCore
import ServiceManagement

@MainActor
package final class SubtaskDisclosureState: ObservableObject {
    @Published package private(set) var isExpanded: Bool

    private let eventID: UUID
    private let persistence: SubtaskDisclosurePersistence

    package init(eventID: UUID, persistence: SubtaskDisclosurePersistence) {
        self.eventID = eventID
        self.persistence = persistence
        isExpanded = persistence.isExpanded(eventID: eventID)
    }

    package func setExpanded(_ newValue: Bool) {
        guard newValue != isExpanded else { return }
        DiagnosticLog.shared.record("subtask.disclosure begin id=\(eventID.uuidString) expanded=\(newValue)")
        persistence.setExpanded(newValue, eventID: eventID)
        isExpanded = newValue
        DiagnosticLog.shared.record("subtask.disclosure success id=\(eventID.uuidString) expanded=\(newValue)")
    }
}

@MainActor
package final class SubtaskDisclosureCache {
    private let persistence: SubtaskDisclosurePersistence
    private var states: [UUID: SubtaskDisclosureState] = [:]

    package init(persistence: SubtaskDisclosurePersistence) {
        self.persistence = persistence
    }

    package func state(for eventID: UUID) -> SubtaskDisclosureState {
        if let state = states[eventID] { return state }
        let state = SubtaskDisclosureState(eventID: eventID, persistence: persistence)
        states[eventID] = state
        return state
    }

    package func remove(eventID: UUID) {
        persistence.remove(eventID: eventID)
        states.removeValue(forKey: eventID)
    }

    package var cachedEventIDs: Set<UUID> { Set(states.keys) }
}

@MainActor
package final class Store: ObservableObject {
    @Published package private(set) var data = CountdownData()
    @Published private(set) var today = Day(Date())
    @Published package private(set) var isLoading = true
    @Published var error: String?
    @Published private(set) var loginStatus = SMAppService.mainApp.status
    private let fileURL: URL
    private let repository: CountdownRepository
    private let persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)?
    private let disclosureCache: SubtaskDisclosureCache
    private var readFailed = false
    private var revision = 0
    private var durableRevision = 0
    private var durableData = CountdownData()
    private var inFlightPersistenceRevisions: Set<Int> = []
    private var subscriptions = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    package init(
        fileURL: URL? = nil,
        disclosureDefaults: UserDefaults = .standard,
        persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)? = nil
    ) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedURL = fileURL ?? support.appendingPathComponent("CountdownManager/countdowns.json")
        self.fileURL = resolvedURL
        repository = CountdownRepository(fileURL: resolvedURL)
        self.persistenceSaveOverride = persistenceSaveOverride
        disclosureCache = SubtaskDisclosureCache(
            persistence: SubtaskDisclosurePersistence(defaults: disclosureDefaults)
        )
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
            let loaded = try await repository.load()
            data = loaded
            durableData = loaded
            isLoading = false
            DiagnosticLog.shared.record("data.load success items=\(data.items.count)")
            refresh()
        } catch {
            readFailed = true
            isLoading = false
            DiagnosticLog.shared.record("data.load failure error=\(error.localizedDescription)")
            self.error = "Не удалось прочитать сохранённые события. Файл оставлен без изменений: \(fileURL.path)\n\(error.localizedDescription)"
        }
    }

    var active: [Countdown] {
        activeCountdowns(in: data, today: today)
    }
    var primary: Countdown? { active.first { $0.id == data.primaryID } ?? active.first }
    var statusTitle: String { statusBarTitle(data: data, today: today) }
    var tomorrow: Date { Day.calendar.date(byAdding: .day, value: 1, to: today.date())! }

    func subtasksAreExpanded(for eventID: UUID) -> Bool {
        disclosureState(for: eventID).isExpanded
    }

    func disclosureState(for eventID: UUID) -> SubtaskDisclosureState {
        disclosureCache.state(for: eventID)
    }

    func setSubtasksExpanded(_ isExpanded: Bool, for eventID: UUID) {
        disclosureState(for: eventID).setExpanded(isExpanded)
    }

    func refresh() {
        let currentDay = Day(Date())
        if currentDay != today { today = currentDay }
        if !isLoading && !readFailed {
            var updated = data
            updated.normalize(today: today)
            if updated != data {
                let removedEventIDs = Set(data.items.map(\.id)).subtracting(updated.items.map(\.id))
                DiagnosticLog.shared.record("data.normalize removed=\(data.items.count - updated.items.count)")
                stagePersistence(
                    updated,
                    reason: "normalize",
                    disclosureCleanup: removedEventIDs
                )
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

    private func stagePersistence(
        _ updated: CountdownData,
        reason: String,
        disclosureCleanup: Set<UUID> = []
    ) {
        revision += 1
        let writeRevision = revision
        inFlightPersistenceRevisions.insert(writeRevision)
        data = updated
        Task { [weak self] in
            let didSave = await self?.finishPersistence(
                updated,
                revision: writeRevision,
                reason: reason
            )
            if didSave == true {
                disclosureCleanup.forEach { self?.disclosureCache.remove(eventID: $0) }
            }
        }
    }

    private func commit(_ updated: CountdownData, reason: String) async -> Bool {
        guard !isLoading, !readFailed else {
            error = "Сохранение недоступно: сначала восстановите файл \(fileURL.path) и перезапустите приложение."
            return false
        }
        if updated == data { return true }
        revision += 1
        let writeRevision = revision
        inFlightPersistenceRevisions.insert(writeRevision)
        data = updated
        return await finishPersistence(
            updated,
            revision: writeRevision,
            reason: reason
        )
    }

    private func finishPersistence(
        _ updated: CountdownData,
        revision writeRevision: Int,
        reason: String
    ) async -> Bool {
        do {
            let didWrite: Bool
            if let persistenceSaveOverride {
                didWrite = try await persistenceSaveOverride(updated, writeRevision)
            } else {
                didWrite = try await repository.save(updated, revision: writeRevision)
            }
            if didWrite, writeRevision >= durableRevision {
                durableRevision = writeRevision
                durableData = updated
            }
            finishPersistenceRevision(writeRevision)
            DiagnosticLog.shared.record(
                didWrite
                    ? "data.save success reason=\(reason) revision=\(writeRevision) items=\(updated.items.count) primary=\(updated.primaryID?.uuidString ?? "none")"
                    : "data.save superseded reason=\(reason) revision=\(writeRevision)"
            )
            return true
        } catch {
            finishPersistenceRevision(writeRevision)
            DiagnosticLog.shared.record("data.save failure error=\(error.localizedDescription)")
            self.error = "Не удалось сохранить изменения: \(error.localizedDescription)"
            return false
        }
    }

    private func finishPersistenceRevision(_ writeRevision: Int) {
        inFlightPersistenceRevisions.remove(writeRevision)
        if inFlightPersistenceRevisions.isEmpty {
            data = durableData
        }
    }

    package func save(_ countdown: Countdown, primary: Bool) async -> Bool {
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
        let didSave = await commit(updated, reason: "countdown.save")
        if didSave, countdown.subtasks.isEmpty {
            disclosureCache.remove(eventID: countdown.id)
        }
        return didSave
    }

    func addSubtask(to eventID: UUID, text: String) async -> Bool {
        DiagnosticLog.shared.record("subtask.add begin event=\(eventID.uuidString)")
        var updated = data
        do {
            _ = try updated.addSubtask(to: eventID, text: text, today: Day(Date()))
        } catch {
            DiagnosticLog.shared.record("subtask.add rejected event=\(eventID.uuidString) error=\(error.localizedDescription)")
            self.error = error.localizedDescription
            return false
        }
        let count = updated.items.first(where: { $0.id == eventID })?.subtasks.count ?? 0
        let didSave = await commit(updated, reason: "subtask.add")
        if didSave {
            setSubtasksExpanded(true, for: eventID)
            DiagnosticLog.shared.record("subtask.add success event=\(eventID.uuidString) count=\(count)")
        }
        return didSave
    }

    func editSubtask(eventID: UUID, subtaskID: UUID, text: String) async -> Bool {
        DiagnosticLog.shared.record("subtask.edit begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.editSubtask(eventID: eventID, subtaskID: subtaskID, text: text, today: Day(Date()))
        } catch {
            DiagnosticLog.shared.record("subtask.edit rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) error=\(error.localizedDescription)")
            self.error = error.localizedDescription
            return false
        }
        return await commit(updated, reason: "subtask.edit")
    }

    func deleteSubtask(eventID: UUID, subtaskID: UUID) async -> Bool {
        DiagnosticLog.shared.record("subtask.delete begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.deleteSubtask(eventID: eventID, subtaskID: subtaskID, today: Day(Date()))
        } catch {
            DiagnosticLog.shared.record("subtask.delete rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) error=\(error.localizedDescription)")
            self.error = error.localizedDescription
            return false
        }
        let remaining = updated.items.first(where: { $0.id == eventID })?.subtasks.count ?? 0
        let didSave = await commit(updated, reason: "subtask.delete")
        if didSave, remaining == 0 {
            disclosureCache.remove(eventID: eventID)
        }
        return didSave
    }

    func toggleSubtask(eventID: UUID, subtaskID: UUID) async -> Bool {
        DiagnosticLog.shared.record("subtask.toggle begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.toggleSubtask(eventID: eventID, subtaskID: subtaskID, today: Day(Date()))
        } catch {
            DiagnosticLog.shared.record("subtask.toggle rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) error=\(error.localizedDescription)")
            self.error = error.localizedDescription
            return false
        }
        return await commit(updated, reason: "subtask.toggle")
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
        if await commit(updated, reason: "countdown.delete") {
            disclosureCache.remove(eventID: id)
        }
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
