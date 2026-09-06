import Foundation
import CountdownCore
import CountdownManagerUI

@main
enum UIChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CountdownManagerUIChecks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let today = Day(Date())
        let yesterdayDate = Day.calendar.date(byAdding: .day, value: -1, to: today.date())!
        let tomorrowDate = Day.calendar.date(byAdding: .day, value: 1, to: today.date())!
        let twoDaysDate = Day.calendar.date(byAdding: .day, value: 2, to: today.date())!
        let activeOne = try Subtask(text: "First active")
        let completedOne = try Subtask(text: "First completed", isCompleted: true)
        let activeTwo = try Subtask(text: "Second active")
        let completedTwo = try Subtask(text: "Second completed", isCompleted: true)
        let activeThree = try Subtask(text: "Third active")
        let expiredItem = Countdown(title: "Expired UI", date: Day(yesterdayDate), emoji: "⌛️")
        let todayItem = Countdown(
            title: "Today UI",
            note: "Visible note",
            date: today,
            emoji: "☀️",
            subtasks: [activeOne, completedOne, activeTwo, completedTwo, activeThree]
        )
        let futureItem = Countdown(title: "Future UI", note: "Editable note", date: Day(tomorrowDate), emoji: "🚀")
        var data = CountdownData()
        data.items = [expiredItem, todayItem, futureItem]
        data.primaryID = futureItem.id

        // User-facing terminology and empty state.
        precondition(EventUIStrings.addEvent == "Добавить событие")
        precondition(EventUIStrings.newEvent == "Новое событие")
        precondition(EventUIStrings.editEvent == "Редактировать событие")
        precondition(EventUIStrings.deleteEvent == "Удалить событие?")
        precondition(EventUIStrings.emptyTitle == "Пока нет событий")
        precondition(EventUIStrings.emptyMessage.contains("Добавь событие и выбери дату"))

        // Primary first, then stable date order; expired events are absent.
        precondition(activeCountdowns(in: data, today: today).map(\.id) == [futureItem.id, todayItem.id])
        let todayRow = CountdownRowPresentation(item: todayItem, today: today, primaryID: data.primaryID)
        precondition(todayRow.note == "Visible note")
        precondition(todayRow.remainingLabel == "Сегодня")
        precondition(todayRow.dateAndRemainingLabel == "\(humanDateLabel(today)) · Сегодня")
        precondition(humanDateLabel(Day(DateComponents(calendar: Day.calendar, year: 2027, month: 5, day: 1).date!)) == "1 мая 2027")
        precondition(todayRow.isToday)
        precondition(!todayRow.isPrimary)
        precondition(todayRow.completionLabel == "2/5")
        precondition(todayRow.activeSubtasks.map(\.id) == [activeOne.id, activeTwo.id, activeThree.id])
        precondition(todayRow.completedSubtasks.map(\.id) == [completedOne.id, completedTwo.id])
        precondition(subtaskDisclosureLabel(isExpanded: false, completion: "2/5") == "▸ 2/5")
        precondition(subtaskDisclosureLabel(isExpanded: true, completion: "2/5") == "▾ 2/5")

        let emptyRow = CountdownRowPresentation(item: futureItem, today: today, primaryID: data.primaryID)
        precondition(emptyRow.completionLabel == nil) // No disclosure and no 0/0.
        precondition(emptyRow.dateAndRemainingLabel == "\(humanDateLabel(Day(tomorrowDate))) · 1 день")

        // Creation versus editing an event on Today.
        precondition(editorCanSave(
            title: "Future UI",
            note: String(repeating: "я", count: 280),
            date: futureItem.date,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "Today is invalid for creation",
            note: "",
            date: today,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(editorCanSave(
            title: "Today is editable",
            note: "Changed",
            date: today,
            emoji: "🎂",
            subtasks: todayItem.subtasks,
            today: today,
            originalDate: today
        ))
        precondition(editorCanSave(
            title: "Move Today forward",
            note: "",
            date: Day(twoDaysDate),
            emoji: "🎂",
            subtasks: todayItem.subtasks,
            today: today,
            originalDate: today
        ))
        precondition(!editorCanSave(
            title: "Invalid note",
            note: String(repeating: "я", count: 281),
            date: futureItem.date,
            emoji: futureItem.emoji,
            today: today
        ))
        precondition(!editorCanSave(
            title: "Invalid subtask",
            note: "",
            date: futureItem.date,
            emoji: futureItem.emoji,
            subtasks: [invalidDraft()],
            today: today
        ))

        // The event editor creates active subtasks and targets the newest stable ID for focus.
        var newDraft = EventEditorDraft(item: nil)
        guard case let .subtask(firstNewID)? = newDraft.addSubtask() else {
            fatalError("The first new subtask must receive a focus target")
        }
        precondition(newDraft.subtasks.count == 1)
        precondition(newDraft.subtasks[0].id == firstNewID)
        precondition(!newDraft.subtasks[0].isCompleted)
        newDraft.subtasks[0].text = "First draft"
        guard case let .subtask(secondNewID)? = newDraft.addSubtask() else {
            fatalError("The second new subtask must receive a focus target")
        }
        precondition(secondNewID != firstNewID)
        precondition(newDraft.subtasks.last?.id == secondNewID)
        precondition(newDraft.subtasks.last?.isCompleted == false)
        newDraft.subtasks[1].text = "Second draft"
        let savedNewDraft = newDraft.countdown(id: UUID(), date: Day(tomorrowDate))
        precondition(savedNewDraft.subtasks.map(\.isCompleted) == [false, false])

        // Editing text never changes an existing completion state.
        var existingDraft = EventEditorDraft(item: todayItem)
        existingDraft.subtasks[0].text = "Active edited"
        existingDraft.subtasks[1].text = "Completed edited"
        let editedCountdown = existingDraft.countdown(id: todayItem.id, date: today)
        precondition(editedCountdown.subtasks[0].text == "Active edited")
        precondition(!editedCountdown.subtasks[0].isCompleted)
        precondition(editedCountdown.subtasks[1].text == "Completed edited")
        precondition(editedCountdown.subtasks[1].isCompleted)

        // Emoji controls are isolated from every other user-text field.
        let originalTitle = existingDraft.title
        let originalNote = existingDraft.note
        let originalSubtasks = existingDraft.subtasks
        precondition(EventEmojiCatalog.presets == ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️"])
        precondition(EventEmojiCatalog.all.count == 48)
        precondition(EventEmojiCatalog.all.allSatisfy(CountdownData.isEmoji))
        precondition(existingDraft.title == originalTitle)
        precondition(existingDraft.note == originalNote)
        precondition(existingDraft.subtasks == originalSubtasks)
        precondition(existingDraft.replaceEmoji(with: "🏖️"))
        precondition(existingDraft.emoji == "🏖️")
        precondition(existingDraft.title == originalTitle)
        precondition(existingDraft.note == originalNote)
        precondition(existingDraft.subtasks == originalSubtasks)
        precondition(!existingDraft.replaceEmoji(with: "🎉😎"))
        precondition(existingDraft.emoji == "🏖️")
        precondition(EditorLayout.focusRingInset >= 3)

        // Deterministic quick-operation state transitions used by card controls.
        var quickData = CountdownData()
        try quickData.save(futureItem, primary: true, today: today)
        let quickID = try quickData.addSubtask(to: futureItem.id, text: "Quick add", today: today)
        var quickRow = CountdownRowPresentation(item: quickData.items[0], today: today, primaryID: quickData.primaryID)
        precondition(quickRow.completionLabel == "0/1")
        precondition(quickRow.activeSubtasks.map(\.id) == [quickID])
        try quickData.editSubtask(eventID: futureItem.id, subtaskID: quickID, text: "Quick edit", today: today)
        precondition(quickData.items[0].subtasks[0].text == "Quick edit")
        try quickData.toggleSubtask(eventID: futureItem.id, subtaskID: quickID, today: today)
        quickRow = CountdownRowPresentation(item: quickData.items[0], today: today, primaryID: quickData.primaryID)
        precondition(quickRow.activeSubtasks.isEmpty)
        precondition(quickRow.completedSubtasks.map(\.id) == [quickID])
        precondition(quickRow.completionLabel == "1/1")
        try quickData.toggleSubtask(eventID: futureItem.id, subtaskID: quickID, today: today)
        quickRow = CountdownRowPresentation(item: quickData.items[0], today: today, primaryID: quickData.primaryID)
        precondition(quickRow.activeSubtasks.map(\.id) == [quickID])
        precondition(quickRow.completedSubtasks.isEmpty)
        try quickData.deleteSubtask(eventID: futureItem.id, subtaskID: quickID, today: today)
        quickRow = CountdownRowPresentation(item: quickData.items[0], today: today, primaryID: quickData.primaryID)
        precondition(quickRow.completionLabel == nil) // Last deletion removes the disclosure state.
        for number in 1...5 {
            _ = try quickData.addSubtask(to: futureItem.id, text: "Task \(number)", today: today)
        }
        precondition(quickData.items[0].subtasks.count == 5)
        do {
            _ = try quickData.addSubtask(to: futureItem.id, text: "Sixth", today: today)
            fatalError("The sixth quick subtask must be rejected")
        } catch {}

        // Collapse state is separate from countdown JSON and survives a new persistence instance.
        let suiteName = "CountdownManagerUIChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let firstDisclosure = SubtaskDisclosurePersistence(defaults: defaults)
        precondition(firstDisclosure.isExpanded(eventID: todayItem.id))
        firstDisclosure.setExpanded(false, eventID: todayItem.id)
        precondition(firstDisclosure.isExpanded(eventID: futureItem.id))
        let restoredDisclosure = SubtaskDisclosurePersistence(defaults: defaults)
        precondition(!restoredDisclosure.isExpanded(eventID: todayItem.id))
        restoredDisclosure.setExpanded(true, eventID: todayItem.id)
        precondition(firstDisclosure.isExpanded(eventID: todayItem.id))
        restoredDisclosure.remove(eventID: todayItem.id)
        precondition(firstDisclosure.isExpanded(eventID: todayItem.id))

        // Per-event disclosure objects keep stable identity without coupling event states.
        firstDisclosure.setExpanded(false, eventID: todayItem.id)
        let disclosureCache = await MainActor.run {
            SubtaskDisclosureCache(persistence: firstDisclosure)
        }
        let cachedToday = await MainActor.run { disclosureCache.state(for: todayItem.id) }
        let cachedTodayAgain = await MainActor.run { disclosureCache.state(for: todayItem.id) }
        let cachedFuture = await MainActor.run { disclosureCache.state(for: futureItem.id) }
        precondition(cachedToday === cachedTodayAgain)
        precondition(cachedToday !== cachedFuture)
        let cachedValuesAreIndependent = await MainActor.run {
            !cachedToday.isExpanded && cachedFuture.isExpanded
        }
        let initialCachedIDsAreCorrect = await MainActor.run {
            disclosureCache.cachedEventIDs == Set([todayItem.id, futureItem.id])
        }
        precondition(cachedValuesAreIndependent)
        precondition(initialCachedIDsAreCorrect)

        // Removing an event clears both the cached object and its persisted value.
        await MainActor.run { disclosureCache.remove(eventID: todayItem.id) }
        let removedCachedID = await MainActor.run {
            disclosureCache.cachedEventIDs == Set([futureItem.id])
        }
        precondition(removedCachedID)
        let restartedCache = await MainActor.run {
            SubtaskDisclosureCache(persistence: SubtaskDisclosurePersistence(defaults: defaults))
        }
        let restartedValuesAreExpanded = await MainActor.run {
            restartedCache.state(for: todayItem.id).isExpanded
                && restartedCache.state(for: futureItem.id).isExpanded
        }
        precondition(restartedValuesAreExpanded)

        // Menu bar contains only the primary emoji and day count / Today.
        precondition(statusBarTitle(data: data, today: today) == "🚀 1 день")
        var farFuture = CountdownData()
        let in238Days = Day.calendar.date(byAdding: .day, value: 238, to: today.date())!
        let farEvent = Countdown(title: "Hidden from menu bar", date: Day(in238Days), emoji: "☀️")
        farFuture.items = [farEvent]
        farFuture.primaryID = farEvent.id
        precondition(statusBarTitle(data: farFuture, today: today) == "☀️ 238 дней")
        data.primaryID = todayItem.id
        precondition(statusBarTitle(data: data, today: today) == "☀️ Сегодня")
        precondition(!statusBarTitle(data: data, today: today).contains(todayItem.title))
        precondition(statusBarTitle(data: CountdownData(), today: today) == "◷ Countdown")
        var expiredOnly = CountdownData()
        expiredOnly.items = [expiredItem]
        expiredOnly.primaryID = expiredItem.id
        precondition(activeCountdowns(in: expiredOnly, today: today).isEmpty)
        precondition(statusBarTitle(data: expiredOnly, today: today) == "◷ Countdown")

        // Renaming does not reorder equal dates.
        let equalA = Countdown(title: "Zulu", date: Day(twoDaysDate), emoji: "🎉")
        let equalB = Countdown(title: "Alpha", date: Day(twoDaysDate), emoji: "🎂")
        data.items = [equalA, equalB]
        data.primaryID = nil
        precondition(activeCountdowns(in: data, today: today).map(\.id) == [equalA.id, equalB.id])
        data.items[0].title = "Aardvark"
        precondition(activeCountdowns(in: data, today: today).map(\.id) == [equalA.id, equalB.id])

        let fileURL = directory.appendingPathComponent("countdowns.json")
        let repository = CountdownRepository(fileURL: fileURL)
        let didSave = try await repository.save(data, revision: 1)
        let loaded = try await repository.load()
        precondition(didSave)
        precondition(loaded == data)

        print("PASS UI state: Event terminology, human date/countdown, empty state, no 0/0, disclosure 2/5, grouping and completed state, editor focus/active-subtask/emoji isolation, quick CRUD/toggle/limit, collapse persistence, Today editor, stable event order and menu-bar presentation")
    }

    private static func invalidDraft() -> Subtask {
        var draft = try! Subtask(text: "Temporary")
        draft.text = "   "
        return draft
    }
}
