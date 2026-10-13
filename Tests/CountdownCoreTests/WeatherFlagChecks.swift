import Foundation
import CountdownCore

func testWeatherFlagPersistence() async throws {
    let legacyJSON = """
    {"items":[{"id":"28B1DD31-4671-4BD1-AB0D-3F6232967299","title":"Понедельник","date":{"year":2027,"month":5,"day":3},"emoji":""}]}
    """
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()
    let legacy = try decoder.decode(CountdownData.self, from: Data(legacyJSON.utf8))
    precondition(!legacy.items[0].showsWeather, "Legacy weekday titles must not opt into weather")
    let legacyEncoded = try JSONSerialization.jsonObject(with: encoder.encode(legacy)) as? [String: Any]
    let legacyItems = legacyEncoded?["items"] as? [[String: Any]]
    precondition(legacyItems?[0]["showsWeather"] == nil)

    let today = weatherFlagDay(2027, 5, 1)
    let future = weatherFlagDay(2027, 5, 3)
    let ordinary = Countdown(title: "Ordinary", date: future, emoji: "")
    precondition(!ordinary.showsWeather)
    let subtask = try Subtask(text: "Take an umbrella")
    let event = Countdown(title: "  Trip  ", date: future, emoji: "", subtasks: [subtask], showsWeather: true)
    var data = CountdownData()
    try data.save(event, primary: true, today: today)
    precondition(data.items[0].showsWeather && data.items[0].title == "Trip")
    let encodedEvent = try encoder.encode(data.items[0])
    let eventJSON = try JSONSerialization.jsonObject(with: encodedEvent) as? [String: Any]
    precondition(eventJSON?["showsWeather"] as? Bool == true)
    let roundTrip = try decoder.decode(CountdownData.self, from: encoder.encode(data))
    precondition(roundTrip == data)

    guard var invalid = eventJSON else { preconditionFailure("Expected encoded weather event object") }
    let invalidValues: [Any] = ["true", 1, NSNull()]
    for value in invalidValues {
        invalid["showsWeather"] = value
        let bytes = try JSONSerialization.data(withJSONObject: invalid)
        do {
            _ = try decoder.decode(Countdown.self, from: bytes)
            preconditionFailure("Non-Boolean weather flag must fail decoding")
        } catch is DecodingError {
            // Malformed metadata must not silently enable or disable weather.
        }
    }
    invalid["showsWeather"] = false
    let explicitFalse = try decoder.decode(Countdown.self, from: JSONSerialization.data(withJSONObject: invalid))
    precondition(!explicitFalse.showsWeather)

    try data.toggleSubtask(eventID: event.id, subtaskID: subtask.id, today: today)
    precondition(data.items[0].showsWeather && data.items[0].subtasks[0].isCompleted)
    try data.editSubtask(eventID: event.id, subtaskID: subtask.id, text: "Changed checklist", today: today)
    let addedID = try data.addSubtask(to: event.id, text: "Another task", today: today)
    try data.deleteSubtask(eventID: event.id, subtaskID: addedID, today: today)
    precondition(data.items[0].showsWeather)
    var edited = data.items[0]
    edited.title = "Renamed day"
    edited.date = weatherFlagDay(2027, 5, 4)
    try data.save(edited, primary: false, today: today)
    data.normalize(today: future)
    precondition(data.items[0].showsWeather && data.items[0].id == event.id)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("CountdownWeatherFlagChecks-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let repository = CountdownRepository(fileURL: directory.appendingPathComponent("countdowns.json"))
    let initialSave = try await repository.save(data, revision: 1)
    let initialLoad = try await repository.load()
    precondition(initialSave && initialLoad == data)
    edited = data.items[0]
    edited.showsWeather = false
    try data.save(edited, primary: false, today: future)
    let secondSave = try await repository.save(data, revision: 2)
    precondition(secondSave)
    let reopened = try await repository.load()
    precondition(reopened == data && !reopened.items[0].showsWeather)
}

private func weatherFlagDay(_ year: Int, _ month: Int, _ day: Int) -> Day {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return Day(calendar.date(from: DateComponents(year: year, month: month, day: day))!, calendar: calendar)
}
