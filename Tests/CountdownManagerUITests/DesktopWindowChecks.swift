import Foundation
import CountdownCore
import CountdownManagerUI
import SwiftUI

func testDesktopPresentation() throws {
    let today = Day(DateComponents(calendar: Day.calendar, year: 2026, month: 10, day: 23).date!)
    let tomorrow = Day(Day.calendar.date(byAdding: .day, value: 1, to: today.date())!)
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    let preparation = try Subtask(text: "Проверить документы", isCompleted: true)
    let expired = Countdown(title: "Старое событие", date: yesterday, emoji: "")
    let first = Countdown(title: "Встреча", note: "Билеты и документы", date: today, emoji: "")
    precondition(desktopEventAccessibilityLabel(first) == "Открыть событие: Встреча")
    var materialEvent = first
    materialEvent.links = (0..<10).map { EventLink(address: "https://example.com/\($0)") }
    precondition(desktopEventAccessibilityLabel(materialEvent) == "Открыть событие: Встреча. Ссылки: 10")
    materialEvent.attachments = [try EventAttachment(name: "Билет.pdf", byteCount: 42)]
    precondition(desktopEventAccessibilityLabel(materialEvent) == "Открыть событие: Встреча. Вложения: 1. Ссылки: 10")

    let second = Countdown(title: "Поездка", note: "Сохранённая заметка", date: today, emoji: "🚗")
    let favorite = Countdown(
        title: "Отпуск", date: tomorrow, emoji: "🌴", subtasks: [preparation], showsWeather: true
    )
    let items = [favorite, expired, first, second]
    let unselected = DesktopEventCollection(items: items, today: today, primaryID: nil, query: "")
    precondition(unselected.favorite == nil)
    precondition(unselected.ordinary == [first, second, favorite])
    precondition(unselected.events == unselected.ordinary)
    let selected = DesktopEventCollection(items: items, today: today, primaryID: favorite.id, query: "")
    precondition(selected.favorite == favorite)
    precondition(selected.ordinary == [first, second])
    precondition(selected.events == [favorite, first, second])
    precondition(selected.events.filter { $0.id == favorite.id }.count == 1)
    for invalidID in [expired.id, UUID()] {
        let invalid = DesktopEventCollection(items: items, today: today, primaryID: invalidID, query: "")
        precondition(invalid == unselected)
    }
    let matchingTitle = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "  пОеЗдКа\n"
    )
    precondition(matchingTitle.favorite == nil && matchingTitle.events == [second])
    let matchingNote = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "ДОКУМЕНТЫ"
    )
    precondition(matchingNote.events == [favorite, first])
    let matchingFavorite = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "  оТПУСК\n"
    )
    precondition(matchingFavorite.favorite == favorite)
    precondition(matchingFavorite.events == [favorite] && matchingFavorite.ordinary.isEmpty)
    let nonmatchingFavorite = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "Поездка"
    )
    precondition(nonmatchingFavorite.favorite == nil && nonmatchingFavorite.events == [second])
    let matchingUnfavorited = DesktopEventCollection(items: items, today: today, primaryID: nil, query: "Отпуск")
    precondition(matchingUnfavorited.favorite == nil && matchingUnfavorited.ordinary == [favorite])
    precondition(DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "Не найдено"
    ).events.isEmpty)
    precondition(DesktopEventCollection(
        items: items, today: tomorrow, primaryID: nil, query: " \n"
    ).events == [favorite])
    precondition(desktopSelection(current: second.id, available: selected.events.map(\.id)) == second.id)
    precondition(desktopSelection(current: nil, available: selected.events.map(\.id)) == favorite.id)
    precondition(desktopSelection(current: UUID(), available: selected.events.map(\.id)) == favorite.id)
    precondition(desktopSelection(current: favorite.id, available: matchingTitle.events.map(\.id)) == second.id)
    precondition(desktopSelection(current: second.id, available: []) == nil)
    precondition(desktopMinimumPaneWidth(contentWidth: 960) == 320)
    precondition(desktopMinimumPaneWidth(contentWidth: 1_201) == 400)
    precondition(desktopMinimumPaneWidth(contentWidth: 0) == 320)
    precondition(desktopMinimumPaneWidth(contentWidth: -20) == 320)
    precondition(DesktopEventViewMode.allCases == [.collection, .feed])
    precondition(DesktopEventViewMode.collection.title == "Коллекция")
    precondition(DesktopEventViewMode.feed.title == "Лента")
    precondition(DesktopEventViewMode.collection.systemImage == "square.grid.2x2")
    precondition(DesktopEventViewMode.feed.systemImage == "list.bullet")
    testDesktopMonthGrouping()
    try testDesktopSubtaskSearch()
    try testDesktopMaterialSearch()
    try testSubtaskDropGeometry()
}

private func testSubtaskDropGeometry() throws {
    let first = try Subtask(text: "Same size")
    let second = try Subtask(text: "Wraps at the current width")
    let third = try Subtask(text: "Third row")
    let done = try Subtask(text: "Completed", isCompleted: true)
    let tasks = [first, second, third, done]
    let sizes = [first.id: CGSize(width: 280, height: 28), second.id: CGSize(width: 280, height: 43),
                 third.id: CGSize(width: 280, height: 28), done.id: CGSize(width: 280, height: 16)]
    let move = SubtaskReorder(subtasks: tasks, subtaskID: third.id)!
    let frames = subtaskRowFrames(tasks, sizes: sizes, spacing: 13)
    precondition(frames[second.id]?.minY == 41 && frames[third.id]?.minY == 97)
    func index(_ x: CGFloat, _ y: CGFloat, displayed: [Subtask] = tasks) -> Int? {
        subtaskDropIndex(move: move, displayed: displayed, frames: subtaskRowFrames(displayed, sizes: sizes, spacing: 13),
                         pointer: CGPoint(x: x, y: y))
    }
    precondition(index(45, 63) == 2)
    precondition(index(45, 60) == 1)
    let preview = move.reordered(to: 1)!
    precondition(preview == [first, third, second, done])
    precondition(index(45, 60, displayed: preview) == 1)
    precondition(index(45, 10, displayed: preview) == 0)
    precondition(index(45, 119, displayed: preview) == 2)
    precondition(index(45, 146, displayed: preview) == nil)
    precondition(index(-1, 60, displayed: preview) == nil)
    precondition(index(281, 60, displayed: preview) == nil)
    let longMove = SubtaskReorder(subtasks: tasks, subtaskID: second.id)!
    precondition(subtaskDropIndex(move: longMove, displayed: tasks, frames: frames, pointer: CGPoint(x: 45, y: 4)) == 0)
    let lifted = frames[second.id]!
    let boundary = frames[first.id]!.union(frames[third.id]!)
    precondition(subtaskLiftOffset(-1_000, origin: lifted, groupBounds: boundary) == -41)
    precondition(subtaskLiftOffset(1_000, origin: lifted, groupBounds: boundary) == 41)
    precondition(subtaskLiftOffset(6, origin: lifted, groupBounds: boundary) == 6)
    precondition(subtaskRowFrames(tasks, sizes: [:], spacing: 13).isEmpty)
}

private func testDesktopSubtaskSearch() throws {
    let today = Day(Date())
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    let completed = try Subtask(text: "Сохранить страховку в телефон", isCompleted: true)
    let active = try Subtask(text: "Продлить СТРАХОВКУ")
    var first = Countdown(title: "Первое", date: today, emoji: "", subtasks: [completed, active])
    let second = Countdown(title: "Второе", date: today, emoji: "", subtasks: [completed])
    let past = Countdown(title: "Прошлое", date: yesterday, emoji: "", subtasks: [completed], keepsAfterDate: true)
    let expired = Countdown(title: "Удаляемое", date: yesterday, emoji: "", subtasks: [active])
    let other = Countdown(title: "Пустое", date: today, emoji: "")
    let items = [first, past, second, expired, other]
    let search = DesktopEventSearch(" \nсТрАхОвКу  ")
    precondition(search.query == "сТрАхОвКу")
    let collection = DesktopEventCollection(items: items, today: today, primaryID: nil, query: search.query)
    precondition(collection.events == [first, second, past])
    precondition(collection.pastItems == [past])
    precondition(search.firstSubtask(in: first) == active)
    first.subtasks[1].isCompleted = true
    precondition(search.firstSubtask(in: first) == completed)
    precondition(DesktopEventCollection(items: [first], today: today, primaryID: nil, query: search.query).events == [first])
    precondition(DesktopEventCollection(items: items, today: today, primaryID: second.id, query: search.query)
        .events == [second, items[0], past])
    precondition(DesktopEventSearch("  \n").firstSubtask(in: first) == nil)
    precondition(DesktopEventSearch("Первое").firstSubtask(in: first) == nil)
    precondition(DesktopEventCollection(items: items, today: today, primaryID: nil, query: "без совпадений").events.isEmpty)
    let plain = DesktopEventCollection(items: items, today: today, primaryID: nil, query: " \n")
    precondition(plain.events == [items[0], second, other, past])
    precondition(desktopSelection(current: second.id, available: collection.events.map(\.id)) == second.id)

    let repeated = "👨‍👩‍👧‍👦 страховка, СТРАХОВКА и е\u{301}"
    let repeatedSearch = DesktopEventSearch("страховка")
    precondition(repeatedSearch.ranges(in: repeated).map { String(repeated[$0]) } == ["страховка", "СТРАХОВКА"])
    precondition(DesktopEventSearch("é").matches("e\u{301}"))
    let composedRange = DesktopEventSearch("é").ranges(in: "e\u{301}")
    precondition(composedRange.count == 1)
    precondition(DesktopEventSearch("👨‍👩‍👧‍👦").ranges(in: repeated).count == 1)
    precondition(DesktopEventSearch(" ").ranges(in: repeated).isEmpty)
    let longText = String(repeating: "👨‍👩‍👧‍👦 ", count: 20) + "страховка" + String(repeating: " дорога", count: 20)
    let snippet = repeatedSearch.snippet(in: longText)!.context
    precondition(snippet.hasPrefix("…") && snippet.hasSuffix("…") && snippet.contains("страховка"))
    precondition(snippet.count == 8 + "страховка".count + 24 + 2)
    precondition(repeatedSearch.snippet(in: "страховка")?.context == "страховка")
    precondition(DesktopEventSearch("страховку").snippet(in: "Продлить страховку")?.context == "Продлить страховку")
    precondition(repeatedSearch.snippet(in: "Без совпадения") == nil)

    let attributed = desktopSearchAttributedText(repeated, search: repeatedSearch, color: .red)
    precondition(String(attributed.characters) == repeated)
    precondition(attributed.runs.filter { $0.foregroundColor == .red }.count == 2)
    precondition(attributed.runs.allSatisfy { $0.font == nil && $0.kern == nil && $0.tracking == nil })
    let plainText = desktopSearchAttributedText(repeated, search: DesktopEventSearch(""), color: .red)
    precondition(plainText.runs.allSatisfy { $0.foregroundColor == nil && $0.font == nil })
}

private func testDesktopMaterialSearch() throws {
    let today = Day(Date())
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    let firstFile = try EventAttachment(name: "Билеты.pdf", byteCount: 42)
    let secondFile = try EventAttachment(name: "Билеты обратно.pdf", byteCount: 42)
    let namedLink = EventLink(name: "Схема вокзала", address: "https://rail.example/путешествие/схема-выходов")
    let unnamedLink = EventLink(address: "https://hotel.example/check-in")
    let trip = Countdown(title: "Поездка", date: today, emoji: "", attachments: [firstFile, secondFile], links: [namedLink])
    let past = Countdown(title: "Встреча", date: yesterday, emoji: "", keepsAfterDate: true,
                         attachments: [secondFile], links: [unnamedLink])
    let expired = Countdown(title: "Старое событие", date: yesterday, emoji: "", links: [namedLink, unnamedLink])
    let task = try Subtask(text: "Билеты распечатаны", isCompleted: true)
    let mixed = Countdown(title: "Дела", date: today, emoji: "", subtasks: [task], attachments: [firstFile],
                          links: [EventLink(name: "Билеты", address: "https://rail.example/tickets")])
    let items = [past, trip, expired, mixed]
    func results(_ query: String) -> [Countdown] {
        DesktopEventCollection(items: items, today: today, primaryID: trip.id, query: query).events
    }

    let files = DesktopEventSearch(" \nБиЛеТы  ")
    precondition(results(files.query) == [trip, mixed, past])
    precondition(files.cardMatch(in: trip)?.text == firstFile.name)
    precondition(files.cardMatch(in: mixed)?.text == task.text)
    precondition(results(".PDF") == [trip, mixed, past])
    let name = DesktopEventSearch("СХЕМА")
    precondition(results(name.query) == [trip])
    precondition(name.cardMatch(in: trip)?.text == namedLink.name)
    let path = DesktopEventSearch("выходов")
    precondition(results(path.query) == [trip])
    precondition(path.cardMatch(in: trip)?.text == namedLink.address)
    precondition(results("HOTEL.EXAMPLE") == [past])
    precondition(DesktopEventSearch("check-in").cardMatch(in: past)?.text == unnamedLink.address)
    precondition(results("не найдено").isEmpty)
    precondition(results(" \n") == [trip, mixed, past])
    precondition(DesktopEventSearch(" ").cardMatch(in: trip) == nil)

    let control = DesktopEventSearch("контроль")
    for separator in ["\n", "\r\n", "\u{2028}"] {
        let attachment = try EventAttachment(name: "Маршрут\(separator)КОНТРОЛЬ.txt", byteCount: 42)
        let event = Countdown(title: "Поездка", date: today, emoji: "", attachments: [attachment])
        let match = control.cardMatch(in: event)!
        let snippet = control.snippet(in: match.text)!
        precondition(match.text == attachment.name)
        let shown = desktopSearchAttributedText(snippet.context, search: control, color: .red, singleLine: true)
        precondition(String(shown.characters) == "Маршрут КОНТРОЛЬ.txt")
        precondition(snippet.matchingText == "КОНТРОЛЬ")
    }
    let wideAddress = "https://rail.example/" + String(repeating: "W", count: 120) + "/PLATFORM-MAP?section=1"
    let wideSnippet = DesktopEventSearch("platform-map").snippet(in: wideAddress)!
    precondition(wideSnippet.context.hasPrefix("…WWWWWWW/PLATFORM-MAP"))
    precondition(wideSnippet.matchingText == "PLATFORM-MAP")

    let filename = "A\nB A B.txt"
    for (query, expected) in [("A B", ["A B ", "A B", ".txt"]), ("A\nB", ["A B", " A B.txt"])] {
        let search = DesktopEventSearch(query)
        let snippet = search.snippet(in: filename)!
        let shown = desktopSearchAttributedText(snippet.context, search: search, color: .red, singleLine: true)
        precondition(String(shown.characters) == "A B A B.txt")
        precondition(shown.runs.map { String(shown[$0.range].characters) } == expected)
        let highlighted = shown.runs.filter { $0.foregroundColor == .red }.map { String(shown[$0.range].characters) }
        precondition(highlighted == ["A B"])
    }
}

private func testDesktopMonthGrouping() {
    func date(year: Int, month: Int, day: Int) -> Day {
        Day(DateComponents(calendar: Day.calendar, year: year, month: month, day: day).date!)
    }
    let today = date(year: 2026, month: 10, day: 23)
    let first = Countdown(title: "Первое", date: today, emoji: "")
    let equalDate = Countdown(title: "Второе", note: "Точное совпадение", date: today, emoji: "")
    let lastOctober = Countdown(title: "В конце месяца", date: date(year: 2026, month: 10, day: 31), emoji: "")
    let favorite = Countdown(title: "Избранное", date: date(year: 2026, month: 11, day: 1), emoji: "")
    let december = Countdown(title: "Конец года", date: date(year: 2026, month: 12, day: 31), emoji: "")
    let january = Countdown(title: "Новый год", date: date(year: 2027, month: 1, day: 1), emoji: "")
    let nextOctober = Countdown(title: "Ещё один октябрь", date: date(year: 2027, month: 10, day: 23), emoji: "")
    let expired = Countdown(title: "Прошлое", date: date(year: 2026, month: 9, day: 30), emoji: "")
    let items = [january, first, nextOctober, expired, favorite, lastOctober, equalDate, december]
    let collection = DesktopEventCollection(items: items, today: today, primaryID: favorite.id, query: "")
    let sections = collection.monthSections
    precondition(sections.map(\.title) == ["Октябрь 2026", "Декабрь 2026", "Январь 2027", "Октябрь 2027"])
    precondition(sections.map(\.id) == [2026 * 12 + 10, 2026 * 12 + 12, 2027 * 12 + 1, 2027 * 12 + 10])
    precondition(Set(sections.map(\.id)).count == sections.count)
    precondition(sections.allSatisfy { !$0.items.isEmpty })
    precondition(sections.flatMap(\.items) == collection.ordinary)
    precondition(sections[0].items == [first, equalDate, lastOctober])
    precondition(sections[1].items == [december] && sections[2].items == [january])
    precondition(!sections.flatMap(\.items).contains { $0.id == favorite.id })
    let unselected = DesktopEventCollection(items: items, today: today, primaryID: nil, query: "")
    precondition(unselected.monthSections.map(\.title) == [
        "Октябрь 2026", "Ноябрь 2026", "Декабрь 2026", "Январь 2027", "Октябрь 2027"
    ])
    precondition(unselected.monthSections[1].items == [favorite])
    let searched = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "точное СОВПАДЕНИЕ"
    )
    precondition(searched.monthSections.count == 1)
    precondition(searched.monthSections[0].items == [equalDate])
    precondition(searched.monthSections[0].id == sections[0].id)
    precondition(searched.monthSections[0].title == sections[0].title)
    let favoriteOnly = DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "Избранное"
    )
    precondition(favoriteOnly.favorite == favorite && favoriteOnly.monthSections.isEmpty)
    precondition(DesktopEventCollection(
        items: items, today: today, primaryID: favorite.id, query: "Нет результатов"
    ).monthSections.isEmpty)
    precondition(DesktopEventCollection(
        items: [], today: today, primaryID: nil, query: ""
    ).monthSections.isEmpty)
}

@MainActor
func testDesktopEditorOwnership() {
    testSubtaskTransferOwnership()
    testSubtaskTransferReconciliation()
    let session = EventEditorSession()
    precondition(!session.hasActiveEditor && !session.isPresented && !session.desktopIsPresented)
    precondition(session.beginPanelEditor())
    precondition(session.hasActiveEditor && session.isPresented && !session.desktopIsPresented)
    precondition(!session.beginPanelEditor() && !session.beginDesktopEditor())
    session.endDesktopEditor()
    precondition(session.isPresented)
    session.isPresented = false
    precondition(!session.hasActiveEditor)
    precondition(session.beginDesktopEditor())
    precondition(session.hasActiveEditor && session.desktopIsPresented && !session.isPresented)
    precondition(!session.beginDesktopEditor() && !session.beginPanelEditor())
    session.isPresented = true
    precondition(session.desktopIsPresented && !session.isPresented)
    session.isPresented = false
    session.endPanelEditor()
    precondition(session.desktopIsPresented)
    var installations = 0
    let updates = ApplicationUpdates(info: [:], enabled: false) {
        updateRestartBlockReason(
            editorIsPresented: session.hasActiveEditor, persistenceIsBusy: false, timerIsRunning: false
        )
    }
    precondition(updates.postponeInstallation { installations += 1 })
    precondition(updates.isInstallationDeferred && !updates.resumeDeferredInstallation())
    session.endDesktopEditor()
    precondition(!session.hasActiveEditor && !session.desktopIsPresented)
    session.isPresented = true
    precondition(session.isPresented && !updates.resumeDeferredInstallation())
    session.endPanelEditor()
    precondition(updates.resumeDeferredInstallation() && installations == 1)
    precondition(!updates.resumeDeferredInstallation())
    precondition(session.beginDesktopEditor())
    precondition(updates.shouldCancelUpdateTermination)
    session.endDesktopEditor()
    precondition(!updates.shouldCancelUpdateTermination)
    session.endDesktopEditor()
    precondition(!session.hasActiveEditor)
}

@MainActor
private func testSubtaskTransferOwnership() {
    let today = Day(Date())
    let tomorrow = Day(Day.calendar.date(byAdding: .day, value: 1, to: today.date())!)
    let session = EventEditorSession()
    let eventID = UUID()
    let subtaskID = UUID()
    let targetID = UUID()
    precondition(session.beginPanelEditor())
    precondition(!session.beginSubtaskTransfer(eventID: eventID, subtaskID: subtaskID,
                                              surface: .desktop, date: tomorrow))
    session.endPanelEditor()
    precondition(session.beginDesktopEditor())
    precondition(!session.beginSubtaskTransfer(eventID: eventID, subtaskID: subtaskID,
                                              surface: .panel, date: tomorrow))
    session.endDesktopEditor()

    for surface in [EventEditorSession.Surface.panel, .desktop] {
        precondition(session.beginSubtaskTransfer(eventID: eventID, subtaskID: subtaskID,
                                                 surface: surface, date: tomorrow))
        precondition(session.hasActiveEditor && !session.isPresented && !session.desktopIsPresented)
        precondition(session.surface == nil && session.subtaskTransfer?.surface == surface)
        precondition(session.subtaskTransfer?.eventID == eventID)
        precondition(session.subtaskTransfer?.subtaskID == subtaskID)
        precondition(session.subtaskTransfer?.date == tomorrow && session.subtaskTransfer?.targetEventID == nil)
        precondition(!session.beginPanelEditor() && !session.beginDesktopEditor())
        precondition(!session.beginSubtaskTransfer(eventID: UUID(), subtaskID: UUID(),
                                                  surface: .panel, date: today))
        precondition(!session.beginSubtaskTransfer(eventID: UUID(), subtaskID: UUID(),
                                                  surface: .desktop, date: today))
        session.endPanelEditor()
        session.endDesktopEditor()
        session.isPresented = false
        precondition(session.subtaskTransfer?.surface == surface)
        session.isPresented = true
        precondition(!session.isPresented && session.subtaskTransfer?.surface == surface)
        session.selectSubtaskTransferTarget(targetID)
        precondition(session.subtaskTransfer?.targetEventID == targetID)
        session.updateSubtaskTransfer(date: today)
        precondition(session.subtaskTransfer?.date == today && session.subtaskTransfer?.targetEventID == nil)
        session.selectSubtaskTransferTarget(targetID)
        session.selectSubtaskTransferTarget(nil)
        precondition(session.subtaskTransfer?.targetEventID == nil)
        precondition(updateRestartBlockReason(editorIsPresented: session.hasActiveEditor,
                                             persistenceIsBusy: false, timerIsRunning: false) != nil)
        testSubtaskTransferSaveReservation(session, today: today, tomorrow: tomorrow)
        session.endSubtaskTransfer()
        precondition(!session.hasActiveEditor && session.subtaskTransfer == nil && !session.subtaskTransferIsSaving)
    }
    session.updateSubtaskTransfer(date: tomorrow)
    session.selectSubtaskTransferTarget(targetID)
    session.endSubtaskTransfer()
    precondition(!session.hasActiveEditor)
    precondition(session.beginPanelEditor())
    session.endSubtaskTransfer()
    precondition(session.isPresented)
    session.endPanelEditor()
}

@MainActor
private func testSubtaskTransferSaveReservation(_ session: EventEditorSession, today: Day, tomorrow: Day) {
    let expectedDraft = session.subtaskTransfer!
    var staleDraft = expectedDraft
    staleDraft.date = tomorrow
    precondition(!session.beginSubtaskTransferSave(staleDraft) && !session.subtaskTransferIsSaving)
    precondition(session.beginSubtaskTransferSave(expectedDraft))
    precondition(session.subtaskTransferIsSaving && session.hasActiveEditor)
    precondition(!session.beginSubtaskTransferSave(expectedDraft))
    session.endSubtaskTransfer()
    session.updateSubtaskTransfer(date: tomorrow)
    session.selectSubtaskTransferTarget(UUID())
    session.reconcileSubtaskTransfer(items: [], today: today)
    precondition(session.subtaskTransfer == expectedDraft && session.subtaskTransferIsSaving)
    precondition(!session.beginSubtaskTransfer(eventID: UUID(), subtaskID: UUID(),
                                              surface: .panel, date: tomorrow))
    precondition(!session.beginSubtaskTransfer(eventID: UUID(), subtaskID: UUID(),
                                              surface: .desktop, date: tomorrow))
    precondition(!session.beginPanelEditor() && !session.beginDesktopEditor())
    session.finishSubtaskTransferSave(staleDraft, succeeded: true)
    precondition(session.subtaskTransfer == expectedDraft && session.subtaskTransferIsSaving)
    session.finishSubtaskTransferSave(expectedDraft, succeeded: false)
    precondition(session.subtaskTransfer == expectedDraft && !session.subtaskTransferIsSaving)
    precondition(session.beginSubtaskTransferSave(expectedDraft))
    session.finishSubtaskTransferSave(expectedDraft, succeeded: true)
    precondition(session.subtaskTransfer == nil && !session.subtaskTransferIsSaving && !session.hasActiveEditor)
    precondition(!session.beginSubtaskTransferSave(expectedDraft))
    session.finishSubtaskTransferSave(expectedDraft, succeeded: false)
    precondition(session.subtaskTransfer == nil && !session.subtaskTransferIsSaving)
}

@MainActor
private func testSubtaskTransferReconciliation() {
    let today = Day(Date())
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    let tomorrow = Day(Day.calendar.date(byAdding: .day, value: 1, to: today.date())!)
    let subtask = try! Subtask(text: "Переносимый пункт")
    let neighbor = try! Subtask(text: "Другой пункт")
    let original = Countdown(title: "Источник", date: today, emoji: "", subtasks: [subtask, neighbor])
    let session = EventEditorSession()
    precondition(session.beginSubtaskTransfer(eventID: original.id, subtaskID: subtask.id,
                                             surface: .panel, date: tomorrow))
    session.selectSubtaskTransferTarget(UUID())
    let draft = session.subtaskTransfer
    session.reconcileSubtaskTransfer(items: [original], today: today)
    precondition(session.subtaskTransfer == draft)
    var otherCompleted = original
    otherCompleted.subtasks[1].isCompleted = true
    session.reconcileSubtaskTransfer(items: [otherCompleted], today: today)
    precondition(session.subtaskTransfer == draft)
    session.reconcileSubtaskTransfer(items: [original], today: tomorrow)
    precondition(session.subtaskTransfer == nil && !session.hasActiveEditor)

    var retained = original
    retained.date = yesterday
    retained.keepsAfterDate = true
    precondition(session.beginSubtaskTransfer(eventID: retained.id, subtaskID: subtask.id,
                                             surface: .desktop, date: tomorrow))
    let retainedDraft = session.subtaskTransfer
    session.reconcileSubtaskTransfer(items: [retained], today: today)
    precondition(session.subtaskTransfer == retainedDraft)
    session.endSubtaskTransfer()

    var completed = original
    completed.subtasks[0].isCompleted = true
    var removed = original
    removed.subtasks = [neighbor]
    var expired = original
    expired.date = yesterday
    for unavailableItems in [[], [completed], [removed], [expired]] {
        precondition(session.beginSubtaskTransfer(eventID: original.id, subtaskID: subtask.id,
                                                 surface: .panel, date: tomorrow))
        session.reconcileSubtaskTransfer(items: unavailableItems, today: today)
        precondition(session.subtaskTransfer == nil && !session.hasActiveEditor)
    }
    precondition(session.beginDesktopEditor())
    session.reconcileSubtaskTransfer(items: [], today: today)
    precondition(session.desktopIsPresented)
    session.endDesktopEditor()
}
