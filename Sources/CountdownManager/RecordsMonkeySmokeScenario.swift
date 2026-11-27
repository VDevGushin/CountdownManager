import AppKit
import CountdownCore
import SwiftUI

/// A fixed action sequence on the two production surfaces, with durable state as its oracle.
@MainActor
struct RecordsMonkeySmokeScenario {
    let configuration: UISmokeConfiguration
    let store: Store
    let editorSession: EventEditorSession
    let visualEnvironment: UISmokeVisualEnvironment
    let accessibility: AuroraAccessibilitySettings
    let desktopWindow: () -> NSWindow?
    let panelWindow: () -> NSWindow?
    let statusButton: () -> NSStatusBarButton?
    let showDesktop: () -> Void
    let showPanel: () -> Void
    let pressStatusItem: () -> Void
    let replaceFocusedText: (String, String, NSWindow?) async throws -> Void
    let capture: (String, NSWindow) throws -> Void

    private var controls: UISmokeControlRegistry { .shared }
    private var recordsURL: URL { CountdownRepository.recordsFileURL(beside: configuration.dataURL) }

    func run() async throws -> [String] {
        try await wait("empty isolated snapshots load") { !store.isLoading && !store.isLoadingRecords }
        try require(store.records.isEmpty && store.active.isEmpty, "monkey scenario requires a fresh profile")
        accessibility.setIsolatedCaptureOverrides(highContrast: false, reduceMotion: true)
        visualEnvironment.colorSchemeOverride = .dark
        let desktop = try await openDesktop()
        try await select("desktop", "records")
        try await wait("desktop empty record creation available") { enabled("desktop.record.empty.create") }
        let panel = try await openPanel()
        try await select("panel", "records")
        try await wait("mini empty record creation available") { enabled("panel.record.create") }
        try require(!FileManager.default.fileExists(atPath: recordsURL.path), "opening an empty surface created record data")
        let fixture = try await seed()
        let eventBytes = try Data(contentsOf: configuration.dataURL)
        _ = try await openDesktop()
        try await verifyDesktopBrowseAndBurst(fixture, window: desktop)
        var expected = store.records
        let panelAgain = try await openPanel()
        try require(panelAgain === panel, "desktop-to-mini switch replaced the retained window")
        try await verifyMiniDraft(fixture, window: panel, desktop: desktop)
        try require(store.records == expected, "Cancel or hidden draft changed saved records")
        try await verifyMiniChecklist(fixture)
        try await verifyMiniEditUsesLatestRecord(fixture, window: panel)
        expected = store.records
        try await verifyWriteFailureAndRetry(fixture, desktop: desktop, expected: expected)
        try await verifyDeletion(fixture, desktop: desktop)
        try require(try Data(contentsOf: configuration.dataURL) == eventBytes,
                    "record actions changed the dated event snapshot")
        try require(store.error == nil, "record scenario ended with an unresolved storage error")
        let reopened = try await CountdownRepository(fileURL: configuration.dataURL).loadRecords()
        try require(reopened == store.records && reopened.map(\.id) == [fixture.full.id, fixture.single.id],
                    "a fresh repository did not find the intended surviving records in creation order")
        try require(reopened.first?.links == fixture.full.links && reopened.first?.attachments == fixture.full.attachments,
                    "unrelated data disappeared from the full record")
        let survivingFile = try value(fixture.full.attachments.first, "fixture attachment")
        let url = try value(await store.attachmentThumbnailURL(survivingFile, recordID: fixture.full.id), "surviving attachment")
        try require(try String(contentsOf: url, encoding: .utf8) == "records monkey attachment",
                    "the owned attachment bytes changed")
        return [
            "both native surfaces start empty; retained section and exact record identities survive switching",
            "both surfaces drain rapid distinct and repeated checklist actions; desktop search stays scoped during section changes",
            "mini retains a hidden full-checklist draft; desktop editor is excluded; invalid Save and Cancel preserve bytes",
            "collapsed and inactive mini controls reject stale actions; mini edits preserve intervening checklist changes",
            "mini and desktop failures show banners and successful retries clear them",
            "mini confirmation Cancel and desktop confirmation Delete preserve source event bytes and other record materials"
        ]
    }

    private struct Fixture {
        let full: UndatedRecord
        let single: UndatedRecord
        let blank: UndatedRecord
        let event: Countdown
    }

    private func seed() async throws -> Fixture {
        let calendar = Countdown(title: "Monkey Needle dated-only", date: Day(store.tomorrow), emoji: "")
        try require(await store.save(calendar, primary: false), "could not save dated neighbor")
        let draftID = UUID()
        try require(await store.beginRecordAttachmentDraft(draftID), "could not start record fixture import")
        let text = TextAttachment(name: "monkey-file.txt", text: "records monkey attachment")
        let file = try value(await store.createTextAttachment(text, draftID: draftID), "fixture text attachment")
        let tasks = try (0..<Subtask.maximumCount).map {
            try Subtask(text: "Monkey task \($0)", isCompleted: $0.isMultiple(of: 3))
        }
        let link = EventLink(name: "Monkey link", address: "https://example.com/records-monkey")
        let full = UndatedRecord(title: "Monkey Needle full", note: "Full checklist", subtasks: tasks,
                                 attachments: [file], links: [link])
        let single = UndatedRecord(title: "Monkey single", subtasks: [try Subtask(text: "Single unique task")])
        let blank = UndatedRecord(title: "Monkey blank")
        for record in [blank, single, full] {
            try require(await store.saveRecord(record), "could not save fixture \(record.title)")
        }
        await store.discardAttachmentDraft(draftID)
        try require(store.records.map(\.id) == [full.id, single.id, blank.id], "fixture lost insertion order")
        return Fixture(full: full, single: single, blank: blank, event: calendar)
    }

    private func verifyDesktopBrowseAndBurst(_ fixture: Fixture, window: NSWindow) async throws {
        try await select("desktop", "records")
        try await press("desktop.record.\(fixture.full.id)")
        try await expect("desktop.inspector", fixture.full.id.uuidString)
        try await verifyBurst(controlPrefix: "desktop.record.subtask.toggle.", surface: "desktop")

        try await replaceFocusedText("desktop.search", "Monkey Needle", window)
        try await expect("desktop.inspector", fixture.full.id.uuidString)
        try require(controls.frame("desktop.event.\(fixture.event.id)") == nil, "record search exposed date event")
        try await select("desktop", "events")
        try await replaceFocusedText("desktop.search", "dated-only", window)
        try await expect("desktop.inspector", fixture.event.id.uuidString)
        try await verifyMaterialResolutionBlocksSectionChange()
        for (index, scheme) in [ColorScheme.light, .dark, .light].enumerated() {
            visualEnvironment.colorSchemeOverride = scheme
            try await select("desktop", "records")
            try await expect("desktop.search", "Monkey Needle")
            try await expect("desktop.inspector", fixture.full.id.uuidString)
            try await press("desktop.mode")
            try await expect("desktop.mode", index.isMultiple(of: 2) ? "feed" : "collection")
            try require(controls.frame("desktop.record.\(fixture.single.id)") == nil, "record search leaked an unmatched row")
            try await select("desktop", "events")
            try await expect("desktop.search", "dated-only")
            try await expect("desktop.inspector", fixture.event.id.uuidString)
            try require(controls.frame("desktop.record.\(fixture.full.id)") == nil, "event search exposed a record")
        }
        try await select("desktop", "records")
        try await replaceFocusedText("desktop.search", "¥ no such item", window)
        try await wait("desktop no-match record state") {
            controls.frame("desktop.record.empty") != nil && controls.value("desktop.inspector") == nil
        }
        try await replaceFocusedText("desktop.search", "", window)
        try await expect("desktop.inspector", fixture.full.id.uuidString)
        try capture("records-monkey-desktop-after-burst", window)
    }

    private func verifyMaterialResolutionBlocksSectionChange() async throws {
        // This holds the same Store reservation an accepted provider owns until completion.
        try require(store.beginMaterialResolution(), "could not hold event material resolution")
        do {
            defer { store.endMaterialResolution() }
            try await wait("desktop section action disabled while accepted material is resolving") {
                !enabled("desktop.section.records")
            }
            try require(!controls.press("desktop.section.records") && controls.value("desktop.section") == "events",
                        "desktop removed the event surface during material resolution")
        }
        try await wait("desktop restores section navigation after material resolution") { enabled("desktop.section.records") }
    }

    private func verifyBurst(controlPrefix: String, surface: String) async throws {
        let before = store.records
        let tasks = try value(before.first?.subtasks, "\(surface) burst fixture")
        try require(tasks.count == Subtask.maximumCount, "\(surface) burst fixture lost its full checklist")
        var expected = before
        let schedule = [0, 1, 0, 2, 2, 3]
        let writesBefore = try await successfulRecordWrites()
        for index in schedule {
            let id = controlPrefix + tasks[index].id.uuidString
            try require(controls.press(id), "\(surface) did not deliver the registered action for task \(index)")
            expected[0].subtasks[index].isCompleted.toggle()
            await Task.yield()
        }
        try await wait("\(surface) rapid toggles drain in order") {
            !store.hasPendingPersistence && store.records == expected
        }
        try require(try diskRecords() == expected, "\(surface) rapid toggles were not durable or changed neighbors")
        let writesAfter = try await successfulRecordWrites()
        try require(writesAfter - writesBefore == schedule.count, "\(surface) discarded or duplicated rapid checklist toggles")
    }

    private func successfulRecordWrites() async throws -> Int {
        await DiagnosticLog.shared.flushAsync()
        let log = try String(contentsOf: DiagnosticLog.fileURL, encoding: .utf8)
        return log.split(separator: "\n").filter { $0.contains(" records.save success ") }.count
    }

    private func verifyMiniDraft(_ fixture: Fixture, window: NSWindow, desktop: NSWindow) async throws {
        try await select("panel", "records")
        let bytes = try Data(contentsOf: recordsURL)
        try await press("panel.record.edit.\(fixture.full.id)")
        try await expect("editor.subtasks", String(Subtask.maximumCount))
        try require(!enabled("editor.subtask.add") && controls.entries["editor.date"] == nil,
                    "record editor exposed an eleventh task action or a date field")
        try await replaceFocusedText("editor.title", "Cancelled \u{1F9EA} record", window)
        let removed = fixture.full.subtasks[1]
        try await press("editor.subtask.delete.\(removed.id)")
        try await expect("editor.subtasks", String(Subtask.maximumCount - 1))
        try await press("editor.subtask.add")
        try await expect("editor.subtasks", String(Subtask.maximumCount))
        try await wait("empty replacement task disables Save") { !enabled("editor.save") }

        pressStatusItem()
        try await wait("mini draft was hidden by the status item") { !window.isVisible && !window.occlusionState.contains(.visible) }
        _ = try await openDesktop()
        try await wait("desktop observes ownership by the hidden mini draft") {
            desktop.isKeyWindow && controls.entries["desktop.editor-busy"] != nil && !enabled("desktop.record.create")
        }
        try require(editorSession.isPresented && !controls.press("desktop.record.detail.edit"),
                    "desktop could replace a hidden mini editor")
        let reopened = try await openPanel()
        try require(reopened === window && editorSession.isPresented, "return to mini discarded its draft owner")
        try await expect("editor.title", "Cancelled \u{1F9EA} record")
        try await expect("editor.subtasks", String(Subtask.maximumCount))
        try capture("records-monkey-mini-retained-invalid-draft", window)
        try await press("editor.cancel")
        try await wait("mini Cancel releases editor") { !editorSession.hasActiveEditor }
        try require(try Data(contentsOf: recordsURL) == bytes, "invalid or cancelled mini draft changed file bytes")
    }

    private func verifyMiniChecklist(_ fixture: Fixture) async throws {
        let disclosure = "subtasks.disclosure.\(fixture.full.id)"
        let task = fixture.full.subtasks[1]
        let row = "subtask.toggle.\(task.id)"
        if controls.value(disclosure) == "collapsed" { try await press(disclosure) }
        try await expect(disclosure, "expanded")
        let before = store.records
        let bytes = try Data(contentsOf: recordsURL)
        let staleAction = try value(controls.entries[row]?.action, "expanded mini row action")
        let wasCompleted = before.first?.subtasks.first(where: { $0.id == task.id })?.isCompleted == true
        try await press(disclosure)
        try await expect(disclosure, "collapsed")
        try await wait("collapsed mini row removed from targetable controls") { !enabled(row) }
        try require(!controls.press(row), "collapsed mini checklist still exposes an enabled row")
        // A callback captured before collapse still reaches the production action and its own admission check.
        staleAction()
        try await Task.sleep(nanoseconds: 100_000_000)
        try await wait("stale mini callback settles") { !store.hasPendingPersistence }
        try require(try Data(contentsOf: recordsURL) == bytes && store.records == before,
                    "collapsed mini row callback changed a task or wrote record bytes")
        try await press(disclosure)
        try await expect(disclosure, "expanded")
        for desired in [!wasCompleted, wasCompleted] {
            try await press(row)
            try await wait("mini completion writes the requested identity") {
                !store.hasPendingPersistence
                    && store.records.first?.subtasks.first(where: { $0.id == task.id })?.isCompleted == desired
            }
        }
        let saved = try diskRecords()
        try require(store.records == before && saved == before,
                    "mini reverse toggle lost checklist identity, data or order")
        try await verifyMiniWriteFailureAndRetry(taskID: task.id, before: before)
        try await verifyBurst(controlPrefix: "subtask.toggle.", surface: "mini")
    }

    private func verifyMiniWriteFailureAndRetry(taskID: UUID, before: [UndatedRecord]) async throws {
        let row = "subtask.toggle.\(taskID)"
        try await withDeniedRecordWrite { original, backup in
            try await wait("mini checkbox is ready for write denial") { enabled(row) }
            try require(controls.press(row) && controls.press(row), "mini could not deliver two queued toggles")
            let message = AppText.string("record.storageWriteFailed") + AppText.string("store.queuedActionsSkipped")
            try await expect("application.error", message)
            try require(store.records == before && Data(contentsOf: backup) == original,
                        "failed mini toggles published changes or altered the original record bytes")
        }
        var expected = before
        let index = try value(before.first?.subtasks.firstIndex { $0.id == taskID }, "mini write retry task")
        expected[0].subtasks[index].isCompleted.toggle()
        for snapshot in [expected, before] {
            try await press(row)
            try await wait("mini toggle is durable again after storage recovery") {
                !store.hasPendingPersistence && store.records == snapshot && store.error == nil
                    && (try? diskRecords()) == snapshot
            }
        }
    }

    private func verifyMiniEditUsesLatestRecord(_ fixture: Fixture, window: NSWindow) async throws {
        let editID = "panel.record.edit.\(fixture.full.id)"
        let oldEdit = try value(controls.entries[editID]?.action, "mini edit action before checklist mutation")
        let before = try diskRecords()
        var expected = before
        let taskID = try value(expected.first?.subtasks.first?.id, "task for intervening write")
        let toggleID = "subtask.toggle.\(taskID)"
        let oldToggle = try value(controls.entries[toggleID]?.action, "mini checkbox action before section change")
        expected[0].subtasks[0].isCompleted.toggle()
        try await press(toggleID)
        try await wait("checklist change before mini edit") {
            !store.hasPendingPersistence && store.records == expected
        }
        try require(try diskRecords() == expected, "intervening checkbox change was not durable")

        try await select("panel", "events")
        oldToggle()
        oldEdit()
        try require(!editorSession.hasActiveEditor && !store.hasPendingPersistence,
                    "inactive record action opened an editor or queued a write over Events")
        try require(try diskRecords() == expected, "inactive checkbox changed durable records")
        try await select("panel", "records")
        oldEdit()
        try await expect("editor.title", fixture.full.title)
        let title = fixture.full.title + " updated"
        try await replaceFocusedText("editor.title", title, window)
        try await press("editor.save")
        expected[0].title = title
        try await wait("mini title-only save preserves the latest checklist") {
            !store.hasPendingPersistence && !editorSession.hasActiveEditor && store.records == expected
        }
        try require(try diskRecords() == expected, "mini edit restored stale record fields")
    }

    private func verifyWriteFailureAndRetry(_ fixture: Fixture, desktop: NSWindow,
                                            expected: [UndatedRecord]) async throws {
        _ = try await openDesktop()
        try await select("desktop", "records")
        try await press("desktop.record.\(fixture.single.id)")
        try await expect("desktop.inspector", fixture.single.id.uuidString)
        try await press("desktop.record.detail.edit")
        try await wait("desktop owns a native record sheet") { desktop.attachedSheet?.isKeyWindow == true }
        let sheet = try value(desktop.attachedSheet, "native record sheet")
        let title = "Monkey renamed \u{1F344} e\u{0301}"
        try await replaceFocusedText("editor.title", title, sheet)
        try await rejectNextWrite(expected: expected, title: title)
        try await press("editor.save")
        try await wait("native retry committed and dismissed") {
            !store.hasPendingPersistence && !editorSession.hasActiveEditor
                && desktop.attachedSheet == nil && store.records.first(where: { $0.id == fixture.single.id })?.title == title
        }
        var edited = fixture.single
        edited.title = title
        let saved = try diskRecords()
        try require(store.records == [expected[0], edited, expected[2]] && saved == store.records,
                    "native retry changed a neighbor, checklist identity or creation order")
        // The registry can retain the dismissed sheet's last banner value. The capture
        // independently shows how the current Store error state renders.
        try require(store.error == nil, "successful retry left an active storage error")
        try capture("records-monkey-desktop-after-retry", desktop)
    }

    private func rejectNextWrite(expected: [UndatedRecord], title: String) async throws {
        try await withDeniedRecordWrite { original, backup in
            try await press("editor.save")
            try await wait("native storage denial leaves the original draft retryable") {
                store.error != nil && controls.value("desktop.error") == store.error
                    && !store.hasPendingPersistence && editorSession.desktopIsPresented && enabled("editor.save")
            }
            try await expect("editor.title", title)
            try require(store.records == expected && Data(contentsOf: backup) == original,
                        "failed record write published changes, moved records or damaged original bytes")
        }
    }

    private func withDeniedRecordWrite(_ exercise: (Data, URL) async throws -> Void) async throws {
        let fileManager = FileManager.default
        let backup = recordsURL.appendingPathExtension("monkey-backup")
        try require(!fileManager.fileExists(atPath: backup.path), "record write denial backup already exists")
        let bytes = try Data(contentsOf: recordsURL)
        try fileManager.moveItem(at: recordsURL, to: backup)
        var madeDirectory = false
        defer {
            if madeDirectory { try? fileManager.removeItem(at: recordsURL) }
            if fileManager.fileExists(atPath: backup.path) { try? fileManager.moveItem(at: backup, to: recordsURL) }
        }
        try fileManager.createDirectory(at: recordsURL, withIntermediateDirectories: false)
        madeDirectory = true
        try await exercise(bytes, backup)
        try fileManager.removeItem(at: recordsURL)
        madeDirectory = false
        try fileManager.moveItem(at: backup, to: recordsURL)
    }

    private func verifyDeletion(_ fixture: Fixture, desktop: NSWindow) async throws {
        let bytes = try Data(contentsOf: recordsURL)
        _ = try await openPanel()
        try await select("panel", "records")
        try await press("panel.record.edit.\(fixture.blank.id)")
        try await expect("editor.title", fixture.blank.title)
        try await press("record.delete")
        try await press("record.delete.cancel")
        try await expect("editor.title", fixture.blank.title)
        try await press("editor.cancel")
        try await wait("mini record delete Cancel has closed the draft") { !editorSession.hasActiveEditor }
        try require(try Data(contentsOf: recordsURL) == bytes, "mini delete Cancel changed record bytes")
        _ = try await openDesktop()
        try await select("desktop", "records")
        try await press("desktop.record.\(fixture.blank.id)")
        try await expect("desktop.inspector", fixture.blank.id.uuidString)
        try await press("desktop.record.detail.delete")
        try await expect("desktop.record.delete.confirmation", fixture.blank.title)
        try await press("desktop.record.delete.confirm")
        try await wait("desktop deletes only the confirmed record") {
            !store.hasPendingPersistence && store.records.map(\.id) == [fixture.full.id, fixture.single.id]
        }
        try await expect("desktop.inspector", fixture.full.id.uuidString)
        try capture("records-monkey-desktop-after-delete", desktop)
    }

    private func openDesktop() async throws -> NSWindow {
        showDesktop()
        try await wait("desktop window is visible and key") { desktopWindow()?.isVisible == true && desktopWindow()?.isKeyWindow == true }
        return try value(desktopWindow(), "desktop window")
    }

    private func openPanel() async throws -> NSWindow {
        try await wait("status item is attached to a display") { statusButton()?.window?.screen != nil }
        showPanel()
        try await wait("mini-panel is visible and key") { panelWindow()?.isVisible == true && panelWindow()?.isKeyWindow == true }
        return try value(panelWindow(), "mini-panel")
    }

    private func diskRecords() throws -> [UndatedRecord] {
        try JSONDecoder().decode([UndatedRecord].self, from: Data(contentsOf: recordsURL))
    }

    private func select(_ surface: String, _ section: String) async throws {
        if controls.value("\(surface).section") != section {
            try await press("\(surface).section.\(section)")
        }
        try await expect("\(surface).section", section)
    }

    private func enabled(_ id: String) -> Bool { controls.entries[id]?.isEnabled == true }

    private func press(_ id: String) async throws {
        try await wait("enabled \(id)") { enabled(id) }
        try require(controls.press(id), "could not activate \(id)")
    }

    private func expect(_ id: String, _ value: String) async throws {
        try await wait("\(id) = \(value)") { controls.value(id) == value }
    }

    private func wait(_ description: String, until condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while !condition() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, "timeout: \(description)")
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    private func require(_ condition: Bool, _ failure: String) throws {
        if !condition { throw Failure(message: failure) }
    }

    private func value<Value>(_ value: Value?, _ description: String) throws -> Value {
        guard let value else { throw Failure(message: "missing \(description)") }
        return value
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
