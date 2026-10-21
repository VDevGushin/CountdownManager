import Foundation
import CountdownCore

extension CountdownCoreTests {
    func testRejectedEventEditsPreserveSavedSnapshot() throws {
        let today = day(2026, 9, 5)
        let event = Countdown(
            title: "Saved title", note: "Saved note", date: day(2026, 9, 7), emoji: "🎉",
            subtasks: [try Subtask(text: "Done", isCompleted: true), try Subtask(text: "Pending")],
            showsWeather: true
        )
        let favorite = Countdown(title: "Favorite", date: day(2026, 9, 8), emoji: "")
        var data = CountdownData()
        try data.save(event, primary: false, today: today)
        try data.save(favorite, primary: true, today: today)
        let saved = data

        var invalidEdits: [Countdown] = []
        var edited = event
        edited.title = " \n\t "
        invalidEdits.append(edited)
        edited = event
        edited.note = String(repeating: "👨‍👩‍👧‍👦", count: 151)
        invalidEdits.append(edited)
        edited = event
        edited.date = day(2026, 9, 4)
        invalidEdits.append(edited)
        edited = event
        edited.subtasks[1].text = " "
        invalidEdits.append(edited)
        edited = event
        edited.subtasks[1].text = String(repeating: "é", count: 51)
        invalidEdits.append(edited)
        edited = event
        edited.subtasks = try (1...11).map { try Subtask(text: "Task \($0)") }
        invalidEdits.append(edited)

        for draft in invalidEdits {
            try expectCoreValidationFailure { try data.save(draft, primary: true, today: today) }
            expectCoreRegression(data == saved, "A rejected edit must preserve all events and the selected favorite")
        }
        var invalidFavorite = favorite
        invalidFavorite.title = " "
        try expectCoreValidationFailure { try data.save(invalidFavorite, primary: false, today: today) }
        expectCoreRegression(data == saved)
    }

    func testStaleAndCrossEventSubtaskActionsPreserveNeighbors() throws {
        let today = day(2026, 9, 5)
        let first = Countdown(
            title: "First", date: day(2026, 9, 7), emoji: "",
            subtasks: [try Subtask(text: "First task", isCompleted: true)]
        )
        let second = Countdown(
            title: "Second", date: first.date, emoji: "🎉",
            subtasks: [try Subtask(text: "Second task")]
        )
        var data = CountdownData()
        try data.save(first, primary: true, today: today)
        try data.save(second, primary: false, today: today)
        let saved = data
        let foreignID = second.subtasks[0].id
        for subtaskID in [foreignID, UUID()] {
            try expectCoreValidationFailure {
                try data.toggleSubtask(eventID: first.id, subtaskID: subtaskID, today: today)
            }
            try expectCoreValidationFailure {
                try data.editSubtask(eventID: first.id, subtaskID: subtaskID, text: "Wrong target", today: today)
            }
            try expectCoreValidationFailure {
                try data.deleteSubtask(eventID: first.id, subtaskID: subtaskID, today: today)
            }
            expectCoreRegression(data == saved, "A stale/foreign subtask action must not affect either event")
        }

        data.delete(first.id, today: today)
        let afterDeletion = data
        try expectCoreValidationFailure {
            _ = try data.addSubtask(to: first.id, text: "Stale action", today: today)
        }
        try expectCoreValidationFailure {
            try data.toggleSubtask(eventID: first.id, subtaskID: first.subtasks[0].id, today: today)
        }
        try expectCoreValidationFailure {
            try data.editSubtask(eventID: first.id, subtaskID: first.subtasks[0].id, text: "Stale edit", today: today)
        }
        try expectCoreValidationFailure {
            try data.deleteSubtask(eventID: first.id, subtaskID: first.subtasks[0].id, today: today)
        }
        expectCoreRegression(data == afterDeletion && data.items == [second] && data.primaryID == nil)
    }

    func testFullChecklistDeleteReplaceAndReopenRoundTrip() throws {
        let today = day(2026, 9, 5)
        let tasks = try (1...10).map { try Subtask(text: "Task \($0)", isCompleted: $0.isMultiple(of: 2)) }
        let event = Countdown(title: "Checklist", date: day(2026, 9, 7), emoji: "", subtasks: tasks)
        var data = CountdownData()
        try data.save(event, primary: true, today: today)
        let removed = tasks[4]
        try data.deleteSubtask(eventID: event.id, subtaskID: removed.id, today: today)
        let newID = try data.addSubtask(to: event.id, text: "Replacement", today: today)
        let expected = tasks.filter { $0.id != removed.id }
        expectCoreRegression(Array(data.items[0].subtasks.dropLast()) == expected)
        expectCoreRegression(data.items[0].subtasks.last?.id == newID && data.items[0].subtasks.last?.isCompleted == false)
        let beforeRejection = data
        try expectCoreValidationFailure { _ = try data.addSubtask(to: event.id, text: "Eleventh", today: today) }
        expectCoreRegression(data == beforeRejection)

        data = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
        try data.toggleSubtask(eventID: event.id, subtaskID: tasks[1].id, today: today)
        var reopened = expected
        reopened[1].isCompleted = false
        expectCoreRegression(Array(data.items[0].subtasks.dropLast()) == reopened)
        expectCoreRegression(data.items[0].subtasks.map(\.id) == expected.map(\.id) + [newID])
        expectCoreRegression(data.primaryID == event.id)
        print("PASS core regression: rejected edits, stale subtask actions and full-checklist replacement")
    }

    func testPersistedEditsAndExpirySurviveFreshRepository() async throws {
        let directory = regressionDirectory("Lifecycle")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("nested/countdowns.json")
        let repository = CountdownRepository(fileURL: fileURL)
        expectCoreRegression(try await repository.load() == CountdownData())
        expectCoreRegression(!FileManager.default.fileExists(atPath: directory.path), "Reading missing data must not create files")
        let today = day(2026, 9, 5)
        let legacy = Countdown(
            title: "Legacy", note: "  " + String(repeating: "🙂", count: 180) + "\n ",
            date: today, emoji: "📅", subtasks: [try Subtask(text: "Pending")], showsWeather: true
        )
        let future = Countdown(title: "Survivor", date: day(2026, 9, 9), emoji: "")
        var data = CountdownData()
        data.items = [legacy, future]
        data.primaryID = legacy.id
        expectCoreRegression(try await repository.save(data, revision: 1))

        let reopened = CountdownRepository(fileURL: fileURL)
        data = try await reopened.load()
        var edited = data.items[0]
        edited.title = "Renamed without changing legacy note"
        try data.save(edited, primary: true, today: today)
        try data.toggleSubtask(eventID: legacy.id, subtaskID: legacy.subtasks[0].id, today: today)
        expectCoreRegression(try await reopened.save(data, revision: 1))
        let afterEdit = try await CountdownRepository(fileURL: fileURL).load()
        expectCoreRegression(afterEdit == data && afterEdit.items[0].note == legacy.note)
        expectCoreRegression(afterEdit.items[0].showsWeather && afterEdit.items[0].subtasks[0].isCompleted)

        data.normalize(today: day(2026, 9, 6))
        expectCoreRegression(data.items == [future] && data.primaryID == nil)
        expectCoreRegression(try await reopened.save(data, revision: 2))
        expectCoreRegression(try await CountdownRepository(fileURL: fileURL).load() == data)
    }

    func testRepositoryRejectedRevisionDoesNotDestroyOrBlockData() async throws {
        let directory = regressionDirectory("RejectedWrite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("countdowns.json")
        let repository = CountdownRepository(fileURL: fileURL)
        var good = CountdownData()
        try good.save(Countdown(title: "Saved", date: day(2026, 9, 7), emoji: ""), primary: true, today: day(2026, 9, 5))
        expectCoreRegression(try await repository.save(good, revision: 1))
        let originalBytes = try Data(contentsOf: fileURL)
        var invalid = good
        invalid.items[0].subtasks = [try Subtask(text: "Valid initially")]
        invalid.items[0].subtasks[0].text = " \n "
        do {
            _ = try await repository.save(invalid, revision: 100)
            preconditionFailure("Invalid newer snapshot must be rejected")
        } catch is CountdownError {}
        expectCoreRegression(try Data(contentsOf: fileURL) == originalBytes)
        expectCoreRegression(try await repository.load() == good)
        good.items[0].title = "Retry after validation failure"
        expectCoreRegression(try await repository.save(good, revision: 2), "A rejected revision must not block a valid retry")
        expectCoreRegression(try await CountdownRepository(fileURL: fileURL).load() == good)
        expectCoreRegression(!(try await repository.save(CountdownData(), revision: 1)))
        expectCoreRegression(try await repository.load() == good)
    }

    func testRepositoryFilesystemFailureCanRetryWithoutDataLoss() async throws {
        let directory = regressionDirectory("FilesystemRetry")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blockedDirectory = directory.appendingPathComponent("blocked")
        let sentinel = Data("unrelated file".utf8)
        try sentinel.write(to: blockedDirectory)
        let fileURL = blockedDirectory.appendingPathComponent("countdowns.json")
        let repository = CountdownRepository(fileURL: fileURL)
        var data = CountdownData()
        try data.save(Countdown(title: "Retry me", date: day(2026, 9, 7), emoji: ""), primary: false, today: day(2026, 9, 5))
        do {
            _ = try await repository.save(data, revision: 100)
            preconditionFailure("A regular file cannot be used as the parent directory")
        } catch {}
        expectCoreRegression(try Data(contentsOf: blockedDirectory) == sentinel)
        try FileManager.default.removeItem(at: blockedDirectory)
        expectCoreRegression(try await repository.save(data, revision: 1), "An unsuccessful write must not advance the revision guard")
        expectCoreRegression(try await CountdownRepository(fileURL: fileURL).load() == data)

        let corruptBytes = Data("{\"items\":[".utf8)
        try corruptBytes.write(to: fileURL)
        do {
            _ = try await CountdownRepository(fileURL: fileURL).load()
            preconditionFailure("Corrupt JSON must fail instead of silently becoming an empty event list")
        } catch is DecodingError {}
        expectCoreRegression(try Data(contentsOf: fileURL) == corruptBytes)
        print("PASS core regression: fresh-repository lifecycle, rejected revisions, filesystem retry and corrupt JSON preservation")
    }
}

private func expectCoreValidationFailure(_ operation: () throws -> Void) throws {
    do {
        try operation()
        preconditionFailure("Expected a rejected domain mutation")
    } catch is CountdownError {}
}

private func regressionDirectory(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("CountdownCoreRegression-\(name)-\(UUID().uuidString)", isDirectory: true)
}

private func expectCoreRegression(_ value: Bool, _ message: String = "Core regression failed") {
    precondition(value, message)
}
