import CountdownCore
import Foundation

struct Generator {
    var state: UInt64 = 0xC0A17D0A20261116
    mutating func next(_ limit: Int) -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 24) % UInt64(limit))
    }
}

@main
struct TransferFuzz {
    static func main() throws {
        var random = Generator()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var successes = 0
        var rejections = 0
        let fixtureDates = [(2026, 11, 16), (2026, 12, 31), (2028, 2, 28), (2028, 2, 29), (2027, 3, 28)]
        for index in 0..<12000 {
            let parts = fixtureDates[index % fixtureDates.count]
            let baseDate = calendar.date(from: DateComponents(year: parts.0, month: parts.1, day: parts.2, hour: 12))!
            let today = Day(baseDate, calendar: calendar)
            var before = CountdownData()
            for eventIndex in 0..<4 {
                let date = calendar.date(byAdding: .day, value: random.next(7), to: baseDate)!
                var subtasks: [Subtask] = []
                for taskIndex in 0..<random.next(11) {
                    subtasks.append(try Subtask(text: "Дело \(eventIndex)·\(taskIndex) 🙂", isCompleted: random.next(4) == 0))
                }
                before.items.append(Countdown(title: "Событие \(eventIndex)", note: "Сохранить заметку",
                                              date: Day(date, calendar: calendar), emoji: "", subtasks: subtasks,
                                              keepsAfterDate: random.next(2) == 0))
            }
            if random.next(2) == 0 { before.primaryID = before.items[random.next(4)].id }
            let source = before.items[random.next(4)]
            let target = before.items[random.next(4)]
            let subtask = source.subtasks.isEmpty ? try Subtask(text: "Несуществующее дело")
                : source.subtasks[random.next(source.subtasks.count)]
            let createsDay = random.next(3) == 0
            let dateOffset = createsDay ? random.next(10) - 1 : 0
            var destinationDay = createsDay
                ? Day(calendar.date(byAdding: .day, value: dateOffset, to: baseDate)!, calendar: calendar) : target.date
            if random.next(13) == 0 { destinationDay = today }
            let expectedSuccess = source.subtasks.contains(subtask) && !subtask.isCompleted
                && destinationDay >= today
                && (createsDay ? !before.items.contains { $0.date == destinationDay }
                    : source.id != target.id && target.date == destinationDay && target.subtasks.count < 10)
            var after = before
            do {
                let destination = try after.transferSubtask(from: source.id, subtaskID: subtask.id,
                                                           to: createsDay ? nil : target.id,
                                                           on: destinationDay, today: today)
                precondition(expectedSuccess, "Unexpected acceptance in case \(index)")
                precondition(!subtask.isCompleted && source.subtasks.contains(subtask))
                precondition(destinationDay >= today && destination.subtasks.count <= 10)
                var expected = before
                let sourceIndex = expected.items.firstIndex { $0.id == source.id }!
                expected.items[sourceIndex].subtasks.removeAll { $0.id == subtask.id }
                if createsDay {
                    precondition(!before.items.contains { $0.date == destinationDay })
                    let newDay = Countdown(id: destination.id, title: automaticEventTitle(for: destinationDay),
                                           date: destinationDay, emoji: "", subtasks: [subtask], showsWeather: true,
                                           usesAutomaticTitle: true, isDay: true)
                    precondition(newDay == destination)
                    expected.items.append(newDay)
                } else {
                    precondition(source.id != target.id && target.date == destinationDay)
                    let targetIndex = expected.items.firstIndex { $0.id == target.id }!
                    expected.items[targetIndex].subtasks.append(subtask)
                }
                precondition(after == expected, "Transfer changed more than the chosen task in case \(index)")
                let ids = after.items.flatMap { $0.subtasks.map(\.id) }
                precondition(Set(ids).count == ids.count)
                let decoded = try JSONDecoder().decode(CountdownData.self, from: JSONEncoder().encode(after))
                precondition(decoded == after)
                successes += 1
            } catch {
                precondition(!expectedSuccess, "Unexpected rejection in case \(index): \(error)")
                precondition(after == before, "Rejected transfer changed data in case \(index)")
                rejections += 1
            }
        }
        precondition(successes > 1000 && rejections > 1000)
        print("PASS randomized transfer properties: 12000 fixtures, \(successes) successful, \(rejections) rejected; exact snapshots, UUID conservation, limits and JSON round-trip")
    }
}
