import Foundation
import CountdownCore
import CountdownManagerUI

func testWeatherEditorDraftBoundaries() throws {
    let day = weatherDraftDay(2027, 5, 3)
    let nextDay = weatherDraftDay(2027, 5, 4)
    var ordinary = EventEditorDraft(item: nil)
    precondition(!ordinary.showsWeather)
    ordinary.setTitle("Понедельник")
    ordinary.updateDayTitle(for: nextDay)
    precondition(!ordinary.showsWeather, "Weekday-looking titles must not opt into weather")

    var newDay = EventEditorDraft(day: day)
    precondition(newDay.showsWeather && newDay.title == russianWeekdayTitle(day))
    newDay.updateDayTitle(for: nextDay)
    precondition(newDay.showsWeather && newDay.title == russianWeekdayTitle(nextDay))
    newDay.setTitle("Outdoor plan")
    newDay.updateDayTitle(for: day)
    precondition(newDay.showsWeather && newDay.title == "Outdoor plan")
    _ = newDay.addSubtask()
    newDay.subtasks[0].text = "Bring a coat"
    newDay.subtasks[0].isCompleted = true
    precondition(newDay.showsWeather)
    let newEvent = newDay.countdown(id: UUID(), date: nextDay)
    precondition(newEvent.showsWeather && newEvent.subtasks == newDay.subtasks)

    var disabledDay = EventEditorDraft(day: day)
    disabledDay.showsWeather = false
    disabledDay.updateDayTitle(for: nextDay)
    disabledDay.setTitle("Weather disabled")
    _ = disabledDay.addSubtask()
    precondition(!disabledDay.showsWeather && !disabledDay.countdown(id: UUID(), date: nextDay).showsWeather)

    let existing = Countdown(title: "Day", note: "Preserved note", date: day, emoji: "", showsWeather: true)
    var data = CountdownData()
    try data.save(existing, primary: false, today: day)
    let saved = data
    var cancelledDraft = EventEditorDraft(item: existing)
    precondition(cancelledDraft.showsWeather)
    cancelledDraft.showsWeather = false
    cancelledDraft.setTitle("Cancelled change")
    precondition(!cancelledDraft.countdown(id: existing.id, date: nextDay).showsWeather)
    precondition(data == saved, "Draft-only edits must not alter saved events")
    let reopenedAfterCancel = EventEditorDraft(item: data.items[0])
    precondition(reopenedAfterCancel.showsWeather && reopenedAfterCancel.title == existing.title)

    var committedDraft = reopenedAfterCancel
    committedDraft.showsWeather = false
    committedDraft.setTitle("Saved change")
    try data.save(committedDraft.countdown(id: existing.id, date: nextDay), primary: false, today: day)
    precondition(!data.items[0].showsWeather && data.items[0].title == "Saved change")
    var enabledDraft = EventEditorDraft(item: data.items[0])
    precondition(!enabledDraft.showsWeather)
    enabledDraft.showsWeather = true
    enabledDraft.note = "Updated note"
    enabledDraft.clearEmoji()
    try data.save(enabledDraft.countdown(id: existing.id, date: nextDay), primary: false, today: day)
    let restored = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(data))
    precondition(restored.items[0].showsWeather && EventEditorDraft(item: restored.items[0]).showsWeather)
    precondition(restored.items[0].id == existing.id && restored.items[0].note == "Updated note")
}

private func weatherDraftDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return Day(calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar)
}
