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
