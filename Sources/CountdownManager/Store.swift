import AppKit
import Combine
import CountdownCore
import ServiceManagement
import UniformTypeIdentifiers

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
    @Published private(set) var today: Day
    @Published package private(set) var isLoading = true
    @Published package private(set) var isExportingDiagnostics = false
    @Published var error: String?
    @Published package private(set) var loginStatus: SMAppService.Status
    package let loginItemManagementIsAvailable: Bool
    private let fileURL: URL
    private let repository: CountdownRepository
    private let persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)?
    private let now: () -> Date
    private let recordDiagnostic: @Sendable (String) -> Void
    private let disclosureCache: SubtaskDisclosureCache
    private var readFailed = false
    private var revision = 0
    private var durableRevision = 0
    private var durableData = CountdownData()
    private var inFlightPersistenceRevisions: Set<Int> = []
    private var isRecoveringPersistence = false
    private var recoveryMutationInFlight = false
    private var persistenceRecoveryWaiters: [CheckedContinuation<Void, Never>] = []
    private var needsDeferredNormalization = false
    private var subscriptions = Set<AnyCancellable>()
    private var midnightTimer: Timer?

    package init(
        fileURL: URL? = nil,
        disclosureDefaults: UserDefaults = .standard,
        persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)? = nil,
        now: @escaping () -> Date = Date.init,
        loginItemManagementIsAvailable: Bool = true,
        diagnosticRecord: @escaping @Sendable (String) -> Void = { DiagnosticLog.shared.record($0) }
    ) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedURL = fileURL ?? support.appendingPathComponent("CountdownManager/countdowns.json")
        self.fileURL = resolvedURL
        today = Day(now())
        repository = CountdownRepository(fileURL: resolvedURL)
        self.persistenceSaveOverride = persistenceSaveOverride
        self.now = now
        self.recordDiagnostic = diagnosticRecord
        self.loginItemManagementIsAvailable = loginItemManagementIsAvailable
        loginStatus = loginItemManagementIsAvailable ? SMAppService.mainApp.status : .notRegistered
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
            recordDiagnostic("data.load success items=\(data.items.count)")
            refresh()
        } catch {
            readFailed = true
            isLoading = false
            recordDiagnostic("data.load failure \(DiagnosticPrivacy.errorFields(error))")
            self.error = "Не удалось прочитать сохранённые события. Файл оставлен без изменений: \(fileURL.path)\n\(error.localizedDescription)"
        }
    }

    var active: [Countdown] {
        activeCountdowns(in: data, today: today)
    }
    var primary: Countdown? { active.first { $0.id == data.primaryID } ?? active.first }
    var statusTitle: String { statusBarTitle(data: data, today: today) }
    var tomorrow: Date { Day.calendar.date(byAdding: .day, value: 1, to: today.date())! }

    package var hasPendingPersistence: Bool {
        isLoading || !inFlightPersistenceRevisions.isEmpty || isRecoveringPersistence || recoveryMutationInFlight
    }

    func subtasksAreExpanded(for eventID: UUID) -> Bool {
        disclosureState(for: eventID).isExpanded
    }

    func disclosureState(for eventID: UUID) -> SubtaskDisclosureState {
        disclosureCache.state(for: eventID)
    }

    func setSubtasksExpanded(_ isExpanded: Bool, for eventID: UUID) {
        disclosureState(for: eventID).setExpanded(isExpanded)
    }

    package func refresh() {
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        if !isLoading && !readFailed {
            var updated = data
            updated.normalize(today: today)
            if updated != data {
                let removedEventIDs = Set(data.items.map(\.id)).subtracting(updated.items.map(\.id))
                recordDiagnostic("data.normalize removed=\(data.items.count - updated.items.count)")
                if isRecoveringPersistence {
                    needsDeferredNormalization = true
                } else {
                    stagePersistence(
                        updated,
                        reason: "normalize",
                        disclosureCleanup: removedEventIDs
                    )
                }
            }
        }
        if loginItemManagementIsAvailable {
            let currentLoginStatus = SMAppService.mainApp.status
            if currentLoginStatus != loginStatus { loginStatus = currentLoginStatus }
        }
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
        guard !isRecoveringPersistence else { return }
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
            recordDiagnostic(
                didWrite
                    ? "data.save success reason=\(reason) revision=\(writeRevision) items=\(updated.items.count) primary=\(updated.primaryID?.uuidString ?? "none")"
                    : "data.save superseded reason=\(reason) revision=\(writeRevision)"
            )
            return true
        } catch {
            isRecoveringPersistence = true
            finishPersistenceRevision(writeRevision)
            recordDiagnostic("data.save failure \(DiagnosticPrivacy.errorFields(error))")
            self.error = "Не удалось сохранить изменения: \(error.localizedDescription)"
            return false
        }
    }

    private func finishPersistenceRevision(_ writeRevision: Int) {
        inFlightPersistenceRevisions.remove(writeRevision)
        if inFlightPersistenceRevisions.isEmpty {
            data = durableData
            startNextRecoveryMutationIfReady()
        }
    }

    private func waitForPersistenceRecoveryIfNeeded() async -> Bool {
        guard isRecoveringPersistence else { return false }
        await withCheckedContinuation { continuation in
            persistenceRecoveryWaiters.append(continuation)
            startNextRecoveryMutationIfReady()
        }
        return true
    }

    private func finishRecoveryMutation() {
        recoveryMutationInFlight = false
        startNextRecoveryMutationIfReady()
    }

    private func startNextRecoveryMutationIfReady() {
        guard isRecoveringPersistence,
              !recoveryMutationInFlight,
              inFlightPersistenceRevisions.isEmpty else { return }
        guard !persistenceRecoveryWaiters.isEmpty else {
            isRecoveringPersistence = false
            persistDeferredNormalizationIfNeeded()
            return
        }
        recoveryMutationInFlight = true
        persistenceRecoveryWaiters.removeFirst().resume()
    }

    private func persistDeferredNormalizationIfNeeded() {
        guard needsDeferredNormalization else { return }
        needsDeferredNormalization = false
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        var updated = data
        updated.normalize(today: today)
        guard updated != data else { return }
        let removedEventIDs = Set(data.items.map(\.id)).subtracting(updated.items.map(\.id))
        recordDiagnostic("data.normalize deferred removed=\(data.items.count - updated.items.count)")
        stagePersistence(updated, reason: "normalize", disclosureCleanup: removedEventIDs)
    }

    package func save(_ countdown: Countdown, primary: Bool, requireExisting: Bool = false) async -> Bool {
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("countdown.save begin id=\(countdown.id.uuidString) primary=\(primary)")
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        var updated = data
        // Check at the mutation boundary: an editor task may run after expiry/removal.
        if requireExisting && !updated.items.contains(where: { $0.id == countdown.id && $0.date >= today }) {
            error = "Событие больше недоступно. Черновик не сохранён."
            return false
        }
        do { try updated.save(countdown, primary: primary, today: today) }
        catch {
            recordDiagnostic("countdown.save rejected id=\(countdown.id.uuidString) \(DiagnosticPrivacy.errorFields(error))")
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
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("subtask.add begin event=\(eventID.uuidString)")
        var updated = data
        do {
            _ = try updated.addSubtask(to: eventID, text: text, today: Day(now()))
        } catch {
            recordDiagnostic("subtask.add rejected event=\(eventID.uuidString) \(DiagnosticPrivacy.errorFields(error))")
            self.error = error.localizedDescription
            return false
        }
        let count = updated.items.first(where: { $0.id == eventID })?.subtasks.count ?? 0
        let didSave = await commit(updated, reason: "subtask.add")
        if didSave {
            setSubtasksExpanded(true, for: eventID)
            recordDiagnostic("subtask.add success event=\(eventID.uuidString) count=\(count)")
        }
        return didSave
    }

    func editSubtask(eventID: UUID, subtaskID: UUID, text: String) async -> Bool {
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("subtask.edit begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.editSubtask(eventID: eventID, subtaskID: subtaskID, text: text, today: Day(now()))
        } catch {
            recordDiagnostic("subtask.edit rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) \(DiagnosticPrivacy.errorFields(error))")
            self.error = error.localizedDescription
            return false
        }
        return await commit(updated, reason: "subtask.edit")
    }

    func deleteSubtask(eventID: UUID, subtaskID: UUID) async -> Bool {
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("subtask.delete begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.deleteSubtask(eventID: eventID, subtaskID: subtaskID, today: Day(now()))
        } catch {
            recordDiagnostic("subtask.delete rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) \(DiagnosticPrivacy.errorFields(error))")
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
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("subtask.toggle begin event=\(eventID.uuidString) id=\(subtaskID.uuidString)")
        var updated = data
        do {
            try updated.toggleSubtask(eventID: eventID, subtaskID: subtaskID, today: Day(now()))
        } catch {
            recordDiagnostic("subtask.toggle rejected event=\(eventID.uuidString) id=\(subtaskID.uuidString) \(DiagnosticPrivacy.errorFields(error))")
            self.error = error.localizedDescription
            return false
        }
        return await commit(updated, reason: "subtask.toggle")
    }

    func makePrimary(_ id: UUID) async {
        await setPrimarySelection(id)
    }

    package func clearPrimary() async {
        await setPrimarySelection(nil)
    }

    private func setPrimarySelection(_ id: UUID?) async {
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        var updated = data
        updated.normalize(today: today)
        if let id, !updated.items.contains(where: { $0.id == id }) { return }
        recordDiagnostic("countdown.primary id=\(id?.uuidString ?? "none")")
        updated.primaryID = id
        guard updated != data else { return }
        _ = await commit(updated, reason: "countdown.primary")
    }

    @discardableResult
    func delete(_ id: UUID) async -> Bool {
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        recordDiagnostic("countdown.delete id=\(id.uuidString)")
        var updated = data
        updated.delete(id, today: Day(now()))
        let didDelete = await commit(updated, reason: "countdown.delete")
        if didDelete { disclosureCache.remove(eventID: id) }
        return didDelete
    }

    package func setLogin(_ enabled: Bool) {
        guard loginItemManagementIsAvailable else { return }
        recordDiagnostic("login-item.change requested=\(enabled)")
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            recordDiagnostic("login-item.change failure \(DiagnosticPrivacy.errorFields(error))")
            self.error = "Не удалось изменить автозапуск: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
        recordDiagnostic("login-item.status value=\(loginStatus.rawValue)")
    }

    package func openLoginItemSettings() {
        guard loginItemManagementIsAvailable else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    func openDiagnostics() {
        recordDiagnostic("diagnostics.open-folder")
        Task {
            do {
                let url = try await DiagnosticLog.shared.directoryForViewing()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                recordDiagnostic("diagnostics.open-folder failure \(DiagnosticPrivacy.errorFields(error))")
                self.error = "Не удалось открыть папку диагностики: \(error.localizedDescription)"
            }
        }
    }

    package func saveDiagnostics(context: @escaping @MainActor () -> DiagnosticExportContext) {
        guard !isExportingDiagnostics else { return }
        isExportingDiagnostics = true
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Countdown-Diagnostics.zip"
        panel.title = "Сохранить диагностику"
        panel.message = "Архив содержит техническую сводку и два последних журнала без содержимого событий и файлов настроек."
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            panel.orderOut(nil)
            guard let self else { return }
            guard response == .OK, let destination = panel.url else {
                self.isExportingDiagnostics = false
                if response == .cancel { self.recordDiagnostic("diagnostics.export cancelled") }
                else {
                    self.recordDiagnostic("diagnostics.export failure category=other")
                    self.error = "Не удалось открыть окно сохранения диагностики. Повторите попытку."
                }
                return
            }
            let context = context()
            let state = DiagnosticStoreState(
                loading: self.isLoading, readFailed: self.readFailed, eventCount: self.data.items.count,
                subtaskCount: self.data.items.reduce(0) { $0 + $1.subtasks.count },
                pendingWrites: self.inFlightPersistenceRevisions.count,
                recovering: self.isRecoveringPersistence || self.recoveryMutationInFlight,
                revision: self.revision, durableRevision: self.durableRevision
            )
            self.recordDiagnostic("diagnostics.export begin")
            Task {
                defer { self.isExportingDiagnostics = false }
                do {
                    let snapshot = try await DiagnosticLog.shared.snapshot()
                    try await DiagnosticArchiveExporter().export(snapshot: snapshot, context: context, store: state, destination: destination)
                    self.recordDiagnostic("diagnostics.export success")
                } catch {
                    self.recordDiagnostic("diagnostics.export failure \(DiagnosticPrivacy.errorFields(error))")
                    self.error = "Не удалось сохранить диагностику. Выберите другую папку и повторите попытку."
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let host = NSApp.keyWindow, host.isVisible, NSApp.windows.contains(where: { $0 === host }) {
            panel.beginSheetModal(for: host, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }
}
