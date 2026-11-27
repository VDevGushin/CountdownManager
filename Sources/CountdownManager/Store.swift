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

private enum StoreAttachmentPersistenceError: LocalizedError {
    case overriddenWriter

    var errorDescription: String? {
        AppText.string("store.testAttachmentSave")
    }
}

package enum SavedMaterialOwnerID: Equatable {
    case event(UUID), record(UUID)

    var id: UUID {
        switch self {
        case let .event(id), let .record(id): id
        }
    }

    var collection: StoredAttachmentCollection {
        switch self {
        case .event: .events
        case .record: .records
        }
    }

    var unavailableAttachment: String {
        switch self {
        case .event: AppText.string("store.attachmentUnavailable")
        case .record: AppText.string("record.error.attachmentUnavailable")
        }
    }

    var unavailableLink: String {
        switch self {
        case .event: AppText.string("store.linkUnavailable")
        case .record: AppText.string("record.error.linkUnavailable")
        }
    }

    var unavailableTitle: String {
        switch self {
        case .event: AppText.string("event.unavailable")
        case .record: AppText.string("record.error.unavailable")
        }
    }
}

extension Store {
    package func beginAttachmentDraft(_ draftID: UUID) async -> Bool {
        guard eventCreationIsAvailable else { return false }
        return await prepareAttachmentDraft(draftID, in: .events)
    }

    package func beginRecordAttachmentDraft(_ draftID: UUID) async -> Bool {
        guard recordCreationIsAvailable, !isWritingRecords else { return false }
        return await prepareAttachmentDraft(draftID, in: .records)
    }

    private func prepareAttachmentDraft(_ draftID: UUID, in collection: StoredAttachmentCollection) async -> Bool {
        if let existing = attachmentDrafts[draftID] { return existing == collection }
        attachmentDrafts[draftID] = collection
        attachmentOperationCount += 1
        defer { attachmentOperationCount -= 1 }
        do {
            try await repository.beginAttachmentDraft(draftID, in: collection)
            guard attachmentDrafts[draftID] == collection else {
                do { try await repository.discardAttachmentDraft(draftID) }
                catch { reportAttachmentCleanupFailure() }
                return false
            }
            return true
        } catch {
            attachmentDrafts.removeValue(forKey: draftID)
            recordDiagnostic("attachments.draft failure category=storage")
            self.error = AppText.string("store.prepareAttachmentFailed")
            return false
        }
    }

    package func importAttachment(from source: URL, draftID: UUID) async -> EventAttachment? {
        guard !Task.isCancelled, attachmentDrafts[draftID] != nil else { return nil }
        attachmentOperationCount += 1
        let scopedAccess = source.startAccessingSecurityScopedResource()
        defer {
            if scopedAccess { source.stopAccessingSecurityScopedResource() }
            attachmentOperationCount -= 1
        }
        do {
            let attachment = try await repository.importAttachment(from: source, draftID: draftID)
            guard !Task.isCancelled, attachmentDrafts[draftID] != nil else { return nil }
            return attachment
        } catch {
            guard attachmentDrafts[draftID] != nil else { return nil }
            recordDiagnostic("attachments.import failure category=storage")
            self.error = AppText.string("store.copyAttachmentFailed")
            return nil
        }
    }

    package func discardAttachmentDraft(_ draftID: UUID) async {
        guard attachmentDrafts.removeValue(forKey: draftID) != nil else { return }
        if attachmentPicker?.draftID == draftID { attachmentPicker?.panel.cancel(nil) }
        attachmentOperationCount += 1
        defer { attachmentOperationCount -= 1 }
        do { try await repository.discardAttachmentDraft(draftID) }
        catch { reportAttachmentCleanupFailure() }
    }

    package func chooseAttachments(draftID: UUID, currentAttachments: [EventAttachment]) async -> [EventAttachment] {
        guard attachmentDrafts[draftID] != nil, attachmentPicker == nil, !isImportingAttachments else { return [] }
        guard currentAttachments.count < EventAttachment.maximumCount else {
            error = AppText.string("store.attachmentLimit", "\(EventAttachment.maximumCount)")
            return []
        }
        let host = NSApp.keyWindow
        let panel = NSOpenPanel()
        panel.appearanceSource = host ?? dialogAppearanceSource
        panel.title = AppText.string("store.addAttachments")
        panel.prompt = AppText.string("common.add")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        attachmentPicker = (draftID, panel)
        attachmentOperationCount += 1
        defer {
            attachmentPicker = nil
            attachmentOperationCount -= 1
        }
        let response = await withCheckedContinuation { continuation in
            let completion: (NSApplication.ModalResponse) -> Void = { response in
                panel.orderOut(nil)
                continuation.resume(returning: response)
            }
            if let host, host.isVisible, NSApp.windows.contains(where: { $0 === host }) {
                panel.beginSheetModal(for: host, completionHandler: completion)
            } else {
                panel.begin(completionHandler: completion)
            }
        }
        guard response == .OK, !Task.isCancelled, attachmentDrafts[draftID] != nil else { return [] }
        return await importAttachments(from: panel.urls, draftID: draftID, currentAttachments: currentAttachments)
    }

    package func importAttachments(from sources: [URL], draftID: UUID,
                                   currentAttachments: [EventAttachment]) async -> [EventAttachment] {
        guard !Task.isCancelled, attachmentDrafts[draftID] != nil else { return [] }
        let remaining = max(0, EventAttachment.maximumCount - currentAttachments.count)
        guard sources.count <= remaining else {
            error = AppText.string("store.pickerFileLimit", "\(sources.count)", "\(remaining)")
            return []
        }
        var imported: [EventAttachment] = []
        for source in sources {
            guard attachmentDrafts[draftID] != nil else { return [] }
            guard let attachment = await importAttachment(from: source, draftID: draftID) else { break }
            imported.append(attachment)
        }
        return !Task.isCancelled && attachmentDrafts[draftID] != nil ? imported : []
    }

    package func openAttachment(_ attachment: EventAttachment, eventID: UUID) async {
        await openSavedAttachment(attachment, owner: .event(eventID))
    }

    package func openAttachment(_ attachment: EventAttachment, recordID: UUID) async {
        await openSavedAttachment(attachment, owner: .record(recordID))
    }

    func openSavedAttachment(_ attachment: EventAttachment, owner: SavedMaterialOwnerID) async {
        guard !Task.isCancelled else { return }
        guard attachmentIsActive(attachment, owner: owner) else {
            error = owner.unavailableAttachment
            return
        }
        do {
            let url = try await repository.attachmentURL(for: attachment, in: owner.collection)
            guard !Task.isCancelled else { return }
            guard attachmentIsActive(attachment, owner: owner) else {
                error = owner.unavailableAttachment
                return
            }
            if !NSWorkspace.shared.open(url) {
                error = AppText.string("store.openAttachmentFailed")
            }
        } catch {
            guard !Task.isCancelled else { return }
            recordDiagnostic("attachments.open failure category=storage")
            self.error = AppText.string("store.attachmentCopyUnavailable")
        }
    }

    package func editorAttachmentThumbnailURL(_ attachment: EventAttachment, eventID: UUID?, draftID: UUID) async -> URL? {
        await editorAttachmentThumbnailURL(
            attachment, owner: eventID.map(SavedMaterialOwnerID.event), draftID: draftID, in: .events
        )
    }

    package func editorAttachmentThumbnailURL(_ attachment: EventAttachment, recordID: UUID?, draftID: UUID) async -> URL? {
        await editorAttachmentThumbnailURL(
            attachment, owner: recordID.map(SavedMaterialOwnerID.record), draftID: draftID, in: .records
        )
    }

    private func editorAttachmentThumbnailURL(
        _ attachment: EventAttachment,
        owner: SavedMaterialOwnerID?,
        draftID: UUID,
        in collection: StoredAttachmentCollection
    ) async -> URL? {
        if let owner, attachmentIsActive(attachment, owner: owner) {
            return await attachmentThumbnailURL(attachment, owner: owner)
        }
        guard !Task.isCancelled, attachmentDrafts[draftID] == collection else { return nil }
        do {
            let url = try await repository.draftAttachmentURL(for: attachment, draftID: draftID)
            guard !Task.isCancelled, attachmentDrafts[draftID] == collection else { return nil }
            return url
        } catch {
            return nil
        }
    }

    func attachmentThumbnailURL(_ attachment: EventAttachment, eventID: UUID) async -> URL? {
        await attachmentThumbnailURL(attachment, owner: .event(eventID))
    }

    package func attachmentThumbnailURL(_ attachment: EventAttachment, recordID: UUID) async -> URL? {
        await attachmentThumbnailURL(attachment, owner: .record(recordID))
    }

    func attachmentThumbnailURL(_ attachment: EventAttachment, owner: SavedMaterialOwnerID) async -> URL? {
        guard !Task.isCancelled, attachmentIsActive(attachment, owner: owner) else { return nil }
        do {
            let url = try await repository.attachmentURL(for: attachment, in: owner.collection)
            guard !Task.isCancelled, attachmentIsActive(attachment, owner: owner) else { return nil }
            return url
        } catch {
            return nil
        }
    }

    private func attachmentIsActive(_ attachment: EventAttachment, owner: SavedMaterialOwnerID) -> Bool {
        switch owner {
        case .event(let id):
            data.items.contains { $0.id == id && $0.isAvailable(on: Day(now())) && $0.attachments.contains(attachment) }
        case .record(let id):
            records.contains { $0.id == id && $0.attachments.contains(attachment) }
        }
    }

    private func reportAttachmentCleanupFailure() {
        recordDiagnostic("attachments.cleanup failure category=storage")
        error = AppText.string("store.cleanupFailed")
    }
}

extension Store {
    private func loadRecords() async {
        defer { isLoadingRecords = false }
        do {
            records = try await repository.loadRecords()
            if await repository.attachmentCleanupFailed(in: .records) { reportAttachmentCleanupFailure() }
            recordDiagnostic("records.load success count=\(records.count)")
        } catch {
            recordReadFailed = true
            recordDiagnostic("records.load failure \(DiagnosticPrivacy.errorFields(error))")
            let url = CountdownRepository.recordsFileURL(beside: fileURL)
            if (error as? CocoaError)?.code == .fileReadNoSuchFile {
                self.error = AppText.string("record.storageMissing", url.path)
            } else {
                self.error = AppText.string("record.storageReadFailed", url.path)
            }
        }
    }

    package func saveRecord(_ record: UndatedRecord, requireExisting: Bool = false) async -> Bool {
        let saved = await changeRecords { candidate in
            let normalized = try record.normalized()
            if let index = candidate.firstIndex(where: { $0.id == record.id }) {
                guard requireExisting else { throw UndatedRecordError.identity }
                candidate[index] = normalized
            } else {
                guard !requireExisting else { throw UndatedRecordError.unavailable }
                candidate.insert(normalized, at: 0)
            }
            return true
        }
        if saved, record.subtasks.isEmpty { recordDisclosureCache.remove(eventID: record.id) }
        return saved
    }

    package func deleteRecord(_ recordID: UUID) async -> Bool {
        let deleted = await changeRecords { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == recordID }) else {
                throw UndatedRecordError.unavailable
            }
            candidate.remove(at: index)
            return true
        }
        if deleted { recordDisclosureCache.remove(eventID: recordID) }
        return deleted
    }

    package func toggleRecordSubtask(recordID: UUID, subtaskID: UUID) async -> Bool {
        await changeRecords { candidate in
            guard let index = candidate.firstIndex(where: { $0.id == recordID }) else {
                throw UndatedRecordError.unavailable
            }
            try candidate[index].subtasks.toggleCompletion(id: subtaskID)
            return true
        }
    }

    package var canEnqueuePanelRecordSubtaskToggle: Bool {
        recordCreationIsAvailable && (isApplyingPanelRecordToggles || !hasPendingPersistence)
    }

    package func enqueuePanelRecordSubtaskToggle(recordID: UUID, subtaskID: UUID) {
        guard canEnqueuePanelRecordSubtaskToggle else { return }
        panelRecordToggles.append((recordID, subtaskID))
        guard !isApplyingPanelRecordToggles else { return }
        isApplyingPanelRecordToggles = true
        Task {
            defer { isApplyingPanelRecordToggles = false }
            while !panelRecordToggles.isEmpty {
                let next = panelRecordToggles.removeFirst()
                guard await toggleRecordSubtask(recordID: next.recordID, subtaskID: next.subtaskID) else {
                    let hadRemainingActions = !panelRecordToggles.isEmpty
                    panelRecordToggles.removeAll()
                    reportQueuedActionFailure(fallback: AppText.string("record.error.unavailable"),
                                              hadRemainingActions: hadRemainingActions)
                    return
                }
            }
        }
    }

    package func reorderRecordSubtask(recordID: UUID, move: SubtaskReorder, to index: Int) async -> Bool {
        await changeRecords { candidate in
            guard let recordIndex = candidate.firstIndex(where: { $0.id == recordID }) else {
                throw UndatedRecordError.unavailable
            }
            return try candidate[recordIndex].subtasks.applyReorder(move, to: index)
        }
    }

    private func changeRecords(_ mutate: (inout [UndatedRecord]) throws -> Bool) async -> Bool {
        guard !Task.isCancelled, recordCreationIsAvailable, !isWritingRecords else { return false }
        var candidate = records
        do {
            guard try mutate(&candidate) else { return false }
            guard candidate != records else {
                clearRecordWriteError()
                return true
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
        isWritingRecords = true
        defer { isWritingRecords = false }
        do {
            try await repository.saveRecords(candidate)
            records = candidate
            if await repository.attachmentCleanupFailed(in: .records) { reportAttachmentCleanupFailure() }
            clearRecordWriteError()
            recordDiagnostic("records.save success count=\(records.count)")
            return true
        } catch {
            recordDiagnostic("records.save failure \(DiagnosticPrivacy.errorFields(error))")
            let message = AppText.string("record.storageWriteFailed")
            recordWriteError = message
            self.error = message
            return false
        }
    }

    private func clearRecordWriteError() {
        if let recordWriteError, error == recordWriteError { error = nil }
        recordWriteError = nil
    }

    func reportQueuedActionFailure(fallback: String, hadRemainingActions: Bool) {
        let message = error ?? fallback
        let annotated = hadRemainingActions ? message + AppText.string("store.queuedActionsSkipped") : message
        if let recordWriteError, error == recordWriteError { self.recordWriteError = annotated }
        error = annotated
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
    @Published package private(set) var records: [UndatedRecord] = []
    @Published private(set) var today: Day
    @Published package private(set) var isLoading = true
    @Published package private(set) var isLoadingRecords = true
    @Published package private(set) var isExportingDiagnostics = false
    @Published package var error: String?
    @Published package private(set) var loginStatus: SMAppService.Status
    package let loginItemManagementIsAvailable: Bool
    private let fileURL: URL
    private let repository: CountdownRepository
    private let persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)?
    private let openWebURL: (URL) -> Bool
    private let now: () -> Date
    private let recordDiagnostic: @Sendable (String) -> Void
    private let disclosureCache: SubtaskDisclosureCache
    private let recordDisclosureCache: SubtaskDisclosureCache
    private var readFailed = false
    private var recordReadFailed = false
    @Published private var isWritingRecords = false
    @Published private var isApplyingPanelRecordToggles = false
    private var panelRecordToggles: [(recordID: UUID, subtaskID: UUID)] = []
    private var recordWriteError: String?
    private var revision = 0
    private var durableRevision = 0
    private var durableData = CountdownData()
    private var inFlightPersistenceRevisions: Set<Int> = []
    @Published private var isRecoveringPersistence = false
    private var recoveryMutationInFlight = false
    private var persistenceRecoveryWaiters: [CheckedContinuation<Void, Never>] = []
    private var isTransferringSubtask = false
    private var subtaskTransferWaiters: [CheckedContinuation<Void, Never>] = []
    private var needsDeferredNormalization = false
    private var subscriptions = Set<AnyCancellable>()
    private var midnightTimer: Timer?
    @Published package private(set) var isResolvingMaterials = false
    @Published package private(set) var isReceivingMaterials = false
    private var attachmentDrafts: [UUID: StoredAttachmentCollection] = [:]
    private var savingCopyDrafts: Set<UUID> = []
    private var attachmentPicker: (draftID: UUID, panel: NSOpenPanel)?
    package weak var dialogAppearanceSource: NSWindow?
    @Published private var attachmentOperationCount = 0

    package init(
        fileURL: URL? = nil,
        disclosureDefaults: UserDefaults = .standard,
        persistenceSaveOverride: ((CountdownData, Int) async throws -> Bool)? = nil,
        now: @escaping () -> Date = Date.init,
        loginItemManagementIsAvailable: Bool = true,
        openWebURL: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) },
        diagnosticRecord: @escaping @Sendable (String) -> Void = { DiagnosticLog.shared.record($0) }
    ) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedURL = fileURL ?? support.appendingPathComponent("CountdownManager/countdowns.json")
        self.fileURL = resolvedURL
        today = Day(now())
        repository = CountdownRepository(fileURL: resolvedURL)
        self.persistenceSaveOverride = persistenceSaveOverride
        self.openWebURL = openWebURL
        self.now = now
        self.recordDiagnostic = diagnosticRecord
        self.loginItemManagementIsAvailable = loginItemManagementIsAvailable
        loginStatus = loginItemManagementIsAvailable ? SMAppService.mainApp.status : .notRegistered
        disclosureCache = SubtaskDisclosureCache(
            persistence: SubtaskDisclosurePersistence(defaults: disclosureDefaults)
        )
        recordDisclosureCache = SubtaskDisclosureCache(
            persistence: SubtaskDisclosurePersistence(defaults: disclosureDefaults, key: "expandedSubtasksByRecord")
        )
        Task { await load() }
        Task { await loadRecords() }
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
            if await repository.attachmentCleanupFailed { reportAttachmentCleanupFailure() }
            isLoading = false
            recordDiagnostic("data.load success items=\(data.items.count)")
            refresh()
        } catch {
            readFailed = true
            isLoading = false
            recordDiagnostic("data.load failure \(DiagnosticPrivacy.errorFields(error))")
            self.error = AppText.string("store.storageReadFailed", fileURL.path)
        }
    }

    var active: [Countdown] {
        activeCountdowns(in: data, today: today)
    }
    var primary: Countdown? { active.first { $0.id == data.primaryID } ?? active.first }
    var statusPresentation: StatusBarPresentation { statusBarPresentation(data: data, today: today) }
    var statusTitle: String { statusPresentation.title }
    var tomorrow: Date { Day.calendar.date(byAdding: .day, value: 1, to: today.date())! }

    package var hasPendingPersistence: Bool {
        isLoading || isWritingRecords || isApplyingPanelRecordToggles || !inFlightPersistenceRevisions.isEmpty
            || isRecoveringPersistence || recoveryMutationInFlight
            || isTransferringSubtask
            || isImportingAttachments || isHandlingMaterials
    }

    var isHandlingMaterials: Bool { isReceivingMaterials || isResolvingMaterials }

    package var isImportingAttachments: Bool { attachmentOperationCount > 0 }

    package var eventCreationIsAvailable: Bool {
        !isLoading && !readFailed && !isRecoveringPersistence && !recoveryMutationInFlight
    }

    package var showsEmptyEventList: Bool { eventCreationIsAvailable && active.isEmpty }

    package var recordCreationIsAvailable: Bool { !isLoadingRecords && !recordReadFailed }

    package var showsEmptyRecordList: Bool { recordCreationIsAvailable && records.isEmpty }

    func subtasksAreExpanded(for eventID: UUID) -> Bool {
        disclosureState(for: eventID).isExpanded
    }

    func disclosureState(for eventID: UUID) -> SubtaskDisclosureState {
        disclosureCache.state(for: eventID)
    }

    package func recordDisclosureState(for recordID: UUID) -> SubtaskDisclosureState {
        recordDisclosureCache.state(for: recordID)
    }

    func disclosureState(for owner: SavedMaterialOwnerID) -> SubtaskDisclosureState {
        switch owner {
        case let .event(id): disclosureState(for: id)
        case let .record(id): recordDisclosureState(for: id)
        }
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
                if isRecoveringPersistence || isTransferringSubtask || isHandlingMaterials {
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

    private func commit(_ updated: CountdownData, reason: String, publishImmediately: Bool = true) async -> Bool {
        guard !isLoading, !readFailed else {
            error = AppText.string("store.storageRecoveryRequired", fileURL.path)
            return false
        }
        if updated == data { return true }
        revision += 1
        let writeRevision = revision
        inFlightPersistenceRevisions.insert(writeRevision)
        if publishImmediately { data = updated }
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
                guard updated.items.allSatisfy({ $0.attachments.isEmpty }),
                      durableData.items.allSatisfy({ $0.attachments.isEmpty }) else {
                    throw StoreAttachmentPersistenceError.overriddenWriter
                }
                didWrite = try await persistenceSaveOverride(updated, writeRevision)
            } else {
                didWrite = try await repository.save(updated, revision: writeRevision)
                if await repository.attachmentCleanupFailed { reportAttachmentCleanupFailure() }
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
            self.error = AppText.string("store.storageWriteFailed")
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
        if isTransferringSubtask {
            await withCheckedContinuation { subtaskTransferWaiters.append($0) }
        }
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
        guard needsDeferredNormalization, !isTransferringSubtask, !isHandlingMaterials, !isRecoveringPersistence else { return }
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

    package func openLink(_ link: EventLink, eventID: UUID) {
        openSavedLink(link, owner: .event(eventID))
    }

    package func openLink(_ link: EventLink, recordID: UUID) {
        openSavedLink(link, owner: .record(recordID))
    }

    func openSavedLink(_ link: EventLink, owner: SavedMaterialOwnerID) {
        let isSaved: Bool
        switch owner {
        case .event(let id):
            isSaved = !isLoading && !readFailed && data.items.contains {
                $0.id == id && $0.isAvailable(on: Day(now())) && $0.links.contains(link)
            }
        case .record(let id):
            isSaved = !isLoadingRecords && !recordReadFailed && records.contains {
                $0.id == id && $0.links.contains(link)
            }
        }
        guard isSaved, let url = link.url else {
            error = owner.unavailableLink
            return
        }
        if !openWebURL(url) {
            error = AppText.string("store.openLinkFailed")
        }
    }

    package func save(_ countdown: Countdown, primary: Bool, requireExisting: Bool = false) async -> Bool {
        let waitingForTransfer = isTransferringSubtask
        let eventBeforeTransfer = data.items.first { $0.id == countdown.id }
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        if waitingForTransfer, eventBeforeTransfer != data.items.first(where: { $0.id == countdown.id }) {
            error = AppText.string("store.staleEditor")
            recordDiagnostic("countdown.save rejected id=\(countdown.id.uuidString) category=transfer-conflict")
            return false
        }
        recordDiagnostic("countdown.save begin id=\(countdown.id.uuidString) primary=\(primary)")
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        var updated = data
        // Check at the mutation boundary: an editor task may run after expiry/removal.
        if requireExisting && !updated.items.contains(where: { $0.id == countdown.id && $0.isAvailable(on: today) }) {
            error = AppText.string("store.missingEventEditor")
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

    package func saveCopy(_ countdown: Countdown, sourceID: UUID, draftID: UUID, primary: Bool) async -> Countdown? {
        guard !Task.isCancelled, attachmentDrafts[draftID] == .events,
              savingCopyDrafts.insert(draftID).inserted else { return nil }
        error = nil
        attachmentOperationCount += 1
        defer {
            attachmentOperationCount -= 1
            savingCopyDrafts.remove(draftID)
        }
        let isRecoveryMutation = await waitForPersistenceRecoveryIfNeeded()
        defer { if isRecoveryMutation { finishRecoveryMutation() } }
        let copyDraftID = UUID()
        var savedCopy: Countdown?
        do {
            let currentDay = Day(now())
            if currentDay != today { today = currentDay }
            guard !Task.isCancelled, attachmentDrafts[draftID] == .events else { throw CancellationError() }
            guard let source = data.items.first(where: { $0.id == sourceID && $0.isAvailable(on: today) }) else {
                throw CountdownError.eventNotFound
            }
            var candidate = data
            try candidate.saveCopy(countdown, sourceID: sourceID, primary: primary, today: today)
            let attachments = try await repository.copyEventAttachments(
                countdown.attachments, inheritedFrom: source.attachments,
                editorDraftID: draftID, copyDraftID: copyDraftID
            )
            guard !Task.isCancelled, attachmentDrafts[draftID] == .events else { throw CancellationError() }
            let commitDay = Day(now())
            if commitDay != today { today = commitDay }
            guard let latestSource = data.items.first(where: { $0.id == sourceID && $0.isAvailable(on: today) }),
                  countdown.attachments.filter({ source.attachments.contains($0) })
                    .allSatisfy({ latestSource.attachments.contains($0) }) else {
                throw CountdownError.eventNotFound
            }
            candidate = data
            try candidate.saveCopy(countdown, sourceID: sourceID, primary: primary, today: today)
            guard let index = candidate.items.firstIndex(where: { $0.id == countdown.id }) else {
                throw CountdownError.eventNotFound
            }
            candidate.items[index].attachments = attachments
            let normalizedCopy = candidate.items[index]
            if await commit(candidate, reason: "countdown.copy") { savedCopy = normalizedCopy }
        } catch {
            if attachmentDrafts[draftID] == .events, !Task.isCancelled {
                recordDiagnostic("countdown.copy failure \(DiagnosticPrivacy.errorFields(error))")
                switch error {
                case let validation as CountdownError: self.error = validation.errorDescription
                case let validation as EventLinkError: self.error = validation.errorDescription
                case let attachment as EventAttachmentError: self.error = attachment.errorDescription
                default: self.error = AppText.string("store.copyEventFailed")
                }
            }
        }
        do { try await repository.discardAttachmentDraft(copyDraftID) }
        catch { reportAttachmentCleanupFailure() }
        return savedCopy
    }

    package func createWeekDays(_ week: DayCreationWeek) async -> [Countdown]? {
        guard !hasPendingPersistence, eventCreationIsAvailable else { return nil }
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        guard week.referenceDay == today else {
            error = EventUIStrings.weekDateChanged
            return nil
        }
        var updated = data
        let created: [Countdown]
        do { created = try updated.createMissingDays(in: week, today: today) }
        catch {
            self.error = error.localizedDescription
            return nil
        }
        guard !created.isEmpty else { return [] }
        return await commit(updated, reason: "countdown.create-week") ? created : nil
    }

    package func transferSubtask(
        eventID: UUID,
        subtaskID: UUID,
        to targetEventID: UUID?,
        on targetDay: Day
    ) async -> Countdown? {
        guard !Task.isCancelled, !hasPendingPersistence, eventCreationIsAvailable else { return nil }
        let currentDay = Day(now())
        if currentDay != today { today = currentDay }
        error = nil
        var updated = data
        let destination: Countdown
        do {
            destination = try updated.transferSubtask(from: eventID, subtaskID: subtaskID,
                                                     to: targetEventID, on: targetDay, today: today)
        } catch {
            recordDiagnostic("subtask.transfer rejected event=\(eventID.uuidString) \(DiagnosticPrivacy.errorFields(error))")
            self.error = error.localizedDescription
            return nil
        }
        isTransferringSubtask = true
        defer {
            isTransferringSubtask = false
            let waiters = subtaskTransferWaiters
            subtaskTransferWaiters.removeAll()
            waiters.forEach { $0.resume() }
            persistDeferredNormalizationIfNeeded()
        }
        guard await commit(updated, reason: "subtask.transfer", publishImmediately: false) else { return nil }
        if updated.items.first(where: { $0.id == eventID })?.subtasks.isEmpty == true {
            disclosureCache.remove(eventID: eventID)
        }
        setSubtasksExpanded(true, for: destination.id)
        return destination
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
        guard !isHandlingMaterials else { return false }
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

    package func reorderSubtask(eventID: UUID, move: SubtaskReorder, to index: Int) async -> Bool {
        guard !Task.isCancelled, !hasPendingPersistence, eventCreationIsAvailable else { return false }
        var updated = data
        do {
            guard try updated.reorderSubtask(eventID: eventID, move: move, to: index, today: Day(now())) else {
                return false
            }
        } catch {
            self.error = error.localizedDescription
            return false
        }
        error = nil
        return await commit(updated, reason: "subtask.reorder")
    }

    func toggleSubtask(owner: SavedMaterialOwnerID, subtaskID: UUID) async -> Bool {
        switch owner {
        case let .event(id): await toggleSubtask(eventID: id, subtaskID: subtaskID)
        case let .record(id): await toggleRecordSubtask(recordID: id, subtaskID: subtaskID)
        }
    }

    func reorderSubtask(owner: SavedMaterialOwnerID, move: SubtaskReorder, to index: Int) async -> Bool {
        switch owner {
        case let .event(id): await reorderSubtask(eventID: id, move: move, to: index)
        case let .record(id): await reorderRecordSubtask(recordID: id, move: move, to: index)
        }
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
        guard !isHandlingMaterials else { return }
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
            self.error = AppText.string("store.loginItemFailed", String((error as NSError).code))
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
                self.error = AppText.string("store.diagnosticsOpenFailed", String((error as NSError).code))
            }
        }
    }

    package func saveDiagnostics(context: @escaping @MainActor () -> DiagnosticExportContext) {
        guard !isExportingDiagnostics else { return }
        isExportingDiagnostics = true
        let panel = NSSavePanel()
        panel.appearanceSource = NSApp.keyWindow ?? dialogAppearanceSource
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Countdown-Diagnostics.zip"
        panel.title = AppText.string("store.saveDiagnostics")
        panel.message = AppText.string("store.diagnosticsContents")
        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            panel.orderOut(nil)
            guard let self else { return }
            guard response == .OK, let destination = panel.url else {
                self.isExportingDiagnostics = false
                if response == .cancel { self.recordDiagnostic("diagnostics.export cancelled") }
                else {
                    self.recordDiagnostic("diagnostics.export failure category=other")
                    self.error = AppText.string("store.diagnosticsPanelFailed")
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
                    self.error = AppText.string("store.diagnosticsSaveFailed")
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        if let host = NSApp.keyWindow, host.isVisible, NSApp.windows.contains(where: { $0 === host }) {
            panel.beginSheetModal(for: host, completionHandler: completion)
        } else { panel.begin(completionHandler: completion) }
    }
}


extension Store {
    package func beginMaterialResolution() -> Bool {
        guard !hasPendingPersistence, eventCreationIsAvailable else { return false }
        isResolvingMaterials = true
        return true
    }

    func beginMaterialResolution(for ownerID: SavedMaterialOwnerID) -> Bool {
        guard !hasPendingPersistence, savedMaterialOwner(ownerID) != nil else { return false }
        isResolvingMaterials = true
        return true
    }

    func savedMaterialOwner(_ ownerID: SavedMaterialOwnerID) -> SavedMaterialOwner? {
        switch ownerID {
        case let .event(id):
            guard eventCreationIsAvailable else { return nil }
            return data.items.first { $0.id == id && $0.isAvailable(on: Day(now())) }.map(SavedMaterialOwner.init)
        case let .record(id):
            guard recordCreationIsAvailable else { return nil }
            return records.first { $0.id == id }.map(SavedMaterialOwner.init)
        }
    }

    package func endMaterialResolution() {
        isResolvingMaterials = false
        if needsDeferredNormalization {
            // The synchronous handoff can acquire the next material reservation before normalization runs.
            Task { [weak self] in self?.persistDeferredNormalizationIfNeeded() }
        }
    }

    package func createTextAttachment(_ text: TextAttachment, draftID: UUID) async -> EventAttachment? {
        guard !Task.isCancelled, attachmentDrafts[draftID] != nil else { return nil }
        attachmentOperationCount += 1
        defer { attachmentOperationCount -= 1 }
        do {
            let attachment = try await repository.createTextAttachment(text, draftID: draftID)
            guard !Task.isCancelled, attachmentDrafts[draftID] != nil else { return nil }
            return attachment
        } catch {
            if attachmentDrafts[draftID] != nil {
                self.error = (error as? TextAttachmentError)?.errorDescription
                    ?? (error as? EventAttachmentError)?.errorDescription
                    ?? AppText.string("store.textAttachmentCreateFailed")
            }
            return nil
        }
    }

    package func scheduleMaterialAddition(_ materials: EventMaterials, to eventID: UUID) {
        scheduleMaterialAddition(materials, to: .event(eventID))
    }

    func scheduleMaterialAddition(_ materials: EventMaterials, to ownerID: SavedMaterialOwnerID) {
        guard let original = reserveMaterialAddition(materials, to: ownerID) else { return }
        Task { await appendReservedMaterials(materials, to: ownerID, original: original) }
    }

    @discardableResult
    package func appendMaterials(_ materials: EventMaterials, to eventID: UUID) async -> Bool {
        await appendMaterials(materials, to: .event(eventID))
    }

    @discardableResult
    package func appendMaterials(_ materials: EventMaterials, to ownerID: SavedMaterialOwnerID) async -> Bool {
        guard let original = reserveMaterialAddition(materials, to: ownerID) else { return false }
        return await appendReservedMaterials(materials, to: ownerID, original: original)
    }

    private func reserveMaterialAddition(_ materials: EventMaterials, to ownerID: SavedMaterialOwnerID) -> SavedMaterialOwner? {
        guard !hasPendingPersistence, !materials.isEmpty, materials.text == nil,
              let original = savedMaterialOwner(ownerID) else {
            error = AppText.string("store.materialAdmissionBlocked")
            return nil
        }
        do { try materials.validateCapacity(attachments: original.attachments, existingLinks: original.links) }
        catch { self.error = error.localizedDescription; return nil }
        isReceivingMaterials = true
        return original
    }

    @discardableResult
    private func appendReservedMaterials(_ materials: EventMaterials, to ownerID: SavedMaterialOwnerID,
                                         original: SavedMaterialOwner) async -> Bool {
        defer { withExtendedLifetime(materials.stagedFiles) {} }
        defer {
            isReceivingMaterials = false
            persistDeferredNormalizationIfNeeded()
        }
        let draftID = UUID()
        guard await prepareAttachmentDraft(draftID, in: ownerID.collection) else { return false }
        let imported = await importAttachments(from: materials.files, draftID: draftID,
                                                currentAttachments: original.attachments)
        let textFile: EventAttachment?
        if let text = materials.textFile, imported.count == materials.files.count {
            textFile = await createTextAttachment(text, draftID: draftID)
        } else { textFile = nil }
        let latestOwner = savedMaterialOwner(ownerID)
        guard !Task.isCancelled, imported.count == materials.files.count,
              materials.textFile == nil || textFile != nil,
              let latest = latestOwner else {
            await discardAttachmentDraft(draftID)
            if latestOwner == nil || error == nil { error = AppText.string("store.materialBecameUnavailable") }
            return false
        }
        do { try materials.validateCapacity(attachments: latest.attachments, existingLinks: latest.links) }
        catch {
            self.error = error.localizedDescription
            await discardAttachmentDraft(draftID)
            return false
        }
        let files = imported + (textFile.map { [$0] } ?? [])
        let links = materials.links.map { $0.normalized() }
        let saved = await saveAddedMaterials(files, links: links, to: ownerID)
        await discardAttachmentDraft(draftID)
        return saved
    }

    private func saveAddedMaterials(_ files: [EventAttachment], links: [EventLink],
                                    to ownerID: SavedMaterialOwnerID) async -> Bool {
        func appending<Owner: SavedMaterialContent>(_ owner: Owner) -> Owner {
            var updated = owner
            updated.attachments += files
            updated.links += links
            return updated
        }
        switch ownerID {
        case let .event(id):
            guard let event = data.items.first(where: { $0.id == id }) else { return false }
            return await save(appending(event), primary: data.primaryID == id, requireExisting: true)
        case let .record(id):
            guard let record = records.first(where: { $0.id == id }) else { return false }
            return await saveRecord(appending(record), requireExisting: true)
        }
    }

}
