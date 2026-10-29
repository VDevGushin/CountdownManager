import Foundation
import CountdownCore
import CountdownManagerUI

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
    precondition(matchingNote.events == [first])
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
    precondition(desktopSelection(current: second.id, available: selected.events) == second.id)
    precondition(desktopSelection(current: nil, available: selected.events) == favorite.id)
    precondition(desktopSelection(current: UUID(), available: selected.events) == favorite.id)
    precondition(desktopSelection(current: favorite.id, available: matchingTitle.events) == second.id)
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
