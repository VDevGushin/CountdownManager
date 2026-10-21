import CountdownCore
import CountdownManagerUI
import Foundation

func testMenuBarIdentity() throws {
    let today = menuDay(2026, 10, 5)
    let nearest = Countdown(title: "Private today title", date: today, emoji: "🎂")
    let later = Countdown(title: "Private future title", date: menuDay(2026, 10, 8), emoji: "")
    let expired = Countdown(title: "Expired favorite", date: menuDay(2026, 10, 4), emoji: "🚀")
    var data = CountdownData()
    data.items = [later, nearest, expired]
    let before = data
    let noFavorite = statusBarPresentation(data: data, today: today)
    precondition(noFavorite == StatusBarPresentation(
        title: "", icon: .mars, toolTip: "Countdown Manager · нет избранного"
    ), "No explicit favorite must produce Mars without a title")
    precondition(activeCountdowns(in: data, today: today).first?.id == nearest.id)
    precondition(data == before, "Presentation must not select or mutate a favorite")

    data.primaryID = UUID()
    precondition(statusBarPresentation(data: data, today: today) == noFavorite)
    data.primaryID = expired.id
    precondition(statusBarPresentation(data: data, today: today) == noFavorite,
                 "An expired favorite must never fall back to a different event in the menu")
    data.primaryID = later.id
    let calendar = statusBarPresentation(data: data, today: today)
    precondition(calendar.title == "3 дня" && calendar.icon == .calendar,
                 "An iconless explicit favorite must produce K1 and its calendar-day count")
    precondition(calendar.toolTip == "Countdown Manager · 3 дня")
    data.items[0].emoji = "📅"
    precondition(statusBarPresentation(data: data, today: today) == calendar,
                 "Legacy calendar emoji maps to K1 without rewriting the stored value")
    precondition(data.items[0].emoji == "📅")
    data.items[0].emoji = "👨‍👩‍👧‍👦"
    let custom = statusBarPresentation(data: data, today: today)
    precondition(custom.title == "👨‍👩‍👧‍👦 3 дня" && custom.icon == nil && custom.toolTip == custom.title,
                 "A custom emoji must remain in the title without an additional template image")
    precondition(!custom.title.contains(later.title))
    var deletedFavorite = data
    deletedFavorite.delete(later.id, today: today)
    precondition(statusBarPresentation(data: deletedFavorite, today: today).icon == .mars)
    precondition(statusBarTitle(data: deletedFavorite, today: today).isEmpty)
    precondition(activeCountdowns(in: deletedFavorite, today: today).first?.id == nearest.id)

    data.primaryID = nearest.id
    precondition(statusBarPresentation(data: data, today: today).title == "🎂 Сегодня")
    data.items[1].emoji = ""
    precondition(statusBarPresentation(data: data, today: today).title == "Сегодня")
    precondition(statusBarPresentation(data: data, today: today).icon == .calendar)
    let empty = statusBarPresentation(data: CountdownData(), today: today)
    precondition(empty.title.isEmpty && empty.icon == .mars && empty.toolTip == "Countdown Manager · нет событий")

    for (from, to) in [
        (menuDay(2026, 12, 31), menuDay(2027, 1, 1)),
        (menuDay(2028, 2, 28), menuDay(2028, 2, 29)),
        (menuDay(2028, 2, 29), menuDay(2028, 3, 1))
    ] {
        var boundary = CountdownData()
        let event = Countdown(title: "Boundary", date: to, emoji: "")
        boundary.items = [event]
        boundary.primaryID = event.id
        precondition(statusBarPresentation(data: boundary, today: from).title == "Завтра",
                     "Tomorrow must follow civil dates across year and leap-day boundaries")
        precondition(statusBarPresentation(data: boundary, today: to).title == "Сегодня")
        precondition(countdownLabel(1) == "1 день", "Tomorrow is a menu-specific label")
        boundary.items[0].emoji = "🚀"
        precondition(statusBarPresentation(data: boundary, today: from).title == "🚀 Завтра")
    }
}

@MainActor
func testMenuBarIdentityTransitions(in directory: URL) async throws {
    let suite = "CountdownManagerMenuIdentity.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let initialDay = Day(Date())
    var clock = initialDay.date()
    let file = directory.appendingPathComponent("events.json")
    let store = Store(fileURL: file, disclosureDefaults: defaults, now: { clock },
                      loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    while store.isLoading { await Task.yield() }
    precondition(statusBarPresentation(data: store.data, today: Day(clock)).icon == .mars && statusBarTitle(data: store.data, today: Day(clock)).isEmpty)
    let nearest = Countdown(title: "Nearest today", date: Day(clock), emoji: "☀️")
    var favorite = Countdown(title: "Tomorrow favorite", date: menuFutureDay(1, from: initialDay), emoji: "")
    let later = Countdown(title: "Still active", date: menuFutureDay(4, from: initialDay), emoji: "✈️")
    let savedNearest = await store.save(nearest, primary: false)
    let savedLater = await store.save(later, primary: false)
    let savedFavorite = await store.save(favorite, primary: true)
    precondition(savedNearest && savedLater && savedFavorite)
    precondition(activeCountdowns(in: store.data, today: Day(clock)).first?.id == favorite.id && statusBarPresentation(data: store.data, today: Day(clock)).icon == .calendar)
    precondition(statusBarTitle(data: store.data, today: Day(clock)) == "Завтра")
    favorite.emoji = "🎉"
    let changed = await store.save(favorite, primary: true, requireExisting: true)
    precondition(changed && statusBarPresentation(data: store.data, today: Day(clock)).icon == nil && statusBarTitle(data: store.data, today: Day(clock)) == "🎉 Завтра")
    await store.clearPrimary()
    precondition(activeCountdowns(in: store.data, today: Day(clock)).first?.id == nearest.id && statusBarTitle(data: store.data, today: Day(clock)).isEmpty && statusBarPresentation(data: store.data, today: Day(clock)).icon == .mars)
    let restoredData = await menuRestoredData(file: file, defaults: defaults, now: clock)
    precondition(restoredData.primaryID == nil)
    precondition(activeCountdowns(in: restoredData, today: initialDay).first?.id == nearest.id)
    precondition(statusBarTitle(data: restoredData, today: initialDay).isEmpty)
    precondition(statusBarPresentation(data: restoredData, today: initialDay).icon == .mars)
    let selected = await store.save(favorite, primary: true, requireExisting: true)
    precondition(selected)
    var expiring = favorite
    expiring.date = initialDay
    expiring.emoji = ""
    let savedExpiring = await store.save(expiring, primary: true)
    precondition(savedExpiring && statusBarTitle(data: store.data, today: Day(clock)) == "Сегодня" && statusBarPresentation(data: store.data, today: Day(clock)).icon == .calendar)
    clock = menuFutureDay(1, from: initialDay).date()
    store.refresh()
    while store.hasPendingPersistence { await Task.yield() }
    precondition(store.data.primaryID == nil && activeCountdowns(in: store.data, today: Day(clock)).first?.id == later.id)
    precondition(statusBarPresentation(data: store.data, today: Day(clock)).icon == .mars && statusBarTitle(data: store.data, today: Day(clock)).isEmpty)
    let disk = try await CountdownRepository(fileURL: file).load()
    precondition(disk == store.data && disk.items == [later])
}

private func menuDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    Day(Day.calendar.date(from: DateComponents(year: year, month: month, day: day))!)
}

private func menuFutureDay(_ offset: Int, from today: Day) -> Day {
    Day(Day.calendar.date(byAdding: .day, value: offset, to: today.date())!)
}

@MainActor
private func menuRestoredData(file: URL, defaults: UserDefaults, now: Date) async -> CountdownData {
    let restored = Store(fileURL: file, disclosureDefaults: defaults, now: { now },
                         loginItemManagementIsAvailable: false, diagnosticRecord: { _ in })
    while restored.isLoading { await Task.yield() }
    return restored.data
}
