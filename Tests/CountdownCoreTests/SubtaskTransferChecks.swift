import CountdownCore
import Foundation

func testSubtaskTransferPreservesContentAndIdentity() throws {
    let today = transferCheckDay(2026, 11, 16)
    let tomorrow = transferCheckDay(2026, 11, 17)
    let tasks = [try Subtask(text: "First"), try Subtask(text: "Move this"),
                 try Subtask(text: "Completed", isCompleted: true)]
    let file = try EventAttachment(name: "route.pdf", byteCount: 12)
    let link = EventLink(name: "Route", address: "https://example.com/route")
    let source = Countdown(title: "Source", note: String(repeating: "я", count: 180), date: today,
                           emoji: "🏍️", subtasks: tasks, keepsAfterDate: true,
                           attachments: [file], links: [link])
    let targetTask = try Subtask(text: "Keep target task", isCompleted: true)
    let target = Countdown(title: "Target", note: "Keep target", date: tomorrow, emoji: "",
                           subtasks: [targetTask], showsWeather: true, keepsAfterDate: true)
    let neighbor = Countdown(title: "Neighbor", date: tomorrow, emoji: "")
    var data = CountdownData()
    data.items = [source, target, neighbor]
    data.primaryID = source.id
    let result = try data.transferSubtask(from: source.id, subtaskID: tasks[1].id,
                                          to: target.id, on: tomorrow, today: today)
    var expectedSource = source
    expectedSource.subtasks.remove(at: 1)
    var expectedTarget = target
    expectedTarget.subtasks.append(tasks[1])
    precondition(data.items == [expectedSource, expectedTarget, neighbor])
    precondition(data.primaryID == source.id && result == expectedTarget)
    let restored = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
    precondition(restored == data, "The same task identity and legacy metadata must survive JSON without duplication")

    let sameDateResult = try data.transferSubtask(from: target.id, subtaskID: tasks[1].id,
                                                  to: neighbor.id, on: tomorrow, today: today)
    precondition(sameDateResult.subtasks == [tasks[1]], "Another event on the same date is a valid destination")
    print("PASS subtask transfer core: exact task identity/text/completion, neighboring order, source/target metadata, favorite and JSON")
}

func testSubtaskTransferCreatesStandardDayAndRetainsSource() throws {
    let yesterday = transferCheckDay(2026, 12, 31)
    let today = transferCheckDay(2027, 1, 1)
    let nextDay = transferCheckDay(2027, 1, 2)
    let task = try Subtask(text: "From retained event")
    let retained = Countdown(title: "Retained", date: yesterday, emoji: "", subtasks: [task], keepsAfterDate: true)
    var data = CountdownData()
    data.items = [retained]
    data.primaryID = retained.id
    let destination = try data.transferSubtask(from: retained.id, subtaskID: task.id,
                                               to: nil, on: today, today: today)
    precondition(destination.date == today && destination.title == "Пятница")
    precondition(destination.isDay && destination.usesAutomaticTitle && destination.showsWeather)
    precondition(!destination.keepsAfterDate && destination.emoji.isEmpty && destination.note == nil)
    precondition(destination.attachments.isEmpty && destination.links.isEmpty && destination.subtasks == [task])
    precondition(data.items.count == 2 && data.items[0].id == retained.id && data.items[0].subtasks.isEmpty)
    precondition(data.items[0].keepsAfterDate && data.primaryID == retained.id)
    let newDestination = try data.transferSubtask(from: destination.id, subtaskID: task.id,
                                                  to: nil, on: nextDay, today: today)
    precondition(newDestination.title == "Суббота" && newDestination.date == nextDay)
    precondition(data.items.first { $0.id == destination.id }?.subtasks.isEmpty == true,
                 "Moving the final task keeps the available source event")
}

func testSubtaskTransferRejectionsPreserveWholeSnapshot() throws {
    let today = transferCheckDay(2026, 11, 16)
    let tomorrow = transferCheckDay(2026, 11, 17)
    let past = transferCheckDay(2026, 11, 15)
    let task = try Subtask(text: "Move")
    let done = try Subtask(text: "Done", isCompleted: true)
    let source = Countdown(title: "Source", date: today, emoji: "", subtasks: [task, done])
    let target = Countdown(title: "Target", date: tomorrow, emoji: "",
                           subtasks: try (1...10).map { try Subtask(text: "Done \($0)", isCompleted: true) })
    let expired = Countdown(title: "Expired", date: past, emoji: "", subtasks: [try Subtask(text: "Old")])
    var baseline = CountdownData()
    baseline.items = [source, target, expired]
    baseline.primaryID = source.id
    let attempts: [(UUID, UUID, UUID?, Day)] = [
        (source.id, task.id, target.id, tomorrow),
        (source.id, done.id, nil, transferCheckDay(2026, 11, 18)),
        (source.id, task.id, source.id, today),
        (source.id, task.id, nil, tomorrow),
        (source.id, task.id, target.id, today),
        (source.id, task.id, nil, past),
        (UUID(), task.id, target.id, tomorrow),
        (source.id, UUID(), target.id, tomorrow),
        (source.id, task.id, UUID(), tomorrow),
        (expired.id, expired.subtasks[0].id, nil, transferCheckDay(2026, 11, 18))
    ]
    for (eventID, subtaskID, targetID, day) in attempts {
        var candidate = baseline
        do {
            _ = try candidate.transferSubtask(from: eventID, subtaskID: subtaskID,
                                               to: targetID, on: day, today: today)
            preconditionFailure("Invalid or stale transfer must be rejected")
        } catch {
            precondition(candidate == baseline,
                         "Rejection must preserve both events and unrelated expired data without normalization")
        }
    }
    var capacity = baseline
    capacity.items[1].subtasks.removeLast()
    let filled = try capacity.transferSubtask(from: source.id, subtaskID: task.id,
                                              to: target.id, on: tomorrow, today: today)
    precondition(filled.subtasks.count == 10 && filled.subtasks.last == task)
    let completedSnapshot = capacity
    do {
        _ = try capacity.transferSubtask(from: source.id, subtaskID: task.id,
                                          to: target.id, on: tomorrow, today: today)
        preconditionFailure("A repeated transfer must not duplicate its task")
    } catch {
        precondition(capacity == completedSnapshot)
    }
    var legacyCollision = baseline
    legacyCollision.items[1].subtasks = [try Subtask(id: task.id, text: "Legacy child", isCompleted: true)]
    legacyCollision = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(legacyCollision))
    let collisionSnapshot = legacyCollision
    do {
        _ = try legacyCollision.transferSubtask(from: source.id, subtaskID: task.id,
                                                 to: target.id, on: tomorrow, today: today)
        preconditionFailure("A legacy destination with the same child UUID must not gain duplicate row identities")
    } catch SubtaskTransferError.destinationContainsSubtask {
        precondition(legacyCollision == collisionSnapshot)
    }
    print("PASS subtask transfer guards: completed/missing/foreign tasks, source expiry, occupied/date-changed destinations, same event, 9/10 capacity and retry")
}

private func transferCheckDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return Day(calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar)
}
